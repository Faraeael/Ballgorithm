import 'dart:convert';
import 'dart:io';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

final class _FaultInjectingFileOps implements CareerStorageFileOps {
  FileSystemException? Function(File file)? failOnExists;
  bool Function(File source, String newPath)? failOnRename;
  bool Function(File source, String newPath)? failOnCopy;
  bool Function(File file)? failOnDelete;
  bool Function(File file)? failOnWrite;
  String? partialWriteContentBeforeFail;
  int transientErrorsRemaining = 0;
  int renameCalls = 0;

  @override
  Future<bool> exists(File file) async {
    final err = failOnExists?.call(file);
    if (err != null) throw err;
    return file.exists();
  }

  @override
  Future<int> length(File file) => file.length();

  @override
  Future<String> readAsString(File file) => file.readAsString();

  @override
  Future<void> writeAsString(
    File file,
    String contents, {
    bool flush = false,
  }) async {
    if (failOnWrite?.call(file) == true) {
      if (partialWriteContentBeforeFail != null) {
        await file.writeAsString(partialWriteContentBeforeFail!, flush: flush);
      }
      throw FileSystemException('Injected write failure', file.path);
    }
    await file.writeAsString(contents, flush: flush);
  }

  @override
  Future<void> rename(File source, String newPath) async {
    renameCalls++;
    if (transientErrorsRemaining > 0) {
      transientErrorsRemaining--;
      throw FileSystemException(
        'Transient Windows sharing violation',
        source.path,
        const OSError('Sharing violation', 32),
      );
    }
    if (failOnRename?.call(source, newPath) == true) {
      throw FileSystemException(
        'Injected rename failure',
        source.path,
        const OSError('Access denied', 5),
      );
    }
    await source.rename(newPath);
  }

  @override
  Future<void> copy(File source, String newPath) async {
    if (failOnCopy?.call(source, newPath) == true) {
      throw FileSystemException('Injected copy failure', source.path);
    }
    await source.copy(newPath);
  }

  @override
  Future<void> delete(File file) async {
    if (failOnDelete?.call(file) == true) {
      throw FileSystemException('Injected delete failure', file.path);
    }
    await file.delete();
  }

  @override
  Future<void> createParentDir(File file) =>
      file.parent.create(recursive: true);
}

