import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simulation_core/simulation_core.dart';

import 'support/d3c_fixture_helper.dart';

Map<String, Object?> _summarize(List<int> samplesMs) {
  if (samplesMs.isEmpty) {
    return {
      'samples_ms': <int>[],
      'min_ms': 0,
      'median_ms': 0,
      'max_ms': 0,
      'iterations': 0,
    };
  }
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
      reason: 'D3C-T03B2 latency benchmark must run in AOT profile mode',
    );

    final docsDir = await getApplicationDocumentsDirectory();
    benchRootDir = Directory(
      '${docsDir.path}/d3c_t03b2_latency_${DateTime.now().millisecondsSinceEpoch}',
    )..createSync(recursive: true);

    y2Completed = await compute(_buildY2CompletedFixture, 'd3c-t03b2-latency');
  });

  tearDownAll(() async {
    try {
      if (benchRootDir.existsSync()) {
        benchRootDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  testWidgets('D3C-T03B2 Android AOT Profile Optimized Controller Benchmark', (
    tester,
  ) async {
    final y2Encoded = GmCareerCodec.encode(y2Completed);

    // Warm up isolate & ArchiveWorkerSession outside measured timings.
    final warmupDir = Directory('${benchRootDir.path}/warmup')
      ..createSync(recursive: true);
    final warmupStorage = FileGmCareerStorage(directoryPath: warmupDir.path);
    await warmupStorage.write(y2Encoded);
    final warmupCtrl = GmCareerController(storage: warmupStorage);
    try {
      await warmupCtrl.loadCareer();
      await warmupCtrl.continueToNextSeason(confirmed: true);
    } finally {
      warmupCtrl.dispose();
      warmupDir.deleteSync(recursive: true);
    }

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

    final controllerE2eMs = <int>[];
    final heartbeatGapsMs = <int>[];
    final rolloverFrameTotalUs = <int>[];
    final rolloverFrameBuildUs = <int>[];
    var captureFrames = false;

    void onTimings(List<FrameTiming> timings) {
      if (!captureFrames) return;
      for (final t in timings) {
        rolloverFrameTotalUs.add(t.totalSpan.inMicroseconds);
        rolloverFrameBuildUs.add(t.buildDuration.inMicroseconds);
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

          captureFrames = true;
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
          captureFrames = false;
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
    final sortedFrameTotal = List<int>.of(rolloverFrameTotalUs)..sort();
    final sortedFrameBuild = List<int>.of(rolloverFrameBuildUs)..sort();

    final report = <String, Object?>{
      'build_mode': kProfileMode ? 'profile' : 'other',
      'optimized_controller_e2e': _summarize(controllerE2eMs),
      'heartbeat': {
        'tick_count': heartbeatGapsMs.length,
        'max_gap_ms': sortedGaps.isEmpty ? null : sortedGaps.last,
        'median_gap_ms': sortedGaps.isEmpty
            ? null
            : sortedGaps[sortedGaps.length ~/ 2],
        'gaps_over_50ms': heartbeatGapsMs.where((g) => g > 50).length,
        'gaps_over_100ms': heartbeatGapsMs.where((g) => g > 100).length,
        'gaps_over_250ms': heartbeatGapsMs.where((g) => g > 250).length,
      },
      'rollover_frame_timings': {
        'frame_count': rolloverFrameTotalUs.length,
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
    print('[D3C-T03B2-OPTIMIZED] ${jsonEncode(report)}');
  });
}
