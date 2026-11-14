import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/league.dart';
import '../models/position.dart';
import '../models/roster_category.dart';
import '../models/team.dart';
import '../simulation/game_fingerprint.dart';
import '../simulation/game_input.dart';

/// A supported historical game-input and rules profile.
final class RegularSeasonGameVersionProfile {
  const RegularSeasonGameVersionProfile({
    required this.fingerprintVersion,
    required this.simulationVersion,
    required this.rulesVersion,
    required this.eventSchemaVersion,
    required this.prngImplementationId,
    required this.coreEngineVersion,
    required this.leagueSchemaVersion,
    required this.periods,
    required this.periodSeconds,
    required this.overtimeSeconds,
    required this.maxOvertimes,
  });

  static const t03 = RegularSeasonGameVersionProfile(
    fingerprintVersion: 5,
    simulationVersion: 7,
    rulesVersion: 3,
    eventSchemaVersion: 3,
    prngImplementationId: 'xorshift32-v1',
    coreEngineVersion: '1.0.0',
    leagueSchemaVersion: 1,
    periods: 4,
    periodSeconds: 720,
    overtimeSeconds: 300,
    maxOvertimes: 10,
  );

  /// Add a profile only when its input and result contracts are supported.
  static const supported = [t03];

  final int fingerprintVersion;
  final int simulationVersion;
  final int rulesVersion;
  final int eventSchemaVersion;
  final String prngImplementationId;
  final String coreEngineVersion;
  final int leagueSchemaVersion;
  final int periods;
  final int periodSeconds;
  final int overtimeSeconds;
  final int maxOvertimes;

  static RegularSeasonGameVersionProfile? find({
    required int fingerprintVersion,
    required int simulationVersion,
    required int rulesVersion,
    required int eventSchemaVersion,
    required String prngImplementationId,
    required String coreEngineVersion,
    required int leagueSchemaVersion,
  }) {
    for (final profile in supported) {
      if (profile.fingerprintVersion == fingerprintVersion &&
          profile.simulationVersion == simulationVersion &&
          profile.rulesVersion == rulesVersion &&
          profile.eventSchemaVersion == eventSchemaVersion &&
          profile.prngImplementationId == prngImplementationId &&
          profile.coreEngineVersion == coreEngineVersion &&
          profile.leagueSchemaVersion == leagueSchemaVersion) {
        return profile;
      }
    }
    return null;
  }
}

/// Exact canonical input payload with its full game-time league stored once.
final class RegularSeasonGameInputEvidence {
  const RegularSeasonGameInputEvidence({
    required this.leagueSnapshotId,
    required this.payloadTemplateJson,
  });

  static const _markerPrefix = '__BALLGORITHM_LEAGUE_SNAPSHOT_';

  factory RegularSeasonGameInputEvidence.fromJson(Map<String, dynamic> json) {
    final snapshotId = json['leagueSnapshotId'];
    final payloadTemplateJson = json['payloadTemplateJson'];
    if (snapshotId is! String || payloadTemplateJson is! String) {
      throw const FormatException('Malformed regular-season input evidence');
    }
    return RegularSeasonGameInputEvidence(
      leagueSnapshotId: snapshotId,
      payloadTemplateJson: payloadTemplateJson,
    );
  }

  static ({RegularSeasonGameInputEvidence evidence, String leagueSnapshotJson})
  capture(GameInput input) {
    final canonicalJson = GameFingerprint.canonicalJson(input);
    final leagueJson = jsonEncode(
      GameFingerprint.canonicalPayload(input)['league'],
    );
    final leagueKey = '"league":$leagueJson';
    final leagueKeyIndex = canonicalJson.indexOf(leagueKey);
    if (leagueKeyIndex < 0 ||
        canonicalJson.indexOf(leagueKey, leagueKeyIndex + 1) >= 0) {
      throw const FormatException('Cannot isolate game-time league snapshot');
    }
    final snapshotId = sha256.convert(utf8.encode(leagueJson)).toString();
    var marker = '$_markerPrefix${snapshotId}__';
    var suffix = 0;
    while (canonicalJson.contains(jsonEncode(marker))) {
      marker = '$_markerPrefix${snapshotId}_${++suffix}__';
    }
    final leagueValueStart = leagueKeyIndex + '"league":'.length;
    final template = canonicalJson.replaceRange(
      leagueValueStart,
      leagueValueStart + leagueJson.length,
      jsonEncode(marker),
    );
    return (
      evidence: RegularSeasonGameInputEvidence(
        leagueSnapshotId: snapshotId,
        payloadTemplateJson: template,
      ),
      leagueSnapshotJson: leagueJson,
    );
  }

