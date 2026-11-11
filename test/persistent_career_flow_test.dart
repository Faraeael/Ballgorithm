import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
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

void main() {
  late League league;

  setUpAll(() {
    league = const LeagueGenerator().generate(_config);
  });

  group('M008-T04: Persistent GM Career UI & Lifecycle Flow', () {
    testWidgets(
      'Full End-to-End: Create career -> Offseason Overview -> Restart app -> State restored',
      (tester) async {
        _useSmallViewport(tester);

        final seasonStorage = InMemorySeasonStorage();
        final careerStorage = InMemoryGmCareerStorage();

        // 1. Initial app launch
        await tester.pumpWidget(
          BasketballManagerApp(
            league: league,
            storage: seasonStorage,
            careerStorage: careerStorage,
            seasonMode: true,
            seedProvider: () => 20261028,
          ),
        );
        await tester.pumpAndSettle();

        // Tap GM Career preview from franchise select
        expect(
          find.byKey(const ValueKey('open-career-preview')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('open-career-preview')));
        await tester.pumpAndSettle();

        // Screen 1: Select Aurora Comets (team-1)
        expect(find.text('GM Career: Select Team'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('career-team-option-team-1')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('next-situation-button')));
        await tester.pumpAndSettle();

        // Screen 2: Select Tanking situation
        expect(find.text('GM Career: Starting Situation'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('situation-card-tanking')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('generate-career-preview-button')),
        );
        await tester.pumpAndSettle();

        // Screen 3: Generated Preview
        expect(find.text('GM Career Setup: Preview'), findsOneWidget);

        // Drag down to reveal Start GM Career button
        await tester.drag(
          find.byKey(const ValueKey('career-preview-scroll')),
          const Offset(0, -1500),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('start-career-button')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('start-career-button')));
        await tester.pumpAndSettle();

        // Confirmation dialog appears
        expect(find.text('Confirm GM Career Creation'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('confirm-start-career-button')),
          findsOneWidget,
        );

        // Confirm creation
        await tester.tap(
          find.byKey(const ValueKey('confirm-start-career-button')),
        );
        await tester.pumpAndSettle();

        // Offseason Overview Screen is now active (Scope 1, 8, 17)
        expect(find.text('AUR Offseason'), findsOneWidget);
        expect(find.text('Aurora Comets'), findsOneWidget);
        expect(find.text('Year 1 • Opening Offseason'), findsOneWidget);
        expect(find.text('Starting Situation:'), findsOneWidget);
        expect(find.text('Tanking / Rebuilding'), findsOneWidget);
        expect(find.text('Guaranteed Rookie Draft Pick'), findsOneWidget);
        expect(find.text('#1'), findsOneWidget);
        expect(find.text('Current Roster (12 Players)'), findsOneWidget);
        // Scroll down to check disabled future modules
        await tester.drag(
          find.byKey(const ValueKey('offseason-overview-scroll')),
          const Offset(0, -1200),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Front Office Modules (In Development)'),
          findsOneWidget,
        );
        expect(find.text('Rookie Draft'), findsOneWidget);
        expect(find.text('Free Agency'), findsOneWidget);
        expect(find.text('Trades'), findsOneWidget);
        expect(find.text('Staff & Coaching'), findsOneWidget);
        expect(find.text('Facilities'), findsOneWidget);
        expect(find.text('Franchise Finances'), findsOneWidget);

        // Verify storage received valid career data
        expect(await careerStorage.hasSave(), isTrue);
        final savedJson = await careerStorage.read();
        expect(savedJson, isNotNull);
        final decoded = GmCareerCodec.decode(savedJson!);
        expect(decoded.userFranchiseId, TeamId('team-1'));
        expect(decoded.originalSituation, FranchiseSituation.tanking);
        expect(decoded.userOpeningDraftPick, 1);
        expect(decoded.league.teams.length, 30);

        // Scope 14: Verify M007 season storage remains completely untouched
        expect(await seasonStorage.read(), isNull);

        // 2. Simulate closing and reopening the app (Scope 10)
        await tester.pumpWidget(
          BasketballManagerApp(
            league: league,
            storage: seasonStorage,
            careerStorage: careerStorage,
            seasonMode: true,
          ),
        );
        await tester.pumpAndSettle();

        // App reopens directly into the restored Offseason Overview!
        expect(find.text('AUR Offseason'), findsOneWidget);
        await tester.drag(
          find.byKey(const ValueKey('offseason-overview-scroll')),
          const Offset(0, 1200),
        );
        await tester.pumpAndSettle();
        expect(find.text('Year 1 • Opening Offseason'), findsOneWidget);
        expect(find.text('Aurora Comets'), findsOneWidget);
        expect(find.text('#1'), findsOneWidget);

        // 3. Exit to Franchise Select
        expect(
          find.byKey(const ValueKey('exit-career-menu-button')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('exit-career-menu-button')));
        await tester.pumpAndSettle();

        // On FranchiseSelectScreen, Resume GM Career is available
        expect(
          find.byKey(const ValueKey('resume-career-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('resume-career-card-button')),
          findsOneWidget,
        );
        expect(find.text('Resume GM Career: Aurora Comets'), findsOneWidget);

        // Tap Resume GM Career
        await tester.tap(find.byKey(const ValueKey('resume-career-button')));
        await tester.pumpAndSettle();

        // Returned to Offseason Overview
        expect(find.text('AUR Offseason'), findsOneWidget);
      },
    );

    testWidgets(
      'Scope 13: Protection against accidental overwrite prompts for confirmation',
      (tester) async {
        _useSmallViewport(tester);

        final careerStorage = InMemoryGmCareerStorage();
        // Pre-populate with existing career
        const existingCareerJson = '{"schemaVersion":1,"id":"career-existing"}';
        await careerStorage.write(existingCareerJson);

        await tester.pumpWidget(
          BasketballManagerApp(
            league: league,
            careerStorage: careerStorage,
            seasonMode: true,
            seedProvider: () => 20261028,
          ),
        );
        await tester.pumpAndSettle();

        // Since existing save was invalid JSON, app shows franchise select with error notice or option to start new
        // Navigate through setup to preview
        await tester.tap(find.byKey(const ValueKey('open-career-preview')));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('career-team-option-team-1')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('next-situation-button')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('situation-card-playIn')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('generate-career-preview-button')),
        );
        await tester.pumpAndSettle();

        // Drag to reveal Start GM Career button
        await tester.drag(
          find.byKey(const ValueKey('career-preview-scroll')),
          const Offset(0, -1500),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('start-career-button')));
        await tester.pumpAndSettle();

        // Overwrite confirmation dialog is presented
        expect(find.text('Replace Existing Career?'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('cancel-overwrite-career-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('confirm-overwrite-career-button')),
          findsOneWidget,
        );

        // Tap cancel
        await tester.tap(
          find.byKey(const ValueKey('cancel-overwrite-career-button')),
        );
        await tester.pumpAndSettle();

        // Still on preview screen, previous save untouched
        expect(find.text('GM Career Setup: Preview'), findsOneWidget);
        expect(await careerStorage.read(), equals(existingCareerJson));

        // Tap Start GM Career again and confirm overwrite
        await tester.tap(find.byKey(const ValueKey('start-career-button')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('confirm-overwrite-career-button')),
        );
        await tester.pumpAndSettle();

        // Replaced and entered offseason overview
        expect(find.text('AUR Offseason'), findsOneWidget);
        expect(find.text('Starting Situation:'), findsOneWidget);
        expect(find.text('Play-In Contender'), findsOneWidget);
        expect(find.text('#8'), findsNothing); // PlayIn pick is #12
        expect(find.text('#12'), findsOneWidget);
      },
    );
  });
}
