@Tags(['endurance'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/domain_versions.dart' as domain_versions;

class _FaultyArchiveFileStorage extends FileGmCareerStorage {
  _FaultyArchiveFileStorage({required super.directoryPath});

  bool failNextActiveWrite = false;

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    if (failNextActiveWrite) {
      failNextActiveWrite = false;
      throw const GmCareerStorageException('Simulated active save failure');
    }
    return super.write(data, slot: slot);
  }
}

GmCareer _buildCompletedYear1() {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: 20261028,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 't05c-d3a-endurance');
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

void main() {
  late Directory rootTempDir;

  setUpAll(() {
    rootTempDir = Directory.systemTemp.createTempSync('t05c_d3a_endurance_');
  });

  tearDownAll(() {
    try {
      if (rootTempDir.existsSync()) {
        rootTempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  test(
    'Full Multi-Season Controller Endurance: Year 1 -> Year 2 (82 rounds + Play-In + Playoffs) -> Year 3 + bundle + Year 2 failure/retry',
    timeout: const Timeout(Duration(minutes: 25)),
    () async {
      final enduranceStopwatch = Stopwatch()..start();
      final dir = Directory('${rootTempDir.path}/endurance')
        ..createSync(recursive: true);
      final storage = _FaultyArchiveFileStorage(directoryPath: dir.path);
      const slot = 'endurance_slot';

      // ================================================================
      // 1. YEAR 1 -> YEAR 2 VIA PRODUCTION CONTROLLER
      // ================================================================
      final completedYear1 = _buildCompletedYear1();
      final y1Champion = completedYear1.playoffState!.champion!;
      final y1MarketRecordJson = jsonEncode(
        SeasonMarketHistoryRecord.fromCareer(completedYear1).toJson(),
      );
      final y1RookieContractPayloads = {
        for (final e in completedYear1.rookieSigningLedger.contracts.entries)
          e.key: jsonEncode(e.value.toJson()),
      };
      final y1StaffPayloads = {
        for (final e in completedYear1.finances.staffCommitments.entries)
          e.key: jsonEncode(e.value.toJson()),
      };
      final y1FacilityPayloads = {
        for (final e in completedYear1.finances.facilities.entries)
          e.key: jsonEncode(e.value.toJson()),
      };
      expect(completedYear1.draftExecutionState.selections, isNotEmpty);
      expect(completedYear1.aiRookieSigning.decisions, isNotEmpty);
      expect(completedYear1.freeAgentPool.acquisitions.entries, isNotEmpty);
      expect(completedYear1.freeAgentMarket.roundHistory, isNotEmpty);
      expect(y1RookieContractPayloads, isNotEmpty);
      expect(y1StaffPayloads, isNotEmpty);
      expect(y1FacilityPayloads, isNotEmpty);
      await storage.write(GmCareerCodec.encode(completedYear1), slot: slot);

      var controller = GmCareerController(storage: storage);
      await controller.loadCareer(slot: slot);
      expect(controller.career!.currentYear, 1);

      await controller.continueToNextSeason(confirmed: true, slot: slot);
      expect(controller.career!.currentYear, 2);
      expect(controller.career!.phase, CareerPhase.openingOffseason);

      final year2JsonBeforeDispose = GmCareerCodec.encode(controller.career!);
      controller.dispose();

      // Reload Year 2 in a fresh controller instance.
      controller = GmCareerController(storage: storage);
      await controller.loadCareer(slot: slot);
      final year2 = controller.career!;
      expect(year2.currentYear, 2);
      expect(year2.phase, CareerPhase.openingOffseason);
      expect(GmCareerCodec.encode(year2), year2JsonBeforeDispose);
      expect(year2.seasonHistory.length, 1);
      expect(year2.marketHistory.length, 1);
      expect(year2.seasonSettlements.length, 1);
      expect(
        jsonEncode(year2.marketHistory.single.toJson()),
        y1MarketRecordJson,
      );
      for (final entry in y1RookieContractPayloads.entries) {
        expect(
          jsonEncode(year2.rookieSigningLedger.contracts[entry.key]?.toJson()),
          entry.value,
        );
      }
      final y1SettlementJson = jsonEncode(
        year2.seasonSettlements.single.toJson(),
      );
      final y1Archive = await controller.loadSeasonArchive(1, slot: slot);
      final y1ArchiveRaw = await storage.readArchive(seasonYear: 1, slot: slot);
      expect(y1ArchiveRaw, isNotNull);
      expect(y1Archive.seasonYear, 1);
      expect(y1Archive.regularSeasonState.gameResults.length, 1230);
      expect(y1Archive.playInState.isComplete, isTrue);
      expect(y1Archive.playoffState.champion, y1Champion);
      expect(
        SeasonArchiveCodec.digestOf(y1ArchiveRaw!),
        year2.seasonHistory.single.archiveDigest,
      );
      expect(year2.seasonHistory.single.championTeamId, y1Champion);

      // ================================================================
      // 2. COMPLETE YEAR 2 OFFSEASON VIA PRODUCTION CONTROLLER
      // ================================================================
      await controller.startDraft(slot: slot);
      while (!controller.career!.draftExecutionState.isCompleted) {
        final c = controller.career!;
        final pick = c.draftClass.prospects.firstWhere(
          (p) => !c.draftExecutionState.draftRights.containsKey(p.id.value),
        );
        await controller.makeHumanSelection(prospectId: pick.id, slot: slot);
      }
      await controller.advanceAiRookieSigning(slot: slot);

      for (final right in controller.career!.unsignedDraftRights.toList()) {
        if (right.owningTeamId == controller.career!.userFranchiseId) {
          final currentTeam = controller.career!.userTeam;
          final standardCount = currentTeam.roster.players
              .where(
                (p) =>
                    currentTeam.roster.categoryOf(p.id) ==
                    RosterCategory.standard,
              )
              .length;
          if (standardCount < 15) {
            await controller.signDraftedRookie(
              prospectId: right.prospectId,
              category: RosterCategory.standard,
              durationYears: 2,
              slot: slot,
            );
          }
        }
      }

      for (var round = 0; round < 2; round++) {
        await controller.startFreeAgencyRound(slot: slot);
        await controller.prepareFreeAgencyResolution(slot: slot);
        await controller.resolveFreeAgencyRound(slot: slot);
      }

      await controller.startOffseasonClearance(slot: slot);
      await controller.prepareOffseasonClearance(slot: slot);
      if (controller.career!.offseasonClearance.isResolvable) {
        await controller.resolveOffseasonClearance(slot: slot);
      }
      if (const OffseasonReadinessGate().evaluate(controller.career!).status ==
          OffseasonReadinessStatus.financialExceptionRequired) {
        await controller.prepareHardshipSettlement(
          humanParticipationConfirmed: true,
          slot: slot,
        );
        if (controller.career!.hardshipSettlement.isResolvable) {
          await controller.resolveHardshipSettlement(slot: slot);
        }
      }
      await controller.markOffseasonCleared(slot: slot);

      final clearedYear2 = controller.career!;
      expect(
        const OffseasonReadinessGate().evaluate(clearedYear2).status,
        OffseasonReadinessStatus.cleared,
      );

      // ================================================================
      // 3. REAL YEAR 2 REGULAR SEASON (ALL 82 ROUNDS)
      // ================================================================
      await controller.startRegularSeason(confirmed: true, slot: slot);
      await controller.generateRegularSeasonSchedule(slot: slot);
      expect(controller.career!.phase, CareerPhase.regularSeason);
      expect(
        controller.career!.regularSeasonState!.schedule!.rounds.length,
        82,
      );

      final rsStopwatch = Stopwatch()..start();
      for (var round = 1; round <= 82; round++) {
        await controller.simulateNextRegularSeasonRound(
          expectedRoundNumber: round,
          confirmed: true,
          slot: slot,
        );
        if (round == 1 ||
            round == 20 ||
            round == 40 ||
            round == 60 ||
            round == 82) {
          // ignore: avoid_print
          print(
            '[C2-D3A] Year 2 regular season round $round/82 '
            '(elapsed=${rsStopwatch.elapsed.inSeconds}s, '
            'games=${controller.career!.regularSeasonState!.gameResults.length})',
          );
        }
        // Periodically reload from disk mid-season and continue cleanly.
        if (round == 40) {
          controller.dispose();
          controller = GmCareerController(storage: storage);
          await controller.loadCareer(slot: slot);
          expect(
            controller.career!.regularSeasonState!.gameResults.length,
            40 * 15,
          );
        }
      }

      final completedRs = controller.career!.regularSeasonState!;
      expect(controller.career!.currentYear, 2);
      expect(completedRs.gameResults.length, 1230);
      expect(completedRs.gameResults.keys.toSet().length, 1230);
      final totalGamesByTeam = <String, int>{};
      final homeGamesByTeam = <String, int>{};
      final awayGamesByTeam = <String, int>{};
      for (final res in completedRs.gameResults.values) {
        totalGamesByTeam[res.homeTeamId.value] =
            (totalGamesByTeam[res.homeTeamId.value] ?? 0) + 1;
        totalGamesByTeam[res.awayTeamId.value] =
            (totalGamesByTeam[res.awayTeamId.value] ?? 0) + 1;
        homeGamesByTeam[res.homeTeamId.value] =
            (homeGamesByTeam[res.homeTeamId.value] ?? 0) + 1;
        awayGamesByTeam[res.awayTeamId.value] =
            (awayGamesByTeam[res.awayTeamId.value] ?? 0) + 1;
      }
      expect(totalGamesByTeam.length, 30);
      for (final team in controller.career!.league.teams) {
        expect(totalGamesByTeam[team.id.value], 82);
        expect(homeGamesByTeam[team.id.value], 41);
        expect(awayGamesByTeam[team.id.value], 41);
      }

      // ================================================================
      // 4. REAL YEAR 2 PLAY-IN AND PLAYOFFS
      // ================================================================
      await controller.enterPlayIn(confirmed: true, slot: slot);
      expect(controller.career!.phase, CareerPhase.playIn);
      while (!controller.career!.playInState!.isComplete) {
        final pi = controller.career!.playInState!;
        final rsSeed = controller.career!.regularSeasonState!.scheduleSeed;
        String? nextGameId;
        for (var g = 1; g <= 3; g++) {
          final fix = pi.fixture(gameNumber: g, scheduleSeed: rsSeed);
          if (fix != null && !pi.gameResults.containsKey(fix.id)) {
            nextGameId = fix.id;
            break;
          }
        }
        expect(nextGameId, isNotNull);
        await controller.simulatePlayInGame(
          expectedGameId: nextGameId!,
          confirmed: true,
          slot: slot,
        );
      }
      expect(controller.career!.playInState!.isComplete, isTrue);

      await controller.enterPlayoffs(confirmed: true, slot: slot);
      expect(controller.career!.phase, CareerPhase.playoffs);
      while (!controller.career!.playoffState!.isComplete) {
        await controller.simulateNextPlayoffSlate(confirmed: true, slot: slot);
      }

      final completedYear2 = controller.career!;
      expect(completedYear2.currentYear, 2);
      expect(completedYear2.playoffState!.isComplete, isTrue);
      expect(completedYear2.playoffState!.champion, isNotNull);
      expect(completedYear2.regularSeasonState!.gameResults.length, 1230);

      final y2Champion = completedYear2.playoffState!.champion!;
      final y2MarketRecordJson = jsonEncode(
        SeasonMarketHistoryRecord.fromCareer(completedYear2).toJson(),
      );
      final y2RookieContractPayloads = {
        for (final e in completedYear2.rookieSigningLedger.contracts.entries)
          e.key: jsonEncode(e.value.toJson()),
      };
      expect(completedYear2.draftExecutionState.selections, isNotEmpty);
      expect(completedYear2.aiRookieSigning.decisions, isNotEmpty);
      expect(completedYear2.freeAgentPool.acquisitions.entries, isNotEmpty);
      expect(completedYear2.freeAgentMarket.roundHistory, isNotEmpty);
      expect(y2RookieContractPayloads, isNotEmpty);
      // ignore: avoid_print
      print(
        '[C2-D3A] Endurance continuity counts: '
        'y1Offers=${completedYear1.freeAgentOffers.entries.length}, '
        'y2Offers=${completedYear2.freeAgentOffers.entries.length}, '
        'y1Clearance=${completedYear1.offseasonClearance.outcomes.length}, '
        'y2Clearance=${completedYear2.offseasonClearance.outcomes.length}, '
        'y2Hardship=${completedYear2.hardshipSettlement.outcomes.length}, '
        'y2Liabilities=${completedYear2.finances.guaranteedLiabilities.length}, '
        'y2Debts=${completedYear2.finances.debtByTeam.values.where((d) => d > 0).length}',
      );

      // Save a copy of completed Year 2 for isolated failure/retry test (#10).
      final completedYear2Json = GmCareerCodec.encode(completedYear2);
      controller.dispose();

      // Reload completed Year 2 championship before Year 2 -> Year 3 rollover.
      controller = GmCareerController(storage: storage);
      await controller.loadCareer(slot: slot);
      expect(controller.career!.currentYear, 2);
      expect(controller.career!.playoffState!.isComplete, isTrue);

      // ================================================================
      // 5. YEAR 2 -> YEAR 3 ROLLOVER & RELOAD & BUNDLE
      // ================================================================
      await controller.continueToNextSeason(confirmed: true, slot: slot);
      final year3 = controller.career!;
      expect(year3.currentYear, 3);
      expect(year3.phase, CareerPhase.openingOffseason);
      expect(year3.regularSeasonState, isNull);
      expect(year3.playInState, isNull);
      expect(year3.playoffState, isNull);
      expect(year3.seasonHistory.map((h) => h.seasonYear).toList(), [1, 2]);
      expect(year3.marketHistory.map((m) => m.seasonYear).toList(), [1, 2]);
      expect(year3.seasonSettlements.map((s) => s.seasonYear).toList(), [1, 2]);

      final year3Json = GmCareerCodec.encode(year3);
      final y2SettlementJson = jsonEncode(year3.seasonSettlements[1].toJson());
      final y3StaffPayloads = {
        for (final e in year3.finances.staffCommitments.entries)
          e.key: jsonEncode(e.value.toJson()),
      };
      final y3FacilityPayloads = {
        for (final e in year3.finances.facilities.entries)
          e.key: jsonEncode(e.value.toJson()),
      };
      final y3ContractPayloads = {
        for (final e in year3.finances.contracts.entries)
          e.key: jsonEncode(e.value.toJson()),
      };
      final y3SchedulePayloads = {
        for (final e in year3.finances.schedules.entries)
          e.key: jsonEncode(e.value.toJson()),
      };
      final y3LiabilityPayloads = {
        for (final e in year3.finances.guaranteedLiabilities.entries)
          e.key: jsonEncode(e.value.toJson()),
      };
      final y3DraftRightPayloads = {
        for (final e in year3.careerDraftRights.entries)
          e.key: jsonEncode(e.value.toJson()),
      };
      expect(y3FacilityPayloads, isNotEmpty);
      expect(y3ContractPayloads, isNotEmpty);
      expect(y3SchedulePayloads, isNotEmpty);
      for (final facilityEntry in y1FacilityPayloads.entries) {
        expect(y3FacilityPayloads[facilityEntry.key], facilityEntry.value);
      }
      controller.dispose();

      // Reload Year 3 in a new controller instance.
      final reloadedController = GmCareerController(storage: storage);
      await reloadedController.loadCareer(slot: slot);
      final reloadedYear3 = reloadedController.career!;
      expect(GmCareerCodec.encode(reloadedYear3), year3Json);
      expect(reloadedYear3.id, completedYear1.id);
      expect(reloadedYear3.league.teams.length, 30);

      // Verify both historical season archives (content, champions, digests).
      final reloadedY1Archive = await reloadedController.loadSeasonArchive(
        1,
        slot: slot,
      );
      final reloadedY2Archive = await reloadedController.loadSeasonArchive(
        2,
        slot: slot,
      );
      final reloadedY1Raw = await storage.readArchive(
        seasonYear: 1,
        slot: slot,
      );
      final reloadedY2Raw = await storage.readArchive(
        seasonYear: 2,
        slot: slot,
      );
      expect(reloadedY1Raw, isNotNull);
      expect(reloadedY2Raw, isNotNull);
      expect(reloadedY1Archive.seasonYear, 1);
      expect(reloadedY1Archive.regularSeasonState.gameResults.length, 1230);
      expect(reloadedY1Archive.playInState.isComplete, isTrue);
      expect(reloadedY1Archive.playoffState.champion, y1Champion);
      expect(
        SeasonArchiveCodec.digestOf(reloadedY1Raw!),
        reloadedYear3.seasonHistory[0].archiveDigest,
      );
      expect(reloadedYear3.seasonHistory[0].championTeamId, y1Champion);

      expect(reloadedY2Archive.seasonYear, 2);
      expect(reloadedY2Archive.regularSeasonState.gameResults.length, 1230);
      expect(reloadedY2Archive.playInState.isComplete, isTrue);
      expect(reloadedY2Archive.playoffState.champion, y2Champion);
      expect(
        SeasonArchiveCodec.digestOf(reloadedY2Raw!),
        reloadedYear3.seasonHistory[1].archiveDigest,
      );
      expect(reloadedYear3.seasonHistory[1].championTeamId, y2Champion);

      // Verify full serialized payloads for marketHistory, contracts, rights,
      // staff, facilities, liabilities, settlements & 30-team debts/cash.
      void verifyYear3Payloads(GmCareer candidate) {
        expect(
          jsonEncode(candidate.marketHistory[0].toJson()),
          y1MarketRecordJson,
        );
        expect(
          jsonEncode(candidate.marketHistory[1].toJson()),
          y2MarketRecordJson,
        );
        expect(
          jsonEncode(candidate.seasonSettlements[0].toJson()),
          y1SettlementJson,
        );
        expect(
          jsonEncode(candidate.seasonSettlements[1].toJson()),
          y2SettlementJson,
        );
        for (final e in y2RookieContractPayloads.entries) {
          expect(
            jsonEncode(
              candidate.rookieSigningLedger.contracts[e.key]?.toJson(),
            ),
            e.value,
          );
        }
        expect({
          for (final e in candidate.careerDraftRights.entries)
            e.key: jsonEncode(e.value.toJson()),
        }, y3DraftRightPayloads);
        expect({
          for (final e in candidate.finances.staffCommitments.entries)
            e.key: jsonEncode(e.value.toJson()),
        }, y3StaffPayloads);
        expect({
          for (final e in candidate.finances.facilities.entries)
            e.key: jsonEncode(e.value.toJson()),
        }, y3FacilityPayloads);
        expect({
          for (final e in candidate.finances.contracts.entries)
            e.key: jsonEncode(e.value.toJson()),
        }, y3ContractPayloads);
        expect({
          for (final e in candidate.finances.schedules.entries)
            e.key: jsonEncode(e.value.toJson()),
        }, y3SchedulePayloads);
        expect({
          for (final e in candidate.finances.guaranteedLiabilities.entries)
            e.key: jsonEncode(e.value.toJson()),
        }, y3LiabilityPayloads);
        final y2Settlement = candidate.seasonSettlements[1];
        expect(y2Settlement.seasonYear, 2);
        expect(y2Settlement.teamEntries.length, 30);
        for (final teamSettlement in y2Settlement.teamEntries) {
          expect(
            candidate.finances.debtByTeam[teamSettlement.teamId.value] ?? 0,
            teamSettlement.endingDebt,
          );
          expect(
            candidate.finances.teamFinances[teamSettlement.teamId.value]?.cash,
            teamSettlement.endingCash,
          );
        }
      }

      verifyYear3Payloads(reloadedYear3);

      // Export & import Year 3 bundle into isolated slot.
      final bundleJson = await reloadedController.exportCareerBundle(
        slot: slot,
      );
      const bundleSlot = 'bundle_slot';
      await reloadedController.importCareerBundle(bundleJson, slot: bundleSlot);
      expect(reloadedController.career!.currentYear, 3);
      expect(
        reloadedController.career!.seasonHistory
            .map((h) => h.seasonYear)
            .toList(),
        [1, 2],
      );
      verifyYear3Payloads(reloadedController.career!);
      final bundleY1 = await reloadedController.loadSeasonArchive(
        1,
        slot: bundleSlot,
      );
      final bundleY2 = await reloadedController.loadSeasonArchive(
        2,
        slot: bundleSlot,
      );
      expect(bundleY1.seasonYear, 1);
      expect(bundleY1.playoffState.champion, y1Champion);
      expect(bundleY2.seasonYear, 2);
      expect(bundleY2.playoffState.champion, y2Champion);
      reloadedController.dispose();

      // ================================================================
      // 6. YEAR 2 ROLLOVER FAILURE / RETRY ON ISOLATED SLOT
      // ================================================================
      const retrySlot = 'retry_slot';
      await storage.write(completedYear2Json, slot: retrySlot);
      // Seed Year 1 archive in retry_slot so export/continuity is complete.
      final rawY1Archive = await storage.readArchive(seasonYear: 1, slot: slot);
      await storage.writeArchive(
        seasonYear: 1,
        archiveJson: rawY1Archive!,
        expectedDigest: SeasonArchiveCodec.digestOf(rawY1Archive),
        slot: retrySlot,
      );

      final retryController = GmCareerController(storage: storage);
      await retryController.loadCareer(slot: retrySlot);
      storage.failNextActiveWrite = true;
      await expectLater(
        retryController.continueToNextSeason(confirmed: true, slot: retrySlot),
        throwsA(isA<GmCareerStorageException>()),
      );
      expect(retryController.career!.currentYear, 2);
      expect(retryController.draftRecoveryRequired, isTrue);
      expect(await storage.hasArchive(seasonYear: 2, slot: retrySlot), isTrue);

      await retryController.loadCareer(slot: retrySlot);
      expect(retryController.career!.currentYear, 2);
      expect(retryController.draftRecoveryRequired, isFalse);

      await retryController.continueToNextSeason(
        confirmed: true,
        slot: retrySlot,
      );
      expect(retryController.career!.currentYear, 3);
      expect(
        retryController.career!.seasonHistory.map((h) => h.seasonYear).toList(),
        [1, 2],
      );
      expect(
        retryController.career!.seasonSettlements
            .map((s) => s.seasonYear)
            .toList(),
        [1, 2],
      );
      retryController.dispose();

      // ignore: avoid_print
      print(
        '[C2-D3A] Full multi-season endurance complete in '
        '${enduranceStopwatch.elapsed.inSeconds}s',
      );
    },
  );
}
