import 'dart:async';

import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_home_screen.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/playoff_tournament_screen.dart';
import 'package:basketball_manager/features/career/rollover_isolate_workers.dart';
import 'package:basketball_manager/features/season/season_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

import '../integration_test/support/d3c_fixture_helper.dart';

class _GatedArchiveStorage extends InMemoryGmCareerStorage {
  Completer<void>? archiveGate;
  Completer<void>? activeGate;
  bool failArchive = false;
  bool failActive = false;
  int archiveWrites = 0;
  int activeWrites = 0;

  @override
  Future<void> writeArchive({
    required int seasonYear,
    required String archiveJson,
    required String expectedDigest,
    String slot = 'default',
  }) async {
    if (archiveGate != null) {
      await archiveGate!.future;
    }
    if (failArchive) {
      failArchive = false;
      throw const GmCareerStorageException('Simulated archive write failure');
    }
    archiveWrites++;
    await super.writeArchive(
      seasonYear: seasonYear,
      archiveJson: archiveJson,
      expectedDigest: expectedDigest,
      slot: slot,
    );
  }

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    if (activeGate != null) {
      await activeGate!.future;
    }
    if (failActive) {
      failActive = false;
      throw const GmCareerStorageException('Simulated active save failure');
    }
    activeWrites++;
    await super.write(data, slot: slot);
  }
}

