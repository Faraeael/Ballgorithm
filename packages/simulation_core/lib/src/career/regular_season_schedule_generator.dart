import 'dart:convert';

import '../generation/deterministic_random.dart';
import '../models/ids.dart';
import '../season/season_seed.dart';
import 'regular_season_schedule.dart';
import 'regular_season_state.dart';

const _teamCount = 30;
const _roundRobinRoundCount = 29;
const _repeatRoundCount = 12;
typedef _RoundSpec = ({int pairingRoundIndex, bool reverseHomeAway});

/// Builds the owner-approved deterministic 30-franchise regular-season schedule.
final class RegularSeasonScheduleGenerator {
  const RegularSeasonScheduleGenerator();

  RegularSeasonSchedule generate({
    required String seasonId,
    required int seasonYear,
    required int scheduleSeed,
    required List<RegularSeasonTeamIdentity> openingTeams,
  }) {
    if (seasonId.trim().isEmpty || seasonYear < 1) {
      throw const FormatException('Invalid season identity for schedule');
    }
    if (openingTeams.length != _teamCount) {
      throw ArgumentError.value(
        openingTeams.length,
        'openingTeams.length',
        'regular-season schedule requires exactly 30 franchises',
      );
    }
    final teamIds = [for (final team in openingTeams) team.teamId.value]
      ..sort();
    if (teamIds.any((id) => id.trim().isEmpty) ||
        teamIds.toSet().length != _teamCount) {
      throw ArgumentError('Opening team IDs must be unique and nonempty');
    }

    final indexById = {
      for (var index = 0; index < teamIds.length; index++)
        teamIds[index]: index,
    };
    final pairingRounds = _roundRobinPairings();
    final selectedRoundIndices = List<int>.generate(
      _roundRobinRoundCount,
      (index) => index,
    );
    DeterministicRandom(scheduleSeed).shuffle(selectedRoundIndices);
    final selected = selectedRoundIndices.take(_repeatRoundCount).toList();

    final roundSpecs = <_RoundSpec>[
      for (var index = 0; index < _roundRobinRoundCount; index++)
        (pairingRoundIndex: index, reverseHomeAway: false),
      for (var index = 0; index < _roundRobinRoundCount; index++)
        (pairingRoundIndex: index, reverseHomeAway: true),
      for (final index in selected)
        (pairingRoundIndex: index, reverseHomeAway: false),
      for (final index in selected)
        (pairingRoundIndex: index, reverseHomeAway: true),
    ];
    final orderedRoundSpecs = _orderRounds(roundSpecs, pairingRounds);
    final rounds = <RegularSeasonRound>[];
    void appendRound(_RoundSpec roundSpec) {
      final roundNumber = rounds.length + 1;
      final fixtures = <RegularSeasonFixture>[];
      final pairings = pairingRounds[roundSpec.pairingRoundIndex];
      for (var position = 0; position < pairings.length; position++) {
        final (lowerIndex, higherIndex) = pairings[position];
        final lowerIsHome =
            (roundSpec.pairingRoundIndex + lowerIndex + higherIndex).isEven;
        final originalHomeIndex = lowerIsHome ? lowerIndex : higherIndex;
        final originalAwayIndex = lowerIsHome ? higherIndex : lowerIndex;
        final homeIndex = roundSpec.reverseHomeAway
            ? originalAwayIndex
            : originalHomeIndex;
        final awayIndex = roundSpec.reverseHomeAway
            ? originalHomeIndex
            : originalAwayIndex;
        final homeTeamId = TeamId(teamIds[homeIndex]);
        final awayTeamId = TeamId(teamIds[awayIndex]);
        fixtures.add(
          RegularSeasonFixture(
            id: '$seasonId-r$roundNumber-f$position',
            seasonId: seasonId,
            seasonYear: seasonYear,
            roundNumber: roundNumber,
            fixturePosition: position,
            homeTeamId: homeTeamId,
            awayTeamId: awayTeamId,
            gameSeed: deriveGameSeed(
              leagueSeed: scheduleSeed,
              homeIndex: indexById[homeTeamId.value]!,
              awayIndex: indexById[awayTeamId.value]!,
              rematchIndex: roundNumber,
            ),
            status: RegularSeasonFixtureStatus.scheduled,
          ),
        );
      }
      rounds.add(
        RegularSeasonRound(roundNumber: roundNumber, fixtures: fixtures),
      );
    }

    for (final roundSpec in orderedRoundSpecs) {
      appendRound(roundSpec);
    }

    return RegularSeasonSchedule(
      seasonId: seasonId,
      seasonYear: seasonYear,
      scheduleSeed: scheduleSeed,
      rounds: rounds,
    );
  }

