import '../models/league.dart';
import 'season_fixture.dart';
import 'season_round.dart';
import 'season_seed.dart';

final class SeasonSchedule {
  SeasonSchedule({required List<SeasonRound> rounds})
    : rounds = List.unmodifiable(rounds);

  factory SeasonSchedule.fromJson(Map<String, dynamic> json) => SeasonSchedule(
    rounds: [
      for (final r in json['rounds'] as List)
        SeasonRound.fromJson(r as Map<String, dynamic>),
    ],
  );

  final List<SeasonRound> rounds;

  int get totalFixtures => rounds.fold(0, (sum, r) => sum + r.fixtures.length);

  bool get isCompleted => rounds.every((r) => r.isCompleted);

  SeasonRound roundAt(int roundNumber) {
    if (roundNumber < 1 || roundNumber > rounds.length) {
      throw RangeError.range(roundNumber, 1, rounds.length, 'roundNumber');
    }
    return rounds[roundNumber - 1];
  }

  SeasonSchedule copyWithUpdatedRound(SeasonRound updated) {
    return SeasonSchedule(
      rounds: [
        for (final r in rounds)
          r.roundNumber == updated.roundNumber ? updated : r,
      ],
    );
  }

  /// Generates a deterministic, symmetric 14-round round-robin schedule for an
  /// 8-team league.
  ///
  /// Every team plays exactly 14 games (7 home, 7 away). Each team plays all 7
  /// opponents exactly twice (once home, once away). Exactly 4 games per round,
  /// 56 games total.
  static SeasonSchedule generate({required League league}) {
    if (league.teams.length != 8) {
      throw ArgumentError.value(
        league.teams.length,
        'league.teams.length',
        'M007 single-season schedule requires exactly 8 teams',
      );
    }

    final teams = league.teams;
    const n = 8;
    final roundsFirstHalf = <List<({int home, int away})>>[];

    // Canonical circle/polygon method: fix team 0, rotate 1..7
    final rotation = List<int>.generate(n - 1, (i) => i + 1);

    for (var r = 0; r < n - 1; r++) {
      final roundMatches = <({int home, int away})>[];
      final t0 = 0;
      final t1 = rotation.last;

      // Alternate home/away for the fixed anchor team
      if (r % 2 == 0) {
        roundMatches.add((home: t0, away: t1));
      } else {
        roundMatches.add((home: t1, away: t0));
      }

      for (var i = 0; i < (n - 2) ~/ 2; i++) {
        final home = rotation[i];
        final away = rotation[rotation.length - 2 - i];
        if ((i + r) % 2 == 0) {
          roundMatches.add((home: home, away: away));
        } else {
          roundMatches.add((home: away, away: home));
        }
      }

      roundsFirstHalf.add(roundMatches);
      // Rotate elements
      final last = rotation.removeLast();
      rotation.insert(0, last);
    }

    // Second half (rounds 8..14): exactly reverse home and away of first half
    final roundsSecondHalf = <List<({int home, int away})>>[];
    for (final rMatches in roundsFirstHalf) {
      roundsSecondHalf.add([
        for (final m in rMatches) (home: m.away, away: m.home),
      ]);
    }

    final allRoundsMatches = [...roundsFirstHalf, ...roundsSecondHalf];
    final seasonRounds = <SeasonRound>[];

    for (var rIdx = 0; rIdx < allRoundsMatches.length; rIdx++) {
      final roundNum = rIdx + 1;
      final matches = allRoundsMatches[rIdx];
      final fixtures = <SeasonFixture>[];

      for (var fIdx = 0; fIdx < matches.length; fIdx++) {
        final m = matches[fIdx];
        final homeTeam = teams[m.home];
        final awayTeam = teams[m.away];

        final seed = deriveGameSeed(
          leagueSeed: league.config.seed,
          homeIndex: m.home,
          awayIndex: m.away,
          rematchIndex: roundNum,
        );

        fixtures.add(
          SeasonFixture(
            roundNumber: roundNum,
            fixtureIndex: fIdx,
            id: 'round-$roundNum-game-$fIdx',
            homeTeamId: homeTeam.id,
            awayTeamId: awayTeam.id,
            seed: seed,
          ),
        );
      }

      seasonRounds.add(SeasonRound(roundNumber: roundNum, fixtures: fixtures));
    }

    return SeasonSchedule(rounds: seasonRounds);
  }

  Map<String, dynamic> toJson() => {
    'rounds': [for (final r in rounds) r.toJson()],
  };
}
