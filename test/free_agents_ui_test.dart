import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/free_agents_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

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

void main() {
  testWidgets('free-agent board lists public data without hidden fields', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _controller();
    addTearDown(controller.dispose);
    await _pumpBoard(tester, controller);

    expect(find.byKey(const ValueKey('free-agents-screen')), findsOneWidget);
    expect(find.text('Free Agents (90)'), findsOneWidget);
    expect(
      find.text('Read-only board. No contract offers yet.'),
      findsOneWidget,
    );
    expect(find.textContaining('Potential'), findsNothing);
    expect(find.textContaining('Trajectory'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Sign'), findsNothing);
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
}
