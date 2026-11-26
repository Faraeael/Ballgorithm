import '../draft/ai_rookie_signing_service.dart';
import '../finance/career_finances.dart';
import '../finance/financial_rules.dart';
import '../finance/financial_transactions.dart';
import '../models/free_agent.dart';
import '../models/free_agent_acquisition.dart';
import '../models/free_agent_market.dart';
import '../models/hardship_settlement.dart';
import '../models/ids.dart';
import '../models/league.dart';
import '../models/player_career_profile.dart';
import '../models/player_contract.dart';
import '../models/position.dart';
import '../models/roster_category.dart';
import '../models/roster_rules.dart';
import '../models/team.dart';
import 'career_phase.dart';
import 'free_agent_offer_evaluator.dart';
import 'gm_career.dart';

enum EmergencyPlanStatus {
  optimal,
  feasibleNotProvenOptimal,
  noSolution,
  inconclusive,
}

final class EmergencyOffer {
  const EmergencyOffer({
    required this.teamId,
    required this.playerId,
    required this.seasonYear,
    required this.salary,
    required this.relief,
  });

  final TeamId teamId;
  final PlayerId playerId;
  final int seasonYear;
  final int salary;
  final int relief;

  String get offerId =>
      'emergency-offer-${teamId.value}-${playerId.value}-$seasonYear-$salary';
  String get transactionId => FreeAgentAcquisition.idFor(playerId, seasonYear);
}

final class EmergencyTeamProjection {
  EmergencyTeamProjection({
    required this.teamId,
    required this.standardBefore,
    required this.standardAfter,
    required this.payrollBefore,
    required this.payrollAfter,
    required this.cashBefore,
    required this.cashAfter,
    required this.relief,
    required List<Position> missingPositionsBefore,
    required List<Position> missingPositionsAfter,
  }) : missingPositionsBefore = List.unmodifiable(missingPositionsBefore),
       missingPositionsAfter = List.unmodifiable(missingPositionsAfter);

  final TeamId teamId;
  final int standardBefore;
  final int standardAfter;
  final int payrollBefore;
  final int payrollAfter;
  final int cashBefore;
  final int cashAfter;
  final int relief;
  final List<Position> missingPositionsBefore;
  final List<Position> missingPositionsAfter;
}

final class EmergencyRosterPlan {
  EmergencyRosterPlan({
    required this.status,
    required List<EmergencyOffer> offers,
    required List<EmergencyTeamProjection> teams,
    required this.exploredStates,
    required List<String> blockers,
  }) : offers = List.unmodifiable(offers),
       teams = List.unmodifiable(teams),
       blockers = List.unmodifiable(blockers);

  final EmergencyPlanStatus status;
  final List<EmergencyOffer> offers;
  final List<EmergencyTeamProjection> teams;
  final int exploredStates;
  final List<String> blockers;
}

/// One franchise still short of a mandatory roster at the emergency pass.
final class EmergencyNeed {
  const EmergencyNeed({
    required this.team,
    required this.payroll,
    required this.cash,
  });

  final Team team;

  /// Cap payroll, including guaranteed liabilities, before the pass.
  final int payroll;

  /// Projected end-of-season cash less debt before the pass.
  final int cash;
}

/// Player willingness for a one-year standard offer from [original] whose
/// roster is currently [current] (after earlier emergency signings).
typedef EmergencyWillingness =
    bool Function(
      Team original,
      Team current,
      FreeAgentEntry entry,
      int salary,
    );

final class EmergencyAllocation {
  EmergencyAllocation({
    required this.status,
    required List<EmergencyOffer> offers,
    required this.exploredStates,
  }) : offers = List.unmodifiable(offers);

  final EmergencyPlanStatus status;
  final List<EmergencyOffer> offers;
  final int exploredStates;
}

/// Read-only league-wide emergency allocation. Search truncation is explicit.
final class EmergencyRosterService {
  const EmergencyRosterService({this.maxSearchStates = 200000});

  final int maxSearchStates;

