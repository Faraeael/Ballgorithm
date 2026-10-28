import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'game_input.dart';
import 'game_versions.dart';

/// Canonical ordered UTF-8 JSON and SHA-256 input fingerprint (OD-06/A2).
abstract final class GameFingerprint {
  static Map<String, Object?> canonicalPayload(GameInput input) => {
    'fingerprintVersion': gameFingerprintVersion,
    'league': input.league.toJson(),
    'homeTeamId': input.homeTeamId.value,
    'awayTeamId': input.awayTeamId.value,
    'homeLineup': List<String>.of(input.homeLineup.playerIds),
    'awayLineup': List<String>.of(input.awayLineup.playerIds),
    'gameSeed': input.seed,
    'normalizedSeed': input.normalizedSeed,
    'rules': input.rules.toJson(),
    'versions': {
      'simulation': gameSimulationVersion,
      'rules': gameRulesVersion,
      'eventSchema': gameEventSchemaVersion,
      'prng': 'xorshift32-v1',
      'coreEngine': '1.0.0',
      'leagueSchema': 1,
    },
  };

  static String canonicalJson(GameInput input) =>
      jsonEncode(canonicalPayload(input));

  static String of(GameInput input) =>
      sha256.convert(utf8.encode(canonicalJson(input))).toString();
}
