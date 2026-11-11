import 'dart:io';

import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('M008-T04: GmCareerStorage File & In-Memory Isolation', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('career_storage_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('atomic write, read, and clear round-trip', () async {
      final savePath = '${tempDir.path}/ballgorithm_gm_career.json';
      final storage = FileGmCareerStorage(filePath: savePath);

      expect(await storage.hasSave(), isFalse);
      expect(await storage.read(), isNull);

      const payload = '{"schemaVersion":1,"id":"career-1"}';
      await storage.write(payload);

      expect(await storage.hasSave(), isTrue);
      expect(await storage.read(), equals(payload));

      await storage.clear();
      expect(await storage.hasSave(), isFalse);
      expect(await storage.read(), isNull);
    });

    test(
      'Scope 12: backup recovery restores prior save when active file is missing or corrupted',
      () async {
        final savePath = '${tempDir.path}/ballgorithm_gm_career.json';
        final storage = FileGmCareerStorage(filePath: savePath);

        const saveV1 = '{"schemaVersion":1,"id":"save-v1"}';
        await storage.write(saveV1);

        // Simulate a previous verified save moved to .bak
        final activeFile = File(savePath);
        final backupFile = File('$savePath.bak');
        await activeFile.copy(backupFile.path);

        // Truncate active file to simulate crash during write
        await activeFile.writeAsString('');

        // Reading should recover valid backup content
        final recovered = await storage.read();
        expect(recovered, equals(saveV1));
        expect(await activeFile.readAsString(), equals(saveV1));
      },
    );

    test(
      'Scope 11: corrupt save is preserved and never silently erased',
      () async {
        final savePath = '${tempDir.path}/ballgorithm_gm_career.json';
        final storage = FileGmCareerStorage(filePath: savePath);

        const corruptPayload = '{"corrupted":true, invalid json';
        final activeFile = File(savePath);
        await activeFile.writeAsString(corruptPayload);

        final readData = await storage.read();
        expect(readData, equals(corruptPayload));
        // File still exists on disk
        expect(await activeFile.exists(), isTrue);
        expect(await activeFile.readAsString(), equals(corruptPayload));
      },
    );

    test(
      'Scope 14: complete storage isolation between M007 season and M008 GM career files',
      () async {
        final seasonPath = '${tempDir.path}/ballgorithm_save.json';
        final careerPath = '${tempDir.path}/ballgorithm_gm_career.json';

        final careerStorage = FileGmCareerStorage(filePath: careerPath);
        final seasonFile = File(seasonPath);
        const m007Data = '{"schemaVersion":1,"id":"m007-season-state"}';
        await seasonFile.writeAsString(m007Data);

        // Career write
        const careerData = '{"schemaVersion":1,"id":"gm-career-state"}';
        await careerStorage.write(careerData);

        // Verify M007 file was NOT modified
        expect(await seasonFile.readAsString(), equals(m007Data));
        expect(await careerStorage.read(), equals(careerData));

        // Career clear
        await careerStorage.clear();
        expect(await careerStorage.hasSave(), isFalse);
        // M007 file remains intact
        expect(await seasonFile.exists(), isTrue);
        expect(await seasonFile.readAsString(), equals(m007Data));
      },
    );

    test(
      'Scope 13: supports slot-based career saves without redesigning domain',
      () async {
        final storage = FileGmCareerStorage(directoryPath: tempDir.path);

        await storage.write('{"career":1}', slot: 'slot-1');
        await storage.write('{"career":2}', slot: 'slot-2');

        expect(await storage.hasSave(slot: 'slot-1'), isTrue);
        expect(await storage.hasSave(slot: 'slot-2'), isTrue);
        expect(await storage.hasSave(slot: 'slot-3'), isFalse);

        expect(await storage.read(slot: 'slot-1'), equals('{"career":1}'));
        expect(await storage.read(slot: 'slot-2'), equals('{"career":2}'));
      },
    );
  });
}
