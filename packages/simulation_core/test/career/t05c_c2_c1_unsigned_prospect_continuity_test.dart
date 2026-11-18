import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/domain_versions.dart' as domain_versions;
import 'package:test/test.dart';

GmCareer _buildCompletedChampionshipCareer({int seed = 20261028}) {
  final setup = const CareerSetupService().generate(
    CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: seed,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 'career-c2c1-$seed');
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
    final fp = GameFingerprint.of(input);
    final rawPayload = jsonEncode(GameFingerprint.canonicalPayload(input));
    final templateJson = rawPayload.replaceFirst(leagueJson, markerJson);
    final lines = <SeasonPlayerGameLine>[];
    void addLines(Team team, int totalPts) {
      final players = team.players.take(8).toList();
      final base = totalPts ~/ players.length;
      final rem = totalPts % players.length;
      for (var i = 0; i < players.length; i++) {
        final p = players[i];
        final pts = base + (i < rem ? 1 : 0);
        final fgm = pts ~/ 2;
        final ftm = pts % 2;
        lines.add(
          SeasonPlayerGameLine(
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
          ),
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
        playerLines: {for (final l in lines) l.playerId: l},
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

GmCareer _withYear2CarriedProspect({
  required GmCareer completedY1,
  required DraftRights rights,
  required CarriedUnsignedProspect prospect,
  Map<String, GuaranteedLiability>? liabilities,
  Map<String, int>? debtByTeam,
}) {
  final cleanLeague = completedY1.league;
  final bootstrappedFinances = FinancialMigration.bootstrapFromCareerState(
    league: cleanLeague,
    careerProfiles: completedY1.careerProfiles,
    rookieSigningLedger: RookieSigningLedger.empty(),
    currentYear: 2,
  );
  final nextFinances = CareerFinances(
    contracts: bootstrappedFinances.contracts.values,
    schedules: bootstrappedFinances.schedules.values,
    teamFinances: [
      for (final tf in bootstrappedFinances.teamFinances.values)
        if ((debtByTeam?[tf.teamId.value] ?? 0) > 0)
          TeamFinances(
            teamId: tf.teamId,
            operatingBudget: tf.operatingBudget,
            cash: 0,
            revenueBaseline: tf.revenueBaseline,
            season: tf.season,
            capGrandfathered: tf.capGrandfathered,
            grandfatheredPayroll: tf.grandfatheredPayroll,
            capException: tf.capException,
          )
        else
          tf,
    ],
    staffCommitments: bootstrappedFinances.staffCommitments.values,
    facilities: bootstrappedFinances.facilities.values,
    guaranteedLiabilities: liabilities?.values ?? const [],
    debtByTeam: debtByTeam ?? const {},
  );
  final archive = SeasonArchive.fromCareer(completedY1);
  final historyRecord = archive.toHistoryRecord(
    sha256.convert(utf8.encode(jsonEncode(archive.toJson()))).toString(),
  );

  return completedY1.copyWith(
    currentYear: 2,
    phase: CareerPhase.openingOffseason,
    league: cleanLeague,
    draftClass: const DraftGenerator().generateDraftClass(
      league: cleanLeague,
      seed: completedY1.generationSeed + 2,
      seasonYear: 2,
    ),
    draftExecutionState: DraftExecutionState.initial(),
    rookieSigningLedger: RookieSigningLedger.empty(),
    aiRookieSigning: AiRookieSigningState.empty(),
    freeAgentPool: FreeAgentPool(
      seasonYear: 2,
      entries: completedY1.freeAgentPool.entries,
    ),
    freeAgentOffers: FreeAgentOfferLedger.empty(),
    freeAgentMarket: FreeAgentMarketState.initial(seasonYear: 2),
    offseasonClearance: OffseasonClearanceState.initial(seasonYear: 2),
    hardshipSettlement: HardshipSettlement.initial(seasonYear: 2),
    finances: nextFinances,
    regularSeasonState: null,
    playInState: null,
    playoffState: null,
    seasonHistory: [historyRecord],
    seasonSettlements: [
      SeasonSettlementRecord(
        seasonYear: 1,
        settledTeamIds: [for (final t in cleanLeague.teams) t.id]
          ..sort((a, b) => a.value.compareTo(b.value)),
        totalRevenue: 1000000,
        totalExpenses: 900000,
      ),
    ],
    careerDraftRights: {rights.prospectId.value: rights},
    carriedUnsignedProspects: {prospect.playerId.value: prospect},
  );
}

void main() {
  group('M009-T05C-C2-C1: Unsigned Draft Prospect Continuity', () {
    late GmCareer completedChamp;

    setUpAll(() {
      completedChamp = _buildCompletedChampionshipCareer();
    });

    test(
      '1, 2, 3, 4: v24 construction, lossless v23->v24 migration, legacy failure on unreconstructible rights, deterministic codec',
      () {
        expect(GmCareer.currentSchemaVersion, 24);
        expect(GmCareerCodec.currentSchemaVersion, 24);
        expect(completedChamp.carriedUnsignedProspects, isEmpty);

        // Lossless v23 -> v24 migration when careerDraftRights is empty
        final v23Map =
            jsonDecode(GmCareerCodec.encode(completedChamp))
                as Map<String, dynamic>;
        v23Map['schemaVersion'] = 23;
        v23Map.remove('carriedUnsignedProspects');
        final migratedFromV23 = GmCareerCodec.decode(jsonEncode(v23Map));
        expect(migratedFromV23.schemaVersion, 24);
        expect(migratedFromV23.carriedUnsignedProspects, isEmpty);
        expect(
          GmCareerCodec.encode(migratedFromV23),
          equals(GmCareerCodec.encode(completedChamp)),
        );

        // < v24 JSON with carriedUnsignedProspects field rejected
        final pollutedV23 =
            jsonDecode(GmCareerCodec.encode(completedChamp))
                as Map<String, dynamic>;
        pollutedV23['schemaVersion'] = 23;
        expect(
          () => GmCareerCodec.decode(jsonEncode(pollutedV23)),
          throwsFormatException,
        );

        // Legacy v23 with non-empty careerDraftRights and no matching draftClass fails explicitly
        final badV23 = Map<String, dynamic>.from(v23Map);
        badV23['careerDraftRights'] = {
          'orphan-prospect-y0': {
            'prospectId': 'orphan-prospect-y0',
            'owningTeamId': 'team-1',
            'overallPick': 55,
            'seasonYear': 1,
          },
        };
        expect(
          () => GmCareerCodec.decode(jsonEncode(badV23)),
          throwsFormatException,
        );
      },
    );

    test(
      '5, 6, 7, 8, 9, 10, 11, 12, 13, 27, 28, 29, 30: Year 1->2 handoff, Year 2->3 carryover, +1 age >22, frozen attributes/potential, purity, determinism',
      () {
        const planner = SeasonRolloverPlanner();
        final beforeJson = GmCareerCodec.encode(completedChamp);

        final plan1 = planner.plan(completedChamp);
        final plan2 = planner.plan(completedChamp);
        expect(GmCareerCodec.encode(completedChamp), equals(beforeJson));
        expect(completedChamp.currentYear, 1);

        final unsignedRights = completedChamp.unsignedDraftRights.first;
        final pid = unsignedRights.prospectId.value;
        final originalProspect = completedChamp.draftClass.byId(
          unsignedRights.prospectId,
        )!;

        final carriedY2 = plan1.proposedCarriedUnsignedProspects[pid]!;
        expect(carriedY2.playerId, originalProspect.id);
        expect(carriedY2.firstName, originalProspect.firstName);
        expect(carriedY2.lastName, originalProspect.lastName);
        expect(carriedY2.position, originalProspect.position);
        expect(
          carriedY2.attributes.overallRating,
          originalProspect.overallRating,
        );
        expect(carriedY2.potential, originalProspect.potential);
        expect(carriedY2.trajectory, originalProspect.trajectory);
        expect(carriedY2.draftSeasonYear, 1);
        expect(carriedY2.overallPick, unsignedRights.overallPick);
        expect(carriedY2.age, originalProspect.age + 1);
        expect(
          plan1.proposedDraftRightsCarryover[pid]!.owningTeamId,
          unsignedRights.owningTeamId,
        );
        expect(
          plan2.proposedCarriedUnsignedProspects[pid]!.toJson(),
          equals(carriedY2.toJson()),
        );

        // Age to 23+ (exceeding RookieProspect.maxAge 22) and carry Year 2 -> Year 3
        final agedOver22 = carriedY2.withAge(23);
        expect(agedOver22.age, 23);

        final y2Career = _withYear2CarriedProspect(
          completedY1: completedChamp,
          rights: unsignedRights,
          prospect: agedOver22,
        );
        final y2Encoded = GmCareerCodec.encode(y2Career);
        final y2Decoded = GmCareerCodec.decode(y2Encoded);
        expect(GmCareerCodec.encode(y2Decoded), equals(y2Encoded));
        expect(y2Decoded.carriedUnsignedProspects[pid]!.age, 23);

        final aged24 = agedOver22.withAge(24);
        expect(aged24.age, 24);
        expect(aged24.attributes.overallRating, originalProspect.overallRating);
        expect(aged24.potential, originalProspect.potential);
        expect(aged24.draftSeasonYear, 1);
        expect(aged24.overallPick, unsignedRights.overallPick);
      },
    );

    test(
      '14, 15: carried unsigned prospect retires at age 38 with no age-39 survivor',
      () {
        final sampleProspect = completedChamp.draftClass.prospects.first;
        const age38Id = PlayerId('carried-y0-age38');
        const age38Rights = DraftRights(
          prospectId: age38Id,
          owningTeamId: TeamId('team-1'),
          overallPick: 42,
          seasonYear: 1,
        );
        final age38Carried = CarriedUnsignedProspect(
          playerId: age38Id,
          firstName: sampleProspect.firstName,
          lastName: sampleProspect.lastName,
          position: sampleProspect.position,
          attributes: sampleProspect.attributes,
          age: 38,
          potential: sampleProspect.potential,
          trajectory: sampleProspect.trajectory,
          draftSeasonYear: 1,
          overallPick: 42,
          projectedRank: sampleProspect.projectedRank,
          estimatedPotentialGrade: sampleProspect.estimatedPotentialGrade,
          estimatedPotentialRange: sampleProspect.estimatedPotentialRange,
        );

        expect(() => age38Carried.withAge(39), throwsFormatException);

        final careerWithAge38Carried = completedChamp.copyWith(
          careerDraftRights: {age38Id.value: age38Rights},
          carriedUnsignedProspects: {age38Id.value: age38Carried},
        );

        const planner = SeasonRolloverPlanner();
        final plan = planner.plan(careerWithAge38Carried);
        expect(
          plan.retirements.any(
            (r) => r.playerId == age38Id && r.finalAge == 38,
          ),
          isTrue,
        );
        expect(
          plan.proposedDraftRightsCarryover.containsKey(age38Id.value),
          isFalse,
        );
        expect(
          plan.proposedCarriedUnsignedProspects.containsKey(age38Id.value),
          isFalse,
        );
      },
    );

    test(
      '16, 17, 18, 19, 20, 21, 22, 23: historical signing by owning franchise, rejections, contract terms, financial obligations, and current-year regression',
      () {
        const planner = SeasonRolloverPlanner();
        final plan = planner.plan(completedChamp);

        final userUnsignedRights = completedChamp.unsignedDraftRights.first;
        final pid = userUnsignedRights.prospectId.value;
        final carriedY2 = plan.proposedCarriedUnsignedProspects[pid]!.withAge(
          23,
        );

        final y2Career = _withYear2CarriedProspect(
          completedY1: completedChamp,
          rights: userUnsignedRights,
          prospect: carriedY2,
          debtByTeam: {userUnsignedRights.owningTeamId.value: 500},
        );
        final updatedTeamFinances = [
          for (final tf in y2Career.finances.teamFinances.values)
            if (tf.teamId == userUnsignedRights.owningTeamId)
              TeamFinances(
                teamId: tf.teamId,
                operatingBudget: tf.operatingBudget,
                cash: 0,
                revenueBaseline: tf.revenueBaseline,
                season: tf.season,
                capGrandfathered: tf.capGrandfathered,
                grandfatheredPayroll: tf.grandfatheredPayroll,
                capException: tf.capException,
              )
            else
              tf,
        ];
        final y2WithDebt = y2Career.copyWith(
          finances: CareerFinances(
            contracts: y2Career.finances.contracts.values,
            schedules: y2Career.finances.schedules.values,
            teamFinances: updatedTeamFinances,
            staffCommitments: y2Career.finances.staffCommitments.values,
            facilities: y2Career.finances.facilities.values,
            debtByTeam: y2Career.finances.debtByTeam,
          ),
        );

        const signingService = RookieSigningService();
        final otherTeamId = y2WithDebt.league.teams
            .firstWhere((t) => t.id != userUnsignedRights.owningTeamId)
            .id;

        // 17. Reject unauthorized signing team
        expect(
          () => signingService.signDraftedRookie(
            career: y2WithDebt,
            teamId: otherTeamId,
            prospectId: userUnsignedRights.prospectId,
            category: RosterCategory.standard,
            durationYears: 2,
          ),
          throwsStateError,
        );

        // 16, 19, 20, 21, 22. Owning franchise signs historical prospect in Year 2
        final y2BeforeJson = GmCareerCodec.encode(y2WithDebt);
        final signedCareer = signingService.signDraftedRookie(
          career: y2WithDebt,
          teamId: userUnsignedRights.owningTeamId,
          prospectId: userUnsignedRights.prospectId,
          category: RosterCategory.standard,
          durationYears: 2,
        );
        expect(GmCareerCodec.encode(y2WithDebt), equals(y2BeforeJson));

        signedCareer.validate();
        expect(signedCareer.careerDraftRights.containsKey(pid), isFalse);
        expect(signedCareer.carriedUnsignedProspects.containsKey(pid), isFalse);

        final rookieContract = signedCareer.rookieSigningLedger.forPlayer(
          userUnsignedRights.prospectId,
        )!;
        expect(rookieContract.startYear, 2);
        expect(rookieContract.draftSeasonYear, 1);
        expect(rookieContract.overallPick, userUnsignedRights.overallPick);

        final employmentContract = signedCareer.finances.contractForPlayer(
          userUnsignedRights.prospectId,
        )!;
        expect(employmentContract.startYear, 2);
        expect(employmentContract.durationYears, 2);
        expect(employmentContract.source, ContractSource.rookie);
        expect(
          signedCareer.finances.debtByTeam[userUnsignedRights
              .owningTeamId
              .value],
          500,
        );

        final signedProfile = signedCareer.careerProfiles.forPlayer(
          userUnsignedRights.prospectId,
        )!;
        expect(signedProfile.age, 23);

        // 18. Reject duplicate signing
        expect(
          () => signingService.signDraftedRookie(
            career: signedCareer,
            teamId: userUnsignedRights.owningTeamId,
            prospectId: userUnsignedRights.prospectId,
            category: RosterCategory.standard,
            durationYears: 2,
          ),
          throwsStateError,
        );

        // 23. Current-year Year 1 signing still works
        final setup = const CareerSetupService().generate(
          CareerSetupRequest(
            selectedTeamId: TeamId('team-1'),
            selectedSituation: FranchiseSituation.contender,
            seed: 998877,
          ),
        );
        var freshY1 = GmCareer.fromSetupResult(setup, id: 'fresh-y1');
        const draftService = DraftExecutionService();
        freshY1 = draftService.startDraft(freshY1);
        while (!freshY1.draftExecutionState.isCompleted) {
          if (freshY1.draftExecutionState.isHumanTurn(
            order: freshY1.draftOrder,
            userTeamId: freshY1.userFranchiseId,
          )) {
            final pick = freshY1.draftClass.prospects.firstWhere(
              (p) => !freshY1.draftExecutionState.draftRights.containsKey(
                p.id.value,
              ),
            );
            freshY1 = draftService.makeHumanSelection(
              career: freshY1,
              prospectId: pick.id,
            );
          } else {
            freshY1 = draftService.executeAiSelection(freshY1);
          }
        }
        final y1UserRight = freshY1.unsignedDraftRights.firstWhere(
          (r) => r.owningTeamId == freshY1.userFranchiseId,
        );
        final y1Signed = signingService.signDraftedRookie(
          career: freshY1,
          teamId: y1UserRight.owningTeamId,
          prospectId: y1UserRight.prospectId,
          category: RosterCategory.standard,
          durationYears: 2,
        );
        expect(
          y1Signed.rookieSigningLedger.isSigned(y1UserRight.prospectId),
          isTrue,
        );
      },
    );

    test(
      '24, 25, 26: duplicate identity, missing snapshot, and corrupted snapshot rejections',
      () {
        final rights = completedChamp.unsignedDraftRights.first;
        final prospect = completedChamp.draftClass.byId(rights.prospectId)!;
        final carried = CarriedUnsignedProspect.fromRookieProspect(
          prospect: prospect,
          rights: rights,
          age: 22,
        );
        final y2Career = _withYear2CarriedProspect(
          completedY1: completedChamp,
          rights: rights,
          prospect: carried,
        );

        // 25. Missing snapshot rejected
        expect(
          () => y2Career.copyWith(carriedUnsignedProspects: const {}),
          throwsFormatException,
        );

        // 26a. Orphan snapshot without rights rejected
        expect(
          () => y2Career.copyWith(careerDraftRights: const {}),
          throwsFormatException,
        );

        // 26b. Mismatched overallPick rejected
        final badPick = CarriedUnsignedProspect(
          playerId: carried.playerId,
          firstName: carried.firstName,
          lastName: carried.lastName,
          position: carried.position,
          attributes: carried.attributes,
          age: carried.age,
          potential: carried.potential,
          trajectory: carried.trajectory,
          draftSeasonYear: carried.draftSeasonYear,
          overallPick: carried.overallPick == 1 ? 2 : 1,
          projectedRank: carried.projectedRank,
          estimatedPotentialGrade: carried.estimatedPotentialGrade,
          estimatedPotentialRange: carried.estimatedPotentialRange,
        );
        expect(
          () => y2Career.copyWith(
            carriedUnsignedProspects: {carried.playerId.value: badPick},
          ),
          throwsFormatException,
        );

        // 24. Duplicate identity with active roster rejected
        final rostered = y2Career.league.teams.first.players.first;
        final rosteredRights = DraftRights(
          prospectId: rostered.id,
          owningTeamId: y2Career.league.teams.first.id,
          overallPick: 59,
          seasonYear: 1,
        );
        final rosteredCarried = CarriedUnsignedProspect(
          playerId: rostered.id,
          firstName: rostered.firstName,
          lastName: rostered.lastName,
          position: rostered.position,
          attributes: rostered.attributes,
          age: 22,
          potential: 85,
          trajectory: DevelopmentTrajectory.steady,
          draftSeasonYear: 1,
          overallPick: 59,
          projectedRank: 59,
          estimatedPotentialGrade: 'C',
          estimatedPotentialRange: '70-78',
        );
        expect(
          () => y2Career.copyWith(
            careerDraftRights: {rostered.id.value: rosteredRights},
            carriedUnsignedProspects: {rostered.id.value: rosteredCarried},
          ),
          throwsFormatException,
        );
      },
    );
  });
}
