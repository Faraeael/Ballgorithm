// M008-T08H-P2 hardship feasibility diagnostics. Run from packages/simulation_core:
//   dart run tool/t08h_p2_hardship_diagnostics.dart
import 'package:simulation_core/simulation_core.dart';

const _requiredSeeds = [20261028, 1604126146, 987654321];
const _heldOutSeeds = [314159265, 271828182, 8675309];
const _situations = FranchiseSituation.values;
const _draft = DraftExecutionService();
const _aiRookies = RookieAiSigningService();
const _market = FreeAgentMarketService();
const _clearance = OffseasonClearanceService();
const _hardship = HardshipSettlementService();
const _gate = OffseasonReadinessGate();
const _evaluator = FreeAgentOfferEvaluator();
const _marketValue = FreeAgentMarketValueService();

void main() {
  for (final seed in [..._requiredSeeds, ..._heldOutSeeds]) {
    for (final situation in _situations) {
      _run(seed, situation);
    }
  }
}

void _run(int seed, FranchiseSituation situation) {
  var career = GmCareer.fromSetupResult(
    CareerSetupService().generate(
      CareerSetupRequest(
        selectedTeamId: const TeamId('team-1'),
        selectedSituation: situation,
        seed: seed,
      ),
    ),
    id: 't08h-p2-$seed-${situation.jsonValue}',
  );
  career = _completeDraft(career);
  career = _completeAiRookieDecisions(career);
  career = _completeMarketRounds(career);
  final afterRounds = career;
  final afterAuthorization = _clearance.start(career);
  final afterSealing = _sealClearance(afterAuthorization);
  final afterClearance = _resolveClearance(afterSealing);
  final before = _gate.evaluate(afterRounds);
  final afterAuthorizationReadiness = _gate.evaluate(afterAuthorization);
  final afterSealingReadiness = _gate.evaluate(afterSealing);
  final afterClearanceReadiness = _gate.evaluate(afterClearance);
  final teamAssessments = [
    for (final team in afterClearance.league.teams)
      _hardship.assessTeam(afterClearance, team.id),
  ];
  var settled = _hardship.prepare(
    afterClearance,
    humanParticipationConfirmed: false,
  );
  var guard = 0;
  while (settled.hardshipSettlement.isResolvable) {
    settled = _hardship.resolveNext(settled);
    if (++guard > 90) {
      throw StateError('Hardship resolution exceeded pool size');
    }
  }
  final after = _gate.evaluate(settled);
  final beforeCounts = _counts(before);
  final afterCounts = _counts(after);
  final offers = settled.hardshipSettlement.offers;
  final outcomes = settled.hardshipSettlement.outcomes;
  final hardAcquisitions = settled.freeAgentPool.acquisitions.entries.values
      .where((item) => item.origin == AcquisitionOrigin.hardship)
      .toList();
  final rejections = outcomes
      .expand((outcome) => outcome.results)
      .where((result) => result.outcome == FreeAgentMarketOfferOutcome.rejected)
      .length;
  final outbids = outcomes
      .expand((outcome) => outcome.results)
      .where((result) => result.outcome == FreeAgentMarketOfferOutcome.outbid)
      .length;
  final authorizedRelief = settled.hardshipSettlement.authorizations.fold<int>(
    0,
    (sum, record) => sum + record.additionalAmount,
  );
  final usedRelief = settled.hardshipSettlement.authorizations.fold<int>(
    0,
    (sum, record) => sum + record.usedAmount,
  );
  final ordinaryUsed = settled.league.teams.fold<int>(0, (sum, team) {
    final overage =
        settled.finances.capPayrollFor(team.id, settled.currentYear) -
        FinancialRules.salaryCap;
    final hardshipUsed =
        settled.hardshipSettlement.authorizationFor(team.id)?.usedAmount ?? 0;
    final used = (overage - hardshipUsed)
        .clamp(0, settled.finances.financesFor(team.id).capException)
        .toInt();
    return sum + used;
  });
  final totalExceptionUsed = ordinaryUsed + usedRelief;
  final aiClearanceAcquisitions = afterClearance
      .freeAgentPool
      .acquisitions
      .entries
      .values
      .where(
        (item) =>
            item.origin == AcquisitionOrigin.clearance &&
            item.teamId != afterClearance.userFranchiseId,
      )
      .length;

  final marketRounds = afterClearance.freeAgentMarket.roundHistory;
  final normalMarketOffers = marketRounds
      .expand((round) => [...round.humanOffers, ...round.aiOffers])
      .toList();
  final normalMarketResults = marketRounds
      .expand((round) => round.outcomes)
      .expand((outcome) => outcome.results)
      .toList();
  final normalMarketAcquisitions = afterClearance
      .freeAgentPool
      .acquisitions
      .entries
      .values
      .where((item) => item.origin == AcquisitionOrigin.initialPool)
      .length;
  final blockedTeamIds = after.teams
      .where((team) => team.requiredPlayers > 0)
      .map((team) => team.teamId.value)
      .toSet();
  final outbidTeamIds = <String>{
    for (final result in normalMarketResults)
      if (result.outcome == FreeAgentMarketOfferOutcome.outbid)
        result.teamId.value,
    for (final outcome in afterClearance.offseasonClearance.outcomes)
      for (final result in outcome.results)
        if (result.outcome == FreeAgentMarketOfferOutcome.outbid)
          result.teamId.value,
    for (final outcome in settled.hardshipSettlement.outcomes)
      for (final result in outcome.results)
        if (result.outcome == FreeAgentMarketOfferOutcome.outbid)
          result.teamId.value,
  };
  final rejectedTeamIds = <String>{
    for (final result in normalMarketResults)
      if (result.outcome == FreeAgentMarketOfferOutcome.rejected)
        result.teamId.value,
    for (final outcome in afterClearance.offseasonClearance.outcomes)
      for (final result in outcome.results)
        if (result.outcome == FreeAgentMarketOfferOutcome.rejected)
          result.teamId.value,
    for (final outcome in settled.hardshipSettlement.outcomes)
      for (final result in outcome.results)
        if (result.outcome == FreeAgentMarketOfferOutcome.rejected)
          result.teamId.value,
  };
  final financiallyBlockedCount = after.teams.where((need) {
    if (need.requiredPlayers <= 0) return false;
    final assessment = teamAssessments.firstWhere(
      (item) => item.teamId == need.teamId,
    );
    return assessment.blockers.any(
      (reason) =>
          reason.contains('cash insolvent') ||
          reason.contains('No willing contract fits cash') ||
          reason.contains('fit the approved ceiling'),
    );
  }).length;
  final competitionBlockedCount = blockedTeamIds
      .intersection(outbidTeamIds)
      .length;
  final playerRejectionBlockedCount = blockedTeamIds
      .intersection(rejectedTeamIds)
      .length;

  print('\nCASE seed=$seed situation=${situation.jsonValue}');
  print(
    'Normal market: offers=${normalMarketOffers.length} '
    'AI offers=${normalMarketOffers.where((offer) => offer.source == FreeAgentMarketOfferSource.ai).length} '
    'acquisitions=$normalMarketAcquisitions '
    'outbids=${normalMarketResults.where((result) => result.outcome == FreeAgentMarketOfferOutcome.outbid).length} '
    'rejections=${normalMarketResults.where((result) => result.outcome == FreeAgentMarketOfferOutcome.rejected).length}',
  );
  _printSnapshot('A after two normal market rounds', afterRounds, before);
  _printSnapshot(
    'B immediately after exception authorization',
    afterAuthorization,
    afterAuthorizationReadiness,
  );
  _printSnapshot(
    'C after clearance offers are sealed',
    afterSealing,
    afterSealingReadiness,
  );
  _printSnapshot(
    'D after original clearance resolution',
    afterClearance,
    afterClearanceReadiness,
  );
  print(
    'Human franchise=${afterClearance.league.teams.firstWhere((team) => team.id == afterClearance.userFranchiseId).abbreviation} '
    'normalMarketOffers=${normalMarketOffers.where((offer) => offer.teamId == afterClearance.userFranchiseId).length} '
    'hardshipOffers=${offers.where((offer) => offer.teamId == afterClearance.userFranchiseId).length} '
    'hardshipConfirmation=false (no human participation auto-approved)',
  );
  print(
    'Hardship authorizations: team | ordinary relief | additional authorized '
    '| combined authorized | used additional | status',
  );
  for (final authorization in settled.hardshipSettlement.authorizations) {
    print(
      '${authorization.teamId.value} | ${authorization.existingOrdinaryRelief} | '
      '${authorization.additionalAmount} | '
      '${authorization.existingOrdinaryRelief + authorization.additionalAmount} | '
      '${authorization.usedAmount} | ${authorization.status.name}',
    );
  }
  print('Hardship offers/results: team | player | salary | duration | result');
  for (final offer in offers) {
    final matchingOutcomes = outcomes.where(
      (item) => item.playerId == offer.playerId,
    );
    final outcome = matchingOutcomes.isEmpty ? null : matchingOutcomes.first;
    final matchingResults = outcome?.results.where(
      (item) => item.offerId == offer.offerId,
    );
    final result = matchingResults == null || matchingResults.isEmpty
        ? null
        : matchingResults.first;
    print(
      '${offer.teamId.value} | ${offer.playerId.value} | '
      '${offer.firstYearSalary} | ${offer.durationYears} | '
      '${result?.outcome.name ?? 'pending'}:${result?.reasonCode ?? ''}',
    );
  }
  for (final authorization in settled.hardshipSettlement.authorizations) {
    for (final acquisition in hardAcquisitions.where(
      (item) => item.teamId == authorization.teamId,
    )) {
      final contract = settled.finances.contractForPlayer(
        acquisition.playerId,
      )!;
      final schedule = settled.finances.schedules[contract.id]!;
      print(
        '  contract ${acquisition.teamId.value}/${acquisition.playerId.value}: '
        'salary=${schedule.annualSalaries.first} '
        'schedule=${schedule.annualSalaries.join('/')} '
        'years=${contract.durationYears} '
        'future=${schedule.annualSalaries.skip(1).fold<int>(0, (sum, value) => sum + value)}',
      );
    }
  }
  final highestCombined = settled.hardshipSettlement.authorizations.fold<int>(
    0,
    (highest, record) {
      final combined = record.existingOrdinaryRelief + record.usedAmount;
      return combined > highest ? combined : highest;
    },
  );
  print(
    'Before hardship: ready=${beforeCounts.ready}/30 vacancies='
    '${beforeCounts.vacancies} financiallyEligibleMinimumOffers='
    '${beforeCounts.financiallyLegal} willingMinimumOffers='
    '${beforeCounts.willing} AIclearanceAcquisitions=$aiClearanceAcquisitions',
  );
  print(
    'Hardship: eligibleTeams=${teamAssessments.where((item) => item.eligible).length} '
    'offers=${offers.length} rejections=$rejections outbids=$outbids '
    'acquisitions=${hardAcquisitions.length} '
    'financialBlocks=$financiallyBlockedCount '
    'competitionBlocks=$competitionBlockedCount '
    'playerRejectionBlocks=$playerRejectionBlockedCount '
    'authorizedAdditional=$authorizedRelief usedOrdinary=$ordinaryUsed '
    'usedAdditional=$usedRelief totalExceptionUsed=$totalExceptionUsed '
    'highestCombinedOverage=$highestCombined',
  );
  print(
    'After hardship: ready=${afterCounts.ready}/30 vacancies='
    '${afterCounts.vacancies} financiallyEligibleMinimumOffers='
    '${afterCounts.financiallyLegal} willingMinimumOffers='
    '${afterCounts.willing} status=${after.status.name} '
    'currentYear=${settled.currentYear} phase=${settled.phase.name}',
  );
  final blocked = after.teams.where((team) => team.requiredPlayers > 0).toList()
    ..sort((a, b) => a.teamId.value.compareTo(b.teamId.value));
  if (blocked.isEmpty) {
    print('Remaining blocked franchises: none');
  } else {
    print(
      'team (human/AI) | roster | payroll | capRoom | ordinary | missing '
      '| lowest willing | total first-year | extra relief needed | cash after '
      '| future salary | unsigned rookies | eligibility/results',
    );
    for (final need in blocked) {
      final assessment = teamAssessments.firstWhere(
        (item) => item.teamId == need.teamId,
      );
      _printBlockedTeam(settled, need, assessment);
    }
  }
  settled.validate();
}