  final String leagueSnapshotId;
  final String payloadTemplateJson;

  Map<String, Object?> toJson() => {
    'leagueSnapshotId': leagueSnapshotId,
    'payloadTemplateJson': payloadTemplateJson,
  };
  static League parseLeagueSnapshot({
    required String snapshotId,
    required String leagueSnapshotJson,
    required Set<String> openingTeamIds,
  }) {
    if (!_isDigest(snapshotId) ||
        sha256.convert(utf8.encode(leagueSnapshotJson)).toString() !=
            snapshotId) {
      throw const FormatException('Invalid game-time league snapshot digest');
    }
    final Object? snapshotValue;
    try {
      snapshotValue = jsonDecode(leagueSnapshotJson);
    } on FormatException {
      throw const FormatException('Malformed game-time league snapshot');
    }
    if (snapshotValue is! Map<String, dynamic> ||
        jsonEncode(snapshotValue) != leagueSnapshotJson) {
      throw const FormatException('Non-canonical game-time league snapshot');
    }
    final League league;
    try {
      league = League.fromJson(
        snapshotValue.cast<String, Object?>(),
        enforceRosterSize: false,
      );
    } on Object catch (error) {
      throw FormatException('Invalid game-time league snapshot: $error');
    }
    final leagueTeamIds = league.teams.map((team) => team.id.value).toSet();
    if (league.teams.length != openingTeamIds.length ||
        !leagueTeamIds.containsAll(openingTeamIds) ||
        !openingTeamIds.containsAll(leagueTeamIds) ||
        league.teams.any(
          (team) => team.roster.categories.values.any(
            (category) => category != RosterCategory.standard,
          ),
        )) {
      throw const FormatException('Invalid historical game-time league roster');
    }
    return league;
  }

  RegularSeasonHistoricalInput validate({
    required String leagueSnapshotId,
    required String leagueSnapshotJson,
    required League league,
    required String inputFingerprint,
    required String homeTeamId,
    required String awayTeamId,
    required int gameSeed,
    required int simulationVersion,
    required int rulesVersion,
    required int eventSchemaVersion,
    required String prngImplementationId,
    required int fingerprintVersion,
    required String coreEngineVersion,
    required int leagueSchemaVersion,
  }) {
    if (this.leagueSnapshotId != leagueSnapshotId) {
      throw const FormatException('Game-input snapshot reference mismatch');
    }

    final Object? templateValue;
    try {
      templateValue = jsonDecode(payloadTemplateJson);
    } on FormatException {
      throw const FormatException('Malformed canonical game-input template');
    }
    if (templateValue is! Map<String, dynamic> ||
        jsonEncode(templateValue) != payloadTemplateJson) {
      throw const FormatException('Non-canonical game-input template');
    }
    final marker = templateValue['league'];
    if (marker is! String ||
        !marker.startsWith('$_markerPrefix$leagueSnapshotId')) {
      throw const FormatException(
        'Game-input template has invalid snapshot reference',
      );
    }
    final markerJson = jsonEncode(marker);
    if (payloadTemplateJson.split(markerJson).length != 2) {
      throw const FormatException(
        'Game-input template has duplicate snapshot markers',
      );
    }
    final templateKeys = templateValue.keys.toList();
    final expectedKeys = <String>[
      'fingerprintVersion',
      'league',
      'homeTeamId',
      'awayTeamId',
      'homeLineup',
      'awayLineup',
      'gameSeed',
      'normalizedSeed',
      'rules',
      if (templateValue.containsKey('rotationPlan')) 'rotationPlan',
      'versions',
    ];
    if (!_sameStrings(templateKeys, expectedKeys)) {
      throw const FormatException('Unsupported canonical game-input layout');
    }
    final leagueValueIndex = payloadTemplateJson.indexOf(
      '"league":$markerJson',
    );
    if (leagueValueIndex < 0) {
      throw const FormatException('Game-input snapshot marker is missing');
    }
    final leagueValueStart = leagueValueIndex + '"league":'.length;
    final canonicalPayloadJson = payloadTemplateJson.replaceRange(
      leagueValueStart,
      leagueValueStart + markerJson.length,
      leagueSnapshotJson,
    );
    final payloadValue = templateValue;
    if (sha256.convert(utf8.encode(canonicalPayloadJson)).toString() !=
        inputFingerprint) {
      throw const FormatException('Historical game-input fingerprint mismatch');
    }

    final versions = _map(payloadValue, 'versions');
    final profile = RegularSeasonGameVersionProfile.find(
      fingerprintVersion: _int(payloadValue, 'fingerprintVersion'),
      simulationVersion: _int(versions, 'simulation'),
      rulesVersion: _int(versions, 'rules'),
      eventSchemaVersion: _int(versions, 'eventSchema'),
      prngImplementationId: _string(versions, 'prng'),
      coreEngineVersion: _string(versions, 'coreEngine'),
      leagueSchemaVersion: _int(versions, 'leagueSchema'),
    );
    if (profile == null ||
        profile.simulationVersion != simulationVersion ||
        profile.rulesVersion != rulesVersion ||
        profile.eventSchemaVersion != eventSchemaVersion ||
        profile.prngImplementationId != prngImplementationId ||
        profile.fingerprintVersion != fingerprintVersion ||
        profile.coreEngineVersion != coreEngineVersion ||
        profile.leagueSchemaVersion != leagueSchemaVersion) {
      throw const FormatException(
        'Unsupported historical game version profile',
      );
    }

    final homeId = _string(payloadValue, 'homeTeamId');
    final awayId = _string(payloadValue, 'awayTeamId');
    final seed = _int(payloadValue, 'gameSeed');
    final normalizedSeed = seed & 0xFFFFFFFF;
    if (homeId != homeTeamId ||
        awayId != awayTeamId ||
        seed != gameSeed ||
        _int(payloadValue, 'normalizedSeed') !=
            (normalizedSeed == 0 ? 0x9E3779B9 : normalizedSeed)) {
      throw const FormatException('Historical game input identity mismatch');
    }

    final home = league.teams
        .where((team) => team.id.value == homeId)
        .firstOrNull;
    final away = league.teams
        .where((team) => team.id.value == awayId)
        .firstOrNull;
    if (home == null || away == null || homeId == awayId) {
      throw const FormatException('Historical game teams are missing');
    }
    final homeLineup = _lineupPlayers(_list(payloadValue, 'homeLineup'), home);
    final awayLineup = _lineupPlayers(_list(payloadValue, 'awayLineup'), away);
    if (homeLineup.intersection(awayLineup).isNotEmpty) {
      throw const FormatException('Historical lineups share a player');
    }
    final rules = _map(payloadValue, 'rules');
    if (_int(rules, 'rulesVersion') != profile.rulesVersion ||
        _int(rules, 'periods') != profile.periods ||
        _int(rules, 'periodSeconds') != profile.periodSeconds ||
        _int(rules, 'overtimeSeconds') != profile.overtimeSeconds ||
        _int(rules, 'maxOvertimes') != profile.maxOvertimes) {
      throw const FormatException('Historical game rules do not match version');
    }
    return RegularSeasonHistoricalInput(league: league, profile: profile);
  }

