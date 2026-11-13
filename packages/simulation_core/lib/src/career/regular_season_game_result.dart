import '../domain_versions.dart' as versions;
import '../models/ids.dart';
import '../season/season_fixture.dart';
import '../simulation/game_rules.dart';
import '../simulation/game_versions.dart';
import 'regular_season_schedule.dart';

final _fingerprintPattern = RegExp(r'^[0-9a-f]{64}$');

/// Immutable fixture-bound result persisted by a regular-season career.
final class RegularSeasonGameResult {
  const RegularSeasonGameResult({
    required this.fixtureId,
    required this.seasonId,
    required this.seasonYear,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.gameSeed,
    required this.inputFingerprint,
    required this.simulationVersion,
    required this.rulesVersion,
    required this.eventSchemaVersion,
    required this.prngImplementationId,
    required this.periodsPlayed,
    required this.summary,
  });

  factory RegularSeasonGameResult.fromJson(Map<String, dynamic> json) =>
      RegularSeasonGameResult(
        fixtureId: _string(json, 'fixtureId'),
        seasonId: _string(json, 'seasonId'),
        seasonYear: _int(json, 'seasonYear'),
        homeTeamId: TeamId(_string(json, 'homeTeamId')),
        awayTeamId: TeamId(_string(json, 'awayTeamId')),
        gameSeed: _int(json, 'gameSeed'),
        inputFingerprint: _string(json, 'inputFingerprint'),
        simulationVersion: _int(json, 'simulationVersion'),
        rulesVersion: _int(json, 'rulesVersion'),
        eventSchemaVersion: _int(json, 'eventSchemaVersion'),
        prngImplementationId: _string(json, 'prngImplementationId'),
        periodsPlayed: _int(json, 'periodsPlayed'),
        summary: SeasonGameSummary.fromJson(_map(json, 'summary')),
      );

  final String fixtureId;
  final String seasonId;
  final int seasonYear;
  final TeamId homeTeamId;
  final TeamId awayTeamId;
  final int gameSeed;
  final String inputFingerprint;
  final int simulationVersion;
  final int rulesVersion;
  final int eventSchemaVersion;
  final String prngImplementationId;
  final int periodsPlayed;
  final SeasonGameSummary summary;

  Map<String, Object?> toJson() => {
    'fixtureId': fixtureId,
    'seasonId': seasonId,
    'seasonYear': seasonYear,
    'homeTeamId': homeTeamId.value,
    'awayTeamId': awayTeamId.value,
    'gameSeed': gameSeed,
    'inputFingerprint': inputFingerprint,
    'simulationVersion': simulationVersion,
    'rulesVersion': rulesVersion,
    'eventSchemaVersion': eventSchemaVersion,
    'prngImplementationId': prngImplementationId,
    'periodsPlayed': periodsPlayed,
    'summary': summary.toJson(),
  };

  void validateFor({
    required RegularSeasonFixture fixture,
    required String expectedSeasonId,
    required int expectedSeasonYear,
    required Set<String> standardPlayers,
    required Map<String, String> playerTeams,
  }) {
    if (fixtureId != fixture.id ||
        seasonId != expectedSeasonId ||
        seasonYear != expectedSeasonYear ||
        fixture.seasonId != seasonId ||
        fixture.seasonYear != seasonYear ||
        homeTeamId != fixture.homeTeamId ||
        awayTeamId != fixture.awayTeamId ||
        gameSeed != fixture.gameSeed ||
        !_fingerprintPattern.hasMatch(inputFingerprint) ||
        simulationVersion != gameSimulationVersion ||
        rulesVersion != gameRulesVersion ||
        eventSchemaVersion != gameEventSchemaVersion ||
        prngImplementationId != versions.prngImplementationId ||
        periodsPlayed < 4 ||
        periodsPlayed > 4 + GameRules.standard.maxOvertimes) {
      throw const FormatException('Regular-season result identity mismatch');
    }
    final s = summary;
    if (s.homeScore < 0 ||
        s.awayScore < 0 ||
        s.homeScore == s.awayScore ||
        s.winnerTeamId !=
            (s.homeScore > s.awayScore ? homeTeamId : awayTeamId)) {
      throw const FormatException('Invalid regular-season result score');
    }
    final expectedPeriods = <String>[
      for (var i = 1; i <= periodsPlayed; i++) i <= 4 ? 'Q$i' : 'OT${i - 4}',
    ];
    if (s.periodScoresHome.keys.toList().join('|') !=
            expectedPeriods.join('|') ||
        s.periodScoresAway.keys.toList().join('|') !=
            expectedPeriods.join('|') ||
        s.periodScoresHome.values.any((score) => score < 0) ||
        s.periodScoresAway.values.any((score) => score < 0) ||
        s.periodScoresHome.values.fold<int>(0, (a, b) => a + b) !=
            s.homeScore ||
        s.periodScoresAway.values.fold<int>(0, (a, b) => a + b) !=
            s.awayScore) {
      throw const FormatException('Invalid regular-season period scores');
    }
    var duration = 0;
    for (var period = 1; period <= periodsPlayed; period++) {
      duration += GameRules.standard.periodLength(period);
    }
    var homePoints = 0;
    var awayPoints = 0;
    for (final entry in s.playerLines.entries) {
      final line = entry.value;
      final teamId = playerTeams[line.playerId];
      if (entry.key != line.playerId ||
          !standardPlayers.contains(line.playerId) ||
          teamId != line.teamId ||
          (line.teamId != homeTeamId.value &&
              line.teamId != awayTeamId.value) ||
          line.secondsPlayed < 0 ||
          line.secondsPlayed > duration ||
          [
            line.points,
            line.fgm,
            line.fga,
            line.threePm,
            line.threePa,
            line.ftm,
            line.fta,
            line.oreb,
            line.dreb,
            line.rebounds,
            line.assists,
            line.steals,
            line.blocks,
            line.turnovers,
            line.personalFouls,
          ].any((value) => value < 0) ||
          line.threePm > line.threePa ||
          line.threePm > line.fgm ||
          line.fgm > line.fga ||
          line.threePa > line.fga ||
          line.ftm > line.fta ||
          line.rebounds != line.oreb + line.dreb ||
          line.points != (2 * line.fgm + line.threePm + line.ftm)) {
        throw const FormatException('Invalid regular-season player line');
      }
      if (line.teamId == homeTeamId.value) {
        homePoints += line.points;
      } else {
        awayPoints += line.points;
      }
    }
    if (homePoints != s.homeScore || awayPoints != s.awayScore) {
      throw const FormatException(
        'Regular-season box score does not reconcile',
      );
    }
  }
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Invalid result field: $key');
  return value;
}

int _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('Invalid result field: $key');
  return value;
}

Map<String, dynamic> _map(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map<String, dynamic>) {
    throw FormatException('Invalid result field: $key');
  }
  return value;
}
