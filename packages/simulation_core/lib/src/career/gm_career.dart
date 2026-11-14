import '../generation/draft_generator.dart';
import '../generation/free_agent_generator.dart';
import '../finance/career_finances.dart';
import '../finance/financial_rules.dart';
import '../finance/financial_migration.dart';
import '../models/draft_execution_state.dart';
import '../models/draft_order.dart';
import '../models/draft_rights.dart';
import '../models/ai_rookie_signing.dart';
import '../models/franchise_situation.dart';
import '../models/free_agent.dart';
import '../models/free_agent_acquisition.dart';
import '../models/free_agent_market.dart';
import '../models/free_agent_offer.dart';
import '../models/offseason_clearance.dart';
import '../models/hardship_settlement.dart';
import '../models/ids.dart';
import '../models/league.dart';
import '../models/player_career_profile.dart';
import '../models/rookie_draft_class.dart';
import '../models/rookie_signing_ledger.dart';
import '../models/player_contract.dart';
import '../models/roster_category.dart';
import '../models/roster_rules.dart';
import '../models/team.dart';
import 'career_phase.dart';
import 'career_setup.dart';
import 'regular_season_state.dart';
import 'regular_season_schedule_generator.dart';
import '../simulation/game_fingerprint.dart';
import 'regular_season_game_adapter.dart';

import 'regular_season_game_input_evidence.dart';

typedef _RegularSeasonResultValidationContext = ({
  String seasonId,
  int seasonYear,
  String fixtureId,
  String fixtureSeasonId,
  int fixtureSeasonYear,
  String homeTeamId,
  String awayTeamId,
  int gameSeed,
  String snapshotId,
  String snapshotJson,
});

/// The authoritative, persistent root state of a GM Career.
final class GmCareer {
  // Reuse validation only for immutable results; decoding creates fresh objects.

