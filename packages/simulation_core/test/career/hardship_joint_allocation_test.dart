import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _hardship = HardshipSettlementService();
const _gate = OffseasonReadinessGate();
const _evaluator = FreeAgentOfferEvaluator();

Player _makePlayer({
  required String id,
  required Position position,
  required int overall,
}) => Player(
  id: PlayerId(id),
  firstName: 'Test',
  lastName: id,
  position: position,
  attributes: PlayerAttributes(
    insideScoring: overall,
    midrange: overall,
    threePoint: overall,
    freeThrow: overall,
    passing: overall,
    ballHandling: overall,
    perimeterDefense: overall,
    interiorDefense: overall,
    rebounding: overall,
    athleticism: overall,
    stamina: overall,
    basketballIQ: overall,
  ),
);

FreeAgentEntry _makeFa({
  required String id,
  required Position position,
  required int overall,
  int age = 26,
}) => FreeAgentEntry(
  player: _makePlayer(id: id, position: position, overall: overall),
  profile: PlayerCareerProfile(
    playerId: PlayerId(id),
    age: age,
    potential: overall < 75 ? 75 : overall,
    trajectory: DevelopmentTrajectory.steady,
  ),
);

GmCareer _runYear1ThroughClearance(int seed) {
  const draft = DraftExecutionService();
  const signing = RookieSigningService();
  const rookies = RookieAiSigningService();
  const market = FreeAgentMarketService();
  const clearance = OffseasonClearanceService();

  var c = GmCareer.fromSetupResult(
    const CareerSetupService().generate(
      CareerSetupRequest(
        selectedTeamId: const TeamId('team-1'),
        selectedSituation: FranchiseSituation.tanking,
        seed: seed,
      ),
    ),
    id: 't05c-p1-seed-$seed',
  );
  c = draft.startDraft(c);
  while (!c.draftExecutionState.isCompleted) {
    c =
        c.draftExecutionState.isHumanTurn(
          order: c.draftOrder,
          userTeamId: c.userFranchiseId,
        )
        ? draft.makeHumanSelection(
            career: c,
            prospectId: c.draftExecutionState
                .availableProspects(c.draftClass)
                .first
                .id,
          )
        : draft.executeAiSelection(c);
  }
  c = rookies.initialize(c);
  while (rookies.pendingRights(c).isNotEmpty) {
    c = rookies.applyNextDecision(c);
  }
  for (final r in c.unsignedDraftRights) {
    if (r.owningTeamId == c.userFranchiseId) {
      c = signing.signDraftedRookie(
        career: c,
        teamId: c.userFranchiseId,
        prospectId: r.prospectId,
        category: RosterCategory.standard,
        durationYears: 2,
      );
    }
  }
  for (var r = 0; r < 2; r++) {
    c = market.startRound(c);
    c = market.prepareResolution(c);
    while (c.freeAgentMarket.isResolvable) {
      c = market.resolveNext(c);
    }
  }
  c = clearance.start(c);
  c = clearance.prepare(c);
  while (c.offseasonClearance.isResolvable) {
    c = clearance.resolveNext(c);
  }
  return c;
}

