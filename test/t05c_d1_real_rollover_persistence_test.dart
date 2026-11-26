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

  bool failNextArchiveWrite = false;
  bool failNextActiveWrite = false;

  @override
  Future<void> writeArchive({
    required int seasonYear,
    required String archiveJson,
    required String expectedDigest,
    String slot = 'default',
  }) async {
    if (failNextArchiveWrite) {
      failNextArchiveWrite = false;
      throw const GmCareerStorageException('Simulated archive write failure');
    }
    return super.writeArchive(
      seasonYear: seasonYear,
      archiveJson: archiveJson,
      expectedDigest: expectedDigest,
      slot: slot,
    );
  }

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    if (failNextActiveWrite) {
      failNextActiveWrite = false;
      throw const GmCareerStorageException('Simulated active save failure');
    }
    return super.write(data, slot: slot);
  }
}

class _NonArchiveCareerStorage implements GmCareerStorage {
  final Map<String, String> _saves = <String, String>{};
  int writeCount = 0;

  @override
  Future<void> clear({String slot = 'default'}) async {
    _saves.remove(slot);
  }

  @override
  Future<bool> hasSave({String slot = 'default'}) async =>
      _saves.containsKey(slot);

  @override
  Future<String?> read({String slot = 'default'}) async => _saves[slot];

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    writeCount++;
    _saves[slot] = data;
  }
}

