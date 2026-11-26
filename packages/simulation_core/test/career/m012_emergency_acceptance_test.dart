import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import '../support/career_season_fixtures.dart';

GmCareer _settle(GmCareer c) {
  const market = FreeAgentMarketService();
  const clearance = OffseasonClearanceService();
  const hardship = HardshipSettlementService();
  for (var round = 0; round < 2; round++) {
    c = market.prepareResolution(market.startRound(c));
    while (c.freeAgentMarket.isResolvable) {
      c = market.resolveNext(c);
    }
  }
  c = clearance.prepare(clearance.start(c));
  while (c.offseasonClearance.isResolvable) {
    c = clearance.resolveNext(c);
  }
  c = hardship.prepare(c, humanParticipationConfirmed: true);
  while (c.hardshipSettlement.isResolvable) {
    c = hardship.resolveNext(c);
  }
  return c;
}

/// Seed 8675309, human team-1, one own drafted rookie deliberately unsigned.
GmCareer _humanShortCareer() {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: 8675309,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 'emergency-human-8675309');
  const draft = DraftExecutionService();
  const ai = RookieAiSigningService();
  c = draft.startDraft(c);
  while (!c.draftExecutionState.isCompleted) {
    if (c.draftExecutionState.isHumanTurn(
      order: c.draftOrder,
      userTeamId: c.userFranchiseId,
    )) {
      final pick = c.draftClass.prospects.firstWhere(
        (p) => !c.draftExecutionState.draftRights.containsKey(p.id.value),
      );
      c = draft.makeHumanSelection(career: c, prospectId: pick.id);
    } else {
      c = draft.executeAiSelection(c);
    }
  }
  c = ai.initialize(c);
  while (ai.pendingRights(c).isNotEmpty) {
    c = ai.applyNextDecision(c);
  }
  final own = c.unsignedDraftRights
      .where((r) => r.owningTeamId == c.userFranchiseId)
      .toList();
  for (final r in own.skip(1)) {
    c = const RookieSigningService().signDraftedRookie(
      career: c,
      teamId: c.userFranchiseId,
      prospectId: r.prospectId,
      category: RosterCategory.standard,
      durationYears: 2,
    );
  }
  return _settle(c);
}

Map<String, dynamic> _json(GmCareer career) =>
    jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;

void _rejects(Map<String, dynamic> raw) =>
    expect(() => GmCareerCodec.decode(jsonEncode(raw)), throwsFormatException);

/// Removes standard players while preserving position coverage.
Team _shortTeam(Team team, int standard) {
  var roster = team.roster;
  for (final player in team.roster.standardPlayers) {
    if (roster.standardCount <= standard) break;
    final next = roster.withoutPlayer(player.id);
    if (Position.values.every(next.covers)) roster = next;
  }
  expect(roster.standardCount, standard);
  return team.copyWith(roster: roster);
}

