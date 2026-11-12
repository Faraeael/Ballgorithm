import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/free_agent_offer_screen.dart';
import 'package:basketball_manager/features/career/free_agents_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _market = FreeAgentMarketValueService();

Future<GmCareerController> _controller() async {
  final controller = GmCareerController(storage: InMemoryGmCareerStorage());
  await controller.startCareer(
    const CareerSetupService().generate(
      const CareerSetupRequest(
        selectedTeamId: TeamId('team-1'),
        selectedSituation: FranchiseSituation.playIn,
        seed: 20261028,
      ),
    ),
  );
  return controller;
}

Future<void> _pumpBoard(
  WidgetTester tester,
  GmCareerController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(home: GmFreeAgentsScreen(controller: controller)),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpOfferRoute(
  WidgetTester tester,
  GmCareerController controller,
  PlayerId id,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const ValueKey('open-offer'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GmFreeAgentOfferScreen(
                    controller: controller,
                    freeAgentId: id,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-offer')));
  await tester.pumpAndSettle();
}

Future<void> _scrollToKey(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _submitVisibleOffer(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('offer-submit')),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('offer-submit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('offer-confirm-submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('free-agent board lists public data and offer action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await _pumpBoard(tester, controller);

    expect(find.byKey(const ValueKey('free-agents-screen')), findsOneWidget);
    expect(find.text('Free Agents (90)'), findsOneWidget);
    expect(find.textContaining('Est. market'), findsWidgets);
    expect(
      find.textContaining('Estimated values are public guidance'),
      findsOneWidget,
    );
    expect(find.textContaining('Potential'), findsNothing);
    expect(find.textContaining('Trajectory'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Sign'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Make Offer'), findsWidgets);
    expect(find.byKey(const ValueKey('free-agent-list')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('free-agent board filters and sorts at both target sizes', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    for (final size in [const Size(360, 640), const Size(393, 852)]) {
      await tester.binding.setSurfaceSize(size);
      await _pumpBoard(tester, controller);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('free-agent-filter-PG')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('shown'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('free-agent-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Age').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('offer form shows financial preview without hidden thresholds', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    final entry = controller.career!.freeAgentPool.entries.firstWhere(
      (candidate) => candidate.player.attributes.overallRating >= 60,
    );
    for (final size in [const Size(360, 640), const Size(393, 852)]) {
      await tester.binding.setSurfaceSize(size);
      await _pumpOfferRoute(tester, controller, entry.id);
      expect(
        find.byKey(const ValueKey('free-agent-offer-screen')),
        findsOneWidget,
      );
      expect(find.textContaining('Estimated market'), findsOneWidget);
      await _scrollToKey(tester, const ValueKey('offer-attempts'));
      expect(find.byKey(const ValueKey('offer-attempts')), findsOneWidget);
      expect(find.textContaining('threshold'), findsNothing);
      expect(find.textContaining('Potential'), findsNothing);
      expect(find.textContaining('Trajectory'), findsNothing);
      expect(tester.takeException(), isNull);
      Navigator.of(
        tester.element(find.byKey(const ValueKey('free-agent-offer-screen'))),
      ).pop();
      await tester.pumpAndSettle();
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('cancel on confirmation performs no write', (tester) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    final entry = controller.career!.freeAgentPool.entries.first;
    await _pumpOfferRoute(tester, controller, entry.id);
    await _scrollToKey(tester, const ValueKey('offer-submit'));
    await tester.tap(find.byKey(const ValueKey('offer-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('offer-cancel')));
    await tester.pumpAndSettle();
    expect(controller.career!.freeAgentOffers.length, 0);
    expect(controller.career!.freeAgentPool.length, 90);
  });

  testWidgets('accepted offer updates pool, roster and history', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    final entry = controller.career!.freeAgentPool.entries.firstWhere(
      (candidate) => candidate.player.attributes.overallRating >= 60,
    );
    final valuation = _market.estimate(entry.toPublicView());
    await _pumpOfferRoute(tester, controller, entry.id);
    await tester.enterText(
      find.byKey(const ValueKey('offer-salary')),
      '${valuation.acceptableMaximum}',
    );
    await _submitVisibleOffer(tester);
    expect(find.text('Offer Accepted'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(controller.career!.freeAgentPool.length, 89);
    expect(controller.career!.freeAgentOffers.length, 1);
    expect(
      controller.career!.freeAgentOffers
          .attemptsFor(
            teamId: controller.career!.userFranchiseId,
            playerId: entry.id,
            seasonYear: 1,
          )
          .single
          .outcome,
      FreeAgentOfferOutcome.accepted,
    );
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('rejected offer persists and leaves the form available', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    final entry = controller.career!.freeAgentPool.entries.firstWhere(
      (candidate) => candidate.player.attributes.overallRating >= 75,
    );
    await _pumpOfferRoute(tester, controller, entry.id);
    await tester.enterText(find.byKey(const ValueKey('offer-salary')), '400');
    await _submitVisibleOffer(tester);
    expect(find.text('Offer Rejected'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(controller.career!.freeAgentOffers.length, 1);
    expect(controller.career!.freeAgentPool.length, 90);
    expect(
      find.byKey(const ValueKey('free-agent-offer-screen')),
      findsOneWidget,
    );
    expect(find.textContaining('1'), findsWidgets);
  });
}