  static final _validatedRegularSeasonResults =
      Expando<_RegularSeasonResultValidationContext>();
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
    FreeAgentMarketState? freeAgentMarket,
    OffseasonClearanceState? offseasonClearance,
    HardshipSettlement? hardshipSettlement,
    this.regularSeasonState,
    CareerFinances? finances,
  }) : draftExecutionState =
           draftExecutionState ?? DraftExecutionState.initial(),
       rookieSigningLedger = rookieSigningLedger ?? RookieSigningLedger.empty(),
       aiRookieSigning = aiRookieSigning ?? AiRookieSigningState.empty(),
       freeAgentOffers = freeAgentOffers ?? FreeAgentOfferLedger.empty(),
       freeAgentMarket =
           freeAgentMarket ??
           FreeAgentMarketState.initial(seasonYear: currentYear),
       offseasonClearance =
           offseasonClearance ??
           OffseasonClearanceState.initial(seasonYear: currentYear),
       hardshipSettlement =
           hardshipSettlement ??
           HardshipSettlement.initial(seasonYear: currentYear),
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

  static const int currentSchemaVersion = 18;

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

  /// Shared two-round free-agency market state.
  final FreeAgentMarketState freeAgentMarket;

  /// Bounded post-market compliance pass.
  final OffseasonClearanceState offseasonClearance;

  /// Separate one-time roster-completion settlement and authority.
  final HardshipSettlement hardshipSettlement;

  /// Deterministic opening state for a career that entered regular season.
  final RegularSeasonState? regularSeasonState;

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
    _validateFreeAgentMarket();
    _validateFreeAgentOffers();
    _validateHardshipSettlement();
    _validateOffseasonClearance();
    finances.validate(
      league: league,
      rookieSigningLedger: rookieSigningLedger,
      currentYear: currentYear,
      hardshipCapReliefByTeam: _hardshipCapReliefByTeam,
    );
    _validateRegularSeasonState();
  }

  void _validateRegularSeasonState() {
    final state = regularSeasonState;
    if (phase == CareerPhase.openingOffseason) {
      if (state != null) {
        throw const FormatException(
          'Opening-offseason career cannot contain regular-season state',
        );
      }
      return;
    }
    if (schemaVersion < 15 || state == null) {
      throw const FormatException(
        'Regular-season career requires schema v15 regular-season state',
      );
    }
    if (state.schedule != null && schemaVersion < 16) {
      throw const FormatException(
        'Scheduled regular-season career requires schema v16',
      );
    }
    if (schemaVersion < 17 && state.gameResults.isNotEmpty) {
      throw const FormatException(
        'Pre-v17 regular-season results are not supported',
      );
    }
    state.validate();
    if (state.seasonYear != currentYear ||
        state.scheduleSeed != generationSeed ||
        state.seasonId != RegularSeasonState.seasonIdFor(id, currentYear)) {
      throw const FormatException(
        'Regular-season identity does not match the career',
      );
    }
    if (state.openingTeams.length != league.teams.length) {
      throw const FormatException(
        'Regular-season opening teams do not match the league',
      );
    }
    for (var index = 0; index < league.teams.length; index++) {
      final team = league.teams[index];
      final identity = state.openingTeams[index];
      if (identity.teamId != team.id ||
          identity.name != team.name ||
          identity.abbreviation != team.abbreviation) {
        throw const FormatException(
          'Regular-season opening team identity changed',
        );
      }
    }
    final schedule = state.schedule;
    if (schedule != null) {
      RegularSeasonScheduleGenerator.validateCanonical(
        schedule: schedule,
        openingTeams: state.openingTeams,
      );
    }
    if (schedule == null || state.gameResults.isEmpty) return;
    final fixturesById = {
      for (final fixture in schedule.allFixtures) fixture.id: fixture,
    };
    if (schemaVersion < 18) {
      final adapter = const RegularSeasonGameAdapter();
      final simulationLeague = adapter.simulationLeagueFor(this);
      for (final entry in state.gameResults.entries) {
        final fixture = fixturesById[entry.key]!;
        final participants = {
          fixture.homeTeamId.value,
          fixture.awayTeamId.value,
        };
        final standardPlayers = <String>{};
        final playerTeams = <String, String>{};
        for (final team in league.teams) {
          if (!participants.contains(team.id.value)) continue;
          for (final player in team.players) {
            if (team.roster.categoryOf(player.id) == RosterCategory.standard) {
              standardPlayers.add(player.id.value);
              playerTeams[player.id.value] = team.id.value;
            }
          }
        }
        final result = entry.value;
        result.validateFor(
          fixture: fixture,
          expectedSeasonId: state.seasonId,
          expectedSeasonYear: state.seasonYear,
          standardPlayers: standardPlayers,
          playerTeams: playerTeams,
          legacyCompatibility: true,
        );
        if (GameFingerprint.of(
              adapter.createInput(
                this,
                fixture,
                simulationLeague: simulationLeague,
              ),
            ) !=
            result.inputFingerprint) {
          throw const FormatException(
            'Regular-season result input fingerprint mismatch',
          );
        }
      }
      return;
    }
    final openingTeamIds = {
      for (final team in state.openingTeams) team.teamId.value,
    };
    final historicalLeagues = <String, League>{
      for (final entry in state.gameInputSnapshots.entries)
        entry.key: RegularSeasonGameInputEvidence.parseLeagueSnapshot(
          snapshotId: entry.key,
          leagueSnapshotJson: entry.value,
          openingTeamIds: openingTeamIds,
        ),
    };
    for (final entry in state.gameResults.entries) {
      final fixture = fixturesById[entry.key]!;
      final result = entry.value;
      final evidence = result.inputEvidence;
      if (evidence == null ||
          result.fingerprintVersion == null ||
          result.coreEngineVersion == null ||
          result.leagueSchemaVersion == null) {
        throw const FormatException(
          'Native regular-season result lacks historical input evidence',
        );
      }
      final snapshotJson = state.gameInputSnapshots[evidence.leagueSnapshotId];
      final historicalLeague = historicalLeagues[evidence.leagueSnapshotId];
      if (snapshotJson == null || historicalLeague == null) {
        throw const FormatException(
          'Historical game-time league snapshot is missing',
        );
      }
      final validationContext = (
        seasonId: state.seasonId,
        seasonYear: state.seasonYear,
        fixtureId: fixture.id,
        fixtureSeasonId: fixture.seasonId,
        fixtureSeasonYear: fixture.seasonYear,
        homeTeamId: fixture.homeTeamId.value,
        awayTeamId: fixture.awayTeamId.value,
        gameSeed: fixture.gameSeed,
        snapshotId: evidence.leagueSnapshotId,
        snapshotJson: snapshotJson,
      );
      if (_validatedRegularSeasonResults[result] == validationContext) {
        continue;
      }

      final historicalInput = evidence.validate(
        leagueSnapshotId: evidence.leagueSnapshotId,
        leagueSnapshotJson: snapshotJson,
        league: historicalLeague,
        inputFingerprint: result.inputFingerprint,
        homeTeamId: result.homeTeamId.value,
        awayTeamId: result.awayTeamId.value,
        gameSeed: result.gameSeed,
        simulationVersion: result.simulationVersion,
        rulesVersion: result.rulesVersion,
        eventSchemaVersion: result.eventSchemaVersion,
        prngImplementationId: result.prngImplementationId,
        fingerprintVersion: result.fingerprintVersion!,
        coreEngineVersion: result.coreEngineVersion!,
        leagueSchemaVersion: result.leagueSchemaVersion!,
      );
      final participants = {fixture.homeTeamId.value, fixture.awayTeamId.value};
      final standardPlayers = <String>{};
      final playerTeams = <String, String>{};
      for (final team in historicalInput.league.teams) {
        if (!participants.contains(team.id.value)) continue;
        for (final player in team.players) {
          standardPlayers.add(player.id.value);
          playerTeams[player.id.value] = team.id.value;
        }
      }
      result.validateFor(
        fixture: fixture,
        expectedSeasonId: state.seasonId,
        expectedSeasonYear: state.seasonYear,
        standardPlayers: standardPlayers,
        playerTeams: playerTeams,
      );
      _validatedRegularSeasonResults[result] = validationContext;
    }
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

  /// Rejects market rounds that disagree with acquisitions or franchise roles.
  void _validateFreeAgentMarket() {
    freeAgentMarket.validate();
    if (freeAgentMarket.seasonYear != currentYear) {
      throw FormatException(
        'Free-agent market season ${freeAgentMarket.seasonYear} does not '
        'match career year $currentYear',
      );
    }
    final initialIds = {
      for (final id in freeAgentPool.initialPlayerIds) id.value,
    };
    final teamById = {for (final team in league.teams) team.id.value: team};
    for (final offer in freeAgentMarket.allOffers) {
      if (!initialIds.contains(offer.playerId.value)) {
        throw FormatException(
          'Market offer ${offer.offerId} references a player outside the '
          'initial snapshot',
        );
      }
      if (!teamById.containsKey(offer.teamId.value)) {
        throw FormatException(
          'Market offer ${offer.offerId} references unknown team',
        );
      }
      if (offer.source == FreeAgentMarketOfferSource.human &&
          offer.teamId != userFranchiseId) {
        throw FormatException('Human market offer targets another franchise');
      }
      if (offer.source == FreeAgentMarketOfferSource.ai &&
          offer.teamId == userFranchiseId) {
        throw FormatException('AI market offer targets the human franchise');
      }
    }
    for (final outcome in freeAgentMarket.outcomes) {
      _validateMarketOutcome(
        outcome: outcome,
        offers: freeAgentMarket.allOffers,
        seasonYear: freeAgentMarket.seasonYear,
        expectedOrigin: AcquisitionOrigin.initialPool,
      );
    }
    for (final round in freeAgentMarket.roundHistory) {
      final offers = [...round.humanOffers, ...round.aiOffers];
      for (final outcome in round.outcomes) {
        _validateMarketOutcome(
          outcome: outcome,
          offers: offers,
          seasonYear: round.seasonYear,
          expectedOrigin: AcquisitionOrigin.initialPool,
        );
      }
    }
  }

  void _validateMarketOutcome({
    required FreeAgentMarketOutcome outcome,
    required Iterable<FreeAgentMarketOffer> offers,
    required int seasonYear,
    required AcquisitionOrigin expectedOrigin,
  }) {
    for (final result in outcome.results) {
      if (result.outcome == FreeAgentMarketOfferOutcome.accepted) {
        final acquisition = freeAgentPool.acquisitions.forPlayer(
          outcome.playerId,
        );
        if (acquisition == null ||
            outcome.winningTeamId != result.teamId ||
            acquisition.teamId != result.teamId ||
            acquisition.origin != expectedOrigin) {
          throw FormatException(
            'Market result ${result.offerId} lacks its acquisition',
          );
        }
        final marketOffer = offers.firstWhere(
          (offer) => offer.offerId == result.offerId,
          orElse: () => throw FormatException(
            'Accepted market offer ${result.offerId} is missing',
          ),
        );
        final contract = finances.contractForPlayer(outcome.playerId);
        if (contract == null ||
            contract.category != marketOffer.category ||
            contract.durationYears != marketOffer.durationYears ||
            contract.startYear != marketOffer.seasonYear ||
            contract.source != ContractSource.freeAgent ||
            finances.scheduleFor(contract.id)?.annualSalaries.first !=
                marketOffer.firstYearSalary) {
          throw FormatException(
            'Accepted market offer ${result.offerId} does not match its '
            'contract',
          );
        }
        final acceptedAttempt = freeAgentOffers
            .attemptsFor(
              teamId: result.teamId,
              playerId: outcome.playerId,
              seasonYear: seasonYear,
            )
            .where(
              (attempt) =>
                  attempt.outcome.isAccepted &&
                  attempt.acquisitionTransactionId == acquisition.transactionId,
            );
        if (acceptedAttempt.isEmpty) {
          throw FormatException(
            'Accepted market offer ${result.offerId} lacks a formal '
            'accepted offer record',
          );
        }
      } else if (result.outcome == FreeAgentMarketOfferOutcome.rejected) {
        final marketOffer = offers.firstWhere(
          (offer) => offer.offerId == result.offerId,
          orElse: () => throw FormatException(
            'Rejected market offer ${result.offerId} is missing',
          ),
        );
        final attempts = freeAgentOffers.attemptsFor(
          teamId: result.teamId,
          playerId: outcome.playerId,
          seasonYear: seasonYear,
        );
        final matching = attempts.where(
          (attempt) =>
              !attempt.outcome.isAccepted &&
              attempt.category == marketOffer.category &&
              attempt.durationYears == marketOffer.durationYears &&
              attempt.firstYearSalary == marketOffer.firstYearSalary &&
              attempt.reasonCode == result.reasonCode &&
              attempt.attemptNumber <=
                  FreeAgentOfferAttempt.maximumPlayerSideAttempts,
        );
        if (matching.isEmpty) {
          throw FormatException(
            'Rejected market result ${result.offerId} lacks its exact formal '
            'rejection record',
          );
        }
      }
    }
  }

  void _validateOffseasonClearance() {
    final clearance = offseasonClearance;
    clearance.validate();
    if (clearance.seasonYear != currentYear) {
      throw FormatException(
        'Clearance season ${clearance.seasonYear} does not match career year '
        '$currentYear',
      );
    }
    final initialIds = {
      for (final id in freeAgentPool.initialPlayerIds) id.value,
    };
    final teamById = {for (final team in league.teams) team.id.value: team};
    for (final offer in clearance.allOffers) {
      if (!initialIds.contains(offer.playerId.value) ||
          !teamById.containsKey(offer.teamId.value)) {
        throw FormatException('Clearance offer references unknown identity');
      }
      if (offer.source == FreeAgentMarketOfferSource.human &&
          offer.teamId != userFranchiseId) {
        throw FormatException('Human clearance offer targets another team');
      }
      if (offer.source == FreeAgentMarketOfferSource.ai &&
          offer.teamId == userFranchiseId) {
        throw FormatException('AI clearance offer targets the human team');
      }
    }
    for (final outcome in clearance.outcomes) {
      _validateMarketOutcome(
        outcome: outcome,
        offers: clearance.allOffers,
        seasonYear: clearance.seasonYear,
        expectedOrigin: AcquisitionOrigin.clearance,
      );
    }
    final clearanceOfferCounts = <String, int>{};
    for (final offer in clearance.allOffers) {
      clearanceOfferCounts[offer.teamId.value] =
          (clearanceOfferCounts[offer.teamId.value] ?? 0) + 1;
    }
    for (final entry in clearanceOfferCounts.entries) {
      if (entry.value > FinancialRules.maximumReliefDeals) {
        throw FormatException(
          'Clearance exceeds two standard contracts for team ${entry.key}',
        );
      }
    }
    if (clearance.status == OffseasonClearanceStatus.notStarted &&
        clearance.capExceptions.isNotEmpty) {
      throw FormatException('Unstarted clearance carries cap exceptions');
    }
    final exceptionTeams = <String>{};
    for (final exception in clearance.capExceptions) {
      if (!exceptionTeams.add(exception.teamId.value)) {
        throw FormatException('Duplicate team cap exception');
      }
      final team = teamById[exception.teamId.value];
      if (team == null) {
        throw FormatException('Cap exception references unknown team');
      }
      final rosterCompletionAcquisitions = freeAgentPool
          .acquisitions
          .entries
          .values
          .where(
            (acquisition) =>
                acquisition.teamId == exception.teamId &&
                (acquisition.origin == AcquisitionOrigin.clearance ||
                    acquisition.origin == AcquisitionOrigin.hardship),
          )
          .toList();
      final initialStandard =
          team.roster.standardCount - rosterCompletionAcquisitions.length;
      final initialPayroll =
          finances.capPayrollFor(exception.teamId, currentYear) -
          rosterCompletionAcquisitions.fold<int>(0, (sum, acquisition) {
            final contract = finances.contractForPlayer(acquisition.playerId);
            return sum +
                finances.scheduleFor(contract!.id)!.annualSalaries.first;
          });
      final expectedAmount = FinancialRules.minimumRosterReliefOverage(
        standardCount: initialStandard,
        capRoom: FinancialRules.salaryCap - initialPayroll,
      );
      if (exception.missingPlayers !=
              FinancialRules.minimumStandardRoster - initialStandard ||
          expectedAmount == null ||
          expectedAmount == 0 ||
          exception.amount != expectedAmount) {
        throw FormatException(
          'Cap exception does not match the authorized roster shortage',
        );
      }
      final teamFinances = finances.financesFor(exception.teamId);
      if (teamFinances.capException != exception.amount) {
        throw FormatException('Cap exception does not match team finances');
      }
      final capPayroll = finances.capPayrollFor(exception.teamId, currentYear);
      final hardshipRelief =
          _hardshipCapReliefByTeam[exception.teamId.value] ?? 0;
      if (capPayroll >
          FinancialRules.salaryCap + exception.amount + hardshipRelief) {
        throw FormatException(
          'Team payroll exceeds its approved cap exception',
        );
      }
    }
    for (final finances in this.finances.teamFinances.values) {
      if (finances.capException > 0 &&
          !exceptionTeams.contains(finances.teamId.value)) {
        throw FormatException(
          'Team finances carry an unrecorded cap exception',
        );
      }
    }
    if (clearance.isComplete) {
      for (final acquisition in freeAgentPool.acquisitions.entries.values) {
        if (acquisition.origin != AcquisitionOrigin.clearance) continue;
        final linkedResult = clearance.outcomes.any(
          (outcome) =>
              outcome.playerId == acquisition.playerId &&
              outcome.results.any(
                (result) =>
                    result.teamId == acquisition.teamId &&
                    result.outcome == FreeAgentMarketOfferOutcome.accepted,
              ),
        );
        if (!linkedResult) {
          throw FormatException(
            'Completed clearance acquisition lacks accepted outcome',
          );
        }
      }
    }
  }

  void _validateHardshipSettlement() {
    final settlement = hardshipSettlement;
    settlement.validate();
    final acquisitions = freeAgentPool.acquisitions.entries.values
        .where((item) => item.origin == AcquisitionOrigin.hardship)
        .toList();
    if (settlement.status == HardshipSettlementStatus.notStarted) {
      if (acquisitions.isNotEmpty) {
        throw const FormatException(
          'Hardship acquisition exists without a settlement',
        );
      }
      return;
    }
    if (settlement.seasonYear > currentYear ||
        (!settlement.isComplete && settlement.seasonYear != currentYear)) {
      throw const FormatException('Hardship settlement season is invalid');
    }
    if (!settlement.isComplete &&
        (phase != CareerPhase.openingOffseason ||
            freeAgentMarket.status != FreeAgentMarketStatus.marketComplete ||
            ![
              OffseasonClearanceStatus.complete,
              OffseasonClearanceStatus.cleared,
            ].contains(offseasonClearance.status))) {
      throw const FormatException(
        'Hardship settlement is outside the authorized offseason phase',
      );
    }
    final initialIds = {
      for (final id in freeAgentPool.initialPlayerIds) id.value,
    };
    final teamsById = {for (final team in league.teams) team.id.value: team};
    for (final offer in settlement.offers) {
      if (!initialIds.contains(offer.playerId.value) ||
          !teamsById.containsKey(offer.teamId.value) ||
          offer.seasonYear != settlement.seasonYear ||
          (offer.source == FreeAgentMarketOfferSource.human) !=
              (offer.teamId == userFranchiseId) ||
          (offer.source == FreeAgentMarketOfferSource.human &&
              !settlement.humanParticipationConfirmed)) {
        throw const FormatException('Hardship offer identity is invalid');
      }
    }
    for (final acquisition in acquisitions) {
      if (acquisition.seasonYear != settlement.seasonYear ||
          acquisition.category != RosterCategory.standard) {
        throw const FormatException(
          'Hardship acquisition has invalid season or category',
        );
      }
      final offer = settlement.offers
          .where(
            (candidate) =>
                candidate.playerId == acquisition.playerId &&
                candidate.teamId == acquisition.teamId &&
                candidate.seasonYear == acquisition.seasonYear,
          )
          .firstOrNull;
      if (offer == null) {
        throw const FormatException(
          'Hardship acquisition lacks an exact authorized offer',
        );
      }
      final contract = finances.contractForPlayer(acquisition.playerId);
      final schedule = contract == null
          ? null
          : finances.scheduleFor(contract.id);
      if (contract == null ||
          schedule == null ||
          acquisition.contractId != contract.id ||
          contract.id !=
              PlayerContract.idFor(
                acquisition.playerId,
                settlement.seasonYear,
              ) ||
          contract.teamId != offer.teamId ||
          contract.category != RosterCategory.standard ||
          contract.durationYears != offer.durationYears ||
          contract.startYear != offer.seasonYear ||
          contract.source != ContractSource.freeAgent ||
          schedule.annualSalaries.join(',') != offer.salarySchedule.join(',')) {
        throw const FormatException(
          'Hardship acquisition does not conserve contract identity',
        );
      }
    }
    final acquisitionIds = {
      for (final item in acquisitions) item.transactionId,
    };
    for (final authorization in settlement.authorizations) {
      final team = teamsById[authorization.teamId.value];
      if (team == null ||
          authorization.seasonYear != settlement.seasonYear ||
          authorization.existingOrdinaryRelief !=
              finances.financesFor(authorization.teamId).capException ||
          finances.financesFor(authorization.teamId).capGrandfathered) {
        throw const FormatException('Hardship authorization is not eligible');
      }
      final teamOffers = settlement.offers
          .where((offer) => offer.teamId == authorization.teamId)
          .toList();
      final teamAcquisitions = acquisitions
          .where((item) => item.teamId == authorization.teamId)
          .toList();
      final initialStandard =
          team.roster.standardCount - teamAcquisitions.length;
      final missing = RosterRules.minRegularSeasonStandard - initialStandard;
      if (missing < 1 ||
          missing > FinancialRules.maximumReliefDeals ||
          authorization.missingPlayers != missing ||
          teamOffers.length > missing) {
        throw const FormatException('Hardship shortage authorization mismatch');
      }
      final acquisitionSalary = teamAcquisitions.fold<int>(0, (sum, item) {
        final contract = finances.contractForPlayer(item.playerId)!;
        return sum + finances.scheduleFor(contract.id)!.annualSalaries.first;
      });
      final initialPayroll =
          finances.capPayrollFor(authorization.teamId, settlement.seasonYear) -
          acquisitionSalary;
      final proposedSalary = teamOffers.fold<int>(
        0,
        (sum, offer) => sum + offer.firstYearSalary,
      );
      final overage =
          initialPayroll + proposedSalary - FinancialRules.salaryCap;
      final requiredAdditional = overage > authorization.existingOrdinaryRelief
          ? overage - authorization.existingOrdinaryRelief
          : 0;
      if (teamOffers.isEmpty ||
          requiredAdditional < 1 ||
          authorization.additionalAmount != requiredAdditional ||
          authorization.additionalAmount +
                  authorization.existingOrdinaryRelief >
              FinancialRules.maximumCombinedHardshipOverage) {
        throw const FormatException(
          'Hardship authorization is not the exact permitted amount',
        );
      }
      final actualOverage =
          finances.capPayrollFor(authorization.teamId, settlement.seasonYear) -
          FinancialRules.salaryCap -
          authorization.existingOrdinaryRelief;
      final actualUsed = actualOverage > 0 ? actualOverage : 0;
      final teamTransactionIds = {
        for (final item in teamAcquisitions) item.transactionId,
      };
      if (authorization.usedAmount != actualUsed ||
          !teamTransactionIds.containsAll(authorization.transactionIds) ||
          !authorization.transactionIds.toSet().containsAll(
            teamTransactionIds,
          ) ||
          (teamAcquisitions.isEmpty) !=
              (authorization.status == HardshipAuthorizationStatus.unused)) {
        throw const FormatException(
          'Hardship authorization use does not match acquisitions',
        );
      }
      if (!acquisitionIds.containsAll(authorization.transactionIds)) {
        throw const FormatException(
          'Hardship authorization references an unknown transaction',
        );
      }
    }
    for (final acquisition in acquisitions) {
      if (!settlement.authorizations.any(
        (authorization) =>
            authorization.teamId == acquisition.teamId &&
            authorization.transactionIds.contains(acquisition.transactionId),
      )) {
        throw const FormatException(
          'Hardship acquisition lacks consumed authority',
        );
      }
    }
    for (final outcome in settlement.outcomes) {
      for (final result in outcome.results) {
        final offer = settlement.offerById(result.offerId)!;
        if (result.outcome == FreeAgentMarketOfferOutcome.accepted) {
          final acquisition = freeAgentPool.acquisitions.forPlayer(
            outcome.playerId,
          );
          final attempt = freeAgentOffers.entries[result.offerId];
          if (acquisition == null ||
              acquisition.origin != AcquisitionOrigin.hardship ||
              acquisition.teamId != result.teamId ||
              outcome.winningOfferId != result.offerId ||
              attempt == null ||
              !attempt.outcome.isAccepted ||
              attempt.playerId != offer.playerId ||
              attempt.teamId != offer.teamId ||
              attempt.seasonYear != offer.seasonYear ||
              attempt.durationYears != offer.durationYears ||
              attempt.firstYearSalary != offer.firstYearSalary ||
              attempt.acquisitionTransactionId != acquisition.transactionId) {
            throw const FormatException(
              'Accepted hardship result lacks its exact transaction record',
            );
          }
        } else if (result.outcome == FreeAgentMarketOfferOutcome.rejected) {
          final attempt = freeAgentOffers.entries[result.offerId];
          final expectedRejection = switch (result.reasonCode) {
            'salaryBelowExpectation' => FreeAgentOfferOutcome.salaryTooLow,
            'veteranDuration' ||
            'durationCompensation' => FreeAgentOfferOutcome.unfavorableDuration,
            'roleOrFranchiseFit' => FreeAgentOfferOutcome.poorFit,
            _ => null,
          };
          if (attempt == null ||
              expectedRejection == null ||
              attempt.outcome != expectedRejection ||
              attempt.playerId != offer.playerId ||
              attempt.teamId != offer.teamId ||
              attempt.seasonYear != offer.seasonYear ||
              attempt.category != offer.category ||
              attempt.durationYears != offer.durationYears ||
              attempt.firstYearSalary != offer.firstYearSalary ||
              attempt.reasonCode != result.reasonCode) {
            throw const FormatException(
              'Rejected hardship result lacks its exact formal attempt',
            );
          }
        }
      }
    }
    for (final acquisition in acquisitions) {
      final accepted = settlement.outcomes.any(
        (outcome) =>
            outcome.playerId == acquisition.playerId &&
            outcome.results.any(
              (result) =>
                  result.teamId == acquisition.teamId &&
                  result.outcome == FreeAgentMarketOfferOutcome.accepted,
            ),
      );
      if (!accepted) {
        throw const FormatException(
          'Hardship acquisition lacks an accepted settlement result',
        );
      }
    }
  }

  Map<String, int> get _hardshipCapReliefByTeam => {
    for (final authorization in hardshipSettlement.authorizations)
      if (hardshipSettlement.seasonYear == currentYear &&
          authorization.status == HardshipAuthorizationStatus.consumed)
        authorization.teamId.value: authorization.additionalAmount,
  };

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
    FreeAgentMarketState? freeAgentMarket,
    OffseasonClearanceState? offseasonClearance,
    HardshipSettlement? hardshipSettlement,
    RegularSeasonState? regularSeasonState,
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
      freeAgentMarket: freeAgentMarket ?? this.freeAgentMarket,
      offseasonClearance: offseasonClearance ?? this.offseasonClearance,
      hardshipSettlement: hardshipSettlement ?? this.hardshipSettlement,
      regularSeasonState: regularSeasonState ?? this.regularSeasonState,
      finances: finances ?? this.finances,
    );
  }
}