  EmergencyRosterPlan preview(GmCareer career) {
    final blockers = <String>[];
    if (career.phase != CareerPhase.openingOffseason) {
      blockers.add('Career is outside the opening offseason');
    }
    if (!career.draftExecutionState.isCompleted ||
        const RookieAiSigningService().pendingRights(career).isNotEmpty) {
      blockers.add('Rookie decisions are incomplete');
    }
    if (career.freeAgentMarket.status != FreeAgentMarketStatus.marketComplete ||
        career.freeAgentMarket.completedRounds != 2) {
      blockers.add('Both free-agent market rounds must be complete');
    }
    if (!career.offseasonClearance.isComplete ||
        !career.hardshipSettlement.isComplete) {
      blockers.add('Clearance and hardship settlement must be complete');
    }
    if (career.emergencySettlement != null) {
      blockers.add('Emergency settlement is already complete');
    }
    if (maxSearchStates < 1) blockers.add('Search limit must be positive');
    if (blockers.isNotEmpty) {
      return EmergencyRosterPlan(
        status: EmergencyPlanStatus.inconclusive,
        offers: const [],
        teams: const [],
        exploredStates: 0,
        blockers: blockers,
      );
    }
    career.validate();
    final teams = [...career.league.teams]
      ..sort((a, b) => a.id.value.compareTo(b.id.value));
    final entries = [...career.freeAgentPool.entries]
      ..sort((a, b) => a.id.value.compareTo(b.id.value));
    final needs = [
      for (final team in teams)
        if (!_ready(team))
          EmergencyNeed(
            team: team,
            payroll: career.finances.capPayrollFor(team.id, career.currentYear),
            cash:
                career.finances.projectedEndOfSeasonCash(
                  team.id,
                  career.currentYear,
                ) -
                career.finances.debtFor(team.id),
          ),
    ];
    const evaluator = FreeAgentOfferEvaluator();
    final allocation = allocate(
      seasonYear: career.currentYear,
      phase: career.phase,
      needs: needs,
      entries: entries,
      accepts: (original, current, entry, salary) => evaluator
          .evaluateWillingness(
            career: career,
            teamId: original.id,
            freeAgentId: entry.id,
            category: RosterCategory.standard,
            durationYears: 1,
            salary: salary,
            teamOverride: current,
          )
          .accepts,
    );
    final projections = <EmergencyTeamProjection>[];
    for (final need in needs) {
      final team = need.team;
      final offers = allocation.offers
          .where((offer) => offer.teamId == team.id)
          .toList();
      var roster = team.roster;
      for (final offer in offers) {
        roster = roster.withPlayer(
          career.freeAgentPool.byId(offer.playerId)!.player,
          category: RosterCategory.standard,
        );
      }
      final salary = offers.fold<int>(0, (sum, offer) => sum + offer.salary);
      projections.add(
        EmergencyTeamProjection(
          teamId: team.id,
          standardBefore: team.roster.standardCount,
          standardAfter: roster.standardCount,
          payrollBefore: need.payroll,
          payrollAfter: need.payroll + salary,
          cashBefore: need.cash,
          cashAfter: need.cash - salary,
          relief: offers.fold<int>(0, (sum, offer) => sum + offer.relief),
          missingPositionsBefore: [
            for (final p in Position.values)
              if (!team.roster.covers(p)) p,
          ],
          missingPositionsAfter: [
            for (final p in Position.values)
              if (!roster.covers(p)) p,
          ],
        ),
      );
    }
    final found =
        allocation.status == EmergencyPlanStatus.optimal ||
        allocation.status == EmergencyPlanStatus.feasibleNotProvenOptimal;
    return EmergencyRosterPlan(
      status: allocation.status,
      offers: allocation.offers,
      teams: projections,
      exploredStates: allocation.exploredStates,
      blockers: found ? const [] : ['No complete allocation was found'],
    );
  }

  /// Maximum first-year salary of one emergency contract.
  static const int maximumSalary = 1200;