GmCareer _completeDraft(GmCareer career) {
  var current = _draft.startDraft(career);
  while (!current.draftExecutionState.isCompleted) {
    current =
        current.draftExecutionState.isHumanTurn(
          order: current.draftOrder,
          userTeamId: current.userFranchiseId,
        )
        ? _draft.makeHumanSelection(
            career: current,
            prospectId: current.draftExecutionState
                .availableProspects(current.draftClass)
                .first
                .id,
          )
        : _draft.executeAiSelection(current);
  }
  return current;
}

GmCareer _completeAiRookieDecisions(GmCareer career) {
  var current = _aiRookies.initialize(career);
  var guard = 0;
  while (_aiRookies.pendingRights(current).isNotEmpty) {
    current = _aiRookies.applyNextDecision(current);
    if (++guard > 200) throw StateError('AI rookie signing loop');
  }
  return current;
}

GmCareer _completeMarketRounds(GmCareer career) {
  var current = career;
  for (var round = 0; round < 2; round++) {
    current = _market.startRound(current);
    current = _market.prepareResolution(current);
    var guard = 0;
    while (current.freeAgentMarket.isResolvable) {
      current = _market.resolveNext(current);
      if (++guard > FreeAgentPool.expectedSize) {
        throw StateError('Free-agent market resolution exceeded pool size');
      }
    }
  }
  return current;
}

