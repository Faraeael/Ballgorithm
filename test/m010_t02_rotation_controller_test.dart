import 'dart:convert';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

class _FailingStorage extends InMemoryGmCareerStorage {
  _FailingStorage(String initial) : super({'default': initial});

  bool failNextWrite = false;
  int writes = 0;

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw const GmCareerStorageException('Simulated rotation save failure');
    }
    writes++;
    await super.write(data, slot: slot);
  }
}

GmCareer? _clearedCache;

/// Real offseason up to clearance (no regular season yet).
GmCareer _cleared() => _clearedCache ??= () {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.contender,
      seed: 20261028,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 'm010-t02-controller');
  const draft = DraftExecutionService();
  c = draft.startDraft(c);
  while (!c.draftExecutionState.isCompleted) {
    final state = c.draftExecutionState;
    if (state.isHumanTurn(order: c.draftOrder, userTeamId: c.userFranchiseId)) {
      final pick = c.draftClass.prospects.firstWhere(
        (p) => !state.isProspectSelected(p.id),
      );
      c = draft.makeHumanSelection(career: c, prospectId: pick.id);
    } else {
      c = draft.executeAiSelection(c);
    }
  }
  const aiSigning = RookieAiSigningService();
  c = aiSigning.initialize(c);
  while (aiSigning.pendingRights(c).isNotEmpty) {
    c = aiSigning.applyNextDecision(c);
  }
  for (final r in c.unsignedDraftRights) {
    if (r.owningTeamId == c.userFranchiseId) {
      c = const RookieSigningService().signDraftedRookie(
        career: c,
        teamId: c.userFranchiseId,
        prospectId: r.prospectId,
        category: RosterCategory.standard,
        durationYears: 2,
      );
    }
  }
  const market = FreeAgentMarketService();
  for (var round = 0; round < 2; round++) {
    c = market.startRound(c);
    c = market.prepareResolution(c);
    while (c.freeAgentMarket.isResolvable) {
      c = market.resolveNext(c);
    }
  }
  const clearance = OffseasonClearanceService();
  c = clearance.start(c);
  c = clearance.prepare(c);
  while (c.offseasonClearance.isResolvable) {
    c = clearance.resolveNext(c);
  }
  const hardship = HardshipSettlementService();
  c = hardship.prepare(c, humanParticipationConfirmed: true);
  while (c.hardshipSettlement.isResolvable) {
    c = hardship.resolveNext(c);
  }
  return clearance.markCleared(c);
}();

GmCareer _scheduled() => const RegularSeasonScheduleService().generate(
  const RegularSeasonEntryService().start(_cleared()),
);

CareerRotationSettings _manual(GmCareer c) {
  final team = RegularSeasonGameAdapter.standardTeamFor(c.userTeam);
  final lineup = CourtLineup.defaultFor(team);
  final bench = team.players.firstWhere(
    (p) => !lineup.playerIds.contains(p.id.value),
  );
  return CareerRotationSettings.manual(
    starters: [
      bench.id,
      for (final id in lineup.playerIds.skip(1)) PlayerId(id),
    ],
    preset: RotationPreset.starterHeavy,
  );
}

Future<GmCareerController> _controllerFor(InMemoryGmCareerStorage s) async {
  final controller = GmCareerController(storage: s);
  await controller.loadCareer();
  return controller;
}