GmCareer _isolatedPreHardshipScenario({
  required Map<TeamId, ({int stdCount, int payroll, FranchiseSituation sit})>
  targetTeams,
  required List<FreeAgentEntry> poolEntries,
  int seed = 20261028,
}) {
  var base = GmCareer.fromSetupResult(
    const CareerSetupService().generate(
      CareerSetupRequest(
        selectedTeamId: const TeamId('team-1'),
        selectedSituation: FranchiseSituation.tanking,
        seed: seed,
      ),
    ),
    id: 't05c-p1-isolated',
  );
  const draft = DraftExecutionService();
  base = draft.startDraft(base);
  while (!base.draftExecutionState.isCompleted) {
    base =
        base.draftExecutionState.isHumanTurn(
          order: base.draftOrder,
          userTeamId: base.userFranchiseId,
        )
        ? draft.makeHumanSelection(
            career: base,
            prospectId: base.draftExecutionState
                .availableProspects(base.draftClass)
                .first
                .id,
          )
        : draft.executeAiSelection(base);
  }
  final aiDecisions = <String, AiSigningDecision>{};
  for (final r in base.unsignedDraftRights) {
    if (r.owningTeamId != base.userFranchiseId) {
      aiDecisions[r.prospectId.value] = AiSigningDecision(
        teamId: r.owningTeamId,
        prospectId: r.prospectId,
        draftSeasonYear: r.seasonYear,
        overallPick: r.overallPick,
        decision: AiSigningDecisionType.deferred,
        reason: AiSigningReason.deferredLowFit,
      );
    }
  }
  const currentYear = 1;
  final profiles = <String, PlayerCareerProfile>{};
  final contracts = <PlayerContract>[];
  final schedules = <ContractFinancials>[];
  final teams = <Team>[];
  final teamFinances = <TeamFinances>[];

  for (final orig in base.league.teams) {
    final override = targetTeams[orig.id];
    final stdCount = override?.stdCount ?? 14;
    final totalPay =
        override?.payroll ?? (stdCount * FinancialRules.minimumSalary);
    final sit = override?.sit ?? orig.situation ?? FranchiseSituation.playIn;

    final rosterPlayers = <Player>[];
    final categories = <String, RosterCategory>{};
    final baseSal = stdCount > 0 ? totalPay ~/ stdCount : 0;
    final rem = stdCount > 0 ? totalPay % stdCount : 0;

    for (var i = 0; i < stdCount; i++) {
      final pid = '${orig.id.value}-std-$i';
      final pos = Position.values[i % Position.values.length];
      final player = _makePlayer(id: pid, position: pos, overall: 65);
      rosterPlayers.add(player);
      categories[pid] = RosterCategory.standard;
      profiles[pid] = PlayerCareerProfile(
        playerId: player.id,
        age: 26,
        potential: 75,
        trajectory: DevelopmentTrajectory.steady,
      );
      final sal = baseSal + (i < rem ? 1 : 0);
      final contract = PlayerContract(
        id: PlayerContract.idFor(player.id, currentYear),
        playerId: player.id,
        teamId: orig.id,
        category: RosterCategory.standard,
        startYear: currentYear,
        durationYears: 1,
        source: ContractSource.freeAgent,
      );
      contracts.add(contract);
      schedules.add(
        ContractFinancials(
          contractId: contract.id,
          playerId: player.id,
          teamId: orig.id,
          annualSalaries: [sal],
          guaranteedYears: 1,
          source: ContractSource.freeAgent,
          signedYear: currentYear,
        ),
      );
    }

    teams.add(
      orig.copyWith(
        situation: sit,
        roster: Roster(rosterPlayers, categories: categories),
      ),
    );
    final origTf = base.finances.financesFor(orig.id);
    teamFinances.add(
      TeamFinances(
        teamId: orig.id,
        operatingBudget: origTf.operatingBudget,
        cash: 30000,
        revenueBaseline: origTf.revenueBaseline,
        season: currentYear,
        capGrandfathered: false,
        grandfatheredPayroll: 0,
        capException: 0,
      ),
    );
  }

  final league = League.create(
    id: base.league.id,
    name: base.league.name,
    config: base.league.config,
    teams: teams,
    enforceRosterSize: false,
    enforcePositionCoverage: false,
  );
  final finances = CareerFinances(
    contracts: contracts,
    schedules: schedules,
    teamFinances: teamFinances,
    staffCommitments: base.finances.staffCommitments.values,
    facilities: base.finances.facilities.values,
  );

  final allPool = <FreeAgentEntry>[
    ...poolEntries,
    for (var i = poolEntries.length; i < 90; i++)
      _makeFa(
        id: 'fa-pad-$i',
        position: Position.values[i % Position.values.length],
        overall: 95,
        age: 26,
      ),
  ];

  return base.copyWith(
    league: league,
    careerProfiles: LeagueCareerProfiles(
      schemaVersion: base.careerProfiles.schemaVersion,
      leagueSeed: base.careerProfiles.leagueSeed,
      profiles: profiles,
    ),
    aiRookieSigning: AiRookieSigningState(decisions: aiDecisions),
    finances: finances,
    freeAgentPool: FreeAgentPool(
      seasonYear: currentYear,
      entries: allPool,
      initialPlayerIds: [for (final e in allPool) e.id],
    ),
    freeAgentOffers: FreeAgentOfferLedger.empty(),
    freeAgentMarket: FreeAgentMarketState(
      status: FreeAgentMarketStatus.marketComplete,
      roundNumber: 2,
      completedRounds: 2,
      seasonYear: currentYear,
      humanOffers: const [],
      aiOffers: const [],
      resolutionOrder: const [],
      nextResolutionIndex: 0,
      outcomes: const [],
      roundHistory: [
        FreeAgentMarketRoundRecord(
          roundNumber: 1,
          seasonYear: currentYear,
          humanOffers: const [],
          aiOffers: const [],
          resolutionOrder: const [],
          outcomes: const [],
        ),
        FreeAgentMarketRoundRecord(
          roundNumber: 2,
          seasonYear: currentYear,
          humanOffers: const [],
          aiOffers: const [],
          resolutionOrder: const [],
          outcomes: const [],
        ),
      ],
    ),
    offseasonClearance: OffseasonClearanceState(
      status: OffseasonClearanceStatus.complete,
      seasonYear: currentYear,
      humanOffers: const [],
      aiOffers: const [],
      resolutionOrder: const [],
      nextResolutionIndex: 0,
      outcomes: const [],
      capExceptions: const [],
    ),
    hardshipSettlement: HardshipSettlement.initial(seasonYear: currentYear),
  );
}

