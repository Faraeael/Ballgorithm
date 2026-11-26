import 'dart:io';

import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/career/career_shell_scaffold.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/season/season_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

class _HasSaveFaultCareerStorage extends InMemoryGmCareerStorage {
  bool throwOnHasSave = false;
  int writeAttempts = 0;

  @override
  Future<bool> hasSave({String slot = 'default'}) async {
    if (throwOnHasSave) {
      throw const GmCareerStorageException(
        'File system error checking career save: Permission denied',
        FileSystemException('Permission denied'),
      );
    }
    return super.hasSave(slot: slot);
  }

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    writeAttempts++;
    return super.write(data, slot: slot);
  }
}

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

        // Career Shell + Home Screen is now active (T01A/T01B)
        expect(find.byType(CareerShellScaffold), findsOneWidget);
        expect(find.text('AURORA COMETS'), findsWidgets);
        expect(find.textContaining('Opening Offseason'), findsWidgets);

        // Verify Market tab exposes offseason modules
        await tester.tap(find.byKey(const ValueKey('nav-tab-market')));
        await tester.pumpAndSettle();
        expect(find.text('Rookie Draft'), findsOneWidget);
        // T04 added Trade Center above it; the lazy list must scroll first.
        await tester.scrollUntilVisible(
          find.text('Free Agency Pool'),
          200,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('career-market-tab')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('Free Agency Pool'), findsOneWidget);

        // Verify Career tab exposes starting situation and finance/exit actions
        await tester.tap(find.byKey(const ValueKey('nav-tab-career')));
        await tester.pumpAndSettle();
        final careerScroll = find
            .descendant(
              of: find.byKey(const ValueKey('career-career-tab')),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.text('Tanking / Rebuilding'),
          200,
          scrollable: careerScroll,
        );
        expect(find.text('Tanking / Rebuilding'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('career-tab-main-menu-button')),
          200,
          scrollable: careerScroll,
        );
        expect(
          find.byKey(const ValueKey('career-tab-main-menu-button')),
          findsOneWidget,
        );

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

        // App reopens directly into the restored Career Shell!
        expect(find.byType(CareerShellScaffold), findsOneWidget);
        expect(find.textContaining('Opening Offseason'), findsWidgets);
        expect(find.text('AURORA COMETS'), findsWidgets);

        // 3. Exit to Main Menu via Career tab
        await tester.tap(find.byKey(const ValueKey('nav-tab-career')));
        await tester.pumpAndSettle();
        final careerScroll2 = find
            .descendant(
              of: find.byKey(const ValueKey('career-career-tab')),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('career-tab-main-menu-button')),
          200,
          scrollable: careerScroll2,
        );
        expect(
          find.byKey(const ValueKey('career-tab-main-menu-button')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('career-tab-main-menu-button')),
        );
        await tester.pumpAndSettle();

        // On MainMenuScreen, Continue GM Career is available
        expect(
          find.byKey(const ValueKey('continue-gm-career-button')),
          findsOneWidget,
        );
        expect(find.textContaining('Aurora Comets'), findsOneWidget);

        // Tap Continue GM Career
        await tester.tap(
          find.byKey(const ValueKey('continue-gm-career-button')),
        );
        await tester.pumpAndSettle();

        // Returned to Career Shell
        expect(find.byType(CareerShellScaffold), findsOneWidget);
        expect(find.text('AURORA COMETS'), findsWidgets);
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
          find.byKey(const ValueKey('confirm-new-career-replace')),
        );
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

        // Replaced and entered Career Shell
        expect(find.byType(CareerShellScaffold), findsOneWidget);
        expect(find.text('AURORA COMETS'), findsWidgets);
        await tester.tap(find.byKey(const ValueKey('nav-tab-career')));
        await tester.pumpAndSettle();
        final careerScroll3 = find
            .descendant(
              of: find.byKey(const ValueKey('career-career-tab')),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.text('Play-In Contender'),
          200,
          scrollable: careerScroll3,
        );
        expect(find.text('Play-In Contender'), findsOneWidget);
      },
    );

    testWidgets(
      'FIX2: FranchiseSelectScreen surfaces error and CareerSetupReviewScreen refuses to write when hasSave fails',
      (tester) async {
        _useSmallViewport(tester);

        final existingSetup = const CareerSetupService().generate(
          const CareerSetupRequest(
            selectedTeamId: TeamId('team-1'),
            selectedSituation: FranchiseSituation.tanking,
            seed: 20261028,
          ),
        );
        final existingJson = GmCareerCodec.encode(
          GmCareer.fromSetupResult(existingSetup, id: 'existing-fix2'),
        );

        final seasonStorage = InMemorySeasonStorage();
        final careerStorage = _HasSaveFaultCareerStorage();
        await careerStorage.write(existingJson);
        careerStorage.writeAttempts = 0;
        careerStorage.throwOnHasSave = true;
        careerStorage.shouldThrowOnRead = true;

        // 1. Launch app -> FranchiseSelectScreen._checkCareerSave catches hasSave error
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

        expect(
          find.byKey(const ValueKey('main-menu-storage-error')),
          findsOneWidget,
        );

        // 2. Attempt New GM Career when hasSave throws: MainMenu refuses to
        // overwrite or enter setup and writes nothing.
        await tester.tap(find.byKey(const ValueKey('open-career-preview')));
        await tester.pumpAndSettle();

        expect(find.text('Confirm GM Career Creation'), findsNothing);
        expect(find.text('Replace Existing Career?'), findsNothing);
        expect(
          find.byKey(const ValueKey('main-menu-storage-error')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Cannot verify existing career storage safely:'),
          findsOneWidget,
        );
        expect(careerStorage.writeAttempts, 0);

        // Existing save on disk remains completely untouched
        careerStorage.throwOnHasSave = false;
        careerStorage.shouldThrowOnRead = false;
        expect(await careerStorage.read(), equals(existingJson));
      },
    );
  });
}