  /// Deterministic, bounded joint search. Each player is used at most once;
  /// willingness is re-evaluated against the roster after earlier signings.
  /// Minimizes total relief, then total salary, then canonical offer order.
  EmergencyAllocation allocate({
    required int seasonYear,
    required CareerPhase phase,
    required List<EmergencyNeed> needs,
    required List<FreeAgentEntry> entries,
    required EmergencyWillingness accepts,
  }) {
    final used = <String>{};
    final chosen = <EmergencyOffer>[];
    List<EmergencyOffer>? best;
    var bestRelief = 0;
    var bestSalary = 0;
    var explored = 0;
    var truncated = false;

    int compareOffers(EmergencyOffer a, EmergencyOffer b) {
      var comparison = a.teamId.value.compareTo(b.teamId.value);
      if (comparison == 0) {
        comparison = a.playerId.value.compareTo(b.playerId.value);
      }
      if (comparison == 0) comparison = a.salary.compareTo(b.salary);
      return comparison;
    }

    bool better(int relief, int salary) {
      final current = best;
      if (current == null) return true;
      if (relief != bestRelief) return relief < bestRelief;
      if (salary != bestSalary) return salary < bestSalary;
      final left = [...chosen]..sort(compareOffers);
      final right = [...current]..sort(compareOffers);
      for (var i = 0; i < left.length && i < right.length; i++) {
        final comparison = compareOffers(left[i], right[i]);
        if (comparison != 0) return comparison < 0;
      }
      return left.length < right.length;
    }

    void search(
      int teamIndex,
      Team? rosterTeam,
      int teamSalary,
      int totalRelief,
      int totalSalary,
    ) {
      if (explored >= maxSearchStates) {
        truncated = true;
        return;
      }
      explored++;
      if (best != null &&
          (totalRelief > bestRelief ||
              (totalRelief == bestRelief && totalSalary > bestSalary))) {
        return;
      }
      if (teamIndex == needs.length) {
        if (better(totalRelief, totalSalary)) {
          best = List.of(chosen);
          bestRelief = totalRelief;
          bestSalary = totalSalary;
        }
        return;
      }
      final need = needs[teamIndex];
      final original = need.team;
      final current = rosterTeam ?? original;
      if (_ready(current)) {
        search(teamIndex + 1, null, 0, totalRelief, totalSalary);
        return;
      }
      if (current.roster.standardCount >=
              RosterRules.maxRegularSeasonStandard ||
          current.roster.totalContractedCount >=
              RosterRules.maxRegularSeasonTotal ||
          current.roster.trainingCampCount != 0) {
        return;
      }
      final payroll = need.payroll;
      final baseline = payroll > FinancialRules.salaryCap
          ? payroll
          : FinancialRules.salaryCap;
      final oldExcess = payroll + teamSalary - baseline;
      final oldRelief = oldExcess > 0 ? oldExcess : 0;
      for (final entry in entries) {
        if (truncated) return;
        if (used.contains(entry.id.value)) continue;
        final nextRoster = current.roster.withPlayer(
          entry.player,
          category: RosterCategory.standard,
        );
        if (!nextRoster.validateStructure(phase: phase).isValid) continue;
        var low = FinancialRules.minimumSalary;
        var high = maximumSalary;
        if (!accepts(original, current, entry, high)) continue;
        while (low < high) {
          final middle = (low + high) ~/ 2;
          if (accepts(original, current, entry, middle)) {
            high = middle;
          } else {
            low = middle + 1;
          }
        }
        final salary = low;
        if (need.cash < teamSalary + salary) continue;
        final excess = payroll + teamSalary + salary - baseline;
        final delta = (excess > 0 ? excess : 0) - oldRelief;
        chosen.add(
          EmergencyOffer(
            teamId: original.id,
            playerId: entry.id,
            seasonYear: seasonYear,
            salary: salary,
            relief: delta,
          ),
        );
        used.add(entry.id.value);
        search(
          teamIndex,
          current.copyWith(roster: nextRoster),
          teamSalary + salary,
          totalRelief + delta,
          totalSalary + salary,
        );
        used.remove(entry.id.value);
        chosen.removeLast();
      }
    }

    search(0, null, 0, 0, 0);
    final selected = best;
    return EmergencyAllocation(
      status: selected == null
          ? (truncated
                ? EmergencyPlanStatus.inconclusive
                : EmergencyPlanStatus.noSolution)
          : (truncated
                ? EmergencyPlanStatus.feasibleNotProvenOptimal
                : EmergencyPlanStatus.optimal),
      offers: selected ?? const [],
      exploredStates: explored,
    );
  }