GmCareer _sealClearance(GmCareer career) {
  var current = career;
  final missing =
      RosterRules.minRegularSeasonStandard -
      current.userTeam.roster.standardCount;
  for (final entry in current.freeAgentPool.entries) {
    if (current.offseasonClearance.humanOffers.length >= missing) break;
    final offer = _cheapestAcceptable(
      current,
      current.userFranchiseId,
      entry.id,
      minimumOnly: true,
    );
    if (offer == null || offer.salary != FinancialRules.minimumSalary) continue;
    final decision = _evaluator.evaluate(
      career: current,
      teamId: current.userFranchiseId,
      freeAgentId: entry.id,
      category: RosterCategory.standard,
      durationYears: offer.duration,
      agreedFirstYearSalary: offer.salary,
      clearanceOffer: true,
    );
    if (!decision.isFinanciallyLegal) continue;
    try {
      current = _clearance.stageHumanOffer(
        career: current,
        teamId: current.userFranchiseId,
        playerId: entry.id,
        durationYears: offer.duration,
        firstYearSalary: offer.salary,
      );
    } on DomainValidationException {
      // A preceding reservation can make a later player unaffordable.
    }
  }
  return _clearance.prepare(current);
}

GmCareer _resolveClearance(GmCareer career) {
  var current = career;
  var guard = 0;
  while (current.offseasonClearance.isResolvable) {
    current = _clearance.resolveNext(current);
    if (++guard > FreeAgentPool.expectedSize) {
      throw StateError('Clearance resolution exceeded pool size');
    }
  }
  return current;
}

