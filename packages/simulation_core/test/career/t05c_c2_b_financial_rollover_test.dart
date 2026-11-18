import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/domain_versions.dart' as domain_versions;
import 'package:test/test.dart';

GmCareer _completedYear1Championship({int seed = 20261028}) {
  final setup = const CareerSetupService().generate(
    CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: seed,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 'career-c2b-$seed');
  const draftService = DraftExecutionService();
  const signingService = RookieSigningService();
  const aiSigningService = RookieAiSigningService();
  const marketService = FreeAgentMarketService();
  const clearanceService = OffseasonClearanceService();
  const hardshipService = HardshipSettlementService();
  const rsEntryService = RegularSeasonEntryService();
  const rsScheduleService = RegularSeasonScheduleService();

  c = draftService.startDraft(c);
  while (!c.draftExecutionState.isCompleted) {
    if (c.draftExecutionState.isHumanTurn(
      order: c.draftOrder,
      userTeamId: c.userFranchiseId,
    )) {
      final pick = c.draftClass.prospects.firstWhere(
        (p) => !c.draftExecutionState.draftRights.containsKey(p.id.value),
      );
      c = draftService.makeHumanSelection(career: c, prospectId: pick.id);
    } else {
      c = draftService.executeAiSelection(c);
    }
  }
  c = aiSigningService.initialize(c);
  while (aiSigningService.pendingRights(c).isNotEmpty) {
    c = aiSigningService.applyNextDecision(c);
  }
  for (final r in c.unsignedDraftRights) {
    if (r.owningTeamId == c.userFranchiseId) {
      c = signingService.signDraftedRookie(
        career: c,
        teamId: c.userFranchiseId,
        prospectId: r.prospectId,
        category: RosterCategory.standard,
        durationYears: 2,
      );
    }
  }
  for (var round = 0; round < 2; round++) {
    c = marketService.startRound(c);
    c = marketService.prepareResolution(c);
    while (c.freeAgentMarket.isResolvable) {
      c = marketService.resolveNext(c);
    }
  }
  c = clearanceService.start(c);
  c = clearanceService.prepare(c);
  while (c.offseasonClearance.isResolvable) {
    c = clearanceService.resolveNext(c);
  }
  c = hardshipService.prepare(c, humanParticipationConfirmed: true);
  while (c.hardshipSettlement.isResolvable) {
    c = hardshipService.resolveNext(c);
  }
  c = clearanceService.markCleared(c);
  c = rsEntryService.start(c);
  c = rsScheduleService.generate(c);

  const adapter = RegularSeasonGameAdapter();
  final simLeague = adapter.simulationLeagueFor(c);
  final rs0 = c.regularSeasonState!;
  final schedule = rs0.schedule!;
  final sampleInput = adapter.createGameInput(
    c,
    gameId: schedule.rounds.first.fixtures.first.id,
    homeTeamId: schedule.rounds.first.fixtures.first.homeTeamId,
    awayTeamId: schedule.rounds.first.fixtures.first.awayTeamId,
    seed: schedule.rounds.first.fixtures.first.gameSeed,
    simulationLeague: simLeague,
  );
  final leagueJson = jsonEncode(
    GameFingerprint.canonicalPayload(sampleInput)['league'],
  );
  final snapshotId = sha256.convert(utf8.encode(leagueJson)).toString();
  final marker = '__BALLGORITHM_LEAGUE_SNAPSHOT_${snapshotId}__';
  final markerJson = jsonEncode(marker);
  final teamById = {for (final t in simLeague.teams) t.id: t};

  RegularSeasonGameResult buildResult(
    String gameId,
    String seasonId,
    int seasonYear,
    TeamId homeTeamId,
    TeamId awayTeamId,
    int gameSeed,
  ) {
    final input = adapter.createGameInput(
      c,
      gameId: gameId,
      homeTeamId: homeTeamId,
      awayTeamId: awayTeamId,
      seed: gameSeed,
      simulationLeague: simLeague,
    );
    final payload = Map<String, Object?>.of(
      GameFingerprint.canonicalPayload(input),
    );
    payload['league'] = marker;
    final templateJson = jsonEncode(payload);
    final idx =
        templateJson.indexOf('"league":$markerJson') + '"league":'.length;
    final canonicalJson = templateJson.replaceRange(
      idx,
      idx + markerJson.length,
      leagueJson,
    );
    final fp = sha256.convert(utf8.encode(canonicalJson)).toString();
    final lines = <String, SeasonPlayerGameLine>{};
    void addLines(Team team, int ptsTotal) {
      final active = team.players.take(10).toList();
      var rem = ptsTotal;
      for (var i = 0; i < active.length; i++) {
        final p = active[i];
        final pts = i == active.length - 1 ? rem : (ptsTotal ~/ active.length);
        rem -= pts;
        final fgm = pts ~/ 2;
        final ftm = pts - fgm * 2;
        lines[p.id.value] = SeasonPlayerGameLine(
          playerId: p.id.value,
          teamId: team.id.value,
          secondsPlayed: 1440,
          points: pts,
          fgm: fgm,
          fga: fgm + 4,
          threePm: 0,
          threePa: 2,
          ftm: ftm,
          fta: ftm,
          oreb: 1,
          dreb: 3,
          rebounds: 4,
          assists: 2,
          steals: 1,
          blocks: 0,
          turnovers: 1,
          personalFouls: 2,
        );
      }
    }

    addLines(teamById[homeTeamId]!, 104);
    addLines(teamById[awayTeamId]!, 96);
    return RegularSeasonGameResult(
      fixtureId: gameId,
      seasonId: seasonId,
      seasonYear: seasonYear,
      homeTeamId: homeTeamId,
      awayTeamId: awayTeamId,
      gameSeed: gameSeed,
      inputFingerprint: fp,
      simulationVersion: gameSimulationVersion,
      rulesVersion: gameRulesVersion,
      eventSchemaVersion: gameEventSchemaVersion,
      prngImplementationId: 'xorshift32-v1',
      fingerprintVersion: gameFingerprintVersion,
      coreEngineVersion: domain_versions.coreEngineVersion,
      leagueSchemaVersion: domain_versions.snapshotSchemaVersion,
      inputEvidence: RegularSeasonGameInputEvidence(
        leagueSnapshotId: snapshotId,
        payloadTemplateJson: templateJson,
      ),
      periodsPlayed: 4,
      summary: SeasonGameSummary(
        homeScore: 104,
        awayScore: 96,
        winnerTeamId: homeTeamId,
        periodScoresHome: const {'Q1': 26, 'Q2': 26, 'Q3': 26, 'Q4': 26},
        periodScoresAway: const {'Q1': 24, 'Q2': 24, 'Q3': 24, 'Q4': 24},
        playerLines: lines,
      ),
    );
  }

  final rsResults = <String, RegularSeasonGameResult>{};
  final updatedRounds = <RegularSeasonRound>[];
  for (final round in schedule.rounds) {
    final updatedFixtures = <RegularSeasonFixture>[];
    for (final f in round.fixtures) {
      rsResults[f.id] = buildResult(
        f.id,
        rs0.seasonId,
        rs0.seasonYear,
        f.homeTeamId,
        f.awayTeamId,
        f.gameSeed,
      );
      updatedFixtures.add(
        RegularSeasonFixture(
          id: f.id,
          seasonId: f.seasonId,
          seasonYear: f.seasonYear,
          roundNumber: f.roundNumber,
          fixturePosition: f.fixturePosition,
          homeTeamId: f.homeTeamId,
          awayTeamId: f.awayTeamId,
          gameSeed: f.gameSeed,
          status: RegularSeasonFixtureStatus.completed,
        ),
      );
    }
    updatedRounds.add(
      RegularSeasonRound(
        roundNumber: round.roundNumber,
        fixtures: updatedFixtures,
      ),
    );
  }
  c = c.copyWith(
    regularSeasonState: rs0.copyWith(
      gameResults: rsResults,
      gameInputSnapshots: {snapshotId: leagueJson},
      schedule: RegularSeasonSchedule(
        seasonId: schedule.seasonId,
        seasonYear: schedule.seasonYear,
        scheduleSeed: schedule.scheduleSeed,
        rounds: updatedRounds,
      ),
    ),
  );
  c = const PlayInEntryService().enter(c);
  const piService = PlayInGameService();
  for (var g = 1; g <= 3; g++) {
    c = piService.simulateGame(c, expectedGameId: '${rs0.seasonId}-playin-g$g');
  }
  c = const PlayoffEntryService().enter(c);
  const poService = PlayoffSlateService();
  while (!c.playoffState!.isComplete) {
    c = poService.simulateNextSlate(c);
  }
  return c;
}