  /// Recomputes the reviewed plan and commits all accepted offers together.
  GmCareer execute(
    GmCareer career,
    EmergencyRosterPlan plan, {
    required bool humanApproved,
  }) {
    final fresh = preview(career);
    if ((fresh.status != EmergencyPlanStatus.optimal &&
            fresh.status != EmergencyPlanStatus.feasibleNotProvenOptimal) ||
        fresh.offers.isEmpty ||
        !_samePlan(plan, fresh)) {
      throw StateError('Emergency plan is stale, forged, or not executable');
    }
    if (!humanApproved &&
        fresh.offers.any((offer) => offer.teamId == career.userFranchiseId)) {
      throw StateError('Human emergency offers require explicit approval');
    }
    var finances = career.finances;
    var acquisitions = career.freeAgentPool.acquisitions;
    final updatedTeams = {
      for (final team in career.league.teams) team.id.value: team,
    };
    final profiles = {...career.careerProfiles.profiles};
    final acquiredIds = <String>{};
    for (final offer in fresh.offers) {
      final entry = career.freeAgentPool.byId(offer.playerId)!;
      final team = updatedTeams[offer.teamId.value]!;
      final contract = PlayerContract(
        id: PlayerContract.idFor(offer.playerId, career.currentYear),
        playerId: offer.playerId,
        teamId: offer.teamId,
        category: RosterCategory.standard,
        startYear: career.currentYear,
        durationYears: 1,
        source: ContractSource.freeAgent,
      );
      finances = FinancialTransactions.addContract(
        finances: finances,
        contract: contract,
        annualSalaries: [offer.salary],
      );
      acquisitions = acquisitions.add(
        FreeAgentAcquisition(
          transactionId: offer.transactionId,
          playerId: offer.playerId,
          teamId: offer.teamId,
          contractId: contract.id,
          seasonYear: career.currentYear,
          category: RosterCategory.standard,
          origin: AcquisitionOrigin.emergency,
        ),
      );
      updatedTeams[team.id.value] = team.copyWith(
        roster: team.roster.withPlayer(
          entry.player,
          category: RosterCategory.standard,
        ),
      );
      profiles[offer.playerId.value] = entry.profile;
      acquiredIds.add(offer.playerId.value);
    }
    final userOffers = fresh.offers.any(
      (offer) => offer.teamId == career.userFranchiseId,
    );
    final settlement = EmergencySettlement(
      seasonYear: career.currentYear,
      humanApproved: humanApproved && userOffers,
      searchStatus: fresh.status,
      offers: fresh.offers,
      teams: [
        for (final team in fresh.teams)
          if (fresh.offers.any((offer) => offer.teamId == team.teamId))
            EmergencyTeamReceipt.capture(career, team),
      ],
    );
    return career.copyWith(
      schemaVersion: GmCareer.currentSchemaVersion,
      league: League.create(
        id: career.league.id,
        name: career.league.name,
        config: career.league.config,
        teams: [
          for (final team in career.league.teams) updatedTeams[team.id.value]!,
        ],
        enforceRosterSize: false,
        enforcePositionCoverage: false,
      ),
      careerProfiles: LeagueCareerProfiles(
        schemaVersion: career.careerProfiles.schemaVersion,
        leagueSeed: career.careerProfiles.leagueSeed,
        profiles: profiles,
      ),
      freeAgentPool: FreeAgentPool(
        seasonYear: career.freeAgentPool.seasonYear,
        entries: [
          for (final entry in career.freeAgentPool.entries)
            if (!acquiredIds.contains(entry.id.value)) entry,
        ],
        initialPlayerIds: career.freeAgentPool.initialPlayerIds,
        acquisitions: acquisitions,
      ),
      finances: finances,
      emergencySettlement: settlement,
    );
  }

  static bool _samePlan(EmergencyRosterPlan a, EmergencyRosterPlan b) {
    if (a.status != b.status ||
        a.offers.length != b.offers.length ||
        a.teams.length != b.teams.length) {
      return false;
    }
    for (var i = 0; i < a.offers.length; i++) {
      final x = a.offers[i], y = b.offers[i];
      if (x.teamId != y.teamId ||
          x.playerId != y.playerId ||
          x.seasonYear != y.seasonYear ||
          x.salary != y.salary ||
          x.relief != y.relief) {
        return false;
      }
    }
    for (var i = 0; i < a.teams.length; i++) {
      final x = a.teams[i], y = b.teams[i];
      if (x.teamId != y.teamId ||
          x.standardBefore != y.standardBefore ||
          x.standardAfter != y.standardAfter ||
          x.payrollBefore != y.payrollBefore ||
          x.payrollAfter != y.payrollAfter ||
          x.cashBefore != y.cashBefore ||
          x.cashAfter != y.cashAfter ||
          x.relief != y.relief ||
          x.missingPositionsBefore.join(',') !=
              y.missingPositionsBefore.join(',') ||
          x.missingPositionsAfter.join(',') !=
              y.missingPositionsAfter.join(',')) {
        return false;
      }
    }
    return true;
  }

