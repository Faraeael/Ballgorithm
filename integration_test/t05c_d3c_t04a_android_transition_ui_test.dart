import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/offseason_overview_screen.dart';
import 'package:basketball_manager/features/career/playoff_tournament_screen.dart';
import 'package:basketball_manager/features/season/season_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simulation_core/simulation_core.dart';

import 'support/d3c_fixture_helper.dart';

({GmCareer y2Completed, String y1ArchJson, String y1ArchDigest})
_buildYear2CompletedWithY1Archive(String careerId) {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: 20261028,
    ),
  );
  final y1Initial = GmCareer.fromSetupResult(setup, id: careerId);
  final y1Completed = completeSeasonFromSetup(y1Initial);
  final prep1 = const SeasonRolloverService().prepareArchiveAndRollover(
    current: y1Completed,
  );
  final y2Completed = completeSeasonFromSetup(prep1.rolloverResult.nextCareer);
  return (
    y2Completed: y2Completed,
    y1ArchJson: prep1.archiveJson,
    y1ArchDigest: prep1.archiveDigest,
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory testRootDir;
  late GmCareer y2Completed;
  late String y1ArchJson;
  late String y1ArchDigest;

  setUpAll(() async {
    final docsDir = await getApplicationDocumentsDirectory();
    testRootDir = Directory(
      '${docsDir.path}/d3c_t04a_ui_${DateTime.now().millisecondsSinceEpoch}',
    )..createSync(recursive: true);

    final built = await compute(
      _buildYear2CompletedWithY1Archive,
      'd3c-t04a-android-ui',
    );
    y2Completed = built.y2Completed;
    y1ArchJson = built.y1ArchJson;
    y1ArchDigest = built.y1ArchDigest;
  });

  tearDownAll(() async {
    try {
      if (testRootDir.existsSync()) {
        testRootDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  testWidgets(
    'D3C-T04A Real Android UI Season 2 -> Season 3 Transition & Persistence',
    (tester) async {
      final storage = FileGmCareerStorage(directoryPath: testRootDir.path);
      await storage.writeArchive(
        seasonYear: 1,
        archiveJson: y1ArchJson,
        expectedDigest: y1ArchDigest,
      );
      await storage.write(GmCareerCodec.encode(y2Completed));

      final controller = GmCareerController(storage: storage);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        BasketballManagerApp(
          league: y2Completed.league,
          storage: InMemorySeasonStorage(),
          careerStorage: storage,
          careerController: controller,
          seasonMode: true,
        ),
      );
      // Wait for initial loadCareer to render PlayoffTournamentScreen.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(PlayoffTournamentScreen).evaluate().isNotEmpty) {
          break;
        }
      }

      // 1. Playoff champion screen appears.
      expect(find.byType(PlayoffTournamentScreen), findsOneWidget);
      expect(find.text('Season 2'), findsOneWidget);
      final championId = y2Completed.playoffState!.champion!;
      final championName = y2Completed.league.teams
          .firstWhere((t) => t.id == championId)
          .name;
      expect(find.text(championName), findsWidgets);

      // 2. Open confirmation dialog & 3. Cancel leaves Year 2 unchanged.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('continue-to-next-season')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('continue-to-next-season')));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(find.text('Start Next Season?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('cancel-next-season')));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(controller.career?.currentYear, 2);
      expect(controller.career?.phase, CareerPhase.playoffs);

      // 4. Confirm starts actual rollover; measure heartbeat + frame timings.
      await tester.tap(find.byKey(const ValueKey('continue-to-next-season')));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      final heartbeatGapsMs = <int>[];
      final frameTotalUs = <int>[];
      var captureFrames = false;
      void onTimings(List<FrameTiming> timings) {
        if (!captureFrames) return;
        for (final t in timings) {
          frameTotalUs.add(t.totalSpan.inMicroseconds);
        }
      }

      SchedulerBinding.instance.addTimingsCallback(onTimings);
      var lastTickMs = 0;
      final hbSw = Stopwatch()..start();
      final timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        final now = hbSw.elapsedMilliseconds;
        heartbeatGapsMs.add(now - lastTickMs);
        lastTickMs = now;
      });

      var sawProgressCard = false;
      var duplicateBlocked = false;
      final transitionSw = Stopwatch()..start();
      try {
        captureFrames = true;
        await tester.tap(find.byKey(const ValueKey('confirm-next-season')));

        // 5-7. Pump frames without pumpAndSettle while indeterminate animation is active.
        for (var i = 0; i < 3000; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (!sawProgressCard &&
              find
                  .byKey(const ValueKey('season-transition-progress-card'))
                  .evaluate()
                  .isNotEmpty) {
            sawProgressCard = true;
            expect(find.text('Season 2 → Season 3'), findsOneWidget);
          }
          if (!duplicateBlocked &&
              find
                  .byKey(const ValueKey('continue-to-next-season'))
                  .evaluate()
                  .isNotEmpty) {
            final btn = tester.widget<FilledButton>(
              find.byKey(const ValueKey('continue-to-next-season')),
            );
            if (btn.onPressed == null) {
              duplicateBlocked = true;
            }
          }
          if (find.byType(GmOffseasonOverviewScreen).evaluate().isNotEmpty &&
              !controller.isLoading) {
            break;
          }
        }
        transitionSw.stop();
      } finally {
        captureFrames = false;
        timer.cancel();
        hbSw.stop();
        SchedulerBinding.instance.removeTimingsCallback(onTimings);
      }

      // 8. Year 3 offseason becomes visible.
      expect(sawProgressCard, isTrue);
      expect(duplicateBlocked, isTrue);
      expect(find.byType(GmOffseasonOverviewScreen), findsOneWidget);
      expect(find.byType(PlayoffTournamentScreen), findsNothing);
      expect(find.text('Year 3 • Opening Offseason'), findsOneWidget);

      // 9-10. Year 3 persisted + Year 1 & Year 2 archives cryptographically verified.
      final verifyStorage = FileGmCareerStorage(
        directoryPath: testRootDir.path,
      );
      final persistedY3 = GmCareerCodec.decode((await verifyStorage.read())!);
      expect(persistedY3.currentYear, 3);
      expect(persistedY3.seasonHistory.length, 2);

      final a1 = await verifyStorage.readArchive(seasonYear: 1);
      final a2 = await verifyStorage.readArchive(seasonYear: 2);
      expect(a1, isNotNull);
      expect(a2, isNotNull);
      SeasonArchiveCodec.decodeAndVerify(
        a1!,
        expectedDigest: persistedY3.seasonHistory[0].archiveDigest,
        expectedCareerId: persistedY3.id,
        expectedSeasonYear: 1,
        expectedRecord: persistedY3.seasonHistory[0],
      );
      SeasonArchiveCodec.decodeAndVerify(
        a2!,
        expectedDigest: persistedY3.seasonHistory[1].archiveDigest,
        expectedCareerId: persistedY3.id,
        expectedSeasonYear: 2,
        expectedRecord: persistedY3.seasonHistory[1],
      );

      // 11. Restart/reload restores Year 3 without duplicating archive history.
      final reloadCtrl = GmCareerController(storage: verifyStorage);
      addTearDown(reloadCtrl.dispose);
      await reloadCtrl.loadCareer();
      expect(reloadCtrl.career?.currentYear, 3);
      expect(reloadCtrl.career?.seasonHistory.length, 2);
      expect(reloadCtrl.draftRecoveryRequired, isFalse);

      final sortedGaps = List<int>.of(heartbeatGapsMs)..sort();
      final report = <String, Object?>{
        'transition_ms': transitionSw.elapsedMilliseconds,
        'heartbeat_ticks': heartbeatGapsMs.length,
        'heartbeat_max_gap_ms': sortedGaps.isEmpty ? 0 : sortedGaps.last,
        'heartbeat_median_gap_ms': sortedGaps.isEmpty
            ? 0
            : sortedGaps[sortedGaps.length ~/ 2],
        'heartbeat_gaps_over_250ms': heartbeatGapsMs
            .where((g) => g > 250)
            .length,
        'frame_count': frameTotalUs.length,
      };
      binding.reportData = report;
      // ignore: avoid_print
      print('[D3C-T04A-ANDROID-UI] ${jsonEncode(report)}');
    },
  );
}
