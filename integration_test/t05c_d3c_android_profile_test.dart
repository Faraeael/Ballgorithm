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
  final sorted = List<int>.of(samplesMs)..sort();
  return {
    'samples_ms': samplesMs,
    'min_ms': sorted.first,
    'median_ms': sorted[sorted.length ~/ 2],
    'max_ms': sorted.last,
    'iterations': samplesMs.length,
  };
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;
  late Directory benchRootDir;
  late GmCareer y1Career;
  late GmCareer y2Completed;
  late GmCareer y3Career;
  late String y1ArchiveJson;
  late String y1ArchiveDigest;
  late String y2ArchiveJson;
  late String y2ArchiveDigest;

  setUpAll(() async {
    expect(
      kProfileMode,
      isTrue,
      reason: 'D3C-T02 must run in AOT profile mode (--profile), not debug',
    );

    docsDir = await getApplicationDocumentsDirectory();
    benchRootDir = Directory(
      '${docsDir.path}/d3c_t02_profile_${DateTime.now().millisecondsSinceEpoch}',
    )..createSync(recursive: true);

    // Build deterministic Year 1, Year 2 completed, Year 3 active, and archives
    // outside measured benchmark timings.
    final setup = const CareerSetupService().generate(
      const CareerSetupRequest(
        selectedTeamId: TeamId('team-1'),
        selectedSituation: FranchiseSituation.tanking,
        seed: 20261028,
      ),
    );
    y1Career = GmCareer.fromSetupResult(setup, id: 'd3c-t02-profile');
    final y1Completed = completeSeasonFromSetup(y1Career);

    final setupDir = Directory('${benchRootDir.path}/fixture_setup')
      ..createSync(recursive: true);
    final setupStorage = FileGmCareerStorage(directoryPath: setupDir.path);
    final setupCtrl = GmCareerController(storage: setupStorage);
    try {
      await setupStorage.write(GmCareerCodec.encode(y1Completed));
      await setupCtrl.loadCareer();
      await setupCtrl.continueToNextSeason(confirmed: true);

      y2Completed = completeSeasonFromSetup(setupCtrl.career!);
      await setupStorage.write(GmCareerCodec.encode(y2Completed));
      await setupCtrl.loadCareer();
      await setupCtrl.continueToNextSeason(confirmed: true);
      y3Career = setupCtrl.career!;

      y1ArchiveJson = (await setupStorage.readArchive(seasonYear: 1))!;
      y1ArchiveDigest = SeasonArchiveCodec.digestOf(y1ArchiveJson);
      y2ArchiveJson = (await setupStorage.readArchive(seasonYear: 2))!;
      y2ArchiveDigest = SeasonArchiveCodec.digestOf(y2ArchiveJson);
    } finally {
      setupCtrl.dispose();
      if (setupDir.existsSync()) {
        setupDir.deleteSync(recursive: true);
      }
    }
  });

  tearDownAll(() async {
    try {
      if (benchRootDir.existsSync()) {
        benchRootDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  testWidgets('D3C-T02 Android Profile-Mode Persistence Audit', (tester) async {
    final rssBeforeBench = ProcessInfo.currentRss;
    final maxRssBeforeBench = ProcessInfo.maxRss;

    // -------------------------------------------------------------------------
    // 1. Warm-up (excluded from measured statistics)
    // -------------------------------------------------------------------------
    final warmupDir = Directory('${benchRootDir.path}/warmup')
      ..createSync(recursive: true);
    final warmupStorage = FileGmCareerStorage(directoryPath: warmupDir.path);
    final warmupEncoded = GmCareerCodec.encode(y1Career);
    await warmupStorage.write(warmupEncoded);
    final warmupRead = await warmupStorage.read();
    GmCareerCodec.decode(warmupRead!);
    await warmupStorage.writeArchive(
      seasonYear: 1,
      archiveJson: y1ArchiveJson,
      expectedDigest: y1ArchiveDigest,
    );
    final warmupArch = await warmupStorage.readArchive(seasonYear: 1);
    SeasonArchiveCodec.decodeAndVerify(
      warmupArch!,
      expectedDigest: y1ArchiveDigest,
      expectedCareerId: y3Career.id,
      expectedSeasonYear: 1,
      expectedRecord: y3Career.seasonHistory[0],
    );
    warmupDir.deleteSync(recursive: true);

    // -------------------------------------------------------------------------
    // 2. Active Career Serialization (Year 1 & Year 3, 3 iterations each)
    // -------------------------------------------------------------------------
    Future<Map<String, Object?>> benchActiveCareer(
      GmCareer career,
      String label,
    ) async {
      final encodeMs = <int>[];
      final writeMs = <int>[];
      final readMs = <int>[];
      final decodeMs = <int>[];
      var utf8Bytes = 0;

      for (var i = 0; i < 3; i++) {
        final dir = Directory('${benchRootDir.path}/active_${label}_$i')
          ..createSync(recursive: true);
        final storage = FileGmCareerStorage(directoryPath: dir.path);

        final swEnc = Stopwatch()..start();
        final encoded = GmCareerCodec.encode(career);
        swEnc.stop();
        encodeMs.add(swEnc.elapsedMilliseconds);
        if (i == 0) {
          utf8Bytes = utf8.encode(encoded).length;
        }

        final swWrite = Stopwatch()..start();
        await storage.write(encoded);
        swWrite.stop();
        writeMs.add(swWrite.elapsedMilliseconds);

        final swRead = Stopwatch()..start();
        final loaded = await storage.read();
        swRead.stop();
        readMs.add(swRead.elapsedMilliseconds);

        final swDec = Stopwatch()..start();
        final decoded = GmCareerCodec.decode(loaded!);
        swDec.stop();
        decodeMs.add(swDec.elapsedMilliseconds);
        expect(decoded.id, career.id);

        dir.deleteSync(recursive: true);
      }

      return {
        'utf8_bytes': utf8Bytes,
        'encode': _summarize(encodeMs),
        'write': _summarize(writeMs),
        'read': _summarize(readMs),
        'decode': _summarize(decodeMs),
      };
    }

    final activeY1Report = await benchActiveCareer(y1Career, 'y1');
    final activeY3Report = await benchActiveCareer(y3Career, 'y3');

    // -------------------------------------------------------------------------
    // 3. Archive Read & Validation Breakdown (Year 1 & Year 2, 3 iterations)
    // -------------------------------------------------------------------------
    Future<Map<String, Object?>> benchArchiveRead({
      required int seasonYear,
      required String archiveJson,
      required String expectedDigest,
      required SeasonHistoryRecord expectedRecord,
    }) async {
      final dir = Directory('${benchRootDir.path}/arch_read_y$seasonYear')
        ..createSync(recursive: true);
      final storage = FileGmCareerStorage(directoryPath: dir.path);
      await storage.writeArchive(
        seasonYear: seasonYear,
        archiveJson: archiveJson,
        expectedDigest: expectedDigest,
      );
      final file = File(storage.resolveArchivePath(seasonYear));
      final sizeBytes = file.lengthSync();

      final fileReadMs = <int>[];
      final digestMs = <int>[];
      final decodeVerifyMs = <int>[];
      final e2eMs = <int>[];
      final rssBeforeDecode = ProcessInfo.currentRss;

      for (var i = 0; i < 3; i++) {
        final swRead = Stopwatch()..start();
        final raw = await file.readAsString();
        swRead.stop();
        fileReadMs.add(swRead.elapsedMilliseconds);

        final swDigest = Stopwatch()..start();
        final d = SeasonArchiveCodec.digestOf(raw);
        swDigest.stop();
        digestMs.add(swDigest.elapsedMilliseconds);
        expect(d, expectedDigest);

        final swDec = Stopwatch()..start();
        final parsed = SeasonArchiveCodec.decodeAndVerify(
          raw,
          expectedDigest: expectedDigest,
          expectedCareerId: y3Career.id,
          expectedSeasonYear: seasonYear,
          expectedRecord: expectedRecord,
        );
        swDec.stop();
        decodeVerifyMs.add(swDec.elapsedMilliseconds);
        expect(parsed.playoffState.champion, expectedRecord.championTeamId);

        final swE2e = Stopwatch()..start();
        final rawE2e = await storage.readArchive(seasonYear: seasonYear);
        final parsedE2e = SeasonArchiveCodec.decodeAndVerify(
          rawE2e!,
          expectedDigest: expectedDigest,
          expectedCareerId: y3Career.id,
          expectedSeasonYear: seasonYear,
          expectedRecord: expectedRecord,
        );
        swE2e.stop();
        e2eMs.add(swE2e.elapsedMilliseconds);
        expect(parsedE2e.seasonYear, seasonYear);
      }

      final rssAfterDecode = ProcessInfo.currentRss;
      dir.deleteSync(recursive: true);

      return {
        'size_bytes': sizeBytes,
        'rss_before_bytes': rssBeforeDecode,
        'rss_after_bytes': rssAfterDecode,
        'file_read': _summarize(fileReadMs),
        'digest': _summarize(digestMs),
        'decode_and_verify': _summarize(decodeVerifyMs),
        'e2e_read_and_validate': _summarize(e2eMs),
      };
    }

    final archY1Report = await benchArchiveRead(
      seasonYear: 1,
      archiveJson: y1ArchiveJson,
      expectedDigest: y1ArchiveDigest,
      expectedRecord: y3Career.seasonHistory[0],
    );
    final archY2Report = await benchArchiveRead(
      seasonYear: 2,
      archiveJson: y2ArchiveJson,
      expectedDigest: y2ArchiveDigest,
      expectedRecord: y3Career.seasonHistory[1],
    );

    // -------------------------------------------------------------------------
    // 4. Rollover Stages A-G (3 iterations) + Stage H End-to-End (3 iterations)
    // -------------------------------------------------------------------------
    final stageAFromCareerMs = <int>[];
    final stageBEncodeDigestMs = <int>[];
    final stageCHistoryRecordMs = <int>[];
    final stageDRolloverMs = <int>[];
    final stageEEncodeNextMs = <int>[];
    final stageFWriteArchiveMs = <int>[];
    final stageGWriteActiveMs = <int>[];

    for (var i = 0; i < 3; i++) {
      final dir = Directory('${benchRootDir.path}/rollover_stages_$i')
        ..createSync(recursive: true);
      final storage = FileGmCareerStorage(directoryPath: dir.path);

      final swA = Stopwatch()..start();
      final archive = SeasonArchive.fromCareer(y2Completed);
      swA.stop();
      stageAFromCareerMs.add(swA.elapsedMilliseconds);

      final swB = Stopwatch()..start();
      final encodedArchive = SeasonArchiveCodec.encodeWithDigest(archive);
      swB.stop();
      stageBEncodeDigestMs.add(swB.elapsedMilliseconds);

      final swC = Stopwatch()..start();
      final record = archive.toHistoryRecord(encodedArchive.digest);
      swC.stop();
      stageCHistoryRecordMs.add(swC.elapsedMilliseconds);

      final swD = Stopwatch()..start();
      final next = const SeasonRolloverService().rollover(
        current: y2Completed,
        archiveRecord: record,
      );
      swD.stop();
      stageDRolloverMs.add(swD.elapsedMilliseconds);

      final swE = Stopwatch()..start();
      final encodedNext = GmCareerCodec.encode(next);
      swE.stop();
      stageEEncodeNextMs.add(swE.elapsedMilliseconds);

      final swF = Stopwatch()..start();
      await storage.writeArchive(
        seasonYear: y2Completed.currentYear,
        archiveJson: encodedArchive.json,
        expectedDigest: encodedArchive.digest,
      );
      swF.stop();
      stageFWriteArchiveMs.add(swF.elapsedMilliseconds);

      final swG = Stopwatch()..start();
      await storage.write(encodedNext);
      swG.stop();
      stageGWriteActiveMs.add(swG.elapsedMilliseconds);

      dir.deleteSync(recursive: true);
    }

    // Stage H: Complete controller rollover + UI frame timing capture
    final stageHControllerMs = <int>[];
    final y2Encoded = GmCareerCodec.encode(y2Completed);
    final frameTotalUs = <int>[];
    final frameBuildUs = <int>[];
    void onTimings(List<FrameTiming> timings) {
      for (final t in timings) {
        frameTotalUs.add(t.totalSpan.inMicroseconds);
        frameBuildUs.add(t.buildDuration.inMicroseconds);
      }
    }

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    );
    await tester.pump();
    SchedulerBinding.instance.addTimingsCallback(onTimings);

    final rssBeforeRollover = ProcessInfo.currentRss;
    try {
      for (var i = 0; i < 3; i++) {
        final dir = Directory('${benchRootDir.path}/rollover_ctrl_$i')
          ..createSync(recursive: true);
        final storage = FileGmCareerStorage(directoryPath: dir.path);
        await storage.write(y2Encoded);
        final ctrl = GmCareerController(storage: storage);
        try {
          await ctrl.loadCareer();
          final swH = Stopwatch()..start();
          await ctrl.continueToNextSeason(confirmed: true);
          swH.stop();
          stageHControllerMs.add(swH.elapsedMilliseconds);
          expect(ctrl.career!.currentYear, 3);
        } finally {
          ctrl.dispose();
          dir.deleteSync(recursive: true);
        }
      }
      await tester.pump();
    } finally {
      SchedulerBinding.instance.removeTimingsCallback(onTimings);
    }

    final rssAfterRollover = ProcessInfo.currentRss;
    final maxRssAfterBench = ProcessInfo.maxRss;

    final maxFrameTotalUs = frameTotalUs.isEmpty
        ? null
        : (List<int>.of(frameTotalUs)..sort()).last;
    final maxFrameBuildUs = frameBuildUs.isEmpty
        ? null
        : (List<int>.of(frameBuildUs)..sort()).last;

    final report = <String, Object?>{
      'build_mode': kProfileMode ? 'profile' : 'other',
      'active_y1': activeY1Report,
      'active_y3': activeY3Report,
      'archive_y1': archY1Report,
      'archive_y2': archY2Report,
      'rollover': {
        'A_fromCareer': _summarize(stageAFromCareerMs),
        'B_encodeWithDigest': _summarize(stageBEncodeDigestMs),
        'C_toHistoryRecord': _summarize(stageCHistoryRecordMs),
        'D_rolloverService': _summarize(stageDRolloverMs),
        'E_encodeNextCareer': _summarize(stageEEncodeNextMs),
        'F_writeArchive': _summarize(stageFWriteArchiveMs),
        'G_writeActive': _summarize(stageGWriteActiveMs),
        'H_controllerEndToEnd': _summarize(stageHControllerMs),
      },
      'memory': {
        'rss_before_bench_bytes': rssBeforeBench,
        'max_rss_before_bench_bytes': maxRssBeforeBench,
        'rss_before_rollover_bytes': rssBeforeRollover,
        'rss_after_rollover_bytes': rssAfterRollover,
        'max_rss_after_bench_bytes': maxRssAfterBench,
      },
      'ui_frame_timings': {
        'frame_count': frameTotalUs.length,
        'max_total_span_us': maxFrameTotalUs,
        'max_build_duration_us': maxFrameBuildUs,
      },
    };

    binding.reportData = report;
    // ignore: avoid_print
    print('[D3C-T02-PROFILE] ${jsonEncode(report)}');
  });
}