({GmCareer completed, GmCareer regularSeason, GmCareer incompletePlayoffs})
_buildYear1Fixtures({
  String id = 't05c-d1-career',
  int seed = 20261028,
  TeamId selectedTeamId = const TeamId('team-1'),
}) {
  final setup = const CareerSetupService().generate(
    CareerSetupRequest(
      selectedTeamId: selectedTeamId,
      selectedSituation: FranchiseSituation.tanking,
      seed: seed,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: id);
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
  final regularSeasonCareer = c;

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
  final incompletePlayoffsCareer = c;
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

  return (
    completed: c,
    regularSeason: regularSeasonCareer,
    incompletePlayoffs: incompletePlayoffsCareer,
  );
}

void main() {
  late GmCareer completedYear1;
  late GmCareer regularSeasonYear1;
  late GmCareer incompletePlayoffsYear1;
  late String completedYear1Json;
  late GmCareer completedYear1SlotB;
  late String completedYear1SlotBJson;
  late Directory rootTempDir;

  setUpAll(() {
    rootTempDir = Directory.systemTemp.createTempSync('t05c_d1_test_');
    final fixtures = _buildYear1Fixtures();
    completedYear1 = fixtures.completed;
    regularSeasonYear1 = fixtures.regularSeason;
    incompletePlayoffsYear1 = fixtures.incompletePlayoffs;
    completedYear1Json = GmCareerCodec.encode(completedYear1);
    completedYear1SlotB = _buildYear1Fixtures(
      id: 't05c-d1-career-b',
      seed: 20261028,
      selectedTeamId: const TeamId('team-2'),
    ).completed;
    completedYear1SlotBJson = GmCareerCodec.encode(completedYear1SlotB);
  });

  tearDownAll(() {
    try {
      if (rootTempDir.existsSync()) {
        rootTempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Directory createCaseDir(String name) =>
      Directory('${rootTempDir.path}/$name')..createSync(recursive: true);

  test(
    '1-8, 16-20: Real Year 1 -> Year 2 rollover, durable reload, history, financials, bundle, schema v25',
    timeout: const Timeout(Duration(minutes: 3)),
    () async {
      final dir = createCaseDir('happy_path');
      final storage = FileGmCareerStorage(directoryPath: dir.path);
      await storage.write(completedYear1Json, slot: 'slot_a');

      final controller = GmCareerController(storage: storage);
      await controller.loadCareer(slot: 'slot_a');
      expect(controller.career?.currentYear, 1);

      // 1. Confirmation required: confirmed=false must reject cleanly pre-write.
      await expectLater(
        controller.continueToNextSeason(confirmed: false, slot: 'slot_a'),
        throwsA(isA<StateError>()),
      );
      expect(controller.career?.currentYear, 1);
      expect(controller.draftRecoveryRequired, isFalse);
      expect(await storage.hasArchive(seasonYear: 1, slot: 'slot_a'), isFalse);

      // 2. Real rollover via continueToNextSeason(confirmed: true).
      var notifications = 0;
      controller.addListener(() => notifications++);
      await controller.continueToNextSeason(confirmed: true, slot: 'slot_a');

      expect(notifications, greaterThan(0));
      expect(controller.draftRecoveryRequired, isFalse);
      expect(controller.errorMessage, isNull);

      final year2 = controller.career!;
      // 3. Opening-offseason phase & structure.
      expect(year2.currentYear, 2);
      expect(year2.phase, CareerPhase.openingOffseason);
      expect(year2.regularSeasonState, isNull);
      expect(year2.playInState, isNull);
      expect(year2.playoffState, isNull);
      expect(year2.league.teams.length, 30);
      expect(
        year2.league.teams.map((t) => t.id.value).toList(),
        completedYear1.league.teams.map((t) => t.id.value).toList(),
      );
      expect(year2.seasonHistory.length, 1);
      expect(year2.marketHistory.length, 1);
      expect(year2.seasonSettlements.length, 1);
      // 19. No automatic FA signings or regular-season entry.
      expect(year2.freeAgentPool.acquisitions.entries, isEmpty);
      expect(year2.freeAgentOffers.entries, isEmpty);

      // Verify archive file & active Year 2 file exist on disk.
      expect(await storage.hasArchive(seasonYear: 1, slot: 'slot_a'), isTrue);
      expect(await storage.hasSave(slot: 'slot_a'), isTrue);

      // 16. Fresh controller reload from disk.
      final reloadedController = GmCareerController(storage: storage);
      await reloadedController.loadCareer(slot: 'slot_a');
      final reloaded = reloadedController.career!;
      expect(reloaded.currentYear, 2);
      expect(reloaded.phase, CareerPhase.openingOffseason);
      expect(reloaded.seasonHistory, equals(year2.seasonHistory));
      expect(
        jsonEncode(reloaded.marketHistory.single.toJson()),
        jsonEncode(year2.marketHistory.single.toJson()),
      );
      expect(
        jsonEncode(reloaded.seasonSettlements.single.toJson()),
        jsonEncode(year2.seasonSettlements.single.toJson()),
      );
      expect(reloaded.seasonSettlements.length, 1);

      // Current schema v29 persists append-only trade history.
      expect(reloaded.schemaVersion, GmCareer.currentSchemaVersion);
      expect(GmCareer.currentSchemaVersion, 29);
      final reencoded = GmCareerCodec.encode(reloaded);
      final redecoded = GmCareerCodec.decode(reencoded);
      expect(redecoded.currentYear, 2);
      expect(
        jsonEncode(redecoded.marketHistory.single.toJson()),
        jsonEncode(year2.marketHistory.single.toJson()),
      );

      // 4. Year 1 archive digest verified.
      final archive = await reloadedController.loadSeasonArchive(
        1,
        slot: 'slot_a',
      );
      expect(archive.seasonYear, 1);
      expect(archive.careerId, completedYear1.id);
      final rawArchive = await storage.readArchive(
        seasonYear: 1,
        slot: 'slot_a',
      );
      expect(
        SeasonArchiveCodec.digestOf(rawArchive!),
        reloaded.seasonHistory.single.archiveDigest,
      );

      // 5. Year 1 market history survives disk reload with original IDs & provenance.
      final mh = reloaded.marketHistory.single;
      expect(mh.seasonYear, 1);
      expect(
        jsonEncode(mh.draftOrder.toJson()),
        jsonEncode(completedYear1.draftOrder.toJson()),
      );
      expect(
        jsonEncode(mh.draftExecutionState.toJson()),
        jsonEncode(completedYear1.draftExecutionState.toJson()),
      );
      expect(
        jsonEncode(mh.aiRookieSigning.toJson()),
        jsonEncode(completedYear1.aiRookieSigning.toJson()),
      );
      expect(
        jsonEncode(mh.freeAgentAcquisitions.toJson()),
        jsonEncode(completedYear1.freeAgentPool.acquisitions.toJson()),
      );
      expect(
        jsonEncode(mh.freeAgentOffers.toJson()),
        jsonEncode(completedYear1.freeAgentOffers.toJson()),
      );
      expect(
        jsonEncode(mh.freeAgentMarket.toJson()),
        jsonEncode(completedYear1.freeAgentMarket.toJson()),
      );
      expect(
        jsonEncode(mh.offseasonClearance.toJson()),
        jsonEncode(completedYear1.offseasonClearance.toJson()),
      );
      expect(
        jsonEncode(mh.hardshipSettlement.toJson()),
        jsonEncode(completedYear1.hardshipSettlement.toJson()),
      );
      expect(
        mh.freeAgentAcquisitions.entries.keys.toSet(),
        completedYear1.freeAgentPool.acquisitions.entries.keys.toSet(),
      );

      // 6 & 8. Settlement, debt, and guaranteed liabilities preserved.
      expect(reloaded.seasonSettlements.single.seasonYear, 1);
      expect(reloaded.finances.debtByTeam, equals(year2.finances.debtByTeam));
      expect(
        reloaded.finances.guaranteedLiabilities.keys,
        equals(year2.finances.guaranteedLiabilities.keys),
      );
      expect(
        reloaded.retiredPlayers.map((r) => r.playerId.value).toList(),
        equals(year2.retiredPlayers.map((r) => r.playerId.value).toList()),
      );

      // 7. Surviving player IDs preserved (on active rosters or as expired FAs).
      final retiredIds = reloaded.retiredPlayers
          .map((r) => r.playerId.value)
          .toSet();
      final expectedSurvivingIds = completedYear1.league.teams
          .expand((t) => t.players)
          .where((p) => !retiredIds.contains(p.id.value))
          .map((p) => p.id.value)
          .toSet();
      final actualSurvivingIds = <String>{
        ...reloaded.league.teams
            .expand((t) => t.players)
            .map((p) => p.id.value),
        ...reloaded.freeAgentPool.entries.map((e) => e.player.id.value),
      };
      expect(actualSurvivingIds.containsAll(expectedSurvivingIds), isTrue);
      expect(
        reloaded.league.teams
            .expand((t) => t.players)
            .map((p) => p.id.value)
            .toSet(),
        equals(
          year2.league.teams
              .expand((t) => t.players)
              .map((p) => p.id.value)
              .toSet(),
        ),
      );

      // 17. Bundle export/import preserves Year 2 + Year 1 archive + market history.
      final bundle = await reloadedController.exportCareerBundle(
        slot: 'slot_a',
      );
      final importController = GmCareerController(storage: storage);
      await importController.importCareerBundle(bundle, slot: 'slot_bundle');
      final imported = importController.career!;
      expect(imported.currentYear, 2);
      expect(
        jsonEncode(imported.marketHistory.single.toJson()),
        jsonEncode(reloaded.marketHistory.single.toJson()),
      );
      expect(
        jsonEncode(imported.seasonSettlements.single.toJson()),
        jsonEncode(reloaded.seasonSettlements.single.toJson()),
      );
      final importedArchive = await importController.loadSeasonArchive(
        1,
        slot: 'slot_bundle',
      );
      expect(importedArchive.seasonYear, 1);

      // 14. Duplicate continuation rejected in Year 2.
      await expectLater(
        reloadedController.continueToNextSeason(
          confirmed: true,
          slot: 'slot_a',
        ),
        throwsA(isA<StateError>()),
      );
      expect(reloadedController.career?.currentYear, 2);
      expect(reloadedController.career?.seasonHistory.length, 1);
      expect(reloadedController.career?.marketHistory.length, 1);
      expect(reloadedController.career?.seasonSettlements.length, 1);
    },
  );

  test(
    '9: Wrong-phase continuation rejected before persistence without recovery guard',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final dir = createCaseDir('wrong_phase');
      final storage = FileGmCareerStorage(directoryPath: dir.path);

      // openingOffseason
      final setup = const CareerSetupService().generate(
        const CareerSetupRequest(
          selectedTeamId: TeamId('team-1'),
          selectedSituation: FranchiseSituation.tanking,
          seed: 20261028,
        ),
      );
      final opening = GmCareer.fromSetupResult(setup, id: 'wrong-phase-open');
      await storage.write(GmCareerCodec.encode(opening), slot: 'open');

      final c1 = GmCareerController(storage: storage);
      await c1.loadCareer(slot: 'open');
      await expectLater(
        c1.continueToNextSeason(confirmed: true, slot: 'open'),
        throwsA(anything),
      );
      expect(c1.career?.phase, CareerPhase.openingOffseason);
      expect(c1.draftRecoveryRequired, isFalse);
      expect(await storage.hasArchive(seasonYear: 1, slot: 'open'), isFalse);

      // regularSeason
      await storage.write(GmCareerCodec.encode(regularSeasonYear1), slot: 'rs');
      final cRs = GmCareerController(storage: storage);
      await cRs.loadCareer(slot: 'rs');
      await expectLater(
        cRs.continueToNextSeason(confirmed: true, slot: 'rs'),
        throwsA(anything),
      );
      expect(cRs.career?.phase, CareerPhase.regularSeason);
      expect(cRs.draftRecoveryRequired, isFalse);
      expect(await storage.hasArchive(seasonYear: 1, slot: 'rs'), isFalse);

      // incomplete playoffs
      await storage.write(
        GmCareerCodec.encode(incompletePlayoffsYear1),
        slot: 'po',
      );
      final c2 = GmCareerController(storage: storage);
      await c2.loadCareer(slot: 'po');
      await expectLater(
        c2.continueToNextSeason(confirmed: true, slot: 'po'),
        throwsA(anything),
      );
      expect(c2.career?.currentYear, 1);
      expect(c2.draftRecoveryRequired, isFalse);
      expect(await storage.hasArchive(seasonYear: 1, slot: 'po'), isFalse);
    },
  );

  test(
    '10-12: Failed archive write, failed active write, and matching orphan archive retry',
    timeout: const Timeout(Duration(minutes: 4)),
    () async {
      final dir = createCaseDir('failure_retry');
      final storage = _FaultyArchiveFileStorage(directoryPath: dir.path);
      await storage.write(completedYear1Json);

      final controller = GmCareerController(storage: storage);
      await controller.loadCareer();

      // 10. Archive write failure -> Year 1 stays authoritative, recovery guard set, reload restores Year 1.
      storage.failNextArchiveWrite = true;
      await expectLater(
        controller.continueToNextSeason(confirmed: true),
        throwsA(isA<GmCareerStorageException>()),
      );
      expect(controller.career?.currentYear, 1);
      expect(controller.draftRecoveryRequired, isTrue);
      expect(await storage.hasArchive(seasonYear: 1), isFalse);

      await controller.loadCareer();
      expect(controller.career?.currentYear, 1);
      expect(controller.draftRecoveryRequired, isFalse);

      // 11. Active save write failure after archive succeeds -> valid orphan archive, Year 1 active preserved.
      storage.failNextActiveWrite = true;
      await expectLater(
        controller.continueToNextSeason(confirmed: true),
        throwsA(isA<GmCareerStorageException>()),
      );
      expect(controller.career?.currentYear, 1);
      expect(controller.draftRecoveryRequired, isTrue);
      expect(await storage.hasArchive(seasonYear: 1), isTrue);

      final diskActive = GmCareerCodec.decode((await storage.read())!);
      expect(diskActive.currentYear, 1);

      // 12. Reload authoritative Year 1 and retry -> matching orphan archive accepted, Year 2 published once.
      await controller.loadCareer();
      expect(controller.career?.currentYear, 1);
      expect(controller.draftRecoveryRequired, isFalse);

      await controller.continueToNextSeason(confirmed: true);
      expect(controller.career?.currentYear, 2);
      expect(controller.career?.seasonHistory.length, 1);
      expect(controller.career?.marketHistory.length, 1);
      expect(controller.career?.seasonSettlements.length, 1);
    },
  );

  test(
    '13: Conflicting archive rejects rollover without overwriting active save or archive',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final dir = createCaseDir('conflicting_archive');
      final storage = FileGmCareerStorage(directoryPath: dir.path);
      await storage.write(completedYear1Json);

      final conflictingArchive = SeasonArchive.fromCareer(completedYear1SlotB);
      final encodedConflict = SeasonArchiveCodec.encodeWithDigest(
        conflictingArchive,
      );
      await storage.writeArchive(
        seasonYear: 1,
        archiveJson: encodedConflict.json,
        expectedDigest: encodedConflict.digest,
      );

      final controller = GmCareerController(storage: storage);
      await controller.loadCareer();
      await expectLater(
        controller.continueToNextSeason(confirmed: true),
        throwsA(isA<GmCareerStorageException>()),
      );
      expect(controller.career?.currentYear, 1);
      expect(controller.draftRecoveryRequired, isTrue);

      final diskActive = GmCareerCodec.decode((await storage.read())!);
      expect(diskActive.currentYear, 1);
      final diskArchive = await storage.readArchive(seasonYear: 1);
      expect(SeasonArchiveCodec.digestOf(diskArchive!), encodedConflict.digest);
    },
  );

  test(
    '15: Save-slot isolation between slot_a and slot_b',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final dir = createCaseDir('slot_isolation');
      final storage = FileGmCareerStorage(directoryPath: dir.path);
      await storage.write(completedYear1Json, slot: 'slot_a');
      await storage.write(completedYear1SlotBJson, slot: 'slot_b');

      final controllerA = GmCareerController(storage: storage);
      await controllerA.loadCareer(slot: 'slot_a');
      await controllerA.continueToNextSeason(confirmed: true, slot: 'slot_a');

      final controllerB = GmCareerController(storage: storage);
      await controllerB.loadCareer(slot: 'slot_b');
      expect(controllerB.career?.currentYear, 1);
      expect(controllerB.career?.id, completedYear1SlotB.id);
      expect(await storage.hasArchive(seasonYear: 1, slot: 'slot_b'), isFalse);
      expect(await storage.hasArchive(seasonYear: 1, slot: 'slot_a'), isTrue);
    },
  );

  test(
    'Missing archive storage capability fails before active write',
    () async {
      final storage = _NonArchiveCareerStorage();
      await storage.write(completedYear1Json);
      final writesBefore = storage.writeCount;

      final controller = GmCareerController(storage: storage);
      await controller.loadCareer();
      await expectLater(
        controller.continueToNextSeason(confirmed: true),
        throwsA(isA<StateError>()),
      );
      expect(storage.writeCount, writesBefore);
      expect(controller.career?.currentYear, 1);
    },
  );

  test(
    'Restart after uncertain write does not revert completed Year 2 to stale .bak',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final dir = createCaseDir('uncertain_write');
      final storage = FileGmCareerStorage(directoryPath: dir.path);
      await storage.write(completedYear1Json);

      final controller = GmCareerController(storage: storage);
      await controller.loadCareer();
      await controller.continueToNextSeason(confirmed: true);
      expect(controller.career?.currentYear, 2);

      // Simulate a stale .bak (Year 1) and stale .tmp left beside a valid Year 2 save.
      final activePath = storage.resolvePath();
      await File(
        '$activePath.bak',
      ).writeAsString(completedYear1Json, flush: true);
      await File(
        '$activePath.tmp',
      ).writeAsString('{"incomplete":true}', flush: true);

      final restartedController = GmCareerController(storage: storage);
      await restartedController.loadCareer();
      expect(restartedController.career?.currentYear, 2);
      expect(restartedController.career?.phase, CareerPhase.openingOffseason);
    },
  );
}
