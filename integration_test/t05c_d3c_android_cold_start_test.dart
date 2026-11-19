import 'dart:convert';
import 'dart:io';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simulation_core/simulation_core.dart';

import 'support/d3c_fixture_helper.dart';

const String _coldStartPhase = String.fromEnvironment(
  'D3C_COLD_START_PHASE',
  defaultValue: 'write',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android Cold-Start Verification (phase=$_coldStartPhase)', (
    tester,
  ) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final coldDir = Directory('${docsDir.path}/d3c_t01_cold_start');
    final manifestFile = File('${coldDir.path}/cold_start_manifest.json');

    if (_coldStartPhase == 'write') {
      if (coldDir.existsSync()) {
        coldDir.deleteSync(recursive: true);
      }
      coldDir.createSync(recursive: true);

      final storage = FileGmCareerStorage(directoryPath: coldDir.path);
      final setup = const CareerSetupService().generate(
        const CareerSetupRequest(
          selectedTeamId: TeamId('team-1'),
          selectedSituation: FranchiseSituation.tanking,
          seed: 20261028,
        ),
      );
      final y1Initial = GmCareer.fromSetupResult(
        setup,
        id: 'd3c-android-cold-start',
      );
      final y1Completed = completeSeasonFromSetup(y1Initial);

      final ctrl = GmCareerController(storage: storage);
      try {
        await storage.write(GmCareerCodec.encode(y1Completed));
        await ctrl.loadCareer();
        await ctrl.continueToNextSeason(confirmed: true);
        expect(ctrl.career!.currentYear, 2);

        final y2Completed = completeSeasonFromSetup(ctrl.career!);
        await storage.write(GmCareerCodec.encode(y2Completed));
        await ctrl.loadCareer();
        await ctrl.continueToNextSeason(confirmed: true);
        expect(ctrl.career!.currentYear, 3);
      } finally {
        ctrl.dispose();
      }

      final verifyStorage = FileGmCareerStorage(directoryPath: coldDir.path);
      final loaded = GmCareerCodec.decode((await verifyStorage.read())!);
      final arch1Json = await verifyStorage.readArchive(seasonYear: 1);
      final arch2Json = await verifyStorage.readArchive(seasonYear: 2);
      expect(arch1Json, isNotNull);
      expect(arch2Json, isNotNull);

      final arch1Digest = SeasonArchiveCodec.digestOf(arch1Json!);
      final arch2Digest = SeasonArchiveCodec.digestOf(arch2Json!);

      await manifestFile.writeAsString(
        jsonEncode({
          'careerId': loaded.id,
          'currentYear': loaded.currentYear,
          'userFranchiseId': loaded.userFranchiseId.value,
          'arch1Digest': arch1Digest,
          'arch2Digest': arch2Digest,
        }),
        flush: true,
      );

      // ignore: avoid_print
      print(
        '[D3C-T01] [COLD_START_WRITE] dir=${coldDir.path} '
        'careerId=${loaded.id} currentYear=${loaded.currentYear} '
        'arch1Digest=$arch1Digest arch2Digest=$arch2Digest',
      );
    } else if (_coldStartPhase == 'verify') {
      expect(
        manifestFile.existsSync(),
        isTrue,
        reason:
            'cold_start_manifest.json missing; app data was cleared or write phase did not run',
      );
      final manifest =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;

      final storage = FileGmCareerStorage(directoryPath: coldDir.path);
      final ctrl = GmCareerController(storage: storage);
      try {
        await ctrl.loadCareer();
        final career = ctrl.career;
        expect(ctrl.errorMessage, isNull);
        expect(ctrl.draftRecoveryRequired, isFalse);
        expect(career, isNotNull);
        expect(career!.id, manifest['careerId']);
        expect(career.currentYear, manifest['currentYear']);
        expect(career.phase, CareerPhase.openingOffseason);
        expect(career.userFranchiseId.value, manifest['userFranchiseId']);
        expect(career.seasonHistory.length, 2);
        expect(career.seasonSettlements.length, 2);
        expect(career.marketHistory.length, 2);

        final arch1Json = await storage.readArchive(seasonYear: 1);
        final arch2Json = await storage.readArchive(seasonYear: 2);
        expect(arch1Json, isNotNull);
        expect(arch2Json, isNotNull);

        final arch1 = SeasonArchiveCodec.decodeAndVerify(
          arch1Json!,
          expectedDigest: manifest['arch1Digest'] as String,
          expectedCareerId: career.id,
          expectedSeasonYear: 1,
          expectedRecord: career.seasonHistory[0],
        );
        final arch2 = SeasonArchiveCodec.decodeAndVerify(
          arch2Json!,
          expectedDigest: manifest['arch2Digest'] as String,
          expectedCareerId: career.id,
          expectedSeasonYear: 2,
          expectedRecord: career.seasonHistory[1],
        );

        expect(arch1.careerId, career.id);
        expect(arch2.careerId, career.id);
        expect(
          arch1.playoffState.champion,
          career.seasonHistory[0].championTeamId,
        );
        expect(
          arch2.playoffState.champion,
          career.seasonHistory[1].championTeamId,
        );

        // ignore: avoid_print
        print(
          '[D3C-T01] [COLD_START_VERIFY] PASS careerId=${career.id} '
          'currentYear=${career.currentYear} '
          'arch1Digest=${career.seasonHistory[0].archiveDigest} '
          'arch2Digest=${career.seasonHistory[1].archiveDigest}',
        );
      } finally {
        ctrl.dispose();
        try {
          if (coldDir.existsSync()) {
            coldDir.deleteSync(recursive: true);
          }
        } catch (_) {}
      }
    } else {
      fail('Unknown D3C_COLD_START_PHASE: $_coldStartPhase');
    }
  });
}