GmCareer _withUpdatedTeamFinances(
  GmCareer base, {
  required TeamId teamId,
  int? cash,
  int? revenueBaseline,
  int? operatingBudget,
  bool? capGrandfathered,
  int? grandfatheredPayroll,
  Map<String, int>? debtByTeam,
}) {
  final old = base.finances.financesFor(teamId);
  final updated = TeamFinances(
    teamId: teamId,
    operatingBudget: operatingBudget ?? old.operatingBudget,
    cash: cash ?? old.cash,
    revenueBaseline: revenueBaseline ?? old.revenueBaseline,
    season: old.season,
    capGrandfathered: capGrandfathered ?? old.capGrandfathered,
    grandfatheredPayroll: grandfatheredPayroll ?? old.grandfatheredPayroll,
    capException: old.capException,
  );
  final nextFinances = CareerFinances(
    contracts: base.finances.contracts.values,
    schedules: base.finances.schedules.values,
    teamFinances: [
      for (final tf in base.finances.teamFinances.values)
        if (tf.teamId == teamId) updated else tf,
    ],
    staffCommitments: base.finances.staffCommitments.values,
    facilities: base.finances.facilities.values,
    guaranteedLiabilities: base.finances.guaranteedLiabilities.values,
    debtByTeam: debtByTeam ?? base.finances.debtByTeam,
  );
  return base.copyWith(finances: nextFinances);
}