({int ready, int vacancies, int financiallyLegal, int willing}) _counts(
  OffseasonReadinessResult result,
) => (
  ready: result.readyCount,
  vacancies: result.totalShortage,
  financiallyLegal: result.teams.fold<int>(
    0,
    (sum, team) => sum + team.financiallyLegalMinimumOffers,
  ),
  willing: result.teams.fold<int>(
    0,
    (sum, team) => sum + team.willingMinimumOffers,
  ),
);

void _printSnapshot(
  String label,
  GmCareer career,
  OffseasonReadinessResult readiness,
) {
  final counts = _counts(readiness);
  print(
    '$label: ready=${counts.ready}/30 vacancies=${counts.vacancies} '
    'financiallyEligibleMinimumOffers=${counts.financiallyLegal} '
    'willingMinimumOffers=${counts.willing} '
    'clearanceAcquisitions=${career.freeAgentPool.acquisitions.entries.values.where((item) => item.origin == AcquisitionOrigin.clearance).length} '
    'hardshipStatus=${career.hardshipSettlement.status.name}',
  );
}

void _printBlockedTeam(
  GmCareer career,
  FranchiseClearanceNeed need,
  HardshipTeamAssessment assessment,
) {
  final payroll = career.finances.capPayrollFor(
    need.teamId,
    career.currentYear,
  );
  final ordinary = career.finances.financesFor(need.teamId).capException;
  final candidates = <_CheapestContract>[];
  for (final entry in career.freeAgentPool.entries) {
    final offer = _cheapestAcceptable(career, need.teamId, entry.id);
    if (offer != null) candidates.add(offer);
  }
  candidates.sort((a, b) {
    final salary = a.salary.compareTo(b.salary);
    if (salary != 0) return salary;
    final total = a.schedule
        .fold<int>(0, (sum, value) => sum + value)
        .compareTo(b.schedule.fold<int>(0, (sum, value) => sum + value));
    if (total != 0) return total;
    final duration = a.duration.compareTo(b.duration);
    if (duration != 0) return duration;
    return a.playerId.value.compareTo(b.playerId.value);
  });
  var legalWillingCandidates = 0;
  for (final candidate in candidates) {
    final decision = _evaluator.evaluate(
      career: career,
      teamId: need.teamId,
      freeAgentId: candidate.playerId,
      category: RosterCategory.standard,
      durationYears: candidate.duration,
      agreedFirstYearSalary: candidate.salary,
      clearanceOffer: true,
    );
    if (decision.isFinanciallyLegal && decision.isAcceptable) {
      legalWillingCandidates++;
    }
  }
  final missing = need.requiredPlayers;
  final path = candidates.take(missing).toList();
  final enoughPlayers = path.length == missing;
  final salaryTotal = path.fold<int>(0, (sum, offer) => sum + offer.salary);
  final projectedCash = career.finances.projectedEndOfSeasonCash(
    need.teamId,
    career.currentYear,
  );
  final cashAfter = projectedCash - salaryTotal;
  final overage = payroll + salaryTotal - FinancialRules.salaryCap - ordinary;
  final extraNeeded = overage > 0 ? overage : 0;
  final future = path.fold<int>(
    0,
    (sum, offer) => sum + offer.schedule.skip(1).fold<int>(0, (a, b) => a + b),
  );
  final unsigned = career.unsignedDraftRights
      .where((rights) => rights.owningTeamId == need.teamId)
      .length;
  final combinedNeeded = extraNeeded + ordinary;
  final fitsOrdinaryCap = payroll + salaryTotal <= FinancialRules.salaryCap;
  final fitsHardshipCeiling =
      enoughPlayers &&
      cashAfter >= 0 &&
      combinedNeeded <= FinancialRules.maximumCombinedHardshipOverage;
  final rosterFit =
      need.standardCount + missing <= RosterRules.maxOffseasonStandard;
  final teamOffers = career.hardshipSettlement.offers
      .where((offer) => offer.teamId == need.teamId)
      .toList();
  final teamResults = career.hardshipSettlement.outcomes
      .expand((outcome) => outcome.results)
      .where((result) => result.teamId == need.teamId)
      .toList();
  final classification = [
    if (!enoughPlayers) 'fewer acceptable free agents than vacancies',
    if (cashAfter < 0) 'cash insolvent',
    if (!rosterFit) 'roster capacity',
    if (!fitsHardshipCeiling) 'combined cap authority insufficient',
    if (teamResults.any(
      (result) => result.outcome == FreeAgentMarketOfferOutcome.outbid,
    ))
      'lost hardship competition',
    if (teamResults.any(
      (result) => result.outcome == FreeAgentMarketOfferOutcome.rejected,
    ))
      'player rejected formal hardship offer',
    if (teamOffers.isEmpty && fitsOrdinaryCap)
      'ordinary-cap signing path exists; no hardship authority needed',
    if (teamOffers.isEmpty && assessment.proposedOffers.isEmpty)
      'not hardship eligible: ${assessment.blockers.join(', ')}',
    if (teamOffers.isEmpty && assessment.eligible)
      'eligible assessment produced no sealed hardship offer',
    if (career.unsignedDraftRights.any(
      (rights) => rights.owningTeamId == need.teamId,
    ))
      'unsigned rookie rights are not rostered or signed',
  ].join('; ');
  final attemptsBlocked = career.freeAgentPool.entries
      .where(
        (entry) =>
            career.freeAgentOffers.remainingAttempts(
              teamId: need.teamId,
              playerId: entry.id,
              seasonYear: career.currentYear,
            ) <=
            0,
      )
      .length;
  final team = career.league.teams.firstWhere((item) => item.id == need.teamId);
  print(
    '${need.abbreviation} (${team.id == career.userFranchiseId ? 'human' : 'AI'}) | '
    '${need.standardCount} | $payroll | '
    '${FinancialRules.salaryCap - payroll} | $ordinary | $missing | '
    '${candidates.isEmpty ? 'none' : candidates.first.salary} | '
    '${enoughPlayers ? salaryTotal : 'infeasible'} | '
    '${enoughPlayers ? extraNeeded : 'infeasible'} | $cashAfter | $future | '
    '$unsigned | rosterFit=$rosterFit attemptsBlocked=$attemptsBlocked; '
    '${classification.isEmpty ? 'no measured blocker' : classification}',
  );
  print(
    '  remaining willing free agents=${candidates.length} '
    'financially legal at ordinary authority=$legalWillingCandidates',
  );
  print(
    '  assessment: eligible=${assessment.eligible} '
    'proposals=${assessment.proposedOffers.map((offer) => '${offer.playerId.value}:${offer.firstYearSalary}').join(',')} '
    'additional=${assessment.additionalAuthority} '
    'combined=${assessment.combinedOverage} '
    'blockers=${assessment.blockers.join('; ')}',
  );
  final rookieFeasibility = _rookieRightsFeasibility(career, team);
  if (rookieFeasibility != 'none') {
    print('  unsigned rookie path: $rookieFeasibility');
  }
  if (path.isNotEmpty) {
    for (final offer in path) {
      final view = career.freeAgentPool.byId(offer.playerId)!.toPublicView();
      final valuation = _marketValue.estimate(view);
      print(
        '  ${offer.playerId.value} OVR ${view.overallRating} '
        '${view.position.shortName} age ${view.age}; estimate '
        '${valuation.estimatedAnnualSalary} CU; ${offer.salary} CU x '
        '${offer.duration} (${offer.schedule.join('/')}); '
        'minimum-400 legal=${_evaluator.evaluate(career: career, teamId: need.teamId, freeAgentId: offer.playerId, category: RosterCategory.standard, durationYears: offer.duration, agreedFirstYearSalary: FinancialRules.minimumSalary).isFinanciallyLegal}; attemptsRemaining='
        '${career.freeAgentOffers.remainingAttempts(teamId: need.teamId, playerId: offer.playerId, seasonYear: career.currentYear)}',
      );
    }
  }
}

