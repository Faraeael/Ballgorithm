import '../finance/financial_rules.dart';
import '../models/free_agent_acquisition.dart';
import '../models/free_agent_market.dart';
import '../models/free_agent_offer.dart';
import '../models/hardship_settlement.dart';
import '../models/ids.dart';
import '../models/roster_category.dart';
import '../models/roster_rules.dart';
import '../models/offseason_clearance.dart';
import '../validation/validation_result.dart';
import 'career_phase.dart';
import 'competitive_offer_ranker.dart';
import 'free_agent_acquisition_service.dart';
import 'free_agent_offer_evaluator.dart';
import 'gm_career.dart';

final class HardshipTeamAssessment {
  HardshipTeamAssessment({
    required this.teamId,
    required this.abbreviation,
    required this.standardCount,
    required this.missingPlayers,
    required this.currentPayroll,
    required this.normalCapRoom,
    required this.ordinaryRelief,
    required this.projectedCash,
    required List<HardshipOffer> proposedOffers,
    required this.additionalAuthority,
    required this.combinedOverage,
    required List<String> blockers,
  }) : proposedOffers = List.unmodifiable(proposedOffers),
       blockers = List.unmodifiable(blockers);

  final TeamId teamId;
  final String abbreviation;
  final int standardCount;
  final int missingPlayers;
  final int currentPayroll;
  final int normalCapRoom;
  final int ordinaryRelief;
  final int projectedCash;
  final List<HardshipOffer> proposedOffers;
  final int additionalAuthority;
  final int combinedOverage;
  final List<String> blockers;

  bool get eligible => proposedOffers.isNotEmpty && additionalAuthority > 0;

  int get projectedCashAfterOffers =>
      projectedCash -
      proposedOffers.fold<int>(0, (sum, offer) => sum + offer.firstYearSalary);
}

/// One deterministic settlement after the original clearance has completed.
final class HardshipSettlementService {
  const HardshipSettlementService({
    this.evaluator = const FreeAgentOfferEvaluator(),
    this.ranker = const CompetitiveOfferRanker(),
    this.acquisition = const FreeAgentAcquisitionService(),
  });

  final FreeAgentOfferEvaluator evaluator;
  final CompetitiveOfferRanker ranker;
  final FreeAgentAcquisitionService acquisition;