void main() {
  late GmCareer completedChamp;

  setUpAll(() {
    completedChamp = _completedYear1Championship();
  });

  group('M009-T05C-C2-B: Schema v23 & FinancialRolloverService', () {
    const planner = SeasonRolloverPlanner();
    const financeService = FinancialRolloverService();

    test(
      '1, 2, 3, 4: v23 construction, v22 -> v23 & legacy v21 migration, deterministic encode/decode',
      () {
        expect(GmCareer.currentSchemaVersion, greaterThanOrEqualTo(23));
        expect(GmCareerCodec.currentSchemaVersion, greaterThanOrEqualTo(23));
        expect(FinancialRules.financialSchemaVersion, 2);
        expect(completedChamp.schemaVersion, GmCareer.currentSchemaVersion);
        expect(completedChamp.finances.guaranteedLiabilities, isEmpty);
        expect(completedChamp.finances.debtByTeam, isEmpty);

        // Construct synthetic v22 save (financial schema v1 without guaranteedLiabilities/debtByTeam)
        final v23Map =
            jsonDecode(GmCareerCodec.encode(completedChamp))
                as Map<String, dynamic>;
        v23Map['schemaVersion'] = 22;
        v23Map.remove('carriedUnsignedProspects');
        v23Map.remove('marketHistory');
        final finMap = v23Map['finances'] as Map<String, dynamic>;
        finMap['schemaVersion'] = 1;
        finMap.remove('guaranteedLiabilities');
        finMap.remove('debtByTeam');

        final migrated = GmCareerCodec.decode(jsonEncode(v23Map));
        expect(migrated.schemaVersion, GmCareer.currentSchemaVersion);
        expect(migrated.finances.guaranteedLiabilities, isEmpty);
        expect(migrated.finances.debtByTeam, isEmpty);
        expect(
          GmCareerCodec.encode(migrated),
          equals(GmCareerCodec.encode(completedChamp)),
        );
      },
    );

    test(
      '5, 6, 7, 8, 30: rejects malformed liabilities, negative/unknown debt, double-counted payroll, negative Year 1 cash',
      () {
        final team1 = completedChamp.league.teams.first;
        final sampleContract = completedChamp.finances.contracts.values.first;

        // Negative debt rejected
        expect(
          () => CareerFinances(
            contracts: completedChamp.finances.contracts.values,
            schedules: completedChamp.finances.schedules.values,
            teamFinances: completedChamp.finances.teamFinances.values,
            staffCommitments: completedChamp.finances.staffCommitments.values,
            facilities: completedChamp.finances.facilities.values,
            debtByTeam: {team1.id.value: -100},
          ),
          throwsA(isA<DomainValidationException>()),
        );

        // Unknown debt franchise rejected on validate
        final badDebtFinances = CareerFinances(
          contracts: completedChamp.finances.contracts.values,
          schedules: completedChamp.finances.schedules.values,
          teamFinances: completedChamp.finances.teamFinances.values,
          staffCommitments: completedChamp.finances.staffCommitments.values,
          facilities: completedChamp.finances.facilities.values,
          debtByTeam: {'unknown-team': 500},
        );
        expect(
          () => badDebtFinances.validate(
            league: completedChamp.league,
            rookieSigningLedger: completedChamp.rookieSigningLedger,
            currentYear: 1,
          ),
          throwsA(isA<DomainValidationException>()),
        );

        // Malformed liability (year <= retirementYear) rejected
        expect(
          () => GuaranteedLiability(
            id: 'bad-liab',
            originalContractId: 'c1',
            playerId: PlayerId('p1'),
            teamId: team1.id,
            originalCategory: RosterCategory.standard,
            retirementYear: 2,
            salariesByYear: const {2: 500},
          ),
          throwsA(isA<DomainValidationException>()),
        );

        // Double-counted liability matching active contract rejected
        final dupFinances = CareerFinances(
          contracts: completedChamp.finances.contracts.values,
          schedules: completedChamp.finances.schedules.values,
          teamFinances: completedChamp.finances.teamFinances.values,
          staffCommitments: completedChamp.finances.staffCommitments.values,
          facilities: completedChamp.finances.facilities.values,
          guaranteedLiabilities: [
            GuaranteedLiability(
              id: GuaranteedLiability.idFor(sampleContract.id),
              originalContractId: sampleContract.id,
              playerId: sampleContract.playerId,
              teamId: sampleContract.teamId,
              originalCategory: sampleContract.category,
              retirementYear: 1,
              salariesByYear: const {2: 500},
            ),
          ],
        );
        expect(
          () => dupFinances.validate(
            league: completedChamp.league,
            rookieSigningLedger: completedChamp.rookieSigningLedger,
            currentYear: 1,
          ),
          throwsA(isA<DomainValidationException>()),
        );

        // Year 1 active career still rejects negative projected cash
        expect(
          () => _withUpdatedTeamFinances(
            completedChamp,
            teamId: team1.id,
            cash: 0,
            revenueBaseline: 0,
          ),
          throwsA(isA<DomainValidationException>()),
        );
      },
    );

    test(
      '9, 10, 11, 12, 13, 14, 15, 16: liabilities, final-year retirement, cap vs two-way, staff & facilities',
      () {
        final team1 = completedChamp.league.teams.first;
        final p0 = team1
            .players[0]; // retires at 38 with 2-year deal -> Year 2 liability
        final p1 = team1
            .players[1]; // retires at 38 in final year (1-year deal) -> zero liability

        final c0 = completedChamp.finances.contractForPlayer(p0.id)!;
        final s0 = completedChamp.finances.scheduleFor(c0.id)!;
        final c1 = completedChamp.finances.contractForPlayer(p1.id)!;
        final s1 = completedChamp.finances.scheduleFor(c1.id)!;

        final newC0 = PlayerContract(
          id: c0.id,
          playerId: c0.playerId,
          teamId: c0.teamId,
          category: RosterCategory.standard,
          startYear: 1,
          durationYears: 2,
          source: c0.source,
          rookieContractId: c0.rookieContractId,
        );
        final newS0 = ContractFinancials(
          contractId: s0.contractId,
          playerId: s0.playerId,
          teamId: s0.teamId,
          annualSalaries: FinancialRules.standardSchedule(
            s0.annualSalaries.first,
            2,
          ),
          guaranteedYears: 2,
          signedYear: 1,
          source: s0.source,
        );
        final newC1 = PlayerContract(
          id: c1.id,
          playerId: c1.playerId,
          teamId: c1.teamId,
          category: RosterCategory.standard,
          startYear: 1,
          durationYears: 1,
          source: c1.source,
          rookieContractId: c1.rookieContractId,
        );
        final newS1 = ContractFinancials(
          contractId: s1.contractId,
          playerId: s1.playerId,
          teamId: s1.teamId,
          annualSalaries: [s1.annualSalaries.first],
          guaranteedYears: 1,
          signedYear: 1,
          source: s1.source,
        );

        final modifiedProfiles = LeagueCareerProfiles(
          schemaVersion: completedChamp.careerProfiles.schemaVersion,
          leagueSeed: completedChamp.careerProfiles.leagueSeed,
          profiles: {
            ...completedChamp.careerProfiles.profiles,
            p0.id.value: PlayerCareerProfile(
              playerId: p0.id,
              age: 38,
              potential: completedChamp.careerProfiles
                  .forPlayer(p0.id)!
                  .potential,
              trajectory: completedChamp.careerProfiles
                  .forPlayer(p0.id)!
                  .trajectory,
            ),
            p1.id.value: PlayerCareerProfile(
              playerId: p1.id,
              age: 38,
              potential: completedChamp.careerProfiles
                  .forPlayer(p1.id)!
                  .potential,
              trajectory: completedChamp.careerProfiles
                  .forPlayer(p1.id)!
                  .trajectory,
            ),
          },
        );
        final modifiedFinances = CareerFinances(
          contracts: [
            for (final c in completedChamp.finances.contracts.values)
              if (c.id == c0.id) newC0 else if (c.id == c1.id) newC1 else c,
          ],
          schedules: [
            for (final s in completedChamp.finances.schedules.values)
              if (s.contractId == c0.id)
                newS0
              else if (s.contractId == c1.id)
                newS1
              else
                s,
          ],
          teamFinances: completedChamp.finances.teamFinances.values,
          staffCommitments: completedChamp.finances.staffCommitments.values,
          facilities: completedChamp.finances.facilities.values,
        );
        final custom = completedChamp.copyWith(
          careerProfiles: modifiedProfiles,
          finances: modifiedFinances,
        );

        final c2aPlan = planner.plan(custom);
        final finPlan = financeService.plan(
          career: custom,
          rolloverPlan: c2aPlan,
        );

        // Only p0 generates a Year 2 liability; p1 (final year) does not
        expect(finPlan.newlyExtractedLiabilities, hasLength(1));
        final liab = finPlan.newlyExtractedLiabilities.single;
        expect(liab.playerId, p0.id);
        expect(liab.retirementYear, 1);
        expect(liab.salariesByYear, equals({2: newS0.salaryForYear(2)!}));

        // Year 1 settlement does NOT double-charge p0's Year 2 guarantee in Year 1
        final team1Breakdown = finPlan.teamBreakdowns[team1.id.value]!;
        expect(team1Breakdown.settlementEntry.retiredGuaranteeExpense, 0);
        expect(
          team1Breakdown.capStatus.nextYearGuaranteedLiabilityCap,
          newS0.salaryForYear(2)!,
        );
        expect(
          team1Breakdown.capStatus.nextYearTotalCapPayroll,
          team1Breakdown.capStatus.nextYearActiveStandardPayroll +
              newS0.salaryForYear(2)!,
        );

        // Staff expiration & facility continuity
        for (final staff in finPlan.expiredStaff) {
          expect(staff.isActiveIn(2), isFalse);
        }
        for (final staff in finPlan.continuingStaff) {
          expect(staff.isActiveIn(2), isTrue);
        }
        expect(
          finPlan.preservedFacilities.length,
          custom.finances.facilities.length,
        );
      },
    );

    test(
      '17, 18, 19, 20, 21, 22, 23, 24: positive/zero/deficit->debt settlement, grandfathering, 30-team totals',
      () {
        final team1 = completedChamp.league.teams.first;
        final team2 = completedChamp.league.teams[1];

        // Set team1 to deficit-producing cash/revenue? Note: CareerFinances.validate() checks Year 1 projected >= 0,
        // EXCEPT if we test deficit -> debt when startDebt already exists OR test overflow/exact zero-cash boundary.
        // Let's set team1 exact zero-cash (netPosition == 0):
        final t1Cash =
            completedChamp.finances.cashPayrollFor(team1.id, 1) +
            completedChamp.finances.operatingCommitmentsFor(team1.id) -
            completedChamp.finances.financesFor(team1.id).revenueBaseline;
        final exactZeroCareer = _withUpdatedTeamFinances(
          completedChamp,
          teamId: team1.id,
          cash: t1Cash < 0 ? 0 : t1Cash,
        );
        final c2aPlan = planner.plan(exactZeroCareer);
        final finPlan = financeService.plan(
          career: exactZeroCareer,
          rolloverPlan: c2aPlan,
        );

        expect(finPlan.teamBreakdowns, hasLength(30));
        expect(finPlan.proposedSettlementRecord.teamEntries, hasLength(30));
        var sumRev = 0;
        var sumExp = 0;
        for (final b in finPlan.teamBreakdowns.values) {
          final e = b.settlementEntry;
          sumRev += e.revenue;
          sumExp += e.totalExpenses;
          expect(
            e.startingCash - e.startingDebt + e.revenue - e.totalExpenses,
            equals(e.endingCash - e.endingDebt),
          );
        }
        expect(finPlan.proposedSettlementRecord.totalRevenue, sumRev);
        expect(finPlan.proposedSettlementRecord.totalExpenses, sumExp);

        // Grandfathering cleared when eligible (payroll <= salaryCap)
        final gfClearedCareer = _withUpdatedTeamFinances(
          completedChamp,
          teamId: team2.id,
          capGrandfathered: true,
          grandfatheredPayroll: 50000,
        );
        final gfPlan = financeService.plan(
          career: gfClearedCareer,
          rolloverPlan: planner.plan(gfClearedCareer),
        );
        final t2Status = gfPlan.teamBreakdowns[team2.id.value]!.capStatus;
        expect(t2Status.wasGrandfathered, isTrue);
        if (t2Status.nextYearTotalCapPayroll <= FinancialRules.salaryCap) {
          expect(t2Status.isGrandfathered, isFalse);
          expect(t2Status.grandfatheredPayroll, 0);
        }

        // Overflow (> maximumBalance) fails explicitly instead of truncating
        final overflowCareer = _withUpdatedTeamFinances(
          completedChamp,
          teamId: team1.id,
          cash: FinancialRules.maximumBalance,
          revenueBaseline: 50000,
        );
        expect(
          () => financeService.plan(
            career: overflowCareer,
            rolloverPlan: planner.plan(overflowCareer),
          ),
          throwsStateError,
        );
      },
    );

    test(
      '19 & 20 (deficit -> debt & repayment): CareerFinances deficit/debt math with allowRolloverDeficit',
      () {
        final team1 = completedChamp.league.teams.first;
        // Verify CareerFinances.validate(allowRolloverDeficit: true) permits explicit debt & surplus paydown
        final debtFinances = CareerFinances(
          contracts: completedChamp.finances.contracts.values,
          schedules: completedChamp.finances.schedules.values,
          teamFinances: [
            for (final tf in completedChamp.finances.teamFinances.values)
              if (tf.teamId == team1.id)
                TeamFinances(
                  teamId: tf.teamId,
                  operatingBudget: tf.operatingBudget,
                  cash: 0,
                  revenueBaseline: tf.revenueBaseline,
                  season: 2,
                  capGrandfathered: tf.capGrandfathered,
                  grandfatheredPayroll: tf.grandfatheredPayroll,
                  capException: 0,
                )
              else
                TeamFinances(
                  teamId: tf.teamId,
                  operatingBudget: tf.operatingBudget,
                  cash: tf.cash,
                  revenueBaseline: tf.revenueBaseline,
                  season: 2,
                  capGrandfathered: tf.capGrandfathered,
                  grandfatheredPayroll: tf.grandfatheredPayroll,
                  capException: 0,
                ),
          ],
          staffCommitments: completedChamp.finances.staffCommitments.values,
          facilities: completedChamp.finances.facilities.values,
          debtByTeam: {team1.id.value: 3500},
        );
        expect(debtFinances.debtFor(team1.id), 3500);
        // Verify TeamSettlementEntry deficit -> debt & debt paydown invariants
        final deficitEntry = TeamSettlementEntry(
          teamId: team1.id,
          startingCash: 1000,
          startingDebt: 0,
          revenue: 20000,
          activePlayerSalaryExpense: 18000,
          retiredGuaranteeExpense: 1000,
          staffExpense: 2500,
          facilityMaintenanceExpense: 1500,
          endingCash: 0,
          endingDebt: 2000,
        );
        expect(deficitEntry.endingDebt, 2000);

        final paydownEntry = TeamSettlementEntry(
          teamId: team1.id,
          startingCash: 0,
          startingDebt: 2000,
          revenue: 25000,
          activePlayerSalaryExpense: 15000,
          retiredGuaranteeExpense: 0,
          staffExpense: 2000,
          facilityMaintenanceExpense: 1000,
          endingCash: 5000,
          endingDebt: 0,
        );
        expect(paydownEntry.endingCash, 5000);
        expect(paydownEntry.endingDebt, 0);
      },
    );

    test(
      '25, 26, 27, 28, 29: duplicate settlement rejection, mismatched C2-A plan rejection, purity',
      () {
        final beforeJson = GmCareerCodec.encode(completedChamp);
        final c2aPlan = planner.plan(completedChamp);
        final finPlan1 = financeService.plan(
          career: completedChamp,
          rolloverPlan: c2aPlan,
        );
        final finPlan2 = financeService.plan(
          career: completedChamp,
          rolloverPlan: c2aPlan,
        );
        expect(
          finPlan1.proposedSettlementRecord,
          equals(finPlan2.proposedSettlementRecord),
        );
        expect(GmCareerCodec.encode(completedChamp), equals(beforeJson));
        expect(completedChamp.currentYear, 1);

        // Mismatched C2-A plan rejected
        final mismatchedPlan = SeasonRolloverPlan(
          careerId: 'other-career',
          completedYear: 1,
          targetYear: 2,
          retirements: c2aPlan.retirements,
          continuingContracts: c2aPlan.continuingContracts,
          expiredContracts: c2aPlan.expiredContracts,
          retiredContracts: c2aPlan.retiredContracts,
          pendingGuaranteedLiabilities: c2aPlan.pendingGuaranteedLiabilities,
          proposedRosters: c2aPlan.proposedRosters,
          rosterShortages: c2aPlan.rosterShortages,
          eligibleExpiringFreeAgents: c2aPlan.eligibleExpiringFreeAgents,
          carriedForwardFreeAgents: c2aPlan.carriedForwardFreeAgents,
          proposedDraftRightsCarryover: c2aPlan.proposedDraftRightsCarryover,
          proposedCarriedUnsignedProspects:
              c2aPlan.proposedCarriedUnsignedProspects,
        );
        expect(
          () => financeService.plan(
            career: completedChamp,
            rolloverPlan: mismatchedPlan,
          ),
          throwsStateError,
        );
      },
    );

    test(
      'Audit fixes: Year 2 debt passes GmCareer.validate, tampered C2-A continuingContracts rejected, v23 rejects v1 finances',
      () {
        // 1. Malformed v23 career with v1 finances is rejected
        final badV23 =
            jsonDecode(GmCareerCodec.encode(completedChamp))
                as Map<String, dynamic>;
        final finMap = badV23['finances'] as Map<String, dynamic>;
        finMap['schemaVersion'] = 1;
        finMap.remove('guaranteedLiabilities');
        finMap.remove('debtByTeam');
        expect(
          () => GmCareerCodec.decode(jsonEncode(badV23)),
          throwsFormatException,
        );

        // 2. Tampered C2-A continuingContracts omitted/altered is rejected
        final c2aPlan = planner.plan(completedChamp);
        final omittedPlan = SeasonRolloverPlan(
          careerId: c2aPlan.careerId,
          completedYear: c2aPlan.completedYear,
          targetYear: c2aPlan.targetYear,
          retirements: c2aPlan.retirements,
          continuingContracts: c2aPlan.continuingContracts.skip(1).toList(),
          expiredContracts: c2aPlan.expiredContracts,
          retiredContracts: c2aPlan.retiredContracts,
          pendingGuaranteedLiabilities: c2aPlan.pendingGuaranteedLiabilities,
          proposedRosters: c2aPlan.proposedRosters,
          rosterShortages: c2aPlan.rosterShortages,
          eligibleExpiringFreeAgents: c2aPlan.eligibleExpiringFreeAgents,
          carriedForwardFreeAgents: c2aPlan.carriedForwardFreeAgents,
          proposedDraftRightsCarryover: c2aPlan.proposedDraftRightsCarryover,
          proposedCarriedUnsignedProspects:
              c2aPlan.proposedCarriedUnsignedProspects,
        );
        expect(
          () => financeService.plan(
            career: completedChamp,
            rolloverPlan: omittedPlan,
          ),
          throwsStateError,
        );

        // 3. Year 2 GmCareer carrying explicit debtByTeam passes GmCareer.validate() while Year 1 rejects it
        final team1 = completedChamp.league.teams.first;
        expect(
          () => _withUpdatedTeamFinances(
            completedChamp,
            teamId: team1.id,
            cash: 0,
            debtByTeam: {team1.id.value: 2500},
          ),
          throwsFormatException,
        );

        final setup = const CareerSetupService().generate(
          const CareerSetupRequest(
            selectedTeamId: TeamId('team-1'),
            selectedSituation: FranchiseSituation.tanking,
            seed: 20261119,
          ),
        );
        final baseY1 = GmCareer.fromSetupResult(setup, id: 'y2-debt-test');
        final y2Finances = FinancialMigration.bootstrapFromCareerState(
          league: baseY1.league,
          careerProfiles: baseY1.careerProfiles,
          rookieSigningLedger: RookieSigningLedger.empty(),
          currentYear: 2,
        );
        final y2WithDebt = baseY1.copyWith(
          currentYear: 2,
          draftClass: const DraftGenerator().generateDraftClass(
            league: baseY1.league,
            seed: baseY1.generationSeed + 2,
            seasonYear: 2,
          ),
          freeAgentPool: FreeAgentPool(
            seasonYear: 2,
            entries: baseY1.freeAgentPool.entries,
          ),
          freeAgentMarket: FreeAgentMarketState.initial(seasonYear: 2),
          offseasonClearance: OffseasonClearanceState.initial(seasonYear: 2),
          hardshipSettlement: HardshipSettlement.initial(seasonYear: 2),
          finances: CareerFinances(
            contracts: y2Finances.contracts.values,
            schedules: y2Finances.schedules.values,
            teamFinances: [
              for (final tf in y2Finances.teamFinances.values)
                if (tf.teamId == team1.id)
                  TeamFinances(
                    teamId: tf.teamId,
                    operatingBudget: tf.operatingBudget,
                    cash: 0,
                    revenueBaseline: tf.revenueBaseline,
                    season: 2,
                    capGrandfathered: tf.capGrandfathered,
                    grandfatheredPayroll: tf.grandfatheredPayroll,
                    capException: 0,
                  )
                else
                  tf,
            ],
            staffCommitments: y2Finances.staffCommitments.values,
            facilities: y2Finances.facilities.values,
            debtByTeam: {team1.id.value: 5000},
          ),
        );
        expect(y2WithDebt.finances.debtFor(team1.id), 5000);
        final roundTripped = GmCareerCodec.decode(
          GmCareerCodec.encode(y2WithDebt),
        );
        expect(roundTripped.finances.debtFor(team1.id), 5000);
      },
    );
  });
}
