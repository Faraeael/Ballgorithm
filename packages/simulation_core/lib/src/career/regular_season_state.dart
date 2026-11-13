import '../models/ids.dart';
import '../models/team.dart';
import '../season/season_fixture.dart';
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

/// Minimal persisted entry state; T01 creates no fixtures or game results.
final class RegularSeasonState {
  RegularSeasonState({
    required this.seasonId,
    required this.seasonYear,
    required this.scheduleSeed,
    required List<RegularSeasonTeamIdentity> openingTeams,
    required Map<String, SeasonGameSummary> gameResults,
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
    final parsedResults = <String, SeasonGameSummary>{};
    for (final entry in rawResults.entries) {
      if (entry.value is! Map<String, dynamic>) {
        throw const FormatException('Malformed regular-season game result');
      }
      parsedResults[entry.key] = SeasonGameSummary.fromJson(
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
      gameResults: parsedResults,
      schedule: schedule,
    );
  }

  final String seasonId;
  final int seasonYear;
  final int scheduleSeed;
  final List<RegularSeasonTeamIdentity> openingTeams;
  final Map<String, SeasonGameSummary> gameResults;
  final RegularSeasonSchedule? schedule;
  static String seasonIdFor(String careerId, int seasonYear) =>
      '$careerId-season-$seasonYear';

  int get completedGames => gameResults.length;
  RegularSeasonState copyWith({RegularSeasonSchedule? schedule}) =>
      RegularSeasonState(
        seasonId: seasonId,
        seasonYear: seasonYear,
        scheduleSeed: scheduleSeed,
        openingTeams: openingTeams,
        gameResults: gameResults,
        schedule: schedule ?? this.schedule,
      );

  void validate() {
    if (seasonId.trim().isEmpty || seasonYear < 1) {
      throw const FormatException('Invalid regular-season identity');
    }
    if (openingTeams.length != 30) {
      throw FormatException(
        'Regular-season state requires 30 opening teams, found ${openingTeams.length}',
      );
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
    if (gameResults.isNotEmpty) {
      throw const FormatException(
        'T01 regular-season entry must begin with an empty game ledger',
      );
    }
    final generatedSchedule = schedule;
    if (generatedSchedule != null) {
      generatedSchedule.validateAgainst(
        expectedSeasonId: seasonId,
        expectedSeasonYear: seasonYear,
        expectedScheduleSeed: scheduleSeed,
        openingTeamIds: openingTeams.map((team) => team.teamId),
      );
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
