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

    // Extract redundant inline roster categories from rawLeague if present
    final rawTeamsList = rawLeague['teams'];
    final rawInlineCategoriesByTeam = <String, Map<String, dynamic>>{};
    if (rawTeamsList is List<dynamic>) {
      for (final rawTeam in rawTeamsList) {
        if (rawTeam is Map<String, dynamic>) {
          final tId = rawTeam['id'] as String?;
          final rawRoster = rawTeam['roster'];
          if (tId != null && rawRoster is Map<String, dynamic>) {
            final rawCats = rawRoster['categories'];
            if (rawCats is Map<String, dynamic>) {
              rawInlineCategoriesByTeam[tId] = rawCats;
            }
          }
        }
      }
    }

    final rawRosterMemberships = raw['rosterMemberships'];
    final leagueTeams = <Team>[];

    if (schemaVersion >= 3) {
      if (rawRosterMemberships == null ||
          rawRosterMemberships is! Map<String, dynamic>) {
        throw const FormatException(
          'Missing or invalid rosterMemberships in career JSON v3',
        );
      }
    }

    if (rawRosterMemberships != null) {
      if (rawRosterMemberships is! Map<String, dynamic>) {
        throw const FormatException(
          'Invalid rosterMemberships in career JSON: expected Map',
        );
      }

      // Reject membership entries referencing nonexistent franchises
      final validTeamIds = {for (final t in baseLeague.teams) t.id.value};
      for (final key in rawRosterMemberships.keys) {
        if (!validTeamIds.contains(key)) {
          throw FormatException('Unknown franchise $key in rosterMemberships');
        }
      }

      for (final team in baseLeague.teams) {
        final teamMembershipsRaw = rawRosterMemberships[team.id.value];
        if (teamMembershipsRaw == null) {
          if (schemaVersion >= 3) {
            throw FormatException(
              'Missing rosterMemberships entry for franchise ${team.id.value}',
            );
          }
          leagueTeams.add(team);
          continue;
        }

        if (teamMembershipsRaw is! List<dynamic>) {
          throw FormatException(
            'Invalid rosterMemberships list for franchise ${team.id.value}',
          );
        }

        final teamPlayerIds = {for (final p in team.players) p.id.value};
        final seenPlayerIds = <String>{};
        final categories = <String, RosterCategory>{};

        for (var i = 0; i < teamMembershipsRaw.length; i++) {
          final m = teamMembershipsRaw[i];
          if (m is! Map<String, dynamic>) {
            throw FormatException(
              'Malformed membership entry at index $i for franchise ${team.id.value}',
            );
          }
          final membership = RosterMembership.fromJson(m);
          final pid = membership.playerId.value;

          if (!teamPlayerIds.contains(pid)) {
            throw FormatException(
              'Player $pid in rosterMemberships does not belong to franchise ${team.id.value}',
            );
          }

          if (!seenPlayerIds.add(pid)) {
            throw FormatException(
              'Duplicate roster membership entry for player $pid in franchise ${team.id.value}',
            );
          }

          categories[pid] = membership.category;
        }

        // Require exactly one membership entry for each contracted player
        for (final player in team.players) {
          if (!seenPlayerIds.contains(player.id.value)) {
            throw FormatException(
              'Missing roster membership entry for player ${player.id.value} in franchise ${team.id.value}',
            );
          }
        }

        // Reconcile and validate consistency with redundant league.teams[].roster.categories if present
        final inlineCategories = rawInlineCategoriesByTeam[team.id.value];
        if (inlineCategories != null) {
          for (final entry in inlineCategories.entries) {
            final pid = entry.key;
            final rawCat = entry.value as String?;
            if (!teamPlayerIds.contains(pid)) {
              throw FormatException(
                'Inline category references unknown player $pid on franchise ${team.id.value}',
              );
            }
            final expectedCat = categories[pid];
            if (rawCat != expectedCat?.jsonValue) {
              throw FormatException(
                'Conflicting roster categories for player $pid on franchise ${team.id.value}: '
                'inline=$rawCat vs rosterMemberships=${expectedCat?.jsonValue}',
              );
            }
          }
        }

        leagueTeams.add(
          team.copyWith(roster: Roster(team.players, categories: categories)),
        );
      }
    } else {
      for (final team in baseLeague.teams) {
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
