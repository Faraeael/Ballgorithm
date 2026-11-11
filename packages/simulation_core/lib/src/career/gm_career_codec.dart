import 'dart:convert';

import '../generation/draft_generator.dart';
import '../models/draft_order.dart';
import '../models/franchise_situation.dart';
import '../models/ids.dart';
import '../models/league.dart';
import '../models/player_career_profile.dart';
import '../models/rookie_draft_class.dart';
import '../models/roster.dart';
import '../models/roster_category.dart';
import '../models/roster_membership.dart';
import '../models/team.dart';
import 'career_phase.dart';
import 'gm_career.dart';

/// Serialization and strict validation for persistent [GmCareer] state.
final class GmCareerCodec {
  const GmCareerCodec._();

  static const int currentSchemaVersion = 3;

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
      'draftOrder': career.draftOrder.toJson(),
      'draftClass': career.draftClass.toJson(),
      'rosterMemberships': {
        for (final team in career.league.teams)
          team.id.value: [
            for (final player in team.players)
              RosterMembership(
                playerId: player.id,
                category: team.roster.categoryOf(player.id),
              ).toJson(),
          ],
      },
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
    if (schemaVersion is! int ||
        schemaVersion < 1 ||
        schemaVersion > currentSchemaVersion) {
      throw FormatException(
        'Unsupported career schema version: $schemaVersion (supported: 1..$currentSchemaVersion)',
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
    final baseLeague = League.fromJson(rawLeague, enforceRosterSize: false);

    final rawRosterMemberships =
        raw['rosterMemberships'] as Map<String, dynamic>?;
    final leagueTeams = <Team>[];
    for (final team in baseLeague.teams) {
      final teamMembershipsRaw =
          rawRosterMemberships?[team.id.value] as List<dynamic>?;
      if (teamMembershipsRaw != null) {
        final categories = <String, RosterCategory>{};
        for (final m in teamMembershipsRaw) {
          final membership = RosterMembership.fromJson(
            m as Map<String, dynamic>,
          );
          categories[membership.playerId.value] = membership.category;
        }
        leagueTeams.add(
          team.copyWith(roster: Roster(team.players, categories: categories)),
        );
      } else {
        leagueTeams.add(team);
      }
    }
    final league = League.create(
      id: baseLeague.id,
      name: baseLeague.name,
      config: baseLeague.config,
      teams: leagueTeams,
      enforceRosterSize: false,
    );
    final rawCareerProfiles = raw['careerProfiles'];
    if (rawCareerProfiles is! Map<String, dynamic>) {
      throw const FormatException(
        'Missing or invalid careerProfiles in career JSON',
      );
    }
    final careerProfiles = LeagueCareerProfiles.fromJson(rawCareerProfiles);

    final DraftOrder draftOrder;
    final rawDraftOrder = raw['draftOrder'];
    if (rawDraftOrder != null && rawDraftOrder is Map<String, dynamic>) {
      draftOrder = DraftOrder.fromJson(rawDraftOrder);
    } else {
      if (schemaVersion >= 2) {
        throw const FormatException(
          'Missing or invalid draftOrder in career JSON v2',
        );
      }
      draftOrder = const DraftGenerator().generateDraftOrder(
        league: league,
        seed: generationSeed,
        userTeamId: userFranchiseId,
        userSituation: originalSituation,
      );
    }

    final RookieDraftClass draftClass;
    final rawDraftClass = raw['draftClass'];
    if (rawDraftClass != null && rawDraftClass is Map<String, dynamic>) {
      draftClass = RookieDraftClass.fromJson(rawDraftClass);
    } else {
      if (schemaVersion >= 2) {
        throw const FormatException(
          'Missing or invalid draftClass in career JSON v2',
        );
      }
      draftClass = const DraftGenerator().generateDraftClass(
        league: league,
        seed: generationSeed,
        seasonYear: currentYear,
      );
    }

    final career = GmCareer(
      id: id,
      schemaVersion: currentSchemaVersion,
      generationSeed: generationSeed,
      userFranchiseId: userFranchiseId,
      originalSituation: originalSituation,
      currentYear: currentYear,
      phase: phase,
      league: league,
      careerProfiles: careerProfiles,
      userOpeningDraftPick: userOpeningDraftPick,
      draftOrder: draftOrder,
      draftClass: draftClass,
    );
    career.validate();
    return career;
  }
}
