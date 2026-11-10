import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

void main() {
  group('LeagueStandings', () {
    late League league;
    late Team teamA;
    late Team teamB;
    late Team teamC;

    setUp(() {
      const generator = LeagueGenerator();
      league = generator.generate(const GenerationConfig(seed: 20261028));
      teamA = league.teams[0];
      teamB = league.teams[1];
      teamC = league.teams[2];
    });

    test('initializes all teams with 0-0 record and neutral streak', () {
      final standings = LeagueStandings.initial(league);
      expect(standings.table.length, 8);

      for (final team in league.teams) {
        final s = standings.table[team.id.value]!;
        expect(s.gamesPlayed, 0);
        expect(s.wins, 0);
        expect(s.losses, 0);
        expect(s.pointsFor, 0);
        expect(s.pointsAgainst, 0);
        expect(s.pointDifferential, 0);
        expect(s.winPercentage, 0.0);
        expect(s.streak, '-');
      }
    });

    test('records game results and tracks streaks correctly', () {
      var standings = LeagueStandings.initial(league);

      // Game 1: A beats B (100-90)
      standings = standings.applyGame(
        homeId: teamA.id,
        awayId: teamB.id,
        homeScore: 100,
        awayScore: 90,
      );

      final sA1 = standings.table[teamA.id.value]!;
      expect(sA1.gamesPlayed, 1);
      expect(sA1.wins, 1);
      expect(sA1.losses, 0);
      expect(sA1.pointsFor, 100);
      expect(sA1.pointsAgainst, 90);
      expect(sA1.pointDifferential, 10);
      expect(sA1.winPercentage, 1.0);
      expect(sA1.streak, 'W1');

      final sB1 = standings.table[teamB.id.value]!;
      expect(sB1.gamesPlayed, 1);
      expect(sB1.wins, 0);
      expect(sB1.losses, 1);
      expect(sB1.pointsFor, 90);
      expect(sB1.pointsAgainst, 100);
      expect(sB1.pointDifferential, -10);
      expect(sB1.winPercentage, 0.0);
      expect(sB1.streak, 'L1');

      // Game 2: A beats C (105-95) -> streak becomes W2
      standings = standings.applyGame(
        homeId: teamA.id,
        awayId: teamC.id,
        homeScore: 105,
        awayScore: 95,
      );
      final sA2 = standings.table[teamA.id.value]!;
      expect(sA2.wins, 2);
      expect(sA2.streak, 'W2');

      // Game 3: B beats A (110-100) -> A streak breaks to L1, B becomes W1
      standings = standings.applyGame(
        homeId: teamB.id,
        awayId: teamA.id,
        homeScore: 110,
        awayScore: 100,
      );
      final sA3 = standings.table[teamA.id.value]!;
      expect(sA3.gamesPlayed, 3);
      expect(sA3.wins, 2);
      expect(sA3.losses, 1);
      expect(sA3.streak, 'L1');

      final sB2 = standings.table[teamB.id.value]!;
      expect(sB2.gamesPlayed, 2);
      expect(sB2.wins, 1);
      expect(sB2.losses, 1);
      expect(sB2.streak, 'W1');
    });

    test(
      'deterministic tie-break hierarchy: Wins -> Diff -> Points For -> TeamId',
      () {
        var standings = LeagueStandings.initial(league);

        // Make Team A: 1 W, +10 diff (100-90)
        standings = standings.applyGame(
          homeId: teamA.id,
          awayId: teamB.id,
          homeScore: 100,
          awayScore: 90,
        );

        // Make Team C: 1 W, +15 diff (115-100)
        standings = standings.applyGame(
          homeId: teamC.id,
          awayId: league.teams[3].id,
          homeScore: 115,
          awayScore: 100,
        );

        // Team C should be ranked #1 (higher diff), Team A #2
        final ranked1 = standings.ranked;
        expect(ranked1[0].teamId, teamC.id);
        expect(ranked1[1].teamId, teamA.id);

        // Test tie-break by Points For when Wins and Diff are tied:
        // Team D: 1 W, +10 diff, 110 PF (110-100)
        final teamD = league.teams[4];
        standings = standings.applyGame(
          homeId: teamD.id,
          awayId: league.teams[5].id,
          homeScore: 110,
          awayScore: 100,
        );

        // Both Team D and Team A have 1 W and +10 diff, but Team D has 110 PF vs Team A's 100 PF
        final ranked2 = standings.ranked;
        expect(ranked2[0].teamId, teamC.id); // +15 diff
        expect(ranked2[1].teamId, teamD.id); // +10 diff, 110 PF
        expect(ranked2[2].teamId, teamA.id); // +10 diff, 100 PF
      },
    );
  });
}
