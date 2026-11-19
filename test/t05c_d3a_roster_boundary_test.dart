import 'dart:convert';
import 'dart:io';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/domain_versions.dart' as domain_versions;

GmCareer _buildCompletedYear1() {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: 20261028,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 't05c-d3a-boundary');
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
    int gameSeed, {
    bool homeWins = true,
  }) {
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

    addLines(teamById[homeTeamId]!, homeWins ? 104 : 96);
    addLines(teamById[awayTeamId]!, homeWins ? 96 : 104);
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
        homeScore: homeWins ? 104 : 96,
        awayScore: homeWins ? 96 : 104,
        winnerTeamId: homeWins ? homeTeamId : awayTeamId,
        periodScoresHome: homeWins
            ? const {'Q1': 26, 'Q2': 26, 'Q3': 26, 'Q4': 26}
            : const {'Q1': 24, 'Q2': 24, 'Q3': 24, 'Q4': 24},
        periodScoresAway: homeWins
            ? const {'Q1': 24, 'Q2': 24, 'Q3': 24, 'Q4': 24}
            : const {'Q1': 26, 'Q2': 26, 'Q3': 26, 'Q4': 26},
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
  for (var g = 1; g <= 3; g++) {
    final pi = c.playInState!;
    final fix = pi.fixture(gameNumber: g, scheduleSeed: rs0.scheduleSeed)!;
    final res = buildResult(
      fix.id,
      pi.seasonId,
      pi.seasonYear,
      fix.homeTeamId,
      fix.awayTeamId,
      fix.gameSeed,
    );
    c = c.copyWith(
      playInState: pi.withResult(
        result: res,
        leagueSnapshotJson: leagueJson,
        scheduleSeed: rs0.scheduleSeed,
      ),
    );
  }
  c = const PlayoffEntryService().enter(c);
  while (!c.playoffState!.isComplete) {
    final po = c.playoffState!;
    final resList = <RegularSeasonGameResult>[];
    for (final g in po.nextEligibleGames) {
      final slot = po.seriesAt(g.seriesIndex);
      resList.add(
        buildResult(
          g.id,
          po.seasonId,
          po.seasonYear,
          g.homeTeamId,
          g.awayTeamId,
          g.gameSeed,
          homeWins: g.homeTeamId == slot.firstTeamId,
        ),
      );
    }
    c = c.copyWith(
      playoffState: po.withResults(
        results: resList,
        addedSnapshots: {snapshotId: leagueJson},
        scheduleSeed: rs0.scheduleSeed,
        franchiseIds: [for (final t in rs0.openingTeams) t.teamId],
      ),
    );
  }
  return c;
}

