import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/ids.dart';
import '../season/season_seed.dart';

const _regularSeasonTeamCount = 30;
const _regularSeasonRoundCount = 82;
const _fixturesPerRound = 15;

String _fixtureId(String seasonId, int roundNumber, int fixturePosition) =>
    '$seasonId-r$roundNumber-f$fixturePosition';

List<String> _collectTeamIds(List<RegularSeasonRound> rounds) {
  final ids = <String>{};
  for (final round in rounds) {
    for (final fixture in round.fixtures) {
      ids
        ..add(fixture.homeTeamId.value)
        ..add(fixture.awayTeamId.value);
    }
  }
  return ids.toList()..sort();
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('Invalid schedule field: $key');
  return value;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Invalid schedule field: $key');
  return value;
}

enum RegularSeasonFixtureStatus {
  scheduled('scheduled'),
  completed('completed');

  const RegularSeasonFixtureStatus(this.jsonValue);

  final String jsonValue;

  static RegularSeasonFixtureStatus fromJson(String value) => values.firstWhere(
    (status) => status.jsonValue == value,
    orElse: () => throw FormatException('Unknown fixture status: $value'),
  );
}

final class RegularSeasonFixture {
  const RegularSeasonFixture({
    required this.id,
    required this.seasonId,
    required this.seasonYear,
    required this.roundNumber,
    required this.fixturePosition,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.gameSeed,
    required this.status,
  });

  factory RegularSeasonFixture.fromJson(Map<String, dynamic> json) =>
      RegularSeasonFixture(
        id: _requiredString(json, 'id'),
        seasonId: _requiredString(json, 'seasonId'),
        seasonYear: _requiredInt(json, 'seasonYear'),
        roundNumber: _requiredInt(json, 'roundNumber'),
        fixturePosition: _requiredInt(json, 'fixturePosition'),
        homeTeamId: TeamId(_requiredString(json, 'homeTeamId')),
        awayTeamId: TeamId(_requiredString(json, 'awayTeamId')),
        gameSeed: _requiredInt(json, 'gameSeed'),
        status: RegularSeasonFixtureStatus.fromJson(
          _requiredString(json, 'status'),
        ),
      );

  final String id;
  final String seasonId;
  final int seasonYear;
  final int roundNumber;
  final int fixturePosition;
  final TeamId homeTeamId;
  final TeamId awayTeamId;
  final int gameSeed;
  final RegularSeasonFixtureStatus status;

  Map<String, Object?> toJson() => {
    'id': id,
    'seasonId': seasonId,
    'seasonYear': seasonYear,
    'roundNumber': roundNumber,
    'fixturePosition': fixturePosition,
    'homeTeamId': homeTeamId.value,
    'awayTeamId': awayTeamId.value,
    'gameSeed': gameSeed,
    'status': status.jsonValue,
  };
}

final class RegularSeasonRound {
  RegularSeasonRound({
    required this.roundNumber,
    required List<RegularSeasonFixture> fixtures,
  }) : fixtures = List.unmodifiable(fixtures);

  factory RegularSeasonRound.fromJson(Map<String, dynamic> json) {
    final rawFixtures = json['fixtures'];
    if (rawFixtures is! List) {
      throw const FormatException('Invalid regular-season round fixtures');
    }
    return RegularSeasonRound(
      roundNumber: _requiredInt(json, 'roundNumber'),
      fixtures: [
        for (final rawFixture in rawFixtures)
          if (rawFixture is Map<String, dynamic>)
            RegularSeasonFixture.fromJson(rawFixture)
          else
            throw const FormatException('Malformed regular-season fixture'),
      ],
    );
  }

  final int roundNumber;
  final List<RegularSeasonFixture> fixtures;

  Map<String, Object?> toJson() => {
    'roundNumber': roundNumber,
    'fixtures': [for (final fixture in fixtures) fixture.toJson()],
  };
}

final class RegularSeasonSchedule {
  RegularSeasonSchedule({
    required this.seasonId,
    required this.seasonYear,
    required this.scheduleSeed,
    required List<RegularSeasonRound> rounds,
  }) : rounds = List.unmodifiable(rounds),
       _teamIds = List.unmodifiable(_collectTeamIds(rounds)) {
    validate();
  }

  factory RegularSeasonSchedule.fromJson(Map<String, dynamic> json) {
    final rawRounds = json['rounds'];
    if (rawRounds is! List) {
      throw const FormatException('Invalid regular-season schedule rounds');
    }
    return RegularSeasonSchedule(
      seasonId: _requiredString(json, 'seasonId'),
      seasonYear: _requiredInt(json, 'seasonYear'),
      scheduleSeed: _requiredInt(json, 'scheduleSeed'),
      rounds: [
        for (final rawRound in rawRounds)
          if (rawRound is Map<String, dynamic>)
            RegularSeasonRound.fromJson(rawRound)
          else
            throw const FormatException('Malformed regular-season round'),
      ],
    );
  }

