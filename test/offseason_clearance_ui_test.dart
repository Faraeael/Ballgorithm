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
}
