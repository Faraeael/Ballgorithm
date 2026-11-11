import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

void main() {
  const draftService = DraftExecutionService();
  late GmCareer playInCareer;
  late GmCareer tankingCareer;
  late Directory directory;
  late FileGmCareerStorage files;
  late _RecordingStorage storage;
  late GmCareerController controller;

  setUpAll(() {
    const setup = CareerSetupService();
    playInCareer = GmCareer.fromSetupResult(
      setup.generate(
        const CareerSetupRequest(
          selectedTeamId: TeamId('team-2'),
          selectedSituation: FranchiseSituation.playIn,
          seed: 20261028,
        ),
      ),
      id: 'draft-controller-play-in',
    );
    tankingCareer = GmCareer.fromSetupResult(
      setup.generate(
        const CareerSetupRequest(
          selectedTeamId: TeamId('team-1'),
          selectedSituation: FranchiseSituation.tanking,
          seed: 20261028,
        ),
      ),
      id: 'draft-controller-tanking',
    );
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('draft_controller_');
    files = FileGmCareerStorage(directoryPath: directory.path);
    final initial = GmCareerCodec.encode(playInCareer);
    await files.write(initial);
    storage = _RecordingStorage(files, initial);
    controller = GmCareerController(storage: storage);
    await controller.loadCareer();
  });

  tearDown(() async {
    controller.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> loadTankingCareer() async {
    final initial = GmCareerCodec.encode(tankingCareer);
    await files.write(initial);
    storage.committedData = initial;
    await controller.loadCareer();
  }

  test(
    'start saves every transition before exposing it and stops at pick 12',
    () async {
      storage.beforeWrite = (_) async {
        expect(GmCareerCodec.encode(controller.career!), storage.committedData);
      };
      controller.addListener(() {
        expect(GmCareerCodec.encode(controller.career!), storage.committedData);
      });

      await controller.startDraft();

      expect(storage.selectionCounts, List.generate(12, (index) => index));
      expect(controller.career!.draftExecutionState.currentOverallPick, 12);
      expect(
        controller.career!.draftExecutionState.isHumanTurn(
          order: controller.career!.draftOrder,
          userTeamId: controller.career!.userFranchiseId,
        ),
        isTrue,
      );
      expect(controller.isLoading, isFalse);
      expect(controller.errorMessage, isNull);
      expect(await files.read(), GmCareerCodec.encode(controller.career!));

      await controller.advanceDraft();
      await expectLater(controller.startDraft(), throwsA(isA<StateError>()));
      expect(storage.commits, hasLength(12));
    },
  );

  test(
    'human picks save separately, complete all picks, and preserve rosters',
    () async {
      final original =
          jsonDecode(GmCareerCodec.encode(playInCareer))
              as Map<String, dynamic>;
      await controller.startDraft();
      final firstProspect = controller.career!.draftExecutionState
          .availableProspects(controller.career!.draftClass)
          .first
          .id;

      await controller.makeHumanSelection(prospectId: firstProspect);
      expect(controller.career!.draftExecutionState.currentOverallPick, 42);
      expect(storage.selectionCounts, List.generate(42, (index) => index));
      final humanPick = controller.career!.draftExecutionState.selections[11];
      expect(humanPick.prospectId, firstProspect);
      expect(humanPick.selectingTeamId, playInCareer.userFranchiseId);
      final secondProspect = controller.career!.draftExecutionState
          .availableProspects(controller.career!.draftClass)
          .first
          .id;

      await controller.makeHumanSelection(prospectId: secondProspect);

      expect(storage.selectionCounts, List.generate(61, (index) => index));
      final completed = controller.career!;
      expect(completed.draftExecutionState.isCompleted, isTrue);
      expect(completed.draftExecutionState.selections, hasLength(60));
      expect(completed.draftExecutionState.draftRights, hasLength(60));
      expect(completed.draftExecutionState.selectedProspectIds, hasLength(60));
      expect(
        completed.draftExecutionState.undraftedProspects(completed.draftClass),
        hasLength(30),
      );
      for (final saved in storage.commits) {
        final snapshot = jsonDecode(saved) as Map<String, dynamic>;
        for (final key in ['league', 'careerProfiles', 'rosterMemberships']) {
          expect(
            snapshot[key],
            original[key],
            reason: '$key changed during draft',
          );
        }
      }
      await controller.advanceDraft();
      await expectLater(
        controller.makeHumanSelection(prospectId: firstProspect),
        throwsStateError,
      );
      expect(identical(controller.career, completed), isTrue);
      expect(storage.commits, hasLength(61));
    },
  );

  test(
    'failed AI save retains last committed pick and reload resumes exactly',
    () async {
      storage.failOnAttempt = 6;

      await expectLater(
        controller.startDraft(),
        throwsA(isA<GmCareerStorageException>()),
      );

      expect(storage.selectionCounts, [0, 1, 2, 3, 4]);
      final committed = controller.career!;
      expect(committed.draftExecutionState.currentOverallPick, 5);
      expect(controller.errorMessage, isNotNull);
      expect(controller.isLoading, isFalse);
      expect(await files.read(), GmCareerCodec.encode(committed));

      final resumedFiles = FileGmCareerStorage(directoryPath: directory.path);
      final resumedStorage = _RecordingStorage(
        resumedFiles,
        GmCareerCodec.encode(committed),
      );
      final resumed = GmCareerController(storage: resumedStorage);
      addTearDown(resumed.dispose);
      await resumed.loadCareer();
      await resumed.advanceDraft();

      expect(resumedStorage.selectionCounts, [5, 6, 7, 8, 9, 10, 11]);
      expect(
        resumed.career!.draftExecutionState.selections
            .take(4)
            .map((selection) => selection.toJson())
            .toList(),
        committed.draftExecutionState.selections
            .map((selection) => selection.toJson())
            .toList(),
      );
      final expected = draftService.advanceUntilHumanOrComplete(
        draftService.startDraft(playInCareer),
      );
      expect(
        GmCareerCodec.encode(resumed.career!),
        GmCareerCodec.encode(expected),
      );
      expect(await resumedFiles.read(), GmCareerCodec.encode(expected));
    },
  );

  test(
    'human save failure requires reload before retrying the selection',
    () async {
      await loadTankingCareer();
      await controller.startDraft();
      final before = controller.career!;
      final prospectId = before.draftClass.prospects.first.id;
      storage.failOnAttempt = 2;

      await expectLater(
        controller.makeHumanSelection(prospectId: prospectId),
        throwsA(isA<GmCareerStorageException>()),
      );

      expect(identical(controller.career, before), isTrue);
      expect(await files.read(), GmCareerCodec.encode(before));
      expect(storage.selectionCounts, [0]);
      storage.failOnAttempt = null;
      await expectLater(
        controller.makeHumanSelection(prospectId: prospectId),
        throwsStateError,
      );
      expect(storage.writeAttempts, 2);
      await controller.loadCareer();
      await controller.makeHumanSelection(prospectId: prospectId);

      expect(storage.selectionCounts, List.generate(31, (index) => index));
      expect(controller.career!.draftExecutionState.currentOverallPick, 31);
      expect(
        controller.career!.draftExecutionState.selections.first.prospectId,
        prospectId,
      );
      expect(controller.errorMessage, isNull);
    },
  );

  test(
    'AI failure after human pick preserves human rights on resume',
    () async {
      await loadTankingCareer();
      await controller.startDraft();
      final prospectId = controller.career!.draftClass.prospects.first.id;
      storage.failOnAttempt = 4;

      await expectLater(
        controller.makeHumanSelection(prospectId: prospectId),
        throwsA(isA<GmCareerStorageException>()),
      );

      expect(storage.selectionCounts, [0, 1, 2]);
      expect(controller.career!.draftExecutionState.currentOverallPick, 3);
      expect(
        controller
            .career!
            .draftExecutionState
            .draftRights[prospectId.value]!
            .owningTeamId,
        tankingCareer.userFranchiseId,
      );
      storage.failOnAttempt = null;
      await controller.loadCareer();
      await controller.advanceDraft();

      expect(storage.selectionCounts, List.generate(31, (index) => index));
      expect(controller.career!.draftExecutionState.currentOverallPick, 31);
      expect(
        controller.career!.draftExecutionState.selections.first.prospectId,
        prospectId,
      );
    },
  );

  test(
    'write rejection blocks queued draft work until disk is reloaded',
    () async {
      final writeEntered = Completer<void>();
      final releaseWrite = Completer<void>();
      storage.failOnAttempt = 3;
      storage.failAfterCommit = true;
      storage.beforeWrite = (_) async {
        if (storage.writeAttempts == 3) {
          writeEntered.complete();
          await releaseWrite.future;
        }
      };
      final draft = expectLater(
        controller.startDraft(),
        throwsA(isA<GmCareerStorageException>()),
      );
      await writeEntered.future;
      final queuedAdvance = expectLater(
        controller.advanceDraft(),
        throwsStateError,
      );
      final queuedStart = expectLater(
        controller.startDraft(),
        throwsStateError,
      );
      final queuedHuman = expectLater(
        controller.makeHumanSelection(
          prospectId: playInCareer.draftClass.prospects.first.id,
        ),
        throwsStateError,
      );
      releaseWrite.complete();
      await draft;
      await queuedAdvance;
      await queuedStart;
      await queuedHuman;

      expect(storage.writeAttempts, 3);
      expect(
        controller.career!.draftExecutionState.completedSelectionsCount,
        1,
      );
      expect(
        GmCareerCodec.decode(
          (await files.read())!,
        ).draftExecutionState.completedSelectionsCount,
        2,
      );
      storage.failOnAttempt = null;
      await expectLater(controller.advanceDraft(), throwsStateError);
      expect(storage.writeAttempts, 3);
      await controller.loadCareer();
      expect(
        controller.career!.draftExecutionState.completedSelectionsCount,
        2,
      );
      await controller.advanceDraft();

      expect(storage.selectionCounts, List.generate(12, (index) => index));
      expect(controller.career!.draftExecutionState.currentOverallPick, 12);
      expect(storage.maximumConcurrentWrites, 1);
    },
  );

  test(
    'illegal human commands never write or mutate committed state',
    () async {
      final notStarted = controller.career!;
      await expectLater(controller.advanceDraft(), throwsStateError);
      await expectLater(
        controller.makeHumanSelection(
          prospectId: notStarted.draftClass.prospects.first.id,
        ),
        throwsStateError,
      );
      expect(identical(controller.career, notStarted), isTrue);
      expect(storage.commits, isEmpty);

      final started = draftService.startDraft(playInCareer);
      final encoded = GmCareerCodec.encode(started);
      await files.write(encoded);
      storage.committedData = encoded;
      await controller.loadCareer();
      final aiTurn = controller.career!;
      await expectLater(
        controller.makeHumanSelection(
          prospectId: aiTurn.draftClass.prospects.first.id,
        ),
        throwsStateError,
      );
      expect(identical(controller.career, aiTurn), isTrue);
      expect(storage.commits, isEmpty);

      await controller.advanceDraft();
      final humanTurn = controller.career!;
      final count = storage.commits.length;
      await expectLater(
        controller.makeHumanSelection(
          prospectId: const PlayerId('missing-prospect'),
        ),
        throwsArgumentError,
      );
      await expectLater(
        controller.makeHumanSelection(
          prospectId: humanTurn.draftExecutionState.selections.first.prospectId,
        ),
        throwsStateError,
      );
      expect(identical(controller.career, humanTurn), isTrue);
      expect(storage.commits, hasLength(count));
      expect(await files.read(), GmCareerCodec.encode(humanTurn));
    },
  );

  test(
    'queued stale human submissions cannot consume the next human pick',
    () async {
      await loadTankingCareer();
      await controller.startDraft();
      final before = controller.career!;
      final writeEntered = Completer<void>();
      final releaseWrite = Completer<void>();
      storage.beforeWrite = (_) async {
        if (!writeEntered.isCompleted) {
          writeEntered.complete();
          await releaseWrite.future;
        }
      };
      final first = controller.makeHumanSelection(
        prospectId: before.draftClass.prospects[0].id,
      );
      await writeEntered.future;
      final duplicate = expectLater(
        controller.makeHumanSelection(
          prospectId: before.draftClass.prospects[1].id,
        ),
        throwsStateError,
      );
      final advance = controller.advanceDraft();
      expect(identical(controller.career, before), isTrue);
      expect(await files.read(), GmCareerCodec.encode(before));
      releaseWrite.complete();
      await first;
      await duplicate;
      await advance;

      expect(storage.maximumConcurrentWrites, 1);
      expect(storage.selectionCounts, List.generate(31, (index) => index));
      expect(controller.career!.draftExecutionState.currentOverallPick, 31);
      expect(
        controller.career!.draftExecutionState.selections.first.prospectId,
        before.draftClass.prospects[0].id,
      );
    },
  );

  test('load and clear wait for an active draft command', () async {
    final writeEntered = Completer<void>();
    final releaseWrite = Completer<void>();
    storage.beforeWrite = (_) async {
      if (!writeEntered.isCompleted) {
        writeEntered.complete();
        await releaseWrite.future;
      }
    };
    final draft = controller.startDraft();
    await writeEntered.future;
    final reload = controller.loadCareer();
    final clear = controller.clearCareer();
    expect(storage.reads, 1);
    expect(storage.clears, 0);
    releaseWrite.complete();
    await draft;
    await reload;
    await clear;

    expect(storage.selectionCounts, List.generate(12, (index) => index));
    expect(storage.maximumConcurrentWrites, 1);
    expect(storage.reads, 2);
    expect(storage.clears, 1);
    expect(controller.career, isNull);
    expect(await files.read(), isNull);
  });

  test(
    'named-slot draft recovery never touches default or M007 saves',
    () async {
      const slot = 'draft-test';
      const seasonData = '{"m007":"untouched"}';
      final seasonFiles = [
        for (final suffix in ['', '.bak', '.tmp'])
          File('${directory.path}/ballgorithm_save.json$suffix'),
      ];
      for (final file in seasonFiles) {
        await file.writeAsString(seasonData);
      }
      final defaultSave = await files.read();
      await files.write(defaultSave!, slot: slot);
      await controller.loadCareer(slot: slot);

      await controller.startDraft(slot: slot);

      expect(await files.read(), defaultSave);
      final active = GmCareerCodec.decode((await files.read(slot: slot))!);
      expect(active.draftExecutionState.currentOverallPick, 12);
      final backupFile = File('${files.resolvePath(slot)}.bak');
      expect(await backupFile.exists(), isFalse);
      await backupFile.writeAsString(storage.commits[10]);
      expect(await File('${files.resolvePath(slot)}.tmp').exists(), isFalse);
      await File(files.resolvePath(slot)).writeAsString('{interrupted');
      final recovered = GmCareerController(storage: files);
      addTearDown(recovered.dispose);
      await recovered.loadCareer(slot: slot);
      expect(recovered.errorMessage, isNull);
      expect(recovered.career!.draftExecutionState.currentOverallPick, 11);
      await recovered.advanceDraft(slot: slot);
      expect(
        GmCareerCodec.encode(recovered.career!),
        GmCareerCodec.encode(active),
      );
      await recovered.clearCareer(slot: slot);
      expect(await files.read(slot: slot), isNull);
      expect(await files.read(), defaultSave);
      for (final file in seasonFiles) {
        expect(await file.readAsString(), seasonData);
      }
    },
  );
}

class _RecordingStorage implements GmCareerStorage {
  _RecordingStorage(this.delegate, this.committedData);

  final GmCareerStorage delegate;
  String? committedData;
  final List<String> commits = [];
  Future<void> Function(String data)? beforeWrite;
  int? failOnAttempt;
  bool failAfterCommit = false;
  int writeAttempts = 0;
  int reads = 0;
  int clears = 0;
  int _concurrentWrites = 0;
  int maximumConcurrentWrites = 0;

  List<int> get selectionCounts => [
    for (final data in commits)
      GmCareerCodec.decode(data).draftExecutionState.completedSelectionsCount,
  ];

  @override
  Future<String?> read({String slot = 'default'}) {
    reads++;
    return delegate.read(slot: slot);
  }

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    final attempt = ++writeAttempts;
    _concurrentWrites++;
    if (_concurrentWrites > maximumConcurrentWrites) {
      maximumConcurrentWrites = _concurrentWrites;
    }
    try {
      await beforeWrite?.call(data);
      if (attempt == failOnAttempt && !failAfterCommit) {
        throw const GmCareerStorageException('Injected write interruption');
      }
      await delegate.write(data, slot: slot);
      committedData = data;
      commits.add(data);
      if (attempt == failOnAttempt && failAfterCommit) {
        throw const GmCareerStorageException('Injected post-promotion failure');
      }
    } finally {
      _concurrentWrites--;
    }
  }

  @override
  Future<void> clear({String slot = 'default'}) async {
    clears++;
    await delegate.clear(slot: slot);
    committedData = null;
  }

  @override
  Future<bool> hasSave({String slot = 'default'}) =>
      delegate.hasSave(slot: slot);
}
