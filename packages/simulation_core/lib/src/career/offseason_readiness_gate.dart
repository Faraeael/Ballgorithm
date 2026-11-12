import '../finance/financial_rules.dart';
import '../models/free_agent_market.dart';
import '../models/offseason_clearance.dart';
import '../models/roster_category.dart';
import '../models/ids.dart';
import '../models/roster_rules.dart';
import '../models/team.dart';
import 'free_agent_market_value_service.dart';
import 'free_agent_offer_evaluator.dart';
import 'gm_career.dart';
import '../draft/ai_rookie_signing_service.dart';

enum OffseasonReadinessStatus {
  offseasonInProgress('offseasonInProgress'),
  clearanceRequired('clearanceRequired'),
  financialExceptionRequired('financialExceptionRequired'),
  readyForConfirmation('readyForConfirmation'),
  cleared('cleared');

  const OffseasonReadinessStatus(this.jsonValue);

  final String jsonValue;
}

final class FranchiseClearanceNeed {
  const FranchiseClearanceNeed({
    required this.teamId,
    required this.abbreviation,
    required this.standardCount,
    required this.requiredPlayers,
    required this.capRoom,
    required this.cash,
    required this.projectedCash,
    required this.eligibleFreeAgents,
    required this.affordableFreeAgents,
    required this.acceptableOffers,
    required this.unsignedDraftRights,
    required this.blockers,
  });

  final TeamId teamId;
  final String abbreviation;
  final int standardCount;
  final int requiredPlayers;
  final int capRoom;
  final int cash;
  final int projectedCash;
  final int eligibleFreeAgents;
  final int affordableFreeAgents;
  final int acceptableOffers;
  final int unsignedDraftRights;
  final List<String> blockers;

  bool get canClear => requiredPlayers > 0 && acceptableOffers > 0;
}

final class OffseasonReadinessResult {
  const OffseasonReadinessResult({
    required this.status,
    required this.reasons,
    required this.teams,
    required this.readyCount,
    required this.belowMinimumCount,
    required this.totalShortage,
    required this.humanShortage,
  });

  final OffseasonReadinessStatus status;
  final List<String> reasons;
  final List<FranchiseClearanceNeed> teams;
  final int readyCount;
  final int belowMinimumCount;
  final int totalShortage;
  final int humanShortage;

  List<FranchiseClearanceNeed> get blockedTeams => [
    for (final team in teams)
      if (team.requiredPlayers > 0 && !team.canClear) team,
  ];
}

/// Read-only authoritative offseason and league readiness gate.
final class OffseasonReadinessGate {
  const OffseasonReadinessGate({
    this.market = const FreeAgentMarketValueService(),
    this.evaluator = const FreeAgentOfferEvaluator(),
  });

  final FreeAgentMarketValueService market;
  final FreeAgentOfferEvaluator evaluator;

