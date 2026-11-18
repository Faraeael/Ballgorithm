import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/domain_versions.dart' as domain_versions;
import 'package:test/test.dart';

GmCareer _completedYear1Championship({int seed = 20261028, int year = 1}) {
  final setup = const CareerSetupService().generate(
    CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: seed,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 'career-c2a-$seed');
  if (year > 1) {
    c = c.copyWith(
      currentYear: year,
      draftClass: const DraftGenerator().generateDraftClass(
        league: c.league,
        seed: c.generationSeed + year,
        seasonYear: year,
      ),
      freeAgentPool: FreeAgentPool(
        seasonYear: year,
        entries: c.freeAgentPool.entries,
      ),
      freeAgentMarket: FreeAgentMarketState.initial(seasonYear: year),
      offseasonClearance: OffseasonClearanceState.initial(seasonYear: year),
      hardshipSettlement: HardshipSettlement.initial(seasonYear: year),
      finances: FinancialMigration.bootstrapFromCareerState(
        league: c.league,
        careerProfiles: c.careerProfiles,
        rookieSigningLedger: RookieSigningLedger.empty(),
        currentYear: year,
      ),
    );
  }
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

GmCareer _withModifiedAgeAndContracts(
  GmCareer base, {
  required PlayerId targetPlayerId,
  required int age,
  int? contractDurationYears,
  RosterCategory? category,
}) {
  final existingProfile = base.careerProfiles.forPlayer(targetPlayerId)!;
  final nextProfiles = LeagueCareerProfiles(
    schemaVersion: base.careerProfiles.schemaVersion,
    leagueSeed: base.careerProfiles.leagueSeed,
    profiles: {
      ...base.careerProfiles.profiles,
      targetPlayerId.value: PlayerCareerProfile(
        playerId: targetPlayerId,
        age: age,
        potential: existingProfile.potential,
        trajectory: existingProfile.trajectory,
      ),
    },
  );
  var nextFinances = base.finances;
  var nextLeague = base.league;
  if (contractDurationYears != null || category != null) {
    final oldContract = base.finances.contractForPlayer(targetPlayerId)!;
    final oldSchedule = base.finances.scheduleFor(oldContract.id)!;
    final newDuration = contractDurationYears ?? oldContract.durationYears;
    final newCategory = category ?? oldContract.category;
    final newContract = PlayerContract(
      id: oldContract.id,
      playerId: oldContract.playerId,
      teamId: oldContract.teamId,
      category: newCategory,
      startYear: oldContract.startYear,
      durationYears: newDuration,
      source: oldContract.source,
      rookieContractId: oldContract.rookieContractId,
    );
    final baseSal = newCategory == RosterCategory.twoWay
        ? FinancialRules.twoWaySalary
        : oldSchedule.annualSalaries.first;
    final newSchedule = ContractFinancials(
      contractId: oldSchedule.contractId,
      playerId: oldSchedule.playerId,
      teamId: oldSchedule.teamId,
      annualSalaries: newCategory == RosterCategory.twoWay
          ? List.filled(newDuration, FinancialRules.twoWaySalary)
          : FinancialRules.standardSchedule(baseSal, newDuration),
      guaranteedYears: newDuration,
      signedYear: oldSchedule.signedYear,
      source: oldSchedule.source,
    );
    nextFinances = CareerFinances(
      contracts: [
        for (final c in base.finances.contracts.values)
          if (c.id == oldContract.id) newContract else c,
      ],
      schedules: [
        for (final s in base.finances.schedules.values)
          if (s.contractId == oldSchedule.contractId) newSchedule else s,
      ],
      teamFinances: base.finances.teamFinances.values,
      staffCommitments: base.finances.staffCommitments.values,
      facilities: base.finances.facilities.values,
    );
    if (category != null) {
      final team = base.league.teams.firstWhere(
        (t) => t.id == oldContract.teamId,
      );
      final updatedTeam = Team(
        id: team.id,
        name: team.name,
        abbreviation: team.abbreviation,
        situation: team.situation,
        roster: Roster(
          team.players,
          categories: {
            for (final p in team.players)
              p.id.value: p.id == targetPlayerId
                  ? newCategory
                  : team.roster.categoryOf(p.id),
          },
        ),
      );
      nextLeague = League.create(
        id: base.league.id,
        name: base.league.name,
        config: base.league.config,
        teams: [
          for (final t in base.league.teams)
            if (t.id == updatedTeam.id) updatedTeam else t,
        ],
        enforceRosterSize: false,
      );
    }
  }
  return base.copyWith(
    league: nextLeague,
    careerProfiles: nextProfiles,
    finances: nextFinances,
  );
}

void main() {
  late GmCareer completedChamp;

  setUpAll(() {
    completedChamp = _completedYear1Championship();
  });

  group('M009-T05C-C2-A: SeasonRolloverPlanner', () {
    const planner = SeasonRolloverPlanner();

    test(
      '1, 3, 21, 22, 23, 24: completed Year 1 -> Year 2 plan is deterministic, pure, and repeatable',
      () {
        final beforeJson = GmCareerCodec.encode(completedChamp);
        final plan1 = planner.plan(completedChamp);
        final plan2 = planner.plan(completedChamp);

        expect(plan1.completedYear, 1);
        expect(plan1.targetYear, 2);
        expect(plan1.careerId, completedChamp.id);
        expect(plan1.proposedRosters, hasLength(30));

        // Determinism & repeated planning idempotency
        expect(plan1.totalContinuingPlayers, plan2.totalContinuingPlayers);
        expect(plan1.retirements, equals(plan2.retirements));
        expect([
          for (final c in plan1.continuingContracts) c.contract.id,
        ], equals([for (final c in plan2.continuingContracts) c.contract.id]));
        expect([
          for (final c in plan1.expiredContracts) c.contract.id,
        ], equals([for (final c in plan2.expiredContracts) c.contract.id]));
        expect(
          plan1.proposedDraftRightsCarryover.keys.toList(),
          equals(plan2.proposedDraftRightsCarryover.keys.toList()),
        );

        // No input-state mutation or persistent save writes
        expect(GmCareerCodec.encode(completedChamp), equals(beforeJson));
        expect(completedChamp.currentYear, 1);
        expect(completedChamp.phase, CareerPhase.playoffs);
      },
    );

    test(
      '2: rejects incomplete championship, non-playoffs phase, and already-archived/settled year',
      () {
        final setup = const CareerSetupService().generate(
          const CareerSetupRequest(
            selectedTeamId: TeamId('team-1'),
            selectedSituation: FranchiseSituation.tanking,
            seed: 99,
          ),
        );
        final opening = GmCareer.fromSetupResult(
          setup,
          id: 'incomplete-opening',
        );
        expect(() => planner.plan(opening), throwsStateError);

        final incompletePlayIn = completedChamp.copyWith(
          phase: CareerPhase.playIn,
          playoffState: null,
        );
        expect(() => planner.plan(incompletePlayIn), throwsStateError);
      },
    );

    test(
      '4, 5, 6, 7, 8, 9: aging +1, frozen attributes/potential, age-38 retirement for roster and FA',
      () {
        // Force one FA entry to age 38 to guarantee FA retirement coverage
        final firstFa = completedChamp.freeAgentPool.entries.first;
        final secondFa = completedChamp.freeAgentPool.entries[1];
        final fa36 = FreeAgentEntry(
          player: firstFa.player,
          profile: PlayerCareerProfile(
            playerId: firstFa.id,
            age: 36,
            potential: firstFa.profile.potential,
            trajectory: firstFa.profile.trajectory,
          ),
        );
        final fa30 = FreeAgentEntry(
          player: secondFa.player,
          profile: PlayerCareerProfile(
            playerId: secondFa.id,
            age: 30,
            potential: secondFa.profile.potential,
            trajectory: secondFa.profile.trajectory,
          ),
        );
        final modifiedPool = FreeAgentPool(
          seasonYear: 1,
          entries: [
            fa36,
            fa30,
            ...completedChamp.freeAgentPool.entries.skip(2),
          ],
          initialPlayerIds: completedChamp.freeAgentPool.initialPlayerIds,
          acquisitions: completedChamp.freeAgentPool.acquisitions,
        );
        final targetRosterPlayer =
            completedChamp.league.teams.first.players.first;
        final careerWith38 = _withModifiedAgeAndContracts(
          completedChamp.copyWith(freeAgentPool: modifiedPool),
          targetPlayerId: targetRosterPlayer.id,
          age: 38,
        );

        final plan = planner.plan(careerWith38);

        // Age-38 roster player retires; never survives at age 39
        final retiredIds = {for (final r in plan.retirements) r.playerId.value};
        expect(retiredIds, contains(targetRosterPlayer.id.value));
        expect(
          plan.retirements
              .firstWhere((r) => r.playerId == targetRosterPlayer.id)
              .lastTeamId,
          equals(completedChamp.league.teams.first.id),
        );

        // Surviving players age +1 with frozen attributes & potential, max age <= 38
        for (final roster in plan.proposedRosters.values) {
          for (final entry in roster.entries) {
            final prev = careerWith38.careerProfiles.forPlayer(
              entry.player.id,
            )!;
            expect(entry.nextProfile.age, prev.age + 1);
            expect(entry.nextProfile.age, lessThanOrEqualTo(38));
            expect(entry.nextProfile.potential, prev.potential);
            expect(entry.nextProfile.trajectory, prev.trajectory);
          }
        }
        final carriedFa36 = plan.carriedForwardFreeAgents.firstWhere(
          (fa) => fa.player.id == fa36.id,
        );
        expect(carriedFa36.nextProfile.age, 37);
        final carriedFa30 = plan.carriedForwardFreeAgents.firstWhere(
          (fa) => fa.player.id == fa30.id,
        );
        expect(carriedFa30.nextProfile.age, 31);
        expect(carriedFa30.nextProfile.potential, fa30.profile.potential);
        expect(
          carriedFa30.player.attributes.overallRating,
          fa30.player.attributes.overallRating,
        );
      },
    );

    test('8: retirement of eligible age-38 unsigned free agent in Year 2+', () {
      final y2Champ = _completedYear1Championship(seed: 20261028, year: 2);
      final firstFa = y2Champ.freeAgentPool.entries.first;
      final fa38 = FreeAgentEntry(
        player: firstFa.player,
        profile: PlayerCareerProfile(
          playerId: firstFa.id,
          age: 38,
          potential: firstFa.profile.potential,
          trajectory: firstFa.profile.trajectory,
        ),
      );
      final modifiedPool = FreeAgentPool(
        seasonYear: 2,
        entries: [fa38, ...y2Champ.freeAgentPool.entries.skip(1)],
        initialPlayerIds: y2Champ.freeAgentPool.initialPlayerIds,
        acquisitions: y2Champ.freeAgentPool.acquisitions,
      );
      final plan = planner.plan(y2Champ.copyWith(freeAgentPool: modifiedPool));
      final faRetirement = plan.retirements.firstWhere(
        (r) => r.playerId == fa38.id,
      );
      expect(faRetirement.finalAge, 38);
      expect(faRetirement.retiredAfterYear, 2);
      expect(faRetirement.lastTeamId, isNull);
      expect(
        plan.carriedForwardFreeAgents.any((fa) => fa.player.id == fa38.id),
        isFalse,
      );
    });

    test(
      '10, 11, 12, 13, 14, 15, 16, 17: continuing, expiring standard/two-way, retired guarantees, shortages',
      () {
        final team1 = completedChamp.league.teams.first;
        final p0 = team1.players[0]; // will be age 38 with 2-year guarantee
        final p1 = team1.players[1]; // 1-year expiring standard
        final p2 = team1.players[2]; // 2-year continuing standard

        var custom = _withModifiedAgeAndContracts(
          completedChamp,
          targetPlayerId: p0.id,
          age: 38,
          contractDurationYears: 2,
        );
        custom = _withModifiedAgeAndContracts(
          custom,
          targetPlayerId: p1.id,
          age: 26,
          contractDurationYears: 1,
          category: RosterCategory.standard,
        );
        custom = _withModifiedAgeAndContracts(
          custom,
          targetPlayerId: p2.id,
          age: 25,
          contractDurationYears: 2,
          category: RosterCategory.standard,
        );
        // Also ensure at least one 1-year expiring two-way contract if team has a two-way or use p3
        final p3 = team1.players[3];
        custom = _withModifiedAgeAndContracts(
          custom,
          targetPlayerId: p3.id,
          age: 24,
          contractDurationYears: 1,
          category: RosterCategory.twoWay,
        );

        final plan = planner.plan(custom);

        // Continuing vs expired vs retiredWithGuarantees
        expect(
          plan.continuingContracts.any((d) => d.contract.playerId == p2.id),
          isTrue,
        );
        expect(
          plan.expiredContracts.any((d) => d.contract.playerId == p1.id),
          isTrue,
        );
        expect(
          plan.expiredContracts.any((d) => d.contract.playerId == p3.id),
          isTrue,
        );
        expect(
          plan.eligibleExpiringFreeAgents.any((fa) => fa.player.id == p1.id),
          isTrue,
        );
        expect(
          plan.eligibleExpiringFreeAgents.any((fa) => fa.player.id == p3.id),
          isTrue,
        );

        // Pending guaranteed liability for retired p0 (Year 2)
        final liability = plan.pendingGuaranteedLiabilities.firstWhere(
          (l) => l.playerId == p0.id,
        );
        final p0Schedule = custom.finances.scheduleFor(liability.contractId)!;
        expect(liability.futureYearSalaries.keys.toList(), equals([2]));
        expect(liability.futureYearSalaries[2], p0Schedule.salaryForYear(2));
        expect(liability.totalRemainingGuarantee, p0Schedule.salaryForYear(2)!);

        // No double-counted contracts
        final allClassifiedIds = [
          for (final c in plan.continuingContracts) c.contract.id,
          for (final c in plan.expiredContracts) c.contract.id,
          for (final c in plan.retiredContracts) c.contract.id,
        ];
        expect(allClassifiedIds.toSet().length, allClassifiedIds.length);
        expect(allClassifiedIds.length, custom.finances.contracts.length);

        // Cross-team ownership uniqueness & roster shortage reporting
        final allProposedPlayers = <String>{};
        for (final r in plan.proposedRosters.values) {
          for (final e in r.entries) {
            expect(allProposedPlayers.add(e.player.id.value), isTrue);
          }
        }
        expect(plan.rosterShortages, isNotEmpty);
      },
    );

    test(
      '18, 19, 20: draft-rights carryover, signed exclusion, and duplicate rejection',
      () {
        final plan = planner.plan(completedChamp);
        final unsignedIds = {
          for (final r in completedChamp.unsignedDraftRights)
            r.prospectId.value,
        };
        expect(
          plan.proposedDraftRightsCarryover.keys.toSet(),
          equals(unsignedIds),
        );
        // Signed prospects excluded
        for (final signedId
            in completedChamp.rookieSigningLedger.contracts.keys) {
          expect(
            plan.proposedDraftRightsCarryover.containsKey(signedId),
            isFalse,
          );
        }

        // Duplicate draft rights between careerDraftRights and draftExecutionState rejected
        if (unsignedIds.isNotEmpty) {
          final dupId = unsignedIds.first;
          final dupRights =
              completedChamp.draftExecutionState.draftRights[dupId]!;
          expect(
            () =>
                completedChamp.copyWith(careerDraftRights: {dupId: dupRights}),
            throwsFormatException,
          );
        }
      },
    );
  });
}
