import 'dart:io';
import 'dart:isolate';

import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/rollover_isolate_workers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

import '../integration_test/support/d3c_fixture_helper.dart';

void _exitBeforeHandshakeEntry(SendPort initReplyPort) {
  Isolate.exit();
}

void _exitOnRequestEntry(SendPort initReplyPort) {
  final commands = ReceivePort();
  initReplyPort.send(commands.sendPort);
  commands.listen((Object? message) {
    if (message == null) {
      commands.close();
      return;
    }
    Isolate.exit();
  });
}

void _uncaughtErrorOnRequestEntry(SendPort initReplyPort) {
  final commands = ReceivePort();
  initReplyPort.send(commands.sendPort);
  commands.listen((Object? message) {
    if (message == null) {
      commands.close();
      return;
    }
    // Schedule an uncaught async error so errorPort fires followed by exitPort.
    Future<void>.microtask(() {
      throw StateError('Uncaught fatal worker crash');
    });
  });
}

void main() {
  late RolloverPrepareOutput samplePrepared;

  setUpAll(() {
    final setup = const CareerSetupService().generate(
      const CareerSetupRequest(
        selectedTeamId: TeamId('team-1'),
        selectedSituation: FranchiseSituation.tanking,
        seed: 20261028,
      ),
    );
    final y1Initial = GmCareer.fromSetupResult(setup, id: 'd3c-t03b2-life');
    final y1Completed = completeSeasonFromSetup(y1Initial);
    samplePrepared = prepareSeasonRolloverWorker(
      RolloverPrepareRequest(y1Completed),
    );
  });

  test(
    'A-C, I-J: Normal startup, verifyArchive, digestArchive, idempotent close, and request after close',
    timeout: const Timeout(Duration(minutes: 1)),
    () async {
      final session = await ArchiveWorkerSession.start();
      try {
        await session.verifyArchive(
          ArchiveVerifyRequest(
            archiveJson: samplePrepared.archiveJson,
            expectedDigest: samplePrepared.archiveDigest,
            expectedSeasonYear: 1,
          ),
        );
        final digest = await session.digestArchive(samplePrepared.archiveJson);
        expect(digest, samplePrepared.archiveDigest);
      } finally {
        await session.close();
        // I. Explicit close is idempotent
        await session.close();
      }

      // J. Request after close fails promptly with StateError
      await expectLater(
        session.digestArchive(samplePrepared.archiveJson),
        throwsStateError,
      );
    },
  );

  test(
    'D: Spawn exception closes all ports and propagates',
    timeout: const Timeout(Duration(seconds: 15)),
    () async {
      final capturedPorts = <SendPort>[];
      await expectLater(
        ArchiveWorkerSession.start(
          spawn:
              (
                entry,
                initSendPort, {
                onExit,
                onError,
                errorsAreFatal = true,
                debugName,
              }) async {
                capturedPorts.add(initSendPort);
                if (onExit != null) capturedPorts.add(onExit);
                if (onError != null) capturedPorts.add(onError);
                throw IsolateSpawnException('Simulated spawn failure');
              },
        ),
        throwsA(isA<IsolateSpawnException>()),
      );
      expect(capturedPorts.length, 3);
    },
  );

  test(
    'E: Worker exit before handshake fails initialization promptly',
    timeout: const Timeout(Duration(seconds: 15)),
    () async {
      await expectLater(
        ArchiveWorkerSession.start(entryPoint: _exitBeforeHandshakeEntry),
        throwsStateError,
      );
    },
  );

  test(
    'F, H, I: Unexpected worker exit during pending requests fails all Futures cleanly and close() on failed session is idempotent',
    timeout: const Timeout(Duration(seconds: 15)),
    () async {
      final session = await ArchiveWorkerSession.start(
        entryPoint: _exitOnRequestEntry,
      );
      final f1 = session.digestArchive('payload-1');
      final f2 = session.digestArchive('payload-2');

      await expectLater(f1, throwsStateError);
      await expectLater(f2, throwsStateError);

      // Subsequent request on failed session fails promptly
      await expectLater(session.digestArchive('payload-3'), throwsStateError);

      // Idempotent close on failed session
      await session.close();
      await session.close();
    },
  );

  test(
    'G, K: Uncaught worker error and exit race fails pending requests once without double-completion',
    timeout: const Timeout(Duration(seconds: 15)),
    () async {
      final session = await ArchiveWorkerSession.start(
        entryPoint: _uncaughtErrorOnRequestEntry,
      );
      final f1 = session.digestArchive('payload-1');
      final f2 = session.digestArchive('payload-2');

      await expectLater(f1, throwsStateError);
      await expectLater(f2, throwsStateError);

      await session.close();
    },
  );

  test(
    'M: Storage writeArchive failure propagates and leaves no orphan file',
    timeout: const Timeout(Duration(seconds: 30)),
    () async {
      final tempDir = Directory.systemTemp.createTempSync('d3c_t03b2_stor_');
      try {
        final storage = FileGmCareerStorage(directoryPath: tempDir.path);
        await expectLater(
          storage.writeArchive(
            seasonYear: 1,
            archiveJson: '{"bad":true}',
            expectedDigest: samplePrepared.archiveDigest,
          ),
          throwsA(isA<GmCareerStorageException>()),
        );
        expect(await storage.hasArchive(seasonYear: 1), isFalse);
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    },
  );
}
