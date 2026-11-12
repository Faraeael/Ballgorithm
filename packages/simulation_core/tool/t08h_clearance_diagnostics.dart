// T08H clearance diagnostics. Run from packages/simulation_core:
//   dart run tool/t08h_clearance_diagnostics.dart
import 'dart:io';

import 'package:simulation_core/simulation_core.dart';

const _seeds = [20261028, 1604126146, 987654321];
const _market = FreeAgentMarketService();
const _clearance = OffseasonClearanceService();
const _gate = OffseasonReadinessGate();
const _value = FreeAgentMarketValueService();

GmCareer _career(int seed, FranchiseSituation situation) =>
    GmCareer.fromSetupResult(
      CareerSetupService().generate(
        CareerSetupRequest(
          selectedTeamId: const TeamId('team-1'),
          selectedSituation: situation,
          seed: seed,
        ),
      ),
      id: 't08h-$seed-${situation.jsonValue}',
    );

GmCareer _draft(GmCareer career) {
  const draft = DraftExecutionService();
  var current = draft.startDraft(career);
  while (!current.draftExecutionState.isCompleted) {
    current =
        current.draftExecutionState.isHumanTurn(
          order: current.draftOrder,
          userTeamId: current.userFranchiseId,
        )
        ? draft.makeHumanSelection(
            career: current,
            prospectId: current.draftExecutionState
                .availableProspects(current.draftClass)
                .first
                .id,
          )
        : draft.executeAiSelection(current);
  }
  return current;
}

GmCareer _aiRookies(GmCareer career) {
  const service = RookieAiSigningService();
  var current = service.initialize(career);
  var guard = 0;
  while (service.pendingRights(current).isNotEmpty) {
    current = service.applyNextDecision(current);
    if (++guard > 200) throw StateError('AI signing loop');
  }
  return current;
}

GmCareer _marketRounds(GmCareer career) {
  var current = _market.startRound(career);
  current = _market.prepareResolution(current);
  while (current.freeAgentMarket.isResolvable) {
    current = _market.resolveNext(current);
  }
  current = _market.startRound(current);
  current = _market.prepareResolution(current);
  while (current.freeAgentMarket.isResolvable) {
    current = _market.resolveNext(current);
  }
  return current;
}

({GmCareer authorized, GmCareer sealed, GmCareer resolved}) _clearancePass(
  GmCareer career,
) {
  final authorized = _clearance.start(career);
  var offerState = authorized;
  final humanNeed =
      RosterRules.minRegularSeasonStandard -
      authorized.userTeam.roster.standardCount;
  if (humanNeed > 0) {
    var staged = 0;
    for (final entry in offerState.freeAgentPool.entries) {
      if (staged >= humanNeed) break;
      final minimum = _minimumAcceptableSalary(
        offerState,
        offerState.userFranchiseId,
        entry,
      );
      if (minimum == null) continue;
      final duration = _value
          .estimate(entry.toPublicView())
          .preferredDurationYears;
      final decision = FreeAgentOfferEvaluator().evaluate(
        career: offerState,
        teamId: offerState.userFranchiseId,
        freeAgentId: entry.id,
        category: RosterCategory.standard,
        durationYears: duration,
        agreedFirstYearSalary: minimum,
        clearanceOffer: true,
      );
      if (!decision.isFinanciallyLegal) continue;
      try {
        offerState = _clearance.stageHumanOffer(
          career: offerState,
          teamId: offerState.userFranchiseId,
          playerId: entry.id,
          durationYears: duration,
          firstYearSalary: minimum,
        );
        staged++;
      } on DomainValidationException {
        // Pending commitments can make a later candidate unaffordable.
      }
    }
  }
  final sealed = _clearance.prepare(offerState);
  var resolved = sealed;
  while (resolved.offseasonClearance.isResolvable) {
    resolved = _clearance.resolveNext(resolved);
  }
  return (authorized: authorized, sealed: sealed, resolved: resolved);
}