  OffseasonReadinessResult evaluate(
    GmCareer career, {
    bool recoveryRequired = false,
  }) {
    final reasons = <String>[];
    if (recoveryRequired) {
      reasons.add('Saved-career reconciliation is required');
    }
    if (!career.draftExecutionState.isCompleted) {
      reasons.add('Rookie draft is not complete');
    } else {
      const ai = RookieAiSigningService();
      if (ai.pendingRights(career).isNotEmpty) {
        reasons.add('AI rookie signing decisions are pending');
      }
    }
    final marketState = career.freeAgentMarket;
    if (marketState.status != FreeAgentMarketStatus.marketComplete ||
        marketState.roundNumber != 2 ||
        marketState.completedRounds != 2) {
      reasons.add('Both free-agency market rounds are not complete');
    }
    final clearance = career.offseasonClearance;
    if (clearance.isResolvable) {
      reasons.add('Clearance offers are not resolved');
    }
    if (reasons.isNotEmpty) {
      return OffseasonReadinessResult(
        status: OffseasonReadinessStatus.offseasonInProgress,
        reasons: reasons,
        teams: const [],
        readyCount: 0,
        belowMinimumCount: 0,
        totalShortage: 0,
        humanShortage: 0,
      );
    }

    try {
      career.validate();
    } catch (error) {
      return OffseasonReadinessResult(
        status: OffseasonReadinessStatus.offseasonInProgress,
        reasons: ['Career validation failed: $error'],
        teams: const [],
        readyCount: 0,
        belowMinimumCount: 0,
        totalShortage: 0,
        humanShortage: 0,
      );
    }

    final needs = <FranchiseClearanceNeed>[];
    var ready = 0;
    var below = 0;
    var shortageTotal = 0;
    var humanShortage = 0;
    final blockers = <String>[];
    for (final team in career.league.teams) {
      final readiness = team.roster.validateRegularSeasonReadiness();
      final standard = team.roster.standardCount;
      final required = (RosterRules.minRegularSeasonStandard - standard).clamp(
        0,
        RosterRules.minRegularSeasonStandard,
      );
      if (readiness.isValid) {
        ready++;
      } else {
        below++;
      }
      shortageTotal += required;
      if (team.id == career.userFranchiseId) humanShortage = required;
      if (required == 0 && readiness.isValid) continue;
      final need = _diagnoseTeam(career, team, required);
      needs.add(need);
      if (required > 0 && !need.canClear) {
        blockers.add(
          '${team.abbreviation}: $required standard player(s) needed; '
          '${need.blockers.join('; ')}',
        );
      }
    }

    if (ready == career.league.teams.length) {
      final cleared = clearance.status == OffseasonClearanceStatus.cleared;
      return OffseasonReadinessResult(
        status: cleared
            ? OffseasonReadinessStatus.cleared
            : OffseasonReadinessStatus.readyForConfirmation,
        reasons: const [],
        teams: needs,
        readyCount: ready,
        belowMinimumCount: below,
        totalShortage: shortageTotal,
        humanShortage: humanShortage,
      );
    }

    final financialException = needs.any((need) {
      return need.requiredPlayers > 0 &&
          need.capRoom < FinancialRules.minimumSalary * need.requiredPlayers &&
          !clearance.isExceptionApproved(need.teamId);
    });
    final status = financialException
        ? OffseasonReadinessStatus.financialExceptionRequired
        : OffseasonReadinessStatus.clearanceRequired;
    return OffseasonReadinessResult(
      status: status,
      reasons: [
        if (financialException)
          'At least one franchise needs cap relief for minimum contracts',
        ...blockers,
        if (clearance.status == OffseasonClearanceStatus.notStarted)
          'A bounded clearance pass is required',
      ],
      teams: needs,
      readyCount: ready,
      belowMinimumCount: below,
      totalShortage: shortageTotal,
      humanShortage: humanShortage,
    );
  }

  FranchiseClearanceNeed _diagnoseTeam(
    GmCareer career,
    Team team,
    int required,
  ) {
    final capRoom =
        FinancialRules.salaryCap -
        career.finances.capPayrollFor(team.id, career.currentYear);
    final finances = career.finances.financesFor(team.id);
    final cash = finances.cash;
    final projected = career.finances.projectedEndOfSeasonCash(
      team.id,
      career.currentYear,
    );
    var eligible = 0;
    var affordable = 0;
    var acceptable = 0;
    for (final entry in career.freeAgentPool.entries) {
      eligible++;
      var anyAffordable = false;
      final view = entry.toPublicView();
      final valuation = market.estimate(view);
      final duration = valuation.preferredDurationYears;
      final candidates =
          <int>{
            FinancialRules.minimumSalary,
            valuation.acceptableMinimum,
            valuation.estimatedAnnualSalary,
            valuation.acceptableMaximum,
          }.where((salary) {
            return salary <= FinancialRules.maximumSalary &&
                salary <= capRoom + (required <= 2 ? 0 : 0);
          });
      for (final salary in candidates) {
        final decision = evaluator.evaluate(
          career: career,
          teamId: team.id,
          freeAgentId: entry.id,
          category: RosterCategory.standard,
          durationYears: duration,
          agreedFirstYearSalary: salary,
        );
        if (decision.isFinanciallyLegal) anyAffordable = true;
        if (decision.isAcceptable) {
          acceptable++;
          break;
        }
      }
      if (anyAffordable) affordable++;
    }
    final blockers = <String>[];
    if (required == 0) {
      blockers.add('non-roster readiness issue');
    } else if (capRoom < FinancialRules.minimumSalary * required) {
      blockers.add(
        'cap room $capRoom does not cover $required minimum deal(s)',
      );
    } else if (projected < FinancialRules.minimumSalary * required) {
      blockers.add('projected cash $projected does not cover minimum deals');
    } else if (acceptable == 0) {
      blockers.add('no available player accepts a legal offer');
    }
    return FranchiseClearanceNeed(
      teamId: team.id,
      abbreviation: team.abbreviation,
      standardCount: team.roster.standardCount,
      requiredPlayers: required,
      capRoom: capRoom,
      cash: cash,
      projectedCash: projected,
      eligibleFreeAgents: eligible,
      affordableFreeAgents: affordable,
      acceptableOffers: acceptable,
      unsignedDraftRights: career.unsignedDraftRights
          .where((rights) => rights.owningTeamId == team.id)
          .length,
      blockers: blockers,
    );
  }
}