  HardshipTeamAssessment assessTeam(GmCareer career, TeamId teamId) {
    final team = career.league.teams
        .where((candidate) => candidate.id == teamId)
        .firstOrNull;
    if (team == null) {
      throw ArgumentError.value(teamId, 'teamId', 'Unknown franchise');
    }
    final finances = career.finances.financesFor(teamId);
    final payroll = career.finances.capPayrollFor(teamId, career.currentYear);
    final capRoom = FinancialRules.salaryCap - payroll;
    final missing =
        RosterRules.minRegularSeasonStandard - team.roster.standardCount;
    final ordinaryRelief = finances.capException;
    final projectedCash = career.finances.projectedEndOfSeasonCash(
      teamId,
      career.currentYear,
    );
    final blockers = <String>[];

    if (career.phase != CareerPhase.openingOffseason) {
      blockers.add('Career is outside the opening offseason');
    }
    if (career.freeAgentMarket.status != FreeAgentMarketStatus.marketComplete ||
        career.freeAgentMarket.completedRounds != 2) {
      blockers.add('Both competitive market rounds must be complete');
    }
    if (career.offseasonClearance.status != OffseasonClearanceStatus.complete) {
      blockers.add('Original clearance must be complete');
    }
    if (career.hardshipSettlement.status !=
        HardshipSettlementStatus.notStarted) {
      blockers.add('Hardship settlement already started');
    }
    if (missing <= 0) blockers.add('No mandatory standard roster vacancy');
    if (missing > FinancialRules.maximumReliefDeals) {
      blockers.add('Shortage exceeds two standard players');
    }
    if (finances.capGrandfathered) {
      blockers.add('Grandfathered payroll cannot use hardship authority');
    }
    if (projectedCash < 0) blockers.add('Current projected cash is insolvent');
    if (blockers.isNotEmpty) {
      return HardshipTeamAssessment(
        teamId: teamId,
        abbreviation: team.abbreviation,
        standardCount: team.roster.standardCount,
        missingPlayers: missing > 0 ? missing : 0,
        currentPayroll: payroll,
        normalCapRoom: capRoom,
        ordinaryRelief: ordinaryRelief,
        projectedCash: projectedCash,
        proposedOffers: const [],
        additionalAuthority: 0,
        combinedOverage: ordinaryRelief,
        blockers: blockers,
      );
    }

    final candidates = <_HardshipCandidate>[];
    var attemptsBlocked = 0;
    for (final entry in career.freeAgentPool.entries) {
      if (career.freeAgentOffers.remainingAttempts(
            teamId: teamId,
            playerId: entry.id,
            seasonYear: career.currentYear,
          ) <=
          0) {
        attemptsBlocked++;
        continue;
      }
      final candidate = _cheapestAcceptableContract(
        career: career,
        teamId: teamId,
        playerId: entry.id,
      );
      if (candidate != null) candidates.add(candidate);
    }
    candidates.sort(_compareCandidates);
    if (candidates.isEmpty) {
      blockers.add(
        attemptsBlocked == career.freeAgentPool.length
            ? 'All remaining free agents have exhausted player-side attempts'
            : 'No available free agent accepts a standard contract',
      );
      return HardshipTeamAssessment(
        teamId: teamId,
        abbreviation: team.abbreviation,
        standardCount: team.roster.standardCount,
        missingPlayers: missing,
        currentPayroll: payroll,
        normalCapRoom: capRoom,
        ordinaryRelief: ordinaryRelief,
        projectedCash: projectedCash,
        proposedOffers: const [],
        additionalAuthority: 0,
        combinedOverage: ordinaryRelief,
        blockers: blockers,
      );
    }

    var ordinarySlots = 0;
    var ordinarySalary = 0;
    for (final candidate in candidates) {
      if (ordinarySlots >= missing) break;
      final nextSalary = ordinarySalary + candidate.offer.firstYearSalary;
      final payrollAfter = payroll + nextSalary;
      final ordinaryLegal =
          payrollAfter <= FinancialRules.salaryCap ||
          (candidate.offer.firstYearSalary == FinancialRules.minimumSalary &&
              payrollAfter <= FinancialRules.salaryCap + ordinaryRelief);
      if (ordinaryLegal && projectedCash >= nextSalary) {
        ordinarySlots++;
        ordinarySalary = nextSalary;
      }
    }
    if (ordinarySlots >= missing) {
      blockers.add(
        'Existing cap room and ordinary relief can fund all vacancies',
      );
      return HardshipTeamAssessment(
        teamId: teamId,
        abbreviation: team.abbreviation,
        standardCount: team.roster.standardCount,
        missingPlayers: missing,
        currentPayroll: payroll,
        normalCapRoom: capRoom,
        ordinaryRelief: ordinaryRelief,
        projectedCash: projectedCash,
        proposedOffers: const [],
        additionalAuthority: 0,
        combinedOverage: ordinaryRelief,
        blockers: blockers,
      );
    }

    final selected = <HardshipOffer>[];
    var committedSalary = 0;
    for (final candidate in candidates) {
      if (selected.length >= missing) break;
      final nextSalary = committedSalary + candidate.offer.firstYearSalary;
      final overage = payroll + nextSalary - FinancialRules.salaryCap;
      final additional = overage > ordinaryRelief
          ? overage - ordinaryRelief
          : 0;
      if (ordinaryRelief + additional >
              FinancialRules.maximumCombinedHardshipOverage ||
          projectedCash - nextSalary < 0) {
        continue;
      }
      selected.add(candidate.offer);
      committedSalary = nextSalary;
    }
    final totalOverage = payroll + committedSalary - FinancialRules.salaryCap;
    final additional = totalOverage > ordinaryRelief
        ? totalOverage - ordinaryRelief
        : 0;
    if (selected.isEmpty || additional <= 0) {
      blockers.add(
        'No willing contract fits cash and the 1,000 CU combined overage ceiling',
      );
      return HardshipTeamAssessment(
        teamId: teamId,
        abbreviation: team.abbreviation,
        standardCount: team.roster.standardCount,
        missingPlayers: missing,
        currentPayroll: payroll,
        normalCapRoom: capRoom,
        ordinaryRelief: ordinaryRelief,
        projectedCash: projectedCash,
        proposedOffers: const [],
        additionalAuthority: 0,
        combinedOverage: ordinaryRelief,
        blockers: blockers,
      );
    }
    if (selected.length < missing) {
      blockers.add(
        'Only ${selected.length} willing contract(s) fit the approved ceiling '
        'for $missing vacancy/vacancies',
      );
    }
    return HardshipTeamAssessment(
      teamId: teamId,
      abbreviation: team.abbreviation,
      standardCount: team.roster.standardCount,
      missingPlayers: missing,
      currentPayroll: payroll,
      normalCapRoom: capRoom,
      ordinaryRelief: ordinaryRelief,
      projectedCash: projectedCash,
      proposedOffers: selected,
      additionalAuthority: additional,
      combinedOverage: ordinaryRelief + additional,
      blockers: blockers,
    );
  }

