import 'dart:convert';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

GmCareer _enabledScheduled() {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: 20261028,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 'm011-t03-controller');
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
  c = const StaffMarketService().enableCoaching(c);
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
  c = clearance.markCleared(c);
  return const RegularSeasonScheduleService().generate(
    const RegularSeasonEntryService().start(c),
  );
}

Future<GmCareerController> _controllerFor(InMemoryGmCareerStorage s) async {
  final controller = GmCareerController(storage: s);
  await controller.loadCareer();
  return controller;
}

void main() {
  test(
    'coaching on: single-round and batch saves are identical and coach-driven',
    () async {
      final start = _enabledScheduled();
      expect(start.staff.coachingEnabled, isTrue);
      final singleStorage = InMemoryGmCareerStorage({
        'default': GmCareerCodec.encode(start),
      });
      final single = await _controllerFor(singleStorage);
      final batch = await _controllerFor(
        InMemoryGmCareerStorage({'default': GmCareerCodec.encode(start)}),
      );
      addTearDown(single.dispose);
      addTearDown(batch.dispose);

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
      final career = single.career!;
      expect(GmCareerCodec.encode(batch.career!), GmCareerCodec.encode(career));

      var userGames = 0;
      for (final r in career.regularSeasonState!.gameResults.values) {
        final template =
            jsonDecode(r.inputEvidence!.payloadTemplateJson) as Map;
        for (final (side, id) in [
          ('home', r.homeTeamId),
          ('away', r.awayTeamId),
        ]) {
          final team = RegularSeasonGameAdapter.standardTeamFor(
            career.league.teams.firstWhere((t) => t.id == id),
          );
          final decision = CareerRotationService.decisionFor(career, team);
          if (decision.authority == RotationAuthority.headCoach &&
              id == career.userFranchiseId) {
            userGames++;
          }
          expect(
            (template['${side}Lineup'] as List)
                .map((s) => (s as Map)['playerId'])
                .toList(),
            decision.lineup.playerIds,
          );
        }
      }
      expect(userGames, 2);

      // Restart: staff, activation and results survive.
      final reloaded = await _controllerFor(singleStorage);
      addTearDown(reloaded.dispose);
      expect(
        GmCareerCodec.encode(reloaded.career!),
        GmCareerCodec.encode(career),
      );
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