  static bool _ready(Team team) =>
      team.roster.validateRegularSeasonReadiness().isValid &&
      Position.values.every(team.roster.covers);
}

/// Transaction-time evidence for one franchise, captured from the validated
/// career immediately before the emergency pass.
final class EmergencyTeamReceipt {
  EmergencyTeamReceipt({
    required this.teamId,
    required this.standardBefore,
    required this.payrollBefore,
    required this.cashBefore,
    required this.ordinaryRelief,
    required this.hardshipRelief,
    required this.grandfathered,
    required this.grandfatheredPayroll,
    required List<Position> missingPositionsBefore,
    required List<String> priorContractIds,
  }) : missingPositionsBefore = List.unmodifiable(missingPositionsBefore),
       priorContractIds = List.unmodifiable(priorContractIds);

  factory EmergencyTeamReceipt.capture(
    GmCareer career,
    EmergencyTeamProjection projection,
  ) {
    final finances = career.finances.financesFor(projection.teamId);
    return EmergencyTeamReceipt(
      teamId: projection.teamId,
      standardBefore: projection.standardBefore,
      payrollBefore: projection.payrollBefore,
      cashBefore: projection.cashBefore,
      ordinaryRelief: finances.capException,
      hardshipRelief: consumedHardshipFor(
        career.hardshipSettlement,
        projection.teamId,
        career.currentYear,
      ),
      grandfathered: finances.capGrandfathered,
      grandfatheredPayroll: finances.capGrandfathered
          ? finances.grandfatheredPayroll
          : 0,
      missingPositionsBefore: projection.missingPositionsBefore,
      priorContractIds: priorContractIdsFor(
        career.finances,
        projection.teamId,
        career.currentYear,
      ),
    );
  }

  final TeamId teamId;
  final int standardBefore;
  final int payrollBefore;
  final int cashBefore;

  /// Existing ordinary cap relief (clearance exception) at execution.
  final int ordinaryRelief;

  /// Consumed hardship relief at execution.
  final int hardshipRelief;
  final bool grandfathered;
  final int grandfatheredPayroll;
  final List<Position> missingPositionsBefore;

  /// Contracts with a current-season salary on this team before the pass.
  final List<String> priorContractIds;

  /// Cap authority that already made the starting payroll lawful.
  int get startingLimit => grandfathered
      ? grandfatheredPayroll + FinancialRules.maximumReliefOverage
      : FinancialRules.salaryCap + ordinaryRelief + hardshipRelief;

  static List<String> priorContractIdsFor(
    CareerFinances finances,
    TeamId teamId,
    int year,
  ) => [
    for (final schedule in finances.schedulesForTeam(teamId))
      if (finances.contracts[schedule.contractId] != null &&
          schedule.salaryForYear(year) != null)
        schedule.contractId,
  ]..sort();

  static int consumedHardshipFor(
    HardshipSettlement settlement,
    TeamId teamId,
    int year,
  ) {
    if (settlement.seasonYear != year) return 0;
    final authorization = settlement.authorizationFor(teamId);
    return authorization != null &&
            authorization.status == HardshipAuthorizationStatus.consumed
        ? authorization.additionalAmount
        : 0;
  }

  factory EmergencyTeamReceipt.fromJson(Map<String, dynamic> raw) {
    final positions = raw['missingPositionsBefore'];
    final contracts = raw['priorContractIds'];
    if (raw.length != 10 ||
        raw['teamId'] is! String ||
        raw['standardBefore'] is! int ||
        raw['payrollBefore'] is! int ||
        raw['cashBefore'] is! int ||
        raw['ordinaryRelief'] is! int ||
        raw['hardshipRelief'] is! int ||
        raw['grandfathered'] is! bool ||
        raw['grandfatheredPayroll'] is! int ||
        positions is! List ||
        positions.any((value) => value is! String) ||
        contracts is! List ||
        contracts.any((value) => value is! String)) {
      throw const FormatException('Malformed emergency team receipt');
    }
    final List<Position> parsed;
    try {
      parsed = [for (final value in positions) Position.parse(value as String)];
    } on Exception {
      throw const FormatException('Invalid emergency receipt position');
    }
    return EmergencyTeamReceipt(
      teamId: TeamId(raw['teamId'] as String),
      standardBefore: raw['standardBefore'] as int,
      payrollBefore: raw['payrollBefore'] as int,
      cashBefore: raw['cashBefore'] as int,
      ordinaryRelief: raw['ordinaryRelief'] as int,
      hardshipRelief: raw['hardshipRelief'] as int,
      grandfathered: raw['grandfathered'] as bool,
      grandfatheredPayroll: raw['grandfatheredPayroll'] as int,
      missingPositionsBefore: parsed,
      priorContractIds: [for (final value in contracts) value as String],
    );
  }

