import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_shell_scaffold.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/widgets/hardwood_components.dart';
import 'package:basketball_manager/theme/hardwood_command_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

import '../integration_test/support/d3c_fixture_helper.dart';

class _FaultingCareerStorage extends InMemoryGmCareerStorage {
  _FaultingCareerStorage(String initialJson) : super({'default': initialJson});

  int writesBeforeFail = 999;
  int writeCount = 0;

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    writeCount++;
    if (writeCount > writesBeforeFail) {
      throw StateError('Simulated disk write failure at write #$writeCount');
    }
    await super.write(data, slot: slot);
  }
}

GmCareer? _cachedRound1Career;
GmCareer? _cachedRound80Career;

GmCareer _buildReadyRegularSeasonCareer({int startingRound = 1}) {
  if (startingRound == 1 && _cachedRound1Career != null) {
    return _cachedRound1Career!;
  }
  if (startingRound == 80 && _cachedRound80Career != null) {
    return _cachedRound80Career!;
  }
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.contender,
      seed: 20261028,
    ),
  );
  var career = GmCareer.fromSetupResult(setup, id: 't01c-career');
  career = const DraftExecutionService().startDraft(career);
  while (!career.draftExecutionState.isCompleted) {
    final state = career.draftExecutionState;
    if (state.isHumanTurn(
      order: career.draftOrder,
      userTeamId: career.userFranchiseId,
    )) {
      final pick = career.draftClass.prospects.firstWhere(
        (p) => !state.isProspectSelected(p.id),
      );
      career = const DraftExecutionService().makeHumanSelection(
        career: career,
        prospectId: pick.id,
      );
    } else {
      career = const DraftExecutionService().executeAiSelection(career);
    }
  }
  const rookieAi = RookieAiSigningService();
  career = rookieAi.initialize(career);
  while (rookieAi.pendingRights(career).isNotEmpty) {
    career = rookieAi.applyNextDecision(career);
  }
  const signingService = RookieSigningService();
  for (final r in career.unsignedDraftRights) {
    if (r.owningTeamId == career.userFranchiseId) {
      career = signingService.signDraftedRookie(
        career: career,
        teamId: career.userFranchiseId,
        prospectId: r.prospectId,
        category: RosterCategory.standard,
        durationYears: 2,
      );
    }
  }
  const market = FreeAgentMarketService();
  for (var round = 0; round < 2; round++) {
    career = market.startRound(career);
    career = market.prepareResolution(career);
    while (career.freeAgentMarket.isResolvable) {
      career = market.resolveNext(career);
    }
  }
  const clearance = OffseasonClearanceService();
  career = clearance.start(career);
  career = clearance.prepare(career);
  while (career.offseasonClearance.isResolvable) {
    career = clearance.resolveNext(career);
  }
  const hardship = HardshipSettlementService();
  career = hardship.prepare(career, humanParticipationConfirmed: true);
  while (career.hardshipSettlement.isResolvable) {
    career = hardship.resolveNext(career);
  }
  career = clearance.markCleared(career);
  career = const RegularSeasonEntryService().start(career);
  career = const RegularSeasonScheduleService().generate(career);
  const roundService = RegularSeasonRoundService();
  for (var r = 1; r < startingRound; r++) {
    career = roundService.simulateNextRound(career, expectedRoundNumber: r);
  }
  if (startingRound == 1) _cachedRound1Career = career;
  if (startingRound == 80) _cachedRound80Career = career;
  return career;
}

GmCareer _buildCareerWithHistory() {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.contender,
      seed: 20261028,
    ),
  );
  final base = GmCareer.fromSetupResult(setup, id: 't01c-history-career');
  final completed = completeSeasonFromSetup(base);
  return const SeasonRolloverService()
      .prepareArchiveAndRollover(current: completed)
      .rolloverResult
      .nextCareer;
}

Widget _wrapWithTheme(Widget child) {
  return MaterialApp(theme: buildHardwoodCommandTheme(), home: child);
}

