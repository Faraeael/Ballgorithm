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
      throw const GmCareerStorageException('Simulated staff save failure');
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
      selectedSituation: FranchiseSituation.tanking,
      seed: 20261028,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 'm011-t02-controller');
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

Future<GmCareerController> _controllerFor(InMemoryGmCareerStorage s) async {
  final controller = GmCareerController(storage: s);
  await controller.loadCareer();
  return controller;
}

void main() {
  group('M011-T02 staff controller commands', () {
    test('enable, replace and renew persist and reload identically', () async {
      final storage = InMemoryGmCareerStorage({
        'default': GmCareerCodec.encode(_cleared()),
      });
      final controller = await _controllerFor(storage);
      addTearDown(controller.dispose);
      await controller.enableCoaching();
      final candidate = const StaffMarketService()
          .headCoachCandidates(controller.career!)
          .first;
      await controller.replaceHeadCoach(
        candidateId: candidate.id,
        durationYears: 2,
      );
      await controller.renewHeadCoach(additionalYears: 1);

      final career = controller.career!;
      final coach = career.staff.employedHeadCoach(career.userFranchiseId)!;
      expect(coach.id, candidate.id);
      expect(
        career.finances.staffCommitments[coach.commitmentId]!.durationYears,
        3,
      );
      final reloaded = await _controllerFor(storage);
      addTearDown(reloaded.dispose);
      expect(
        GmCareerCodec.encode(reloaded.career!),
        GmCareerCodec.encode(career),
      );
    });

    test('staff commands are rejected while another command runs', () async {
      final storage = _FailingStorage(GmCareerCodec.encode(_cleared()));
      final controller = await _controllerFor(storage);
      addTearDown(controller.dispose);
      final first = controller.enableCoaching();
      await expectLater(
        controller.dismissHeadCoach(),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        controller.delegateUserRotationKeepingManual(),
        throwsA(isA<StateError>()),
      );
      await first;
      expect(storage.writes, 1);
      expect(controller.career!.staff.coachingEnabled, isTrue);
      expect(
        controller.career!.staff.employedHeadCoach(
          controller.career!.userFranchiseId,
        ),
        isNotNull,
        reason: 'the rejected dismissal never ran',
      );
    });

    test(
      'rejections write nothing; failed save keeps the old career',
      () async {
        final start = _cleared();
        final storage = _FailingStorage(GmCareerCodec.encode(start));
        final controller = await _controllerFor(storage);
        addTearDown(controller.dispose);

        // Coaching disabled: typed rejection, no write, no change.
        await expectLater(
          controller.dismissHeadCoach(),
          throwsA(isA<StaffTransactionRejected>()),
        );
        expect(storage.writes, 0);
        expect(
          GmCareerCodec.encode(controller.career!),
          GmCareerCodec.encode(start),
        );

        await controller.enableCoaching();
        final enabled = GmCareerCodec.encode(controller.career!);
        final candidate = const StaffMarketService()
            .headCoachCandidates(controller.career!)
            .first;
        storage.failNextWrite = true;
        await expectLater(
          controller.replaceHeadCoach(
            candidateId: candidate.id,
            durationYears: 2,
          ),
          throwsA(isA<GmCareerStorageException>()),
        );
        expect(GmCareerCodec.encode(controller.career!), enabled);
        expect(await storage.read(), enabled, reason: 'no partial transaction');
        expect(controller.draftRecoveryRequired, isTrue);
        await controller.loadCareer();
        expect(controller.draftRecoveryRequired, isFalse);
        await controller.replaceHeadCoach(
          candidateId: candidate.id,
          durationYears: 2,
        );
        expect(
          GmCareerCodec.decode(
            (await storage.read())!,
          ).staff.employedHeadCoach(start.userFranchiseId)!.id,
          candidate.id,
        );
      },
    );

    test(
      'AUTO keeps the manual plan and restores it after validation',
      () async {
        final start = _cleared();
        final storage = InMemoryGmCareerStorage({
          'default': GmCareerCodec.encode(start),
        });
        final controller = await _controllerFor(storage);
        addTearDown(controller.dispose);
        final team = RegularSeasonGameAdapter.standardTeamFor(start.userTeam);
        final lineup = CourtLineup.defaultFor(team);
        final manual = CareerRotationSettings.manual(
          starters: [for (final id in lineup.playerIds.reversed) PlayerId(id)],
          preset: RotationPreset.starterHeavy,
        );
        await controller.updateUserRotation(manual);
        await controller.delegateUserRotationKeepingManual();
        expect(controller.career!.userRotation.isManual, isFalse);
        expect(controller.career!.userRotation.retainedManual, manual);
        await controller.restoreRetainedManualRotation();
        expect(controller.career!.userRotation, manual);
        await expectLater(
          controller.restoreRetainedManualRotation(),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}