GmCareer _resolveAll(GmCareer career) {
  var c = career;
  while (c.hardshipSettlement.isResolvable) {
    c = _hardship.resolveNext(c);
  }
  return c;
}

void main() {
  group('T05C-P1 joint AI hardship allocation and scarcity recovery', () {
    test(
      'A & B: seed 1604126146 avoids OHS/CCB collision and reaches 30/30 legal regular-season entry',
      () {
        final pre = _runYear1ThroughClearance(1604126146);
        final report = _hardship.prepareWithReport(
          pre,
          humanParticipationConfirmed: true,
        );
        expect(report.searchTruncated, isFalse);
        expect(report.completedTeams, 2);
        expect(report.filledSlots, 3);
        expect(report.exploredStates, greaterThan(0));
        final prepared = report.career;
        // Distinct AI targeting: no player receives duplicate coordinated AI offers.
        final aiTargetIds = prepared.hardshipSettlement.offers
            .where((o) => o.source == FreeAgentMarketOfferSource.ai)
            .map((o) => o.playerId.value)
            .toList();
        expect(aiTargetIds.toSet().length, aiTargetIds.length);

        final resolved = _resolveAll(prepared);
        resolved.validate();

        final ohs = resolved.league.teams.firstWhere(
          (t) => t.id == const TeamId('team-23'),
        );
        final ccb = resolved.league.teams.firstWhere(
          (t) => t.id == const TeamId('team-24'),
        );
        expect(ohs.roster.standardCount, 14);
        expect(ccb.roster.standardCount, 14);

        final gate = _gate.evaluate(resolved);
        expect(gate.readyCount, 30);
        expect(gate.status, OffseasonReadinessStatus.readyForConfirmation);

        final cleared = const OffseasonClearanceService().markCleared(resolved);
        final entered = const RegularSeasonEntryService().start(cleared);
        entered.validate();
        expect(entered.phase, CareerPhase.regularSeason);
      },
    );

    test(
      'C: scarcity asymmetry assigns constrained Team A->X and flexible Team B->Y',
      () {
        // Team-2 (earlier teamId) can sign fa-x (~760) or fa-y (~1040).
        // Team-3 (later teamId) only has 400 cap room + 1000 hardship = 1400 CU? Wait:
        // make Team-3 payroll = 40,200 (800 cap room -> max hardship salary 1,800? No!)
        // Make Team-3 payroll = 40,800 (200 room + 1000 = 1,200 max) and
        // make fa-x minSal <= 1,000 while fa-y minSal = 1,350 (<= Team-2's 1,400 max, > Team-3's 1,200 max!).
        // On uncoordinated prepare(), team-2 takes cheaper fa-x leaving team-3 stranded!
        final faX = _makeFa(
          id: 'fa-x',
          position: Position.c,
          overall: 60,
          age: 34,
        );
        final faY = _makeFa(
          id: 'fa-y',
          position: Position.sg,
          overall: 64,
          age: 34,
        );
        final pre = _isolatedPreHardshipScenario(
          targetTeams: {
            const TeamId('team-2'): (
              stdCount: 13,
              payroll: 40600, // room 400 -> max 1400 CU
              sit: FranchiseSituation.contender,
            ),
            const TeamId('team-3'): (
              stdCount: 13,
              payroll:
                  40850, // room 150 -> max 1150 CU (fits fa-x, rejects fa-y!)
              sit: FranchiseSituation.contender,
            ),
          },
          poolEntries: [faX, faY],
        );
        final prepared = _hardship.prepare(
          pre,
          humanParticipationConfirmed: true,
        );
        final resolved = _resolveAll(prepared);
        resolved.validate();

        final t2 = resolved.league.teams.firstWhere(
          (t) => t.id == const TeamId('team-2'),
        );
        final t3 = resolved.league.teams.firstWhere(
          (t) => t.id == const TeamId('team-3'),
        );
        expect(t2.roster.standardCount, 14);
        expect(t3.roster.standardCount, 14);
        expect(t3.players.any((p) => p.id == faX.id), isTrue);
        expect(t2.players.any((p) => p.id == faY.id), isTrue);
      },
    );

    test(
      'D, E, H: seed 271828182 completes CBE & SFS (29/30) and preserves honest blocker on RSC',
      () {
        final pre = _runYear1ThroughClearance(271828182);
        final report = _hardship.prepareWithReport(
          pre,
          humanParticipationConfirmed: true,
        );
        expect(report.searchTruncated, isFalse);
        expect(report.completedTeams, 2);
        expect(report.filledSlots, 3);
        final prepared = report.career;
        final resolved = _resolveAll(prepared);
        resolved.validate();

        final cbe = resolved.league.teams.firstWhere(
          (t) => t.id == const TeamId('team-8'),
        );
        final sfs = resolved.league.teams.firstWhere(
          (t) => t.id == const TeamId('team-22'),
        );
        final rsc = resolved.league.teams.firstWhere(
          (t) => t.id == const TeamId('team-4'),
        );
        expect(cbe.roster.standardCount, 14);
        expect(sfs.roster.standardCount, 14);
        expect(rsc.roster.standardCount, 13);

        final gate = _gate.evaluate(resolved);
        expect(gate.readyCount, 29);
        expect(
          gate.status,
          OffseasonReadinessStatus.financialExceptionRequired,
        );
        expect(gate.teams.single.teamId, const TeamId('team-4'));
        expect(gate.teams.single.abbreviation, 'RSC');
        expect(gate.teams.single.requiredPlayers, 1);
      },
    );

    test(
      'E2 & F: same-position 2-slot hardship recomputes sequential depth fit and rejects pairs > 1,000 CU overage',
      () {
        // Team-2 needs 2 players (payroll = 40,200 -> max total for 2 slots = 1,800 CU).
        // fa-c-a and fa-c-b are both C (~60 OVR -> ~760 individually = 1520, but second C
        // sees stronger>=2 -> -1200 bp pushing total > 1800 if too expensive; keep ~56 OVR).
        // Include fa-c-a (56 OVR), fa-c-b (56 OVR), and fa-c-expensive (68 OVR) which would breach 1,000 CU.
        final faA = _makeFa(
          id: 'fa-c-a',
          position: Position.c,
          overall: 57,
          age: 34,
        );
        final faB = _makeFa(
          id: 'fa-c-b',
          position: Position.c,
          overall: 57,
          age: 34,
        );
        final faExp = _makeFa(
          id: 'fa-c-exp',
          position: Position.c,
          overall: 68,
          age: 34,
        );
        final pre = _isolatedPreHardshipScenario(
          targetTeams: {
            const TeamId('team-2'): (
              stdCount: 12,
              payroll: 40400, // room 600 + 1000 = 1600 max total
              sit: FranchiseSituation.contender,
            ),
          },
          poolEntries: [faA, faB, faExp],
        );
        final prepared = _hardship.prepare(
          pre,
          humanParticipationConfirmed: true,
        );
        for (final auth in prepared.hardshipSettlement.authorizations) {
          expect(
            auth.existingOrdinaryRelief + auth.additionalAmount,
            lessThanOrEqualTo(FinancialRules.maximumCombinedHardshipOverage),
          );
        }
        final resolved = _resolveAll(prepared);
        resolved.validate();
        final t2 = resolved.league.teams.firstWhere(
          (t) => t.id == const TeamId('team-2'),
        );
        // Every active resolved offer must remain acceptable sequentially.
        var sim = prepared;
        while (sim.hardshipSettlement.isResolvable) {
          final pid = sim
              .hardshipSettlement
              .resolutionOrder[sim.hardshipSettlement.nextResolutionIndex];
          for (final offer in sim.hardshipSettlement.offersFor(pid)) {
            final d = _evaluator.evaluate(
              career: sim,
              teamId: offer.teamId,
              freeAgentId: offer.playerId,
              category: RosterCategory.standard,
              durationYears: offer.durationYears,
              agreedFirstYearSalary: offer.firstYearSalary,
              hardshipOfferId: offer.offerId,
            );
            expect(d.isFinanciallyLegal, isTrue, reason: d.reasonCode);
            expect(d.isAcceptable, isTrue, reason: d.reasonCode);
          }
          sim = _hardship.resolveNext(sim);
        }
        expect(t2.roster.standardCount, 14);
        expect(t2.players.any((p) => p.id == faExp.id), isFalse);
      },
    );

    test(
      'G: when no complete joint matching exists, maximizes legally completable teams without fabricating signings',
      () {
        // 3 AI teams compete for ONLY 2 players {fa-1, fa-2}:
        // team-2 (missing 2, payroll 40,500) can only complete if it gets BOTH {fa-1, fa-2}.
        // team-3 (missing 1, payroll 40,600) completes with fa-1 or fa-2.
        // team-4 (missing 1, payroll 40,600) completes with fa-1 or fa-2.
        // Maximizing completed teams picks team-3 + team-4 (2 completed teams) over team-2 alone (1 completed team)!
        final fa1 = _makeFa(
          id: 'fa-1',
          position: Position.pg,
          overall: 58,
          age: 34,
        );
        final fa2 = _makeFa(
          id: 'fa-2',
          position: Position.sg,
          overall: 58,
          age: 34,
        );
        final pre = _isolatedPreHardshipScenario(
          targetTeams: {
            const TeamId('team-2'): (
              stdCount: 12,
              payroll: 40500,
              sit: FranchiseSituation.contender,
            ),
            const TeamId('team-3'): (
              stdCount: 13,
              payroll: 40600,
              sit: FranchiseSituation.contender,
            ),
            const TeamId('team-4'): (
              stdCount: 13,
              payroll: 40600,
              sit: FranchiseSituation.contender,
            ),
          },
          poolEntries: [fa1, fa2],
        );
        final prepared = _hardship.prepare(
          pre,
          humanParticipationConfirmed: true,
        );
        final resolved = _resolveAll(prepared);
        resolved.validate();

        final completedAmong3 = [
          for (final tid in const [
            TeamId('team-2'),
            TeamId('team-3'),
            TeamId('team-4'),
          ])
            resolved.league.teams.firstWhere((t) => t.id == tid),
        ].where((t) => t.roster.standardCount == 14).length;
        expect(completedAmong3, 2);
        expect(resolved.freeAgentPool.byId(fa1.id), isNull);
        expect(resolved.freeAgentPool.byId(fa2.id), isNull);
      },
    );

    test(
      'I, J, K, L: human participation semantics, single-team validity, exact authorizations, and SHA-256 determinism',
      () {
        // Human + AI with identical cheap FA: human offers remain intact when confirmed,
        // excluded when declined, and repeated prepare+resolve is byte-identical.
        final faHumanPref = _makeFa(
          id: 'fa-a',
          position: Position.pg,
          overall: 58,
          age: 34,
        );
        final faAlt = _makeFa(
          id: 'fa-b',
          position: Position.sg,
          overall: 60,
          age: 34,
        );
        final pre = _isolatedPreHardshipScenario(
          targetTeams: {
            const TeamId('team-1'): (
              stdCount: 13,
              payroll: 40600,
              sit: FranchiseSituation.contender,
            ),
            const TeamId('team-2'): (
              stdCount: 13,
              payroll: 40600,
              sit: FranchiseSituation.contender,
            ),
          },
          poolEntries: [faHumanPref, faAlt],
        );

        final humanProposal = _hardship.proposedHumanOffers(pre);
        expect(humanProposal, hasLength(1));

        final declined = _hardship.prepare(
          pre,
          humanParticipationConfirmed: false,
        );
        expect(
          declined.hardshipSettlement.offers.any(
            (o) => o.teamId == pre.userFranchiseId,
          ),
          isFalse,
        );
        final declinedResolved = _resolveAll(declined);
        declinedResolved.validate();

        final confirmed1 = _hardship.prepare(
          pre,
          humanParticipationConfirmed: true,
        );
        final confirmed2 = _hardship.prepare(
          pre,
          humanParticipationConfirmed: true,
        );
        // Human's displayed proposal was not altered.
        final confirmedHumanOffers = confirmed1.hardshipSettlement.offers
            .where((o) => o.teamId == pre.userFranchiseId)
            .toList();
        expect(
          confirmedHumanOffers.map((o) => o.toJson()).toList(),
          humanProposal.map((o) => o.toJson()).toList(),
        );
        // AI chose alternative fa-b to avoid confirmed human target fa-a -> both complete!
        final resolved1 = _resolveAll(confirmed1);
        final resolved2 = _resolveAll(confirmed2);
        resolved1.validate();
        expect(_gate.evaluate(resolved1).readyCount, 30);

        final sha1 = sha256
            .convert(utf8.encode(GmCareerCodec.encode(resolved1)))
            .toString();
        final sha2 = sha256
            .convert(utf8.encode(GmCareerCodec.encode(resolved2)))
            .toString();
        expect(sha1, sha2);

        // Single-team hardship check (team-2 only) remains valid.
        final singlePre = _isolatedPreHardshipScenario(
          targetTeams: {
            const TeamId('team-2'): (
              stdCount: 13,
              payroll: 40600,
              sit: FranchiseSituation.contender,
            ),
          },
          poolEntries: [faHumanPref, faAlt],
        );
        final singleResolved = _resolveAll(
          _hardship.prepare(singlePre, humanParticipationConfirmed: true),
        );
        singleResolved.validate();
        expect(_gate.evaluate(singleResolved).readyCount, 30);
      },
    );
  });
}