  List<HardshipOffer> proposedHumanOffers(GmCareer career) =>
      assessTeam(career, career.userFranchiseId).proposedOffers;

  GmCareer prepare(
    GmCareer career, {
    required bool humanParticipationConfirmed,
  }) {
    if (career.phase != CareerPhase.openingOffseason ||
        career.freeAgentMarket.status != FreeAgentMarketStatus.marketComplete ||
        career.offseasonClearance.status != OffseasonClearanceStatus.complete ||
        career.hardshipSettlement.status !=
            HardshipSettlementStatus.notStarted) {
      _fail('Hardship settlement is not authorized in this career state');
    }
    career.validate();
    final offers = <HardshipOffer>[];
    final teams = [...career.league.teams]
      ..sort((left, right) => left.id.value.compareTo(right.id.value));
    for (final team in teams) {
      if (team.id == career.userFranchiseId && !humanParticipationConfirmed) {
        continue;
      }
      offers.addAll(assessTeam(career, team.id).proposedOffers);
    }
    offers.sort((left, right) {
      final team = left.teamId.value.compareTo(right.teamId.value);
      return team != 0
          ? team
          : left.playerId.value.compareTo(right.playerId.value);
    });
    final authorizations = <HardshipAuthorization>[];
    for (final team in teams) {
      final teamOffers = offers
          .where((offer) => offer.teamId == team.id)
          .toList();
      if (teamOffers.isEmpty) continue;
      final assessment = assessTeam(career, team.id);
      final authorization = HardshipAuthorization(
        authorizationId: HardshipAuthorization.idFor(
          team.id,
          career.currentYear,
        ),
        teamId: team.id,
        seasonYear: career.currentYear,
        additionalAmount: assessment.additionalAuthority,
        existingOrdinaryRelief: assessment.ordinaryRelief,
        maximumCombinedOverage: FinancialRules.maximumCombinedHardshipOverage,
        missingPlayers: assessment.missingPlayers,
        authorizedOfferIds: [for (final offer in teamOffers) offer.offerId],
        reason: hardshipAuthorizationReason,
        status: HardshipAuthorizationStatus.unused,
        usedAmount: 0,
        transactionIds: const [],
      );
      authorizations.add(authorization);
    }
    final order = {for (final offer in offers) offer.playerId.value}.toList()
      ..sort();
    final settlement = HardshipSettlement(
      status: offers.isEmpty
          ? HardshipSettlementStatus.complete
          : HardshipSettlementStatus.preparedForResolution,
      seasonYear: career.currentYear,
      humanParticipationConfirmed: humanParticipationConfirmed,
      offers: offers,
      resolutionOrder: [for (final id in order) PlayerId(id)],
      nextResolutionIndex: 0,
      outcomes: const [],
      authorizations: authorizations,
    );
    return career.copyWith(hardshipSettlement: settlement);
  }

