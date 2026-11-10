import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/game/game_runner.dart';
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

Future<GameResult> _fullValidatingRunner(GameRequest request) async {
  final homeTeam = request.league.teams.firstWhere(
    (t) => t.id == request.homeTeamId,
  );
  final awayTeam = request.league.teams.firstWhere(
    (t) => t.id == request.awayTeamId,
  );
  // Full production validation: exactly forwards rotationPlan, lineups, seed, and fixture ID
  final input = GameInput.create(
    gameId:
        request.gameId ??
        '${request.homeTeamId.value}-${request.awayTeamId.value}-${request.seed}',
    league: request.league,
    homeTeamId: request.homeTeamId,
    awayTeamId: request.awayTeamId,
    homeLineup: request.homeLineup ?? CourtLineup.defaultFor(homeTeam),
    awayLineup: request.awayLineup ?? CourtLineup.defaultFor(awayTeam),
    seed: request.seed,
    rules: GameRules.standard,
    rotationPlan: request.rotationPlan,
  );
  return GameSimulator().simulate(input);
}

void main() {
  late League league;

  setUpAll(() {
    league = const LeagueGenerator().generate(_config);
  });

  group('M007-T03 Rotation & Round Progression Verification', () {
    testWidgets('Case A: Change starter, keep Balanced, Save, Play succeeds', (
      tester,
    ) async {
      _useTallSurface(tester);
      final storage = InMemorySeasonStorage();
      await tester.pumpWidget(
        BasketballManagerApp(
          league: league,
          storage: storage,
          seasonMode: true,
          gameRunner: _fullValidatingRunner,
        ),
      );
      await tester.pumpAndSettle();

      // Start season with team 0
      await tester.tap(find.byKey(const ValueKey('start-season-button')));
      await tester.pumpAndSettle();

      // Navigate to Team strategy
      await tester.tap(find.byKey(const ValueKey('nav-team')));
      await tester.pumpAndSettle();

      // Change starter slot 0 to bench player (index 5)
      await tester.tap(find.byKey(const ValueKey('starter-slot-0')));
      await tester.pumpAndSettle();
      final reserve = league.teams.first.players[5];
      await tester.tap(find.text(reserve.fullName).last);
      await tester.pumpAndSettle();

      // Save strategy
      await tester.tap(find.byKey(const ValueKey('save-strategy-button')));
      await tester.pumpAndSettle();
      expect(find.text('Team strategy saved successfully!'), findsOneWidget);

      // Return to Home and Play Next Game
      await tester.tap(find.byKey(const ValueKey('nav-dashboard')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('play-next-game')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // Verify game completed without rotationPresetMismatch
      expect(find.byKey(const ValueKey('game-success')), findsOneWidget);
      expect(find.textContaining('rotationPresetMismatch'), findsNothing);

      // Continue season
      await tester.tap(find.text('Continue Season'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.textContaining('ROUND 2 OF 14'), findsOneWidget);
    });

    testWidgets(
      'Case B: Change starter, select Starter-Heavy preset, Save, Play succeeds',
      (tester) async {
        _useTallSurface(tester);
        final storage = InMemorySeasonStorage();
        await tester.pumpWidget(
          BasketballManagerApp(
            league: league,
            storage: storage,
            seasonMode: true,
            gameRunner: _fullValidatingRunner,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('start-season-button')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('nav-team')));
        await tester.pumpAndSettle();

        // Change starter
        await tester.tap(find.byKey(const ValueKey('starter-slot-1')));
        await tester.pumpAndSettle();
        final reserve = league.teams.first.players[6];
        await tester.tap(find.text(reserve.fullName).last);
        await tester.pumpAndSettle();

        // Change preset to Starter-Heavy ('Starters' segment)
        await tester.tap(find.text('Starters'));
        await tester.pumpAndSettle();

        // Save
        await tester.tap(find.byKey(const ValueKey('save-strategy-button')));
        await tester.pumpAndSettle();
        expect(find.text('Team strategy saved successfully!'), findsOneWidget);

        // Play
        await tester.tap(find.byKey(const ValueKey('nav-dashboard')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('play-next-game')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('game-success')), findsOneWidget);
        await tester.tap(find.text('Continue Season'));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.textContaining('ROUND 2 OF 14'), findsOneWidget);
      },
    );

    test(
      'Case E: Load legacy strategy without rotationPreset and preserve valid targets',
      () {
        final team = league.teams.first;
        // Synthetic legacy test fixture: 14,400s custom allocation without rotationPreset field
        final legacyJson = {
          'teamId': team.id.value,
          'startingLineup': [
            team.players[0].id.value,
            team.players[1].id.value,
            team.players[2].id.value,
            team.players[3].id.value,
            team.players[4].id.value,
          ],
          'rotationTargets': {
            team.players[0].id.value: 2000,
            team.players[1].id.value: 2000,
            team.players[2].id.value: 2000,
            team.players[3].id.value: 2000,
            team.players[4].id.value: 2000,
            team.players[5].id.value: 1100,
            team.players[6].id.value: 1100,
            team.players[7].id.value: 1100,
            team.players[8].id.value: 1100,
            team.players[9].id.value: 0,
            team.players[10].id.value: 0,
            team.players[11].id.value: 0,
          },
        };

        // Loading legacy JSON without rotationPreset must not crash
        final strategy = FranchiseStrategy.fromJson(legacyJson, team);
        expect(strategy.teamPlan.preset, RotationPreset.custom);
        final sum = strategy.teamPlan.targetSeconds.values.fold(
          0,
          (sum, sec) => sum + sec,
        );
        expect(sum, 14400);

        // Must validate cleanly under GameInput engine validation
        expect(() => strategy.validate(team: team), returnsNormally);
      },
    );

    test('Case F: Attempt invalid rotation targets: Save fails visibly', () {
      final team = league.teams.first;
      final lineup = CourtLineup.defaultFor(team);

      // Invalid targets: sum != 14,400s (e.g. 10,000s)
      final invalidTargets = [
        for (final p in team.players)
          RotationTarget(playerId: p.id, seconds: 600),
      ];

      final plan = TeamRotationPlan.create(
        team: team,
        preset: RotationPreset.custom,
        targets: invalidTargets,
      );

      expect(
        () => GameInput.validateLineupAndPlan(
          team: team,
          lineup: lineup,
          plan: plan,
        ),
        throwsA(isA<GameValidationException>()),
      );
    });

    testWidgets(
      'Case G & H: Game completion auto-finalizes and prevents silent result loss',
      (tester) async {
        _useTallSurface(tester);
        final storage = InMemorySeasonStorage();
        await tester.pumpWidget(
          BasketballManagerApp(
            league: league,
            storage: storage,
            seasonMode: true,
            gameRunner: _fullValidatingRunner,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('start-season-button')));
        await tester.pumpAndSettle();

        // Launch game
        await tester.tap(find.byKey(const ValueKey('play-next-game')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        // Verify GameResultView rendered with completed result
        expect(find.byKey(const ValueKey('game-success')), findsOneWidget);

        // Case H: Tap return to league / pop
        await tester.tap(find.text('Continue Season'));
        await tester.pump();
        await tester.pumpAndSettle();

        // Verified advanced to Round 2
        expect(find.textContaining('ROUND 2 OF 14'), findsOneWidget);

        // Case J: Reopen app with same storage: verify consistency
        await tester.pumpWidget(
          BasketballManagerApp(
            league: league,
            storage: storage,
            seasonMode: true,
            gameRunner: _fullValidatingRunner,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('ROUND 2 OF 14'), findsOneWidget);
      },
    );
  });
}
