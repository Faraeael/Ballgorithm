import 'dart:async';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/offseason_clearance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

import '../packages/simulation_core/test/support/career_season_fixtures.dart';

GmCareer _emergencyCareer() {
  var career = preFreeAgencyOffseason(seed: 271828182);
  const market = FreeAgentMarketService();
  const clearance = OffseasonClearanceService();
  const hardship = HardshipSettlementService();
  for (var round = 0; round < 2; round++) {
    career = market.startRound(career);
    career = market.prepareResolution(career);
    while (career.freeAgentMarket.isResolvable) {
      career = market.resolveNext(career);
    }
  }
  career = clearance.start(career);
  career = clearance.prepare(career);
  while (career.offseasonClearance.isResolvable) {
    career = clearance.resolveNext(career);
  }
  career = hardship.prepare(career, humanParticipationConfirmed: true);
  while (career.hardshipSettlement.isResolvable) {
    career = hardship.resolveNext(career);
  }
  return career;
}

class _ControlledStorage extends InMemoryGmCareerStorage {
  _ControlledStorage(String initial) : super({'default': initial});

  int writes = 0;
  Completer<void>? pendingWrite;

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    writes++;
    final pending = pendingWrite;
    if (pending != null) await pending.future;
    await super.write(data, slot: slot);
  }
}

Future<void> _openPreview(WidgetTester tester) async {
  final review = find.byKey(const ValueKey('review-emergency-roster'));
  await tester.ensureVisible(review);
  await tester.tap(review);
  await tester.pumpAndSettle();
}

void main() {
  late GmCareer career;
  late EmergencyRosterPlan plan;
  late String initial;

  setUpAll(() {
    career = _emergencyCareer();
    plan = const EmergencyRosterService().preview(career);
    initial = GmCareerCodec.encode(career);
  });

  Future<(GmCareerController, _ControlledStorage)> mount(
    WidgetTester tester,
  ) async {
    final storage = _ControlledStorage(initial);
    final controller = GmCareerController(storage: storage);
    addTearDown(controller.dispose);
    await controller.loadCareer();
    await tester.pumpWidget(
      MaterialApp(home: GmOffseasonClearanceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    return (controller, storage);
  }

  testWidgets('preview and decline leave career and storage unchanged', (
    tester,
  ) async {
    final (controller, storage) = await mount(tester);
    expect(career.hardshipSettlement.isComplete, isTrue);
    expect(plan.teams, isNotEmpty);
    await _openPreview(tester);
    expect(find.text('Emergency roster completion'), findsOneWidget);
    expect(find.text('Allocation: ${plan.status.name}'), findsOneWidget);
    final team = plan.teams.first;
    expect(
      find.textContaining(
        '${team.teamId.value}: standard ${team.standardBefore}',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Missing positions:'), findsWidgets);
    for (final blocker in plan.blockers) {
      expect(find.text(blocker), findsOneWidget);
    }
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(storage.writes, 0);
    expect(await storage.read(), initial);
    expect(GmCareerCodec.encode(controller.career!), initial);
  });

  testWidgets('confirmation saves before publishing the career', (
    tester,
  ) async {
    final (controller, storage) = await mount(tester);
    expect(
      plan.status,
      anyOf(
        EmergencyPlanStatus.optimal,
        EmergencyPlanStatus.feasibleNotProvenOptimal,
      ),
    );
    expect(plan.offers, isNotEmpty);
    final pending = Completer<void>();
    storage.pendingWrite = pending;
    await _openPreview(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-emergency-roster')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(storage.writes, 1);
    expect(await storage.read(), initial);
    expect(GmCareerCodec.encode(controller.career!), initial);
    pending.complete();
    await tester.pumpAndSettle();
    await controller.commandsSettled;
    final saved = await storage.read();
    expect(saved, isNot(initial));
    expect(GmCareerCodec.encode(controller.career!), saved);
    expect(controller.career!.emergencySettlement, isNotNull);
    // Consent is recorded only when the reviewed plan contains human offers.
    expect(
      controller.career!.emergencySettlement!.humanApproved,
      plan.offers.any((offer) => offer.teamId == career.userFranchiseId),
    );
    expect(
      controller.career!.emergencySettlement!.offers.length,
      plan.offers.length,
    );
  });

  testWidgets('failed save requires reload before emergency retry', (
    tester,
  ) async {
    final (controller, storage) = await mount(tester);
    expect(
      plan.status,
      anyOf(
        EmergencyPlanStatus.optimal,
        EmergencyPlanStatus.feasibleNotProvenOptimal,
      ),
    );
    storage.shouldThrowOnWrite = true;
    await _openPreview(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-emergency-roster')));
    await tester.pumpAndSettle();
    expect(storage.writes, 1);
    expect(controller.draftRecoveryRequired, isTrue);
    expect(GmCareerCodec.encode(controller.career!), initial);
    expect(await storage.read(), initial);
    expect(
      find.textContaining('Injected in-memory write error'),
      findsOneWidget,
    );
    final review = find.byKey(const ValueKey('review-emergency-roster'));
    expect(tester.widget<FilledButton>(review).onPressed, isNull);
    storage.shouldThrowOnWrite = false;
    final reload = find.byKey(const ValueKey('reload-after-save-failure'));
    await tester.ensureVisible(reload);
    await tester.tap(reload);
    await tester.pumpAndSettle();
    expect(controller.draftRecoveryRequired, isFalse);
    expect(GmCareerCodec.encode(controller.career!), initial);
    await _openPreview(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-emergency-roster')));
    await tester.pumpAndSettle();
    expect(storage.writes, 2);
    expect(controller.career!.emergencySettlement, isNotNull);
    expect(await storage.read(), GmCareerCodec.encode(controller.career!));
  });
}
