import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _seed = 20261028;
const _policy = AiFreeAgentOfferPolicy();
const _marketService = FreeAgentMarketService();

GmCareer _baseCareer() => GmCareer.fromSetupResult(
  const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: _seed,
    ),
  ),
  id: 't05b1-cap-reservation',
);

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

/// Builds a clean Year 3 offseason career where only [aiTeamId] needs players
/// (all other 28 AI teams already have 14 standard + 3 two-way players) so
/// [AiFreeAgentOfferPolicy] decisions for [aiTeamId] are isolated and exact.
GmCareer _isolatedAiScenario({
  required TeamId aiTeamId,
  required int aiStandardCount,
  required int aiContinuingPayroll,
  required int aiProjectedCash,
  required List<FreeAgentEntry> poolEntries,
  int aiTwoWayCount = 0,
  FranchiseSituation aiSituation = FranchiseSituation.playIn,
}) {
  final base = _baseCareer();
  final currentYear = 3;
  final profiles = <String, PlayerCareerProfile>{};
  final contracts = <PlayerContract>[];
  final schedules = <ContractFinancials>[];
  final teams = <Team>[];
  final teamFinances = <TeamFinances>[];

  for (var tIdx = 0; tIdx < base.league.teams.length; tIdx++) {
    final orig = base.league.teams[tIdx];
    final isTarget = orig.id == aiTeamId;
    final stdCount = isTarget ? aiStandardCount : 14;
    final twCount = isTarget ? aiTwoWayCount : 3;
    final rosterPlayers = <Player>[];
    final categories = <String, RosterCategory>{};

    final baseSal = isTarget && stdCount > 0
        ? aiContinuingPayroll ~/ stdCount
        : 0;
    final remSal = isTarget && stdCount > 0
        ? aiContinuingPayroll % stdCount
        : 0;
    for (var i = 0; i < stdCount; i++) {
      final pid = '${orig.id.value}-std-$i';
      final pos = Position.values[i % Position.values.length];
      final player = _makePlayer(id: pid, position: pos, overall: 65);
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

    for (var i = 0; i < twCount; i++) {
      final pid = '${orig.id.value}-tw-$i';
      final pos = Position.values[i % Position.values.length];
      final player = _makePlayer(id: pid, position: pos, overall: 58);
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
        situation: isTarget ? aiSituation : orig.situation,
        roster: Roster(rosterPlayers, categories: categories),
      ),
    );

    final origTf = base.finances.financesFor(orig.id);
    final totalExistingPayroll = isTarget
        ? aiContinuingPayroll + twCount * FinancialRules.twoWaySalary
        : stdCount * FinancialRules.minimumSalary +
              twCount * FinancialRules.twoWaySalary;
    // projectedEndOfSeasonCash = cash + revenueBaseline - cashPayroll - opCommitments
    final opCommitments = base.finances.operatingCommitmentsFor(orig.id);
    final desiredCash = isTarget
        ? (aiProjectedCash -
                  origTf.revenueBaseline +
                  totalExistingPayroll +
                  opCommitments)
              .clamp(0, FinancialRules.maximumBalance)
        : 50000;
    final desiredRev =
        isTarget &&
            (aiProjectedCash -
                    origTf.revenueBaseline +
                    totalExistingPayroll +
                    opCommitments) <
                0
        ? aiProjectedCash + totalExistingPayroll + opCommitments
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
  return base.copyWith(
    currentYear: currentYear,
    league: league,
    careerProfiles: LeagueCareerProfiles(
      schemaVersion: base.careerProfiles.schemaVersion,
      leagueSeed: base.careerProfiles.leagueSeed,
      profiles: profiles,
    ),
    draftClass: const DraftGenerator().generateDraftClass(
      league: league,
      seed: base.generationSeed + currentYear,
      seasonYear: currentYear,
    ),
    rookieSigningLedger: RookieSigningLedger.empty(),
    freeAgentPool: FreeAgentPool(
      seasonYear: currentYear,
      entries: poolEntries,
      initialPlayerIds: [for (final e in poolEntries) e.id],
    ),
    freeAgentOffers: FreeAgentOfferLedger.empty(),
    freeAgentMarket: FreeAgentMarketState.initial(seasonYear: currentYear)
        .copyWith(
          status: FreeAgentMarketStatus.collectingHumanOffers,
          roundNumber: 1,
        ),
    offseasonClearance: OffseasonClearanceState.initial(
      seasonYear: currentYear,
    ),
    hardshipSettlement: HardshipSettlement.initial(seasonYear: currentYear),
    finances: finances,
  );
}

void main() {
  group('T05B1 AI free-agency minimum-roster cap and cash reservation', () {
    test(
      'A-D: 7-player AI team skips premium offer that leaves insufficient cap for remaining mandatory spots and takes affordable offers',
      () {
        // Team has 7 standard players, needs 7 more, and has 4,400 CU cap room
        // (continuing payroll = 36,600 CU; 7 * 400 = 2,800 CU minimum needed).
        // Max allowed for the 1st of 7 needed signings = 4,400 - 6*400 = 2,000 CU.
        // A premium 80 OVR SF demands ~5,000+ CU (exceeding cap room anyway or
        // let's make a 70 OVR SF whose estimated salary is ~2,600 CU, which fits
        // under 4,400 CU raw cap room but leaves only <= 1,800 CU for 6 spots!).
        final pool = <FreeAgentEntry>[
          _makeFa(id: 'fa-prem-1', position: Position.sf, overall: 70, age: 27),
          for (var i = 0; i < 10; i++)
            _makeFa(
              id: 'fa-min-$i',
              position: Position.values[i % Position.values.length],
              overall: 45,
              age: 24,
            ),
        ];
        final aiTeamId = const TeamId('team-28');
        final career = _isolatedAiScenario(
          aiTeamId: aiTeamId,
          aiStandardCount: 7,
          aiContinuingPayroll: 36600,
          aiProjectedCash: 50000,
          poolEntries: pool,
        );

        final offers = _policy.generateOffers(
          career: career,
          marketState: career.freeAgentMarket,
        );
        final teamOffers = offers
            .where(
              (o) =>
                  o.teamId == aiTeamId && o.category == RosterCategory.standard,
            )
            .toList();

        expect(FinancialRules.salaryCap, 41000);
        // Must not bid on fa-prem-1 because doing so leaves < 6 * 400 CU for remaining 6 slots.
        expect(teamOffers.any((o) => o.playerId.value == 'fa-prem-1'), isFalse);
        // Must fill all 7 standard spots using the affordable 400 CU candidates.
        expect(teamOffers.length, 7);
        final committed = teamOffers.fold<int>(
          0,
          (sum, o) => sum + o.firstYearSalary,
        );
        expect(36600 + committed, lessThanOrEqualTo(FinancialRules.salaryCap));
      },
    );

    test(
      'A-F: CVF-like 7-player scenario with 20,273 CU cap room reserves minimum slots across staged offers and reaches 14 standard players',
      () {
        // Mirrors team-28 / CVF: 7 standard players, 20,727 CU continuing payroll
        // (20,273 CU cap room), 4 expensive premium free agents totaling 20,209 CU,
        // plus cheap 400 CU depth free agents.
        final pool = <FreeAgentEntry>[
          _makeFa(id: 'fa-star-1', position: Position.sf, overall: 86, age: 31),
          _makeFa(id: 'fa-star-2', position: Position.sf, overall: 78, age: 33),
          _makeFa(id: 'fa-star-3', position: Position.sf, overall: 77, age: 30),
          _makeFa(id: 'fa-star-4', position: Position.sf, overall: 72, age: 33),
          for (var i = 0; i < 12; i++)
            _makeFa(
              id: 'fa-depth-$i',
              position: Position.values[i % Position.values.length],
              overall: 46,
              age: 24,
            ),
        ];
        final aiTeamId = const TeamId('team-28');
        final career = _isolatedAiScenario(
          aiTeamId: aiTeamId,
          aiStandardCount: 7,
          aiContinuingPayroll: 20727,
          aiProjectedCash: 50000,
          poolEntries: pool,
        );

        var marketCareer = _marketService.prepareResolution(career);
        final aiOffers = marketCareer.freeAgentMarket.aiOffers
            .where(
              (o) =>
                  o.teamId == aiTeamId && o.category == RosterCategory.standard,
            )
            .toList();

        // After each staged offer, remaining cap room must cover 400 CU * remaining needed slots.
        var runningCap = 20727;
        for (var i = 0; i < aiOffers.length; i++) {
          runningCap += aiOffers[i].firstYearSalary;
          final remainingNeeded = 7 - (i + 1);
          expect(
            FinancialRules.salaryCap - runningCap,
            greaterThanOrEqualTo(
              remainingNeeded * FinancialRules.minimumSalary,
            ),
          );
        }

        while (marketCareer.freeAgentMarket.isResolvable) {
          marketCareer = _marketService.resolveNext(marketCareer);
        }
        // Run Round 2 (normal two-round competitive market completion).
        marketCareer = _marketService.startRound(marketCareer);
        marketCareer = _marketService.prepareResolution(marketCareer);
        while (marketCareer.freeAgentMarket.isResolvable) {
          marketCareer = _marketService.resolveNext(marketCareer);
        }
        final resolvedTeam = marketCareer.league.teams.firstWhere(
          (t) => t.id == aiTeamId,
        );
        final remainingRoom =
            FinancialRules.salaryCap -
            marketCareer.finances.capPayrollFor(aiTeamId, 3);
        final stillNeeded =
            FinancialRules.minimumStandardRoster -
            resolvedTeam.roster.standardCount;
        expect(
          remainingRoom,
          greaterThanOrEqualTo(stillNeeded * FinancialRules.minimumSalary),
        );
        expect(resolvedTeam.roster.standardCount, 14);
      },
    );

    test(
      'E & F: continuing payroll and previously staged AI offers reduce remaining cap budget for subsequent slots',
      () {
        // 11 standard players (needs 3), continuing payroll = 37,400 CU (3,600 CU cap room).
        // Slot 1 takes 2,600 CU (leaving 1,000 CU for 2 remaining slots -> >= 800 CU, allowed).
        // Slot 2 sees a 700 CU player: 2,600 + 700 = 3,300 CU, leaving only 300 CU (< 400 CU)
        // for the 14th slot, so Slot 2 MUST skip the 700 CU player and take 400 CU players.
        final pool = <FreeAgentEntry>[
          _makeFa(id: 'fa-mid-1', position: Position.sf, overall: 70, age: 27),
          _makeFa(id: 'fa-mid-2', position: Position.pf, overall: 58, age: 27),
          for (var i = 0; i < 6; i++)
            _makeFa(
              id: 'fa-min-$i',
              position: Position.values[i % Position.values.length],
              overall: 46,
              age: 24,
            ),
        ];
        final aiTeamId = const TeamId('team-28');
        final career = _isolatedAiScenario(
          aiTeamId: aiTeamId,
          aiStandardCount: 11,
          aiContinuingPayroll: 37400,
          aiProjectedCash: 50000,
          poolEntries: pool,
        );

        final offers = _policy.generateOffers(
          career: career,
          marketState: career.freeAgentMarket,
        );
        final stdOffers = offers
            .where(
              (o) =>
                  o.teamId == aiTeamId && o.category == RosterCategory.standard,
            )
            .toList();

        expect(stdOffers.length, 3);
        expect(
          37400 + stdOffers.fold<int>(0, (s, o) => s + o.firstYearSalary),
          lessThanOrEqualTo(FinancialRules.salaryCap),
        );
      },
    );

    test(
      'G & H: projected cash reserves remaining minimum standard contracts and two-way offer cannot exhaust cash needed for mandatory standard completion',
      () {
        // Team has 12 standard players (needs 2), plenty of cap room (30,000 CU),
        // but projected cash is only 1,000 CU (enough for 2 * 400 = 800 CU + 200 CU left).
        // fa-cash-heavy (OVR 58, age 27) wants ~660-710 CU, which fits raw 1,000 CU cash
        // BEFORE the fix, leaving <= 340 CU (< 400 CU) for the 14th standard spot!
        final pool = <FreeAgentEntry>[
          _makeFa(
            id: 'fa-cash-heavy',
            position: Position.sf,
            overall: 58,
            age: 27,
          ),
          _makeFa(
            id: 'fa-tw-young',
            position: Position.sg,
            overall: 55,
            age: 20,
          ),
          for (var i = 0; i < 6; i++)
            _makeFa(
              id: 'fa-cheap-$i',
              position: Position.values[i % Position.values.length],
              overall: 45,
              age: 24,
            ),
        ];
        final aiTeamId = const TeamId('team-28');
        final career = _isolatedAiScenario(
          aiTeamId: aiTeamId,
          aiStandardCount: 12,
          aiContinuingPayroll: 11000,
          aiProjectedCash: 1000,
          aiTwoWayCount: 0,
          poolEntries: pool,
        );

        final offers = _policy.generateOffers(
          career: career,
          marketState: career.freeAgentMarket,
        );
        final teamOffers = offers.where((o) => o.teamId == aiTeamId).toList();
        final stdOffers = teamOffers
            .where((o) => o.category == RosterCategory.standard)
            .toList();
        final twOffers = teamOffers
            .where((o) => o.category == RosterCategory.twoWay)
            .toList();

        expect(stdOffers.length, 2);
        expect(
          stdOffers.any((o) => o.playerId.value == 'fa-cash-heavy'),
          isFalse,
        );
        // 800 CU spent on 2 standard players leaves 200 CU < 250 CU two-way salary.
        expect(twOffers, isEmpty);
        final totalCash = teamOffers.fold<int>(
          0,
          (sum, o) => sum + o.firstYearSalary,
        );
        expect(totalCash, lessThanOrEqualTo(1000));
      },
    );

    test(
      'I: AI team already at 14 standard players reserves 0 for mandatory spots and can sign a two-way up to full cash',
      () {
        final pool = <FreeAgentEntry>[
          _makeFa(id: 'fa-tw-ok', position: Position.sg, overall: 55, age: 20),
        ];
        final aiTeamId = const TeamId('team-28');
        final career = _isolatedAiScenario(
          aiTeamId: aiTeamId,
          aiStandardCount: 14,
          aiContinuingPayroll: 41000, // 0 cap room
          aiProjectedCash: 250, // exact two-way cash
          aiTwoWayCount: 0,
          poolEntries: pool,
        );

        final offers = _policy.generateOffers(
          career: career,
          marketState: career.freeAgentMarket,
        );
        final teamOffers = offers.where((o) => o.teamId == aiTeamId).toList();
        expect(teamOffers.length, 1);
        expect(teamOffers.single.category, RosterCategory.twoWay);
        expect(teamOffers.single.firstYearSalary, FinancialRules.twoWaySalary);
      },
    );

    test(
      'J & K: repeated same input yields identical offer sequence with zero roster, contract, or capacity violations',
      () {
        final pool = <FreeAgentEntry>[
          _makeFa(id: 'fa-star-1', position: Position.sf, overall: 86, age: 31),
          for (var i = 0; i < 10; i++)
            _makeFa(
              id: 'fa-min-$i',
              position: Position.values[i % Position.values.length],
              overall: 46,
              age: 24,
            ),
        ];
        final career = _isolatedAiScenario(
          aiTeamId: const TeamId('team-28'),
          aiStandardCount: 7,
          aiContinuingPayroll: 20727,
          aiProjectedCash: 50000,
          poolEntries: pool,
        );

        final run1 = _policy.generateOffers(
          career: career,
          marketState: career.freeAgentMarket,
        );
        final run2 = _policy.generateOffers(
          career: career,
          marketState: career.freeAgentMarket,
        );
        expect(
          jsonEncode([for (final o in run1) o.toJson()]),
          jsonEncode([for (final o in run2) o.toJson()]),
        );

        var resolved = _marketService.prepareResolution(career);
        while (resolved.freeAgentMarket.isResolvable) {
          resolved = _marketService.resolveNext(resolved);
        }
        resolved.validate();
        for (final team in resolved.league.teams) {
          expect(
            team.roster.standardCount,
            lessThanOrEqualTo(RosterRules.maxOffseasonStandard),
          );
          expect(
            team.roster.twoWayCount,
            lessThanOrEqualTo(RosterRules.maxOffseasonTwoWay),
          );
          expect(
            team.roster.totalContractedCount,
            lessThanOrEqualTo(RosterRules.maxOffseasonTotal),
          );
        }
      },
    );

    test(
      'L: when starting cap or cash is already insufficient for legal minimum completion, returns truthful bounded offers without granting relief or fabricating players',
      () {
        // 7 standard players (needs 7 => 2,800 CU min), but only 2,000 CU cap room.
        final pool = <FreeAgentEntry>[
          for (var i = 0; i < 10; i++)
            _makeFa(
              id: 'fa-min-$i',
              position: Position.values[i % Position.values.length],
              overall: 45,
              age: 24,
            ),
        ];
        final aiTeamId = const TeamId('team-28');
        final capBlocked = _isolatedAiScenario(
          aiTeamId: aiTeamId,
          aiStandardCount: 7,
          aiContinuingPayroll: 39000, // 2,000 CU cap room < 2,800 CU
          aiProjectedCash: 50000,
          poolEntries: pool,
        );
        final capOffers = _policy.generateOffers(
          career: capBlocked,
          marketState: capBlocked.freeAgentMarket,
        );
        expect(capOffers.where((o) => o.teamId == aiTeamId), isEmpty);
        expect(capBlocked.finances.financesFor(aiTeamId).capException, 0);

        // Cash-blocked: 7 standard players (needs 7 => 2,800 CU min), plenty of cap,
        // but only 2,000 CU projected cash.
        final cashBlocked = _isolatedAiScenario(
          aiTeamId: aiTeamId,
          aiStandardCount: 7,
          aiContinuingPayroll: 10000,
          aiProjectedCash: 2000,
          poolEntries: pool,
        );
        final cashOffers = _policy.generateOffers(
          career: cashBlocked,
          marketState: cashBlocked.freeAgentMarket,
        );
        expect(cashOffers.where((o) => o.teamId == aiTeamId), isEmpty);
        expect(cashBlocked.finances.financesFor(aiTeamId).capException, 0);
      },
    );
  });
}
