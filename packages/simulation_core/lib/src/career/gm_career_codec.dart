import 'dart:convert';

import '../generation/draft_generator.dart';
import '../models/draft_execution_state.dart';
import '../models/draft_order.dart';
import '../models/draft_rights.dart';
import '../models/carried_unsigned_prospect.dart';
import '../models/franchise_situation.dart';
import '../models/ids.dart';
import '../models/league.dart';
import '../models/player_career_profile.dart';
import '../models/rookie_draft_class.dart';
import '../models/rookie_signing_ledger.dart';
import '../models/ai_rookie_signing.dart';
import '../models/free_agent.dart';
import '../models/free_agent_market.dart';
import '../models/free_agent_offer.dart';
import '../models/offseason_clearance.dart';
import '../models/hardship_settlement.dart';
import '../models/roster.dart';
import '../models/roster_category.dart';
import '../models/roster_membership.dart';
import '../models/team.dart';
import '../generation/free_agent_generator.dart';
import '../finance/career_finances.dart';
import '../simulation/game_fingerprint.dart';
import 'regular_season_game_adapter.dart';
import 'regular_season_game_input_evidence.dart';
import 'regular_season_game_result.dart';
import 'career_phase.dart';
import 'offseason_readiness_gate.dart';
import 'play_in_state.dart';
import 'playoff_state.dart';
import 'regular_season_state.dart';
import 'retired_player_record.dart';
import 'season_history_record.dart';
import 'season_market_history_record.dart';
import 'season_settlement_record.dart';
import 'gm_career.dart';

/// Serialization and strict validation for persistent [GmCareer] state.
final class GmCareerCodec {
  const GmCareerCodec._();

  static const int currentSchemaVersion = 25;

