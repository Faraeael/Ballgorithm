import 'dart:convert';

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

  group('M008-T07C AI signing controller', () {
    test('loading a career never advances AI signing automatically', () async {
      final storage = _ObservedStorage(completed);
      final controller = GmCareerController(storage: storage);
      addTearDown(controller.dispose);
      await controller.loadCareer();

      expect(controller.career!.aiRookieSigning.isEmpty, isTrue);
      expect(storage.attempts, 0);
    });

    test('advancing persists each decision and skips human rights', () async {
      final storage = _ObservedStorage(completed);
      final controller = GmCareerController(storage: storage);
      addTearDown(controller.dispose);
      await controller.loadCareer();

      await controller.advanceAiRookieSigning();

      final career = controller.career!;
      final aiRights = career.draftExecutionState.draftRights.values.where(
        (rights) => rights.owningTeamId != career.userFranchiseId,
      );
      expect(career.aiRookieSigning.length, aiRights.length);
      expect(career.aiRookieSigning.length, 58);
      expect(storage.attempts, 58);
      expect(storage.saved.aiRookieSigning.length, 58);
      for (final rights in career.draftExecutionState.draftRights.values.where(
        (rights) => rights.owningTeamId == career.userFranchiseId,
      )) {
        expect(career.aiRookieSigning.hasDecision(rights.prospectId), isFalse);
        expect(career.rookieSigningLedger.isSigned(rights.prospectId), isFalse);
      }
      expect(controller.errorMessage, isNull);
    });

    test('a completed process performs no further writes', () async {
      final storage = _ObservedStorage(completed);
      final controller = GmCareerController(storage: storage);
      addTearDown(controller.dispose);
      await controller.loadCareer();
      await controller.advanceAiRookieSigning();
      final attempts = storage.attempts;
      final encoded = GmCareerCodec.encode(controller.career!);

      await controller.advanceAiRookieSigning();

      expect(storage.attempts, attempts);
      expect(GmCareerCodec.encode(controller.career!), encoded);
    });

    test('a failed write stops progress until reload, then resumes', () async {
      final storage = _ObservedStorage(completed);
      final controller = GmCareerController(storage: storage);
      addTearDown(controller.dispose);
      await controller.loadCareer();

      storage.failAtAttempt = 6;
      await expectLater(
        controller.advanceAiRookieSigning(),
        throwsA(isA<GmCareerStorageException>()),
      );

      expect(controller.career!.aiRookieSigning.length, 5);
      expect(controller.draftRecoveryRequired, isTrue);
      expect(storage.saved.aiRookieSigning.length, 5);
      expect(controller.errorMessage, isNotNull);

      await expectLater(
        controller.advanceAiRookieSigning(),
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
      expect(controller.career!.aiRookieSigning.length, 5);

      await controller.advanceAiRookieSigning();
      final career = controller.career!;
      expect(career.aiRookieSigning.length, 58);
      expect(storage.saved.aiRookieSigning.length, 58);
      final contractIds = career.rookieSigningLedger.contracts.values
          .map((contract) => contract.id)
          .toList();
      expect(contractIds.toSet().length, contractIds.length);
      expect(
        jsonEncode(career.aiRookieSigning.toJson()),
        jsonEncode(storage.saved.aiRookieSigning.toJson()),
      );
    });

    test('an uncertain write reconciles through reload', () async {
      final storage = _ObservedStorage(completed);
      final controller = GmCareerController(storage: storage);
      addTearDown(controller.dispose);
      await controller.loadCareer();

      storage.failAfterCommitAtAttempt = 4;
      await expectLater(
        controller.advanceAiRookieSigning(),
        throwsA(isA<GmCareerStorageException>()),
      );
      expect(controller.career!.aiRookieSigning.length, 3);
      expect(controller.draftRecoveryRequired, isTrue);
      expect(storage.saved.aiRookieSigning.length, 4);

      await controller.loadCareer();
      expect(controller.career!.aiRookieSigning.length, 4);
      await controller.advanceAiRookieSigning();
      expect(controller.career!.aiRookieSigning.length, 58);
      expect(storage.saved.aiRookieSigning.length, 58);
    });

    test('advancing before the draft completes is rejected', () async {
      final initial = GmCareer.fromSetupResult(
        const CareerSetupService().generate(
          const CareerSetupRequest(
            selectedTeamId: _team,
            selectedSituation: FranchiseSituation.playIn,
            seed: _seed,
          ),
        ),
        id: 't07c-controller-incomplete',
      );
      final storage = _ObservedStorage(initial);
      final controller = GmCareerController(storage: storage);
      addTearDown(controller.dispose);
      await controller.loadCareer();

      await expectLater(
        controller.advanceAiRookieSigning(),
        throwsA(isA<StateError>()),
      );
      expect(storage.attempts, 0);
      expect(controller.career!.aiRookieSigning.isEmpty, isTrue);
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
  var career = GmCareer.fromSetupResult(setup, id: 't07c-controller');
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

class _ObservedStorage implements GmCareerStorage {
  _ObservedStorage(GmCareer initial)
    : data = GmCareerCodec.encode(initial),
      delegate = InMemoryGmCareerStorage({
        'default': GmCareerCodec.encode(initial),
      });

  final GmCareerStorage delegate;
  String data;
  int attempts = 0;
  int? failAtAttempt;
  int? failAfterCommitAtAttempt;

  GmCareer get saved => GmCareerCodec.decode(data);

  @override
  Future<String?> read({String slot = 'default'}) => delegate.read(slot: slot);

  @override
  Future<void> write(String next, {String slot = 'default'}) async {
    attempts++;
    final failBefore = attempts == failAtAttempt;
    final failAfter = attempts == failAfterCommitAtAttempt;
    if (failBefore || failAfter) {
      failAtAttempt = null;
      failAfterCommitAtAttempt = null;
    }
    if (!failBefore) {
      await delegate.write(next, slot: slot);
      data = next;
    }
    if (failBefore || failAfter) {
      throw const GmCareerStorageException('Injected AI signing write failure');
    }
  }

  @override
  Future<void> clear({String slot = 'default'}) => delegate.clear(slot: slot);

  @override
  Future<bool> hasSave({String slot = 'default'}) =>
      delegate.hasSave(slot: slot);
}
