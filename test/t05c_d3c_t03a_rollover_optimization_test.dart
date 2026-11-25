import 'dart:convert';
import 'dart:io';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

import '../integration_test/support/d3c_fixture_helper.dart';

String _sha256(String s) => sha256.convert(utf8.encode(s)).toString();

void main() {
  // Rebaselined for 6664ceb (M009-T05C-T05B AI free-agent offer policy), which
  // changes the fixture's offseason signings. Pre-6664ceb values reproduced at
  // 2ab8e25: aadfbd75…, bfc2440e…, 4395386f…, 2b53db23…; 298e443 is unchanged.
  const baselineArch1Sha =
      '73507ba699b903cf4c89e7245142d3ef44dd3bcf346e23d004ef54b4f4f10b9f';
  const baselineY2CareerSha =
      '30bbf735f40e836c70b140006683e47f86763b5d01a58964d9207c8fc71d014c';
  const baselineArch2Sha =
      'efd8aaf999ff1ea6f4008f2ccf58ea20ff9811dbb89a586da00febc96c67ff06';
  const baselineY3CareerSha =
      'd900d14c8820dcd179ccff5dc766bdd59ca566b4dd675e88edc92671e0878f38';

  late GmCareer y1Completed;
  late GmCareer y2Completed;

  setUpAll(() {
    final setup = const CareerSetupService().generate(
      const CareerSetupRequest(
        selectedTeamId: TeamId('team-1'),
        selectedSituation: FranchiseSituation.tanking,
        seed: 20261028,
      ),
    );
    final y1Initial = GmCareer.fromSetupResult(setup, id: 'd3c-t03a-baseline');
    y1Completed = completeSeasonFromSetup(y1Initial);
    final y2Initial = const SeasonRolloverService()
        .prepareArchiveAndRollover(current: y1Completed)
        .rolloverResult
        .nextCareer;
    y2Completed = completeSeasonFromSetup(y2Initial);
  });

  test(
    'Optimized rollover produces byte-identical Y1->Y2->Y3 outputs and SHA-256 digests',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      // 1. rolloverWithPlans path
      final arch1 = SeasonArchive.fromCareer(y1Completed);
      final encArch1 = SeasonArchiveCodec.encodeWithDigest(arch1);
      final rec1 = arch1.toHistoryRecord(encArch1.digest);
      final y2ViaRollover = const SeasonRolloverService()
          .rolloverWithPlans(current: y1Completed, archiveRecord: rec1)
          .nextCareer;
      expect(encArch1.digest, baselineArch1Sha);
      expect(_sha256(GmCareerCodec.encode(y2ViaRollover)), baselineY2CareerSha);
      expect(rec1.championTeamId, const TeamId('team-1'));

      // 2. prepareArchiveAndRollover path
      final prep2 = const SeasonRolloverService().prepareArchiveAndRollover(
        current: y2Completed,
      );
      expect(prep2.archiveDigest, baselineArch2Sha);
      expect(
        _sha256(GmCareerCodec.encode(prep2.rolloverResult.nextCareer)),
        baselineY3CareerSha,
      );

      // 3. Full controller continueToNextSeason path with real FileGmCareerStorage
      final tempDir = Directory.systemTemp.createTempSync('d3c_t03a_ctrl_');
      try {
        final storage = FileGmCareerStorage(directoryPath: tempDir.path);
        await storage.write(GmCareerCodec.encode(y2Completed));
        final ctrl = GmCareerController(storage: storage);
        try {
          await ctrl.loadCareer();
          await ctrl.continueToNextSeason(confirmed: true);
          final y3 = ctrl.career!;
          expect(y3.currentYear, 3);
          expect(y3.phase, CareerPhase.openingOffseason);
          expect(y3.league.teams.length, 30);
          expect(y3.finances.contracts.length, 118);
          expect(y3.finances.guaranteedLiabilities.length, 0);
          expect(y3.retiredPlayers.length, 4);
          expect(y3.seasonSettlements.length, 2);
          expect(y3.marketHistory.length, 2);
          expect(y3.seasonHistory.length, 2);
          // 6664ceb: one carried draft right (40 -> 39) now enters the free-agent
          // pool (408 -> 409); combined total remains 448.
          expect(y3.careerDraftRights.length, 39);
          expect(y3.freeAgentPool.entries.length, 409);
          expect(_sha256(GmCareerCodec.encode(y3)), baselineY3CareerSha);
          final storedArch2 = await storage.readArchive(seasonYear: 2);
          expect(storedArch2, isNotNull);
          expect(SeasonArchiveCodec.digestOf(storedArch2!), baselineArch2Sha);
        } finally {
          ctrl.dispose();
        }
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    },
  );

  test(
    'Adversarial validation: optimized entry points still reject invalid states and forged records',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      const service = SeasonRolloverService();
      const planner = SeasonRolloverPlanner();
      final prep1 = service.prepareArchiveAndRollover(current: y1Completed);

      // Forged digest / mismatched SeasonHistoryRecord
      final forgedRecord = SeasonHistoryRecord(
        seasonYear: prep1.archiveRecord.seasonYear,
        seasonId: prep1.archiveRecord.seasonId,
        championTeamId: prep1.archiveRecord.championTeamId,
        regularSeasonStandings: prep1.archiveRecord.regularSeasonStandings,
        playInOutcome: prep1.archiveRecord.playInOutcome,
        playoffSeries: prep1.archiveRecord.playoffSeries,
        archiveId: prep1.archiveRecord.archiveId,
        archiveDigest: '0' * 64,
      );
      expect(
        () => service.rolloverWithPlans(
          current: y1Completed,
          archiveRecord: forgedRecord,
        ),
        throwsStateError,
      );

      // Duplicate historical record rejected at GmCareer invariant boundary
      expect(
        () => y1Completed.copyWith(seasonHistory: [prep1.archiveRecord]),
        throwsFormatException,
      );

      // Incomplete playoffs / missing championship
      final incompletePlayoffs = y1Completed.copyWith(
        phase: CareerPhase.regularSeason,
        playInState: null,
        playoffState: null,
      );
      expect(
        () => service.prepareArchiveAndRollover(current: incompletePlayoffs),
        throwsStateError,
      );
      expect(() => planner.plan(incompletePlayoffs), throwsStateError);

      // Tampered game fingerprint inside completed season
      final rs = y1Completed.regularSeasonState!;
      final firstKey = rs.gameResults.keys.first;
      final firstGame = rs.gameResults[firstKey]!;
      final tamperedResults = Map<String, RegularSeasonGameResult>.of(
        rs.gameResults,
      );
      tamperedResults[firstKey] = RegularSeasonGameResult(
        fixtureId: firstGame.fixtureId,
        seasonId: firstGame.seasonId,
        seasonYear: firstGame.seasonYear,
        homeTeamId: firstGame.homeTeamId,
        awayTeamId: firstGame.awayTeamId,
        gameSeed: firstGame.gameSeed,
        inputFingerprint: 'f' * 64,
        simulationVersion: firstGame.simulationVersion,
        rulesVersion: firstGame.rulesVersion,
        eventSchemaVersion: firstGame.eventSchemaVersion,
        prngImplementationId: firstGame.prngImplementationId,
        fingerprintVersion: firstGame.fingerprintVersion,
        coreEngineVersion: firstGame.coreEngineVersion,
        leagueSchemaVersion: firstGame.leagueSchemaVersion,
        inputEvidence: firstGame.inputEvidence,
        periodsPlayed: firstGame.periodsPlayed,
        summary: firstGame.summary,
      );
      expect(
        () => y1Completed.copyWith(
          regularSeasonState: rs.copyWith(gameResults: tamperedResults),
        ),
        throwsFormatException,
      );

      // Persistence boundary: writeArchive still rejects malformed JSON, wrong year, wrong digest
      final tempDir = Directory.systemTemp.createTempSync('d3c_t03a_adv_');
      try {
        final storage = FileGmCareerStorage(directoryPath: tempDir.path);
        await expectLater(
          storage.writeArchive(
            seasonYear: 1,
            archiveJson: '{"malformed":',
            expectedDigest: SeasonArchiveCodec.digestOf('{"malformed":'),
          ),
          throwsA(isA<GmCareerStorageException>()),
        );
        await expectLater(
          storage.writeArchive(
            seasonYear: 1,
            archiveJson: prep1.archiveJson,
            expectedDigest: '1' * 64,
          ),
          throwsA(isA<GmCareerStorageException>()),
        );
        await expectLater(
          storage.writeArchive(
            seasonYear: 2,
            archiveJson: prep1.archiveJson,
            expectedDigest: prep1.archiveDigest,
          ),
          throwsA(isA<GmCareerStorageException>()),
        );
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    },
  );
}