void main() {
  group('M009-UX-T01C: Batch Simulation, Career History & Visual Refinements', () {
    test(
      '10-round batch produces identical career state to 10 sequential single-round commands',
      // Includes building the real-season fixture (~1.5 min alone; longer under parallel load).
      timeout: const Timeout(Duration(minutes: 6)),
      () async {
        final startingCareer = _buildReadyRegularSeasonCareer();
        final initialJson = GmCareerCodec.encode(startingCareer);

        // Sequential 10 rounds
        final seqStorage = InMemoryGmCareerStorage({'default': initialJson});
        final seqController = GmCareerController(storage: seqStorage);
        await seqController.loadCareer();
        for (var r = 1; r <= 10; r++) {
          await seqController.simulateNextRegularSeasonRound(
            expectedRoundNumber: r,
            confirmed: true,
          );
        }

        // Batch 10 rounds
        final batchStorage = InMemoryGmCareerStorage({'default': initialJson});
        final batchController = GmCareerController(storage: batchStorage);
        await batchController.loadCareer();
        await batchController.simulateRegularSeasonBatch(
          expectedStartRound: 1,
          roundCount: 10,
          confirmed: true,
        );

        expect(batchController.career!.regularSeasonState!.completedRounds, 10);
        expect(await batchStorage.read(), equals(await seqStorage.read()));
        seqController.dispose();
        batchController.dispose();
      },
    );

    test(
      'Remaining-season batch stops cleanly at Round 82 and never auto-enters Play-In',
      timeout: const Timeout(Duration(minutes: 6)),
      () async {
        final nearEnd = _buildReadyRegularSeasonCareer(startingRound: 80);
        final storage = InMemoryGmCareerStorage({
          'default': GmCareerCodec.encode(nearEnd),
        });
        final controller = GmCareerController(storage: storage);
        await controller.loadCareer();

        await controller.simulateRegularSeasonBatch(
          expectedStartRound: 80,
          roundCount: 20, // Exceeds 82 intentionally; must clamp to 82.
          confirmed: true,
        );

        expect(controller.career!.phase, CareerPhase.regularSeason);
        expect(controller.career!.playInState, isNull);
        expect(controller.career!.regularSeasonState!.completedRounds, 82);
        expect(
          controller.career!.regularSeasonState!.nextUnfinishedRoundNumber,
          isNull,
        );
        controller.dispose();
      },
    );

    test(
      'Cancellation between rounds preserves completed saved rounds and save failure stops batch safely',
      () async {
        final start = _buildReadyRegularSeasonCareer();
        final cancelStorage = InMemoryGmCareerStorage({
          'default': GmCareerCodec.encode(start),
        });
        final cancelController = GmCareerController(storage: cancelStorage);
        await cancelController.loadCareer();

        var cancelled = false;
        cancelController.addListener(() {
          final p = cancelController.batchProgress;
          if (!cancelled && p != null && p.roundsCompleted >= 2) {
            cancelled = true;
            cancelController.requestCancelBatchSimulation();
          }
        });

        await cancelController.simulateRegularSeasonBatch(
          expectedStartRound: 1,
          roundCount: 10,
          confirmed: true,
        );
        final savedAfterCancel =
            cancelController.career!.regularSeasonState!.completedRounds;
        expect(savedAfterCancel, greaterThanOrEqualTo(2));
        expect(savedAfterCancel, lessThan(10));
        expect(
          GmCareerCodec.decode(
            (await cancelStorage.read())!,
          ).regularSeasonState!.completedRounds,
          savedAfterCancel,
        );
        cancelController.dispose();

        // Save failure on 3rd write stops batch immediately and requires reload
        final failStorage = _FaultingCareerStorage(GmCareerCodec.encode(start))
          ..writesBeforeFail = 2;
        final failController = GmCareerController(storage: failStorage);
        await failController.loadCareer();

        await expectLater(
          failController.simulateRegularSeasonBatch(
            expectedStartRound: 1,
            roundCount: 5,
            confirmed: true,
          ),
          throwsStateError,
        );
        expect(failController.draftRecoveryRequired, isTrue);
        expect(failController.errorMessage, isNotNull);
        expect(failController.career!.regularSeasonState!.completedRounds, 2);

        // Reload reconciles cleanly and resumes from Round 3 without duplicates
        await failController.loadCareer();
        expect(failController.draftRecoveryRequired, isFalse);
        expect(
          failController.career!.regularSeasonState!.nextUnfinishedRoundNumber,
          3,
        );
        failController.dispose();
      },
    );

    testWidgets(
      'Home simulation options sheet and batch progress UI render cleanly',
      timeout: const Timeout(Duration(minutes: 6)),
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final career = _buildReadyRegularSeasonCareer(startingRound: 1);
        final storage = InMemoryGmCareerStorage({
          'default': GmCareerCodec.encode(career),
        });
        final controller = GmCareerController(storage: storage);
        await controller.loadCareer();

        await tester.pumpWidget(
          _wrapWithTheme(
            CareerShellScaffold(
              controller: controller,
              onReturnToMainMenu: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('home-sim-options-button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('sim-options-sheet')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('sim-option-next-round')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('sim-option-10-rounds')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('sim-option-remaining')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('sim-option-10-rounds')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('confirm-simulate-batch')),
          findsOneWidget,
        );

        // Cancel dialog and verify live batch progress UI via controller.
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        await tester.runAsync(() async {
          final future = controller.simulateRegularSeasonBatch(
            expectedStartRound: 1,
            roundCount: 2,
            confirmed: true,
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));
          controller.requestCancelBatchSimulation();
          await future;
        });
        await tester.pumpAndSettle();

        expect(
          controller.career!.regularSeasonState!.completedRounds,
          greaterThanOrEqualTo(1),
        );
        expect(tester.takeException(), isNull);
        controller.dispose();
      },
    );

    testWidgets(
      'Career History shows empty trophy cabinet for new career, real championships & graceful fallback for compact archive',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        // 1. Empty trophy cabinet
        final emptyCareer = _buildReadyRegularSeasonCareer();
        final emptyController = GmCareerController(
          storage: InMemoryGmCareerStorage({
            'default': GmCareerCodec.encode(emptyCareer),
          }),
        );
        await emptyController.loadCareer();

        await tester.pumpWidget(
          _wrapWithTheme(
            CareerShellScaffold(
              controller: emptyController,
              onReturnToMainMenu: () {},
              initialTabIndex: 4,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('career-empty-trophy-cabinet')),
          findsOneWidget,
        );
        expect(find.text('0 Completed'), findsOneWidget);

        // 2. Populated championship history with graceful archive fallback
        final historyCareer = _buildCareerWithHistory();
        final historyController = GmCareerController(
          storage: InMemoryGmCareerStorage({
            'default': GmCareerCodec.encode(historyCareer),
          }),
        );
        await historyController.loadCareer();

        await tester.pumpWidget(
          _wrapWithTheme(
            CareerShellScaffold(
              controller: historyController,
              onReturnToMainMenu: () {},
              initialTabIndex: 4,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('career-legacy-card')),
          findsOneWidget,
        );
        expect(find.text('1 Completed'), findsOneWidget);
        expect(find.textContaining('Season 1 •'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('career-history-season-1')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('career-season-detail-1')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Compact season summary loaded'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        emptyController.dispose();
        historyController.dispose();
      },
    );

    testWidgets(
      'Team Roster renders player monogram badges, rating tier badges, and position filter counts',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final career = _buildReadyRegularSeasonCareer();
        final controller = GmCareerController(
          storage: InMemoryGmCareerStorage({
            'default': GmCareerCodec.encode(career),
          }),
        );
        await controller.loadCareer();

        await tester.pumpWidget(
          _wrapWithTheme(
            CareerShellScaffold(
              controller: controller,
              onReturnToMainMenu: () {},
              initialTabIndex: 1,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(PlayerMonogramBadge), findsWidgets);
        expect(find.byType(OverallRatingBadge), findsWidgets);
        expect(find.textContaining('ALL ('), findsOneWidget);
        expect(tester.takeException(), isNull);
        controller.dispose();
      },
    );

    testWidgets(
      'Enter Playoffs from pushed Play-In screen keeps failure recovery and returns to shell on success',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        var career = _buildReadyRegularSeasonCareer(startingRound: 80);
        const roundService = RegularSeasonRoundService();
        for (var r = 80; r <= 82; r++) {
          career = roundService.simulateNextRound(
            career,
            expectedRoundNumber: r,
          );
        }
        career = const PlayInEntryService().enter(career);
        final seed = career.regularSeasonState!.scheduleSeed;
        for (var g = 1; g <= 3; g++) {
          final fixture = career.playInState!.fixture(
            gameNumber: g,
            scheduleSeed: seed,
          )!;
          career = const PlayInGameService().simulateGame(
            career,
            expectedGameId: fixture.id,
          );
        }
        final savedPlayIn = GmCareerCodec.encode(career);
        final storage = _FaultingCareerStorage(savedPlayIn)
          ..writesBeforeFail = 0;
        final controller = GmCareerController(storage: storage);
        addTearDown(controller.dispose);
        await controller.loadCareer();

        await tester.pumpWidget(
          _wrapWithTheme(
            CareerShellScaffold(
              controller: controller,
              onReturnToMainMenu: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('View Play-In Results'));
        await tester.pumpAndSettle();
        final enter = find.byKey(const ValueKey('btn-enter-playoffs'));
        await tester.scrollUntilVisible(
          enter,
          220,
          scrollable: find.byType(Scrollable).last,
        );

        // Failed save: stays on Play-In with error/recovery, no navigation.
        await tester.tap(enter);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(controller.career!.phase, CareerPhase.playIn);
        expect(await storage.read(), savedPlayIn);
        expect(find.text('Play-In Tournament'), findsOneWidget);
        expect(
          controller.errorMessage != null || controller.draftRecoveryRequired,
          isTrue,
        );

        storage.writesBeforeFail = 1 << 30;
        if (controller.draftRecoveryRequired) {
          final reload = find.byKey(const ValueKey('btn-play-in-reload'));
          await tester.scrollUntilVisible(
            reload,
            220,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.tap(reload);
          await tester.pumpAndSettle();
        }

        await tester.scrollUntilVisible(
          enter,
          220,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(enter);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();

        expect(controller.career!.phase, CareerPhase.playoffs);
        expect(tester.takeException(), isNull);
        expect(find.text('Play-In Tournament'), findsNothing);
        expect(find.byType(CareerShellScaffold), findsOneWidget);
      },
    );
  });
}