_CheapestContract? _cheapestAcceptable(
  GmCareer career,
  TeamId teamId,
  PlayerId playerId, {
  bool minimumOnly = false,
}) {
  if (career.freeAgentOffers.remainingAttempts(
        teamId: teamId,
        playerId: playerId,
        seasonYear: career.currentYear,
      ) <=
      0) {
    return null;
  }
  _CheapestContract? cheapest;
  for (
    var duration = 1;
    duration <= FinancialRules.maxDurationForCategory(RosterCategory.standard);
    duration++
  ) {
    var low = FinancialRules.minimumSalary;
    var high = minimumOnly ? low + 1 : FinancialRules.maximumSalary + 1;
    while (low < high) {
      final salary = low + (high - low) ~/ 2;
      final decision = _evaluator.evaluateWillingness(
        career: career,
        teamId: teamId,
        freeAgentId: playerId,
        category: RosterCategory.standard,
        durationYears: duration,
        salary: salary,
      );
      if (decision.accepts) {
        high = salary;
      } else {
        low = salary + 1;
      }
    }
    if (low >
        (minimumOnly
            ? FinancialRules.minimumSalary
            : FinancialRules.maximumSalary)) {
      continue;
    }
    final schedule = FinancialRules.standardSchedule(low, duration);
    if (schedule.any((salary) => salary > FinancialRules.maximumSalary)) {
      continue;
    }
    final offer = _CheapestContract(playerId, low, duration, schedule);
    if (cheapest == null ||
        offer.salary < cheapest.salary ||
        (offer.salary == cheapest.salary &&
            offer.schedule.fold<int>(0, (a, b) => a + b) <
                cheapest.schedule.fold<int>(0, (a, b) => a + b)) ||
        (offer.salary == cheapest.salary &&
            offer.duration < cheapest.duration)) {
      cheapest = offer;
    }
  }
  return cheapest;
}

