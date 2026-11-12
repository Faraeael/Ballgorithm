import '../generation/draft_generator.dart';
import '../generation/free_agent_generator.dart';
import '../finance/career_finances.dart';
import '../finance/financial_migration.dart';
import '../models/draft_execution_state.dart';
import '../models/draft_order.dart';
import '../models/draft_rights.dart';
import '../models/ai_rookie_signing.dart';
import '../models/franchise_situation.dart';
import '../models/free_agent.dart';
import '../models/free_agent_offer.dart';
import '../models/ids.dart';
import '../models/league.dart';
import '../models/player_career_profile.dart';
import '../models/rookie_draft_class.dart';
import '../models/rookie_signing_ledger.dart';
import '../models/player_contract.dart';
import '../models/roster_category.dart';
import '../models/team.dart';
import 'career_phase.dart';
import 'career_setup.dart';

/// The authoritative, persistent root state of a GM Career.
final class GmCareer {
  GmCareer({
    required this.id,
    this.schemaVersion = currentSchemaVersion,
    required this.generationSeed,
    required this.userFranchiseId,
    required this.originalSituation,
    this.currentYear = 1,
    this.phase = CareerPhase.openingOffseason,
    required this.league,
    required this.careerProfiles,
    required this.userOpeningDraftPick,
    DraftOrder? draftOrder,
    RookieDraftClass? draftClass,
    DraftExecutionState? draftExecutionState,
    RookieSigningLedger? rookieSigningLedger,
    AiRookieSigningState? aiRookieSigning,
    FreeAgentPool? freeAgentPool,
    FreeAgentOfferLedger? freeAgentOffers,
    CareerFinances? finances,
  }) : draftExecutionState =
           draftExecutionState ?? DraftExecutionState.initial(),
       rookieSigningLedger = rookieSigningLedger ?? RookieSigningLedger.empty(),
       aiRookieSigning = aiRookieSigning ?? AiRookieSigningState.empty(),
       freeAgentOffers = freeAgentOffers ?? FreeAgentOfferLedger.empty(),
       finances =
           finances ??
           FinancialMigration.bootstrapFromCareerState(
             league: league,
             careerProfiles: careerProfiles,
             rookieSigningLedger:
                 rookieSigningLedger ?? RookieSigningLedger.empty(),
             currentYear: currentYear,
           ),
       freeAgentPool =
           freeAgentPool ??
           const FreeAgentGenerator().generate(seed: generationSeed),
       draftOrder =
           draftOrder ??
           const DraftGenerator().generateDraftOrder(
             league: league,
             seed: generationSeed,
             userTeamId: userFranchiseId,
             userSituation: originalSituation,
           ),
       draftClass =
           draftClass ??
           const DraftGenerator().generateDraftClass(
             league: league,
             seed: generationSeed,
             seasonYear: currentYear,
           ) {
    validate();
  }

  /// Creates a new persistent [GmCareer] from a verified [CareerSetupResult].
  factory GmCareer.fromSetupResult(CareerSetupResult result, {String? id}) {
    final careerId =
        id ??
        'career-${result.seed}-${result.selectedTeam.id.value}-${DateTime.now().millisecondsSinceEpoch}';
    return GmCareer(
      id: careerId,
      generationSeed: result.seed,
      userFranchiseId: result.selectedTeam.id,
      originalSituation: result.selectedSituation,
      currentYear: 1,
      phase: CareerPhase.openingOffseason,
      league: result.league,
      careerProfiles: result.careerProfiles,
      userOpeningDraftPick: result.userOpeningDraftPick,
      draftOrder: result.draftOrder,
      draftClass: result.draftClass,
      draftExecutionState: DraftExecutionState.initial(),
    );
  }

  static const int currentSchemaVersion = 10;

  final String id;
  final int schemaVersion;
  final int generationSeed;
  final TeamId userFranchiseId;
  final FranchiseSituation originalSituation;
  final int currentYear;
  final CareerPhase phase;
  final League league;
  final LeagueCareerProfiles careerProfiles;
  final int userOpeningDraftPick;

  final DraftOrder draftOrder;
  final RookieDraftClass draftClass;
  final DraftExecutionState draftExecutionState;

  final RookieSigningLedger rookieSigningLedger;

  final AiRookieSigningState aiRookieSigning;

  final FreeAgentPool freeAgentPool;

  /// Durable formal player-side offer history.
  final FreeAgentOfferLedger freeAgentOffers;