void main() {
  late GmCareer y1Completed;
  late String y1CompletedJson;
  late RolloverPrepareOutput y1Prepared;

  setUpAll(() {
    final setup = const CareerSetupService().generate(
      const CareerSetupRequest(
        selectedTeamId: TeamId('team-1'),
        selectedSituation: FranchiseSituation.tanking,
        seed: 20261028,
      ),
    );
    final y1Initial = GmCareer.fromSetupResult(setup, id: 't05c-d3c-t04a-ui');
    y1Completed = completeSeasonFromSetup(y1Initial);
    y1CompletedJson = GmCareerCodec.encode(y1Completed);
    y1Prepared = prepareSeasonRolloverWorker(
      RolloverPrepareRequest(y1Completed),
    );
  });

  Widget buildApp({
    required GmCareerStorage storage,
    required GmCareerController controller,
  }) => BasketballManagerApp(
    league: y1Completed.league,
    storage: InMemorySeasonStorage(),
    careerStorage: storage,
    careerController: controller,
    seasonMode: true,
  );

  testWidgets(
    'Progress card updates only at real operation boundaries on 360px viewport without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final workerGate = Completer<void>();
      final archiveGate = Completer<void>();
      final activeGate = Completer<void>();
      var workerCalls = 0;

      final storage = _GatedArchiveStorage();
      await storage.write(y1CompletedJson);
      storage
        ..archiveGate = archiveGate
        ..activeGate = activeGate;

      final controller = GmCareerController(
        storage: storage,
        prepareRolloverWorker: (_) async {
          workerCalls++;
          await workerGate.future;
          return y1Prepared;
        },
      );
      await controller.loadCareer();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        buildApp(storage: storage, controller: controller),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inspect Playoff Bracket'));
      await tester.pumpAndSettle();

      // Champion displayed & Continue button eligible.
      expect(find.text('Season 1'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('continue-to-next-season')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('continue-to-next-season')));
      await tester.pumpAndSettle();

      // Confirmation dialog visible; Cancel leaves state unchanged.
      expect(find.text('Start Next Season?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cancel-next-season')));
      await tester.pumpAndSettle();
      expect(workerCalls, 0);
      expect(controller.seasonTransitionStage, isNull);

      // Confirm starts exactly one rollover.
      await tester.tap(find.byKey(const ValueKey('continue-to-next-season')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-next-season')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      // Stage 1: Preparing next season
      expect(controller.seasonTransitionStage, SeasonTransitionStage.preparing);
      expect(
        find.byKey(const ValueKey('season-transition-progress-card')),
        findsOneWidget,
      );
      expect(find.text('Season 1 → Season 2'), findsOneWidget);
      expect(find.text('Preparing next season'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('continue-to-next-season')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('continue-to-next-season')),
            )
            .onPressed,
        isNull,
      );
      // Duplicate tap prevented
      await tester.tap(
        find.byKey(const ValueKey('continue-to-next-season')),
        warnIfMissed: false,
      );
      expect(workerCalls, 1);
      // Bring progress card back into the built viewport for later stages.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('season-transition-progress-card')),
        -300,
        scrollable: find.byType(Scrollable).first,
      );

      // Release worker -> Stage 2: Verifying and archiving completed season
      workerGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(controller.seasonTransitionStage, SeasonTransitionStage.archiving);
      expect(
        find.text('Verifying and archiving completed season'),
        findsOneWidget,
      );

      // Release archive -> Stage 3: Saving your next season
      archiveGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(
        controller.seasonTransitionStage,
        SeasonTransitionStage.savingNextSeason,
      );
      expect(find.text('Saving your next season'), findsOneWidget);

      // Release active write -> Navigates cleanly to Year 2 offseason
      activeGate.complete();
      await tester.pumpAndSettle();
      expect(controller.seasonTransitionStage, isNull);
      expect(controller.career?.currentYear, 2);
      expect(controller.career?.phase, CareerPhase.openingOffseason);
      expect(find.byType(CareerHomeScreen), findsOneWidget);
      expect(find.byType(PlayoffTournamentScreen), findsNothing);
      expect(find.text('Season 2 • Opening Offseason'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Pre-write worker failure distinguishes from recovery-required failure and unmounting mid-transition causes no setState-after-dispose',
    (tester) async {
      final storage = _GatedArchiveStorage();
      await storage.write(y1CompletedJson);

      var failWorker = true;
      final workerGate = Completer<void>();
      final controller = GmCareerController(
        storage: storage,
        prepareRolloverWorker: (_) async {
          if (failWorker) {
            throw StateError('Simulated worker failure');
          }
          await workerGate.future;
          return y1Prepared;
        },
      );
      await controller.loadCareer();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        buildApp(storage: storage, controller: controller),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inspect Playoff Bracket'));
      await tester.pumpAndSettle();

      // 1. Pre-write failure -> no recovery required, clear non-mutation feedback
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('continue-to-next-season')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('continue-to-next-season')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-next-season')));
      await tester.pumpAndSettle();

      expect(controller.draftRecoveryRequired, isFalse);
      expect(controller.seasonTransitionStage, isNull);
      expect(find.text('Season Transition Interrupted'), findsOneWidget);
      expect(
        find.text(
          'No save files were modified. You can review the error and try again.',
        ),
        findsOneWidget,
      );

      // 2. Unmount PlayoffTournamentScreen while transition is in flight -> no setState after dispose
      failWorker = false;
      await tester.ensureVisible(
        find.byKey(const ValueKey('continue-to-next-season')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('continue-to-next-season')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-next-season')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      // Replace widget tree while rollover is awaiting workerGate
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      workerGate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  group('T04A-FIX1: persistArchivedSeasonTransition stage cleanup', () {
    test(
      'A. Custom transition progresses stages and clears seasonTransitionStage on success',
      () async {
        final storage = _GatedArchiveStorage();
        await storage.write(y1CompletedJson);
        final controller = GmCareerController(storage: storage);
        addTearDown(controller.dispose);
        await controller.loadCareer();

        final observedStages = <SeasonTransitionStage?>[];
        controller.addListener(() {
          observedStages.add(controller.seasonTransitionStage);
        });

        await controller.persistArchivedSeasonTransition(
          buildNextCareer: (_, _) => y1Prepared.nextCareer,
          confirmed: true,
        );

        expect(
          observedStages,
          containsAllInOrder([
            SeasonTransitionStage.archiving,
            SeasonTransitionStage.savingNextSeason,
            null,
          ]),
        );
        expect(controller.seasonTransitionStage, isNull);
        expect(controller.isLoading, isFalse);
        expect(controller.draftRecoveryRequired, isFalse);
        expect(controller.career?.currentYear, 2);
        expect(controller.career?.seasonHistory.length, 1);
        expect(await storage.hasArchive(seasonYear: 1), isTrue);
      },
    );

    test(
      'B. buildNextCareer throws before writes: stage == null, no writes, draftRecoveryRequired == false',
      () async {
        final storage = _GatedArchiveStorage();
        await storage.write(y1CompletedJson);
        final controller = GmCareerController(storage: storage);
        addTearDown(controller.dispose);
        await controller.loadCareer();

        final archBefore = storage.archiveWrites;
        final activeBefore = storage.activeWrites;

        await expectLater(
          controller.persistArchivedSeasonTransition(
            buildNextCareer: (_, _) =>
                throw StateError('Custom builder failure'),
            confirmed: true,
          ),
          throwsStateError,
        );

        expect(controller.seasonTransitionStage, isNull);
        expect(controller.isLoading, isFalse);
        expect(controller.draftRecoveryRequired, isFalse);
        expect(storage.archiveWrites, archBefore);
        expect(storage.activeWrites, activeBefore);
        expect(controller.career?.currentYear, 1);
      },
    );

    test(
      'C. Archive write fails: error propagates, stage == null, recovery-required set, no Year 2 publication',
      () async {
        final storage = _GatedArchiveStorage();
        await storage.write(y1CompletedJson);
        final controller = GmCareerController(storage: storage);
        addTearDown(controller.dispose);
        await controller.loadCareer();

        storage.failArchive = true;
        await expectLater(
          controller.persistArchivedSeasonTransition(
            buildNextCareer: (_, _) => y1Prepared.nextCareer,
            confirmed: true,
          ),
          throwsA(isA<GmCareerStorageException>()),
        );

        expect(controller.seasonTransitionStage, isNull);
        expect(controller.isLoading, isFalse);
        expect(controller.draftRecoveryRequired, isTrue);
        expect(controller.career?.currentYear, 1);
        expect(await storage.hasArchive(seasonYear: 1), isFalse);
      },
    );

    test(
      'D-E. Active write fails then retry after valid recovery succeeds with clean stage',
      () async {
        final storage = _GatedArchiveStorage();
        await storage.write(y1CompletedJson);
        final controller = GmCareerController(storage: storage);
        addTearDown(controller.dispose);
        await controller.loadCareer();

        storage.failActive = true;
        await expectLater(
          controller.persistArchivedSeasonTransition(
            buildNextCareer: (_, _) => y1Prepared.nextCareer,
            confirmed: true,
          ),
          throwsA(isA<GmCareerStorageException>()),
        );

        expect(controller.seasonTransitionStage, isNull);
        expect(controller.isLoading, isFalse);
        expect(controller.draftRecoveryRequired, isTrue);
        expect(controller.career?.currentYear, 1);

        // E. Reload and retry succeeds once with clean stage.
        await controller.loadCareer();
        expect(controller.draftRecoveryRequired, isFalse);
        await controller.persistArchivedSeasonTransition(
          buildNextCareer: (_, _) => y1Prepared.nextCareer,
          confirmed: true,
        );
        expect(controller.seasonTransitionStage, isNull);
        expect(controller.isLoading, isFalse);
        expect(controller.career?.currentYear, 2);
        expect(controller.career?.seasonHistory.length, 1);
      },
    );
  });
}
