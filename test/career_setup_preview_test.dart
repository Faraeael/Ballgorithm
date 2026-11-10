import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/career/career_setup_screens.dart';
import 'package:basketball_manager/features/season/season_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _config = GenerationConfig(seed: 20261028);

void _useSmallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  late League league;

  setUpAll(() {
    league = const LeagueGenerator().generate(_config);
  });

  group('M008-T03: Career Setup UI Preview Flow', () {
    testWidgets(
      'Full 3-screen preview flow: Team -> Situation -> League Preview',
      (tester) async {
        _useTallSurface(tester);
        final storage = InMemorySeasonStorage();

        await tester.pumpWidget(
          BasketballManagerApp(
            league: league,
            storage: storage,
            seasonMode: true,
          ),
        );
        await tester.pumpAndSettle();

        // On FranchiseSelectScreen, tap GM Career Preview
        expect(
          find.byKey(const ValueKey('open-career-preview')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('open-career-preview')));
        await tester.pumpAndSettle();

        // Screen 1: Select Team
        expect(find.text('GM Career: Select Team'), findsOneWidget);
        expect(find.byKey(const ValueKey('career-team-list')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('career-team-option-team-1')),
          findsOneWidget,
        );

        // Select Aurora Comets (team-1)
        await tester.tap(
          find.byKey(const ValueKey('career-team-option-team-1')),
        );
        await tester.pumpAndSettle();

        // Tap Next
        await tester.tap(find.byKey(const ValueKey('next-situation-button')));
        await tester.pumpAndSettle();

        // Screen 2: Select Situation
        expect(find.text('GM Career: Starting Situation'), findsOneWidget);
        expect(find.text('Aurora Comets'), findsOneWidget);
        expect(find.text('Opening Pick #1'), findsOneWidget);
        expect(find.text('Opening Pick #12'), findsOneWidget);
        expect(find.text('Opening Pick #20'), findsOneWidget);
        expect(find.text('Opening Pick #30'), findsOneWidget);

        // Select Tanking
        await tester.tap(find.byKey(const ValueKey('situation-card-tanking')));
        await tester.pumpAndSettle();

        // Tap Generate League & Preview Roster
        await tester.tap(
          find.byKey(const ValueKey('generate-career-preview-button')),
        );
        await tester.pumpAndSettle();

        // Screen 3: Generated League Preview
        expect(find.text('GM Career Setup: Preview'), findsOneWidget);
        expect(find.text('Aurora Comets'), findsOneWidget);
        expect(find.text('Tanking / Rebuilding'), findsOneWidget);
        expect(find.text('Pick #1'), findsOneWidget);
        expect(
          find.text('Initial Generated Roster (12 Players)'),
          findsOneWidget,
        );
        expect(
          find.text('30-Team Competitive Tier Distribution'),
          findsOneWidget,
        );
        expect(find.text('7 / 7 teams'), findsOneWidget);
        expect(find.text('9 / 9 teams'), findsNWidgets(2));
        expect(find.text('5 / 5 teams'), findsOneWidget);

        // Pop back safely
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('GM Career: Starting Situation'), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('GM Career: Select Team'), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        // Back at FranchiseSelectScreen; existing M007 season remains untouched
        expect(find.text('Select Your Franchise'), findsOneWidget);
      },
    );

    testWidgets(
      'Screen 3 renders without overflow on 360x640 mobile viewport',
      (tester) async {
        _useSmallViewport(tester);

        final request = const CareerSetupRequest(
          selectedTeamId: TeamId('team-1'),
          selectedSituation: FranchiseSituation.contender,
        );
        final result = const CareerSetupService().generate(request);

        await tester.pumpWidget(
          MaterialApp(home: CareerLeaguePreviewScreen(result: result)),
        );
        await tester.pumpAndSettle();

        expect(find.text('GM Career Setup: Preview'), findsOneWidget);
        expect(find.text('Aurora Comets'), findsOneWidget);
        expect(find.text('Championship Contender'), findsOneWidget);
        expect(find.text('Pick #30'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
