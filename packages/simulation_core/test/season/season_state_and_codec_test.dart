import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

void main() {
  group('SeasonState & SeasonCodec', () {
    late League league;
    late Team userTeam;

    setUp(() {
      const generator = LeagueGenerator();
      league = generator.generate(const GenerationConfig(seed: 20261028));
      userTeam = league.teams.first;
    });

    test('initializes cleanly and identifies next user fixture', () {
      final state = SeasonState.initialize(
        league: league,
        userFranchiseId: userTeam.id,
      );

      expect(state.currentRoundNumber, 1);
      expect(state.isSeasonCompleted, isFalse);
      expect(state.userFranchiseId, userTeam.id);
      expect(state.userTeam.id, userTeam.id);
      expect(state.standings.table.length, 8);
      expect(state.playerStats.length, 96); // 8 teams * 12 players

      final nextFixture = state.nextUserFixture;
      expect(nextFixture, isNotNull);
      expect(
        nextFixture!.homeTeamId == userTeam.id ||
            nextFixture.awayTeamId == userTeam.id,
        isTrue,
      );
      expect(nextFixture.roundNumber, 1);
    });

    test(
      'simulates round, commits atomically, updates standings, and advances',
      () {
        var state = SeasonState.initialize(
          league: league,
          userFranchiseId: userTeam.id,
        );

        final round1 = state.currentRound!;
        expect(round1.isCompleted, isFalse);

        final simulator = GameSimulator();
        final roundResults = <GameResult>[];

        for (final fixture in round1.fixtures) {
          final homeTeam = league.teams.firstWhere(
            (t) => t.id == fixture.homeTeamId,
          );
          final awayTeam = league.teams.firstWhere(
            (t) => t.id == fixture.awayTeamId,
          );
          final input = GameInput.create(
            gameId: fixture.id,
            league: league,
            homeTeamId: fixture.homeTeamId,
            awayTeamId: fixture.awayTeamId,
            homeLineup: CourtLineup.defaultFor(homeTeam),
            awayLineup: CourtLineup.defaultFor(awayTeam),
            seed: fixture.seed,
            rules: GameRules.standard,
          );
          roundResults.add(simulator.simulate(input));
        }

        // Commit round 1
        state = state.commitRound(roundNumber: 1, results: roundResults);

        expect(state.currentRoundNumber, 2);
        expect(state.schedule.rounds[0].isCompleted, isTrue);

        // Verify standings: exactly 4 teams with 1-0, 4 teams with 0-1
        var totalWins = 0;
        var totalLosses = 0;
        for (final s in state.standings.table.values) {
          expect(s.gamesPlayed, 1);
          totalWins += s.wins;
          totalLosses += s.losses;
        }
        expect(totalWins, 4);
        expect(totalLosses, 4);

        // Verify idempotency / transaction guards
        expect(
          () => state.commitRound(roundNumber: 1, results: roundResults),
          throwsStateError,
          reason: 'Cannot re-commit already committed round',
        );
        expect(
          () => state.commitRound(roundNumber: 3, results: roundResults),
          throwsStateError,
          reason: 'Cannot skip ahead of current round',
        );
      },
    );

    test('SeasonCodec preserves exact state through encode and decode', () {
      var state = SeasonState.initialize(
        league: league,
        userFranchiseId: userTeam.id,
      );

      // Simulate round 1
      final round1 = state.currentRound!;
      final simulator = GameSimulator();
      final roundResults = <GameResult>[];
      for (final fixture in round1.fixtures) {
        final homeTeam = league.teams.firstWhere(
          (t) => t.id == fixture.homeTeamId,
        );
        final awayTeam = league.teams.firstWhere(
          (t) => t.id == fixture.awayTeamId,
        );
        final input = GameInput.create(
          gameId: fixture.id,
          league: league,
          homeTeamId: fixture.homeTeamId,
          awayTeamId: fixture.awayTeamId,
          homeLineup: CourtLineup.defaultFor(homeTeam),
          awayLineup: CourtLineup.defaultFor(awayTeam),
          seed: fixture.seed,
          rules: GameRules.standard,
        );
        roundResults.add(simulator.simulate(input));
      }
      state = state.commitRound(roundNumber: 1, results: roundResults);

      final encoded = SeasonCodec.encode(state);
      final decoded = SeasonCodec.decode(encoded, existingLeague: league);

      expect(decoded.schemaVersion, state.schemaVersion);
      expect(decoded.id, state.id);
      expect(decoded.leagueSeed, state.leagueSeed);
      expect(decoded.userFranchiseId, state.userFranchiseId);
      expect(decoded.currentRoundNumber, state.currentRoundNumber);
      expect(decoded.schedule.rounds.length, state.schedule.rounds.length);
      expect(decoded.schedule.rounds[0].isCompleted, isTrue);

      final originalRanked = state.standings.ranked;
      final decodedRanked = decoded.standings.ranked;
      for (var i = 0; i < originalRanked.length; i++) {
        expect(decodedRanked[i].teamId, originalRanked[i].teamId);
        expect(decodedRanked[i].wins, originalRanked[i].wins);
        expect(decodedRanked[i].losses, originalRanked[i].losses);
        expect(
          decodedRanked[i].pointDifferential,
          originalRanked[i].pointDifferential,
        );
        expect(decodedRanked[i].streak, originalRanked[i].streak);
      }
    });

    test('SeasonCodec rejects corrupt or unsupported schema', () {
      expect(
        () => SeasonCodec.decode('{invalid-json'),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => SeasonCodec.decode('{"schemaVersion": 99, "leagueSeed": 1}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('completes full 14-round 56-game season and crowns champion', () {
      var state = SeasonState.initialize(
        league: league,
        userFranchiseId: userTeam.id,
      );
      final simulator = GameSimulator();

      for (var r = 1; r <= 14; r++) {
        expect(state.currentRoundNumber, r);
        expect(state.isSeasonCompleted, isFalse);

        final currentRound = state.currentRound!;
        final roundResults = <GameResult>[];
        for (final fixture in currentRound.fixtures) {
          final homeTeam = league.teams.firstWhere(
            (t) => t.id == fixture.homeTeamId,
          );
          final awayTeam = league.teams.firstWhere(
            (t) => t.id == fixture.awayTeamId,
          );
          final input = GameInput.create(
            gameId: fixture.id,
            league: league,
            homeTeamId: fixture.homeTeamId,
            awayTeamId: fixture.awayTeamId,
            homeLineup: CourtLineup.defaultFor(homeTeam),
            awayLineup: CourtLineup.defaultFor(awayTeam),
            seed: fixture.seed,
            rules: GameRules.standard,
          );
          roundResults.add(simulator.simulate(input));
        }
        state = state.commitRound(roundNumber: r, results: roundResults);
      }

      expect(state.currentRoundNumber, 15);
      expect(state.isSeasonCompleted, isTrue);
      expect(state.currentRound, isNull);
      expect(state.nextUserFixture, isNull);

      // Standings conservation: 8 teams * 14 games = 112 team-games = 56 wins, 56 losses
      var totalW = 0;
      var totalL = 0;
      for (final s in state.standings.table.values) {
        expect(s.gamesPlayed, 14);
        totalW += s.wins;
        totalL += s.losses;
      }
      expect(totalW, 56);
      expect(totalL, 56);

      final champ = state.champion;
      expect(champ.gamesPlayed, 14);
      expect(
        champ.wins,
        greaterThanOrEqualTo(state.standings.ranked.last.wins),
      );
      // Reconciliation audit: Player totals exactly equal sum of game box scores
      final auditPoints = <String, int>{};
      final auditFgm = <String, int>{};
      final auditReb = <String, int>{};
      final auditAst = <String, int>{};

      for (final r in state.schedule.rounds) {
        for (final f in r.fixtures) {
          final summary = f.summary!;
          for (final entry in summary.playerLines.entries) {
            final pId = entry.key;
            final line = entry.value;
            auditPoints[pId] = (auditPoints[pId] ?? 0) + line.points;
            auditFgm[pId] = (auditFgm[pId] ?? 0) + line.fgm;
            auditReb[pId] = (auditReb[pId] ?? 0) + line.rebounds;
            auditAst[pId] = (auditAst[pId] ?? 0) + line.assists;
          }
        }
      }

      for (final pEntry in state.playerStats.entries) {
        final pId = pEntry.key;
        final stats = pEntry.value;
        expect(stats.points, auditPoints[pId] ?? 0);
        expect(stats.fgm, auditFgm[pId] ?? 0);
        expect(stats.rebounds, auditReb[pId] ?? 0);
        expect(stats.assists, auditAst[pId] ?? 0);
      }

      // Attempting to commit beyond round 14 throws StateError
      expect(
        () => state.commitRound(roundNumber: 15, results: []),
        throwsStateError,
      );
    });
  });
}
