import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/draft_board_screen.dart';
import 'package:basketball_manager/features/career/free_agents_screen.dart';
import 'package:basketball_manager/features/career/league_readiness_screen.dart';
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

/// Length + mtime of every file under [dir]; detects any storage write.
Map<String, String> _snapshotDir(Directory dir) => {
  for (final e in dir.listSync(recursive: true).whereType<File>())
    e.path: '${e.lengthSync()}@${e.lastModifiedSync().microsecondsSinceEpoch}',
};

Future<void> _pumpFor(WidgetTester tester, {int frames = 15}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
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
      '${docsDir.path}/d3c_t04b_journey_${DateTime.now().millisecondsSinceEpoch}',
    )..createSync(recursive: true);
    final built = await compute(
      _buildYear2CompletedWithY1Archive,
      'd3c-t04b-android-journey',
    );
    y2Completed = built.y2Completed;
    y1ArchJson = built.y1ArchJson;
    y1ArchDigest = built.y1ArchDigest;
  });

  tearDownAll(() async {
    try {
      if (testRootDir.existsSync()) testRootDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('D3C-T04B Real Android career journey Y2 champion -> Y3 offseason', (
    tester,
  ) async {
    expect(
      kProfileMode,
      isTrue,
      reason: 'must run under flutter drive --profile',
    );

    final storage = FileGmCareerStorage(directoryPath: testRootDir.path);
    await storage.writeArchive(
      seasonYear: 1,
      archiveJson: y1ArchJson,
      expectedDigest: y1ArchDigest,
    );
    await storage.write(GmCareerCodec.encode(y2Completed));

    Widget buildApp(GmCareerController c) => BasketballManagerApp(
      league: y2Completed.league,
      storage: InMemorySeasonStorage(),
      careerStorage: storage,
      careerController: c,
      seasonMode: true,
    );

    // Production controller, production isolate worker (no override).
    final controller = GmCareerController(storage: storage);
    var controllerDisposed = false;
    addTearDown(() {
      if (!controllerDisposed) controller.dispose();
    });
    await tester.pumpWidget(buildApp(controller));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(PlayoffTournamentScreen).evaluate().isNotEmpty) break;
    }

    // --- Championship ---
    expect(find.byType(PlayoffTournamentScreen), findsOneWidget);
    expect(find.text('Season 2'), findsOneWidget);
    final championId = y2Completed.playoffState!.champion!;
    final championName = y2Completed.league.teams
        .firstWhere((t) => t.id == championId)
        .name;
    expect(find.text(championName), findsWidgets);
    final y2Encoded = GmCareerCodec.encode(y2Completed);
    final franchiseId = y2Completed.userFranchiseId;
    final careerId = y2Completed.id;

    final continueKey = const ValueKey('continue-to-next-season');
    await tester.scrollUntilVisible(
      find.byKey(continueKey),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(continueKey));
    await _pumpFor(tester);
    expect(find.text('Start Next Season?'), findsOneWidget);

    final beforeCancel = _snapshotDir(testRootDir);
    await tester.tap(find.byKey(const ValueKey('cancel-next-season')));
    await _pumpFor(tester);
    expect(controller.career?.currentYear, 2);
    expect(controller.career?.phase, CareerPhase.playoffs);
    expect(controller.seasonTransitionStage, isNull);
    expect(_snapshotDir(testRootDir), beforeCancel);
    expect(await storage.read(), y2Encoded);

    await tester.tap(find.byKey(continueKey));
    await _pumpFor(tester);
    expect(find.text('Start Next Season?'), findsOneWidget);

    // --- Rollover (measured) ---
    final gapsMs = <int>[];
    final frameTotalUs = <int>[];
    var capture = false;
    void onTimings(List<FrameTiming> ts) {
      if (!capture) return;
      for (final t in ts) {
        frameTotalUs.add(t.totalSpan.inMicroseconds);
      }
    }

    SchedulerBinding.instance.addTimingsCallback(onTimings);
    var lastTickMs = 0;
    final hbSw = Stopwatch()..start();
    final timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = hbSw.elapsedMilliseconds;
      gapsMs.add(now - lastTickMs);
      lastTickMs = now;
    });

    final stageFirstSeenMs = <String, int>{};
    const stageLabels = {
      'preparing': 'Preparing next season',
      'archiving': 'Verifying and archiving completed season',
      'saving': 'Saving your next season',
    };
    var sawCard = false;
    var duplicateBlocked = false;
    var duplicateTapped = false;
    var rssStart = ProcessInfo.currentRss;
    var rssPeak = rssStart;
    final sw = Stopwatch()..start();
    try {
      capture = true;
      await tester.tap(find.byKey(const ValueKey('confirm-next-season')));
      for (var i = 0; i < 3000; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final rss = ProcessInfo.currentRss;
        if (rss > rssPeak) rssPeak = rss;
        if (find
            .byKey(const ValueKey('season-transition-progress-card'))
            .evaluate()
            .isNotEmpty) {
          if (!sawCard) {
            sawCard = true;
            expect(find.text('Season 2 → Season 3'), findsOneWidget);
          }
          stageLabels.forEach((k, label) {
            if (find.text(label).evaluate().isNotEmpty) {
              stageFirstSeenMs.putIfAbsent(k, () => sw.elapsedMilliseconds);
            }
          });
        }
        final btn = find.byKey(continueKey);
        if (btn.evaluate().isNotEmpty) {
          if (tester.widget<FilledButton>(btn).onPressed == null) {
            duplicateBlocked = true;
            if (!duplicateTapped) {
              duplicateTapped = true;
              await tester.tap(btn, warnIfMissed: false);
            }
          }
        }
        if (find.byType(GmOffseasonOverviewScreen).evaluate().isNotEmpty &&
            !controller.isLoading &&
            controller.seasonTransitionStage == null) {
          break;
        }
      }
      sw.stop();
    } finally {
      capture = false;
      timer.cancel();
      hbSw.stop();
      SchedulerBinding.instance.removeTimingsCallback(onTimings);
    }
    final rssEnd = ProcessInfo.currentRss;
    await _pumpFor(tester);

    expect(sawCard, isTrue);
    expect(duplicateBlocked, isTrue);
    expect(controller.seasonTransitionStage, isNull);
    expect(controller.errorMessage, isNull);
    expect(controller.draftRecoveryRequired, isFalse);
    expect(find.byType(PlayoffTournamentScreen), findsNothing);
    expect(find.byType(GmOffseasonOverviewScreen), findsOneWidget);
    expect(find.text('Year 3 • Opening Offseason'), findsOneWidget);

    // --- Year 3 offseason ---
    final career = controller.career!;
    expect(career.currentYear, 3);
    expect(career.phase, CareerPhase.openingOffseason);
    expect(career.id, careerId);
    expect(career.userFranchiseId, franchiseId);
    final team = career.league.teams.firstWhere((t) => t.id == franchiseId);
    expect(find.text('${team.abbreviation} Offseason'), findsOneWidget);
    expect(career.draftClass.length, greaterThan(0));
    final rosterCount = team.players.length;
    final leaguePlayerCount = career.league.teams.fold<int>(
      0,
      (n, t) => n + t.players.length,
    );
    // ignore: avoid_print
    print(
      '[D3C-T04B-ROSTER] userRoster=$rosterCount leagueRostered=$leaguePlayerCount '
      'freeAgents=${career.freeAgentPool.length} draftClass=${career.draftClass.length}',
    );
    expect(find.byKey(const ValueKey('continue-to-next-season')), findsNothing);
    expect(tester.takeException(), isNull);

    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('offseason-overview-scroll')),
      matching: find.byType(Scrollable),
    );
    Future<void> openAndReturn(
      String key,
      Type screen,
      void Function() inspect,
    ) async {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey(key)),
        300,
        scrollable: scrollable.first,
      );
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(ValueKey(key)));
      await _pumpFor(tester, frames: 25);
      expect(find.byType(screen), findsOneWidget);
      inspect();
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await _pumpFor(tester, frames: 25);
      expect(find.byType(screen), findsNothing);
      expect(find.byType(GmOffseasonOverviewScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Year 3 • Opening Offseason'),
        -300,
        scrollable: scrollable.first,
      );
      expect(find.text('Year 3 • Opening Offseason'), findsOneWidget);
    }

    final beforeNav = _snapshotDir(testRootDir);
    final persistedBeforeNav = await storage.read();
    final loadingDuringNav = <bool>[];
    controller.addListener(() => loadingDuringNav.add(controller.isLoading));

    await openAndReturn('btn-open-draft-board', GmDraftBoardScreen, () {
      expect(find.text('Rookie Draft Board'), findsOneWidget);
    });
    await openAndReturn('btn-open-free-agents', GmFreeAgentsScreen, () {
      expect(
        find.text('Free Agents (${career.freeAgentPool.length})'),
        findsOneWidget,
      );
    });
    await openAndReturn(
      'btn-open-league-readiness',
      GmLeagueReadinessScreen,
      () {
        expect(find.text('League Readiness'), findsWidgets);
      },
    );

    expect(_snapshotDir(testRootDir), beforeNav);
    expect(await storage.read(), persistedBeforeNav);
    expect(identical(controller.career, career), isTrue);
    expect(controller.isLoading, isFalse);
    expect(tester.takeException(), isNull);

    // --- Save integrity ---
    final persistedY3 = GmCareerCodec.decode((await storage.read())!);
    expect(persistedY3.id, careerId);
    expect(persistedY3.currentYear, 3);
    expect(persistedY3.phase, CareerPhase.openingOffseason);
    expect(persistedY3.userFranchiseId, franchiseId);
    expect(persistedY3.seasonHistory.length, 2);
    expect(persistedY3.seasonHistory.map((r) => r.seasonYear).toList(), [1, 2]);
    expect(
      persistedY3.seasonHistory.map((r) => r.archiveDigest).toSet().length,
      2,
    );
    final archiveFiles = testRootDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.contains('archive'))
        .length;
    final a1 = await storage.readArchive(seasonYear: 1);
    final a2 = await storage.readArchive(seasonYear: 2);
    expect(a1, isNotNull);
    expect(a2, isNotNull);
    final arch1 = SeasonArchiveCodec.decodeAndVerify(
      a1!,
      expectedDigest: persistedY3.seasonHistory[0].archiveDigest,
      expectedCareerId: careerId,
      expectedSeasonYear: 1,
      expectedRecord: persistedY3.seasonHistory[0],
    );
    final arch2 = SeasonArchiveCodec.decodeAndVerify(
      a2!,
      expectedDigest: persistedY3.seasonHistory[1].archiveDigest,
      expectedCareerId: careerId,
      expectedSeasonYear: 2,
      expectedRecord: persistedY3.seasonHistory[1],
    );
    expect(
      arch1.playoffState.champion,
      persistedY3.seasonHistory[0].championTeamId,
    );
    expect(arch2.playoffState.champion, championId);
    expect(persistedY3.seasonHistory[1].championTeamId, championId);
    expect(
      a1,
      y1ArchJson,
      reason: 'Year 1 archive must be preserved byte-for-byte',
    );
    expect(await storage.readArchive(seasonYear: 3), isNull);

    // --- App/controller reload (not an OS process restart) ---
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    controller.dispose();
    controllerDisposed = true;
    final reloadCtrl = GmCareerController(storage: storage);
    addTearDown(reloadCtrl.dispose);
    await tester.pumpWidget(buildApp(reloadCtrl));
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(GmOffseasonOverviewScreen).evaluate().isNotEmpty &&
          !reloadCtrl.isLoading) {
        break;
      }
    }
    expect(find.byType(GmOffseasonOverviewScreen), findsOneWidget);
    expect(find.text('Year 3 • Opening Offseason'), findsOneWidget);
    expect(find.text('${team.abbreviation} Offseason'), findsOneWidget);
    expect(find.byType(PlayoffTournamentScreen), findsNothing);
    expect(reloadCtrl.errorMessage, isNull);
    expect(reloadCtrl.draftRecoveryRequired, isFalse);
    expect(reloadCtrl.isLoading, isFalse);
    expect(reloadCtrl.seasonTransitionStage, isNull);
    final rc = reloadCtrl.career!;
    expect(rc.id, careerId);
    expect(rc.userFranchiseId, franchiseId);
    expect(rc.currentYear, 3);
    expect(rc.seasonHistory.length, 2);
    expect(rc.seasonHistory.map((r) => r.seasonYear).toList(), [1, 2]);
    expect(GmCareerCodec.encode(rc), persistedBeforeNav);
    expect(_snapshotDir(testRootDir).keys.toSet(), beforeNav.keys.toSet());
    expect(tester.takeException(), isNull);

    final sorted = List<int>.of(gapsMs)..sort();
    final fs = List<int>.of(frameTotalUs)..sort();
    int pct(List<int> l, double p) =>
        l.isEmpty ? 0 : l[((l.length - 1) * p).round()];
    final report = <String, Object?>{
      'mode': 'profile',
      'k_profile_mode': kProfileMode,
      'rollover_ms': sw.elapsedMilliseconds,
      'stage_first_seen_ms': stageFirstSeenMs,
      'heartbeat_ticks': gapsMs.length,
      'heartbeat_max_gap_ms': sorted.isEmpty ? 0 : sorted.last,
      'heartbeat_median_gap_ms': pct(sorted, 0.5),
      'heartbeat_p99_gap_ms': pct(sorted, 0.99),
      'heartbeat_gaps_over_250ms': gapsMs.where((g) => g > 250).length,
      'heartbeat_gaps_over_100ms': gapsMs.where((g) => g > 100).length,
      'heartbeat_gaps_top10_ms': sorted.reversed.take(10).toList(),
      'frame_count': fs.length,
      'frame_total_median_us': pct(fs, 0.5),
      'frame_total_p95_us': pct(fs, 0.95),
      'frame_total_max_us': fs.isEmpty ? 0 : fs.last,
      'frames_over_700ms': fs.where((u) => u > 700000).length,
      'rss_start_mb': rssStart / 1048576,
      'rss_peak_mb': rssPeak / 1048576,
      'rss_end_mb': rssEnd / 1048576,
      'archive_files': archiveFiles,
      'listener_loading_true_during_nav': loadingDuringNav
          .where((b) => b)
          .length,
    };
    binding.reportData = report;
    // ignore: avoid_print
    print('[D3C-T04B-ANDROID-JOURNEY] ${jsonEncode(report)}');
  });
}
