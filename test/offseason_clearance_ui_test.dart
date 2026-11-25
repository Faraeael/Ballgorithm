import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/offseason_clearance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

Future<GmCareerController> _controller() async {
  final controller = GmCareerController(storage: InMemoryGmCareerStorage());
  await controller.startCareer(
    const CareerSetupService().generate(
      const CareerSetupRequest(
        selectedTeamId: TeamId('team-1'),
        selectedSituation: FranchiseSituation.tanking,
        seed: 20261028,
      ),
    ),
  );
  return controller;
}

/// Real draft, AI rookie signing and two free-agency rounds; no clearance yet.
GmCareer _postFreeAgencyCareer({required int seed}) {
  var c = GmCareer.fromSetupResult(
    const CareerSetupService().generate(
      CareerSetupRequest(
        selectedTeamId: const TeamId('team-1'),
        selectedSituation: FranchiseSituation.tanking,
        seed: seed,
      ),
    ),
    id: 'clearance-financial-exception',
  );
  const draft = DraftExecutionService();
  const aiSigning = RookieAiSigningService();
  const market = FreeAgentMarketService();
  c = draft.startDraft(c);
  while (!c.draftExecutionState.isCompleted) {
    if (c.draftExecutionState.isHumanTurn(
      order: c.draftOrder,
      userTeamId: c.userFranchiseId,
    )) {
      final pick = c.draftClass.prospects.firstWhere(
        (p) => !c.draftExecutionState.draftRights.containsKey(p.id.value),
      );
      c = draft.makeHumanSelection(career: c, prospectId: pick.id);
    } else {
      c = draft.executeAiSelection(c);
    }
  }
  c = aiSigning.initialize(c);
  while (aiSigning.pendingRights(c).isNotEmpty) {
    c = aiSigning.applyNextDecision(c);
  }
  for (var round = 0; round < 2; round++) {
    c = market.startRound(c);
    c = market.prepareResolution(c);
    while (c.freeAgentMarket.isResolvable) {
      c = market.resolveNext(c);
    }
  }
  return c;
}

void main() {
  testWidgets('clearance screen shows actionable blocker and fits sizes', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    for (final size in [const Size(360, 640), const Size(393, 852)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(home: GmOffseasonClearanceScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('offseason-clearance')), findsOneWidget);
      expect(
        find.textContaining('Rookie draft is not complete'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'financialExceptionRequired exposes Start Clearance without bypassing the gate',
    (tester) async {
      final c = _postFreeAgencyCareer(seed: 3);
      const gate = OffseasonReadinessGate();
      expect(
        gate.evaluate(c).status,
        OffseasonReadinessStatus.financialExceptionRequired,
      );
      expect(c.offseasonClearance.status, OffseasonClearanceStatus.notStarted);
      final storage = InMemoryGmCareerStorage();
      await storage.write(GmCareerCodec.encode(c));
      final controller = GmCareerController(storage: storage);
      addTearDown(controller.dispose);
      await controller.loadCareer();

      await tester.pumpWidget(
        MaterialApp(home: GmOffseasonClearanceScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(find.text('financialExceptionRequired'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('start-clearance')));
      await tester.pumpAndSettle();

      final started = controller.career!;
      expect(
        started.offseasonClearance.status,
        isNot(OffseasonClearanceStatus.notStarted),
      );
      expect(find.byKey(const ValueKey('start-clearance')), findsNothing);
      expect(
        gate.evaluate(started).status,
        isNot(OffseasonReadinessStatus.cleared),
      );
      expect(
        gate.evaluate(started).status,
        isNot(OffseasonReadinessStatus.readyForConfirmation),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
