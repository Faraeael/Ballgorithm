import 'dart:convert';
import 'dart:io';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _seed = 20261028;
const _team = TeamId('team-1');

void main() {
  late GmCareer completed;

  setUpAll(() {
    completed = _completedCareer();
  });

  group('M008-T07A rookie signing controller', () {
    test('1. signs a drafted rookie and persists before publishing', () async {
      final storage = _ObservedStorage(completed);
      final controller = GmCareerController(storage: storage);
      addTearDown(controller.dispose);
      await controller.loadCareer();
      final rights = _userRights(controller.career!).first;
      final draftBefore = jsonEncode(
        controller.career!.draftExecutionState.toJson(),
      );

      await controller.signDraftedRookie(
        prospectId: rights.prospectId,
        category: RosterCategory.standard,
        durationYears: 4,
      );

      expect(storage.attempts, 1);
      expect(storage.clears, 0);
      expect(controller.errorMessage, isNull);
      expect(controller.career!.rookieSigningLedger.length, 1);
      expect(controller.career!.userTeam.roster.standardCount, 13);
      expect(storage.saved.rookieSigningLedger.length, 1);
      expect(
        jsonEncode(controller.career!.draftExecutionState.toJson()),
        draftBefore,
      );
      expect(controller.career!.unsignedDraftRights.length, 59);
    });

    test('2. duplicate and stale submissions are rejected', () async {
      final storage = _ObservedStorage(completed);
      final controller = GmCareerController(storage: storage);
      addTearDown(controller.dispose);
      await controller.loadCareer();
      final rights = _userRights(controller.career!).first;

      final first = controller.signDraftedRookie(
        prospectId: rights.prospectId,
        category: RosterCategory.twoWay,
        durationYears: 2,
      );
      final second = controller.signDraftedRookie(
        prospectId: rights.prospectId,
        category: RosterCategory.twoWay,
        durationYears: 2,
      );

      await expectLater(first, completes);
      await expectLater(
        second,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Career changed before the rookie signing'),
          ),
        ),
      );
      expect(storage.attempts, 1);
      expect(controller.career!.rookieSigningLedger.length, 1);

      await expectLater(
        controller.signDraftedRookie(
          prospectId: rights.prospectId,
          category: RosterCategory.twoWay,
          durationYears: 2,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('already signed'),
          ),
        ),
      );
      expect(storage.attempts, 1);
    });

    test('3. a failed write preserves committed career until reload', () async {
      final storage = _ObservedStorage(completed);
      final controller = GmCareerController(storage: storage);
      addTearDown(controller.dispose);
      await controller.loadCareer();
      final rights = _userRights(controller.career!).first;

      storage.failNextWrite = true;
      await expectLater(
        controller.signDraftedRookie(
          prospectId: rights.prospectId,
          category: RosterCategory.standard,
          durationYears: 3,
        ),
        throwsA(isA<GmCareerStorageException>()),
      );

      expect(controller.career!.rookieSigningLedger.isEmpty, isTrue);
      expect(controller.draftRecoveryRequired, isTrue);
      expect(storage.saved.rookieSigningLedger.isEmpty, isTrue);

      await expectLater(
        controller.signDraftedRookie(
          prospectId: rights.prospectId,
          category: RosterCategory.standard,
          durationYears: 3,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Reload saved GM Career'),
          ),
        ),
      );

      await controller.loadCareer();
      expect(controller.draftRecoveryRequired, isFalse);
      expect(controller.career!.rookieSigningLedger.isEmpty, isTrue);
    });

    test('4. an uncertain write reconciles through reload', () async {
      final storage = _ObservedStorage(completed);
      final controller = GmCareerController(storage: storage);
      addTearDown(controller.dispose);
      await controller.loadCareer();
      final rights = _userRights(controller.career!).first;

      storage.failAfterCommit = true;
      await expectLater(
        controller.signDraftedRookie(
          prospectId: rights.prospectId,
          category: RosterCategory.standard,
          durationYears: 3,
        ),
        throwsA(isA<GmCareerStorageException>()),
      );

      expect(controller.career!.rookieSigningLedger.isEmpty, isTrue);
      expect(controller.draftRecoveryRequired, isTrue);
      expect(storage.saved.rookieSigningLedger.length, 1);

      await controller.loadCareer();
      expect(controller.draftRecoveryRequired, isFalse);
      expect(controller.career!.rookieSigningLedger.length, 1);
      expect(controller.career!.userTeam.roster.standardCount, 13);
    });

    test('5. signing leaves the M007 season save untouched', () async {
      final dir = await Directory.systemTemp.createTemp('t07a_signing_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final seasonFile = File('${dir.path}/ballgorithm_save.json');
      const m007 = '{"schemaVersion":1,"id":"m007-season-state"}';
      await seasonFile.writeAsString(m007);

      final storage = FileGmCareerStorage(directoryPath: dir.path);
      await storage.write(GmCareerCodec.encode(completed));
      final controller = GmCareerController(storage: storage);
      addTearDown(controller.dispose);
      await controller.loadCareer();
      final rights = _userRights(controller.career!).first;

      await controller.signDraftedRookie(
        prospectId: rights.prospectId,
        category: RosterCategory.twoWay,
        durationYears: 1,
      );

      expect(await seasonFile.readAsString(), m007);
      expect(
        File('${dir.path}/ballgorithm_gm_career.json').existsSync(),
        isTrue,
      );
      final reloaded = GmCareerController(storage: storage);
      addTearDown(reloaded.dispose);
      await reloaded.loadCareer();
      expect(reloaded.career!.rookieSigningLedger.length, 1);
      expect(reloaded.career!.userTeam.roster.twoWayCount, 1);
    });
  });
}

