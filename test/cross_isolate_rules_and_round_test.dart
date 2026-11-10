import 'dart:io';

import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/game/game_runner.dart';
import 'package:basketball_manager/features/season/season_controller.dart';
import 'package:basketball_manager/features/season/season_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _config = GenerationConfig(seed: 20261028);

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  late League league;
  late Directory tempDir;

  setUpAll(() {
    league = const LeagueGenerator().generate(_config);
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ballgorithm_isolate_test_');
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('GameRules Value-Based Equality & Tamper Rejection', () {
    test('two separately constructed GameRules compare equal', () {
      final r1 = GameRules();
      final r2 = GameRules();

      expect(identical(r1, r2), isFalse);
      expect(r1 == r2, isTrue);
      expect(r1.matchesConfiguration(r2), isTrue);
      expect(r1.hashCode, r2.hashCode);
      expect(r1.matchesConfiguration(GameRules.standard), isTrue);
    });

    test('a changed gameplay-relevant scalar is rejected', () {
      final standard = GameRules.standard;
      final changedPeriod = GameRules(periods: 2);
      final changedClock = GameRules(shotClockSeconds: 14);
      final changedReset = GameRules(offensiveReboundResetSeconds: 12);
      final changedFoulOut = GameRules(foulOutLimit: 5);

      expect(standard == changedPeriod, isFalse);
      expect(standard.matchesConfiguration(changedPeriod), isFalse);

      expect(standard == changedClock, isFalse);
      expect(standard.matchesConfiguration(changedClock), isFalse);

      expect(standard == changedReset, isFalse);
      expect(standard.matchesConfiguration(changedReset), isFalse);

      expect(standard == changedFoulOut, isFalse);
      expect(standard.matchesConfiguration(changedFoulOut), isFalse);
    });

    test('a changed nested phase-duration value is rejected', () {
      final standard = GameRules.standard;

      // Tamper with one duration inside first phase bracket
      final tamperedDurations = [
        [5, 8, 12],
        [9, 13, 16],
        [14, 18, 22],
      ];
      final changedDurations = GameRules(phaseDurations: tamperedDurations);

      expect(standard == changedDurations, isFalse);
      expect(standard.matchesConfiguration(changedDurations), isFalse);

      // Tamper with phase weights
      final changedWeights = GameRules(phaseWeights: const [2000, 3000, 5000]);
      expect(standard == changedWeights, isFalse);
      expect(standard.matchesConfiguration(changedWeights), isFalse);
    });
  });

  group('M007-T04 Real Cross-Isolate Season Execution via runGame()', () {
    test(
      'production runGame() crossing isolate boundary passes rules validation and commits round',
      () async {
        final savePath = '${tempDir.path}/season_isolate.json';
        final storage1 = FileSeasonStorage(filePath: savePath);
        final controller1 = SeasonController(
          league: league,
          storage: storage1,
          gameRunner: runGame, // ACTUAL production isolate runner!
        );

        // 1. Initialize M007 season
        final userTeamId = league.teams.first.id;
        await controller1.startNewSeason(userTeamId);
        expect(controller1.hasActiveSeason, isTrue);

        // 2. Obtain user Round 1 fixture
        final state1 = controller1.state!;
        final userFixture = state1.nextUserFixture!;
        expect(userFixture.roundNumber, 1);

        final homeTeam = league.teams.firstWhere(
          (t) => t.id == userFixture.homeTeamId,
        );
        final awayTeam = league.teams.firstWhere(
          (t) => t.id == userFixture.awayTeamId,
        );
        final homeStrategy = FranchiseStrategy.defaultFor(homeTeam);
        final awayStrategy = FranchiseStrategy.defaultFor(awayTeam);

        // 3. Construct real scheduled GameRequest
        final request = GameRequest(
          gameId: userFixture.id,
          league: league,
          homeTeamId: userFixture.homeTeamId,
          awayTeamId: userFixture.awayTeamId,
          homeLineup: homeStrategy.startingLineup,
          awayLineup: awayStrategy.startingLineup,
          rotationPlan: RotationPlan(
            home: homeStrategy.teamPlan,
            away: awayStrategy.teamPlan,
          ),
          seed: userFixture.seed,
        );

        // 4. Run via ACTUAL runGame() across native isolate boundary
        final userResult = await runGame(request);

        // Mandatory check: prove cross-isolate object non-identity
        expect(identical(userResult.input.rules, GameRules.standard), isFalse);
        // But value-equality passes
        expect(
          userResult.input.rules.matchesConfiguration(GameRules.standard),
          isTrue,
        );

        // 5 & 6. Commit round through controller (simulating remaining 3 fixtures via isolate runner)
        await controller1.commitRoundWithUserResult(userResult);

        // 7. Assert all four fixtures are committed
        final completedRound = controller1.state!.schedule.roundAt(1);
        expect(completedRound.isCompleted, isTrue);
        for (final f in completedRound.fixtures) {
          expect(f.isCompleted, isTrue);
          expect(f.summary, isNotNull);
        }

        // 8. Assert advances to Round 2
        expect(controller1.state!.currentRoundNumber, 2);

        // 9. Assert standings contain 4 wins and 4 losses
        var wins = 0;
        var losses = 0;
        for (final s in controller1.state!.standings.table.values) {
          wins += s.wins;
          losses += s.losses;
        }
        expect(wins, 4);
        expect(losses, 4);

        // 10. Assert player statistics are consistent
        for (final p in homeTeam.players) {
          final stats = controller1.state!.playerStats[p.id.value]!;
          expect(stats.gamesPlayed, 1);
        }

        // 11 & 12. Dispose and reload in a new controller
        controller1.dispose();

        final storage2 = FileSeasonStorage(filePath: savePath);
        final controller2 = SeasonController(
          league: league,
          storage: storage2,
          gameRunner: runGame,
        );

        await controller2.loadSeason();
        expect(controller2.hasActiveSeason, isTrue);
        expect(controller2.state!.currentRoundNumber, 2);
        expect(controller2.state!.schedule.roundAt(1).isCompleted, isTrue);

        // Verify duplicate finalization is rejected
        await expectLater(
          () => controller2.commitRoundWithUserResult(userResult),
          throwsA(isA<ArgumentError>()),
        );

        controller2.dispose();
      },
    );

    testWidgets(
      'Result-screen confirmation: Continue Season disabled during finalization failure and enabled on success',
      (tester) async {
        _useTallSurface(tester);
        final failingStorage = InMemorySeasonStorage();
        final controller = SeasonController(
          league: league,
          storage: failingStorage,
          gameRunner: runGame,
        );

        await tester.pumpWidget(
          BasketballManagerApp(
            league: league,
            storage: failingStorage,
            seasonMode: true,
            gameRunner: runGame,
          ),
        );
        await tester.pumpAndSettle();

        // Start season
        await tester.tap(find.byKey(const ValueKey('start-season-button')));
        await tester.pumpAndSettle();

        // Inject storage write failure before starting the game
        failingStorage.shouldThrowOnWrite = true;

        // Play Next Game
        await tester.tap(find.byKey(const ValueKey('play-next-game')));
        for (var i = 0; i < 60; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
          if (find
              .byKey(const ValueKey('retry-finalization-button'))
              .evaluate()
              .isNotEmpty) {
            break;
          }
        }
        await tester.pump();
        // Game completed, but finalization threw due to storage failure
        expect(find.byKey(const ValueKey('game-success')), findsOneWidget);
        expect(find.textContaining('Failed to record round'), findsOneWidget);

        // "Continue Season" must be disabled
        final continueButtonFinder = find.byKey(
          const ValueKey('return-to-league'),
        );
        expect(continueButtonFinder, findsOneWidget);
        final outlinedButton = tester.widget<OutlinedButton>(
          continueButtonFinder,
        );
        expect(outlinedButton.onPressed, isNull); // DISABLED!

        // Retry button must be visible
        expect(
          find.byKey(const ValueKey('retry-finalization-button')),
          findsOneWidget,
        );

        // Fix storage failure and retry finalization
        failingStorage.shouldThrowOnWrite = false;
        await tester.tap(
          find.byKey(const ValueKey('retry-finalization-button')),
        );
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
          final btn = tester.widget<OutlinedButton>(continueButtonFinder);
          if (btn.onPressed != null) {
            break;
          }
        }
        await tester.pump();
        // Failure banner cleared and Continue Season is now enabled
        expect(
          find.byKey(const ValueKey('retry-finalization-button')),
          findsNothing,
        );
        final enabledButton = tester.widget<OutlinedButton>(
          continueButtonFinder,
        );
        expect(enabledButton.onPressed, isNotNull); // ENABLED!

        // Ensure visible and tap Continue Season
        await tester.ensureVisible(continueButtonFinder);
        await tester.tap(continueButtonFinder);
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.textContaining('ROUND 2 OF 14'), findsOneWidget);
      },
    );
  });
}
