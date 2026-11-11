import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

Map<String, dynamic> _copyJson(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

void main() {
  const service = DraftExecutionService();
  late GmCareer initial;
  late GmCareer started;
  late GmCareer firstPick;
  late GmCareer completed;

  setUpAll(() {
    initial = GmCareer.fromSetupResult(
      const CareerSetupService().generate(
        const CareerSetupRequest(
          selectedTeamId: TeamId('team-1'),
          selectedSituation: FranchiseSituation.tanking,
          seed: 20261028,
        ),
      ),
      id: 'draft-integrity',
    );
    started = service.startDraft(initial);
    firstPick = service.makeHumanSelection(
      career: started,
      prospectId: started.draftClass.prospects.first.id,
    );
    var current = firstPick;
    while (!current.draftExecutionState.isCompleted) {
      if (current.draftExecutionState.isHumanTurn(
        order: current.draftOrder,
        userTeamId: current.userFranchiseId,
      )) {
        current = service.makeHumanSelection(
          career: current,
          prospectId: current.draftExecutionState
              .availableProspects(current.draftClass)
              .first
              .id,
        );
      } else {
        current = service.executeAiSelection(current);
      }
    }
    completed = current;
  });

  test(
    'start and selection commands each commit only their own transition',
    () {
      expect(initial.draftExecutionState.isNotStarted, isTrue);
      expect(started.draftExecutionState.isInProgress, isTrue);
      expect(started.draftExecutionState.selections, isEmpty);
      expect(firstPick.draftExecutionState.completedSelectionsCount, 1);
      final next = service.executeAiSelection(firstPick);
      expect(next.draftExecutionState.completedSelectionsCount, 2);
      expect(next.draftExecutionState.selections.last.overallPick, 2);
      expect(firstPick.draftExecutionState.completedSelectionsCount, 1);
      expect(identical(next.league, initial.league), isTrue);
    },
  );

  test('illegal lifecycle and ownership commands leave input unchanged', () {
    for (final career in [initial, started, firstPick, completed]) {
      final before = GmCareerCodec.encode(career);
      if (!career.draftExecutionState.isNotStarted) {
        expect(() => service.startDraft(career), throwsStateError);
      }
      if (!career.draftExecutionState.isInProgress ||
          career.draftExecutionState.isHumanTurn(
            order: career.draftOrder,
            userTeamId: career.userFranchiseId,
          )) {
        expect(() => service.executeAiSelection(career), throwsStateError);
      }
      if (!career.draftExecutionState.isInProgress ||
          !career.draftExecutionState.isHumanTurn(
            order: career.draftOrder,
            userTeamId: career.userFranchiseId,
          )) {
        expect(
          () => service.makeHumanSelection(
            career: career,
            prospectId: career.draftClass.prospects.last.id,
          ),
          throwsStateError,
        );
      }
      expect(GmCareerCodec.encode(career), before);
    }
    expect(
      () => service.advanceUntilHumanOrComplete(initial),
      throwsStateError,
    );
    expect(service.advanceUntilHumanOrComplete(completed), same(completed));
    expect(service.advanceUntilHumanOrComplete(started), same(started));
    expect(
      () => service.makeHumanSelection(
        career: started,
        prospectId: const PlayerId('unknown-prospect'),
      ),
      throwsArgumentError,
    );
    final secondHuman = service.advanceUntilHumanOrComplete(firstPick);
    final before = GmCareerCodec.encode(secondHuman);
    expect(secondHuman.draftExecutionState.currentOverallPick, 31);
    expect(
      () => service.makeHumanSelection(
        career: secondHuman,
        prospectId: firstPick.draftExecutionState.selections.first.prospectId,
      ),
      throwsStateError,
    );
    expect(GmCareerCodec.encode(secondHuman), before);
  });

  test(
    'every command result persists and resumes without replaying a pick',
    () {
      var current = initial;
      for (var step = 0; step <= 61; step++) {
        final encoded = GmCareerCodec.encode(current);
        final restored = GmCareerCodec.decode(encoded);
        expect(GmCareerCodec.encode(restored), encoded);
        if (step == 61) {
          expect(restored.draftExecutionState.isCompleted, isTrue);
          expect(restored.draftExecutionState.selections.length, 60);
          expect(
            restored.draftExecutionState
                .undraftedProspects(restored.draftClass)
                .length,
            30,
          );
          break;
        }
        GmCareer advance(GmCareer career) {
          if (career.draftExecutionState.isNotStarted) {
            return service.startDraft(career);
          }
          if (career.draftExecutionState.isHumanTurn(
            order: career.draftOrder,
            userTeamId: career.userFranchiseId,
          )) {
            return service.makeHumanSelection(
              career: career,
              prospectId: career.draftExecutionState
                  .availableProspects(career.draftClass)
                  .first
                  .id,
            );
          }
          return service.executeAiSelection(career);
        }

        final next = advance(current);
        expect(
          GmCareerCodec.encode(advance(restored)),
          GmCareerCodec.encode(next),
        );
        current = next;
      }
    },
  );

  test(
    'current ownership controls commands and rights, not original entitlement',
    () {
      final aiOwner = initial.draftOrder.pickAt(2).currentOwnerTeamId;
      final orderJson = _copyJson(initial.draftOrder.toJson());
      final picks = orderJson['picks'] as List<dynamic>;
      (picks[0] as Map<String, dynamic>)['currentOwnerTeamId'] = aiOwner.value;
      (picks[1] as Map<String, dynamic>)['currentOwnerTeamId'] =
          initial.userFranchiseId.value;
      final traded = service.startDraft(
        initial.copyWith(draftOrder: DraftOrder.fromJson(orderJson)),
      );
      expect(
        () => service.makeHumanSelection(
          career: traded,
          prospectId: traded.draftClass.prospects.first.id,
        ),
        throwsStateError,
      );
      final aiPick = service.executeAiSelection(traded);
      final selection = aiPick.draftExecutionState.selections.single;
      expect(selection.originalOwnerTeamId, initial.userFranchiseId);
      expect(selection.selectingTeamId, aiOwner);
      expect(
        aiPick
            .draftExecutionState
            .draftRights[selection.prospectId.value]!
            .owningTeamId,
        aiOwner,
      );
      expect(() => service.executeAiSelection(aiPick), throwsStateError);
      final humanPick = service.makeHumanSelection(
        career: aiPick,
        prospectId: aiPick.draftExecutionState
            .availableProspects(aiPick.draftClass)
            .first
            .id,
      );
      expect(
        humanPick.draftExecutionState.selections.last.selectingTeamId,
        initial.userFranchiseId,
      );
      expect(
        humanPick.draftExecutionState.selections.last.originalOwnerTeamId,
        aiOwner,
      );
    },
  );

  final selectionCorruptions = <String, dynamic>{
    'seasonYear': 2,
    'round': 2,
    'pickInRound': 2,
    'overallPick': 2,
    'originalOwnerTeamId': 'unknown-team',
    'selectingTeamId': 'unknown-team',
    'prospectId': 'unknown-prospect',
  };
  for (final entry in selectionCorruptions.entries) {
    test('rejects selection corruption: ${entry.key}', () {
      final json = _copyJson(firstPick.draftExecutionState.toJson());
      final selection =
          (json['selections'] as List<dynamic>).single as Map<String, dynamic>;
      selection[entry.key] = entry.value;
      expect(() {
        final state = DraftExecutionState.fromJson(json);
        state.validate(
          order: initial.draftOrder,
          draftClass: initial.draftClass,
          seasonYear: initial.currentYear,
        );
      }, throwsFormatException);
    });
  }

  final rightsCorruptions = <String, dynamic>{
    'seasonYear': 2,
    'overallPick': 2,
    'owningTeamId': 'unknown-team',
    'prospectId': 'unknown-prospect',
  };
  for (final entry in rightsCorruptions.entries) {
    test('rejects rights corruption: ${entry.key}', () {
      final json = _copyJson(firstPick.draftExecutionState.toJson());
      final rights = json['draftRights'] as Map<String, dynamic>;
      (rights.values.single as Map<String, dynamic>)[entry.key] = entry.value;
      expect(() => DraftExecutionState.fromJson(json), throwsFormatException);
    });
  }

  test('rejects missing, extra, and mismatched rights keys', () {
    for (final change in ['missing', 'extra', 'mismatched']) {
      final json = _copyJson(firstPick.draftExecutionState.toJson());
      final rights = json['draftRights'] as Map<String, dynamic>;
      final record = rights.values.single;
      if (change == 'missing' || change == 'mismatched') rights.clear();
      if (change != 'missing') rights['unknown-prospect'] = record;
      expect(() => DraftExecutionState.fromJson(json), throwsFormatException);
    }
  });

  test('rejects internally consistent unknown prospect and wrong season', () {
    for (final field in ['prospectId', 'seasonYear']) {
      final json = _copyJson(firstPick.draftExecutionState.toJson());
      final selection =
          (json['selections'] as List<dynamic>).single as Map<String, dynamic>;
      final rights = json['draftRights'] as Map<String, dynamic>;
      final record = rights.values.single as Map<String, dynamic>;
      final value = field == 'prospectId' ? 'unknown-prospect' : 2;
      selection[field] = value;
      record[field] = value;
      if (field == 'prospectId') {
        rights.clear();
        rights[value as String] = record;
      }
      expect(
        () => DraftExecutionState.fromJson(json).validate(
          order: initial.draftOrder,
          draftClass: initial.draftClass,
          seasonYear: initial.currentYear,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => initial.draftExecutionState.validate(
        order: initial.draftOrder,
        draftClass: initial.draftClass,
        seasonYear: 2,
      ),
      throwsFormatException,
    );
  });

  test(
    'rejects duplicate prospects, reordered picks, and inconsistent statuses',
    () {
      final twoPicks = service.executeAiSelection(firstPick);
      for (final change in [
        'duplicate',
        'reordered',
        'notStarted',
        'completed',
      ]) {
        final json = _copyJson(twoPicks.draftExecutionState.toJson());
        final selections = json['selections'] as List<dynamic>;
        if (change == 'duplicate') {
          (selections[1] as Map<String, dynamic>)['prospectId'] =
              (selections[0] as Map<String, dynamic>)['prospectId'];
        } else if (change == 'reordered') {
          json['selections'] = selections.reversed.toList();
        } else {
          json['status'] = change;
        }
        expect(() => DraftExecutionState.fromJson(json), throwsFormatException);
      }
      final full = _copyJson(completed.draftExecutionState.toJson());
      full['status'] = 'inProgress';
      expect(() => DraftExecutionState.fromJson(full), throwsFormatException);
      final empty = _copyJson(initial.draftExecutionState.toJson());
      empty['status'] = 'completed';
      expect(() => DraftExecutionState.fromJson(empty), throwsFormatException);
    },
  );

  test('rejects consistent records with wrong authoritative ownership', () {
    final differentOwner = initial.draftOrder
        .pickAt(2)
        .currentOwnerTeamId
        .value;
    for (final field in ['originalOwnerTeamId', 'selectingTeamId']) {
      final json = _copyJson(firstPick.draftExecutionState.toJson());
      final selection =
          (json['selections'] as List<dynamic>).single as Map<String, dynamic>;
      selection[field] = differentOwner;
      if (field == 'selectingTeamId') {
        final rights = json['draftRights'] as Map<String, dynamic>;
        (rights.values.single as Map<String, dynamic>)['owningTeamId'] =
            differentOwner;
      }
      expect(
        () => DraftExecutionState.fromJson(json).validate(
          order: initial.draftOrder,
          draftClass: initial.draftClass,
          seasonYear: initial.currentYear,
        ),
        throwsFormatException,
      );
    }
  });

  test('records reject malformed field types and invalid bounds', () {
    final selection = firstPick.draftExecutionState.selections.single.toJson();
    for (final value in [null, '1', 0, 61]) {
      expect(
        () => DraftSelection.fromJson({...selection, 'overallPick': value}),
        throwsFormatException,
      );
    }
    final rights = firstPick.draftExecutionState.draftRights.values.single
        .toJson();
    for (final value in [null, '1', 0, -1]) {
      expect(
        () => DraftRights.fromJson({...rights, 'seasonYear': value}),
        throwsFormatException,
      );
    }
    expect(
      () => DraftExecutionState.fromJson({
        'status': 'inProgress',
        'selections': [1],
        'draftRights': <String, dynamic>{},
      }),
      throwsFormatException,
    );
  });

  test('state copies input collections and rejects external mutation', () {
    final selections = [...firstPick.draftExecutionState.selections];
    final rights = {...firstPick.draftExecutionState.draftRights};
    final state = DraftExecutionState(
      status: DraftExecutionStatus.inProgress,
      selections: selections,
      draftRights: rights,
    );
    selections.clear();
    rights.clear();
    expect(state.selections.length, 1);
    expect(state.draftRights.length, 1);
    expect(() => state.selections.clear(), throwsUnsupportedError);
    expect(() => state.draftRights.clear(), throwsUnsupportedError);
    expect(
      () => initial.draftExecutionState.withSelection(
        selection: state.selections.single,
        rights: state.draftRights.values.single,
      ),
      throwsStateError,
    );
    expect(
      () => completed.draftExecutionState.withSelection(
        selection: state.selections.single,
        rights: state.draftRights.values.single,
      ),
      throwsStateError,
    );
  });
}
