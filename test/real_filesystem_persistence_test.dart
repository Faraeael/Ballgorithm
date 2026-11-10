import 'dart:io';

import 'package:basketball_manager/features/game/game_runner.dart';
import 'package:basketball_manager/features/season/season_controller.dart';
import 'package:basketball_manager/features/season/season_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _config = GenerationConfig(seed: 20261028);

Future<GameResult> _headlessRunner(GameRequest request) async {
  final homeTeam = request.league.teams.firstWhere(
    (t) => t.id == request.homeTeamId,
  );
  final awayTeam = request.league.teams.firstWhere(
    (t) => t.id == request.awayTeamId,
  );
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
  late Directory tempDir;

  setUpAll(() {
    league = const LeagueGenerator().generate(_config);
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ballgorithm_fs_test_');
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('FileSeasonStorage crash-resistant filesystem guarantees', () {
    test('genuinely missing save returns null', () async {
      final storage = FileSeasonStorage(
        filePath: '${tempDir.path}/non_existent.json',
      );
      final content = await storage.read();
      expect(content, isNull);
    });

    test('writes and flushes data to real file', () async {
      final savePath = '${tempDir.path}/save.json';
      final storage = FileSeasonStorage(filePath: savePath);

      await storage.write('{"test": "data"}');
      final content = await storage.read();
      expect(content, '{"test": "data"}');
      expect(File(savePath).existsSync(), isTrue);
    });

    test('recovers from interrupted promotion where backup exists', () async {
      final savePath = '${tempDir.path}/save.json';
      final storage = FileSeasonStorage(filePath: savePath);

      // Simulate interrupted state: active file missing, backup exists
      final backupFile = File('$savePath.bak');
      await backupFile.writeAsString('{"restored": "from_backup"}');

      final content = await storage.read();
      expect(content, '{"restored": "from_backup"}');
      // Verify restored to active file
      expect(File(savePath).existsSync(), isTrue);
    });

    test('recovers from interrupted save where temp exists', () async {
      final savePath = '${tempDir.path}/save.json';
      final storage = FileSeasonStorage(filePath: savePath);

      // Simulate interrupted state: active file missing, temp exists
      final tempFile = File('$savePath.tmp');
      await tempFile.writeAsString('{"restored": "from_temp"}');

      final content = await storage.read();
      expect(content, '{"restored": "from_temp"}');
      // Verify promoted to active file
      expect(File(savePath).existsSync(), isTrue);
    });

    test('clear removes active file, backup, and temp', () async {
      final savePath = '${tempDir.path}/save.json';
      final storage = FileSeasonStorage(filePath: savePath);

      await File(savePath).writeAsString('active');
      await File('$savePath.bak').writeAsString('backup');
      await File('$savePath.tmp').writeAsString('temp');

      await storage.clear();

      expect(File(savePath).existsSync(), isFalse);
      expect(File('$savePath.bak').existsSync(), isFalse);
      expect(File('$savePath.tmp').existsSync(), isFalse);
    });
  });

  group('Real persistence workflow: write -> advance -> reload -> advance', () {
    test('8-step lifecycle across real file storage instances', () async {
      final savePath = '${tempDir.path}/season_real.json';
      final storage1 = FileSeasonStorage(filePath: savePath);
      final controller1 = SeasonController(
        league: league,
        storage: storage1,
        gameRunner: _headlessRunner,
      );

      // Step 1: Write a new season
      final userTeamId = league.teams.first.id;
      await controller1.startNewSeason(userTeamId);
      expect(controller1.hasActiveSeason, isTrue);
      expect(controller1.state!.currentRoundNumber, 1);
      expect(File(savePath).existsSync(), isTrue);

      // Step 2 & 3: Complete Round 1 and persist atomically
      final userFixture1 = controller1.state!.nextUserFixture!;
      expect(userFixture1.roundNumber, 1);

      final homeTeam = league.teams.firstWhere(
        (t) => t.id == userFixture1.homeTeamId,
      );
      final awayTeam = league.teams.firstWhere(
        (t) => t.id == userFixture1.awayTeamId,
      );
      final userReq1 = GameRequest(
        gameId: userFixture1.id,
        league: league,
        homeTeamId: userFixture1.homeTeamId,
        awayTeamId: userFixture1.awayTeamId,
        seed: userFixture1.seed,
        homeLineup: CourtLineup.defaultFor(homeTeam),
        awayLineup: CourtLineup.defaultFor(awayTeam),
      );
      final userResult1 = await _headlessRunner(userReq1);

      await controller1.commitRoundWithUserResult(userResult1);
      expect(controller1.state!.currentRoundNumber, 2);

      // Step 4: Dispose the controller
      controller1.dispose();

      // Step 5: Construct new controller and storage instance
      final storage2 = FileSeasonStorage(filePath: savePath);
      final controller2 = SeasonController(
        league: league,
        storage: storage2,
        gameRunner: _headlessRunner,
      );

      // Step 6: Load the saved season from disk
      await controller2.loadSeason();
      expect(controller2.hasActiveSeason, isTrue);

      // Step 7: Verify Round 2, standings, and player totals
      final state2 = controller2.state!;
      expect(state2.currentRoundNumber, 2);
      expect(state2.isSeasonCompleted, isFalse);

      // Standings: 4 games completed -> 4 wins, 4 losses
      var wins = 0;
      var losses = 0;
      for (final s in state2.standings.table.values) {
        wins += s.wins;
        losses += s.losses;
      }
      expect(wins, 4);
      expect(losses, 4);

      // Player totals: non-empty minutes and points
      final userPlayerId = league.teams.first.players.first.id.value;
      expect(state2.playerStats[userPlayerId], isNotNull);
      expect(state2.playerStats[userPlayerId]!.gamesPlayed, 1);

      // Step 8: Complete Round 2 without duplication
      // Verify re-submitting Round 1 result is rejected
      await expectLater(
        () => controller2.commitRoundWithUserResult(userResult1),
        throwsA(isA<ArgumentError>()),
      );

      // Play legitimate Round 2 user game
      final userFixture2 = controller2.state!.nextUserFixture!;
      expect(userFixture2.roundNumber, 2);

      final userReq2 = GameRequest(
        gameId: userFixture2.id,
        league: league,
        homeTeamId: userFixture2.homeTeamId,
        awayTeamId: userFixture2.awayTeamId,
        seed: userFixture2.seed,
      );
      final userResult2 = await _headlessRunner(userReq2);

      await controller2.commitRoundWithUserResult(userResult2);
      expect(controller2.state!.currentRoundNumber, 3);

      controller2.dispose();
    });

    test('strict commit rejects mismatched game and exhibition game', () async {
      final savePath = '${tempDir.path}/season_strict.json';
      final storage = FileSeasonStorage(filePath: savePath);
      final controller = SeasonController(
        league: league,
        storage: storage,
        gameRunner: _headlessRunner,
      );

      await controller.startNewSeason(league.teams.first.id);
      final fixture = controller.state!.nextUserFixture!;

      // Case A: Wrong fixture ID
      final wrongIdReq = GameRequest(
        gameId: 'wrong-fixture-id',
        league: league,
        homeTeamId: fixture.homeTeamId,
        awayTeamId: fixture.awayTeamId,
        seed: fixture.seed,
      );
      final wrongIdResult = await _headlessRunner(wrongIdReq);
      await expectLater(
        () => controller.commitRoundWithUserResult(wrongIdResult),
        throwsA(isA<ArgumentError>()),
      );

      // Case B: Wrong seed
      final wrongSeedReq = GameRequest(
        gameId: fixture.id,
        league: league,
        homeTeamId: fixture.homeTeamId,
        awayTeamId: fixture.awayTeamId,
        seed: 99999999,
      );
      final wrongSeedResult = await _headlessRunner(wrongSeedReq);
      await expectLater(
        () => controller.commitRoundWithUserResult(wrongSeedResult),
        throwsA(isA<ArgumentError>()),
      );

      // Verify state was not modified
      expect(controller.state!.currentRoundNumber, 1);
      controller.dispose();
    });

    test(
      'handles write failure, retains state, and recovers on retry',
      () async {
        final saveStorage = InMemorySeasonStorage();
        final controller = SeasonController(
          league: league,
          storage: saveStorage,
          gameRunner: _headlessRunner,
        );

        await controller.startNewSeason(league.teams.first.id);
        final fixture = controller.state!.nextUserFixture!;

        final userReq = GameRequest(
          gameId: fixture.id,
          league: league,
          homeTeamId: fixture.homeTeamId,
          awayTeamId: fixture.awayTeamId,
          seed: fixture.seed,
        );
        final userResult = await _headlessRunner(userReq);

        // Inject write failure
        saveStorage.shouldThrowOnWrite = true;

        // Attempt commit -> throws
        try {
          await controller.commitRoundWithUserResult(userResult);
          fail('Expected SeasonStorageException');
        } catch (e) {
          expect(e, isA<SeasonStorageException>());
        }

        // State did NOT advance
        expect(controller.state!.currentRoundNumber, 1);
        expect(controller.hasPendingResult, isTrue);
        expect(controller.errorMessage, isNotNull);

        // Resolve write failure and retry
        saveStorage.shouldThrowOnWrite = false;
        await controller.retryPendingCommit();

        // Successfully saved and advanced
        expect(controller.state!.currentRoundNumber, 2);
        expect(controller.hasPendingResult, isFalse);
        expect(controller.errorMessage, isNull);

        controller.dispose();
      },
    );
  });
}