  GmCareer resolveNext(GmCareer career) {
    final settlement = career.hardshipSettlement;
    if (!settlement.isResolvable) {
      _fail('Hardship settlement is not ready for resolution');
    }
    if (settlement.nextResolutionIndex >= settlement.resolutionOrder.length) {
      return career.copyWith(
        hardshipSettlement: settlement.copyWith(
          status: HardshipSettlementStatus.complete,
        ),
      );
    }
    final playerId = settlement.resolutionOrder[settlement.nextResolutionIndex];
    final offers = settlement.offersFor(playerId);
    final results = <FreeAgentMarketOfferResult>[];
    final rejected = <HardshipOffer, FreeAgentOfferDecision>{};
    final acceptable = <HardshipOffer>[];
    for (final offer in offers) {
      final team = career.league.teams.firstWhere(
        (candidate) => candidate.id == offer.teamId,
      );
      if (team.roster.standardCount >= RosterRules.minRegularSeasonStandard) {
        results.add(
          FreeAgentMarketOfferResult(
            offerId: offer.offerId,
            teamId: offer.teamId,
            outcome: FreeAgentMarketOfferOutcome.financiallyUnavailable,
            reasonCode: 'rosterAlreadyAtMinimum',
          ),
        );
        continue;
      }
      final decision = evaluator.evaluate(
        career: career,
        teamId: offer.teamId,
        freeAgentId: offer.playerId,
        category: RosterCategory.standard,
        durationYears: offer.durationYears,
        agreedFirstYearSalary: offer.firstYearSalary,
        hardshipOfferId: offer.offerId,
      );
      if (decision.status == FreeAgentOfferStatus.acceptable) {
        acceptable.add(offer);
      } else if (decision.status == FreeAgentOfferStatus.financiallyIllegal ||
          decision.status == FreeAgentOfferStatus.invalidTerms) {
        results.add(
          FreeAgentMarketOfferResult(
            offerId: offer.offerId,
            teamId: offer.teamId,
            outcome: FreeAgentMarketOfferOutcome.financiallyUnavailable,
            reasonCode: decision.reasonCode,
          ),
        );
      } else {
        rejected[offer] = decision;
        results.add(
          FreeAgentMarketOfferResult(
            offerId: offer.offerId,
            teamId: offer.teamId,
            outcome: FreeAgentMarketOfferOutcome.rejected,
            reasonCode: decision.reasonCode,
          ),
        );
      }
    }
    final ranked = ranker.rankHardship(
      career: career,
      playerId: playerId,
      offers: acceptable,
    );
    HardshipOffer? winner;
    for (final offer in ranked) {
      final team = career.league.teams.firstWhere(
        (candidate) => candidate.id == offer.teamId,
      );
      if (team.roster.standardCount >= RosterRules.minRegularSeasonStandard) {
        results.add(
          FreeAgentMarketOfferResult(
            offerId: offer.offerId,
            teamId: offer.teamId,
            outcome: FreeAgentMarketOfferOutcome.financiallyUnavailable,
            reasonCode: 'rosterAlreadyAtMinimum',
          ),
        );
        continue;
      }
      winner = offer;
      break;
    }
    if (winner != null) {
      for (final offer in ranked) {
        if (offer.offerId == winner.offerId ||
            results.any((result) => result.offerId == offer.offerId)) {
          continue;
        }
        results.add(
          FreeAgentMarketOfferResult(
            offerId: offer.offerId,
            teamId: offer.teamId,
            outcome: FreeAgentMarketOfferOutcome.outbid,
            reasonCode: 'outbid',
          ),
        );
      }
      for (final offer in offers) {
        if (!acceptable.contains(offer) ||
            offer.offerId == winner.offerId ||
            results.any((result) => result.offerId == offer.offerId)) {
          continue;
        }
        results.add(
          FreeAgentMarketOfferResult(
            offerId: offer.offerId,
            teamId: offer.teamId,
            outcome: FreeAgentMarketOfferOutcome.outbid,
            reasonCode: 'outbid',
          ),
        );
      }
      results.add(
        FreeAgentMarketOfferResult(
          offerId: winner.offerId,
          teamId: winner.teamId,
          outcome: FreeAgentMarketOfferOutcome.accepted,
          reasonCode: 'accepted',
        ),
      );
    }
    var ledger = career.freeAgentOffers;
    for (final entry in rejected.entries) {
      ledger = _appendAttempt(
        ledger: ledger,
        offer: entry.key,
        outcome: _attemptOutcome(entry.value.status),
        reasonCode: entry.value.reasonCode,
        transactionId: null,
      );
    }
    final nextIndex = settlement.nextResolutionIndex + 1;
    final complete = nextIndex >= settlement.resolutionOrder.length;
    final authorizations = [...settlement.authorizations];
    if (winner != null) {
      final acquisitionId = FreeAgentAcquisition.idFor(
        winner.playerId,
        career.currentYear,
      );
      final authorizationIndex = authorizations.indexWhere(
        (authorization) => authorization.teamId == winner!.teamId,
      );
      if (authorizationIndex < 0) {
        _fail('Winning hardship offer lacks cap authorization');
      }
      final authorization = authorizations[authorizationIndex];
      final payrollAfter =
          career.finances.capPayrollFor(winner.teamId, career.currentYear) +
          winner.firstYearSalary;
      final actualOverage =
          payrollAfter -
          FinancialRules.salaryCap -
          authorization.existingOrdinaryRelief;
      final usedAmount = actualOverage > 0 ? actualOverage : 0;
      if (usedAmount > authorization.additionalAmount) {
        _fail('Winning offer exceeds exact hardship authority');
      }
      authorizations[authorizationIndex] = authorization.copyWith(
        status: HardshipAuthorizationStatus.consumed,
        usedAmount: usedAmount,
        transactionIds: [...authorization.transactionIds, acquisitionId],
      );
      ledger = _appendAttempt(
        ledger: ledger,
        offer: winner,
        outcome: FreeAgentOfferOutcome.accepted,
        reasonCode: 'accepted',
        transactionId: acquisitionId,
      );
    }
    final outcome = HardshipOutcome(
      playerId: playerId,
      winningTeamId: winner?.teamId,
      winningOfferId: winner?.offerId,
      results: results,
    );
    final nextSettlement = settlement.copyWith(
      status: complete
          ? HardshipSettlementStatus.complete
          : HardshipSettlementStatus.resolving,
      nextResolutionIndex: nextIndex,
      outcomes: [...settlement.outcomes, outcome],
      authorizations: authorizations,
    );
    if (winner == null) {
      return career.copyWith(
        freeAgentOffers: ledger,
        hardshipSettlement: nextSettlement,
      );
    }
    return acquisition.acquire(
      career: career,
      teamId: winner.teamId,
      freeAgentId: winner.playerId,
      category: RosterCategory.standard,
      durationYears: winner.durationYears,
      agreedFirstYearSalary: winner.firstYearSalary,
      origin: AcquisitionOrigin.hardship,
      hardshipOfferId: winner.offerId,
      hardshipSettlementAfterAcquisition: nextSettlement,
      freeAgentOffersAfterAcquisition: ledger,
    );
  }