  final String seasonId;
  final int seasonYear;
  final int scheduleSeed;
  final List<RegularSeasonRound> rounds;
  final List<String> _teamIds;

  int get totalFixtures =>
      rounds.fold(0, (count, round) => count + round.fixtures.length);

  int get completedGamesCount => allFixtures
      .where(
        (fixture) => fixture.status == RegularSeasonFixtureStatus.completed,
      )
      .length;

  int get remainingGamesCount => allFixtures
      .where(
        (fixture) => fixture.status == RegularSeasonFixtureStatus.scheduled,
      )
      .length;

  Iterable<RegularSeasonFixture> get allFixtures =>
      rounds.expand((round) => round.fixtures);

  String get canonicalJson => jsonEncode(toJson());

  String get fingerprint =>
      sha256.convert(utf8.encode(canonicalJson)).toString();

  RegularSeasonRound roundAt(int roundNumber) {
    if (roundNumber < 1 || roundNumber > rounds.length) {
      throw RangeError.range(roundNumber, 1, rounds.length, 'roundNumber');
    }
    return rounds[roundNumber - 1];
  }

  Iterable<RegularSeasonFixture> fixturesForTeam(TeamId teamId) {
    _requireTeam(teamId);
    return allFixtures.where(
      (fixture) => fixture.homeTeamId == teamId || fixture.awayTeamId == teamId,
    );
  }

  Iterable<RegularSeasonFixture> homeFixturesForTeam(TeamId teamId) {
    _requireTeam(teamId);
    return allFixtures.where((fixture) => fixture.homeTeamId == teamId);
  }

  Iterable<RegularSeasonFixture> awayFixturesForTeam(TeamId teamId) {
    _requireTeam(teamId);
    return allFixtures.where((fixture) => fixture.awayTeamId == teamId);
  }

  List<RegularSeasonFixture> fixturesForRound(int roundNumber) =>
      roundAt(roundNumber).fixtures;

  Iterable<RegularSeasonFixture> opponentMatchupHistory(
    TeamId firstTeamId,
    TeamId secondTeamId,
  ) {
    _requireTeam(firstTeamId);
    _requireTeam(secondTeamId);
    if (firstTeamId == secondTeamId) {
      throw ArgumentError.value(secondTeamId, 'secondTeamId', 'must differ');
    }
    return allFixtures.where(
      (fixture) =>
          (fixture.homeTeamId == firstTeamId &&
              fixture.awayTeamId == secondTeamId) ||
          (fixture.homeTeamId == secondTeamId &&
              fixture.awayTeamId == firstTeamId),
    );
  }

  RegularSeasonFixture? nextScheduledGame(TeamId teamId) {
    for (final fixture in fixturesForTeam(teamId)) {
      if (fixture.status == RegularSeasonFixtureStatus.scheduled) {
        return fixture;
      }
    }
    return null;
  }

  int remainingGamesForTeam(TeamId teamId) => fixturesForTeam(teamId)
      .where(
        (fixture) => fixture.status == RegularSeasonFixtureStatus.scheduled,
      )
      .length;

  int completedGamesForTeam(TeamId teamId) => fixturesForTeam(teamId)
      .where(
        (fixture) => fixture.status == RegularSeasonFixtureStatus.completed,
      )
      .length;

  void validateAgainst({
    required String expectedSeasonId,
    required int expectedSeasonYear,
    required int expectedScheduleSeed,
    required Iterable<TeamId> openingTeamIds,
  }) {
    if (seasonId != expectedSeasonId ||
        seasonYear != expectedSeasonYear ||
        scheduleSeed != expectedScheduleSeed) {
      throw const FormatException('Schedule identity does not match season');
    }
    final expectedIds = openingTeamIds.map((teamId) => teamId.value).toSet();
    if (expectedIds.length != _regularSeasonTeamCount ||
        expectedIds.length != _teamIds.length ||
        !expectedIds.containsAll(_teamIds)) {
      throw const FormatException(
        'Schedule franchises do not match opening identities',
      );
    }
  }