GmCareer _buildYear2WithContinuingCount(
  GmCareer completedYear1,
  int targetCount,
) {
  final archive = SeasonArchive.fromCareer(completedYear1);
  final encodedArchive = SeasonArchiveCodec.encodeWithDigest(archive);
  final record = archive.toHistoryRecord(encodedArchive.digest);
  final next = const SeasonRolloverService().rollover(
    current: completedYear1,
    archiveRecord: record,
  );

  final signedIds = next.rookieSigningLedger.contracts.keys.toSet();
  final targetTeam = targetCount == 15
      ? next.userTeam
      : next.league.teams.firstWhere(
          (t) =>
              t.players.length >= targetCount &&
              !t.players.any((p) => signedIds.contains(p.id.value)),
        );
  final nextWithTarget = targetTeam.id == next.userFranchiseId
      ? next
      : next.copyWith(
          userFranchiseId: targetTeam.id,
          userOpeningDraftPick: next.draftOrder
              .picksForTeam(targetTeam.id)
              .first
              .overallPick,
        );
  if (targetCount == 15 && targetTeam.players.length < 15) {
    final needed = 15 - targetTeam.players.length;
    final additions = next.freeAgentPool.entries.take(needed).toList();
    final updatedPlayers = [
      ...targetTeam.players,
      for (final e in additions) e.player,
    ];
    final updatedCategories = Map<String, RosterCategory>.of(
      targetTeam.roster.categories,
    );
    for (final e in additions) {
      updatedCategories[e.player.id.value] = RosterCategory.standard;
    }
    final updatedLeague = League.create(
      id: next.league.id,
      name: next.league.name,
      config: next.league.config,
      teams: [
        for (final t in next.league.teams)
          t.id == targetTeam.id
              ? t.copyWith(
                  roster: Roster(updatedPlayers, categories: updatedCategories),
                )
              : t,
      ],
      enforceRosterSize: false,
      enforcePositionCoverage: false,
    );
    final updatedProfiles = Map<String, PlayerCareerProfile>.of(
      next.careerProfiles.profiles,
    );
    final updatedContracts = List<PlayerContract>.of(
      next.finances.contracts.values,
    );
    final updatedSchedules = List<ContractFinancials>.of(
      next.finances.schedules.values,
    );
    for (final entry in additions) {
      final pid = entry.player.id;
      updatedProfiles[pid.value] = entry.profile;
      final contractId = 'boundary-15-${pid.value}';
      updatedContracts.add(
        PlayerContract(
          id: contractId,
          playerId: pid,
          teamId: targetTeam.id,
          category: RosterCategory.standard,
          startYear: 2,
          durationYears: 1,
          source: ContractSource.freeAgent,
        ),
      );
      updatedSchedules.add(
        ContractFinancials(
          contractId: contractId,
          playerId: pid,
          teamId: targetTeam.id,
          annualSalaries: [FinancialRules.minimumSalary],
          guaranteedYears: 1,
          source: ContractSource.freeAgent,
          signedYear: 2,
        ),
      );
    }
    final additionIds = {for (final e in additions) e.player.id.value};
    return nextWithTarget.copyWith(
      league: updatedLeague,
      careerProfiles: LeagueCareerProfiles(
        schemaVersion: nextWithTarget.careerProfiles.schemaVersion,
        leagueSeed: nextWithTarget.careerProfiles.leagueSeed,
        profiles: updatedProfiles,
      ),
      freeAgentPool: FreeAgentPool(
        seasonYear: nextWithTarget.freeAgentPool.seasonYear,
        entries: [
          for (final e in nextWithTarget.freeAgentPool.entries)
            if (!additionIds.contains(e.player.id.value)) e,
        ],
        acquisitions: nextWithTarget.freeAgentPool.acquisitions,
      ),
      finances: CareerFinances(
        contracts: updatedContracts,
        schedules: updatedSchedules,
        teamFinances: nextWithTarget.finances.teamFinances.values,
        staffCommitments: nextWithTarget.finances.staffCommitments.values,
        facilities: nextWithTarget.finances.facilities.values,
        guaranteedLiabilities:
            nextWithTarget.finances.guaranteedLiabilities.values,
        debtByTeam: nextWithTarget.finances.debtByTeam,
      ),
    );
  }

  final keptTeamPlayers = targetTeam.players.take(targetCount).toList();
  final keptTeamCategories = {
    for (final p in keptTeamPlayers)
      p.id.value: targetTeam.roster.categoryOf(p.id),
  };
  final adjustedLeague = League.create(
    id: nextWithTarget.league.id,
    name: nextWithTarget.league.name,
    config: nextWithTarget.league.config,
    teams: [
      for (final t in nextWithTarget.league.teams)
        t.id == targetTeam.id
            ? t.copyWith(
                roster: Roster(keptTeamPlayers, categories: keptTeamCategories),
              )
            : t,
    ],
    enforceRosterSize: false,
    enforcePositionCoverage: false,
  );
  final keptIds = {
    for (final t in adjustedLeague.teams)
      for (final p in t.players) p.id.value,
  };
  return nextWithTarget.copyWith(
    league: adjustedLeague,
    careerProfiles: LeagueCareerProfiles(
      schemaVersion: nextWithTarget.careerProfiles.schemaVersion,
      leagueSeed: nextWithTarget.careerProfiles.leagueSeed,
      profiles: {
        for (final e in nextWithTarget.careerProfiles.profiles.entries)
          if (keptIds.contains(e.key)) e.key: e.value,
      },
    ),
    finances: CareerFinances(
      contracts: [
        for (final c in nextWithTarget.finances.contracts.values)
          if (keptIds.contains(c.playerId.value)) c,
      ],
      schedules: [
        for (final s in nextWithTarget.finances.schedules.values)
          if (keptIds.contains(s.playerId.value)) s,
      ],
      teamFinances: nextWithTarget.finances.teamFinances.values,
      staffCommitments: nextWithTarget.finances.staffCommitments.values,
      facilities: nextWithTarget.finances.facilities.values,
      guaranteedLiabilities:
          nextWithTarget.finances.guaranteedLiabilities.values,
      debtByTeam: nextWithTarget.finances.debtByTeam,
    ),
  );
}