  _HardshipCandidate? _cheapestAcceptableContract({
    required GmCareer career,
    required TeamId teamId,
    required PlayerId playerId,
  }) {
    _HardshipCandidate? cheapest;
    for (
      var duration = 1;
      duration <=
          FinancialRules.maxDurationForCategory(RosterCategory.standard);
      duration++
    ) {
      var low = FinancialRules.minimumSalary;
      var high = FinancialRules.maximumSalary + 1;
      while (low < high) {
        final salary = low + (high - low) ~/ 2;
        final willingness = evaluator.evaluateWillingness(
          career: career,
          teamId: teamId,
          freeAgentId: playerId,
          category: RosterCategory.standard,
          durationYears: duration,
          salary: salary,
        );
        if (willingness.accepts) {
          high = salary;
        } else {
          low = salary + 1;
        }
      }
      if (low > FinancialRules.maximumSalary) continue;
      final willingness = evaluator.evaluateWillingness(
        career: career,
        teamId: teamId,
        freeAgentId: playerId,
        category: RosterCategory.standard,
        durationYears: duration,
        salary: low,
      );
      if (!willingness.accepts) continue;
      if (FinancialRules.standardSchedule(
        low,
        duration,
      ).any((salary) => salary > FinancialRules.maximumSalary)) {
        continue;
      }
      final offer = HardshipOffer(
        offerId: HardshipOffer.idFor(
          teamId: teamId,
          playerId: playerId,
          seasonYear: career.currentYear,
        ),
        playerId: playerId,
        teamId: teamId,
        seasonYear: career.currentYear,
        durationYears: duration,
        firstYearSalary: low,
        source: teamId == career.userFranchiseId
            ? FreeAgentMarketOfferSource.human
            : FreeAgentMarketOfferSource.ai,
      );
      final candidate = _HardshipCandidate(offer);
      if (cheapest == null || _compareCandidates(candidate, cheapest) < 0) {
        cheapest = candidate;
      }
    }
    return cheapest;
  }