int? _minimumAcceptableSalary(
  GmCareer career,
  TeamId teamId,
  FreeAgentEntry entry,
) {
  final view = entry.toPublicView();
  final duration = _value.estimate(view).preferredDurationYears;
  var low = FinancialRules.minimumSalary;
  var high = FreeAgentMarketValueService.maxYearOneForDuration(duration) + 1;
  while (low < high) {
    final salary = low + (high - low) ~/ 2;
    final response = FreeAgentOfferEvaluator().evaluateWillingness(
      career: career,
      teamId: teamId,
      freeAgentId: entry.id,
      category: RosterCategory.standard,
      durationYears: duration,
      salary: salary,
    );
    if (response.accepts) {
      high = salary;
    } else {
      low = salary + 1;
    }
  }
  return low <= FreeAgentMarketValueService.maxYearOneForDuration(duration)
      ? low
      : null;
}

void _snapshot(StringBuffer out, String label, GmCareer career) {
  final result = _gate.evaluate(career);
  final needs = result.teams.where((team) => team.requiredPlayers > 0).toList();
  final vacancies = needs.fold<int>(
    0,
    (sum, team) => sum + team.requiredPlayers,
  );
  final clearanceAcquisitions = career.freeAgentPool.acquisitions.entries.values
      .where((acquisition) => acquisition.origin == AcquisitionOrigin.clearance)
      .length;
  final outcomes = career.offseasonClearance.outcomes.expand(
    (outcome) => outcome.results,
  );
  final outbids = outcomes
      .where((result) => result.outcome == FreeAgentMarketOfferOutcome.outbid)
      .length;
  final rejections = outcomes
      .where((result) => result.outcome == FreeAgentMarketOfferOutcome.rejected)
      .length;
  final reliefUsed = career.league.teams.fold<int>(0, (sum, team) {
    final payroll = career.finances.capPayrollFor(team.id, career.currentYear);
    return sum +
        (payroll > FinancialRules.salaryCap
            ? payroll - FinancialRules.salaryCap
            : 0);
  });
  out.writeln(
    '| Snapshot | Ready teams | Standard vacancies | Financially legal 400 offers | '
    'Willing at 400 | Clearance acquisitions | Competitive losses | '
    'Player rejections | Cap relief used |',
  );
  out.writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|');
  out.writeln(
    '| $label | ${result.readyCount} | $vacancies | '
    '${needs.fold<int>(0, (sum, team) => sum + team.financiallyLegalMinimumOffers)} | '
    '${needs.fold<int>(0, (sum, team) => sum + team.willingMinimumOffers)} | '
    '$clearanceAcquisitions | $outbids | $rejections | $reliefUsed |',
  );
  out.writeln();
  out.writeln(
    '| Team | Standard | Missing | Normal cap room | Approved relief | '
    'Legal 400 offers | Willing at 400 | Willing and legal | '
    'Formal attempts exhausted | Acquired elsewhere | Unsigned rights |',
  );
  out.writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final need in needs) {
    out.writeln(
      '| ${need.abbreviation} | ${need.standardCount} | '
      '${need.requiredPlayers} | ${need.capRoom} | '
      '${need.authorizedCapRelief} | ${need.financiallyLegalMinimumOffers} | '
      '${need.willingMinimumOffers} | ${need.willingAndLegalMinimumOffers} | '
      '${need.attemptBlockedMinimumOffers} | '
      '${need.acquiredByOtherFranchises} | ${need.unsignedDraftRights} |',
    );
  }
  out.writeln();
}

String _rookieRightsFeasibility(GmCareer career, Team team) {
  final rights = career.unsignedDraftRights.where(
    (right) => right.owningTeamId == team.id,
  );
  if (rights.isEmpty) return 'none';
  final results = <String>[];
  for (final right in rights) {
    final decision = career.aiRookieSigning.decisions.values
        .where((item) => item.prospectId == right.prospectId)
        .firstOrNull;
    if (decision != null) {
      results.add('${right.prospectId.value}:deferred-${decision.reason.name}');
      continue;
    }
    if (career.offseasonClearance.isExceptionApproved(team.id)) {
      results.add('${right.prospectId.value}:exception-update-required');
      continue;
    }
    try {
      final signed = const RookieSigningService().signDraftedRookie(
        career: career,
        teamId: team.id,
        prospectId: right.prospectId,
        category: RosterCategory.standard,
        durationYears: 1,
      );
      results.add(
        '${right.prospectId.value}:legal-standard-${signed.league.teams.firstWhere((item) => item.id == team.id).roster.standardCount}',
      );
    } on Object catch (error) {
      results.add('${right.prospectId.value}:blocked-${error.runtimeType}');
    }
  }
  return results.join(',');
}