  void validate() {
    if (seasonId.trim().isEmpty ||
        seasonYear < 1 ||
        rounds.length != _regularSeasonRoundCount ||
        _teamIds.length != _regularSeasonTeamCount ||
        _teamIds.any((id) => id.trim().isEmpty)) {
      throw const FormatException('Invalid regular-season schedule identity');
    }
    final teamIdSet = _teamIds.toSet();
    final indexById = {
      for (var index = 0; index < _teamIds.length; index++)
        _teamIds[index]: index,
    };
    final homeCounts = {for (final id in _teamIds) id: 0};
    final awayCounts = {for (final id in _teamIds) id: 0};
    final opponents = {for (final id in _teamIds) id: <String, int>{}};
    final pairings = <(String, String), ({int meetings, int lowerHome})>{};
    final fixtureIds = <String>{};
    Set<(String, String)> previousRoundPairings = {};
    var fixtureCount = 0;

    for (var roundIndex = 0; roundIndex < rounds.length; roundIndex++) {
      final round = rounds[roundIndex];
      final roundNumber = roundIndex + 1;
      if (round.roundNumber != roundNumber ||
          round.fixtures.length != _fixturesPerRound) {
        throw const FormatException('Invalid regular-season round ordering');
      }
      final teamsThisRound = <String>{};
      final pairingsThisRound = <(String, String)>{};
      for (var position = 0; position < round.fixtures.length; position++) {
        final fixture = round.fixtures[position];
        final homeId = fixture.homeTeamId.value;
        final awayId = fixture.awayTeamId.value;
        if (fixture.seasonId != seasonId ||
            fixture.seasonYear != seasonYear ||
            fixture.roundNumber != roundNumber ||
            fixture.fixturePosition != position ||
            fixture.id != _fixtureId(seasonId, roundNumber, position) ||
            !fixtureIds.add(fixture.id) ||
            fixture.status != RegularSeasonFixtureStatus.scheduled ||
            homeId == awayId ||
            !teamIdSet.contains(homeId) ||
            !teamIdSet.contains(awayId) ||
            !teamsThisRound.add(homeId) ||
            !teamsThisRound.add(awayId)) {
          throw const FormatException('Invalid regular-season fixture');
        }
        final homeIndex = indexById[homeId]!;
        final awayIndex = indexById[awayId]!;
        if (fixture.gameSeed !=
            deriveGameSeed(
              leagueSeed: scheduleSeed,
              homeIndex: homeIndex,
              awayIndex: awayIndex,
              rematchIndex: roundNumber,
            )) {
          throw const FormatException('Invalid regular-season fixture seed');
        }
        final pair = homeId.compareTo(awayId) < 0
            ? (homeId, awayId)
            : (awayId, homeId);
        if (!pairingsThisRound.add(pair)) {
          throw const FormatException('Duplicate matchup within a round');
        }
        if (previousRoundPairings.contains(pair)) {
          throw const FormatException('Consecutive rematch is not allowed');
        }
        final pairCount = pairings[pair] ?? (meetings: 0, lowerHome: 0);
        pairings[pair] = (
          meetings: pairCount.meetings + 1,
          lowerHome: pairCount.lowerHome + (homeId == pair.$1 ? 1 : 0),
        );
        opponents[homeId]![awayId] = (opponents[homeId]![awayId] ?? 0) + 1;
        opponents[awayId]![homeId] = (opponents[awayId]![homeId] ?? 0) + 1;
        homeCounts[homeId] = homeCounts[homeId]! + 1;
        awayCounts[awayId] = awayCounts[awayId]! + 1;
        fixtureCount++;
      }
      if (teamsThisRound.length != _regularSeasonTeamCount) {
        throw const FormatException(
          'Franchise missing from regular-season round',
        );
      }
      previousRoundPairings = pairingsThisRound;
    }

    if (fixtureCount != 1230 || pairings.length != 435) {
      throw const FormatException('Invalid regular-season fixture total');
    }
    for (final id in _teamIds) {
      final opponentCounts = opponents[id]!.values;
      if (homeCounts[id] != 41 ||
          awayCounts[id] != 41 ||
          opponents[id]!.length != 29 ||
          opponentCounts.where((count) => count == 4).length != 12 ||
          opponentCounts.where((count) => count == 2).length != 17) {
        throw const FormatException('Invalid franchise schedule distribution');
      }
    }
    for (final entry in pairings.entries) {
      final meetings = entry.value.meetings;
      if ((meetings != 2 && meetings != 4) ||
          entry.value.lowerHome != meetings ~/ 2) {
        throw const FormatException('Invalid reciprocal matchup distribution');
      }
    }
  }

  void _requireTeam(TeamId teamId) {
    if (!_teamIds.contains(teamId.value)) {
      throw ArgumentError.value(teamId, 'teamId', 'not in this schedule');
    }
  }

  Map<String, Object?> toJson() => {
    'seasonId': seasonId,
    'seasonYear': seasonYear,
    'scheduleSeed': scheduleSeed,
    'rounds': [for (final round in rounds) round.toJson()],
  };
}