GmCareer _completedCareer() {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: _team,
      selectedSituation: FranchiseSituation.playIn,
      seed: _seed,
    ),
  );
  var career = GmCareer.fromSetupResult(setup, id: 't07a-controller');
  const draft = DraftExecutionService();
  career = draft.startDraft(career);
  while (!career.draftExecutionState.isCompleted) {
    career =
        career.draftExecutionState.isHumanTurn(
          order: career.draftOrder,
          userTeamId: career.userFranchiseId,
        )
        ? draft.makeHumanSelection(
            career: career,
            prospectId: career.draftExecutionState
                .availableProspects(career.draftClass)
                .first
                .id,
          )
        : draft.executeAiSelection(career);
  }
  return career;
}

List<DraftRights> _userRights(GmCareer career) =>
    career.draftExecutionState.draftRights.values
        .where((rights) => rights.owningTeamId == career.userFranchiseId)
        .toList()
      ..sort((a, b) => a.overallPick.compareTo(b.overallPick));

class _ObservedStorage implements GmCareerStorage {
  _ObservedStorage(GmCareer initial)
    : data = GmCareerCodec.encode(initial),
      delegate = InMemoryGmCareerStorage({
        'default': GmCareerCodec.encode(initial),
      });

  final GmCareerStorage delegate;
  String data;
  int attempts = 0;
  int clears = 0;
  bool failNextWrite = false;
  bool failAfterCommit = false;

  GmCareer get saved => GmCareerCodec.decode(data);

  @override
  Future<String?> read({String slot = 'default'}) => delegate.read(slot: slot);

  @override
  Future<void> write(String next, {String slot = 'default'}) async {
    attempts++;
    final fail = failNextWrite || failAfterCommit;
    final commit = !failNextWrite || failAfterCommit;
    if (commit) {
      await delegate.write(next, slot: slot);
      data = next;
    }
    if (fail) {
      failNextWrite = false;
      failAfterCommit = false;
      throw const GmCareerStorageException('Injected signing write failure');
    }
  }

  @override
  Future<void> clear({String slot = 'default'}) async {
    clears++;
    await delegate.clear(slot: slot);
  }

  @override
  Future<bool> hasSave({String slot = 'default'}) =>
      delegate.hasSave(slot: slot);
}