String _rookieRightsFeasibility(GmCareer career, Team team) {
  final rights = career.unsignedDraftRights
      .where((right) => right.owningTeamId == team.id)
      .toList();
  if (rights.isEmpty) return 'none';
  var simulated = career;
  final results = <String>[];
  for (final right in rights) {
    final decision = simulated.aiRookieSigning.decisions.values
        .where((item) => item.prospectId == right.prospectId)
        .firstOrNull;
    if (decision != null) {
      results.add('${right.prospectId.value}:deferred-${decision.reason.name}');
      continue;
    }
    if (simulated.offseasonClearance.isExceptionApproved(team.id)) {
      results.add('${right.prospectId.value}:exception-update-required');
      continue;
    }
    try {
      simulated = const RookieSigningService().signDraftedRookie(
        career: simulated,
        teamId: team.id,
        prospectId: right.prospectId,
        category: RosterCategory.standard,
        durationYears: 1,
      );
      final roster = simulated.league.teams.firstWhere(
        (candidate) => candidate.id == team.id,
      );
      results.add(
        '${right.prospectId.value}:legal-standard-${roster.roster.standardCount}',
      );
    } on Object catch (error) {
      results.add('${right.prospectId.value}:blocked-${error.runtimeType}');
    }
  }
  final finalCount = simulated.league.teams
      .firstWhere((candidate) => candidate.id == team.id)
      .roster
      .standardCount;
  results.add('sequential-final-standard=$finalCount');
  return results.join(',');
}

final class _CheapestContract {
  const _CheapestContract(
    this.playerId,
    this.salary,
    this.duration,
    this.schedule,
  );

  final PlayerId playerId;
  final int salary;
  final int duration;
  final List<int> schedule;
}
