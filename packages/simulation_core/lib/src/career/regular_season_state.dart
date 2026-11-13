import '../models/ids.dart';
import '../models/team.dart';
import '../season/season_standing.dart';
import 'regular_season_game_result.dart';
import 'regular_season_schedule.dart';

final class RegularSeasonTeamIdentity {
  const RegularSeasonTeamIdentity({
    required this.teamId,
    required this.name,
    required this.abbreviation,
  });

  factory RegularSeasonTeamIdentity.fromTeam(Team team) =>
      RegularSeasonTeamIdentity(
        teamId: team.id,
        name: team.name,
        abbreviation: team.abbreviation,
      );

  factory RegularSeasonTeamIdentity.fromJson(Map<String, dynamic> json) {
    final teamId = json['teamId'];
    final name = json['name'];
    final abbreviation = json['abbreviation'];
    if (teamId is! String || name is! String || abbreviation is! String) {
      throw const FormatException('Malformed regular-season team identity');
    }
    return RegularSeasonTeamIdentity(
      teamId: TeamId(teamId),
      name: name,
      abbreviation: abbreviation,
    );
  }

  final TeamId teamId;
  final String name;
  final String abbreviation;

  Map<String, Object?> toJson() => {
    'teamId': teamId.value,
    'name': name,
    'abbreviation': abbreviation,
  };
}

/// Persisted regular-season identity, schedule, and sole result authority.
final class RegularSeasonState {
  RegularSeasonState({
    required this.seasonId,
    required this.seasonYear,
    required this.scheduleSeed,
    required List<RegularSeasonTeamIdentity> openingTeams,
    required Map<String, RegularSeasonGameResult> gameResults,
    this.schedule,
  }) : openingTeams = List.unmodifiable(openingTeams),
       gameResults = Map.unmodifiable(gameResults) {
    validate();
  }

