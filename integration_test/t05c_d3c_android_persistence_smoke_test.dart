import 'dart:io';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simulation_core/simulation_core.dart';

import 'support/d3c_fixture_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;
  late Directory testRootDir;

  setUpAll(() async {
    final docsSw = Stopwatch()..start();
    docsDir = await getApplicationDocumentsDirectory();
    docsSw.stop();
    // ignore: avoid_print
    print(
      '[D3C-T01] path_provider docsDir=${docsDir.path} '
      'resolved_ms=${docsSw.elapsedMilliseconds}',
    );
    testRootDir = Directory(
      '${docsDir.path}/d3c_t01_android_smoke_${DateTime.now().millisecondsSinceEpoch}',
    )..createSync(recursive: true);
  });

  tearDownAll(() async {
    try {
      if (testRootDir.existsSync()) {
        testRootDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('M009-T05C-C2-D3C-T01 Android Persistence Smoke', () {
    testWidgets(
      'Android Storage Smoke Test: real path_provider + FileGmCareerStorage + recovery + controller lifecycle',
      (tester) async {
        final saveDir = Directory('${testRootDir.path}/storage_smoke')
          ..createSync(recursive: true);
        final storageA = FileGmCareerStorage(directoryPath: saveDir.path);

        final setup = const CareerSetupService().generate(
          const CareerSetupRequest(
            selectedTeamId: TeamId('team-1'),
            selectedSituation: FranchiseSituation.tanking,
            seed: 20261028,
          ),
        );
        final careerA = const DraftExecutionService().startDraft(
          GmCareer.fromSetupResult(setup, id: 'd3c-android-smoke-a'),
        );
        final encodedA = GmCareerCodec.encode(careerA);

        final writeSw = Stopwatch()..start();
        await storageA.write(encodedA);
        writeSw.stop();

        final activeFile = File(storageA.resolvePath());
        expect(activeFile.existsSync(), isTrue);
        final activeBytes = activeFile.lengthSync();

        // Read using a fresh FileGmCareerStorage instance
        final storageB = FileGmCareerStorage(directoryPath: saveDir.path);
        final readSw = Stopwatch()..start();
        final loadedJson = await storageB.read();
        expect(loadedJson, isNotNull);
        final decodedA = GmCareerCodec.decode(loadedJson!);
        readSw.stop();

        // Verify preserved content
        expect(loadedJson, encodedA);
        expect(decodedA.id, careerA.id);
        expect(decodedA.userFranchiseId, careerA.userFranchiseId);
        expect(decodedA.currentYear, careerA.currentYear);
        expect(decodedA.phase, careerA.phase);
        expect(
          decodedA.finances.contracts.length,
          careerA.finances.contracts.length,
        );
        expect(
          decodedA.finances.teamFinances.length,
          careerA.finances.teamFinances.length,
        );
        expect(
          decodedA.finances.teamFinances[careerA.userFranchiseId.value]?.cash,
          careerA.finances.teamFinances[careerA.userFranchiseId.value]?.cash,
        );

        // Verify missing/corrupt recovery inside test-owned files
        final recoveryDir = Directory('${testRootDir.path}/recovery_smoke')
          ..createSync(recursive: true);
        final recoveryStorage = FileGmCareerStorage(
          directoryPath: recoveryDir.path,
        );
        await recoveryStorage.write(encodedA);
        // Simulate corrupt active with valid .bak fallback
        await File(
          '${recoveryStorage.resolvePath()}.bak',
        ).writeAsString(encodedA, flush: true);
        await File(
          recoveryStorage.resolvePath(),
        ).writeAsString('{"corruptActive":', flush: true);
        final recoveredJson = await recoveryStorage.read();
        expect(recoveredJson, encodedA);
        expect(GmCareerCodec.decode(recoveredJson!).id, careerA.id);

        // Simulate missing active with corrupt .bak -> must throw, not return null
        final brokenDir = Directory('${testRootDir.path}/broken_smoke')
          ..createSync(recursive: true);
        final brokenStorage = FileGmCareerStorage(
          directoryPath: brokenDir.path,
        );
        await File(
          '${brokenStorage.resolvePath()}.bak',
        ).writeAsString('{"corruptBak":', flush: true);
        await expectLater(
          brokenStorage.read(),
          throwsA(isA<GmCareerStorageException>()),
        );

        // Verify controller disposal & recreation retains writes
        final ctrlDir = Directory('${testRootDir.path}/controller_smoke')
          ..createSync(recursive: true);
        final ctrl1 = GmCareerController(
          storage: FileGmCareerStorage(directoryPath: ctrlDir.path),
        );
        await ctrl1.startCareer(setup);
        final createdId = ctrl1.career!.id;
        ctrl1.dispose();

        final ctrl2 = GmCareerController(
          storage: FileGmCareerStorage(directoryPath: ctrlDir.path),
        );
        try {
          await ctrl2.loadCareer();
          expect(ctrl2.career, isNotNull);
          expect(ctrl2.career!.id, createdId);
          expect(ctrl2.career!.userFranchiseId, const TeamId('team-1'));
        } finally {
          ctrl2.dispose();
        }

        // ignore: avoid_print
        print(
          '[D3C-T01] [DEBUG] active_write_ms=${writeSw.elapsedMilliseconds} '
          'active_read_decode_ms=${readSw.elapsedMilliseconds} '
          'active_size_bytes=$activeBytes '
          'rss_bytes=${ProcessInfo.currentRss} '
          'max_rss_bytes=${ProcessInfo.maxRss}',
        );
      },
    );

    testWidgets(
      'Historical Archive Smoke Test: Year 3 career + Year 1 & Year 2 archives with digest verification',
      (tester) async {
        final archiveDir = Directory('${testRootDir.path}/archive_y3_smoke')
          ..createSync(recursive: true);
        final storage = FileGmCareerStorage(directoryPath: archiveDir.path);

        final setup = const CareerSetupService().generate(
          const CareerSetupRequest(
            selectedTeamId: TeamId('team-1'),
            selectedSituation: FranchiseSituation.tanking,
            seed: 20261028,
          ),
        );
        final y1Initial = GmCareer.fromSetupResult(
          setup,
          id: 'd3c-android-y3-career',
        );
        final y1Completed = completeSeasonFromSetup(y1Initial);

        final y3WriteSw = Stopwatch();
        final ctrl = GmCareerController(storage: storage);
        try {
          // Persist Year 1 and roll over to Year 2 (persists Year 1 archive)
          await storage.write(GmCareerCodec.encode(y1Completed));
          await ctrl.loadCareer();
          await ctrl.continueToNextSeason(confirmed: true);
          expect(ctrl.career!.currentYear, 2);

          // Complete Year 2 and roll over to Year 3 (persists Year 2 archive)
          final y2Completed = completeSeasonFromSetup(ctrl.career!);
          await storage.write(GmCareerCodec.encode(y2Completed));
          await ctrl.loadCareer();

          y3WriteSw.start();
          await ctrl.continueToNextSeason(confirmed: true);
          y3WriteSw.stop();
          expect(ctrl.career!.currentYear, 3);
        } finally {
          ctrl.dispose();
        }

        // Fresh controller & storage verification
        final verifyStorage = FileGmCareerStorage(
          directoryPath: archiveDir.path,
        );
        final verifyCtrl = GmCareerController(storage: verifyStorage);
        try {
          await verifyCtrl.loadCareer();
          final y3 = verifyCtrl.career!;
          expect(y3.id, 'd3c-android-y3-career');
          expect(y3.currentYear, 3);
          expect(y3.seasonHistory.length, 2);
          expect(y3.seasonHistory[0].seasonYear, 1);
          expect(y3.seasonHistory[1].seasonYear, 2);

          expect(await verifyStorage.hasArchive(seasonYear: 1), isTrue);
          expect(await verifyStorage.hasArchive(seasonYear: 2), isTrue);

          final arch1Sw = Stopwatch()..start();
          final arch1Json = await verifyStorage.readArchive(seasonYear: 1);
          expect(arch1Json, isNotNull);
          final arch1Digest = SeasonArchiveCodec.digestOf(arch1Json!);
          final arch1 = SeasonArchiveCodec.decodeAndVerify(
            arch1Json,
            expectedDigest: y3.seasonHistory[0].archiveDigest,
            expectedCareerId: y3.id,
            expectedSeasonYear: 1,
            expectedRecord: y3.seasonHistory[0],
          );
          arch1Sw.stop();

          final arch2Sw = Stopwatch()..start();
          final arch2Json = await verifyStorage.readArchive(seasonYear: 2);
          expect(arch2Json, isNotNull);
          final arch2Digest = SeasonArchiveCodec.digestOf(arch2Json!);
          final arch2 = SeasonArchiveCodec.decodeAndVerify(
            arch2Json,
            expectedDigest: y3.seasonHistory[1].archiveDigest,
            expectedCareerId: y3.id,
            expectedSeasonYear: 2,
            expectedRecord: y3.seasonHistory[1],
          );
          arch2Sw.stop();

          expect(arch1.careerId, y3.id);
          expect(arch2.careerId, y3.id);
          expect(arch1.seasonYear, 1);
          expect(arch2.seasonYear, 2);
          expect(arch1Digest, y3.seasonHistory[0].archiveDigest);
          expect(arch2Digest, y3.seasonHistory[1].archiveDigest);
          expect(
            arch1.playoffState.champion,
            y3.seasonHistory[0].championTeamId,
          );
          expect(
            arch2.playoffState.champion,
            y3.seasonHistory[1].championTeamId,
          );

          final y3Bytes = File(verifyStorage.resolvePath()).lengthSync();
          final arch1Bytes = File(
            verifyStorage.resolveArchivePath(1),
          ).lengthSync();
          final arch2Bytes = File(
            verifyStorage.resolveArchivePath(2),
          ).lengthSync();

          // ignore: avoid_print
          print(
            '[D3C-T01] [DEBUG] y3_rollover_write_ms=${y3WriteSw.elapsedMilliseconds} '
            'arch1_read_validate_ms=${arch1Sw.elapsedMilliseconds} '
            'arch2_read_validate_ms=${arch2Sw.elapsedMilliseconds} '
            'y3_bytes=$y3Bytes arch1_bytes=$arch1Bytes arch2_bytes=$arch2Bytes '
            'rss_bytes=${ProcessInfo.currentRss} max_rss_bytes=${ProcessInfo.maxRss}',
          );
        } finally {
          verifyCtrl.dispose();
        }
      },
    );
  });
}