  static Set<String> _lineupPlayers(List<dynamic> rawSlots, Team team) {
    if (rawSlots.length != 5) {
      throw const FormatException('Historical lineup must contain five slots');
    }
    final ids = <String>{};
    final rosterIds = team.players.map((player) => player.id.value).toSet();
    for (var index = 0; index < rawSlots.length; index++) {
      final rawSlot = rawSlots[index];
      if (rawSlot is! Map<String, dynamic> ||
          rawSlot.keys.toList().join('|') != 'slot|playerId' ||
          rawSlot['slot'] != Position.values[index].shortName ||
          rawSlot['playerId'] is! String ||
          !rosterIds.contains(rawSlot['playerId']) ||
          !ids.add(rawSlot['playerId'] as String)) {
        throw const FormatException('Invalid historical lineup ownership');
      }
    }
    return ids;
  }
}

final class RegularSeasonHistoricalInput {
  const RegularSeasonHistoricalInput({
    required this.league,
    required this.profile,
  });

  final League league;
  final RegularSeasonGameVersionProfile profile;
}

final _digestPattern = RegExp(r'^[0-9a-f]{64}$');

bool _isDigest(String value) => _digestPattern.hasMatch(value);

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Map<String, dynamic> _map(Map<String, dynamic> source, String key) {
  final value = source[key];
  if (value is! Map<String, dynamic>) {
    throw FormatException('Invalid historical game field: $key');
  }
  return value;
}

List<dynamic> _list(Map<String, dynamic> source, String key) {
  final value = source[key];
  if (value is! List) {
    throw FormatException('Invalid historical game field: $key');
  }
  return value;
}

String _string(Map<String, dynamic> source, String key) {
  final value = source[key];
  if (value is! String) {
    throw FormatException('Invalid historical game field: $key');
  }
  return value;
}

int _int(Map<String, dynamic> source, String key) {
  final value = source[key];
  if (value is! int) {
    throw FormatException('Invalid historical game field: $key');
  }
  return value;
}
