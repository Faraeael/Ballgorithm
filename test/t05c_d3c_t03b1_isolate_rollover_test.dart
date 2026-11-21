import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/rollover_isolate_workers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

import '../integration_test/support/d3c_fixture_helper.dart';

String _sha256(String s) => sha256.convert(utf8.encode(s)).toString();

final class _FailingArchiveWriteStorage extends FileGmCareerStorage {
  _FailingArchiveWriteStorage({required super.directoryPath});

  @override
  Future<void> writeArchive({
    required int seasonYear,
    required String archiveJson,
    required String expectedDigest,
    String slot = 'default',
  }) async {
    throw const GmCareerStorageException('Injected archive write failure');
  }
}

final class _FailingActiveWriteStorage extends FileGmCareerStorage {
  _FailingActiveWriteStorage({required super.directoryPath});

  bool failActiveWrite = true;

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    if (failActiveWrite) {
      throw const GmCareerStorageException('Injected active write failure');
    }
    await super.write(data, slot: slot);
  }
}

void main() {
  const baselineArch1Sha =
      'aadfbd7555ece1ddb3c4734c54575a4b981dc9c8943e9c361d8daf8f9699deae';
  const baselineY2CareerSha =
      'bfc2440eeed36adb253e991b73c756c2952be10d9559bc20aac71c63944d9a2e';
  const baselineArch2Sha =
      '4395386fb9ab4699fb1fc7fc1adf94f91869532e5b4485d8c22553f91b1d3bb9';
  const baselineY3CareerSha =
      '2b53db23184b3e1a7e63501fc3025a3fa01e3c8db338a6ea107b084caf5449eb';

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
    'Workers execute on a background isolate and controller produces byte-identical Y1->Y2->Y3 outputs',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final mainIsolateHash = identityHashCode(Isolate.current);
      final workerIsolateHashes = <int>{};

      // Verify compute() actually spawns/uses a different isolate for workers.
      final prepOut = await compute((RolloverPrepareRequest req) {
        return (
          isolateHash: identityHashCode(Isolate.current),
          output: prepareSeasonRolloverWorker(req),
        );
      }, RolloverPrepareRequest(y1Completed));
      workerIsolateHashes.add(prepOut.isolateHash);
      expect(prepOut.isolateHash, isNot(mainIsolateHash));
      expect(prepOut.output.archiveDigest, baselineArch1Sha);
      expect(_sha256(prepOut.output.encodedNextCareer), baselineY2CareerSha);

      final verifyIsolateHash = await compute(
        (ArchiveVerifyRequest req) {
          verifySeasonArchiveWorker(req);
          return identityHashCode(Isolate.current);
        },
        ArchiveVerifyRequest(
          archiveJson: prepOut.output.archiveJson,
          expectedDigest: prepOut.output.archiveDigest,
          expectedSeasonYear: 1,
        ),
      );
      workerIsolateHashes.add(verifyIsolateHash);
      expect(verifyIsolateHash, isNot(mainIsolateHash));

      // Full controller Y1 -> Y2 -> Y3 via continueToNextSeason
      final tempDir = Directory.systemTemp.createTempSync('d3c_t03b1_eq_');
      try {
        final storage = FileGmCareerStorage(directoryPath: tempDir.path);
        await storage.write(GmCareerCodec.encode(y1Completed));
        final ctrl = GmCareerController(storage: storage);
        try {
          await ctrl.loadCareer();
          await ctrl.continueToNextSeason(confirmed: true);
          expect(ctrl.career!.currentYear, 2);
          expect(
            _sha256(GmCareerCodec.encode(ctrl.career!)),
            baselineY2CareerSha,
          );
          final storedArch1 = await storage.readArchive(seasonYear: 1);
          expect(SeasonArchiveCodec.digestOf(storedArch1!), baselineArch1Sha);

          // Advance to completed Y2 and roll over to Y3
          await storage.write(GmCareerCodec.encode(y2Completed));
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
          expect(y3.careerDraftRights.length, 40);
          expect(y3.freeAgentPool.entries.length, 408);
          expect(_sha256(GmCareerCodec.encode(y3)), baselineY3CareerSha);
          final storedArch2 = await storage.readArchive(seasonYear: 2);
          expect(SeasonArchiveCodec.digestOf(storedArch2!), baselineArch2Sha);
        } finally {
          ctrl.dispose();
        }
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Worker computation and transfer failures do not set draftRecoveryRequired or fall back to main isolate',
    () async {
      final tempDir = Directory.systemTemp.createTempSync('d3c_t03b1_werr_');
      try {
        final storage = FileGmCareerStorage(directoryPath: tempDir.path);
        await storage.write(GmCareerCodec.encode(y1Completed));

        // 1. Worker computation failure
        final ctrlComputeFail = GmCareerController(
          storage: storage,
          prepareRolloverWorker: (_) async {
            throw StateError('Simulated worker computation failure');
          },
        );
        try {
          await ctrlComputeFail.loadCareer();
          await expectLater(
            ctrlComputeFail.continueToNextSeason(confirmed: true),
            throwsStateError,
          );
          expect(ctrlComputeFail.draftRecoveryRequired, isFalse);
          expect(ctrlComputeFail.isLoading, isFalse);
          expect(
            ctrlComputeFail.errorMessage,
            contains('Simulated worker computation failure'),
          );
          expect(ctrlComputeFail.career!.currentYear, 1);
          expect(await storage.hasArchive(seasonYear: 1), isFalse);
        } finally {
          ctrlComputeFail.dispose();
        }

        // 2. Worker transfer failure (simulated unsendable isolate message error)
        final ctrlTransferFail = GmCareerController(
          storage: storage,
          prepareRolloverWorker: (_) async {
            throw ArgumentError('Illegal argument in isolate message');
          },
        );
        try {
          await ctrlTransferFail.loadCareer();
          await expectLater(
            ctrlTransferFail.continueToNextSeason(confirmed: true),
            throwsArgumentError,
          );
          expect(ctrlTransferFail.draftRecoveryRequired, isFalse);
          expect(ctrlTransferFail.isLoading, isFalse);
          expect(
            ctrlTransferFail.errorMessage,
            contains('Illegal argument in isolate message'),
          );
          expect(ctrlTransferFail.career!.currentYear, 1);
        } finally {
          ctrlTransferFail.dispose();
        }

        // 3. Real isolate transfer failure with unsendable ReceivePort captured in closure
        final port = ReceivePort();
        addTearDown(port.close);
        await expectLater(
          compute((_) => port.sendPort.toString(), null).then((_) {
            // Verify sending ReceivePort itself across isolate throws ArgumentError
            return compute((ReceivePort p) => p.hashCode, port);
          }),
          throwsArgumentError,
        );
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Filesystem failure semantics: failed archive write and failed active write set draftRecoveryRequired and allow retry',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final tempDirA = Directory.systemTemp.createTempSync(
        'd3c_t03b1_archfail_',
      );
      final tempDirB = Directory.systemTemp.createTempSync(
        'd3c_t03b1_actfail_',
      );
      try {
        // 1. Failed archive write
        final failArchStorage = _FailingArchiveWriteStorage(
          directoryPath: tempDirA.path,
        );
        await failArchStorage.write(GmCareerCodec.encode(y1Completed));
        final ctrlA = GmCareerController(storage: failArchStorage);
        try {
          await ctrlA.loadCareer();
          await expectLater(
            ctrlA.continueToNextSeason(confirmed: true),
            throwsA(isA<GmCareerStorageException>()),
          );
          expect(ctrlA.draftRecoveryRequired, isTrue);
          expect(ctrlA.career!.currentYear, 1);
          expect(ctrlA.isLoading, isFalse);
        } finally {
          ctrlA.dispose();
        }

        // 2. Failed active write after archive write succeeds -> retry succeeds after reload
        final failActiveStorage = _FailingActiveWriteStorage(
          directoryPath: tempDirB.path,
        );
        failActiveStorage.failActiveWrite = false;
        await failActiveStorage.write(GmCareerCodec.encode(y1Completed));
        failActiveStorage.failActiveWrite = true;
        final ctrlB = GmCareerController(storage: failActiveStorage);
        try {
          await ctrlB.loadCareer();
          await expectLater(
            ctrlB.continueToNextSeason(confirmed: true),
            throwsA(isA<GmCareerStorageException>()),
          );
          expect(ctrlB.draftRecoveryRequired, isTrue);
          expect(ctrlB.career!.currentYear, 1);
          expect(await failActiveStorage.hasArchive(seasonYear: 1), isTrue);

          // Reload clears recovery guard and idempotent archive retry succeeds
          failActiveStorage.failActiveWrite = false;
          await ctrlB.loadCareer();
          expect(ctrlB.draftRecoveryRequired, isFalse);
          await ctrlB.continueToNextSeason(confirmed: true);
          expect(ctrlB.career!.currentYear, 2);
          expect(ctrlB.career!.seasonHistory.length, 1);
        } finally {
          ctrlB.dispose();
        }
      } finally {
        if (tempDirA.existsSync()) tempDirA.deleteSync(recursive: true);
        if (tempDirB.existsSync()) tempDirB.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Command serialization: consecutive rollovers, queued behind another command, and disposal while queued',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final tempDir = Directory.systemTemp.createTempSync('d3c_t03b1_race_');
      try {
        final storage = FileGmCareerStorage(directoryPath: tempDir.path);
        await storage.write(GmCareerCodec.encode(y1Completed));

        // 1. Consecutive rollover commands: first succeeds, second fails cleanly without duplicate history
        final workerStarted = Completer<void>();
        final allowWorkerFinish = Completer<void>();
        var workerCalls = 0;
        final ctrl = GmCareerController(
          storage: storage,
          prepareRolloverWorker: (req) async {
            workerCalls++;
            if (workerCalls == 1 && !workerStarted.isCompleted) {
              workerStarted.complete();
              await allowWorkerFinish.future;
            }
            return prepareSeasonRolloverWorker(req);
          },
        );
        try {
          await ctrl.loadCareer();
          final firstFuture = ctrl.continueToNextSeason(confirmed: true);
          await workerStarted.future;
          final secondFuture = ctrl.continueToNextSeason(confirmed: true);
          allowWorkerFinish.complete();

          await firstFuture;
          await expectLater(secondFuture, throwsStateError);
          expect(ctrl.career!.currentYear, 2);
          expect(ctrl.career!.seasonHistory.length, 1);
          expect(workerCalls, 1);
        } finally {
          ctrl.dispose();
        }

        // 2. Rollover queued behind loadCareer()
        final ctrl2 = GmCareerController(storage: storage);
        try {
          // Storage currently holds Year 2 (not completed), so loadCareer then rollover rejects cleanly
          final f1 = ctrl2.loadCareer();
          final f2 = ctrl2.continueToNextSeason(confirmed: true);
          await f1;
          await expectLater(f2, throwsStateError);
          expect(ctrl2.career!.currentYear, 2);
        } finally {
          ctrl2.dispose();
        }

        // 3. Disposal while queued behind a running worker
        final disposeDir = Directory('${tempDir.path}/dispose_test')
          ..createSync(recursive: true);
        final disposeStorage = FileGmCareerStorage(
          directoryPath: disposeDir.path,
        );
        await disposeStorage.write(GmCareerCodec.encode(y1Completed));
        final started3 = Completer<void>();
        final release3 = Completer<void>();
        final ctrl3 = GmCareerController(
          storage: disposeStorage,
          prepareRolloverWorker: (req) async {
            if (!started3.isCompleted) started3.complete();
            await release3.future;
            return prepareSeasonRolloverWorker(req);
          },
        );
        await ctrl3.loadCareer();
        final runningFuture = ctrl3.continueToNextSeason(confirmed: true);
        await started3.future;
        final queuedFuture = ctrl3.continueToNextSeason(confirmed: true);
        ctrl3.dispose();
        release3.complete();

        await expectLater(runningFuture, throwsStateError);
        await expectLater(queuedFuture, throwsStateError);
        // Active save on disk must remain Year 1 (not mutated after disposal)
        final reloaded = GmCareerCodec.decode((await disposeStorage.read())!);
        expect(reloaded.currentYear, 1);
        expect(await disposeStorage.hasArchive(seasonYear: 1), isFalse);
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Negative boundaries: missing confirmation, incomplete season, and archive rejection',
    () async {
      final tempDir = Directory.systemTemp.createTempSync('d3c_t03b1_neg_');
      try {
        final storage = FileGmCareerStorage(directoryPath: tempDir.path);
        await storage.write(GmCareerCodec.encode(y1Completed));
        final ctrl = GmCareerController(storage: storage);
        try {
          await ctrl.loadCareer();
          await expectLater(
            ctrl.continueToNextSeason(confirmed: false),
            throwsStateError,
          );

          final incomplete = y1Completed.copyWith(
            phase: CareerPhase.regularSeason,
            playInState: null,
            playoffState: null,
          );
          await storage.write(GmCareerCodec.encode(incomplete));
          await ctrl.loadCareer();
          await expectLater(
            ctrl.continueToNextSeason(confirmed: true),
            throwsStateError,
          );
        } finally {
          ctrl.dispose();
        }

        // Direct storage writeArchive negative checks via isolate workers
        final prep = prepareSeasonRolloverWorker(
          RolloverPrepareRequest(y1Completed),
        );
        await expectLater(
          storage.writeArchive(
            seasonYear: 1,
            archiveJson: prep.archiveJson,
            expectedDigest: '0' * 64,
          ),
          throwsA(isA<GmCareerStorageException>()),
        );
        await expectLater(
          storage.writeArchive(
            seasonYear: 2,
            archiveJson: prep.archiveJson,
            expectedDigest: prep.archiveDigest,
          ),
          throwsA(isA<GmCareerStorageException>()),
        );
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    },
  );
}