  void validate(int offerCount) {
    var previousPosition = -1;
    for (final position in missingPositionsBefore) {
      if (position.index <= previousPosition) {
        throw const FormatException(
          'Emergency receipt positions are not canonical',
        );
      }
      previousPosition = position.index;
    }
    var previousContract = '';
    for (final id in priorContractIds) {
      if (id.isEmpty || id.compareTo(previousContract) <= 0) {
        throw const FormatException(
          'Emergency receipt contracts are not canonical',
        );
      }
      previousContract = id;
    }
    final shortage =
        (RosterRules.minRegularSeasonStandard - standardBefore > 0
            ? RosterRules.minRegularSeasonStandard - standardBefore
            : 0) +
        missingPositionsBefore.length;
    if (ordinaryRelief < 0 ||
        hardshipRelief < 0 ||
        ordinaryRelief + hardshipRelief >
            FinancialRules.maximumCombinedHardshipOverage ||
        (grandfathered && (hardshipRelief != 0 || grandfatheredPayroll < 1)) ||
        (!grandfathered && grandfatheredPayroll != 0) ||
        payrollBefore > startingLimit ||
        priorContractIds.length < standardBefore ||
        shortage < 1 ||
        offerCount > shortage ||
        standardBefore + offerCount > RosterRules.maxRegularSeasonStandard) {
      throw const FormatException(
        'Emergency receipt lacks a lawful mandatory shortage or authority',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'teamId': teamId.value,
    'standardBefore': standardBefore,
    'payrollBefore': payrollBefore,
    'cashBefore': cashBefore,
    'ordinaryRelief': ordinaryRelief,
    'hardshipRelief': hardshipRelief,
    'grandfathered': grandfathered,
    'grandfatheredPayroll': grandfatheredPayroll,
    'missingPositionsBefore': [
      for (final position in missingPositionsBefore) position.shortName,
    ],
    'priorContractIds': priorContractIds,
  };
}

/// Completed emergency pass and its exact, non-transferable acquisition proof.
final class EmergencySettlement {
  EmergencySettlement({
    required this.seasonYear,
    required this.humanApproved,
    required this.searchStatus,
    required List<EmergencyOffer> offers,
    required List<EmergencyTeamReceipt> teams,
  }) : offers = List.unmodifiable(offers),
       teams = List.unmodifiable(teams) {
    validate();
  }

  factory EmergencySettlement.fromJson(Map<String, dynamic> json) {
    final seasonYear = json['seasonYear'];
    final humanApproved = json['humanApproved'];
    final status = json['searchStatus'];
    final rawOffers = json['offers'];
    final rawTeams = json['teams'];
    if (json.length != 5 ||
        seasonYear is! int ||
        humanApproved is! bool ||
        status is! String ||
        rawOffers is! List ||
        rawTeams is! List) {
      throw const FormatException('Malformed emergency settlement');
    }
    final searchStatus = EmergencyPlanStatus.values
        .where((value) => value.name == status)
        .firstOrNull;
    if (searchStatus == null) {
      throw const FormatException('Invalid emergency search status');
    }
    final offers = <EmergencyOffer>[];
    for (var index = 0; index < rawOffers.length; index++) {
      final raw = rawOffers[index];
      if (raw is! Map<String, dynamic> ||
          raw.length != 8 ||
          raw['sequence'] != index ||
          raw['teamId'] is! String ||
          raw['playerId'] is! String ||
          raw['seasonYear'] is! int ||
          raw['salary'] is! int ||
          raw['relief'] is! int ||
          raw['offerId'] is! String ||
          raw['transactionId'] is! String) {
        throw const FormatException('Malformed emergency offer receipt');
      }
      final offer = EmergencyOffer(
        teamId: TeamId(raw['teamId'] as String),
        playerId: PlayerId(raw['playerId'] as String),
        seasonYear: raw['seasonYear'] as int,
        salary: raw['salary'] as int,
        relief: raw['relief'] as int,
      );
      if (raw['offerId'] != offer.offerId ||
          raw['transactionId'] != offer.transactionId) {
        throw const FormatException('Emergency offer identity mismatch');
      }
      offers.add(offer);
    }
    final teams = <EmergencyTeamReceipt>[
      for (final raw in rawTeams)
        if (raw is Map<String, dynamic>)
          EmergencyTeamReceipt.fromJson(raw)
        else
          throw const FormatException('Malformed emergency team receipt'),
    ];
    return EmergencySettlement(
      seasonYear: seasonYear,
      humanApproved: humanApproved,
      searchStatus: searchStatus,
      offers: offers,
      teams: teams,
    );
  }

  final int seasonYear;
  final bool humanApproved;
  final EmergencyPlanStatus searchStatus;
  final List<EmergencyOffer> offers;
  final List<EmergencyTeamReceipt> teams;

  void validate() {
    if (seasonYear < 1 ||
        (searchStatus != EmergencyPlanStatus.optimal &&
            searchStatus != EmergencyPlanStatus.feasibleNotProvenOptimal) ||
        offers.isEmpty ||
        teams.isEmpty) {
      throw const FormatException('Invalid completed emergency settlement');
    }
    final byTeam = <String, EmergencyTeamReceipt>{};
    var previousTeam = '';
    for (final team in teams) {
      if (team.teamId.value.isEmpty ||
          team.teamId.value.compareTo(previousTeam) <= 0 ||
          team.standardBefore < 0 ||
          team.standardBefore >= RosterRules.maxRegularSeasonStandard ||
          team.payrollBefore < 0 ||
          team.cashBefore < 0) {
        throw const FormatException('Invalid emergency team receipt');
      }
      previousTeam = team.teamId.value;
      byTeam[team.teamId.value] = team;
    }
    final players = <String>{};
    final totals = <String, int>{};
    final counts = <String, int>{};
    previousTeam = '';
    for (final offer in offers) {
      final team = byTeam[offer.teamId.value];
      if (team == null ||
          offer.teamId.value.compareTo(previousTeam) < 0 ||
          offer.playerId.value.trim().isEmpty ||
          !players.add(offer.playerId.value) ||
          offer.seasonYear != seasonYear ||
          offer.salary < FinancialRules.minimumSalary ||
          offer.salary > EmergencyRosterService.maximumSalary) {
        throw const FormatException('Invalid emergency offer');
      }
      previousTeam = offer.teamId.value;
      final previousSalary = totals[offer.teamId.value] ?? 0;
      final salary = previousSalary + offer.salary;
      final baseline = team.payrollBefore > FinancialRules.salaryCap
          ? team.payrollBefore
          : FinancialRules.salaryCap;
      final before = team.payrollBefore + previousSalary - baseline;
      final after = team.payrollBefore + salary - baseline;
      final delta = (after > 0 ? after : 0) - (before > 0 ? before : 0);
      if (offer.relief != delta || salary > team.cashBefore) {
        throw const FormatException(
          'Emergency relief or cash does not match offer',
        );
      }
      totals[offer.teamId.value] = salary;
      counts[offer.teamId.value] = (counts[offer.teamId.value] ?? 0) + 1;
    }
    if (counts.length != teams.length) {
      throw const FormatException('Unused emergency team receipt');
    }
    for (final team in teams) {
      team.validate(counts[team.teamId.value] ?? 0);
    }
  }

  Map<String, Object?> toJson() => {
    'seasonYear': seasonYear,
    'humanApproved': humanApproved,
    'searchStatus': searchStatus.name,
    'offers': [
      for (var index = 0; index < offers.length; index++)
        {
          'sequence': index,
          'offerId': offers[index].offerId,
          'transactionId': offers[index].transactionId,
          'teamId': offers[index].teamId.value,
          'playerId': offers[index].playerId.value,
          'seasonYear': offers[index].seasonYear,
          'salary': offers[index].salary,
          'relief': offers[index].relief,
        },
    ],
    'teams': [for (final team in teams) team.toJson()],
  };
}