  static List<_RoundSpec> _orderRounds(
    List<_RoundSpec> candidates,
    List<List<(int, int)>> pairings,
  ) {
    final remaining = List<_RoundSpec>.of(candidates);
    final ordered = <_RoundSpec>[];
    int? previousPairingRoundIndex;
    List<bool>? previousHomeAssignments;
    while (remaining.isNotEmpty) {
      var selectedIndex = -1;
      var lowestVenueRepeats = _teamCount + 1;
      for (var index = 0; index < remaining.length; index++) {
        final candidate = remaining[index];
        if (candidate.pairingRoundIndex == previousPairingRoundIndex) {
          continue;
        }
        final homeAssignments = _homeAssignments(candidate, pairings);
        var venueRepeats = 0;
        if (previousHomeAssignments != null) {
          for (var teamIndex = 0; teamIndex < _teamCount; teamIndex++) {
            if (homeAssignments[teamIndex] ==
                previousHomeAssignments[teamIndex]) {
              venueRepeats++;
            }
          }
        }
        if (venueRepeats < lowestVenueRepeats) {
          selectedIndex = index;
          lowestVenueRepeats = venueRepeats;
        }
      }
      if (selectedIndex < 0) {
        throw StateError(
          'Unable to order schedule without a consecutive rematch',
        );
      }
      final selected = remaining.removeAt(selectedIndex);
      ordered.add(selected);
      previousPairingRoundIndex = selected.pairingRoundIndex;
      previousHomeAssignments = _homeAssignments(selected, pairings);
    }
    return ordered;
  }

  static List<bool> _homeAssignments(
    _RoundSpec roundSpec,
    List<List<(int, int)>> pairings,
  ) {
    final assignments = List<bool>.filled(_teamCount, false);
    for (final (lowerIndex, higherIndex)
        in pairings[roundSpec.pairingRoundIndex]) {
      final lowerIsHome =
          (roundSpec.pairingRoundIndex + lowerIndex + higherIndex).isEven;
      final originalHomeIndex = lowerIsHome ? lowerIndex : higherIndex;
      final originalAwayIndex = lowerIsHome ? higherIndex : lowerIndex;
      assignments[roundSpec.reverseHomeAway
              ? originalAwayIndex
              : originalHomeIndex] =
          true;
    }
    return assignments;
  }

  static void validateCanonical({
    required RegularSeasonSchedule schedule,
    required List<RegularSeasonTeamIdentity> openingTeams,
  }) {
    final expected = RegularSeasonScheduleGenerator().generate(
      seasonId: schedule.seasonId,
      seasonYear: schedule.seasonYear,
      scheduleSeed: schedule.scheduleSeed,
      openingTeams: openingTeams,
    );
    final normalized = schedule.toJson();
    final rounds = normalized['rounds'] as List<Map<String, Object?>>;
    for (final round in rounds) {
      final fixtures = round['fixtures'] as List<Map<String, Object?>>;
      for (final fixture in fixtures) {
        fixture['status'] = RegularSeasonFixtureStatus.scheduled.jsonValue;
      }
    }
    if (jsonEncode(normalized) != expected.canonicalJson) {
      throw const FormatException(
        'Persisted regular-season schedule differs from seeded generation',
      );
    }
  }

  static List<List<(int, int)>> _roundRobinPairings() {
    final rotation = List<int>.generate(_teamCount - 1, (index) => index + 1);
    final rounds = <List<(int, int)>>[];
    for (var roundIndex = 0; roundIndex < _roundRobinRoundCount; roundIndex++) {
      final pairings = <(int, int)>[(0, rotation.last)];
      for (var index = 0; index < (_teamCount - 2) ~/ 2; index++) {
        pairings.add((rotation[index], rotation[rotation.length - 2 - index]));
      }
      pairings.sort((first, second) {
        final lowOrder = first.$1.compareTo(second.$1);
        return lowOrder != 0 ? lowOrder : first.$2.compareTo(second.$2);
      });
      rounds.add(pairings);
      final last = rotation.removeLast();
      rotation.insert(0, last);
    }
    return rounds;
  }
}
