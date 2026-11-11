import 'dart:convert';

import '../models/franchise_situation.dart';
import '../models/ids.dart';
import '../models/league.dart';
import '../models/player_career_profile.dart';
import 'career_phase.dart';
import 'gm_career.dart';

/// Serialization and strict validation for persistent [GmCareer] state.
final class GmCareerCodec {
  const GmCareerCodec._();

  static const int currentSchemaVersion = 1;

  /// Serializes a validated [GmCareer] into a canonical JSON string.
  static String encode(GmCareer career) {
    career.validate();
    final map = <String, dynamic>{
      'schemaVersion': career.schemaVersion,
      'id': career.id,
      'generationSeed': career.generationSeed,
      'userFranchiseId': career.userFranchiseId.value,
      'originalSituation': career.originalSituation.jsonValue,
      'currentYear': career.currentYear,
      'phase': career.phase.jsonValue,
      'userOpeningDraftPick': career.userOpeningDraftPick,
      'league': career.league.toJson(),
      'careerProfiles': career.careerProfiles.toJson(),
    };
    return jsonEncode(map);
  }

  /// Deserializes and validates a [GmCareer] from a JSON string.
  ///
  /// Reconstructs the saved league snapshot and player career profiles exactly,
  /// without re-generating from seed.
  static GmCareer decode(String jsonString) {
    final dynamic raw;
    try {
      raw = jsonDecode(jsonString);
    } catch (e) {
      throw FormatException('Failed to parse career JSON: $e');
    }

    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid career JSON format: expected Map');
    }

    final schemaVersion = raw['schemaVersion'];
    if (schemaVersion is! int || schemaVersion != currentSchemaVersion) {
      throw FormatException(
        'Unsupported career schema version: $schemaVersion (supported: $currentSchemaVersion)',
      );
    }

    final id = raw['id'] as String?;
    if (id == null || id.trim().isEmpty) {
      throw const FormatException('Missing or empty career id in career JSON');
    }

    final generationSeed = raw['generationSeed'] as int?;
    if (generationSeed == null) {
      throw const FormatException('Missing generationSeed in career JSON');
    }

    final rawUserFranchiseId = raw['userFranchiseId'] as String?;
    if (rawUserFranchiseId == null || rawUserFranchiseId.trim().isEmpty) {
      throw const FormatException(
        'Missing or empty userFranchiseId in career JSON',
      );
    }
    final userFranchiseId = TeamId(rawUserFranchiseId);

    final rawOriginalSituation = raw['originalSituation'] as String?;
    if (rawOriginalSituation == null) {
      throw const FormatException('Missing originalSituation in career JSON');
    }
    final originalSituation = FranchiseSituation.fromJson(rawOriginalSituation);

    final currentYear = raw['currentYear'] as int?;
    if (currentYear == null || currentYear < 1) {
      throw FormatException('Invalid currentYear in career JSON: $currentYear');
    }

    final rawPhase = raw['phase'] as String?;
    if (rawPhase == null) {
      throw const FormatException('Missing phase in career JSON');
    }
    final phase = CareerPhase.fromJson(rawPhase);

    final userOpeningDraftPick = raw['userOpeningDraftPick'] as int?;
    if (userOpeningDraftPick == null) {
      throw const FormatException(
        'Missing userOpeningDraftPick in career JSON',
      );
    }

    final rawLeague = raw['league'];
    if (rawLeague is! Map<String, dynamic>) {
      throw const FormatException('Missing or invalid league in career JSON');
    }
    final league = League.fromJson(rawLeague);

    final rawCareerProfiles = raw['careerProfiles'];
    if (rawCareerProfiles is! Map<String, dynamic>) {
      throw const FormatException(
        'Missing or invalid careerProfiles in career JSON',
      );
    }
    final careerProfiles = LeagueCareerProfiles.fromJson(rawCareerProfiles);

    final career = GmCareer(
      id: id,
      schemaVersion: schemaVersion,
      generationSeed: generationSeed,
      userFranchiseId: userFranchiseId,
      originalSituation: originalSituation,
      currentYear: currentYear,
      phase: phase,
      league: league,
      careerProfiles: careerProfiles,
      userOpeningDraftPick: userOpeningDraftPick,
    );
    career.validate();
    return career;
  }
}
