import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/career/offseason_overview_screen.dart';
import 'package:basketball_manager/features/season/season_storage.dart';
import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/offseason_clearance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _seeds = [20261028, 1604126146, 987654321, 314159265, 271828182, 8675309];
const _situations = FranchiseSituation.values;
const _evaluator = FreeAgentOfferEvaluator();
const _hardship = HardshipSettlementService();
const _gate = OffseasonReadinessGate();

void main() {
  testWidgets('active human hardship diagnostics across 24 cohorts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    for (final seed in _seeds) {
      for (final situation in _situations) {
        final result = await _runActiveCohort(tester, seed, situation);
        expect(result.career.league.teams, hasLength(30));
        debugPrint(
          'ACTIVE seed=$seed situation=${situation.jsonValue} '
          'ready=${result.readiness.readyCount}/30 '
          'vacancies=${result.readiness.totalShortage} '
          'human=${result.readiness.humanShortage} '
          'AI=${result.readiness.totalShortage - result.readiness.humanShortage} '
          'hardshipAcquisitions=${result.hardshipAcquisitions} '
          'financialBlocks=${result.financialBlocks} '
          'competitionBlocks=${result.competitionBlocks} '
          'playerRejectionBlocks=${result.playerRejectionBlocks} '
          'ordinaryUsed=${result.ordinaryUsed} '
          'hardshipUsed=${result.hardshipUsed} '
          'totalExceptionUsed=${result.ordinaryUsed + result.hardshipUsed} '
          'maximumRequired=${result.maximumRequired} '
          'humanOffers=${result.humanOffers} '
          'all30=${result.readiness.readyCount == 30}',
        );
        for (final need in result.readiness.teams.where(
          (team) => team.requiredPlayers > 0,
        )) {
          final assessment = result.assessments[need.teamId.value];
          final candidates = _humanCandidates(
            result.career,
            teamId: need.teamId,
            durationOnly: null,
            clearanceOffer: false,
            requireFinancialLegality: false,
          ).take(need.requiredPlayers).toList();
          final salaryTotal = candidates.fold<int>(
            0,
            (sum, candidate) => sum + candidate.salary,
          );
          final overage =
              result.career.finances.capPayrollFor(
                need.teamId,
                result.career.currentYear,
              ) +
              salaryTotal -
              FinancialRules.salaryCap;
          final combinedRequired = overage > 0 ? overage : 0;
          final extraRequired = combinedRequired > need.authorizedCapRelief
              ? combinedRequired - need.authorizedCapRelief
              : 0;
          debugPrint(
            '  BLOCKED ${need.abbreviation}/${need.teamId.value} '
            'standard=${need.standardCount} missing=${need.requiredPlayers} '
            'payrollRoom=${need.capRoom} ordinary=${need.authorizedCapRelief} '
            'requiredOverage=$combinedRequired additionalRequired=$extraRequired '
            'cashAfter=${need.projectedCash - salaryTotal} '
            'acceptable=${candidates.map((offer) => '${offer.playerId.value}:${offer.salary}x${offer.duration}').join(',')} '
            'recordedOutbid=${result.competitionTeamIds.contains(need.teamId.value)} '
            'readiness=${need.blockers.join('; ')} '
            'hardship=${assessment?.blockers.join('; ') ?? 'not assessed'}',
          );
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets(
    'M009-T01 enters only active-human ready cohorts and recovers promotion failure',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      const readyCases = [
        (20261028, FranchiseSituation.playIn),
        (20261028, FranchiseSituation.playoff),
        (20261028, FranchiseSituation.contender),
        (987654321, FranchiseSituation.tanking),
        (987654321, FranchiseSituation.playIn),
        (987654321, FranchiseSituation.playoff),
      ];
      const blockedCases = [
        (271828182, FranchiseSituation.tanking),
        (8675309, FranchiseSituation.contender),
      ];
      GmCareer? firstCleared;
      String? firstClearedSave;

      for (final (seed, situation) in readyCases) {
        final active = await _runActiveCohort(tester, seed, situation);
        expect(
          active.readiness.status,
          OffseasonReadinessStatus.readyForConfirmation,
          reason: '$seed/${situation.jsonValue}',
        );
        final storage = InMemoryGmCareerStorage({
          'default': GmCareerCodec.encode(active.career),
        });
        final controller = GmCareerController(storage: storage);
        await controller.loadCareer();
        await controller.markOffseasonCleared();
        final cleared = controller.career!;
        expect(
          _gate.evaluate(cleared).status,
          OffseasonReadinessStatus.cleared,
        );
        if (firstCleared == null) {
          firstCleared = cleared;
          firstClearedSave = await storage.read();
          final seasonStorage = InMemorySeasonStorage();
          await tester.pumpWidget(
            BasketballManagerApp(
              league: cleared.league,
              storage: seasonStorage,
              careerStorage: storage,
              careerController: controller,
              seasonMode: true,
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('btn-start-regular-season')),
            220,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('offseason-overview-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('btn-start-regular-season')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('confirm-start-regular-season')),
            findsOneWidget,
          );
          expect(controller.career!.phase, CareerPhase.openingOffseason);
          await tester.tap(
            find.byKey(const ValueKey('cancel-start-regular-season')),
          );
          await tester.pumpAndSettle();
          expect(await storage.read(), firstClearedSave);
          expect(controller.career!.phase, CareerPhase.openingOffseason);
          await expectLater(
            controller.startRegularSeason(confirmed: false),
            throwsStateError,
          );
          expect(controller.career!.phase, CareerPhase.openingOffseason);
          expect(await storage.read(), firstClearedSave);

          await tester.tap(
            find.byKey(const ValueKey('btn-start-regular-season')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('confirm-start-regular-season')),
          );
          await tester.pumpAndSettle();
          final entered = controller.career!;
          expect(entered.phase, CareerPhase.regularSeason);
          expect(entered.regularSeasonState!.gameResults, isEmpty);
          expect(entered.currentYear, cleared.currentYear);
          expect(
            GmCareerCodec.encode(entered),
            GmCareerCodec.encode(
              const RegularSeasonEntryService().start(cleared),
            ),
          );
          expect(find.text('Regular Season'), findsOneWidget);
          expect(find.text('Record: 0 wins, 0 losses'), findsOneWidget);
          expect(find.textContaining('Schedule generation'), findsOneWidget);
          tester.view.physicalSize = const Size(360, 640);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          tester.view.physicalSize = const Size(393, 852);
          await tester.pumpAndSettle();
          await expectLater(
            controller.startRegularSeason(confirmed: true),
            throwsStateError,
          );
          expect(controller.career!.phase, CareerPhase.regularSeason);
          expect(await seasonStorage.read(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();

          final failureSeasonStorage = InMemorySeasonStorage();
          final failureStorage = _CommitThenFailCareerStorage(
            InMemoryGmCareerStorage({'default': firstClearedSave}),
          )..failNextWrite = true;
          final failureController = GmCareerController(storage: failureStorage);
          await failureController.loadCareer();
          await tester.pumpWidget(
            BasketballManagerApp(
              league: cleared.league,
              storage: failureSeasonStorage,
              careerStorage: failureStorage,
              careerController: failureController,
              seasonMode: true,
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('btn-start-regular-season')),
            220,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('offseason-overview-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('btn-start-regular-season')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('confirm-start-regular-season')),
          );
          await tester.pumpAndSettle();
          expect(failureController.career!.phase, CareerPhase.openingOffseason);
          expect(failureController.draftRecoveryRequired, isTrue);
          final promotedSave = await failureStorage.read();
          expect(
            GmCareerCodec.decode(promotedSave!).phase,
            CareerPhase.regularSeason,
          );
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('btn-season-entry-reload')),
            220,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('offseason-overview-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('btn-season-entry-reload')),
          );
          await tester.pumpAndSettle();
          expect(failureController.career!.phase, CareerPhase.regularSeason);
          expect(failureController.draftRecoveryRequired, isFalse);
          expect(
            failureController.career!.regularSeasonState!.seasonId,
            entered.regularSeasonState!.seasonId,
          );
          expect(
            failureController.career!.freeAgentPool.acquisitions.entries.length,
            cleared.freeAgentPool.acquisitions.entries.length,
          );
          expect(
            failureController.career!.finances.contracts.keys.toSet(),
            cleared.finances.contracts.keys.toSet(),
          );
          expect(await failureSeasonStorage.read(), isNull);
          expect(GmCareerCodec.encode(failureController.career!), promotedSave);
          await expectLater(
            failureController.startRegularSeason(confirmed: true),
            throwsStateError,
          );
          expect(await failureStorage.read(), promotedSave);
          await tester.pumpWidget(const SizedBox.shrink());
          failureController.dispose();
        } else {
          final entered = const RegularSeasonEntryService().start(cleared);
          expect(entered.phase, CareerPhase.regularSeason);
          expect(entered.regularSeasonState!.gameResults, isEmpty);
          expect(entered.regularSeasonState!.scheduleSeed, seed);
          expect(
            GmCareerCodec.encode(entered),
            GmCareerCodec.encode(
              const RegularSeasonEntryService().start(cleared),
            ),
          );
          expect(
            GmCareerCodec.decode(GmCareerCodec.encode(entered)).phase,
            CareerPhase.regularSeason,
          );
          controller.dispose();
        }
        debugPrint(
          'M009-T01 READY seed=$seed situation=${situation.jsonValue} '
          'phase=regularSeason scheduleSeed=$seed games=0',
        );
      }

      for (final (seed, situation) in blockedCases) {
        final active = await _runActiveCohort(tester, seed, situation);
        expect(active.readiness.readyCount, lessThan(30));
        expect(
          () => const RegularSeasonEntryService().start(active.career),
          throwsA(isA<RegularSeasonEntryBlocked>()),
        );
        final blockedStorage = InMemoryGmCareerStorage({
          'default': GmCareerCodec.encode(active.career),
        });
        final blockedController = GmCareerController(storage: blockedStorage);
        await blockedController.loadCareer();
        await tester.pumpWidget(
          MaterialApp(
            home: GmOffseasonOverviewScreen(controller: blockedController),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('btn-start-regular-season')),
          220,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('offseason-overview-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('Season Start Blocked'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('btn-start-regular-season')),
              )
              .onPressed,
          isNull,
        );
        expect(blockedController.career!.phase, CareerPhase.openingOffseason);
        await tester.pumpWidget(const SizedBox.shrink());
        blockedController.dispose();
        debugPrint(
          'M009-T01 BLOCKED seed=$seed situation=${situation.jsonValue} '
          'ready=${active.readiness.readyCount}/30 '
          'vacancies=${active.readiness.totalShortage}',
        );
      }
      expect(firstCleared, isNotNull);
      expect(firstClearedSave, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}

Future<_ActiveResult> _runActiveCohort(
  WidgetTester tester,
  int seed,
  FranchiseSituation situation,
) async {
  var career = GmCareer.fromSetupResult(
    const CareerSetupService().generate(
      CareerSetupRequest(
        selectedTeamId: const TeamId('team-1'),
        selectedSituation: situation,
        seed: seed,
      ),
    ),
    id: 't08h-p2-active-$seed-${situation.jsonValue}',
  );
  career = _completeDraft(career);
  career = _completeAiRookieDecisions(career);
  final controller = GmCareerController(
    storage: InMemoryGmCareerStorage({'default': GmCareerCodec.encode(career)}),
  );
  await controller.loadCareer();
  try {
    for (var round = 0; round < 2; round++) {
      await controller.startFreeAgencyRound();
      await _submitHumanMarketOffers(controller);
      await controller.prepareFreeAgencyResolution();
      await controller.resolveFreeAgencyRound();
    }
    await controller.startOffseasonClearance();
    await _submitHumanClearanceOffers(controller);
    await controller.prepareOffseasonClearance();
    await controller.resolveOffseasonClearance();

    final beforeHardship = controller.career!;
    final assessments = <String, HardshipTeamAssessment>{
      for (final team in beforeHardship.league.teams)
        team.id.value: _hardship.assessTeam(beforeHardship, team.id),
    };
    final humanAssessment = assessments[beforeHardship.userFranchiseId.value]!;
    if (beforeHardship.offseasonClearance.status ==
            OffseasonClearanceStatus.complete &&
        beforeHardship.hardshipSettlement.status ==
            HardshipSettlementStatus.notStarted &&
        _gate.evaluate(beforeHardship).belowMinimumCount > 0) {
      await tester.pumpWidget(
        MaterialApp(home: GmOffseasonClearanceScreen(controller: controller)),
      );
      if (humanAssessment.eligible) {
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('confirm-human-hardship')),
          220,
        );
        await tester.tap(find.byKey(const ValueKey('confirm-human-hardship')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('approve-human-hardship')));
        await tester.pumpAndSettle();
      } else {
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('prepare-ai-hardship')),
          220,
        );
        await tester.tap(find.byKey(const ValueKey('prepare-ai-hardship')));
        await tester.pumpAndSettle();
      }
      if (controller.career!.hardshipSettlement.isResolvable) {
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('resolve-hardship')),
          220,
        );
        await tester.tap(find.byKey(const ValueKey('resolve-hardship')));
        await tester.pumpAndSettle();
      }
    }

    final finalCareer = controller.career!;
    expect(controller.errorMessage, isNull);
    expect(finalCareer.freeAgentMarket.completedRounds, 2);
    expect(
      finalCareer.offseasonClearance.status,
      OffseasonClearanceStatus.complete,
    );
    expect(finalCareer.currentYear, 1);
    expect(
      finalCareer.hardshipSettlement.offers.any(
        (offer) => offer.teamId == finalCareer.userFranchiseId,
      ),
      humanAssessment.eligible,
    );
    final readiness = _gate.evaluate(finalCareer);
    final blockedIds = {
      for (final team in readiness.teams)
        if (team.requiredPlayers > 0) team.teamId.value,
    };
    final outbidTeams = <String>{
      for (final round in finalCareer.freeAgentMarket.roundHistory)
        for (final outcome in round.outcomes)
          for (final result in outcome.results)
            if (result.outcome == FreeAgentMarketOfferOutcome.outbid)
              result.teamId.value,
      for (final outcome in finalCareer.offseasonClearance.outcomes)
        for (final result in outcome.results)
          if (result.outcome == FreeAgentMarketOfferOutcome.outbid)
            result.teamId.value,
      for (final outcome in finalCareer.hardshipSettlement.outcomes)
        for (final result in outcome.results)
          if (result.outcome == FreeAgentMarketOfferOutcome.outbid)
            result.teamId.value,
    };
    final rejectedTeams = <String>{
      for (final round in finalCareer.freeAgentMarket.roundHistory)
        for (final outcome in round.outcomes)
          for (final result in outcome.results)
            if (result.outcome == FreeAgentMarketOfferOutcome.rejected)
              result.teamId.value,
      for (final outcome in finalCareer.offseasonClearance.outcomes)
        for (final result in outcome.results)
          if (result.outcome == FreeAgentMarketOfferOutcome.rejected)
            result.teamId.value,
      for (final outcome in finalCareer.hardshipSettlement.outcomes)
        for (final result in outcome.results)
          if (result.outcome == FreeAgentMarketOfferOutcome.rejected)
            result.teamId.value,
    };
    var maximumRequired = finalCareer.hardshipSettlement.authorizations
        .fold<int>(0, (maximum, authorization) {
          final required =
              authorization.existingOrdinaryRelief +
              authorization.additionalAmount;
          return required > maximum ? required : maximum;
        });
    final financiallyBlocked = <String>{};
    final competitionBlocked = <String>{};
    final playerRejected = <String>{};
    for (final teamId in blockedIds) {
      final assessment = assessments[teamId];
      if (assessment != null &&
          assessment.blockers.any(
            (reason) =>
                reason.contains('cash insolvent') ||
                reason.contains('No willing contract fits cash') ||
                reason.contains('fit the approved ceiling'),
          )) {
        financiallyBlocked.add(teamId);
      }
      final need = readiness.teams.firstWhere(
        (team) => team.teamId.value == teamId,
      );
      final candidates = _humanCandidates(
        finalCareer,
        teamId: need.teamId,
        durationOnly: null,
        clearanceOffer: false,
        requireFinancialLegality: false,
      ).take(need.requiredPlayers);
      final salaryTotal = candidates.fold<int>(
        0,
        (sum, candidate) => sum + candidate.salary,
      );
      final overage =
          finalCareer.finances.capPayrollFor(
            need.teamId,
            finalCareer.currentYear,
          ) +
          salaryTotal -
          FinancialRules.salaryCap;
      final required = overage > 0 ? overage : 0;
      if (required > FinancialRules.maximumCombinedHardshipOverage ||
          need.projectedCash - salaryTotal < 0) {
        financiallyBlocked.add(teamId);
      }
      if (required > maximumRequired) maximumRequired = required;
      if (outbidTeams.contains(teamId)) competitionBlocked.add(teamId);
      if (rejectedTeams.contains(teamId)) playerRejected.add(teamId);
    }
    return _ActiveResult(
      career: finalCareer,
      readiness: readiness,
      assessments: assessments,
      hardshipAcquisitions: finalCareer
          .freeAgentPool
          .acquisitions
          .entries
          .values
          .where((item) => item.origin == AcquisitionOrigin.hardship)
          .length,
      financialBlocks: financiallyBlocked.length,
      competitionBlocks: competitionBlocked.length,
      competitionTeamIds: outbidTeams.intersection(blockedIds),
      playerRejectionBlocks: playerRejected.length,
      maximumRequired: maximumRequired,
      ordinaryUsed: finalCareer.league.teams.fold<int>(0, (sum, team) {
        final capException = finalCareer.finances
            .financesFor(team.id)
            .capException;
        final overCap =
            finalCareer.finances.capPayrollFor(
              team.id,
              finalCareer.currentYear,
            ) -
            FinancialRules.salaryCap;
        final hardshipUsed =
            finalCareer.hardshipSettlement
                .authorizationFor(team.id)
                ?.usedAmount ??
            0;
        return sum + (overCap - hardshipUsed).clamp(0, capException).toInt();
      }),
      hardshipUsed: finalCareer.hardshipSettlement.authorizations.fold<int>(
        0,
        (sum, record) => sum + record.usedAmount,
      ),
      humanOffers:
          finalCareer.freeAgentMarket.roundHistory
              .expand((round) => round.humanOffers)
              .where((offer) => offer.teamId == finalCareer.userFranchiseId)
              .length +
          finalCareer.offseasonClearance.humanOffers.length +
          finalCareer.hardshipSettlement.offers
              .where((offer) => offer.teamId == finalCareer.userFranchiseId)
              .length,
    );
  } finally {
    controller.dispose();
  }
}

Future<void> _submitHumanMarketOffers(GmCareerController controller) async {
  var career = controller.career!;
  final missing =
      RosterRules.minRegularSeasonStandard -
      career.userTeam.roster.standardCount;
  if (missing <= 0) return;
  final candidates = _humanCandidates(
    career,
    teamId: career.userFranchiseId,
    durationOnly: null,
    clearanceOffer: false,
  );
  var submitted = 0;
  for (final candidate in candidates) {
    if (submitted >= missing) break;
    career = controller.career!;
    if (_evaluator
            .evaluate(
              career: career,
              teamId: career.userFranchiseId,
              freeAgentId: candidate.playerId,
              category: RosterCategory.standard,
              durationYears: candidate.duration,
              agreedFirstYearSalary: candidate.salary,
            )
            .status !=
        FreeAgentOfferStatus.acceptable) {
      continue;
    }
    try {
      await controller.stageFreeAgentOffer(
        freeAgentId: candidate.playerId,
        category: RosterCategory.standard,
        durationYears: candidate.duration,
        firstYearSalary: candidate.salary,
      );
      submitted++;
    } on DomainValidationException {
      // Skip a candidate when a prior reservation makes its offer illegal.
    }
  }
}

Future<void> _submitHumanClearanceOffers(GmCareerController controller) async {
  var career = controller.career!;
  final missing =
      RosterRules.minRegularSeasonStandard -
      career.userTeam.roster.standardCount;
  if (missing <= 0) return;
  final candidates = _humanCandidates(
    career,
    teamId: career.userFranchiseId,
    durationOnly: 1,
    clearanceOffer: true,
  );
  var submitted = 0;
  for (final candidate in candidates) {
    if (submitted >= missing) break;
    career = controller.career!;
    if (_evaluator
            .evaluate(
              career: career,
              teamId: career.userFranchiseId,
              freeAgentId: candidate.playerId,
              category: RosterCategory.standard,
              durationYears: 1,
              agreedFirstYearSalary: candidate.salary,
              clearanceOffer: true,
            )
            .status !=
        FreeAgentOfferStatus.acceptable) {
      continue;
    }
    try {
      await controller.stageClearanceOffer(
        freeAgentId: candidate.playerId,
        durationYears: 1,
        firstYearSalary: candidate.salary,
      );
      submitted++;
    } on DomainValidationException {
      // Skip a candidate when a prior reservation makes its offer illegal.
    }
  }
}

List<_HumanCandidate> _humanCandidates(
  GmCareer career, {
  required TeamId teamId,
  required int? durationOnly,
  required bool clearanceOffer,
  bool requireFinancialLegality = true,
}) {
  final candidates = <_HumanCandidate>[];
  for (final entry in career.freeAgentPool.entries) {
    if (career.freeAgentOffers.remainingAttempts(
          teamId: teamId,
          playerId: entry.id,
          seasonYear: career.currentYear,
        ) <=
        0) {
      continue;
    }
    final durations = durationOnly == null
        ? Iterable<int>.generate(
            FinancialRules.maxDurationForCategory(RosterCategory.standard),
            (index) => index + 1,
          )
        : [durationOnly];
    _HumanCandidate? cheapest;
    for (final duration in durations) {
      final maxSalary = FreeAgentMarketValueService.maxYearOneForDuration(
        duration,
      );
      var low = FinancialRules.minimumSalary;
      var high = maxSalary + 1;
      while (low < high) {
        final salary = low + (high - low) ~/ 2;
        final willingness = _evaluator.evaluateWillingness(
          career: career,
          teamId: teamId,
          freeAgentId: entry.id,
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
      if (low > maxSalary) continue;
      if (requireFinancialLegality) {
        final decision = _evaluator.evaluate(
          career: career,
          teamId: teamId,
          freeAgentId: entry.id,
          category: RosterCategory.standard,
          durationYears: duration,
          agreedFirstYearSalary: low,
          clearanceOffer: clearanceOffer,
        );
        if (!decision.isAcceptable) continue;
      }
      final candidate = _HumanCandidate(entry.id, low, duration);
      if (cheapest == null || candidate.compareTo(cheapest) < 0) {
        cheapest = candidate;
      }
    }
    if (cheapest != null) candidates.add(cheapest);
  }
  candidates.sort((a, b) => a.compareTo(b));
  return candidates;
}

GmCareer _completeDraft(GmCareer career) {
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

GmCareer _completeAiRookieDecisions(GmCareer career) {
  const rookies = RookieAiSigningService();
  var current = rookies.initialize(career);
  while (rookies.pendingRights(current).isNotEmpty) {
    current = rookies.applyNextDecision(current);
  }
  return current;
}

final class _HumanCandidate implements Comparable<_HumanCandidate> {
  const _HumanCandidate(this.playerId, this.salary, this.duration);

  final PlayerId playerId;
  final int salary;
  final int duration;

  int get totalSalary => FinancialRules.standardSchedule(
    salary,
    duration,
  ).fold<int>(0, (sum, amount) => sum + amount);

  @override
  int compareTo(_HumanCandidate other) {
    var order = salary.compareTo(other.salary);
    if (order != 0) return order;
    order = totalSalary.compareTo(other.totalSalary);
    if (order != 0) return order;
    order = duration.compareTo(other.duration);
    return order != 0 ? order : playerId.value.compareTo(other.playerId.value);
  }
}

final class _ActiveResult {
  const _ActiveResult({
    required this.career,
    required this.readiness,
    required this.assessments,
    required this.hardshipAcquisitions,
    required this.financialBlocks,
    required this.competitionBlocks,
    required this.competitionTeamIds,
    required this.playerRejectionBlocks,
    required this.ordinaryUsed,
    required this.hardshipUsed,
    required this.maximumRequired,
    required this.humanOffers,
  });

  final GmCareer career;
  final OffseasonReadinessResult readiness;
  final Map<String, HardshipTeamAssessment> assessments;
  final int hardshipAcquisitions;
  final int financialBlocks;
  final int competitionBlocks;
  final Set<String> competitionTeamIds;
  final int playerRejectionBlocks;
  final int ordinaryUsed;
  final int hardshipUsed;
  final int maximumRequired;
  final int humanOffers;
}

final class _CommitThenFailCareerStorage implements GmCareerStorage {
  _CommitThenFailCareerStorage(this.delegate);

  final InMemoryGmCareerStorage delegate;
  bool failNextWrite = false;

  @override
  Future<String?> read({String slot = 'default'}) => delegate.read(slot: slot);

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    await delegate.write(data, slot: slot);
    if (failNextWrite) {
      failNextWrite = false;
      throw const GmCareerStorageException('Injected post-promotion failure');
    }
  }

  @override
  Future<void> clear({String slot = 'default'}) => delegate.clear(slot: slot);

  @override
  Future<bool> hasSave({String slot = 'default'}) =>
      delegate.hasSave(slot: slot);
}
