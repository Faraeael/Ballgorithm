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
    required this.authorizedCapRelief,
    required this.cash,
    required this.projectedCash,
    required this.eligibleFreeAgents,
    required this.financiallyLegalMinimumOffers,
    required this.willingMinimumOffers,
    required this.willingAndLegalMinimumOffers,
    required this.playerRejectedMinimumOffers,
    required this.attemptBlockedMinimumOffers,
    required this.acquiredByOtherFranchises,
    required this.acceptableOffers,
    required this.unsignedDraftRights,
    required this.blockers,
  });

  final TeamId teamId;
  final String abbreviation;
  final int standardCount;
  final int requiredPlayers;
  final int capRoom;
  final int authorizedCapRelief;
  final int cash;
  final int projectedCash;
  final int eligibleFreeAgents;
  final int financiallyLegalMinimumOffers;
  final int willingMinimumOffers;
  final int willingAndLegalMinimumOffers;
  final int playerRejectedMinimumOffers;
  final int attemptBlockedMinimumOffers;
  final int acquiredByOtherFranchises;
  final int acceptableOffers;
  final int unsignedDraftRights;
  final List<String> blockers;

  bool get canClear =>
      requiredPlayers > 0 && acceptableOffers >= requiredPlayers;
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
    if (reasons.isNotEmpty &&
        !(clearance.isResolvable &&
            reasons.length == 1 &&
            reasons.single == 'Clearance offers are not resolved')) {
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
    if (clearance.isResolvable) {
      return OffseasonReadinessResult(
        status: OffseasonReadinessStatus.offseasonInProgress,
        reasons: reasons,
        teams: needs,
        readyCount: ready,
        belowMinimumCount: below,
        totalShortage: shortageTotal,
        humanShortage: humanShortage,
      );
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
          need.capRoom + need.authorizedCapRelief <
              FinancialRules.minimumSalary * need.requiredPlayers;
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
    final authorizedRelief =
        career.offseasonClearance.capExceptions
            .where((exception) => exception.teamId == team.id)
            .firstOrNull
            ?.amount ??
        0;
    var eligible = 0;
    var willingAtMinimum = 0;
    var legalAtMinimum = 0;
    var willingAndLegalAtMinimum = 0;
    var rejectedAtMinimum = 0;
    var attemptBlocked = 0;
    var acceptable = 0;
    for (final entry in career.freeAgentPool.entries) {
      eligible++;
      final view = entry.toPublicView();
      final valuation = market.estimate(view);
      final duration = valuation.preferredDurationYears;
      final attemptRemaining = career.freeAgentOffers.remainingAttempts(
        teamId: team.id,
        playerId: entry.id,
        seasonYear: career.currentYear,
      );
      if (attemptRemaining == 0) attemptBlocked++;

      final minDecision = evaluator.evaluate(
        career: career,
        teamId: team.id,
        freeAgentId: entry.id,
        category: RosterCategory.standard,
        durationYears: duration,
        agreedFirstYearSalary: FinancialRules.minimumSalary,
        clearanceOffer: true,
      );
      final minWillingness = evaluator.evaluateWillingness(
        career: career,
        teamId: team.id,
        freeAgentId: entry.id,
        category: RosterCategory.standard,
        durationYears: duration,
        salary: FinancialRules.minimumSalary,
      );
      if (minWillingness.accepts) willingAtMinimum++;
      if (minDecision.isFinanciallyLegal) {
        legalAtMinimum++;
        if (minDecision.isAcceptable) {
          willingAndLegalAtMinimum++;
        } else {
          rejectedAtMinimum++;
        }
      }

      final maxSalary = FreeAgentMarketValueService.maxYearOneForDuration(
        duration,
      );
      var low = FinancialRules.minimumSalary;
      var high = maxSalary + 1;
      while (low < high) {
        final candidate = low + (high - low) ~/ 2;
        final response = evaluator.evaluateWillingness(
          career: career,
          teamId: team.id,
          freeAgentId: entry.id,
          category: RosterCategory.standard,
          durationYears: duration,
          salary: candidate,
        );
        if (response.accepts) {
          high = candidate;
        } else {
          low = candidate + 1;
        }
      }
      if (low <= maxSalary && attemptRemaining > 0) {
        final decision = evaluator.evaluate(
          career: career,
          teamId: team.id,
          freeAgentId: entry.id,
          category: RosterCategory.standard,
          durationYears: duration,
          agreedFirstYearSalary: low,
          clearanceOffer: true,
        );
        if (decision.isFinanciallyLegal) {
          if (decision.isAcceptable) acceptable++;
        }
      }
    }
    final blockers = <String>[];
    if (required == 0) {
      blockers.add('non-roster readiness issue');
    } else if (capRoom + authorizedRelief <
        FinancialRules.minimumSalary * required) {
      blockers.add(
        'cap room $capRoom plus authorized relief $authorizedRelief does not '
        'cover $required minimum deal(s)',
      );
    } else if (projected < FinancialRules.minimumSalary * required) {
      blockers.add('projected cash $projected does not cover minimum deals');
    } else if (acceptable < required) {
      blockers.add(
        'only $acceptable distinct remaining player(s) accept a legal offer '
        'for $required spot(s)',
      );
    }
    return FranchiseClearanceNeed(
      teamId: team.id,
      abbreviation: team.abbreviation,
      standardCount: team.roster.standardCount,
      requiredPlayers: required,
      capRoom: capRoom,
      authorizedCapRelief: authorizedRelief,
      cash: cash,
      projectedCash: projected,
      eligibleFreeAgents: eligible,
      financiallyLegalMinimumOffers: legalAtMinimum,
      willingMinimumOffers: willingAtMinimum,
      willingAndLegalMinimumOffers: willingAndLegalAtMinimum,
      playerRejectedMinimumOffers: rejectedAtMinimum,
      attemptBlockedMinimumOffers: attemptBlocked,
      acquiredByOtherFranchises: career
          .freeAgentPool
          .acquisitions
          .entries
          .values
          .where((acquisition) => acquisition.teamId != team.id)
          .length,
      acceptableOffers: acceptable,
      unsignedDraftRights: career.unsignedDraftRights
          .where((rights) => rights.owningTeamId == team.id)
          .length,
      blockers: blockers,
    );
  }
}
