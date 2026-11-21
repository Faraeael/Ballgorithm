import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/rollover_isolate_workers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simulation_core/simulation_core.dart';

import 'support/d3c_fixture_helper.dart';

Map<String, Object?> _summarize(List<int> samplesMs) {
  final sorted = List<int>.of(samplesMs)..sort();
  return {
    'samples_ms': samplesMs,
    'min_ms': sorted.first,
    'median_ms': sorted[sorted.length ~/ 2],
    'max_ms': sorted.last,
    'iterations': samplesMs.length,
  };
}

GmCareer _buildY2CompletedFixture(String careerId) {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: 20261028,
    ),
  );
  final y1Career = GmCareer.fromSetupResult(setup, id: careerId);
  final y1Completed = completeSeasonFromSetup(y1Career);
  final y2Initial = const SeasonRolloverService()
      .prepareArchiveAndRollover(current: y1Completed)
      .rolloverResult
      .nextCareer;
  return completeSeasonFromSetup(y2Initial);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory benchRootDir;
  late GmCareer y2Completed;

  setUpAll(() async {
    expect(
      kProfileMode,
      isTrue,
      reason: 'D3C-T03B1 responsiveness benchmark must run in AOT profile mode',
    );

    final docsDir = await getApplicationDocumentsDirectory();
    benchRootDir = Directory(
      '${docsDir.path}/d3c_t03b1_profile_${DateTime.now().millisecondsSinceEpoch}',
    )..createSync(recursive: true);

    y2Completed = await compute(_buildY2CompletedFixture, 'd3c-t03b1-profile');
  });

  tearDownAll(() async {
    try {
      if (benchRootDir.existsSync()) {
        benchRootDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  testWidgets('D3C-T03B1 Android AOT Profile Responsiveness Benchmark', (
    tester,
  ) async {
    // Warm-up isolate pool outside measured timings.
    final warmupDir = Directory('${benchRootDir.path}/warmup')
      ..createSync(recursive: true);
    final warmupStorage = FileGmCareerStorage(directoryPath: warmupDir.path);
    await warmupStorage.write(GmCareerCodec.encode(y2Completed));
    final warmupCtrl = GmCareerController(storage: warmupStorage);
    try {
      await warmupCtrl.loadCareer();
      await warmupCtrl.continueToNextSeason(confirmed: true);
    } finally {
      warmupCtrl.dispose();
      warmupDir.deleteSync(recursive: true);
    }

    // Pump live animated UI widget to observe real frame production & gaps.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Rolling over season...'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 1. Stage breakdown (3 iterations)
    final workerPrepMs = <int>[];
    final archiveVerifyMs = <int>[];
    final filesystemMs = <int>[];

    for (var i = 0; i < 3; i++) {
      final dir = Directory('${benchRootDir.path}/stages_$i')
        ..createSync(recursive: true);
      final storage = FileGmCareerStorage(directoryPath: dir.path);

      final swPrep = Stopwatch()..start();
      final prepared = await compute(
        prepareSeasonRolloverWorker,
        RolloverPrepareRequest(y2Completed),
      );
      swPrep.stop();
      workerPrepMs.add(swPrep.elapsedMilliseconds);

      final swVerify = Stopwatch()..start();
      await compute(
        verifySeasonArchiveWorker,
        ArchiveVerifyRequest(
          archiveJson: prepared.archiveJson,
          expectedDigest: prepared.archiveDigest,
          expectedSeasonYear: y2Completed.currentYear,
        ),
      );
      swVerify.stop();
      archiveVerifyMs.add(swVerify.elapsedMilliseconds);

      final swFs = Stopwatch()..start();
      await storage.writeArchive(
        seasonYear: y2Completed.currentYear,
        archiveJson: prepared.archiveJson,
        expectedDigest: prepared.archiveDigest,
      );
      await storage.write(prepared.encodedNextCareer);
      swFs.stop();
      filesystemMs.add(swFs.elapsedMilliseconds);

      dir.deleteSync(recursive: true);
    }

    // 2. End-to-end controller rollover with live main-isolate heartbeat & frame timings
    final controllerE2eMs = <int>[];
    final y2Encoded = GmCareerCodec.encode(y2Completed);
    final frameTotalUs = <int>[];
    final frameBuildUs = <int>[];
    final heartbeatGapsMs = <int>[];

    void onTimings(List<FrameTiming> timings) {
      for (final t in timings) {
        frameTotalUs.add(t.totalSpan.inMicroseconds);
        frameBuildUs.add(t.buildDuration.inMicroseconds);
      }
    }

    SchedulerBinding.instance.addTimingsCallback(onTimings);
    final rssBefore = ProcessInfo.currentRss;
    final maxRssBefore = ProcessInfo.maxRss;

    try {
      for (var i = 0; i < 3; i++) {
        final dir = Directory('${benchRootDir.path}/ctrl_$i')
          ..createSync(recursive: true);
        final storage = FileGmCareerStorage(directoryPath: dir.path);
        await storage.write(y2Encoded);
        final ctrl = GmCareerController(storage: storage);
        try {
          await ctrl.loadCareer();

          var lastTickMs = 0;
          final hbSw = Stopwatch()..start();
          final timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
            final now = hbSw.elapsedMilliseconds;
            heartbeatGapsMs.add(now - lastTickMs);
            lastTickMs = now;
          });

          // Pump frames while rollover future runs so Flutter schedules real frames.
          var done = false;
          final swE2e = Stopwatch()..start();
          final future = ctrl
              .continueToNextSeason(confirmed: true)
              .whenComplete(() {
                done = true;
              });
          while (!done) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          await future;
          swE2e.stop();
          timer.cancel();
          hbSw.stop();

          controllerE2eMs.add(swE2e.elapsedMilliseconds);
          expect(ctrl.career!.currentYear, 3);
        } finally {
          ctrl.dispose();
          dir.deleteSync(recursive: true);
        }
      }
    } finally {
      SchedulerBinding.instance.removeTimingsCallback(onTimings);
    }

    final rssAfter = ProcessInfo.currentRss;
    final maxRssAfter = ProcessInfo.maxRss;

    final sortedGaps = List<int>.of(heartbeatGapsMs)..sort();
    final sortedFrameTotal = List<int>.of(frameTotalUs)..sort();
    final sortedFrameBuild = List<int>.of(frameBuildUs)..sort();

    final report = <String, Object?>{
      'build_mode': kProfileMode ? 'profile' : 'other',
      'stages': {
        'worker_prepare': _summarize(workerPrepMs),
        'archive_verify': _summarize(archiveVerifyMs),
        'filesystem_and_verify': _summarize(filesystemMs),
        'controller_e2e': _summarize(controllerE2eMs),
      },
      'heartbeat': {
        'tick_count': heartbeatGapsMs.length,
        'max_gap_ms': sortedGaps.isEmpty ? null : sortedGaps.last,
        'median_gap_ms': sortedGaps.isEmpty
            ? null
            : sortedGaps[sortedGaps.length ~/ 2],
        'gaps_over_50ms': heartbeatGapsMs.where((g) => g > 50).length,
        'gaps_over_100ms': heartbeatGapsMs.where((g) => g > 100).length,
        'gaps_over_250ms': heartbeatGapsMs.where((g) => g > 250).length,
        'gaps_over_1000ms': heartbeatGapsMs.where((g) => g > 1000).length,
      },
      'ui_frame_timings': {
        'frame_count': frameTotalUs.length,
        'max_total_span_us': sortedFrameTotal.isEmpty
            ? null
            : sortedFrameTotal.last,
        'median_total_span_us': sortedFrameTotal.isEmpty
            ? null
            : sortedFrameTotal[sortedFrameTotal.length ~/ 2],
        'max_build_duration_us': sortedFrameBuild.isEmpty
            ? null
            : sortedFrameBuild.last,
      },
      'memory': {
        'rss_before_bytes': rssBefore,
        'max_rss_before_bytes': maxRssBefore,
        'rss_after_bytes': rssAfter,
        'max_rss_after_bytes': maxRssAfter,
      },
    };

    binding.reportData = report;
    // ignore: avoid_print
    print('[D3C-T03B1-PROFILE] ${jsonEncode(report)}');

    expect(heartbeatGapsMs, isNotEmpty);
    expect(frameTotalUs.length, greaterThan(0));
  });
}