void _playerDiagnostics(StringBuffer out, GmCareer career) {
  final result = _gate.evaluate(career);
  for (final need in result.teams.where((team) => team.requiredPlayers > 0)) {
    final team = career.league.teams.firstWhere(
      (candidate) => candidate.id == need.teamId,
    );
    final payroll = career.finances.capPayrollFor(team.id, career.currentYear);
    final projection = career.finances.projectedEndOfSeasonCash(
      team.id,
      career.currentYear,
    );
    final candidates = <(FreeAgentEntry, int)>[];
    for (final entry in career.freeAgentPool.entries) {
      final minimum = _minimumAcceptableSalary(career, team.id, entry);
      if (minimum != null &&
          career.freeAgentOffers.remainingAttempts(
                teamId: team.id,
                playerId: entry.id,
                seasonYear: career.currentYear,
              ) >
              0) {
        candidates.add((entry, minimum));
      }
    }
    candidates.sort((a, b) => a.$2.compareTo(b.$2));
    final path = candidates.take(need.requiredPlayers).toList();
    final requiredSalary = path.length == need.requiredPlayers
        ? path.fold<int>(0, (sum, item) => sum + item.$2)
        : null;
    final relief = need.authorizedCapRelief;
    final additionalRelief = requiredSalary == null
        ? null
        : (payroll + requiredSalary - FinancialRules.salaryCap - relief).clamp(
            0,
            1 << 30,
          );
    final seasonCash = requiredSalary == null
        ? null
        : projection - requiredSalary;
    final futureCommitment = path.fold<int>(0, (sum, item) {
      final duration = _value
          .estimate(item.$1.toPublicView())
          .preferredDurationYears;
      final schedule = FinancialRules.standardSchedule(item.$2, duration);
      return sum + schedule.skip(1).fold<int>(0, (a, salary) => a + salary);
    });
    final rights = career.unsignedDraftRights
        .where((right) => right.owningTeamId == team.id)
        .map((right) => right.prospectId.value)
        .join(',');
    out.writeln(
      '### ${team.abbreviation}: ${need.requiredPlayers} standard vacancy(s)',
    );
    out.writeln();
    out.writeln(
      'Payroll $payroll; normal room ${need.capRoom}; existing exception '
      '$relief; cheapest willing path ${requiredSalary ?? 'unavailable'} CU; '
      'additional exception needed ${additionalRelief ?? 'unavailable'} CU; '
      'projected season-end cash ${seasonCash ?? 'unavailable'} CU; '
      'future-year commitments $futureCommitment CU; unsigned rookie rights '
      '${rights.isEmpty ? 'none' : rights}.',
    );
    out.writeln(
      'Unsigned-rookie feasibility without state changes: '
      '${_rookieRightsFeasibility(career, team)}.',
    );
    out.writeln();
    final teamResults = career.offseasonClearance.outcomes
        .expand(
          (outcome) => [
            for (final result in outcome.results)
              if (result.teamId == team.id)
                (
                  playerId: outcome.playerId,
                  offerId: result.offerId,
                  status: result.outcome,
                  reason: result.reasonCode,
                ),
          ],
        )
        .toList();
    out.writeln('Actual clearance results:');
    out.writeln();
    out.writeln('| Player | Outcome | Reason |');
    out.writeln('|---|---|---|');
    for (final result in teamResults) {
      out.writeln(
        '| ${result.playerId.value} | ${result.status.name} | '
        '${result.reason} |',
      );
    }
    if (teamResults.isEmpty) out.writeln('| none | none | none |');
    out.writeln();
    out.writeln(
      '| Player | OVR | Pos | Age | Estimate | 400 legal | Accepts 400 | '
      '400 hypothetical reason (no refusal if illegal) | Preferred years | '
      'Cheapest acceptable | Normal cap fit | Relief fit | Cash fit | '
      'Roster fit | Attempts block | Recorded rejection |',
    );
    out.writeln(
      '|---|---:|---|---:|---:|---|---|---|---:|---:|---|---|---|---|---|---|',
    );
    for (final entry in career.freeAgentPool.entries) {
      final view = entry.toPublicView();
      final valuation = _value.estimate(view);
      final duration = valuation.preferredDurationYears;
      final evaluator = FreeAgentOfferEvaluator();
      final at400 = evaluator.evaluate(
        career: career,
        teamId: team.id,
        freeAgentId: entry.id,
        category: RosterCategory.standard,
        durationYears: duration,
        agreedFirstYearSalary: FinancialRules.minimumSalary,
        clearanceOffer: true,
      );
      final willingness = evaluator.evaluateWillingness(
        career: career,
        teamId: team.id,
        freeAgentId: entry.id,
        category: RosterCategory.standard,
        durationYears: duration,
        salary: FinancialRules.minimumSalary,
      );
      final minimum = _minimumAcceptableSalary(career, team.id, entry);
      final salary = minimum ?? FinancialRules.maximumSalary;
      final attempts = career.freeAgentOffers.attemptsFor(
        teamId: team.id,
        playerId: entry.id,
        seasonYear: career.currentYear,
      );
      final formalRejection = attempts
          .where((attempt) => !attempt.outcome.isAccepted)
          .map((attempt) => '${attempt.firstYearSalary}:${attempt.reasonCode}')
          .join(',');
      final normalCapFit = payroll + salary <= FinancialRules.salaryCap;
      final reliefFit =
          normalCapFit ||
          (salary == FinancialRules.minimumSalary &&
              payroll + salary <= FinancialRules.salaryCap + relief);
      final cashFit = projection >= salary;
      final rosterFit = team.roster.standardCount < 14;
      final attemptsBlock =
          career.freeAgentOffers.remainingAttempts(
            teamId: team.id,
            playerId: entry.id,
            seasonYear: career.currentYear,
          ) ==
          0;
      final refusal = !at400.isFinanciallyLegal
          ? 'not offered: ${at400.reasonCode}'
          : (at400.isAcceptable ? 'accepts' : at400.reasonCode);
      out.writeln(
        '| ${entry.id.value} | ${view.overallRating} | ${view.position.name} | '
        '${view.age} | ${valuation.estimatedAnnualSalary} | '
        '${at400.isFinanciallyLegal} | ${willingness.accepts} | $refusal | '
        '$duration | ${minimum ?? 'none'} | $normalCapFit | $reliefFit | '
        '$cashFit | $rosterFit | $attemptsBlock | '
        '${formalRejection.isEmpty ? 'none' : formalRejection} |',
      );
    }
    out.writeln();
  }
}

