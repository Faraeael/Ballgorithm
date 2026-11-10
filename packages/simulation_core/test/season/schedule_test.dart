import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

void main() {
  group('SeasonSchedule', () {
    late League league;

    setUp(() {
      const generator = LeagueGenerator();
      league = generator.generate(const GenerationConfig(seed: 20261028));
    });

    test('generates exactly 14 rounds of 4 games (56 total fixtures)', () {
      final schedule = SeasonSchedule.generate(league: league);
      expect(schedule.rounds.length, 14);
      expect(schedule.totalFixtures, 56);

      for (var r = 0; r < 14; r++) {
        final round = schedule.rounds[r];
        expect(round.roundNumber, r + 1);
        expect(round.fixtures.length, 4);
      }
    });

    test('each team plays exactly 14 games: 7 home and 7 away', () {
      final schedule = SeasonSchedule.generate(league: league);
      final homeCounts = <String, int>{};
      final awayCounts = <String, int>{};

      for (final team in league.teams) {
        homeCounts[team.id.value] = 0;
        awayCounts[team.id.value] = 0;
      }

      for (final round in schedule.rounds) {
        for (final fixture in round.fixtures) {
          homeCounts[fixture.homeTeamId.value] =
              homeCounts[fixture.homeTeamId.value]! + 1;
          awayCounts[fixture.awayTeamId.value] =
              awayCounts[fixture.awayTeamId.value]! + 1;
        }
      }

      for (final team in league.teams) {
        expect(
          homeCounts[team.id.value],
          7,
          reason: 'Team ${team.id.value} should have 7 home games',
        );
        expect(
          awayCounts[team.id.value],
          7,
          reason: 'Team ${team.id.value} should have 7 away games',
        );
      }
    });

    test(
      'each team plays every other team exactly twice: once home, once away',
      () {
        final schedule = SeasonSchedule.generate(league: league);
        final matchupCounts = <String, int>{};

        for (final round in schedule.rounds) {
          for (final f in round.fixtures) {
            final directedKey = '${f.homeTeamId.value}->${f.awayTeamId.value}';
            matchupCounts[directedKey] = (matchupCounts[directedKey] ?? 0) + 1;
          }
        }

        // Exactly 8 * 7 = 56 directed matchups, each occurring once
        expect(matchupCounts.length, 56);
        for (final teamA in league.teams) {
          for (final teamB in league.teams) {
            if (teamA.id == teamB.id) continue;
            final key = '${teamA.id.value}->${teamB.id.value}';
            expect(
              matchupCounts[key],
              1,
              reason: 'Directed matchup $key should occur exactly once',
            );
          }
        }
      },
    );

    test('each team plays exactly once per round with no idle teams', () {
      final schedule = SeasonSchedule.generate(league: league);

      for (final round in schedule.rounds) {
        final teamsInRound = <String>{};
        for (final f in round.fixtures) {
          expect(f.homeTeamId, isNot(equals(f.awayTeamId)));
          expect(
            teamsInRound.add(f.homeTeamId.value),
            isTrue,
            reason:
                'Team ${f.homeTeamId.value} played twice in round ${round.roundNumber}',
          );
          expect(
            teamsInRound.add(f.awayTeamId.value),
            isTrue,
            reason:
                'Team ${f.awayTeamId.value} played twice in round ${round.roundNumber}',
          );
        }
        expect(teamsInRound.length, 8);
      }
    });

    test('all fixture IDs and seeds are distinct and deterministic', () {
      final schedule1 = SeasonSchedule.generate(league: league);
      final schedule2 = SeasonSchedule.generate(league: league);

      final seenIds = <String>{};
      final seenSeeds = <int>{};

      for (var r = 0; r < 14; r++) {
        final r1 = schedule1.rounds[r];
        final r2 = schedule2.rounds[r];

        for (var f = 0; f < 4; f++) {
          final f1 = r1.fixtures[f];
          final f2 = r2.fixtures[f];

          expect(f1.id, f2.id);
          expect(f1.homeTeamId, f2.homeTeamId);
          expect(f1.awayTeamId, f2.awayTeamId);
          expect(f1.seed, f2.seed);

          expect(
            seenIds.add(f1.id),
            isTrue,
            reason: 'Duplicate fixture ID ${f1.id}',
          );
          expect(
            seenSeeds.add(f1.seed),
            isTrue,
            reason: 'Duplicate seed ${f1.seed}',
          );
          expect(f1.seed, isNonZero);
        }
      }

      expect(seenIds.length, 56);
      expect(seenSeeds.length, 56);
    });
  });
}
