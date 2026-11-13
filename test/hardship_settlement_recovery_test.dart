import 'dart:convert';

import 'package:basketball_manager/features/career/offseason_clearance_screen.dart';
import 'package:flutter/material.dart';
import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _seed = 1604126146;
const _draft = DraftExecutionService();
const _rookies = RookieAiSigningService();
const _market = FreeAgentMarketService();
const _clearance = OffseasonClearanceService();
const _hardship = HardshipSettlementService();

GmCareer _preparedHardshipCareer({bool prepareHardship = true}) {
  var career = GmCareer.fromSetupResult(
    const CareerSetupService().generate(
      CareerSetupRequest(
        selectedTeamId: TeamId('team-1'),
        selectedSituation: FranchiseSituation.tanking,
        seed: _seed,
      ),
    ),
    id: 't08h-p2-recovery',
  );
  career = _draft.startDraft(career);
  while (!career.draftExecutionState.isCompleted) {
    career =
        career.draftExecutionState.isHumanTurn(
          order: career.draftOrder,
          userTeamId: career.userFranchiseId,
        )
        ? _draft.makeHumanSelection(
            career: career,
            prospectId: career.draftExecutionState
                .availableProspects(career.draftClass)
                .first
                .id,
          )
        : _draft.executeAiSelection(career);
  }
  career = _rookies.initialize(career);
  while (_rookies.pendingRights(career).isNotEmpty) {
    career = _rookies.applyNextDecision(career);
  }
  for (var round = 0; round < 2; round++) {
    career = _market.startRound(career);
    career = _market.prepareResolution(career);
    while (career.freeAgentMarket.isResolvable) {
      career = _market.resolveNext(career);
    }
  }
  career = _clearance.start(career);
  career = _clearance.prepare(career);
  while (career.offseasonClearance.isResolvable) {
    career = _clearance.resolveNext(career);
  }
  return prepareHardship
      ? _hardship.prepare(career, humanParticipationConfirmed: false)
      : career;
}

GmCareer _eligibleHumanHardshipCareer() {
  final career = _preparedHardshipCareer(prepareHardship: false);
  final raw = jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
  final finances = raw['finances'] as Map<String, dynamic>;
  final contracts = {
    for (final contract in finances['contracts'] as List<dynamic>)
      (contract as Map<String, dynamic>)['id'] as String: contract,
  };
  const salaries = [
    4100,
    4100,
    4100,
    4100,
    4100,
    4100,
    3300,
    3300,
    3300,
    3300,
    2600,
    400,
  ];
  var index = 0;
  var payrollChange = 0;
  for (final schedule
      in (finances['schedules'] as List<dynamic>)
          .cast<Map<String, dynamic>>()) {
    final contract = contracts[schedule['contractId']] as Map<String, dynamic>;
    if (contract['teamId'] != 'team-1' ||
        contract['category'] != RosterCategory.standard.jsonValue) {
      continue;
    }
    final annual = (schedule['annualSalaries'] as List<dynamic>).cast<int>();
    final salary = salaries[index++];
    payrollChange += salary - annual.first;
    schedule['annualSalaries'] = FinancialRules.standardSchedule(
      salary,
      annual.length,
    );
  }
  if (index != salaries.length) {
    throw StateError('Expected 12 human standard contracts, got $index');
  }
  for (final team
      in (finances['teamFinances'] as List<dynamic>)
          .cast<Map<String, dynamic>>()) {
    if (team['teamId'] == 'team-1') {
      team['cash'] = (team['cash'] as int) + payrollChange;
    }
  }
  final adjusted = GmCareerCodec.decode(jsonEncode(raw));
  if (!_hardship.assessTeam(adjusted, adjusted.userFranchiseId).eligible) {
    throw StateError('Human test fixture must qualify for hardship');
  }
  return adjusted;
}

Future<void> _openHumanHardshipDialog(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('confirm-human-hardship')),
    220,
  );
  await tester.tap(find.byKey(const ValueKey('confirm-human-hardship')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('approve-human-hardship')), findsOneWidget);
}

GmCareer _resolveAll(GmCareer career) {
  var current = career;
  while (current.hardshipSettlement.isResolvable) {
    current = _hardship.resolveNext(current);
  }
  return current;
}