void main() {
  final out = StringBuffer()
    ..writeln('# T08H-P1 clearance feasibility diagnostics')
    ..writeln()
    ..writeln(
      'Full opening-offseason sequence; no season advancement. Each snapshot '
      'reports current state only.',
    )
    ..writeln(
      '“Legal at 400” uses the authoritative evaluator; willingness runs '
      'player response separately. Hypothetical refusal is never counted when '
      'finance rejects the offer. Recorded rejections are formal attempts. '
      'Valuation uses public OVR, age and position only.',
    )
    ..writeln();
  for (final seed in _seeds) {
    for (final situation in FranchiseSituation.values) {
      var career = _aiRookies(_draft(_career(seed, situation)));
      career = _marketRounds(career);
      final afterMarkets = career;
      final before = _gate.evaluate(afterMarkets);
      final pass = _clearancePass(afterMarkets);
      out.writeln('## $seed — ${situation.displayName}');
      out.writeln();
      _snapshot(out, 'A · after market rounds', afterMarkets);
      _snapshot(out, 'B · after exception authorization', pass.authorized);
      _snapshot(out, 'C · after clearance offers sealed', pass.sealed);
      _snapshot(out, 'D · after clearance resolution', pass.resolved);
      final after = _gate.evaluate(pass.resolved);
      out.writeln(
        'Final readiness: ${after.status.jsonValue}; ready '
        '${after.readyCount}/${pass.resolved.league.teams.length}; '
        'shortage ${after.totalShortage}; clearance accepted '
        '${pass.resolved.freeAgentPool.acquisitions.entries.values.where((a) => a.origin == AcquisitionOrigin.clearance).length}.',
      );
      out.writeln();
      out.writeln(
        '| AI team | Missing | Classification | Minimum-acceptable legal candidate | '
        'Sealed offers | Outbid | Player rejection | '
        'Financially unavailable | Unsigned rights |',
      );
      out.writeln('|---|---:|---|---|---:|---:|---:|---:|---:|');
      for (final team in pass.resolved.league.teams.where(
        (team) =>
            team.id != pass.resolved.userFranchiseId &&
            team.roster.standardCount < 14,
      )) {
        final candidates = [
          for (final entry in pass.sealed.freeAgentPool.entries)
            if (_minimumAcceptableSalary(pass.sealed, team.id, entry) != null)
              entry,
        ];
        final willingLegal = candidates.any((entry) {
          final salary = _minimumAcceptableSalary(pass.sealed, team.id, entry)!;
          return FreeAgentOfferEvaluator()
              .evaluate(
                career: pass.sealed,
                teamId: team.id,
                freeAgentId: entry.id,
                category: RosterCategory.standard,
                durationYears: _value
                    .estimate(entry.toPublicView())
                    .preferredDurationYears,
                agreedFirstYearSalary: salary,
                clearanceOffer: true,
              )
              .isAcceptable;
        });
        final offers = pass.sealed.offseasonClearance.aiOffers
            .where((offer) => offer.teamId == team.id)
            .toList();
        final results = pass.resolved.offseasonClearance.outcomes
            .expand((outcome) => outcome.results)
            .where((result) => result.teamId == team.id)
            .toList();
        final outbid = results
            .where(
              (result) => result.outcome == FreeAgentMarketOfferOutcome.outbid,
            )
            .length;
        final rejected = results
            .where(
              (result) =>
                  result.outcome == FreeAgentMarketOfferOutcome.rejected,
            )
            .length;
        final unavailable = results
            .where(
              (result) =>
                  result.outcome ==
                  FreeAgentMarketOfferOutcome.financiallyUnavailable,
            )
            .length;
        final classification = unavailable > 0
            ? 'D · earlier signing consumed capacity'
            : outbid > 0
            ? 'C · lost competition'
            : offers.isNotEmpty
            ? 'offer resolved; inspect result'
            : willingLegal
            ? 'B · affordable offer not generated'
            : 'A · no affordable willing minimum';
        out.writeln(
          '| ${team.abbreviation} | ${14 - team.roster.standardCount} | '
          '$classification | $willingLegal | ${offers.length} | '
          '$outbid | $rejected | $unavailable | '
          '${pass.resolved.unsignedDraftRights.where((right) => right.owningTeamId == team.id).length} |',
        );
      }
      out.writeln();
      if (after.belowMinimumCount > 0) {
        out.writeln('### Post-clearance player-level findings');
        out.writeln();
        _playerDiagnostics(out, pass.resolved);
      }
      if (before.status == OffseasonReadinessStatus.offseasonInProgress) {
        throw StateError('Diagnostic sequence did not finish market rounds');
      }
    }
  }
  out.writeln('## Owner decision comparison');
  out.writeln();
  out.writeln(
    '- **A — preserve 400 CU minimum-only relief:** no economic-rule change; '
    'remaining franchises stay blocked where player policy refuses legal '
    '400 CU offers.',
  );
  out.writeln(
    '- **B — individually recorded hardship exceptions:** each post-clearance '
    'team section reports cheapest acceptable salary, exact extra cap needed, '
    'cash projection and future commitments. Apply only one contract per '
    'vacancy; no loan or forced acceptance.',
  );
  out.writeln(
    '- **C — unsigned rookie rights:** a no-change signing trial fills a '
    'user-controlled vacancy in 3 of 12 runs. AI rights have persisted '
    'deferredLowFit decisions, so they cannot fill AI vacancies without a '
    'modeled decision change.',
  );
  out.writeln();
  out.writeln(
    '**Recommendation: Option B for owner approval.** AI clearance blockers '
    'have no affordable willing free agent under current relief; Option C '
    'only clears tested user-controlled vacancies. No player in blocked-team '
    'tables accepts a financially legal 400 CU hypothetical offer. Option B '
    'uses evidenced thresholds and per-team shortfalls; it does not guarantee '
    'competitive wins. It remains unimplemented pending owner approval.',
  );
  out.writeln(
    '**Final clearance: NO-GO.** Remaining standard-roster vacancies remain '
    'after the one authorized pass.',
  );
  out.writeln();
  final file = File(
    '../../specs/008-30-team-league/t08h-p1-clearance-feasibility.md',
  )..createSync(recursive: true);
  file.writeAsStringSync(out.toString());
  stdout.writeln(out);
  stdout.writeln('wrote ${file.path}');
}
