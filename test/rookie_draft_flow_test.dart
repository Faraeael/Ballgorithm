import 'dart:convert';

import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/draft_board_screen.dart';
import 'package:basketball_manager/features/career/offseason_overview_screen.dart';
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
  const careerSetupService = CareerSetupService();

  setUpAll(() {
    league = const LeagueGenerator().generate(_config);
  });

  group('M008-T05: Rookie Draft Board UI & Persistence Flow', () {
    testWidgets(
      '14. Draft Board functions at 360x640: unlocks from offseason overview, displays 60 picks, filters prospects without overflow',
      (tester) async {
        _useSmallViewport(tester);

        final setupResult = careerSetupService.generate(
          const CareerSetupRequest(
            selectedTeamId: TeamId('team-1'),
            selectedSituation: FranchiseSituation.tanking,
            seed: 20261028,
          ),
        );
        final career = GmCareer.fromSetupResult(setupResult);

        await tester.pumpWidget(
          MaterialApp(home: GmOffseasonOverviewScreen(career: career)),
        );
        // 1. Offseason overview shows draft entitlement card and unlocked module
        expect(
          find.byKey(const ValueKey('card-draft-entitlement')),
          findsOneWidget,
        );

        // Scroll down until Rookie Draft module is visible
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('module-rookie-draft')),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('module-rookie-draft')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('btn-open-draft-board')),
          findsOneWidget,
        );
        // 2. Open Draft Board
        await tester.tap(find.byKey(const ValueKey('btn-open-draft-board')));
        await tester.pumpAndSettle();

        expect(find.byType(GmDraftBoardScreen), findsOneWidget);
        expect(find.text('Rookie Draft Board'), findsOneWidget);

        // 3. Draft Order Tab: All 60 picks available
        expect(find.byKey(const ValueKey('draft-order-view')), findsOneWidget);
        expect(find.text('All (60)'), findsOneWidget);
        expect(find.text('Round 1 (30)'), findsOneWidget);
        expect(find.text('Round 2 (30)'), findsOneWidget);

        // User guaranteed pick #1 is highlighted
        expect(find.byKey(const ValueKey('draft-pick-1')), findsOneWidget);
        expect(find.text('YOUR PICK'), findsWidgets);

        // Filter to Round 2
        await tester.tap(find.text('Round 2 (30)'));
        await tester.pumpAndSettle();

        // Round 2 pick 31 belongs to user
        expect(find.byKey(const ValueKey('draft-pick-31')), findsOneWidget);

        // 4. Switch to Prospects Tab
        await tester.tap(find.text('Prospects (90)'));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('prospect-view')), findsOneWidget);
        expect(find.text('Showing 90 of 90 Prospects'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('prospect-search-field')),
          findsOneWidget,
        );

        // Position filters exist
        expect(
          find.byKey(const ValueKey('prospect-filter-all')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('prospect-filter-pg')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('prospect-filter-c')), findsOneWidget);

        // Filter by PG position
        await tester.tap(find.byKey(const ValueKey('prospect-filter-pg')));
        await tester.pumpAndSettle();
        expect(find.text('Showing 18 of 90 Prospects'), findsOneWidget);

        // Reset to ALL
        await tester.tap(find.byKey(const ValueKey('prospect-filter-all')));
        await tester.pumpAndSettle();
        expect(find.text('Showing 90 of 90 Prospects'), findsOneWidget);

        // Top ranked prospect card
        final firstProspect = career.draftClass.rankedFirst;
        expect(
          find.byKey(ValueKey('prospect-card-${firstProspect.projectedRank}')),
          findsOneWidget,
        );

        // 5. Open prospect detail sheet
        await tester.tap(
          find.byKey(ValueKey('prospect-card-${firstProspect.projectedRank}')),
        );
        await tester.pumpAndSettle();

        // Observed abilities are displayed
        expect(find.text('Observed Abilities'), findsOneWidget);
        expect(find.text('Inside Scoring'), findsOneWidget);
        expect(find.text('Three-Point'), findsOneWidget);
        expect(find.text('Public Scouting Evaluation'), findsOneWidget);
        // True ceiling and development trajectory remain hidden
        expect(find.text(firstProspect.trajectory.displayName), findsNothing);
        expect(find.textContaining('True Potential'), findsNothing);

        // Close bottom sheet
        await tester.tapAt(const Offset(180, 50));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      '12 & 13. Reopening career preserves prospects without regeneration & leaves M007 save untouched',
      (tester) async {
        _useSmallViewport(tester);

        final seasonStorage = InMemorySeasonStorage();
        final careerStorage = InMemoryGmCareerStorage();
        // 1. Launch app and create career
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

        await tester.tap(find.byKey(const ValueKey('open-career-preview')));
        await tester.pumpAndSettle();

        // Select team-1
        await tester.tap(
          find.byKey(const ValueKey('career-team-option-team-1')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('next-situation-button')));
        await tester.pumpAndSettle();

        // Select Tanking
        await tester.tap(find.byKey(const ValueKey('situation-card-tanking')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('generate-career-preview-button')),
        );
        await tester.pumpAndSettle();

        // Drag to reveal start button
        await tester.drag(
          find.byKey(const ValueKey('career-preview-scroll')),
          const Offset(0, -1500),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('start-career-button')));
        await tester.pumpAndSettle();

        // Confirm career creation dialog
        expect(
          find.byKey(const ValueKey('confirm-start-career-button')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('confirm-start-career-button')),
        );
        await tester.pumpAndSettle();

        // Offseason overview is now open
        expect(find.byType(GmOffseasonOverviewScreen), findsOneWidget);

        // Inspect saved career data
        final savedRaw = await careerStorage.read();
        expect(savedRaw, isNotNull);
        final initialSavedCareer = GmCareerCodec.decode(savedRaw!);
        final initialTopProspect = initialSavedCareer.draftClass.rankedFirst;

        // Now write an M007 save sentinel into seasonStorage to verify isolation
        await seasonStorage.write('{"m007-sentinel": "untouched-data"}');
        expect(await seasonStorage.read(), isNotNull);

        // 2. Restart app
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

        // Reopens directly into Offseason Overview
        expect(find.byType(GmOffseasonOverviewScreen), findsOneWidget);
        // Scroll down until Rookie Draft module is visible
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('btn-open-draft-board')),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('btn-open-draft-board')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('btn-open-draft-board')));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Prospects (90)'));
        await tester.pumpAndSettle();

        // Prospect class was NOT regenerated
        expect(find.text(initialTopProspect.fullName), findsOneWidget);

        // 13. Verify M007 save was never touched
        final seasonRaw = await seasonStorage.read();
        expect(seasonRaw, equals('{"m007-sentinel": "untouched-data"}'));
      },
    );

    test(
      '11. Storage-level migration from schema v1 to v2 preserves career state and synthesizes draft class',
      () async {
        final careerStorage = InMemoryGmCareerStorage();

        final setupResult = careerSetupService.generate(
          const CareerSetupRequest(
            selectedTeamId: TeamId('team-3'),
            selectedSituation: FranchiseSituation.playoff,
            seed: 20261028,
          ),
        );
        final careerV2 = GmCareer.fromSetupResult(setupResult);
        final rawV2Map =
            jsonDecode(GmCareerCodec.encode(careerV2)) as Map<String, dynamic>;

        // Strip v2 draft fields to produce real v1 payload
        final rawV1Map = Map<String, dynamic>.from(rawV2Map)
          ..['schemaVersion'] = 1
          ..remove('draftOrder')
          ..remove('draftClass');

        await careerStorage.write(jsonEncode(rawV1Map));

        // Read through storage
        final loadedJson = await careerStorage.read();
        expect(loadedJson, isNotNull);

        final migrated = GmCareerCodec.decode(loadedJson!);
        expect(migrated.schemaVersion, GmCareer.currentSchemaVersion);
        expect(migrated.userFranchiseId, const TeamId('team-3'));
        expect(migrated.originalSituation, FranchiseSituation.playoff);
        expect(migrated.userOpeningDraftPick, 20);
        expect(migrated.draftOrder.totalPicks, 60);
        expect(migrated.draftClass.length, 90);
        expect(
          migrated.draftOrder.pickAt(20).currentOwnerTeamId,
          const TeamId('team-3'),
        );
      },
    );
  });
}