  /// Authoritative contract, payroll, budget, staff and facility records.
  final CareerFinances finances;

  /// Draft rights whose prospect has not signed a rookie contract yet.
  ///
  /// Derived from authoritative draft history and the signing ledger; never
  /// stored separately.
  List<DraftRights> get unsignedDraftRights => [
    for (final rights in draftExecutionState.draftRights.values)
      if (!rookieSigningLedger.isSigned(rights.prospectId)) rights,
  ];

  /// Returns the human user's managed [Team].
  Team get userTeam => league.teams.firstWhere(
    (t) => t.id == userFranchiseId,
    orElse: () => throw StateError(
      'User franchise ${userFranchiseId.value} not found in league',
    ),
  );

  /// Validates internal consistency and all domain invariants of the career.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('Career ID cannot be empty');
    }
    if (schemaVersion < 1 || schemaVersion > currentSchemaVersion) {
      throw FormatException(
        'Unsupported career schema version: $schemaVersion (supported: 1..$currentSchemaVersion)',
      );
    }
    if (currentYear < 1) {
      throw FormatException(
        'Invalid career year: $currentYear (expected >= 1)',
      );
    }
    if (league.teams.length != 30) {
      throw FormatException(
        'Invalid league: expected exactly 30 teams, found ${league.teams.length}',
      );
    }

    final teamIds = <String>{};
    final playerIds = <String>{};
    final rosterTeamByPlayerId = <String, TeamId>{};
    final rosterCategoryByPlayerId = <String, RosterCategory>{};
    for (final team in league.teams) {
      if (!teamIds.add(team.id.value)) {
        throw FormatException('Duplicate team ID in league: ${team.id.value}');
      }
      if (team.roster.players.length < 5) {
        throw FormatException(
          'Team ${team.id.value} must have at least 5 players, found ${team.roster.players.length}',
        );
      }
      team.roster.validateStructure(phase: phase).throwIfInvalid();
      for (final player in team.players) {
        if (!playerIds.add(player.id.value)) {
          throw FormatException(
            'Duplicate player ID in league: ${player.id.value}',
          );
        }
        rosterTeamByPlayerId[player.id.value] = team.id;
        rosterCategoryByPlayerId[player.id.value] = team.roster.categoryOf(
          player.id,
        );
      }
    }

    if (!teamIds.contains(userFranchiseId.value)) {
      throw FormatException(
        'User franchise ${userFranchiseId.value} not found in league teams',
      );
    }

    for (final pid in playerIds) {
      if (!careerProfiles.profiles.containsKey(pid)) {
        throw FormatException('Missing career profile for player $pid');
      }
    }

    if (userOpeningDraftPick < 1 || userOpeningDraftPick > 30) {
      throw FormatException(
        'Invalid opening draft pick: $userOpeningDraftPick (expected 1..30)',
      );
    }

    if (currentYear == 1 && phase == CareerPhase.openingOffseason) {
      final expectedPick = originalSituation.userOpeningDraftPick;
      if (userOpeningDraftPick != expectedPick) {
        throw FormatException(
          'Opening draft pick mismatch: expected $expectedPick for ${originalSituation.displayName}, got $userOpeningDraftPick',
        );
      }
    }

    draftOrder.validate();
    draftClass.validate();
    for (final pick in draftOrder.picks) {
      if (!teamIds.contains(pick.originalOwnerTeamId.value) ||
          !teamIds.contains(pick.currentOwnerTeamId.value)) {
        throw const FormatException('Draft pick references unknown franchise');
      }
    }
    for (final prospect in draftClass.prospects) {
      if (playerIds.contains(prospect.id.value) &&
          !rookieSigningLedger.isSigned(prospect.id)) {
        throw FormatException(
          'Draft prospect ${prospect.id.value} is on a roster without a rookie contract',
        );
      }
    }

    final userRound1Pick = draftOrder.pickAt(userOpeningDraftPick);
    if (userRound1Pick.originalOwnerTeamId != userFranchiseId) {
      throw FormatException(
        'User franchise ${userFranchiseId.value} lacks original entitlement to opening draft pick $userOpeningDraftPick',
      );
    }

    draftExecutionState.validate(
      order: draftOrder,
      draftClass: draftClass,
      seasonYear: currentYear,
    );
    _validateRookieSignings(
      rosterTeamByPlayerId: rosterTeamByPlayerId,
      rosterCategoryByPlayerId: rosterCategoryByPlayerId,
    );
    _validateAiSigningDecisions();
    _validateFreeAgentPool();
    _validateFreeAgentOffers();
    finances.validate(
      league: league,
      rookieSigningLedger: rookieSigningLedger,
      currentYear: currentYear,
    );
  }

  /// Rejects free agents that collide with ownership, contracts or prospects.
  void _validateFreeAgentPool() {
    freeAgentPool.validate();
    final freeAgentIds = freeAgentPool.playerIds;
    for (final team in league.teams) {
      for (final player in team.players) {
        if (freeAgentIds.contains(player.id.value)) {
          throw FormatException(
            'Free agent ${player.id.value} is on franchise ${team.id.value}',
          );
        }
      }
    }
    for (final prospect in draftClass.prospects) {
      if (freeAgentIds.contains(prospect.id.value)) {
        throw FormatException(
          'Free agent ${prospect.id.value} collides with a draft prospect',
        );
      }
    }
    for (final contract in rookieSigningLedger.contracts.values) {
      if (freeAgentIds.contains(contract.playerId.value)) {
        throw FormatException(
          'Free agent ${contract.playerId.value} has a rookie contract',
        );
      }
    }
    for (final rights in draftExecutionState.draftRights.values) {
      if (freeAgentIds.contains(rights.prospectId.value)) {
        throw FormatException(
          'Free agent ${rights.prospectId.value} has draft rights',
        );
      }
    }
    for (final decision in aiRookieSigning.decisions.values) {
      if (freeAgentIds.contains(decision.prospectId.value)) {
        throw FormatException(
          'Free agent ${decision.prospectId.value} has an AI decision',
        );
      }
    }
    for (final playerId in freeAgentIds) {
      if (careerProfiles.profiles.containsKey(playerId)) {
        throw FormatException(
          'Free agent $playerId has a roster career profile',
        );
      }
    }

    if (freeAgentPool.initialPlayerIds.length != FreeAgentPool.expectedSize) {
      throw FormatException(
        'Initial free-agent identity snapshot must contain '
        '${FreeAgentPool.expectedSize} IDs, got '
        '${freeAgentPool.initialPlayerIds.length}',
      );
    }
    final initialIds = {
      for (final id in freeAgentPool.initialPlayerIds) id.value,
    };
    final teamById = {for (final team in league.teams) team.id.value: team};
    final rosterCategoryByPlayer = <String, RosterCategory>{};
    final rosterTeamByPlayer = <String, String>{};
    for (final team in league.teams) {
      for (final player in team.players) {
        rosterCategoryByPlayer[player.id.value] = team.roster.categoryOf(
          player.id,
        );
        rosterTeamByPlayer[player.id.value] = team.id.value;
      }
    }
    for (final acquisition in freeAgentPool.acquisitions.entries.values) {
      final pid = acquisition.playerId.value;
      if (!initialIds.contains(pid)) {
        throw FormatException(
          'Acquisition ${acquisition.transactionId} references a player '
          'outside the initial free-agent snapshot',
        );
      }
      if (freeAgentIds.contains(pid)) {
        throw FormatException(
          'Acquired player $pid is still in the available free-agent pool',
        );
      }
      final team = teamById[acquisition.teamId.value];
      if (team == null) {
        throw FormatException(
          'Acquisition ${acquisition.transactionId} references unknown team '
          '${acquisition.teamId.value}',
        );
      }
      if (rosterTeamByPlayer[pid] != acquisition.teamId.value) {
        throw FormatException(
          'Acquired player $pid is not on franchise '
          '${acquisition.teamId.value}',
        );
      }
      if (rosterCategoryByPlayer[pid] != acquisition.category) {
        throw FormatException(
          'Acquired player $pid roster category does not match the '
          'acquisition record',
        );
      }
      final contract = finances.contractForPlayer(acquisition.playerId);
      if (contract == null ||
          contract.id != acquisition.contractId ||
          contract.teamId != acquisition.teamId ||
          contract.category != acquisition.category ||
          contract.source != ContractSource.freeAgent) {
        throw FormatException(
          'Acquisition ${acquisition.transactionId} lacks its matching '
          'freeAgent employment contract',
        );
      }
      if (finances.scheduleFor(contract.id) == null) {
        throw FormatException(
          'Acquisition ${acquisition.transactionId} lacks a financial '
          'schedule',
        );
      }
      if (careerProfiles.forPlayer(acquisition.playerId) == null) {
        throw FormatException('Acquired player $pid has no career profile');
      }
    }
  }

  /// Rejects formal offers that disagree with acquisitions, teams or contracts.
  void _validateFreeAgentOffers() {
    freeAgentOffers.validate();
    final initialIds = {
      for (final id in freeAgentPool.initialPlayerIds) id.value,
    };
    final teamById = {for (final team in league.teams) team.id.value: team};
    for (final attempt in freeAgentOffers.entries.values) {
      if (!initialIds.contains(attempt.playerId.value)) {
        throw FormatException(
          'Offer ${attempt.offerId} references a player outside the initial '
          'free-agent snapshot',
        );
      }
      if (!teamById.containsKey(attempt.teamId.value)) {
        throw FormatException(
          'Offer ${attempt.offerId} references unknown team '
          '${attempt.teamId.value}',
        );
      }
      if (!attempt.outcome.isAccepted) continue;
      final transactionId = attempt.acquisitionTransactionId;
      final acquisition = transactionId == null
          ? null
          : freeAgentPool.acquisitions.entries[transactionId];
      if (acquisition == null) {
        throw FormatException(
          'Accepted offer ${attempt.offerId} has no acquisition record',
        );
      }
      if (acquisition.playerId != attempt.playerId ||
          acquisition.teamId != attempt.teamId ||
          acquisition.seasonYear != attempt.seasonYear ||
          acquisition.category != attempt.category) {
        throw FormatException(
          'Accepted offer ${attempt.offerId} does not match its acquisition',
        );
      }
      final contract = finances.contractForPlayer(attempt.playerId);
      if (contract == null ||
          contract.id != acquisition.contractId ||
          contract.teamId != attempt.teamId ||
          contract.category != attempt.category ||
          contract.startYear != attempt.seasonYear ||
          contract.durationYears != attempt.durationYears ||
          contract.source != ContractSource.freeAgent) {
        throw FormatException(
          'Accepted offer ${attempt.offerId} lacks its matching contract',
        );
      }
      final schedule = finances.scheduleFor(contract.id);
      if (schedule == null ||
          schedule.annualSalaries.isEmpty ||
          schedule.annualSalaries.first != attempt.firstYearSalary) {
        throw FormatException(
          'Accepted offer ${attempt.offerId} salary does not match its '
          'schedule',
        );
      }
    }
  }

  /// Rejects AI decisions that disagree with draft rights, contracts or ownership.
  void _validateAiSigningDecisions() {
    if (aiRookieSigning.isEmpty) return;
    if (!draftExecutionState.isCompleted) {
      throw const FormatException(
        'AI signing decisions require a completed rookie draft',
      );
    }
    final selectionsByProspect = {
      for (final selection in draftExecutionState.selections)
        selection.prospectId.value: selection,
    };
    for (final decision in aiRookieSigning.decisions.values) {
      final pid = decision.prospectId.value;
      if (draftClass.byId(decision.prospectId) == null) {
        throw FormatException('AI decision references unknown prospect $pid');
      }
      final selection = selectionsByProspect[pid];
      if (selection == null) {
        throw FormatException('AI decision references undrafted prospect $pid');
      }
      if (selection.seasonYear != decision.draftSeasonYear ||
          selection.overallPick != decision.overallPick) {
        throw FormatException(
          'AI decision for $pid does not match its draft selection',
        );
      }
      final rights = draftExecutionState.draftRights[pid];
      if (rights == null || rights.owningTeamId != decision.teamId) {
        throw FormatException(
          'AI decision for $pid does not match current draft ownership',
        );
      }
      if (decision.teamId == userFranchiseId) {
        throw FormatException(
          'AI decision for $pid targets the human franchise',
        );
      }
      final contract = rookieSigningLedger.forPlayer(decision.prospectId);
      if (decision.isSigned) {
        if (contract == null) {
          throw FormatException(
            'Signed AI decision for $pid lacks a rookie contract',
          );
        }
        if (contract.teamId != decision.teamId ||
            contract.id != decision.contractId) {
          throw FormatException(
            'Signed AI decision for $pid does not match its contract',
          );
        }
        final expected = decision.decision == AiSigningDecisionType.signedTwoWay
            ? RosterCategory.twoWay
            : RosterCategory.standard;
        if (contract.category != expected) {
          throw FormatException(
            'Signed AI decision for $pid does not match contract category',
          );
        }
      } else if (contract != null) {
        throw FormatException(
          'Deferred AI decision for $pid contradicts a signed contract',
        );
      }
    }
  }

  /// Rejects contracts that disagree with draft history, rostering or profiles.
  void _validateRookieSignings({
    required Map<String, TeamId> rosterTeamByPlayerId,
    required Map<String, RosterCategory> rosterCategoryByPlayerId,
  }) {
    if (rookieSigningLedger.isEmpty) return;
    if (!draftExecutionState.isCompleted) {
      throw const FormatException(
        'Rookie contracts require a completed rookie draft',
      );
    }
    final selectionsByProspect = {
      for (final selection in draftExecutionState.selections)
        selection.prospectId.value: selection,
    };
    for (final contract in rookieSigningLedger.contracts.values) {
      final pid = contract.playerId.value;
      if (draftClass.byId(contract.playerId) == null) {
        throw FormatException(
          'Rookie contract references unknown prospect $pid',
        );
      }
      final selection = selectionsByProspect[pid];
      if (selection == null) {
        throw FormatException('Signed rookie $pid was never drafted');
      }
      if (selection.selectingTeamId != contract.teamId ||
          selection.seasonYear != contract.draftSeasonYear ||
          selection.overallPick != contract.overallPick) {
        throw FormatException(
          'Rookie contract for $pid does not match its draft selection',
        );
      }
      final rosterTeam = rosterTeamByPlayerId[pid];
      if (rosterTeam == null) {
        throw FormatException(
          'Signed rookie $pid is not on a franchise roster',
        );
      }
      if (rosterTeam != contract.teamId) {
        throw FormatException(
          'Signed rookie $pid roster franchise does not match contract',
        );
      }
      if (rosterCategoryByPlayerId[pid] != contract.category) {
        throw FormatException(
          'Roster category for signed rookie $pid does not match contract',
        );
      }
      if (careerProfiles.forPlayer(contract.playerId) == null) {
        throw FormatException('Missing career profile for signed rookie $pid');
      }
    }
  }

  /// Returns a new [GmCareer] with [updatedTeam] swapped into the league.
  GmCareer withUpdatedTeam(
    Team updatedTeam, {
    LeagueCareerProfiles? careerProfiles,
    CareerFinances? finances,
  }) {
    final updatedTeams = [
      for (final t in league.teams)
        if (t.id == updatedTeam.id) updatedTeam else t,
    ];
    final updatedLeague = League.create(
      id: league.id,
      name: league.name,
      config: league.config,
      teams: updatedTeams,
      enforceRosterSize: false,
    );
    return copyWith(
      league: updatedLeague,
      careerProfiles: careerProfiles ?? this.careerProfiles,
      finances: finances,
    );
  }

  GmCareer copyWith({
    String? id,
    int? schemaVersion,
    int? generationSeed,
    TeamId? userFranchiseId,
    FranchiseSituation? originalSituation,
    int? currentYear,
    CareerPhase? phase,
    League? league,
    LeagueCareerProfiles? careerProfiles,
    int? userOpeningDraftPick,
    DraftOrder? draftOrder,
    RookieDraftClass? draftClass,
    DraftExecutionState? draftExecutionState,
    RookieSigningLedger? rookieSigningLedger,
    AiRookieSigningState? aiRookieSigning,
    FreeAgentPool? freeAgentPool,
    FreeAgentOfferLedger? freeAgentOffers,
    CareerFinances? finances,
  }) {
    return GmCareer(
      id: id ?? this.id,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      generationSeed: generationSeed ?? this.generationSeed,
      userFranchiseId: userFranchiseId ?? this.userFranchiseId,
      originalSituation: originalSituation ?? this.originalSituation,
      currentYear: currentYear ?? this.currentYear,
      phase: phase ?? this.phase,
      league: league ?? this.league,
      careerProfiles: careerProfiles ?? this.careerProfiles,
      userOpeningDraftPick: userOpeningDraftPick ?? this.userOpeningDraftPick,
      draftOrder: draftOrder ?? this.draftOrder,
      draftClass: draftClass ?? this.draftClass,
      draftExecutionState: draftExecutionState ?? this.draftExecutionState,
      rookieSigningLedger: rookieSigningLedger ?? this.rookieSigningLedger,
      aiRookieSigning: aiRookieSigning ?? this.aiRookieSigning,
      freeAgentPool: freeAgentPool ?? this.freeAgentPool,
      freeAgentOffers: freeAgentOffers ?? this.freeAgentOffers,
      finances: finances ?? this.finances,
    );
  }
}