  /// Serializes a validated [GmCareer] into a canonical JSON string.
  static String encode(GmCareer career) {
    _validateNativeCareer(career);
    final map = <String, dynamic>{
      'schemaVersion': currentSchemaVersion,
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
      'draftExecutionState': career.draftExecutionState.toJson(),
      'rookieSigningLedger': career.rookieSigningLedger.toJson(),
      'aiRookieSigning': career.aiRookieSigning.toJson(),
      'freeAgentPool': career.freeAgentPool.toJson(),
      'freeAgentOffers': career.freeAgentOffers.toJson(),
      'freeAgentMarket': career.freeAgentMarket.toJson(),
      'offseasonClearance': career.offseasonClearance.toJson(),
      'hardshipSettlement': career.hardshipSettlement.toJson(),
      'regularSeasonState': career.regularSeasonState?.toJson(),
      'playInState': career.playInState?.toJson(),
      'playoffState': career.playoffState?.toJson(),
      'finances': career.finances.toJson(),
      'seasonHistory': [
        for (final record in career.seasonHistory) record.toJson(),
      ],
      'retiredPlayers': [
        for (final retired in career.retiredPlayers) retired.toJson(),
      ],
      'seasonSettlements': [
        for (final settlement in career.seasonSettlements) settlement.toJson(),
      ],
      'careerDraftRights': {
        for (final key in career.careerDraftRights.keys.toList()..sort())
          key: career.careerDraftRights[key]!.toJson(),
      },
      'carriedUnsignedProspects': {
        for (final key in career.carriedUnsignedProspects.keys.toList()..sort())
          key: career.carriedUnsignedProspects[key]!.toJson(),
      },
      'marketHistory': [
        for (final record in career.marketHistory) record.toJson(),
      ],
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
    final baseLeague = League.fromJson(
      rawLeague,
      enforceRosterSize: false,
      enforcePositionCoverage: phase != CareerPhase.openingOffseason,
    );

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
      enforcePositionCoverage: phase != CareerPhase.openingOffseason,
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
    final DraftExecutionState draftExecutionState;
    final rawDraftExecutionState = raw['draftExecutionState'];
    if (schemaVersion >= 4 && rawDraftExecutionState is Map<String, dynamic>) {
      draftExecutionState = DraftExecutionState.fromJson(
        rawDraftExecutionState,
      );
    } else {
      if (schemaVersion >= 4) {
        throw const FormatException(
          'Missing or invalid draftExecutionState in career JSON v4',
        );
      }
      draftExecutionState = DraftExecutionState.initial();
    }

    final RookieSigningLedger rookieSigningLedger;
    final rawRookieSigningLedger = raw['rookieSigningLedger'];
    if (schemaVersion >= 5) {
      if (rawRookieSigningLedger is! Map<String, dynamic>) {
        throw const FormatException(
          'Missing or invalid rookieSigningLedger in career JSON v5',
        );
      }
      rookieSigningLedger = RookieSigningLedger.fromJson(
        rawRookieSigningLedger,
      );
    } else {
      rookieSigningLedger = RookieSigningLedger.empty();
    }

    final AiRookieSigningState aiRookieSigning;
    final rawAiRookieSigning = raw['aiRookieSigning'];
    if (schemaVersion >= 6) {
      if (rawAiRookieSigning is! Map<String, dynamic>) {
        throw const FormatException(
          'Missing or invalid aiRookieSigning in career JSON v6',
        );
      }
      aiRookieSigning = AiRookieSigningState.fromJson(rawAiRookieSigning);
    } else {
      aiRookieSigning = AiRookieSigningState.empty();
    }

    final FreeAgentPool freeAgentPool;
    final rawFreeAgentPool = raw['freeAgentPool'];
    if (schemaVersion >= 7) {
      if (rawFreeAgentPool is! Map<String, dynamic>) {
        throw const FormatException(
          'Missing or invalid freeAgentPool in career JSON v7',
        );
      }
      if (schemaVersion >= 9 &&
          (!rawFreeAgentPool.containsKey('initialPlayerIds') ||
              !rawFreeAgentPool.containsKey('acquisitions'))) {
        throw const FormatException(
          'Missing free-agent identity snapshot or acquisition ledger in '
          'career JSON v9',
        );
      }
      if (schemaVersion >= 22 && !rawFreeAgentPool.containsKey('seasonYear')) {
        throw const FormatException(
          'Missing seasonYear in freeAgentPool in career JSON v22',
        );
      }
      freeAgentPool = FreeAgentPool.fromJson(
        rawFreeAgentPool,
        fallbackSeasonYear: currentYear,
      );
    } else {
      freeAgentPool = const FreeAgentGenerator().generate(seed: generationSeed);
    }

    final FreeAgentOfferLedger freeAgentOffers;
    final rawFreeAgentOffers = raw['freeAgentOffers'];
    if (schemaVersion >= 10) {
      if (rawFreeAgentOffers is! Map<String, dynamic>) {
        throw const FormatException(
          'Missing or invalid freeAgentOffers in career JSON v10',
        );
      }
      freeAgentOffers = FreeAgentOfferLedger.fromJson(rawFreeAgentOffers);
    } else {
      freeAgentOffers = FreeAgentOfferLedger.empty();
    }

    final FreeAgentMarketState freeAgentMarket;
    final rawFreeAgentMarket = raw['freeAgentMarket'];
    if (schemaVersion >= 11) {
      if (rawFreeAgentMarket is! Map<String, dynamic>) {
        throw const FormatException(
          'Missing or invalid freeAgentMarket in career JSON v11',
        );
      }
      if (schemaVersion >= 12 &&
          !rawFreeAgentMarket.containsKey('roundHistory')) {
        throw const FormatException('Missing roundHistory in career JSON v12');
      }
      freeAgentMarket = FreeAgentMarketState.fromJson(rawFreeAgentMarket);
    } else {
      freeAgentMarket = FreeAgentMarketState.initial(seasonYear: currentYear);
    }

    final OffseasonClearanceState offseasonClearance;
    final rawClearance = raw['offseasonClearance'];
    if (schemaVersion >= 13) {
      if (rawClearance is! Map<String, dynamic>) {
        throw const FormatException(
          'Missing or invalid offseasonClearance in career JSON v13',
        );
      }
      offseasonClearance = OffseasonClearanceState.fromJson(rawClearance);
    } else {
      offseasonClearance = OffseasonClearanceState.initial(
        seasonYear: currentYear,
      );
    }

    final HardshipSettlement hardshipSettlement;
    final rawHardship = raw['hardshipSettlement'];
    if (schemaVersion >= 14) {
      if (rawHardship is! Map<String, dynamic>) {
        throw const FormatException(
          'Missing or invalid hardshipSettlement in career JSON v14',
        );
      }
      hardshipSettlement = HardshipSettlement.fromJson(rawHardship);
    } else {
      hardshipSettlement = HardshipSettlement.initial(seasonYear: currentYear);
    }
    final RegularSeasonState? regularSeasonState;
    final rawRegularSeasonState = raw['regularSeasonState'];
    if (schemaVersion >= 15) {
      if (!raw.containsKey('regularSeasonState')) {
        throw const FormatException(
          'Missing regularSeasonState in career JSON v15',
        );
      }
      if (rawRegularSeasonState == null) {
        regularSeasonState = null;
      } else if (rawRegularSeasonState is Map<String, dynamic>) {
        regularSeasonState = RegularSeasonState.fromJson(
          rawRegularSeasonState,
          schemaVersion: schemaVersion,
        );
      } else {
        throw const FormatException(
          'Invalid regularSeasonState in career JSON v15',
        );
      }
    } else {
      regularSeasonState = null;
    }
    final PlayInState? playInState;
    final rawPlayInState = raw['playInState'];
    if (schemaVersion >= 19) {
      if (!raw.containsKey('playInState')) {
        throw const FormatException('Missing playInState in career JSON v19');
      }
      if (rawPlayInState == null) {
        playInState = null;
      } else if (rawPlayInState is Map<String, dynamic>) {
        playInState = PlayInState.fromJson(rawPlayInState);
      } else {
        throw const FormatException('Invalid playInState in career JSON v19');
      }
    } else {
      if (rawPlayInState != null) {
        throw const FormatException(
          'Play-In state is not supported before career schema v19',
        );
      }
      playInState = null;
    }
    final PlayoffState? playoffState;
    final rawPlayoffState = raw['playoffState'];
    if (schemaVersion >= 20) {
      if (!raw.containsKey('playoffState')) {
        throw const FormatException('Missing playoffState in career JSON v20');
      }
      if (rawPlayoffState == null) {
        playoffState = null;
      } else if (rawPlayoffState is Map<String, dynamic>) {
        playoffState = PlayoffState.fromJson(rawPlayoffState);
      } else {
        throw const FormatException('Invalid playoffState in career JSON v20');
      }
    } else {
      if (rawPlayoffState != null) {
        throw const FormatException(
          'Playoff state is not supported before career schema v20',
        );
      }
      playoffState = null;
    }
    final CareerFinances? finances;
    final rawFinances = raw['finances'];
    if (schemaVersion >= 8) {
      if (rawFinances is! Map<String, dynamic>) {
        throw const FormatException(
          'Missing or invalid finances in career JSON v8',
        );
      }
      final finSchema = rawFinances['schemaVersion'];
      if (schemaVersion >= 23 && (finSchema is! int || finSchema < 2)) {
        throw const FormatException(
          'Career schema v23 requires financial schema v2+',
        );
      }
      finances = CareerFinances.fromJson(rawFinances);
    } else {
      finances = null;
    }

    final List<SeasonHistoryRecord> seasonHistory;
    final rawSeasonHistory = raw['seasonHistory'];
    if (schemaVersion >= 21) {
      if (!raw.containsKey('seasonHistory') || rawSeasonHistory is! List) {
        throw const FormatException(
          'Missing or invalid seasonHistory in career JSON v21',
        );
      }
      seasonHistory = [
        for (final entry in rawSeasonHistory)
          if (entry is Map<String, dynamic>)
            SeasonHistoryRecord.fromJson(entry)
          else
            throw const FormatException('Malformed SeasonHistoryRecord entry'),
      ];
    } else {
      if (rawSeasonHistory != null) {
        throw const FormatException(
          'Season history is not supported before career schema v21',
        );
      }
      seasonHistory = const [];
    }

    final List<RetiredPlayerRecord> retiredPlayers;
    final rawRetiredPlayers = raw['retiredPlayers'];
    final List<SeasonSettlementRecord> seasonSettlements;
    final rawSeasonSettlements = raw['seasonSettlements'];
    final Map<String, DraftRights> careerDraftRights;
    final rawCareerDraftRights = raw['careerDraftRights'];
    if (schemaVersion >= 22) {
      if (!raw.containsKey('retiredPlayers') || rawRetiredPlayers is! List) {
        throw const FormatException(
          'Missing or invalid retiredPlayers in career JSON v22',
        );
      }
      retiredPlayers = [
        for (final entry in rawRetiredPlayers)
          if (entry is Map<String, dynamic>)
            RetiredPlayerRecord.fromJson(entry)
          else
            throw const FormatException('Malformed RetiredPlayerRecord entry'),
      ];
      if (!raw.containsKey('seasonSettlements') ||
          rawSeasonSettlements is! List) {
        throw const FormatException(
          'Missing or invalid seasonSettlements in career JSON v22',
        );
      }
      seasonSettlements = [
        for (final entry in rawSeasonSettlements)
          if (entry is Map<String, dynamic>)
            SeasonSettlementRecord.fromJson(entry)
          else
            throw const FormatException(
              'Malformed SeasonSettlementRecord entry',
            ),
      ];
      if (!raw.containsKey('careerDraftRights') ||
          rawCareerDraftRights is! Map<String, dynamic>) {
        throw const FormatException(
          'Missing or invalid careerDraftRights in career JSON v22',
        );
      }
      careerDraftRights = <String, DraftRights>{};
      for (final entry in rawCareerDraftRights.entries) {
        if (entry.value is! Map<String, dynamic>) {
          throw const FormatException('Malformed careerDraftRights entry');
        }
        careerDraftRights[entry.key] = DraftRights.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    } else {
      if (rawRetiredPlayers != null ||
          rawSeasonSettlements != null ||
          rawCareerDraftRights != null) {
        throw const FormatException(
          'Multi-season rollover metadata is not supported before career schema v22',
        );
      }
      retiredPlayers = const [];
      seasonSettlements = const [];
      careerDraftRights = const {};
    }

    final Map<String, CarriedUnsignedProspect> carriedUnsignedProspects;
    final rawCarriedUnsignedProspects = raw['carriedUnsignedProspects'];
    if (schemaVersion >= 24) {
      if (!raw.containsKey('carriedUnsignedProspects') ||
          rawCarriedUnsignedProspects is! Map<String, dynamic>) {
        throw const FormatException(
          'Missing or invalid carriedUnsignedProspects in career JSON v24',
        );
      }
      carriedUnsignedProspects = <String, CarriedUnsignedProspect>{};
      for (final entry in rawCarriedUnsignedProspects.entries) {
        if (entry.value is! Map<String, dynamic>) {
          throw const FormatException(
            'Malformed carriedUnsignedProspects entry',
          );
        }
        carriedUnsignedProspects[entry.key] = CarriedUnsignedProspect.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    } else {
      if (rawCarriedUnsignedProspects != null) {
        throw const FormatException(
          'carriedUnsignedProspects is not supported before career schema v24',
        );
      }
      if (careerDraftRights.isEmpty) {
        carriedUnsignedProspects = const {};
      } else {
        final reconstructed = <String, CarriedUnsignedProspect>{};
        for (final entry in careerDraftRights.entries) {
          final rights = entry.value;
          final prospect = draftClass.seasonYear == rights.seasonYear
              ? draftClass.byId(rights.prospectId)
              : null;
          if (prospect == null) {
            throw FormatException(
              'Legacy career schema v$schemaVersion has non-empty '
              'careerDraftRights (${entry.key}) without reconstructible '
              'prospect data',
            );
          }
          final aged = prospect.age + (currentYear - rights.seasonYear);
          reconstructed[entry.key] = CarriedUnsignedProspect.fromRookieProspect(
            prospect: prospect,
            rights: rights,
            age: aged,
          );
        }
        carriedUnsignedProspects = reconstructed;
      }
    }

    final List<SeasonMarketHistoryRecord> marketHistory;
    final rawMarketHistory = raw['marketHistory'];
    if (schemaVersion >= 25) {
      if (!raw.containsKey('marketHistory') || rawMarketHistory is! List) {
        throw const FormatException(
          'Missing or invalid marketHistory in career JSON v25',
        );
      }
      marketHistory = [
        for (final entry in rawMarketHistory)
          if (entry is Map<String, dynamic>)
            SeasonMarketHistoryRecord.fromJson(entry)
          else
            throw const FormatException(
              'Malformed SeasonMarketHistoryRecord entry',
            ),
      ];
    } else {
      if (rawMarketHistory != null) {
        throw const FormatException(
          'marketHistory is not supported before career schema v25',
        );
      }
      marketHistory = const [];
    }

    final career = GmCareer(
      id: id,
      schemaVersion: schemaVersion == 17 ? 17 : currentSchemaVersion,
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
      draftExecutionState: draftExecutionState,
      rookieSigningLedger: rookieSigningLedger,
      aiRookieSigning: aiRookieSigning,
      freeAgentPool: freeAgentPool,
      freeAgentOffers: freeAgentOffers,
      freeAgentMarket: freeAgentMarket,
      offseasonClearance: offseasonClearance,
      hardshipSettlement: hardshipSettlement,
      finances: finances,
      playInState: playInState,
      regularSeasonState: regularSeasonState,
      playoffState: playoffState,
      seasonHistory: seasonHistory,
      retiredPlayers: retiredPlayers,
      seasonSettlements: seasonSettlements,
      careerDraftRights: careerDraftRights,
      carriedUnsignedProspects: carriedUnsignedProspects,
      marketHistory: marketHistory,
    );
    if (schemaVersion == 17) _validateNativeCareer(career);
    final migrated = schemaVersion == 17 ? _migrateV17(career) : career;
    _validateNativeCareer(migrated);
    return migrated;
  }

  static GmCareer _migrateV17(GmCareer career) {
    final state = career.regularSeasonState;
    if (state == null || state.gameResults.isEmpty) {
      return career.copyWith(schemaVersion: currentSchemaVersion);
    }
    final schedule = state.schedule!;
    final fixtures = {
      for (final fixture in schedule.allFixtures) fixture.id: fixture,
    };
    final adapter = const RegularSeasonGameAdapter();
    final simulationLeague = adapter.simulationLeagueFor(career);
    final snapshots = <String, String>{};
    final results = <String, RegularSeasonGameResult>{};
    const profile = RegularSeasonGameVersionProfile.t03;
    for (final entry in state.gameResults.entries) {
      final legacyResult = entry.value;
      final fixture = fixtures[entry.key]!;
      final input = adapter.createInput(
        career,
        fixture,
        simulationLeague: simulationLeague,
      );
      if (GameFingerprint.of(input) != legacyResult.inputFingerprint) {
        throw const FormatException(
          'Cannot migrate v17 result without exact historical input match',
        );
      }
      final captured = RegularSeasonGameInputEvidence.capture(input);
      final prior = snapshots.putIfAbsent(
        captured.evidence.leagueSnapshotId,
        () => captured.leagueSnapshotJson,
      );
      if (prior != captured.leagueSnapshotJson) {
        throw const FormatException(
          'Historical league snapshot digest collision',
        );
      }
      results[entry.key] = legacyResult.withInputEvidence(
        inputEvidence: captured.evidence,
        fingerprintVersion: profile.fingerprintVersion,
        coreEngineVersion: profile.coreEngineVersion,
        leagueSchemaVersion: profile.leagueSchemaVersion,
      );
    }
    return career.copyWith(
      schemaVersion: currentSchemaVersion,
      regularSeasonState: state.copyWith(
        gameResults: results,
        gameInputSnapshots: snapshots,
      ),
    );
  }

  static void _validateNativeCareer(GmCareer career) {
    career.validate();
    if (career.phase != CareerPhase.regularSeason &&
        career.phase != CareerPhase.playIn &&
        career.phase != CareerPhase.playoffs) {
      return;
    }
    final readiness = const OffseasonReadinessGate().evaluate(career);
    if (readiness.status != OffseasonReadinessStatus.cleared ||
        readiness.readyCount != career.league.teams.length) {
      throw const FormatException(
        'Regular-season save does not satisfy offseason readiness',
      );
    }
  }
}