void main() {
  late GmCareer completedYear1;
  late Directory rootTempDir;

  setUpAll(() {
    rootTempDir = Directory.systemTemp.createTempSync('t05c_d3a_boundary_');
    completedYear1 = _buildCompletedYear1();
  });

  tearDownAll(() {
    try {
      if (rootTempDir.existsSync()) {
        rootTempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  for (final targetCount in const [0, 1, 4, 5, 15]) {
    test(
      'Year 2 openingOffseason validates with exact $targetCount continuing players',
      () {
        final year2 = _buildYear2WithContinuingCount(
          completedYear1,
          targetCount,
        );
        expect(year2.currentYear, 2);
        expect(year2.phase, CareerPhase.openingOffseason);
        expect(year2.userTeam.players.length, targetCount);

        // Domain validation & codec round-trip succeed.
        year2.validate();
        final roundTrip = GmCareerCodec.decode(GmCareerCodec.encode(year2));
        expect(roundTrip.userTeam.players.length, targetCount);

        // Regular-season readiness blocks < 5 or incomplete standard rosters.
        final readiness = const OffseasonReadinessGate().evaluate(year2);
        if (targetCount < 5) {
          expect(readiness.status, isNot(OffseasonReadinessStatus.cleared));
          expect(
            () => const RegularSeasonEntryService().start(year2),
            throwsA(anything),
          );
        }

        // Default strict LeagueValidator rejects rosters < 5.
        final strictResult = LeagueValidator.validate(year2.league);
        if (targetCount < 5) {
          expect(strictResult.isValid, isFalse);
        } else {
          expect(year2.userTeam.players.length, greaterThanOrEqualTo(5));
        }

        // Maximum category limits remain enforced (cannot exceed 15 standard players).
        if (targetCount == 15) {
          expect(year2.userTeam.players.length, 15);
          final freeAgent = year2.freeAgentPool.entries.first.player;
          final overLimitTeam = year2.userTeam.copyWith(
            roster: Roster([...year2.userTeam.players, freeAgent]),
          );
          final overLimitLeague = League.create(
            id: year2.league.id,
            name: year2.league.name,
            config: year2.league.config,
            teams: [
              for (final t in year2.league.teams)
                t.id == overLimitTeam.id ? overLimitTeam : t,
            ],
            enforceRosterSize: false,
            enforcePositionCoverage: false,
          );
          expect(
            () => year2.copyWith(league: overLimitLeague),
            throwsA(anything),
          );
        }
      },
    );
  }

  test(
    '0-player Year 2 team completes first-player acquisition via controller and reloads cleanly',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final year2Empty = _buildYear2WithContinuingCount(completedYear1, 0);
      expect(year2Empty.userTeam.players, isEmpty);

      final dir = Directory('${rootTempDir.path}/zero_player_first_signing')
        ..createSync(recursive: true);
      final storage = FileGmCareerStorage(directoryPath: dir.path);
      await storage.write(GmCareerCodec.encode(year2Empty), slot: 'zero_slot');

      final controller = GmCareerController(storage: storage);
      GmCareerController? reloadedController;
      try {
        await controller.loadCareer(slot: 'zero_slot');
        expect(controller.career!.userTeam.players, isEmpty);

        // Complete Year 2 draft through production controller APIs.
        await controller.startDraft(slot: 'zero_slot');
        while (!controller.career!.draftExecutionState.isCompleted) {
          final c = controller.career!;
          final pick = c.draftClass.prospects.firstWhere(
            (p) => !c.draftExecutionState.draftRights.containsKey(p.id.value),
          );
          await controller.makeHumanSelection(
            prospectId: pick.id,
            slot: 'zero_slot',
          );
        }
        await controller.advanceAiRookieSigning(slot: 'zero_slot');

        final humanRights = controller.career!.unsignedDraftRights
            .where((r) => r.owningTeamId == controller.career!.userFranchiseId)
            .toList();
        expect(humanRights, isNotEmpty);

        // First legitimate player acquisition from an empty 0-player roster!
        final firstRight = humanRights.first;
        await controller.signDraftedRookie(
          prospectId: firstRight.prospectId,
          category: RosterCategory.standard,
          durationYears: 2,
          slot: 'zero_slot',
        );

        final afterSigning = controller.career!;
        expect(afterSigning.userTeam.players.length, 1);
        final signedPlayer = afterSigning.userTeam.players.single;
        expect(signedPlayer.id, firstRight.prospectId);

        final contract = afterSigning.finances.contracts.values.singleWhere(
          (c) => c.playerId == signedPlayer.id,
        );
        expect(contract.teamId, afterSigning.userFranchiseId);
        expect(contract.category, RosterCategory.standard);
        final schedule = afterSigning.finances.schedules[contract.id]!;
        expect(schedule.annualSalaries.first, greaterThan(0));

        // Reload from disk in a fresh controller and verify persistence.
        reloadedController = GmCareerController(storage: storage);
        await reloadedController.loadCareer(slot: 'zero_slot');
        final reloaded = reloadedController.career!;
        expect(reloaded.userTeam.players.length, 1);
        expect(reloaded.userTeam.players.single.id, signedPlayer.id);
        expect(
          reloaded.finances.contracts[contract.id]?.teamId,
          contract.teamId,
        );
      } finally {
        controller.dispose();
        reloadedController?.dispose();
      }
    },
  );
}