  static int _compareCandidates(
    _HardshipCandidate left,
    _HardshipCandidate right,
  ) {
    var compare = left.offer.firstYearSalary.compareTo(
      right.offer.firstYearSalary,
    );
    if (compare != 0) return compare;
    compare = left.totalSalary.compareTo(right.totalSalary);
    if (compare != 0) return compare;
    compare = left.offer.durationYears.compareTo(right.offer.durationYears);
    if (compare != 0) return compare;
    return left.offer.playerId.value.compareTo(right.offer.playerId.value);
  }

  FreeAgentOfferLedger _appendAttempt({
    required FreeAgentOfferLedger ledger,
    required HardshipOffer offer,
    required FreeAgentOfferOutcome outcome,
    required String reasonCode,
    required String? transactionId,
  }) {
    final attempts = ledger.attemptsFor(
      teamId: offer.teamId,
      playerId: offer.playerId,
      seasonYear: offer.seasonYear,
    );
    if (attempts.length >= FreeAgentOfferAttempt.maximumPlayerSideAttempts) {
      _fail('Hardship offer has no player-side attempt remaining');
    }
    return ledger.add(
      FreeAgentOfferAttempt(
        offerId: offer.offerId,
        playerId: offer.playerId,
        teamId: offer.teamId,
        seasonYear: offer.seasonYear,
        category: RosterCategory.standard,
        durationYears: offer.durationYears,
        firstYearSalary: offer.firstYearSalary,
        outcome: outcome,
        reasonCode: reasonCode,
        attemptNumber: attempts.length + 1,
        acquisitionTransactionId: transactionId,
      ),
    );
  }

  static FreeAgentOfferOutcome _attemptOutcome(FreeAgentOfferStatus status) =>
      switch (status) {
        FreeAgentOfferStatus.salaryTooLow => FreeAgentOfferOutcome.salaryTooLow,
        FreeAgentOfferStatus.unfavorableDuration =>
          FreeAgentOfferOutcome.unfavorableDuration,
        FreeAgentOfferStatus.poorFit => FreeAgentOfferOutcome.poorFit,
        FreeAgentOfferStatus.inappropriateCategory =>
          FreeAgentOfferOutcome.inappropriateCategory,
        _ => throw ArgumentError.value(status, 'status'),
      };

  static Never _fail(String message) => throw DomainValidationException([
    ValidationIssue(
      code: ValidationCode.freeAgentAcquisitionInvalid,
      path: 'hardshipSettlement',
      message: message,
    ),
  ]);
}

final class _HardshipCandidate {
  const _HardshipCandidate(this.offer);

  final HardshipOffer offer;

  int get totalSalary => offer.salarySchedule.fold<int>(0, (a, b) => a + b);
}