void main() {
  group('M010-T02 rotation controller commands', () {
    test(
      'manual plan: single-round and batch produce identical saves',
      () async {
        final start = _scheduled();
        final single = await _controllerFor(
          InMemoryGmCareerStorage({'default': GmCareerCodec.encode(start)}),
        );
        final batch = await _controllerFor(
          InMemoryGmCareerStorage({'default': GmCareerCodec.encode(start)}),
        );
        addTearDown(single.dispose);
        addTearDown(batch.dispose);
        final settings = _manual(start);
        await single.updateUserRotation(settings);
        await batch.updateUserRotation(settings);

        await single.simulateNextRegularSeasonRound(
          expectedRoundNumber: 1,
          confirmed: true,
        );
        await single.simulateNextRegularSeasonRound(
          expectedRoundNumber: 2,
          confirmed: true,
        );
        await batch.simulateRegularSeasonBatch(
          expectedStartRound: 1,
          roundCount: 2,
          confirmed: true,
        );
        expect(
          GmCareerCodec.encode(batch.career!),
          GmCareerCodec.encode(single.career!),
        );
        expect(batch.career!.userRotation, settings);
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'edits are rejected while a batch is queued or running; batch uses committed plan',
      () async {
        final start = _scheduled();
        final storage = _FailingStorage(GmCareerCodec.encode(start));
        final controller = await _controllerFor(storage);
        addTearDown(controller.dispose);
        final settings = _manual(start);
        await controller.updateUserRotation(settings);

        final running = controller.simulateRegularSeasonBatch(
          expectedStartRound: 1,
          roundCount: 2,
          confirmed: true,
        );
        // Synchronously after queuing, before the batch body starts.
        await expectLater(
          controller.resetUserRotationToAuto(),
          throwsA(isA<StateError>()),
        );
        while (!controller.isBatchSimulating) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await expectLater(
          controller.updateUserRotation(CareerRotationSettings.auto),
          throwsA(isA<StateError>()),
        );
        await running;
        final career = controller.career!;
        expect(career.userRotation, settings);
        expect(career.regularSeasonState!.completedRounds, 2);
        final user = career.userFranchiseId.value;
        for (final r in career.regularSeasonState!.gameResults.values) {
          final side = r.homeTeamId.value == user
              ? 'home'
              : r.awayTeamId.value == user
              ? 'away'
              : null;
          if (side == null) continue;
          final template =
              jsonDecode(r.inputEvidence!.payloadTemplateJson) as Map;
          expect(
            (template['${side}Lineup'] as List)
                .map((s) => (s as Map)['playerId'])
                .toList(),
            settings.starters.map((id) => id.value).toList(),
          );
        }
        // Editing is allowed again once idle.
        await controller.resetUserRotationToAuto();
        expect(controller.career!.userRotation, CareerRotationSettings.auto);
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'invalid edits write nothing; save failure keeps committed settings',
      () async {
        final start = _scheduled();
        final storage = _FailingStorage(GmCareerCodec.encode(start));
        final controller = await _controllerFor(storage);
        addTearDown(controller.dispose);
        final team = RegularSeasonGameAdapter.standardTeamFor(start.userTeam);
        final manual = _manual(start);
        final starterIds = {for (final id in manual.starters) id.value};

        // Wrong total (starters only 60 s each) -> typed issue, no write.
        final badTotal = CareerRotationSettings.manual(
          starters: manual.starters,
          preset: RotationPreset.custom,
          customTargets: {
            for (final p in team.players)
              p.id.value: starterIds.contains(p.id.value) ? 60 : 0,
          },
        );
        await expectLater(
          controller.updateUserRotation(badTotal),
          throwsA(isA<CareerRotationInvalidException>()),
        );
        // Custom plan that omits a standard player -> rejected (D7).
        final omitted = CareerRotationSettings.manual(
          starters: manual.starters,
          preset: RotationPreset.custom,
          customTargets: {
            for (final p in team.players.take(team.players.length - 1))
              p.id.value: starterIds.contains(p.id.value) ? 2880 : 0,
          },
        );
        await expectLater(
          controller.updateUserRotation(omitted),
          throwsA(isA<StateError>()),
        );
        // Foreign starter -> rejected.
        final foreign = CareerRotationSettings.manual(
          starters: [
            const PlayerId('not-on-roster'),
            ...manual.starters.skip(1),
          ],
          preset: RotationPreset.balanced,
        );
        await expectLater(
          controller.updateUserRotation(foreign),
          throwsA(isA<CareerRotationInvalidException>()),
        );
        expect(storage.writes, 0);
        expect(controller.career!.userRotation, CareerRotationSettings.auto);

        // Failed save: previous settings remain, recovery flow engages.
        storage.failNextWrite = true;
        await expectLater(
          controller.updateUserRotation(manual),
          throwsA(isA<GmCareerStorageException>()),
        );
        expect(controller.career!.userRotation, CareerRotationSettings.auto);
        expect(controller.draftRecoveryRequired, isTrue);
        expect(
          GmCareerCodec.decode((await storage.read())!).userRotation,
          CareerRotationSettings.auto,
        );
        await controller.loadCareer();
        expect(controller.draftRecoveryRequired, isFalse);
        await controller.updateUserRotation(manual);
        expect(
          GmCareerCodec.decode((await storage.read())!).userRotation,
          manual,
        );
      },
    );

    test(
      'obsolete offseason plan: repair writes only on explicit command',
      () async {
        final cleared = _cleared();
        final team = RegularSeasonGameAdapter.standardTeamFor(cleared.userTeam);
        final lineup = CourtLineup.defaultFor(team);
        final obsolete = CareerRotationSettings.manual(
          starters: [
            const PlayerId('departed-player'),
            for (final id in lineup.playerIds.skip(1)) PlayerId(id),
          ],
          preset: RotationPreset.balanced,
        );
        final storage = _FailingStorage(
          GmCareerCodec.encode(cleared.copyWith(userRotation: obsolete)),
        );
        final controller = await _controllerFor(storage);
        addTearDown(controller.dispose);
        expect(controller.career!.userRotation, obsolete);
        await expectLater(
          controller.startRegularSeason(confirmed: true),
          throwsA(isA<CareerRotationInvalidException>()),
        );
        expect(controller.career!.userRotation, obsolete);
        expect(controller.career!.phase, CareerPhase.openingOffseason);

        await controller.applyUserRotationRepair();
        final repaired = controller.career!.userRotation;
        expect(repaired.isManual, isTrue);
        expect(repaired.starters.skip(1), obsolete.starters.skip(1));
        expect(
          CareerRotationService.resolveForCareer(controller.career!).isValid,
          isTrue,
        );
        await expectLater(
          controller.applyUserRotationRepair(),
          throwsA(isA<StateError>()),
        );
        await controller.startRegularSeason(confirmed: true);
        expect(controller.career!.phase, CareerPhase.regularSeason);
      },
    );
  });
}