  factory RegularSeasonState.fromJson(
    Map<String, dynamic> json, {
    int schemaVersion = 15,
  }) {
    final seasonId = json['seasonId'];
    final seasonYear = json['seasonYear'];
    final scheduleSeed = json['scheduleSeed'];
    final rawTeams = json['openingTeams'];
    final rawResults = json['gameResults'];
    if (seasonId is! String ||
        seasonYear is! int ||
        scheduleSeed is! int ||
        rawTeams is! List ||
        rawResults is! Map<String, dynamic>) {
      throw const FormatException('Malformed regular-season state');
    }
    final RegularSeasonSchedule? schedule;
    if (schemaVersion >= 16) {
      if (!json.containsKey('schedule')) {
        throw const FormatException('Missing schedule in regular-season state');
      }
      final rawSchedule = json['schedule'];
      if (rawSchedule == null) {
        schedule = null;
      } else if (rawSchedule is Map<String, dynamic>) {
        schedule = RegularSeasonSchedule.fromJson(rawSchedule);
      } else {
        throw const FormatException('Malformed regular-season schedule');
      }
    } else {
      if (json.containsKey('schedule')) {
        throw const FormatException(
          'Schedule is not supported in regular-season state v15',
        );
      }
      schedule = null;
    }
    if (schemaVersion < 17 && rawResults.isNotEmpty) {
      throw const FormatException(
        'Pre-v17 regular-season results are not supported',
      );
    }
    final parsed = <String, RegularSeasonGameResult>{};
    for (final entry in rawResults.entries) {
      if (entry.value is! Map<String, dynamic>) {
        throw const FormatException('Malformed regular-season game result');
      }
      parsed[entry.key] = RegularSeasonGameResult.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    return RegularSeasonState(
      seasonId: seasonId,
      seasonYear: seasonYear,
      scheduleSeed: scheduleSeed,
      openingTeams: [
        for (final team in rawTeams)
          if (team is Map<String, dynamic>)
            RegularSeasonTeamIdentity.fromJson(team)
          else
            throw const FormatException('Malformed opening team identity'),
      ],
      gameResults: parsed,
      schedule: schedule,
    );
  }

  final String seasonId;
  final int seasonYear;
  final int scheduleSeed;
  final List<RegularSeasonTeamIdentity> openingTeams;
  final Map<String, RegularSeasonGameResult> gameResults;
  final RegularSeasonSchedule? schedule;
  static String seasonIdFor(String careerId, int seasonYear) =>
      '$careerId-season-$seasonYear';

  int get completedGames => gameResults.length;
  int get remainingGames => (schedule?.totalFixtures ?? 0) - completedGames;
  int get completedRounds =>
      schedule?.rounds
          .takeWhile(
            (round) => round.fixtures.every(
              (fixture) =>
                  fixture.status == RegularSeasonFixtureStatus.completed,
            ),
          )
          .length ??
      0;
  int? get nextUnfinishedRoundNumber =>
      completedRounds < (schedule?.rounds.length ?? 0)
      ? completedRounds + 1
      : null;
  int? get nextUnfinishedRound => nextUnfinishedRoundNumber;
  int gamesPlayedForTeam(TeamId teamId) =>
      schedule?.completedGamesForTeam(teamId) ?? 0;

  RegularSeasonState copyWith({
    RegularSeasonSchedule? schedule,
    Map<String, RegularSeasonGameResult>? gameResults,
  }) => RegularSeasonState(
    seasonId: seasonId,
    seasonYear: seasonYear,
    scheduleSeed: scheduleSeed,
    openingTeams: openingTeams,
    gameResults: gameResults ?? this.gameResults,
    schedule: schedule ?? this.schedule,
  );

  LeagueStandings get standings {
    var result = LeagueStandings(
      table: {
        for (final team in openingTeams)
          team.teamId.value: SeasonStanding.initial(team.teamId),
      },
    );
    final source = schedule;
    if (source != null) {
      for (final fixture in source.allFixtures) {
        final game = gameResults[fixture.id];
        if (game == null) continue;
        result = result.applyGame(
          homeId: fixture.homeTeamId,
          awayId: fixture.awayTeamId,
          homeScore: game.summary.homeScore,
          awayScore: game.summary.awayScore,
        );
      }
    }
    return result;
  }

  void validate() {
    if (seasonId.trim().isEmpty ||
        seasonYear < 1 ||
        openingTeams.length != 30) {
      throw const FormatException('Invalid regular-season identity');
    }
    final teamIds = <String>{};
    for (final team in openingTeams) {
      if (team.teamId.value.trim().isEmpty ||
          team.name.trim().isEmpty ||
          team.abbreviation.trim().isEmpty ||
          !teamIds.add(team.teamId.value)) {
        throw const FormatException('Invalid opening team identity snapshot');
      }
    }
    final generatedSchedule = schedule;
    if (generatedSchedule == null) {
      if (gameResults.isNotEmpty) {
        throw const FormatException(
          'Results require a regular-season schedule',
        );
      }
      return;
    }
    generatedSchedule.validateAgainst(
      expectedSeasonId: seasonId,
      expectedSeasonYear: seasonYear,
      expectedScheduleSeed: scheduleSeed,
      openingTeamIds: openingTeams.map((team) => team.teamId),
    );
    final fixtures = {
      for (final fixture in generatedSchedule.allFixtures) fixture.id: fixture,
    };
    if (gameResults.keys.any((id) => !fixtures.containsKey(id))) {
      throw const FormatException('Unknown regular-season result fixture');
    }
    var scheduledSeen = false;
    for (final round in generatedSchedule.rounds) {
      final complete = round.fixtures.every(
        (fixture) => fixture.status == RegularSeasonFixtureStatus.completed,
      );
      final scheduled = round.fixtures.every(
        (fixture) => fixture.status == RegularSeasonFixtureStatus.scheduled,
      );
      if (!complete && !scheduled) {
        throw const FormatException('Partial regular-season round');
      }
      if (complete && scheduledSeen) {
        throw const FormatException(
          'Noncontiguous completed regular-season rounds',
        );
      }
      if (scheduled) scheduledSeen = true;
      for (final fixture in round.fixtures) {
        final hasResult = gameResults.containsKey(fixture.id);
        if (hasResult !=
            (fixture.status == RegularSeasonFixtureStatus.completed)) {
          throw const FormatException(
            'Schedule status and result ledger disagree',
          );
        }
      }
    }
  }

  Map<String, Object?> toJson() => {
    'seasonId': seasonId,
    'seasonYear': seasonYear,
    'scheduleSeed': scheduleSeed,
    'openingTeams': [for (final team in openingTeams) team.toJson()],
    'gameResults': {
      for (final entry in gameResults.entries) entry.key: entry.value.toJson(),
    },
    'schedule': schedule?.toJson(),
  };
}
