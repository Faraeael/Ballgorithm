import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _seed = 20261028;
const _policy = AiFreeAgentOfferPolicy();
const _evaluator = FreeAgentOfferEvaluator();
const _market = FreeAgentMarketValueService();

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
  required int age,
}) => FreeAgentEntry(
  player: _makePlayer(id: id, position: position, overall: overall),
  profile: PlayerCareerProfile(
    playerId: PlayerId(id),
    age: age,
    potential: overall < 75 ? 75 : overall,
    trajectory: DevelopmentTrajectory.steady,
  ),
);

GmCareer _isolatedCapScenario({
  required TeamId aiTeamId,
  required int aiStandardCount,
  required int aiContinuingPayroll,
  required FranchiseSituation aiSituation,
  required List<FreeAgentEntry> poolEntries,
  int aiTwoWayCount = 3,
}) {
  final base = GmCareer.fromSetupResult(
    const CareerSetupService().generate(
      const CareerSetupRequest(
        selectedTeamId: TeamId('team-1'),
        selectedSituation: FranchiseSituation.tanking,
        seed: _seed,
      ),
    ),
    id: 't05b-fix1-salary-efficiency',
  );
  const currentYear = 3;
  final profiles = <String, PlayerCareerProfile>{};
  final contracts = <PlayerContract>[];
  final schedules = <ContractFinancials>[];
  final teams = <Team>[];
  final teamFinances = <TeamFinances>[];

  for (final orig in base.league.teams) {
    final isTarget = orig.id == aiTeamId;
    final stdCount = isTarget ? aiStandardCount : 14;
    final twCount = isTarget ? aiTwoWayCount : 3;
    final rosterPlayers = <Player>[];
    final categories = <String, RosterCategory>{};

    final totalTargetPay = isTarget
        ? aiContinuingPayroll
        : stdCount * FinancialRules.minimumSalary;
    final baseSal = stdCount > 0 ? totalTargetPay ~/ stdCount : 0;
    final remSal = stdCount > 0 ? totalTargetPay % stdCount : 0;

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
      final sal = baseSal + (i < remSal ? 1 : 0);
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
    teamFinances.add(
      TeamFinances(
        teamId: orig.id,
        operatingBudget: origTf.operatingBudget,
        cash: 50000,
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
  group('T05B-FIX1 AI salary efficiency', () {
    test(
      'cap-tight 2-slot contender offers lowest acceptable salary on slot 1 so remaining cap covers slot 2',
      () {
        // Mirrors KSM (team-19, 1,700 CU cap room for 2 spots):
        // - fa-pf-vet (ovr=64, age=35): est=1,190, accMin=1,010, contender lowAcc=950.
        // - fa-c-young (ovr=58, age=21): est=680, accMin=580, contender lowAcc=670.
        // Paying est (1,190) on fa-pf-vet leaves only 510 CU < 670 CU, stranding slot 2.
        // Proposing lowest acceptable salary (950 CU) leaves 750 CU >= 670 CU for slot 2.
        final aiTeamId = const TeamId('team-19');
        final pool = [
          _makeFa(id: 'fa-pf-vet', position: Position.pf, overall: 64, age: 35),
          _makeFa(id: 'fa-c-young', position: Position.c, overall: 58, age: 21),
        ];
        final career = _isolatedCapScenario(
          aiTeamId: aiTeamId,
          aiStandardCount: 12,
          aiContinuingPayroll: 39300, // 1,700 CU cap room
          aiSituation: FranchiseSituation.contender,
          poolEntries: pool,
        );

        final offers = _policy
            .generateOffers(career: career, marketState: career.freeAgentMarket)
            .where((o) => o.teamId == aiTeamId)
            .toList();

        expect(
          offers.length,
          2,
          reason:
              'Both mandatory standard slots must be filled without overspending slot 1: '
              '${offers.map((o) => "${o.playerId.value}:${o.firstYearSalary}").toList()}',
        );
        final totalSalary = offers.fold<int>(
          0,
          (sum, offer) => sum + offer.firstYearSalary,
        );
        expect(totalSalary, lessThanOrEqualTo(1700));
        for (final offer in offers) {
          expect(
            offer.firstYearSalary,
            greaterThanOrEqualTo(FinancialRules.minimumSalary),
          );
          final decision = _evaluator.evaluate(
            career: career,
            teamId: aiTeamId,
            freeAgentId: offer.playerId,
            category: offer.category,
            durationYears: offer.durationYears,
            agreedFirstYearSalary: offer.firstYearSalary,
          );
          expect(decision.isFinanciallyLegal, isTrue);
          expect(decision.isAcceptable, isTrue);
        }
      },
    );

    test(
      '1-slot team whose cap room is below estimatedAnnualSalary still signs when lowest acceptable salary fits',
      () {
        // Tanking 13-player team with 600 CU cap room:
        // fa-young-wing (ovr=58, age=21): est=680 > 600, accMin=580,
        // tanking +1200 bp makes lowest acceptable <= 520 <= 600 CU.
        final aiTeamId = const TeamId('team-19');
        final fa = _makeFa(
          id: 'fa-young-wing',
          position: Position.sf,
          overall: 58,
          age: 21,
        );
        final val = _market.estimate(fa.toPublicView());
        expect(val.estimatedAnnualSalary, greaterThan(600));

        final career = _isolatedCapScenario(
          aiTeamId: aiTeamId,
          aiStandardCount: 13,
          aiContinuingPayroll: 40400, // 600 CU cap room
          aiSituation: FranchiseSituation.tanking,
          poolEntries: [fa],
        );

        final offers1 = _policy
            .generateOffers(career: career, marketState: career.freeAgentMarket)
            .where((o) => o.teamId == aiTeamId)
            .toList();
        final offers2 = _policy
            .generateOffers(career: career, marketState: career.freeAgentMarket)
            .where((o) => o.teamId == aiTeamId)
            .toList();

        expect(offers1.length, 1);
        expect(
          offers1.single.firstYearSalary,
          inInclusiveRange(FinancialRules.minimumSalary, 600),
        );
        expect(
          jsonEncode([for (final o in offers1) o.toJson()]),
          jsonEncode([for (final o in offers2) o.toJson()]),
        );
      },
    );

    test(
      'same-round resolution-ordered prefix depth adjustment prevents salaryTooLow rejections',
      () {
        // aiStandardCount: 4 covers PG, SG, SF, PF (1 each) and leaves C=0.
        // fa-c-z (ovr=70) is higher priority to stage first while C appears empty,
        // but fa-c-a (ovr=62) resolves earlier alphabetically by playerId and drops
        // C from empty (+800 bp) to populated (0 bp). Prefix re-evaluation bumps
        // fa-c-z so both sign without mid-round rejection.
        final aiTeamId = const TeamId('team-19');
        final pool = [
          _makeFa(id: 'fa-c-z', position: Position.c, overall: 70, age: 26),
          _makeFa(id: 'fa-c-a', position: Position.c, overall: 62, age: 26),
          _makeFa(id: 'fa-pg-1', position: Position.pg, overall: 64, age: 26),
          _makeFa(id: 'fa-pg-2', position: Position.pg, overall: 63, age: 26),
          _makeFa(id: 'fa-sg-1', position: Position.sg, overall: 64, age: 26),
          _makeFa(id: 'fa-sg-2', position: Position.sg, overall: 63, age: 26),
          _makeFa(id: 'fa-sf-1', position: Position.sf, overall: 64, age: 26),
          _makeFa(id: 'fa-sf-2', position: Position.sf, overall: 63, age: 26),
          _makeFa(id: 'fa-pf-1', position: Position.pf, overall: 64, age: 26),
          _makeFa(id: 'fa-pf-2', position: Position.pf, overall: 63, age: 26),
        ];
        var career = _isolatedCapScenario(
          aiTeamId: aiTeamId,
          aiStandardCount: 4,
          aiContinuingPayroll: 8000,
          aiSituation: FranchiseSituation.playIn,
          poolEntries: pool,
        );

        const marketService = FreeAgentMarketService();
        career = marketService.prepareResolution(career);
        while (career.freeAgentMarket.isResolvable) {
          career = marketService.resolveNext(career);
        }

        final teamAfter = career.league.teams.firstWhere(
          (t) => t.id == aiTeamId,
        );
        expect(teamAfter.roster.standardCount, 14);
        final rejected = [
          for (final outcome
              in career.freeAgentMarket.roundHistory.last.outcomes)
            for (final result in outcome.results)
              if (result.teamId == aiTeamId &&
                  result.outcome == FreeAgentMarketOfferOutcome.rejected)
                result,
        ];
        expect(rejected, isEmpty);
      },
    );
  });
}
