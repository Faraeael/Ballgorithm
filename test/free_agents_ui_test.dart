import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/free_agent_offer_screen.dart';
import 'package:basketball_manager/features/career/free_agents_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _value = FreeAgentMarketValueService();

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

void main() {
  testWidgets('market board starts a round and exposes public offers', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await _pumpBoard(tester, controller);

    expect(find.byKey(const ValueKey('free-agents-screen')), findsOneWidget);
    expect(find.text('Free Agents (90)'), findsOneWidget);
    expect(find.textContaining('Free Agency Round 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('start-free-agency')), findsOneWidget);
    expect(find.textContaining('Potential'), findsNothing);
    expect(find.textContaining('Trajectory'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('start-free-agency')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Offers Open'), findsOneWidget);
    expect(find.byKey(const ValueKey('lock-free-agency')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Make Offer'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offer form stages a pending offer without acquisition', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await controller.startFreeAgencyRound();
    final entry = controller.career!.freeAgentPool.entries.firstWhere(
      (candidate) => candidate.player.attributes.overallRating >= 60,
    );
    final valuation = _value.estimate(entry.toPublicView());
    await _pumpOfferRoute(tester, controller, entry.id);
    expect(find.textContaining('Estimated market'), findsOneWidget);
    expect(find.textContaining('threshold'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('offer-salary')),
      '${valuation.acceptableMaximum}',
    );
    await _scrollToKey(tester, const ValueKey('offer-submit'));
    await tester.tap(find.byKey(const ValueKey('offer-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('AI franchises will compete'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('offer-confirm-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Offer Pending'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(controller.career!.freeAgentMarket.humanOffers.length, 1);
    expect(controller.career!.freeAgentPool.length, 90);
    expect(controller.career!.freeAgentOffers.length, 0);
  });

  testWidgets('pending human offer can be cancelled before locking', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await controller.startFreeAgencyRound();
    final entry = controller.career!.freeAgentPool.entries.first;
    final valuation = _value.estimate(entry.toPublicView());
    await controller.stageFreeAgentOffer(
      freeAgentId: entry.id,
      category: RosterCategory.standard,
      durationYears: valuation.preferredDurationYears,
      firstYearSalary: valuation.acceptableMaximum,
    );
    await _pumpBoard(tester, controller);
    expect(
      find.byKey(ValueKey('cancel-offer-${entry.id.value}')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(ValueKey('cancel-offer-${entry.id.value}')));
    await tester.pumpAndSettle();
    expect(controller.career!.freeAgentMarket.humanOffers, isEmpty);
  });

  testWidgets('round locks and resolves with visible results', (tester) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await controller.startFreeAgencyRound();
    await _pumpBoard(tester, controller);
    await tester.tap(find.byKey(const ValueKey('lock-free-agency')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Prepared'), findsOneWidget);
    expect(find.byKey(const ValueKey('resolve-free-agency')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('resolve-free-agency')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Round Complete'), findsOneWidget);
    expect(controller.career!.freeAgentMarket.outcomes, isNotEmpty);
    expect(controller.career!.freeAgentMarket.completedRounds, 1);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('market-summary')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('league-market-summary')), findsOneWidget);
    expect(find.textContaining('Rounds completed'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Franchise obligations'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Franchise obligations'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('board and offer form fit both target sizes', (tester) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await controller.startFreeAgencyRound();
    final entry = controller.career!.freeAgentPool.entries.firstWhere(
      (candidate) => candidate.player.attributes.overallRating >= 60,
    );
    for (final size in [const Size(360, 640), const Size(393, 852)]) {
      await tester.binding.setSurfaceSize(size);
      await _pumpBoard(tester, controller);
      expect(tester.takeException(), isNull);
      await _pumpOfferRoute(tester, controller, entry.id);
      await _scrollToKey(tester, const ValueKey('offer-submit'));
      expect(tester.takeException(), isNull);
      Navigator.of(
        tester.element(find.byKey(const ValueKey('free-agent-offer-screen'))),
      ).pop();
      await tester.pumpAndSettle();
    }
    await tester.binding.setSurfaceSize(null);
  });
}