void main() {
  late GmCareer rsc;
  late GmCareer human;
  const service = EmergencyRosterService();

  setUpAll(() {
    rsc = _settle(preFreeAgencyOffseason(seed: 271828182));
    human = _humanShortCareer();
  });

  group('joint allocation', () {
    late Team a;
    late Team b;
    late List<FreeAgentEntry> pool;
    EmergencyAllocation run(
      List<EmergencyNeed> needs,
      List<FreeAgentEntry> entries,
      EmergencyWillingness accepts, {
      int limit = 200000,
    }) => EmergencyRosterService(maxSearchStates: limit).allocate(
      seasonYear: 1,
      phase: CareerPhase.openingOffseason,
      needs: needs,
      entries: entries,
      accepts: accepts,
    );
    bool from(
      int minimum,
      Team original,
      Team current,
      FreeAgentEntry entry,
      int salary,
    ) => salary >= minimum;

    setUpAll(() {
      final ready = [
        for (final team in rsc.league.teams)
          if (team.roster.standardCount >= 14) team,
      ];
      a = _shortTeam(ready[0], 13);
      b = _shortTeam(ready[1], 13);
      pool = [...rsc.freeAgentPool.entries]
        ..sort((x, y) => x.id.value.compareTo(y.id.value));
    });

    test('competing claims receive unique players', () {
      final result = run(
        [
          EmergencyNeed(team: a, payroll: 41000, cash: 5000),
          EmergencyNeed(team: b, payroll: 41000, cash: 5000),
        ],
        pool.take(2).toList(),
        (o, c, e, s) => from(500, o, c, e, s),
      );
      expect(result.status, EmergencyPlanStatus.optimal);
      expect(result.offers.map((o) => o.teamId), [a.id, b.id]);
      expect(result.offers.map((o) => o.playerId).toSet(), hasLength(2));
    });

    test('exhausted supply and unwilling players are NO_SOLUTION', () {
      final needs = [
        EmergencyNeed(team: a, payroll: 41000, cash: 5000),
        EmergencyNeed(team: b, payroll: 41000, cash: 5000),
      ];
      final exhausted = run(needs, pool.take(1).toList(), (o, c, e, s) => true);
      expect(exhausted.status, EmergencyPlanStatus.noSolution);
      expect(exhausted.offers, isEmpty);
      final unwilling = run(needs, pool, (o, c, e, s) => false);
      expect(unwilling.status, EmergencyPlanStatus.noSolution);
    });

    test('salary limit, cash and cheapest willing price are binding', () {
      final need = [EmergencyNeed(team: a, payroll: 41000, cash: 5000)];
      expect(
        run(need, pool, (o, c, e, s) => from(1201, o, c, e, s)).status,
        EmergencyPlanStatus.noSolution,
      );
      final capped = run(need, pool, (o, c, e, s) => from(1200, o, c, e, s));
      expect(capped.offers.single.salary, 1200);
      expect(capped.offers.single.relief, 1200);
      final poor = [EmergencyNeed(team: a, payroll: 41000, cash: 599)];
      expect(
        run(poor, pool, (o, c, e, s) => from(600, o, c, e, s)).status,
        EmergencyPlanStatus.noSolution,
      );
      final cheapest = run(
        need,
        pool.take(2).toList(),
        (o, c, e, s) => from(e == pool[0] ? 900 : 650, o, c, e, s),
      );
      expect(cheapest.offers.single.playerId, pool[1].id);
      expect(cheapest.offers.single.salary, 650);
    });

    test('relief is incremental over payroll that includes liabilities', () {
      // Payroll passed to a need is cap payroll, which already contains
      // standard guaranteed-liability cap charges.
      final short = _shortTeam(a, 12);
      final result = run(
        [EmergencyNeed(team: short, payroll: 40500, cash: 5000)],
        pool.take(2).toList(),
        (o, c, e, s) => from(400, o, c, e, s),
      );
      expect(result.offers.map((o) => o.relief), [0, 300]);
    });

    test('position-only shortages fill the missing position', () {
      var roster = a.roster;
      for (final player in a.roster.players) {
        if (player.position == Position.c) {
          roster = roster.withoutPlayer(player.id);
        }
      }
      final nonCenters = pool.where((e) => e.player.position != Position.c);
      for (final entry in nonCenters) {
        if (roster.standardCount >= 14) break;
        roster = roster.withPlayer(
          entry.player,
          category: RosterCategory.standard,
        );
      }
      final team = a.copyWith(roster: roster);
      expect(roster.standardCount, 14);
      expect(roster.covers(Position.c), isFalse);
      final candidates = pool
          .where((e) => !roster.players.any((p) => p.id == e.id))
          .toList();
      final result = run(
        [EmergencyNeed(team: team, payroll: 41000, cash: 5000)],
        candidates,
        (o, c, e, s) => from(500, o, c, e, s),
      );
      expect(result.status, EmergencyPlanStatus.optimal);
      final signed = pool.firstWhere(
        (e) => e.id == result.offers.single.playerId,
      );
      expect(signed.player.position, Position.c);

      var full = roster;
      for (final entry in candidates.where(
        (e) => e.player.position != Position.c,
      )) {
        if (full.standardCount >= 15) break;
        full = full.withPlayer(entry.player, category: RosterCategory.standard);
      }
      expect(
        run(
          [
            EmergencyNeed(
              team: a.copyWith(roster: full),
              payroll: 41000,
              cash: 5000,
            ),
          ],
          candidates,
          (o, c, e, s) => true,
        ).status,
        EmergencyPlanStatus.noSolution,
      );
    });

    test('search truncation is never reported as optimal', () {
      final need = [EmergencyNeed(team: a, payroll: 41000, cash: 5000)];
      final entries = pool.take(3).toList();
      bool willing(Team o, Team c, FreeAgentEntry e, int s) => s >= 500;
      expect(
        run(need, entries, willing, limit: 1).status,
        EmergencyPlanStatus.inconclusive,
      );
      expect(
        run(need, entries, willing, limit: 3).status,
        EmergencyPlanStatus.feasibleNotProvenOptimal,
      );
      expect(run(need, entries, willing).status, EmergencyPlanStatus.optimal);
    });
  });

  group('human consent and lifecycle', () {
    test('human offers require consent bound to the reviewed plan', () {
      final plan = service.preview(human);
      expect(plan.offers.map((o) => o.teamId), contains(human.userFranchiseId));
      final before = GmCareerCodec.encode(human);
      expect(
        () => service.execute(human, plan, humanApproved: false),
        throwsStateError,
      );
      expect(GmCareerCodec.encode(human), before);

      final approved = service.execute(human, plan, humanApproved: true);
      expect(approved.emergencySettlement!.humanApproved, isTrue);
      final raw = _json(approved);
      (raw['emergencySettlement'] as Map<String, dynamic>)['humanApproved'] =
          false;
      _rejects(raw);

      expect(
        () => service.execute(approved, plan, humanApproved: true),
        throwsStateError,
      );
      expect(
        service.preview(approved).blockers,
        contains('Emergency settlement is already complete'),
      );
    });

    test('a changed allocation requires a fresh review', () {
      final plan = service.preview(human);
      final rights = human.unsignedDraftRights.firstWhere(
        (r) => r.owningTeamId == human.userFranchiseId,
      );
      final changed = const RookieSigningService().signDraftedRookie(
        career: human,
        teamId: human.userFranchiseId,
        prospectId: rights.prospectId,
        category: RosterCategory.standard,
        durationYears: 2,
      );
      expect(
        () => service.execute(changed, plan, humanApproved: true),
        throwsStateError,
      );
    });

    test('later lawful rookie signing keeps the receipt loadable', () {
      final plan = service.preview(human);
      final settled = service.execute(human, plan, humanApproved: true);
      final rights = settled.unsignedDraftRights.firstWhere(
        (r) => r.owningTeamId == settled.userFranchiseId,
      );
      final later = const RookieSigningService().signDraftedRookie(
        career: settled,
        teamId: settled.userFranchiseId,
        prospectId: rights.prospectId,
        category: RosterCategory.standard,
        durationYears: 2,
      );
      final reloaded = GmCareerCodec.decode(GmCareerCodec.encode(later));
      expect(
        reloaded.emergencySettlement!.toJson(),
        settled.emergencySettlement!.toJson(),
      );
      final receipt = reloaded.emergencySettlement!.teams.single;
      expect(
        reloaded.finances.capPayrollFor(receipt.teamId, 1),
        greaterThan(receipt.payrollBefore + plan.offers.single.salary),
      );
    });
  });

  group('receipt integrity', () {
    late GmCareer settled;
    setUpAll(() {
      settled = service.execute(rsc, service.preview(rsc), humanApproved: true);
    });

    test('settled save reloads exactly and records starting authority', () {
      final reloaded = GmCareerCodec.decode(GmCareerCodec.encode(settled));
      expect(GmCareerCodec.encode(reloaded), GmCareerCodec.encode(settled));
      final receipt = reloaded.emergencySettlement!.teams.single;
      expect(receipt.teamId, const TeamId('team-4'));
      expect(receipt.payrollBefore, lessThanOrEqualTo(receipt.startingLimit));
      expect(reloaded.emergencySettlement!.humanApproved, isFalse);
    });

    test('tampered or orphaned evidence is rejected', () {
      Map<String, dynamic> receipt(Map<String, dynamic> raw) =>
          ((raw['emergencySettlement'] as Map<String, dynamic>)['teams']
                      as List)
                  .single
              as Map<String, dynamic>;
      Map<String, dynamic> offer(Map<String, dynamic> raw) =>
          ((raw['emergencySettlement'] as Map<String, dynamic>)['offers']
                      as List)
                  .single
              as Map<String, dynamic>;

      final payroll = _json(settled);
      receipt(payroll)['payrollBefore'] =
          (receipt(payroll)['payrollBefore'] as int) - 100;
      _rejects(payroll);

      final contracts = _json(settled);
      final ids = receipt(contracts)['priorContractIds'] as List;
      ids.removeAt(0);
      _rejects(contracts);

      final ordinary = _json(settled);
      receipt(ordinary)['ordinaryRelief'] =
          (receipt(ordinary)['ordinaryRelief'] as int) + 100;
      _rejects(ordinary);

      final relief = _json(settled);
      offer(relief)['relief'] = (offer(relief)['relief'] as int) + 1;
      _rejects(relief);

      final orphan = _json(settled)..['emergencySettlement'] = null;
      _rejects(orphan);

      final consent = _json(settled);
      (consent['emergencySettlement']
              as Map<String, dynamic>)['humanApproved'] =
          true;
      _rejects(consent);

      final season = _json(settled);
      (season['emergencySettlement'] as Map<String, dynamic>)['seasonYear'] = 2;
      _rejects(season);
    });
  });
}