void main() {
  late Directory rootTempDir;
  late GmCareer careerA;
  late GmCareer careerB;
  late String jsonA;
  late String jsonB;

  setUpAll(() {
    rootTempDir = Directory.systemTemp.createTempSync('t05c_d3b_active_');
    final setup = const CareerSetupService().generate(
      const CareerSetupRequest(
        selectedTeamId: TeamId('team-1'),
        selectedSituation: FranchiseSituation.tanking,
        seed: 20261028,
      ),
    );
    careerA = GmCareer.fromSetupResult(setup, id: 'd3b-career-a');
    careerB = const DraftExecutionService().startDraft(careerA);
    jsonA = GmCareerCodec.encode(careerA);
    jsonB = GmCareerCodec.encode(careerB);
  });

  tearDownAll(() {
    try {
      if (rootTempDir.existsSync()) {
        rootTempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  FileGmCareerStorage makeStorage(
    String name, {
    CareerStorageFileOps? fileOps,
  }) {
    final dir = Directory('${rootTempDir.path}/$name')
      ..createSync(recursive: true);
    return FileGmCareerStorage(directoryPath: dir.path, fileOps: fileOps);
  }

  group('M009-T05C-C2-D3B-T01 Active Career Save Durability', () {
    test(
      '1-3, 17: Valid active save always wins over stale .bak, corrupt .bak, and corrupt .tmp',
      () async {
        // 1. Valid active (B) with stale valid backup (A)
        final s1 = makeStorage('case_1');
        await s1.write(jsonB);
        File('${s1.resolvePath()}.bak').writeAsStringSync(jsonA);
        expect(await s1.read(), jsonB);
        expect(await s1.recoverBackup(), isNull);
        expect(File(s1.resolvePath()).readAsStringSync(), jsonB);

        // 2. Valid active (B) with corrupt backup
        final s2 = makeStorage('case_2');
        await s2.write(jsonB);
        File('${s2.resolvePath()}.bak').writeAsStringSync('{"corrupt":');
        expect(await s2.read(), jsonB);
        expect(await s2.recoverBackup(), isNull);

        // 3. Valid active (B) with corrupt temp
        final s3 = makeStorage('case_3');
        await s3.write(jsonB);
        File(
          '${s3.resolvePath()}.tmp',
        ).writeAsStringSync('{"schemaVersion":25');
        expect(await s3.read(), jsonB);
      },
    );

    test(
      '4-6, 16: Missing active recovery policy (.bak > .tmp, preserves alternate, idempotent)',
      () async {
        // 4. Active missing, valid backup
        final s4 = makeStorage('case_4');
        File('${s4.resolvePath()}.bak').writeAsStringSync(jsonA);
        expect(await s4.read(), jsonA);
        expect(File(s4.resolvePath()).readAsStringSync(), jsonA);
        // 16. Repeated recovery is idempotent
        expect(await s4.read(), jsonA);

        // 5. Active missing, valid temp only
        final s5 = makeStorage('case_5');
        File('${s5.resolvePath()}.tmp').writeAsStringSync(jsonB);
        expect(await s5.read(), jsonB);
        expect(File(s5.resolvePath()).readAsStringSync(), jsonB);

        // 6. Active missing, both .bak (A) and .tmp (B) valid -> conservative .bak wins & .tmp preserved
        final s6 = makeStorage('case_6');
        File('${s6.resolvePath()}.bak').writeAsStringSync(jsonA);
        File('${s6.resolvePath()}.tmp').writeAsStringSync(jsonB);
        expect(await s6.read(), jsonA);
        expect(File('${s6.resolvePath()}.tmp').existsSync(), isTrue);
        expect(File('${s6.resolvePath()}.tmp').readAsStringSync(), jsonB);
      },
    );

    test(
      '7-9, 18-19: Corrupt active recovery & rejection of invalid .bak/.tmp',
      () async {
        // 7. Active corrupt, valid backup -> recovers backup and quarantines corrupt active
        final s7 = makeStorage('case_7');
        File(s7.resolvePath()).writeAsStringSync('{bad json');
        File('${s7.resolvePath()}.bak').writeAsStringSync(jsonA);
        expect(await s7.read(), jsonA);
        expect(File(s7.resolvePath()).readAsStringSync(), jsonA);

        // 8 & 18. Active corrupt, corrupt backup (nonempty but invalid GmCareer) -> neither promoted
        final s8 = makeStorage('case_8');
        File(s8.resolvePath()).writeAsStringSync('{bad active');
        File(
          '${s8.resolvePath()}.bak',
        ).writeAsStringSync('{"notACareer":true}');
        expect(await s8.read(), '{bad active');
        expect(await s8.recoverBackup(), isNull);
        expect(File(s8.resolvePath()).readAsStringSync(), '{bad active');

        // 9 & 19. Active corrupt, corrupt temp -> invalid temp never becomes active
        final s9 = makeStorage('case_9');
        File(s9.resolvePath()).writeAsStringSync('{bad active 2');
        File(
          '${s9.resolvePath()}.tmp',
        ).writeAsStringSync('{"schemaVersion":25}');
        expect(await s9.read(), '{bad active 2');
        expect(File(s9.resolvePath()).readAsStringSync(), '{bad active 2');
      },
    );

    test(
      '10-13, 24: Promotion failure windows preserve last good copy & never report false success',
      () async {
        // 10. Backup creation failure (moving active -> .bak fails)
        final ops10 = _FaultInjectingFileOps();
        final s10 = makeStorage('case_10', fileOps: ops10);
        await s10.write(jsonA);
        ops10.failOnRename = (_, newPath) => newPath.endsWith('.bak');
        ops10.failOnCopy = (_, newPath) => newPath.endsWith('.bak');
        await expectLater(
          s10.write(jsonB),
          throwsA(isA<GmCareerStorageException>()),
        );
        ops10.failOnRename = null;
        ops10.failOnCopy = null;
        expect(await s10.read(), jsonA);

        // 11 & 12. Real failure window: after active -> .bak, during .tmp -> active promotion
        final ops11 = _FaultInjectingFileOps();
        final s11 = makeStorage('case_11', fileOps: ops11);
        await s11.write(jsonA);
        ops11.failOnRename = (source, newPath) =>
            source.path.endsWith('.tmp') && newPath == s11.resolvePath();
        ops11.failOnCopy = (source, newPath) =>
            source.path.endsWith('.tmp') && newPath == s11.resolvePath();
        await expectLater(
          s11.write(jsonB),
          throwsA(isA<GmCareerStorageException>()),
        );
        ops11.failOnRename = null;
        ops11.failOnCopy = null;
        expect(await s11.read(), jsonA);

        // 13. Failure after successful promotion during backup cleanup still commits new save
        final ops13 = _FaultInjectingFileOps();
        final s13 = makeStorage('case_13', fileOps: ops13);
        await s13.write(jsonA);
        ops13.failOnDelete = (f) => f.path.endsWith('.bak');
        await s13.write(jsonB);
        expect(File('${s13.resolvePath()}.bak').existsSync(), isTrue);
        // Valid active (jsonB) wins over stale .bak (jsonA)
        expect(await s13.read(), jsonB);
      },
    );

    test(
      '14-15: Bounded Windows transient lock retry succeeds on transient errors and fails when exhausted',
      () async {
        // 14. Transient sharing violation (32) followed by success
        final ops14 = _FaultInjectingFileOps();
        final s14 = makeStorage('case_14', fileOps: ops14);
        ops14.transientErrorsRemaining = 2;
        await s14.write(jsonA);
        expect(ops14.renameCalls, 3);
        expect(await s14.read(), jsonA);

        // 15. Persistent lock error exhausting retries (max 4 attempts) falls back / fails cleanly
        final ops15 = _FaultInjectingFileOps();
        final s15 = makeStorage('case_15', fileOps: ops15);
        await s15.write(jsonA);
        ops15.transientErrorsRemaining = 100;
        ops15.failOnCopy = (_, _) => true;
        await expectLater(
          s15.write(jsonB),
          throwsA(isA<GmCareerStorageException>()),
        );
        ops15.transientErrorsRemaining = 0;
        ops15.failOnCopy = null;
        expect(await s15.read(), jsonA);
      },
    );

    test(
      '20-23: Schema v25, v24->v25 migration, slot isolation, and controller recovery guard',
      () async {
        // 20 & 22. Schema v25 & slot isolation
        final s = makeStorage('case_20_22');
        await s.write(jsonA, slot: 'slot_one');
        await s.write(jsonB, slot: 'slot_two');
        expect(await s.read(slot: 'slot_one'), jsonA);
        expect(await s.read(slot: 'slot_two'), jsonB);

        // 21. Supported v24 -> v25 legacy save migration remains recoverable from .bak
        final v24Map = jsonDecode(jsonA) as Map<String, dynamic>;
        v24Map['schemaVersion'] = 24;
        v24Map.remove('marketHistory');
        v24Map.remove('userRotation');
        v24Map.remove('staff');
        File(
          '${s.resolvePath('legacy_slot')}.bak',
        ).writeAsStringSync(jsonEncode(v24Map));
        final recoveredLegacy = await s.read(slot: 'legacy_slot');
        expect(recoveredLegacy, isNotNull);
        expect(
          GmCareerCodec.decode(recoveredLegacy!).schemaVersion,
          GmCareerCodec.currentSchemaVersion,
        );

        // 23. Controller loadCareer safety & recovery guard
        final opsCtrl = _FaultInjectingFileOps();
        final sCtrl = makeStorage('case_23', fileOps: opsCtrl);
        final controller = GmCareerController(storage: sCtrl);
        try {
          await sCtrl.write(jsonA, slot: 'ctrl_slot');
          await controller.loadCareer(slot: 'ctrl_slot');
          expect(controller.career!.id, careerA.id);

          // Force promotion failure on next command
          opsCtrl.failOnRename = (src, dst) =>
              src.path.endsWith('.tmp') &&
              dst == sCtrl.resolvePath('ctrl_slot');
          opsCtrl.failOnCopy = (src, dst) =>
              src.path.endsWith('.tmp') &&
              dst == sCtrl.resolvePath('ctrl_slot');
          await expectLater(
            controller.startDraft(slot: 'ctrl_slot'),
            throwsA(isA<GmCareerStorageException>()),
          );
          expect(controller.draftRecoveryRequired, isTrue);

          opsCtrl.failOnRename = null;
          opsCtrl.failOnCopy = null;
          await controller.loadCareer(slot: 'ctrl_slot');
          expect(controller.draftRecoveryRequired, isFalse);
          expect(controller.career!.id, careerA.id);
        } finally {
          controller.dispose();
        }
      },
    );

    test(
      'FIX1-A..D: Missing active with corrupt .bak/.tmp throws, preserves artifacts, and surfaces controller error',
      () async {
        // D. All three absent -> genuinely empty slot
        final sEmpty = makeStorage('fix1_empty');
        expect(await sEmpty.hasSave(), isFalse);
        expect(await sEmpty.read(), isNull);
        final ctrlEmpty = GmCareerController(storage: sEmpty);
        try {
          await ctrlEmpty.loadCareer();
          expect(ctrlEmpty.career, isNull);
          expect(ctrlEmpty.errorMessage, isNull);
        } finally {
          ctrlEmpty.dispose();
        }

        // A. Missing active + corrupt backup only
        final sBak = makeStorage('fix1_corrupt_bak');
        final bakFile = File('${sBak.resolvePath()}.bak')
          ..writeAsStringSync('{"corruptBackup":true');
        expect(await sBak.hasSave(), isTrue);
        await expectLater(
          sBak.read(),
          throwsA(isA<GmCareerStorageException>()),
        );
        expect(bakFile.readAsStringSync(), '{"corruptBackup":true');

        final ctrlBak = GmCareerController(storage: sBak);
        try {
          await ctrlBak.loadCareer();
          expect(ctrlBak.career, isNull);
          expect(ctrlBak.errorMessage, isNotNull);
          await ctrlBak.loadCareer();
          expect(ctrlBak.career, isNull);
          expect(ctrlBak.errorMessage, isNotNull);
          expect(bakFile.readAsStringSync(), '{"corruptBackup":true');
        } finally {
          ctrlBak.dispose();
        }

        // B. Missing active + corrupt temp only
        final sTmp = makeStorage('fix1_corrupt_tmp');
        final tmpFile = File('${sTmp.resolvePath()}.tmp')
          ..writeAsStringSync('{"corruptTemp":true');
        expect(await sTmp.hasSave(), isTrue);
        await expectLater(
          sTmp.read(),
          throwsA(isA<GmCareerStorageException>()),
        );
        expect(tmpFile.readAsStringSync(), '{"corruptTemp":true');

        final ctrlTmp = GmCareerController(storage: sTmp);
        try {
          await ctrlTmp.loadCareer();
          expect(ctrlTmp.career, isNull);
          expect(ctrlTmp.errorMessage, isNotNull);
          expect(tmpFile.readAsStringSync(), '{"corruptTemp":true');
        } finally {
          ctrlTmp.dispose();
        }

        // C. Missing active + both backup and temp corrupt
        final sBoth = makeStorage('fix1_corrupt_both');
        final bothBak = File('${sBoth.resolvePath()}.bak')
          ..writeAsStringSync('{bad bak');
        final bothTmp = File('${sBoth.resolvePath()}.tmp')
          ..writeAsStringSync('{bad tmp');
        expect(await sBoth.hasSave(), isTrue);
        await expectLater(
          sBoth.read(),
          throwsA(isA<GmCareerStorageException>()),
        );
        expect(bothBak.readAsStringSync(), '{bad bak');
        expect(bothTmp.readAsStringSync(), '{bad tmp');

        final ctrlBoth = GmCareerController(storage: sBoth);
        try {
          await ctrlBoth.loadCareer();
          expect(ctrlBoth.career, isNull);
          expect(ctrlBoth.errorMessage, isNotNull);
          expect(bothBak.readAsStringSync(), '{bad bak');
          expect(bothTmp.readAsStringSync(), '{bad tmp');
        } finally {
          ctrlBoth.dispose();
        }
      },
    );

    test(
      'FIX1-double-failure: Active->bak succeeds, tmp->active fails, and bak->active restoration also fails',
      () async {
        final ops = _FaultInjectingFileOps();
        final storage = makeStorage('fix1_double_fail', fileOps: ops);
        await storage.write(jsonA);

        final controller = GmCareerController(storage: storage);
        GmCareerController? freshController;
        try {
          await controller.loadCareer();
          expect(controller.career!.id, careerA.id);

          // Fail both tmp->active AND bak->active promotions.
          ops.failOnRename = (src, dst) =>
              dst == storage.resolvePath() &&
              (src.path.endsWith('.tmp') || src.path.endsWith('.bak'));
          ops.failOnCopy = (src, dst) =>
              dst == storage.resolvePath() &&
              (src.path.endsWith('.tmp') || src.path.endsWith('.bak'));

          await expectLater(
            controller.startDraft(),
            throwsA(isA<GmCareerStorageException>()),
          );
          expect(controller.draftRecoveryRequired, isTrue);

          final bakFile = File('${storage.resolvePath()}.bak');
          final tmpFile = File('${storage.resolvePath()}.tmp');
          expect(bakFile.existsSync(), isTrue);
          expect(tmpFile.existsSync(), isTrue);
          expect(
            GmCareerCodec.decode(bakFile.readAsStringSync()).id,
            careerA.id,
          );
          expect(
            GmCareerCodec.decode(
              tmpFile.readAsStringSync(),
            ).draftExecutionState.isNotStarted,
            isFalse,
          );

          // Disable fault injection and recover via fresh controller reload.
          ops.failOnRename = null;
          ops.failOnCopy = null;
          freshController = GmCareerController(storage: storage);
          await freshController.loadCareer();
          expect(freshController.errorMessage, isNull);
          expect(freshController.career!.id, careerA.id);
          expect(freshController.career!.phase, CareerPhase.openingOffseason);
        } finally {
          controller.dispose();
          freshController?.dispose();
        }
      },
    );

    test(
      'FIX1-failed-temp-write: Truncated/interrupted .tmp write preserves valid active save and allows clean retry',
      () async {
        final ops = _FaultInjectingFileOps();
        final storage = makeStorage('fix1_failed_temp_write', fileOps: ops);
        await storage.write(jsonA);

        ops.failOnWrite = (f) => f.path.endsWith('.tmp');
        ops.partialWriteContentBeforeFail = '{"schemaVersion":25';

        await expectLater(
          storage.write(jsonB),
          throwsA(isA<GmCareerStorageException>()),
        );
        expect(File(storage.resolvePath()).readAsStringSync(), jsonA);
        expect(
          File('${storage.resolvePath()}.tmp').readAsStringSync(),
          '{"schemaVersion":25',
        );

        final controller = GmCareerController(storage: storage);
        try {
          await controller.loadCareer();
          expect(controller.errorMessage, isNull);
          expect(controller.career!.id, careerA.id);

          ops.failOnWrite = null;
          ops.partialWriteContentBeforeFail = null;
          await storage.write(jsonB);
          await controller.loadCareer();
          expect(controller.career!.draftExecutionState.isNotStarted, isFalse);
        } finally {
          controller.dispose();
        }
      },
    );

    test(
      'FIX2-hasSave: Distinguishes empty slot, existing artifacts, and throws GmCareerStorageException on IO errors',
      () async {
        // 1. Artifact detection across all 7 non-empty/existing combinations
        final sValid = makeStorage('fix2_valid_active');
        await sValid.write(jsonA);
        expect(await sValid.hasSave(), isTrue);

        final sEmptyActive = makeStorage('fix2_empty_active');
        File(sEmptyActive.resolvePath()).writeAsStringSync('');
        expect(await sEmptyActive.hasSave(), isTrue);

        final sCorruptActive = makeStorage('fix2_corrupt_active');
        File(sCorruptActive.resolvePath()).writeAsStringSync('{corrupt');
        expect(await sCorruptActive.hasSave(), isTrue);

        final sBakOnly = makeStorage('fix2_bak_only');
        File('${sBakOnly.resolvePath()}.bak').writeAsStringSync(jsonA);
        expect(await sBakOnly.hasSave(), isTrue);

        final sCorruptBak = makeStorage('fix2_corrupt_bak');
        File('${sCorruptBak.resolvePath()}.bak').writeAsStringSync('{corrupt');
        expect(await sCorruptBak.hasSave(), isTrue);

        final sTmpOnly = makeStorage('fix2_tmp_only');
        File('${sTmpOnly.resolvePath()}.tmp').writeAsStringSync(jsonA);
        expect(await sTmpOnly.hasSave(), isTrue);

        final sCorruptTmp = makeStorage('fix2_corrupt_tmp');
        File('${sCorruptTmp.resolvePath()}.tmp').writeAsStringSync('{corrupt');
        expect(await sCorruptTmp.hasSave(), isTrue);

        // 2. Filesystem error injection on active, backup, and temp paths
        final ops = _FaultInjectingFileOps();
        final sErr = makeStorage('fix2_fs_errors', fileOps: ops);
        await sErr.write(jsonA);

        // A. Error on active path (permission denied)
        ops.failOnExists = (f) => f.path == sErr.resolvePath()
            ? FileSystemException(
                'Permission denied',
                f.path,
                const OSError('Access denied', 5),
              )
            : null;
        await expectLater(
          sErr.hasSave(),
          throwsA(
            isA<GmCareerStorageException>().having(
              (e) => e.cause,
              'cause',
              isA<FileSystemException>(),
            ),
          ),
        );
        expect(File(sErr.resolvePath()).readAsStringSync(), jsonA);

        // B. Error on backup path after active returns false (generic I/O)
        final sErrBak = makeStorage('fix2_fs_err_bak', fileOps: ops);
        ops.failOnExists = (f) => f.path.endsWith('.bak')
            ? FileSystemException(
                'Device I/O error',
                f.path,
                const OSError('I/O error', 1),
              )
            : null;
        await expectLater(
          sErrBak.hasSave(),
          throwsA(
            isA<GmCareerStorageException>().having(
              (e) => e.cause,
              'cause',
              isA<FileSystemException>(),
            ),
          ),
        );

        // C. Error on temp path after active & backup return false
        ops.failOnExists = (f) => f.path.endsWith('.tmp')
            ? FileSystemException(
                'Permission denied on temp',
                f.path,
                const OSError('Access denied', 5),
              )
            : null;
        await expectLater(
          sErrBak.hasSave(),
          throwsA(
            isA<GmCareerStorageException>().having(
              (e) => e.cause,
              'cause',
              isA<FileSystemException>(),
            ),
          ),
        );

        // D. Healthy check succeeds after fault clears
        ops.failOnExists = null;
        expect(await sErr.hasSave(), isTrue);
        expect(await sErrBak.hasSave(), isFalse);
      },
    );
  });
}