void main() {
  testWidgets('decline hardship leaves authority and acquisitions unchanged', (
    tester,
  ) async {
    final career = _eligibleHumanHardshipCareer();
    final assessment = _hardship.assessTeam(career, career.userFranchiseId);
    expect(assessment.eligible, isTrue);
    final storage = _PromoteThenFailStorage(GmCareerCodec.encode(career));
    final controller = GmCareerController(storage: storage);
    addTearDown(controller.dispose);
    await controller.loadCareer();
    await tester.pumpWidget(
      MaterialApp(home: GmOffseasonClearanceScreen(controller: controller)),
    );
    await _openHumanHardshipDialog(tester);
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(controller.career!.hardshipSettlement.authorizations, isEmpty);
    expect(
      controller.career!.freeAgentPool.acquisitions.entries.values.where(
        (item) => item.origin == AcquisitionOrigin.hardship,
      ),
      isEmpty,
    );
    expect(storage.writes, 0);
  });

  testWidgets('AI preparation never confirms human hardship', (tester) async {
    final career = _eligibleHumanHardshipCareer();
    final storage = _PromoteThenFailStorage(GmCareerCodec.encode(career));
    final controller = GmCareerController(storage: storage);
    addTearDown(controller.dispose);
    await controller.loadCareer();
    await tester.pumpWidget(
      MaterialApp(home: GmOffseasonClearanceScreen(controller: controller)),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('prepare-ai-hardship')),
      240,
    );
    await tester.tap(find.byKey(const ValueKey('prepare-ai-hardship')));
    await tester.pumpAndSettle();
    final settlement = controller.career!.hardshipSettlement;
    expect(settlement.humanParticipationConfirmed, isFalse);
    expect(
      settlement.authorizations.any(
        (authorization) => authorization.teamId == career.userFranchiseId,
      ),
      isFalse,
    );
    expect(
      settlement.offers.any((offer) => offer.teamId == career.userFranchiseId),
      isFalse,
    );
  });

  testWidgets('confirm persists only displayed offers and cannot be reused', (
    tester,
  ) async {
    final career = _eligibleHumanHardshipCareer();
    final displayed = _hardship.assessTeam(career, career.userFranchiseId);
    final storage = _PromoteThenFailStorage(GmCareerCodec.encode(career));
    final controller = GmCareerController(storage: storage);
    addTearDown(controller.dispose);
    await controller.loadCareer();
    await tester.pumpWidget(
      MaterialApp(home: GmOffseasonClearanceScreen(controller: controller)),
    );
    await _openHumanHardshipDialog(tester);
    await tester.tap(find.byKey(const ValueKey('approve-human-hardship')));
    await tester.pumpAndSettle();
    final prepared = controller.career!.hardshipSettlement;
    final authorization = prepared.authorizationFor(career.userFranchiseId)!;
    expect(prepared.humanParticipationConfirmed, isTrue);
    expect(
      authorization.authorizedOfferIds,
      displayed.proposedOffers.map((offer) => offer.offerId),
    );
    expect(
      prepared.offers
          .where((offer) => offer.teamId == career.userFranchiseId)
          .map((offer) => offer.offerId)
          .toSet(),
      authorization.authorizedOfferIds.toSet(),
    );
    expect(storage.writes, 1);
    await expectLater(
      controller.prepareHardshipSettlement(humanParticipationConfirmed: true),
      throwsA(isA<DomainValidationException>()),
    );
    expect(storage.writes, 1);
    final authorizedOffer = prepared.offers.firstWhere(
      (offer) => offer.teamId == career.userFranchiseId,
    );
    final otherPlayer = career.freeAgentPool.entries
        .firstWhere((entry) => entry.id != authorizedOffer.playerId)
        .id;
    final beforeUnauthorizedAttempt = GmCareerCodec.encode(controller.career!);
    expect(
      () => const FreeAgentAcquisitionService().acquire(
        career: controller.career!,
        teamId: career.userFranchiseId,
        freeAgentId: otherPlayer,
        category: RosterCategory.standard,
        durationYears: authorizedOffer.durationYears,
        agreedFirstYearSalary: authorizedOffer.firstYearSalary,
        origin: AcquisitionOrigin.hardship,
        hardshipOfferId: authorizedOffer.offerId,
        hardshipSettlementAfterAcquisition: prepared,
        freeAgentOffersAfterAcquisition: controller.career!.freeAgentOffers,
      ),
      throwsA(isA<DomainValidationException>()),
    );
    expect(GmCareerCodec.encode(controller.career!), beforeUnauthorizedAttempt);
  });

  testWidgets(
    'uncertain confirmation write requires reload and avoids replay',
    (tester) async {
      final career = _eligibleHumanHardshipCareer();
      final storage = _PromoteThenFailStorage(GmCareerCodec.encode(career))
        ..failAfterPromotionAt = 1;
      final controller = GmCareerController(storage: storage);
      addTearDown(controller.dispose);
      await controller.loadCareer();
      await tester.pumpWidget(
        MaterialApp(home: GmOffseasonClearanceScreen(controller: controller)),
      );
      await _openHumanHardshipDialog(tester);
      await tester.tap(find.byKey(const ValueKey('approve-human-hardship')));
      await tester.pumpAndSettle();
      expect(controller.draftRecoveryRequired, isTrue);
      expect(
        controller.career!.hardshipSettlement.status,
        HardshipSettlementStatus.notStarted,
      );
      expect(
        find.byKey(const ValueKey('reload-after-save-failure')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('reload-after-save-failure')));
      await tester.pumpAndSettle();
      final reloaded = controller.career!;
      expect(reloaded.hardshipSettlement.humanParticipationConfirmed, isTrue);
      final expected = _resolveAll(reloaded);
      storage.failAfterPromotionAt = 2;
      await expectLater(
        controller.resolveHardshipSettlement(),
        throwsA(isA<GmCareerStorageException>()),
      );
      await tester.pumpAndSettle();
      expect(controller.draftRecoveryRequired, isTrue);
      final committed = GmCareerCodec.decode(storage.data!);
      expect(committed.hardshipSettlement.nextResolutionIndex, 1);
      expect(committed.hardshipSettlement.outcomes, hasLength(1));
      expect(
        find.byKey(const ValueKey('reload-after-save-failure')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('reload-after-save-failure')));
      await tester.pumpAndSettle();
      expect(controller.career!.hardshipSettlement.nextResolutionIndex, 1);
      await controller.resolveHardshipSettlement();
      final completed = controller.career!;
      expect(GmCareerCodec.encode(completed), GmCareerCodec.encode(expected));
      expect(
        completed.hardshipSettlement.authorizations
            .map((authorization) => authorization.authorizationId)
            .toSet()
            .length,
        completed.hardshipSettlement.authorizations.length,
      );
      expect(
        completed.hardshipSettlement.outcomes
            .map((outcome) => outcome.playerId)
            .toSet()
            .length,
        completed.hardshipSettlement.outcomes.length,
      );
    },
  );
  test(
    'committed hardship writes resume without replay or transaction loss',
    () async {
      final prepared = _preparedHardshipCareer();
      expect(
        prepared.hardshipSettlement.resolutionOrder.length,
        greaterThan(1),
      );
      final expected = _resolveAll(prepared);
      final storage = _PromoteThenFailStorage(GmCareerCodec.encode(prepared));
      final controller = GmCareerController(storage: storage);
      addTearDown(controller.dispose);

      await controller.loadCareer();
      storage.failAfterPromotionAt = 2;
      await expectLater(
        controller.resolveHardshipSettlement(),
        throwsA(isA<GmCareerStorageException>()),
      );
      expect(controller.draftRecoveryRequired, isTrue);
      expect(storage.writes, 2);
      final committed = GmCareerCodec.decode(storage.data!);
      expect(committed.hardshipSettlement.nextResolutionIndex, 2);
      expect(committed.hardshipSettlement.outcomes, hasLength(2));

      final reloaded = GmCareerController(storage: storage);
      addTearDown(reloaded.dispose);
      await reloaded.loadCareer();
      expect(reloaded.draftRecoveryRequired, isFalse);
      expect(
        reloaded.career!.hardshipSettlement.nextResolutionIndex,
        committed.hardshipSettlement.nextResolutionIndex,
      );
      await reloaded.resolveHardshipSettlement();

      final actual = reloaded.career!;
      expect(GmCareerCodec.encode(actual), GmCareerCodec.encode(expected));
      expect(
        actual.hardshipSettlement.status,
        HardshipSettlementStatus.complete,
      );
      expect(
        actual.hardshipSettlement.outcomes.length,
        actual.hardshipSettlement.resolutionOrder.length,
      );
      expect(
        actual.hardshipSettlement.outcomes
            .map((outcome) => outcome.playerId)
            .toSet()
            .length,
        actual.hardshipSettlement.outcomes.length,
      );
      expect(actual.phase, CareerPhase.openingOffseason);
      expect(actual.currentYear, 1);
      actual.validate();
    },
  );
  testWidgets('hardship controls fit small and large mobile layouts', (
    tester,
  ) async {
    final career = _preparedHardshipCareer(prepareHardship: false);
    expect(career.offseasonClearance.status, OffseasonClearanceStatus.complete);
    expect(
      career.hardshipSettlement.status,
      HardshipSettlementStatus.notStarted,
    );
    expect(
      OffseasonReadinessGate().evaluate(career).belowMinimumCount,
      greaterThan(0),
    );
    final storage = _PromoteThenFailStorage(GmCareerCodec.encode(career));
    final controller = GmCareerController(storage: storage);
    addTearDown(controller.dispose);
    await controller.loadCareer();

    for (final size in const [Size(360, 640), Size(393, 852)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(home: GmOffseasonClearanceScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('offseason-clearance')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('prepare-ai-hardship')),
        240,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('prepare-ai-hardship')), findsOneWidget);
      expect(find.textContaining('acceptance threshold'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

final class _PromoteThenFailStorage implements GmCareerStorage {
  _PromoteThenFailStorage(this.data);

  String? data;
  int writes = 0;
  int? failAfterPromotionAt;

  @override
  Future<String?> read({String slot = 'default'}) async => data;

  @override
  Future<void> write(String next, {String slot = 'default'}) async {
    writes++;
    data = next;
    if (writes == failAfterPromotionAt) {
      failAfterPromotionAt = null;
      throw const GmCareerStorageException(
        'Injected failure after save promotion',
      );
    }
  }

  @override
  Future<void> clear({String slot = 'default'}) async {
    data = null;
  }

  @override
  Future<bool> hasSave({String slot = 'default'}) async =>
      data != null && data!.isNotEmpty;
}
