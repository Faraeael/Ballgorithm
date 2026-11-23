import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _seed = 20261028;
const _policy = AiFreeAgentOfferPolicy();
const _gate = OffseasonReadinessGate();
const _marketService = FreeAgentMarketService();
const _clearanceService = OffseasonClearanceService();
const _entryService = RegularSeasonEntryService();

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

GmCareer _isolatedPositionScenario({
  required TeamId targetTeamId,
  required List<Position> targetStandardPositions,
  List<Position> targetTwoWayPositions = const [],
  required List<FreeAgentEntry> poolEntries,
  int? targetContinuingPayroll,
  int targetProjectedCash = 50000,
  bool completeMarketAndClearance = false,
  bool markCleared = false,
  FranchiseSituation targetSituation = FranchiseSituation.playIn,
}) {
  final base = GmCareer.fromSetupResult(
    const CareerSetupService().generate(
      const CareerSetupRequest(
        selectedTeamId: TeamId('team-1'),
        selectedSituation: FranchiseSituation.tanking,
        seed: _seed,
      ),
    ),
    id: 't05b2-position-coverage',
  );
  const currentYear = 3;
  final profiles = <String, PlayerCareerProfile>{};
  final contracts = <PlayerContract>[];
  final schedules = <ContractFinancials>[];
  final teams = <Team>[];
  final teamFinances = <TeamFinances>[];

  for (final orig in base.league.teams) {
    final isTarget = orig.id == targetTeamId;
    final stdPositions = isTarget
        ? targetStandardPositions
        : [
            for (var i = 0; i < 14; i++)
              Position.values[i % Position.values.length],
          ];
    final twPositions = isTarget
        ? targetTwoWayPositions
        : [
            for (var i = 0; i < 3; i++)
              Position.values[i % Position.values.length],
          ];
    final rosterPlayers = <Player>[];
    final categories = <String, RosterCategory>{};

    final targetTotalPay =
        targetContinuingPayroll ??
        stdPositions.length * FinancialRules.minimumSalary;
    final baseSal = isTarget && stdPositions.isNotEmpty
        ? targetTotalPay ~/ stdPositions.length
        : FinancialRules.minimumSalary;
    final remSal = isTarget && stdPositions.isNotEmpty
        ? targetTotalPay % stdPositions.length
        : 0;

    for (var i = 0; i < stdPositions.length; i++) {
      final pid = '${orig.id.value}-std-$i';
      final player = _makePlayer(
        id: pid,
        position: stdPositions[i],
        overall: 65,
      );
      rosterPlayers.add(player);
      categories[pid] = RosterCategory.standard;
      profiles[pid] = PlayerCareerProfile(
        playerId: player.id,
        age: 25,
        potential: 75,
        trajectory: DevelopmentTrajectory.steady,
      );
      final sal = isTarget
          ? baseSal + (i < remSal ? 1 : 0)
          : FinancialRules.minimumSalary;
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

    for (var i = 0; i < twPositions.length; i++) {
      final pid = '${orig.id.value}-tw-$i';
      final player = _makePlayer(
        id: pid,
        position: twPositions[i],
        overall: 58,
      );
      rosterPlayers.add(player);
      categories[pid] = RosterCategory.twoWay;
      profiles[pid] = PlayerCareerProfile(
        playerId: player.id,
        age: 21,
        potential: 70,
        trajectory: DevelopmentTrajectory.steady,
      );
      final contract = PlayerContract(
        id: PlayerContract.idFor(player.id, currentYear),
        playerId: player.id,
        teamId: orig.id,
        category: RosterCategory.twoWay,
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
          annualSalaries: const [FinancialRules.twoWaySalary],
          guaranteedYears: 1,
          source: ContractSource.freeAgent,
          signedYear: currentYear,
        ),
      );
    }

    teams.add(
      orig.copyWith(
        situation: isTarget ? targetSituation : orig.situation,
        roster: Roster(rosterPlayers, categories: categories),
      ),
    );

    final origTf = base.finances.financesFor(orig.id);
    final totalExistingPayroll =
        (isTarget
            ? targetTotalPay
            : stdPositions.length * FinancialRules.minimumSalary) +
        twPositions.length * FinancialRules.twoWaySalary;
    final opCommitments = base.finances.operatingCommitmentsFor(orig.id);
    final rawCash =
        targetProjectedCash -
        origTf.revenueBaseline +
        totalExistingPayroll +
        opCommitments;
    final desiredCash = isTarget
        ? rawCash.clamp(0, FinancialRules.maximumBalance)
        : 50000;
    final desiredRev = isTarget && rawCash < 0
        ? targetProjectedCash + totalExistingPayroll + opCommitments
        : origTf.revenueBaseline;
    teamFinances.add(
      TeamFinances(
        teamId: orig.id,
        operatingBudget: origTf.operatingBudget,
        cash: desiredCash,
        revenueBaseline: desiredRev,
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
    staffCommitments: [
      for (final s in base.finances.staffCommitments.values)
        StaffCommitment(
          id: s.id,
          teamId: s.teamId,
          category: s.category,
          tier: s.tier,
          annualCost: s.annualCost,
          startYear: currentYear,
          durationYears: 1,
        ),
    ],
    facilities: base.finances.facilities.values,
  );

  final draftOrder = base.draftOrder;
  final draftClass = const DraftGenerator().generateDraftClass(
    league: league,
    seed: base.generationSeed + currentYear,
    seasonYear: currentYear,
  );
  final selections = <DraftSelection>[];
  final rightsMap = <String, DraftRights>{};
  final aiDecisions = <String, AiSigningDecision>{};
  for (var i = 0; i < draftOrder.picks.length; i++) {
    final pick = draftOrder.picks[i];
    final prospect = draftClass.prospects[i];
    selections.add(
      DraftSelection(
        overallPick: pick.overallPick,
        round: pick.round,
        pickInRound: pick.pickInRound,
        originalOwnerTeamId: pick.originalOwnerTeamId,
        selectingTeamId: pick.currentOwnerTeamId,
        prospectId: prospect.id,
        seasonYear: currentYear,
      ),
    );
    rightsMap[prospect.id.value] = DraftRights(
      prospectId: prospect.id,
      owningTeamId: pick.currentOwnerTeamId,
      seasonYear: currentYear,
      overallPick: pick.overallPick,
    );
    if (pick.currentOwnerTeamId != base.userFranchiseId) {
      aiDecisions[prospect.id.value] = AiSigningDecision(
        teamId: pick.currentOwnerTeamId,
        prospectId: prospect.id,
        draftSeasonYear: currentYear,
        overallPick: pick.overallPick,
        decision: AiSigningDecisionType.deferred,
        reason: AiSigningReason.deferredLowFit,
      );
    }
  }
  final draftState = DraftExecutionState(
    status: DraftExecutionStatus.completed,
    selections: selections,
    draftRights: rightsMap,
  );
  final aiSigning = AiRookieSigningState(decisions: aiDecisions);

  return base.copyWith(
    currentYear: currentYear,
    league: league,
    careerProfiles: LeagueCareerProfiles(
      schemaVersion: base.careerProfiles.schemaVersion,
      leagueSeed: base.careerProfiles.leagueSeed,
      profiles: profiles,
    ),
    draftOrder: draftOrder,
    draftClass: draftClass,
    draftExecutionState: draftState,
    aiRookieSigning: aiSigning,
    rookieSigningLedger: RookieSigningLedger.empty(),
    finances: finances,
    freeAgentPool: FreeAgentPool(
      seasonYear: currentYear,
      entries: poolEntries,
      initialPlayerIds: [for (final e in poolEntries) e.id],
    ),
    freeAgentMarket: completeMarketAndClearance
        ? FreeAgentMarketState.initial(seasonYear: currentYear).copyWith(
            status: FreeAgentMarketStatus.marketComplete,
            roundNumber: 2,
            completedRounds: 2,
          )
        : FreeAgentMarketState.initial(seasonYear: currentYear).copyWith(
            status: FreeAgentMarketStatus.collectingHumanOffers,
            roundNumber: 1,
          ),
    offseasonClearance: completeMarketAndClearance
        ? OffseasonClearanceState.initial(seasonYear: currentYear).copyWith(
            status: markCleared
                ? OffseasonClearanceStatus.cleared
                : OffseasonClearanceStatus.complete,
          )
        : OffseasonClearanceState.initial(seasonYear: currentYear),
    hardshipSettlement: completeMarketAndClearance
        ? HardshipSettlement.initial(
            seasonYear: currentYear,
          ).copyWith(status: HardshipSettlementStatus.complete)
        : HardshipSettlement.initial(seasonYear: currentYear),
    freeAgentOffers: FreeAgentOfferLedger.empty(),
  );
}

void main() {
  group('T05B2 AI position coverage and readiness gate alignment', () {
    test(
      'A, B & C: gate rejects 14-standard teams missing C or PF without false financial exception',
      () {
        final noCenter = _isolatedPositionScenario(
          targetTeamId: const TeamId('team-10'),
          targetStandardPositions: [
            for (var i = 0; i < 4; i++) Position.pg,
            for (var i = 0; i < 4; i++) Position.sg,
            for (var i = 0; i < 3; i++) Position.sf,
            for (var i = 0; i < 3; i++) Position.pf,
          ],
          poolEntries: [
            _makeFa(id: 'fa-c-1', position: Position.c, overall: 50, age: 24),
          ],
          completeMarketAndClearance: true,
        );
        final noCenterGate = _gate.evaluate(noCenter);
        expect(noCenterGate.readyCount, 29);
        expect(
          noCenterGate.status,
          isNot(OffseasonReadinessStatus.readyForConfirmation),
        );
        expect(noCenterGate.status, isNot(OffseasonReadinessStatus.cleared));
        expect(
          noCenterGate.status,
          isNot(OffseasonReadinessStatus.financialExceptionRequired),
        );
        expect(
          noCenterGate.reasons.any((r) => r.contains('C')),
          isTrue,
          reason: 'Reasons must identify missing C: ${noCenterGate.reasons}',
        );
        expect(noCenterGate.teams.single.missingPositions, [Position.c]);
        expect(
          () => _clearanceService.markCleared(noCenter),
          throwsA(isA<DomainValidationException>()),
        );

        final noCenterClearedFlag = _isolatedPositionScenario(
          targetTeamId: const TeamId('team-10'),
          targetStandardPositions: [
            for (var i = 0; i < 4; i++) Position.pg,
            for (var i = 0; i < 4; i++) Position.sg,
            for (var i = 0; i < 3; i++) Position.sf,
            for (var i = 0; i < 3; i++) Position.pf,
          ],
          poolEntries: const [],
          completeMarketAndClearance: true,
          markCleared: true,
        );
        final invalidClearedGate = _gate.evaluate(noCenterClearedFlag);
        expect(
          invalidClearedGate.status,
          isNot(OffseasonReadinessStatus.cleared),
        );
        expect(invalidClearedGate.readyCount, 29);
        expect(
          () => _entryService.start(noCenterClearedFlag),
          throwsA(isA<RegularSeasonEntryBlocked>()),
        );

        final noPf = _isolatedPositionScenario(
          targetTeamId: const TeamId('team-19'),
          targetStandardPositions: [
            for (var i = 0; i < 4; i++) Position.pg,
            for (var i = 0; i < 4; i++) Position.sg,
            for (var i = 0; i < 3; i++) Position.sf,
            for (var i = 0; i < 3; i++) Position.c,
          ],
          poolEntries: const [],
          completeMarketAndClearance: true,
        );
        final noPfGate = _gate.evaluate(noPf);
        expect(noPfGate.readyCount, 29);
        expect(
          noPfGate.status,
          isNot(OffseasonReadinessStatus.readyForConfirmation),
        );
        expect(
          noPfGate.reasons.any((r) => r.contains('PF')),
          isTrue,
          reason: 'Reasons must identify missing PF: ${noPfGate.reasons}',
        );
        expect(noPfGate.teams.single.missingPositions, [Position.pf]);
      },
    );

    test(
      'D & E: AI dynamically updates projected position counts across staged offers so both PF and C are covered instead of stacking redundant stars',
      () {
        final aiTeam = const TeamId('team-10');
        // CRM starts with PG, SG, SF covered (6 standard players) and 0 PF, 0 C.
        // Pool has 10 high-OVR PFs (so static sorting puts all 10 PFs ahead of C!)
        // and 1 lower-OVR C. Dynamic position counting must pick 1 PF and then
        // immediately prioritize C instead of staging 8 PFs and 0 Cs.
        final pool = <FreeAgentEntry>[
          for (var i = 0; i < 10; i++)
            _makeFa(
              id: 'fa-pf-$i',
              position: Position.pf,
              overall: 70 - i,
              age: 26,
            ),
          _makeFa(
            id: 'fa-c-needed',
            position: Position.c,
            overall: 50,
            age: 25,
          ),
        ];
        final career = _isolatedPositionScenario(
          targetTeamId: aiTeam,
          targetStandardPositions: const [
            Position.pg,
            Position.pg,
            Position.sg,
            Position.sg,
            Position.sf,
            Position.sf,
          ],
          poolEntries: pool,
        );

        final offers = _policy.generateOffers(
          career: career,
          marketState: career.freeAgentMarket,
        );
        final teamOffers = offers.where((o) => o.teamId == aiTeam).toList();
        final byId = {for (final e in pool) e.id: e.player.position};
        final offeredPositions = [
          for (final o in teamOffers) byId[o.playerId]!,
        ];
        expect(offeredPositions, contains(Position.pf));
        expect(
          offeredPositions,
          contains(Position.c),
          reason:
              'Must cover C instead of exhausting slots on redundant PFs: $offeredPositions',
        );
      },
    );

    test(
      'F: AI cannot stage its final mandatory standard roster spot on a redundant position while a required position remains unrepresented',
      () {
        final aiTeam = const TeamId('team-19');
        // 13 standard players (missing PF); final 14th spot.
        // Pool has ONLY PG/SG/SF/C (no PF available). AI must NOT waste the 14th
        // mandatory standard spot on a redundant PG.
        final noPfPool = <FreeAgentEntry>[
          _makeFa(
            id: 'fa-pg-star',
            position: Position.pg,
            overall: 82,
            age: 26,
          ),
          _makeFa(id: 'fa-sg-rot', position: Position.sg, overall: 68, age: 26),
        ];
        final blockedCareer = _isolatedPositionScenario(
          targetTeamId: aiTeam,
          targetStandardPositions: const [
            Position.pg,
            Position.pg,
            Position.pg,
            Position.sg,
            Position.sg,
            Position.sg,
            Position.sg,
            Position.sf,
            Position.sf,
            Position.sf,
            Position.c,
            Position.c,
            Position.c,
          ],
          poolEntries: noPfPool,
        );

        final offersWithoutPf = _policy
            .generateOffers(
              career: blockedCareer,
              marketState: blockedCareer.freeAgentMarket,
            )
            .where(
              (o) =>
                  o.teamId == aiTeam && o.category == RosterCategory.standard,
            )
            .toList();
        expect(
          offersWithoutPf,
          isEmpty,
          reason:
              'Final mandatory standard spot must not be spent on redundant PG while PF is missing',
        );

        // When a legal PF is in the pool alongside a higher-OVR PG, AI takes PF.
        final withPfPool = <FreeAgentEntry>[
          ...noPfPool,
          _makeFa(
            id: 'fa-pf-need',
            position: Position.pf,
            overall: 50,
            age: 25,
          ),
        ];
        final solvableCareer = _isolatedPositionScenario(
          targetTeamId: aiTeam,
          targetStandardPositions: const [
            Position.pg,
            Position.pg,
            Position.pg,
            Position.sg,
            Position.sg,
            Position.sg,
            Position.sg,
            Position.sf,
            Position.sf,
            Position.sf,
            Position.c,
            Position.c,
            Position.c,
          ],
          poolEntries: withPfPool,
        );
        final offersWithPf = _policy
            .generateOffers(
              career: solvableCareer,
              marketState: solvableCareer.freeAgentMarket,
            )
            .where(
              (o) =>
                  o.teamId == aiTeam && o.category == RosterCategory.standard,
            )
            .toList();
        expect(offersWithPf.length, 1);
        expect(offersWithPf.single.playerId, const PlayerId('fa-pf-need'));
      },
    );

    test(
      'G: two-way players count toward Roster.covers position coverage in gate and AI offer policy',
      () {
        final teamId = const TeamId('team-10');
        // 14 standard players missing C + 1 two-way C => covered via Roster.covers!
        final coveredByTw = _isolatedPositionScenario(
          targetTeamId: teamId,
          targetStandardPositions: [
            for (var i = 0; i < 4; i++) Position.pg,
            for (var i = 0; i < 4; i++) Position.sg,
            for (var i = 0; i < 3; i++) Position.sf,
            for (var i = 0; i < 3; i++) Position.pf,
          ],
          targetTwoWayPositions: const [Position.c],
          poolEntries: const [],
          completeMarketAndClearance: true,
        );
        final gate = _gate.evaluate(coveredByTw);
        expect(gate.readyCount, 30);
        expect(gate.status, OffseasonReadinessStatus.readyForConfirmation);

        // Also check AI offer policy with 13 standard + 1 two-way C + missing C only in two-way:
        // since Roster.covers(C) is already true via the two-way C, AI can fill
        // the 14th standard spot with a PG normally.
        final aiCanFinish = _isolatedPositionScenario(
          targetTeamId: teamId,
          targetStandardPositions: [
            for (var i = 0; i < 4; i++) Position.pg,
            for (var i = 0; i < 3; i++) Position.sg,
            for (var i = 0; i < 3; i++) Position.sf,
            for (var i = 0; i < 3; i++) Position.pf,
          ],
          targetTwoWayPositions: const [Position.c],
          poolEntries: [
            _makeFa(id: 'fa-pg-1', position: Position.pg, overall: 55, age: 25),
          ],
        );
        final offers = _policy
            .generateOffers(
              career: aiCanFinish,
              marketState: aiCanFinish.freeAgentMarket,
            )
            .where((o) => o.teamId == teamId)
            .toList();
        expect(offers.length, 1);
        expect(offers.single.playerId, const PlayerId('fa-pg-1'));

        // And a 14-standard team missing C with an open two-way slot prioritizes
        // an eligible two-way C over redundant two-way candidates.
        final twFix = _isolatedPositionScenario(
          targetTeamId: teamId,
          targetStandardPositions: [
            for (var i = 0; i < 4; i++) Position.pg,
            for (var i = 0; i < 4; i++) Position.sg,
            for (var i = 0; i < 3; i++) Position.sf,
            for (var i = 0; i < 3; i++) Position.pf,
          ],
          targetTwoWayPositions: const [],
          poolEntries: [
            _makeFa(
              id: 'fa-tw-pg',
              position: Position.pg,
              overall: 64,
              age: 21,
            ),
            _makeFa(id: 'fa-tw-c', position: Position.c, overall: 52, age: 21),
          ],
        );
        final twOffers = _policy
            .generateOffers(career: twFix, marketState: twFix.freeAgentMarket)
            .where((o) => o.teamId == teamId)
            .toList();
        expect(twOffers.length, 1);
        expect(twOffers.single.category, RosterCategory.twoWay);
        expect(twOffers.single.playerId, const PlayerId('fa-tw-c'));
      },
    );

    test(
      'H, I, J, K & L: deterministic, T05B1 cap/cash reservation active, market competition & outbid re-check in Round 2, immutable input, no duplicates',
      () {
        final aiTeam = const TeamId('team-10');
        // 12 standard players (missing C), payroll = 40,000 => 1,000 CU cap room for 2 spots.
        // Must skip expensive C (~2,000+ CU) and pick minimum-affordable C + filler,
        // without exceeding 41,000 cap.
        final pool = <FreeAgentEntry>[
          _makeFa(
            id: 'fa-c-expensive',
            position: Position.c,
            overall: 86,
            age: 28,
          ),
          _makeFa(id: 'fa-c-min', position: Position.c, overall: 46, age: 24),
          _makeFa(id: 'fa-pg-min', position: Position.pg, overall: 46, age: 24),
        ];
        final career = _isolatedPositionScenario(
          targetTeamId: aiTeam,
          targetStandardPositions: const [
            Position.pg,
            Position.pg,
            Position.pg,
            Position.sg,
            Position.sg,
            Position.sg,
            Position.sf,
            Position.sf,
            Position.sf,
            Position.pf,
            Position.pf,
            Position.pf,
          ],
          targetContinuingPayroll: 40000,
          targetProjectedCash: 50000,
          poolEntries: pool,
        );
        final beforeJson = GmCareerCodec.encode(career);
        final run1 = _policy.generateOffers(
          career: career,
          marketState: career.freeAgentMarket,
        );
        final run2 = _policy.generateOffers(
          career: career,
          marketState: career.freeAgentMarket,
        );
        // H: deterministic
        expect(
          jsonEncode([for (final o in run1) o.toJson()]),
          jsonEncode([for (final o in run2) o.toJson()]),
        );
        // K: no direct mutations to career
        expect(GmCareerCodec.encode(career), beforeJson);
        // L: no duplicate player offers per team
        final offeredPlayers = [
          for (final o in run1.where((o) => o.teamId == aiTeam))
            o.playerId.value,
        ];
        expect(offeredPlayers.toSet().length, offeredPlayers.length);

        // I: cap reservation preserved (expensive C skipped, affordable C + PG taken)
        final stdOffers = run1
            .where(
              (o) =>
                  o.teamId == aiTeam && o.category == RosterCategory.standard,
            )
            .toList();
        expect(
          stdOffers.any((o) => o.playerId == const PlayerId('fa-c-min')),
          isTrue,
        );
        expect(
          stdOffers.any((o) => o.playerId == const PlayerId('fa-c-expensive')),
          isFalse,
        );

        // J: if human steals the preferred C in Round 1 via higher bid while a
        // second C remains available, the AI team finishes R1 still missing C
        // and re-evaluates actual roster coverage in Round 2 to target fa-c-r2.
        final rivalPool = <FreeAgentEntry>[
          _makeFa(id: 'fa-c-r1', position: Position.c, overall: 58, age: 25),
          _makeFa(id: 'fa-c-r2', position: Position.c, overall: 46, age: 24),
          _makeFa(
            id: 'fa-pg-filler',
            position: Position.pg,
            overall: 46,
            age: 24,
          ),
        ];
        var multiRound = _isolatedPositionScenario(
          targetTeamId: aiTeam,
          targetStandardPositions: const [
            Position.pg,
            Position.pg,
            Position.pg,
            Position.pg,
            Position.sg,
            Position.sg,
            Position.sg,
            Position.sf,
            Position.sf,
            Position.sf,
            Position.pf,
            Position.pf,
            Position.pf,
          ],
          targetTwoWayPositions: const [Position.pg, Position.sg, Position.sf],
          poolEntries: rivalPool,
        );
        multiRound = _marketService.stageHumanOffer(
          career: multiRound,
          teamId: multiRound.userFranchiseId,
          playerId: const PlayerId('fa-c-r1'),
          category: RosterCategory.standard,
          durationYears: 1,
          firstYearSalary: 3000,
        );
        multiRound = _marketService.prepareResolution(multiRound);
        while (multiRound.freeAgentMarket.isResolvable) {
          multiRound = _marketService.resolveNext(multiRound);
        }
        expect(
          multiRound.league.teams
              .firstWhere((t) => t.id == aiTeam)
              .roster
              .covers(Position.c),
          isFalse,
        );
        multiRound = _marketService.startRound(multiRound);
        final r2AiOffers = _policy
            .generateOffers(
              career: multiRound,
              marketState: multiRound.freeAgentMarket,
            )
            .where((o) => o.teamId == aiTeam)
            .toList();
        expect(
          r2AiOffers.any((o) => o.playerId == const PlayerId('fa-c-r2')),
          isTrue,
        );
      },
    );
  });
}
