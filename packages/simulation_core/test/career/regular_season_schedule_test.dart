import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _seeds = [20261028, 1604126146, 987654321, 314159265, 271828182, 8675309];

List<RegularSeasonTeamIdentity> _teams() => [
  for (var index = 0; index < 30; index++)
    RegularSeasonTeamIdentity(
      teamId: TeamId('franchise-${index.toString().padLeft(2, '0')}'),
      name: 'Franchise $index',
      abbreviation: 'F${index.toString().padLeft(2, '0')}',
    ),
];

RegularSeasonSchedule _schedule(
  int seed, {
  List<RegularSeasonTeamIdentity>? teams,
}) => const RegularSeasonScheduleGenerator().generate(
  seasonId: 'career-test-season-1',
  seasonYear: 1,
  scheduleSeed: seed,
  openingTeams: teams ?? _teams(),
);

void main() {
  group('30-franchise regular-season schedule', () {
    test('six requested seeds produce valid deterministic schedules', () {
      for (final seed in _seeds) {
        final generationTimer = Stopwatch()..start();
        final schedule = _schedule(seed);
        generationTimer.stop();
        final validationTimer = Stopwatch()..start();
        schedule.validate();
        validationTimer.stop();

        expect(schedule.rounds, hasLength(82));
        expect(schedule.totalFixtures, 1230);
        expect(schedule.remainingGamesCount, 1230);
        expect(schedule.completedGamesCount, 0);
        expect(
          schedule.allFixtures.every(
            (fixture) => fixture.status == RegularSeasonFixtureStatus.scheduled,
          ),
          isTrue,
        );
        expect(schedule.canonicalJson, _schedule(seed).canonicalJson);
        expect(
          _schedule(seed, teams: _teams().reversed.toList()).canonicalJson,
          schedule.canonicalJson,
        );

        final fixturesByTeam = <String, List<RegularSeasonFixture>>{
          for (final team in _teams()) team.teamId.value: [],
        };
        final pairRounds = <(String, String), List<int>>{};
        final fixtureIds = <String>{};
        var duplicateIds = 0;
        var roundCollisions = 0;
        for (final round in schedule.rounds) {
          final roundTeams = <String>{};
          for (final fixture in round.fixtures) {
            if (!fixtureIds.add(fixture.id)) duplicateIds++;
            if (!roundTeams.add(fixture.homeTeamId.value)) roundCollisions++;
            if (!roundTeams.add(fixture.awayTeamId.value)) roundCollisions++;
            fixturesByTeam[fixture.homeTeamId.value]!.add(fixture);
            fixturesByTeam[fixture.awayTeamId.value]!.add(fixture);
            final ids = [fixture.homeTeamId.value, fixture.awayTeamId.value]
              ..sort();
            pairRounds
                .putIfAbsent((ids[0], ids[1]), () => [])
                .add(round.roundNumber);
          }
          expect(roundTeams, hasLength(30));
        }
        expect(duplicateIds, 0);
        expect(roundCollisions, 0);
        expect(fixtureIds, hasLength(1230));

        var maximumHomeStreak = 0;
        var maximumAwayStreak = 0;
        var minimumRematchSeparation = 82;
        for (final entry in fixturesByTeam.entries) {
          expect(entry.value, hasLength(82));
          expect(
            entry.value.where(
              (fixture) => fixture.homeTeamId.value == entry.key,
            ),
            hasLength(41),
          );
          expect(
            entry.value.where(
              (fixture) => fixture.awayTeamId.value == entry.key,
            ),
            hasLength(41),
          );
        }
        for (final entry in fixturesByTeam.entries) {
          var homeStreak = 0;
          var awayStreak = 0;
          for (final fixture in entry.value) {
            if (fixture.homeTeamId.value == entry.key) {
              homeStreak++;
              awayStreak = 0;
            } else {
              awayStreak++;
              homeStreak = 0;
            }
            if (homeStreak > maximumHomeStreak) maximumHomeStreak = homeStreak;
            if (awayStreak > maximumAwayStreak) maximumAwayStreak = awayStreak;
          }
        }
        for (final rounds in pairRounds.values) {
          for (var index = 1; index < rounds.length; index++) {
            final separation = rounds[index] - rounds[index - 1];
            if (separation < minimumRematchSeparation) {
              minimumRematchSeparation = separation;
            }
          }
        }
        expect(pairRounds, hasLength(435));
        expect(
          pairRounds.values.where((rounds) => rounds.length == 4),
          hasLength(180),
        );
        expect(
          pairRounds.values.where((rounds) => rounds.length == 2),
          hasLength(255),
        );
        expect(minimumRematchSeparation, greaterThan(1));
        expect(schedule.fingerprint, hasLength(64));
        print(
          'SCHEDULE seed=$seed rounds=82 fixtures=1230 homeAway=41/41 '
          'fourGameOpponents=12 twoGameOpponents=17 duplicateIds=$duplicateIds '
          'roundCollisions=$roundCollisions maxHomeStreak=$maximumHomeStreak '
          'maxAwayStreak=$maximumAwayStreak minRematchSeparation=$minimumRematchSeparation '
          'fingerprint=${schedule.fingerprint} '
          'generationUs=${generationTimer.elapsedMicroseconds} '
          'validationUs=${validationTimer.elapsedMicroseconds} '
          'encodedBytes=${utf8.encode(schedule.canonicalJson).length}',
        );
      }
    });

    test('selection rejects invalid team identity sets', () {
      expect(
        () => const RegularSeasonScheduleGenerator().generate(
          seasonId: 'season',
          seasonYear: 1,
          scheduleSeed: 1,
          openingTeams: _teams().take(29).toList(),
        ),
        throwsArgumentError,
      );
      expect(
        () => const RegularSeasonScheduleGenerator().generate(
          seasonId: 'season',
          seasonYear: 1,
          scheduleSeed: 1,
          openingTeams: [..._teams().take(29), _teams().first],
        ),
        throwsArgumentError,
      );
    });

    test('queries preserve order and schedules are immutable', () {
      final schedule = _schedule(_seeds.first);
      final firstTeam = TeamId('franchise-00');
      final secondTeam = TeamId('franchise-01');
      final teamFixtures = schedule.fixturesForTeam(firstTeam).toList();
      expect(teamFixtures, hasLength(82));
      expect(schedule.homeFixturesForTeam(firstTeam), hasLength(41));
      expect(schedule.awayFixturesForTeam(firstTeam), hasLength(41));
      expect(schedule.fixturesForRound(1), hasLength(15));
      expect(
        schedule.opponentMatchupHistory(firstTeam, secondTeam),
        hasLength(2),
      );
      expect(schedule.nextScheduledGame(firstTeam), teamFixtures.first);
      expect(schedule.remainingGamesForTeam(firstTeam), 82);
      expect(schedule.completedGamesForTeam(firstTeam), 0);
      expect(() => schedule.rounds.clear(), throwsUnsupportedError);
      expect(
        () => schedule.rounds.first.fixtures.clear(),
        throwsUnsupportedError,
      );
    });

    test('different seeds change selected pairings but retain contract', () {
      final first = _schedule(_seeds[0]);
      final second = _schedule(_seeds[1]);
      expect(second.fingerprint, isNot(first.fingerprint));
      expect(second.totalFixtures, 1230);
      expect(second.rounds, hasLength(82));
    });

    test('tampered fixture seed is rejected', () {
      final schedule = _schedule(_seeds.first);
      final firstRound = schedule.rounds.first;
      final firstFixture = firstRound.fixtures.first;
      final alteredFixture = RegularSeasonFixture(
        id: firstFixture.id,
        seasonId: firstFixture.seasonId,
        seasonYear: firstFixture.seasonYear,
        roundNumber: firstFixture.roundNumber,
        fixturePosition: firstFixture.fixturePosition,
        homeTeamId: firstFixture.homeTeamId,
        awayTeamId: firstFixture.awayTeamId,
        gameSeed: firstFixture.gameSeed + 1,
        status: firstFixture.status,
      );
      expect(
        () => RegularSeasonSchedule(
          seasonId: schedule.seasonId,
          seasonYear: schedule.seasonYear,
          scheduleSeed: schedule.scheduleSeed,
          rounds: [
            RegularSeasonRound(
              roundNumber: firstRound.roundNumber,
              fixtures: [alteredFixture, ...firstRound.fixtures.skip(1)],
            ),
            ...schedule.rounds.skip(1),
          ],
        ),
        throwsFormatException,
      );
    });
  });
}
