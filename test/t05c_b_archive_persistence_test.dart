import 'dart:convert';
import 'dart:io';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/rollover_isolate_workers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
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

GmCareer _buildCompletedYear1() {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: 20261028,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 't05c-b-flutter');
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

GmCareer _syntheticYear2Shell(GmCareer current, SeasonHistoryRecord record) {
  final base = GmCareer.fromSetupResult(
    const CareerSetupService().generate(
      const CareerSetupRequest(
        selectedTeamId: TeamId('team-1'),
        selectedSituation: FranchiseSituation.tanking,
        seed: 20261028,
      ),
    ),
    id: current.id,
  );
  return base.copyWith(
    currentYear: 2,
    draftClass: const DraftGenerator().generateDraftClass(
      league: base.league,
      seed: base.generationSeed,
      seasonYear: 2,
    ),
    freeAgentPool: FreeAgentPool(
      seasonYear: 2,
      entries: base.freeAgentPool.entries,
    ),
    freeAgentMarket: FreeAgentMarketState.initial(seasonYear: 2),
    offseasonClearance: OffseasonClearanceState.initial(seasonYear: 2),
    hardshipSettlement: HardshipSettlement.initial(seasonYear: 2),
    finances: FinancialMigration.bootstrapFromCareerState(
      league: base.league,
      careerProfiles: base.careerProfiles,
      rookieSigningLedger: RookieSigningLedger.empty(),
      currentYear: 2,
    ),
    seasonHistory: [...current.seasonHistory, record],
  );
}

void main() {
  late GmCareer completedYear1;
  late String completedYear1Json;
  late Directory tempDir;

  setUpAll(() {
    completedYear1 = _buildCompletedYear1();
    completedYear1Json = GmCareerCodec.encode(completedYear1);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('t05c_b_archive_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('M009-T05C-B: Immutable Season Archive Storage & Controller', () {
    test(
      'FileGmCareerStorage archive round-trip, idempotency, conflict rejection, and slot isolation',
      () async {
        final storage = FileGmCareerStorage(directoryPath: tempDir.path);
        final archive = SeasonArchive.fromCareer(completedYear1);
        final encoded = SeasonArchiveCodec.encodeWithDigest(archive);

        expect(
          await storage.hasArchive(seasonYear: 1, slot: 'slot-a'),
          isFalse,
        );

        // Write & read round-trip
        await storage.writeArchive(
          seasonYear: 1,
          archiveJson: encoded.json,
          expectedDigest: encoded.digest,
          slot: 'slot-a',
        );
        expect(await storage.hasArchive(seasonYear: 1, slot: 'slot-a'), isTrue);
        expect(
          await storage.hasArchive(seasonYear: 1, slot: 'slot-b'),
          isFalse,
        );
        expect(
          await storage.readArchive(seasonYear: 1, slot: 'slot-a'),
          equals(encoded.json),
        );

        // Repeated identical write succeeds idempotently
        await storage.writeArchive(
          seasonYear: 1,
          archiveJson: encoded.json,
          expectedDigest: encoded.digest,
          slot: 'slot-a',
        );

        // Conflicting second write is rejected without overwriting
        const otherJson = '{"conflicting":true}';
        final otherDigest = SeasonArchiveCodec.digestOf(otherJson);
        await expectLater(
          storage.writeArchive(
            seasonYear: 1,
            archiveJson: otherJson,
            expectedDigest: otherDigest,
            slot: 'slot-a',
          ),
          throwsA(isA<GmCareerStorageException>()),
        );
        expect(
          await storage.readArchive(seasonYear: 1, slot: 'slot-a'),
          equals(encoded.json),
        );

        // Slot-b can store its own archive and clear(slot-a) leaves slot-b untouched
        await storage.write('{"dummy":"a"}', slot: 'slot-a');
        await storage.write('{"dummy":"b"}', slot: 'slot-b');
        await storage.writeArchive(
          seasonYear: 1,
          archiveJson: encoded.json,
          expectedDigest: encoded.digest,
          slot: 'slot-b',
        );
        // Interrupted .tmp file in slot-a is also cleaned up
        final tmpFile = File('${storage.resolveArchivePath(1, 'slot-a')}.tmp');
        await tmpFile.writeAsString('{"partial":');

        await storage.clear(slot: 'slot-a');
        expect(await storage.hasSave(slot: 'slot-a'), isFalse);
        expect(
          await storage.hasArchive(seasonYear: 1, slot: 'slot-a'),
          isFalse,
        );
        expect(await tmpFile.exists(), isFalse);
        expect(await storage.hasSave(slot: 'slot-b'), isTrue);
        expect(await storage.hasArchive(seasonYear: 1, slot: 'slot-b'), isTrue);
      },
    );

    test(
      'InMemoryGmCareerStorage matches archive write/read/idempotency/clear semantics',
      () async {
        final storage = InMemoryGmCareerStorage();
        final archive = SeasonArchive.fromCareer(completedYear1);
        final encoded = SeasonArchiveCodec.encodeWithDigest(archive);

        await storage.writeArchive(
          seasonYear: 1,
          archiveJson: encoded.json,
          expectedDigest: encoded.digest,
          slot: 's1',
        );
        expect(await storage.hasArchive(seasonYear: 1, slot: 's1'), isTrue);
        await storage.writeArchive(
          seasonYear: 1,
          archiveJson: encoded.json,
          expectedDigest: encoded.digest,
          slot: 's1',
        );
        await expectLater(
          storage.writeArchive(
            seasonYear: 1,
            archiveJson: '{"x":1}',
            expectedDigest: SeasonArchiveCodec.digestOf('{"x":1}'),
            slot: 's1',
          ),
          throwsA(isA<GmCareerStorageException>()),
        );
        await storage.clear(slot: 's1');
        expect(await storage.hasArchive(seasonYear: 1, slot: 's1'), isFalse);
      },
    );

    test(
      'write-before-publish, failed archive write, orphan archive recovery, and bundle transfer',
      () async {
        final storage = _FaultyArchiveFileStorage(directoryPath: tempDir.path);
        await storage.write(completedYear1Json);
        final controller = GmCareerController(storage: storage);
        await controller.loadCareer();

        // 1. Failed archive write preserves Year 1 in memory & on disk
        storage.failNextArchiveWrite = true;
        await expectLater(
          controller.persistArchivedSeasonTransition(
            buildNextCareer: _syntheticYear2Shell,
            confirmed: true,
          ),
          throwsA(isA<GmCareerStorageException>()),
        );
        expect(controller.career!.currentYear, 1);
        expect(controller.draftRecoveryRequired, isTrue);
        expect(await storage.hasArchive(seasonYear: 1), isFalse);
        await controller.loadCareer();
        expect(controller.career!.currentYear, 1);
        expect(controller.draftRecoveryRequired, isFalse);

        // 2. Failed active save leaves Year 1 active + orphan archive on disk; retry succeeds
        storage.failNextActiveWrite = true;
        await expectLater(
          controller.persistArchivedSeasonTransition(
            buildNextCareer: _syntheticYear2Shell,
            confirmed: true,
          ),
          throwsA(isA<GmCareerStorageException>()),
        );
        expect(controller.career!.currentYear, 1);
        expect(controller.draftRecoveryRequired, isTrue);
        expect(await storage.hasArchive(seasonYear: 1), isTrue);

        await controller.loadCareer();
        expect(controller.career!.currentYear, 1);
        await controller.persistArchivedSeasonTransition(
          buildNextCareer: _syntheticYear2Shell,
          confirmed: true,
        );
        expect(controller.career!.currentYear, 2);
        expect(controller.career!.seasonHistory, hasLength(1));

        // 3. loadSeasonArchive verifies & returns full Year 1 archive
        final loadedArchive = await controller.loadSeasonArchive(1);
        expect(loadedArchive.regularSeasonState.gameResults, hasLength(1230));
        expect(
          loadedArchive.playoffState.champion,
          equals(completedYear1.playoffState!.champion),
        );

        // 4. Export bundle and import into a separate slot
        final bundle = await controller.exportCareerBundle();
        await controller.importCareerBundle(bundle, slot: 'imported');
        expect(await storage.hasSave(slot: 'imported'), isTrue);
        expect(
          await storage.hasArchive(seasonYear: 1, slot: 'imported'),
          isTrue,
        );

        // 5. Corrupted archive on disk is rejected
        final archiveFile = File(storage.resolveArchivePath(1, 'imported'));
        await archiveFile.writeAsString('${await archiveFile.readAsString()} ');
        await controller.loadCareer(slot: 'imported');
        await expectLater(
          controller.loadSeasonArchive(1, slot: 'imported'),
          throwsFormatException,
        );

        // 6. Missing archive on disk is rejected
        await archiveFile.delete();
        await expectLater(
          controller.loadSeasonArchive(1, slot: 'imported'),
          throwsA(isA<GmCareerStorageException>()),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'FIX 1 & FIX 2: controller enforces record consistency and transition invariants before writes',
      () async {
        final storage = _FaultyArchiveFileStorage(directoryPath: tempDir.path);
        await storage.write(completedYear1Json);
        final controller = GmCareerController(storage: storage);
        await controller.loadCareer();

        // FIX 2: missing appended seasonHistory record
        await expectLater(
          controller.persistArchivedSeasonTransition(
            confirmed: true,
            buildNextCareer: (current, record) => _syntheticYear2Shell(
              current,
              record,
            ).copyWith(seasonHistory: const []),
          ),
          throwsStateError,
        );
        expect(await storage.hasArchive(seasonYear: 1), isFalse);

        // FIX 2: wrong seasonHistory.last
        await expectLater(
          controller.persistArchivedSeasonTransition(
            confirmed: true,
            buildNextCareer: (current, record) {
              final finals = record.playoffSeries[14];
              final otherChamp = finals.winnerTeamId == finals.firstTeamId
                  ? finals.secondTeamId
                  : finals.firstTeamId;
              final badSeries = [
                for (var i = 0; i < record.playoffSeries.length; i++)
                  if (i == 14)
                    PlayoffSeriesSummary(
                      seriesIndex: 14,
                      round: finals.round,
                      firstTeamId: finals.firstTeamId,
                      secondTeamId: finals.secondTeamId,
                      winnerTeamId: otherChamp,
                      firstTeamWins: finals.firstTeamId == otherChamp ? 4 : 0,
                      secondTeamWins: finals.secondTeamId == otherChamp ? 4 : 0,
                    )
                  else
                    record.playoffSeries[i],
              ];
              final badRecord = SeasonHistoryRecord(
                seasonYear: record.seasonYear,
                seasonId: record.seasonId,
                championTeamId: otherChamp,
                regularSeasonStandings: record.regularSeasonStandings,
                playInOutcome: record.playInOutcome,
                playoffSeries: badSeries,
                archiveId: record.archiveId,
                archiveDigest: record.archiveDigest,
              );
              return _syntheticYear2Shell(current, badRecord);
            },
          ),
          throwsStateError,
        );
        expect(await storage.hasArchive(seasonYear: 1), isFalse);

        // Valid transition succeeds
        await controller.persistArchivedSeasonTransition(
          confirmed: true,
          buildNextCareer: _syntheticYear2Shell,
        );
        expect(controller.career!.currentYear, 2);

        // FIX 1: tamper active career's seasonHistory record while keeping valid archive SHA-256
        final realRecord = controller.career!.seasonHistory.first;
        final finals = realRecord.playoffSeries[14];
        final otherChamp = finals.winnerTeamId == finals.firstTeamId
            ? finals.secondTeamId
            : finals.firstTeamId;
        final badRecord = SeasonHistoryRecord(
          seasonYear: realRecord.seasonYear,
          seasonId: realRecord.seasonId,
          championTeamId: otherChamp,
          regularSeasonStandings: realRecord.regularSeasonStandings,
          playInOutcome: realRecord.playInOutcome,
          playoffSeries: [
            for (var i = 0; i < realRecord.playoffSeries.length; i++)
              if (i == 14)
                PlayoffSeriesSummary(
                  seriesIndex: 14,
                  round: finals.round,
                  firstTeamId: finals.firstTeamId,
                  secondTeamId: finals.secondTeamId,
                  winnerTeamId: otherChamp,
                  firstTeamWins: finals.firstTeamId == otherChamp ? 4 : 0,
                  secondTeamWins: finals.secondTeamId == otherChamp ? 4 : 0,
                )
              else
                realRecord.playoffSeries[i],
          ],
          archiveId: realRecord.archiveId,
          archiveDigest: realRecord.archiveDigest,
        );
        final tamperedCareer = controller.career!.copyWith(
          seasonHistory: [badRecord],
        );
        await storage.write(GmCareerCodec.encode(tamperedCareer));
        await controller.loadCareer();
        await expectLater(
          controller.loadSeasonArchive(1),
          throwsFormatException,
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'FIX 3 & FIX 7: import failure recovery, orphan reconciliation, and slot-scoped bundle export',
      () async {
        final storage = _FaultyArchiveFileStorage(directoryPath: tempDir.path);
        await storage.write(completedYear1Json, slot: 'slot-a');
        final controller = GmCareerController(storage: storage);
        await controller.loadCareer(slot: 'slot-a');
        await controller.persistArchivedSeasonTransition(
          confirmed: true,
          buildNextCareer: _syntheticYear2Shell,
          slot: 'slot-a',
        );
        final bundleA = await controller.exportCareerBundle(slot: 'slot-a');

        // FIX 7: exportCareerBundle(slot: 'slot-b') works even when in-memory _career is different/null
        final freshController = GmCareerController(storage: storage);
        await freshController.importCareerBundle(bundleA, slot: 'slot-b');
        // Load slot-a in memory, then export slot-b
        await freshController.loadCareer(slot: 'slot-a');
        final exportedFromB = await freshController.exportCareerBundle(
          slot: 'slot-b',
        );
        expect(exportedFromB, equals(bundleA));

        // FIX 3: failure BEFORE partial persistence preserves _career and draftRecoveryRequired == false
        final priorCareer = freshController.career!;
        await expectLater(
          freshController.importCareerBundle(
            '{"invalid":true}',
            slot: 'slot-c',
          ),
          throwsFormatException,
        );
        expect(freshController.career, same(priorCareer));
        expect(freshController.draftRecoveryRequired, isFalse);

        // FIX 3: failure AFTER archive write (during active save write) preserves _career, sets draftRecoveryRequired, and retry succeeds
        storage.failNextActiveWrite = true;
        await expectLater(
          freshController.importCareerBundle(bundleA, slot: 'slot-c'),
          throwsA(isA<GmCareerStorageException>()),
        );
        expect(freshController.career, same(priorCareer));
        expect(freshController.draftRecoveryRequired, isTrue);
        expect(await storage.hasArchive(seasonYear: 1, slot: 'slot-c'), isTrue);

        // Retry reconciles identical orphan archive and clears draftRecoveryRequired
        await freshController.importCareerBundle(bundleA, slot: 'slot-c');
        expect(freshController.draftRecoveryRequired, isFalse);
        expect(await storage.hasSave(slot: 'slot-c'), isTrue);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'FIX 4 & FIX 5: strict save-slot validation and .tmp archive recovery',
      () async {
        final storage = FileGmCareerStorage(directoryPath: tempDir.path);
        const invalidSlots = [
          '',
          ' ',
          '../escape',
          'a/b',
          r'a\b',
          'slot:1',
          'UpperCase',
          ' leading',
          'trailing ',
        ];
        for (final bad in invalidSlots) {
          expect(
            () => storage.resolvePath(bad),
            throwsA(isA<GmCareerStorageException>()),
          );
          expect(
            () => storage.resolveArchivePath(1, bad),
            throwsA(isA<GmCareerStorageException>()),
          );
          await expectLater(
            storage.hasSave(slot: bad),
            throwsA(isA<GmCareerStorageException>()),
          );
          await expectLater(
            storage.hasArchive(seasonYear: 1, slot: bad),
            throwsA(isA<GmCareerStorageException>()),
          );
          await expectLater(
            storage.read(slot: bad),
            throwsA(isA<GmCareerStorageException>()),
          );
          await expectLater(
            storage.write('{}', slot: bad),
            throwsA(isA<GmCareerStorageException>()),
          );
          await expectLater(
            storage.clear(slot: bad),
            throwsA(isA<GmCareerStorageException>()),
          );
        }

        // FIX 5: .tmp archive files are never promoted as authoritative
        final archive = SeasonArchive.fromCareer(completedYear1);
        final encoded = SeasonArchiveCodec.encodeWithDigest(archive);
        final archivePath = storage.resolveArchivePath(1, 'slot-tmp');
        final tmpFile = File('$archivePath.tmp');
        await tmpFile.parent.create(recursive: true);

        // 1. Incomplete .tmp without final archive
        await tmpFile.writeAsString('{"partial":');
        expect(
          await storage.hasArchive(seasonYear: 1, slot: 'slot-tmp'),
          isFalse,
        );
        expect(
          await storage.readArchive(seasonYear: 1, slot: 'slot-tmp'),
          isNull,
        );

        // 2. Complete .tmp without final archive is still not promoted by read/has
        await tmpFile.writeAsString(encoded.json);
        expect(
          await storage.hasArchive(seasonYear: 1, slot: 'slot-tmp'),
          isFalse,
        );
        expect(
          await storage.readArchive(seasonYear: 1, slot: 'slot-tmp'),
          isNull,
        );

        // 3. writeArchive replaces/cleans .tmp and promotes final archive
        await storage.writeArchive(
          seasonYear: 1,
          archiveJson: encoded.json,
          expectedDigest: encoded.digest,
          slot: 'slot-tmp',
        );
        expect(
          await storage.hasArchive(seasonYear: 1, slot: 'slot-tmp'),
          isTrue,
        );
        expect(await tmpFile.exists(), isFalse);

        // 4. Stale .tmp alongside valid final archive is cleaned up on idempotent writeArchive
        await tmpFile.writeAsString('{"stale":true}');
        await storage.writeArchive(
          seasonYear: 1,
          archiveJson: encoded.json,
          expectedDigest: encoded.digest,
          slot: 'slot-tmp',
        );
        expect(await tmpFile.exists(), isFalse);
        expect(
          await storage.readArchive(seasonYear: 1, slot: 'slot-tmp'),
          equals(encoded.json),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('M009-UX-T01D: production large-JSON isolate decode workers', () {
    test(
      'large career JSON takes the isolate path and decodes equivalently',
      () async {
        expect(
          completedYear1Json.length,
          greaterThan(kLargeJsonIsolateThresholdChars),
        );
        expect(
          shouldUseIsolateForLargeDecode(completedYear1Json.length),
          isTrue,
        );
        expect(
          await compute(validateCareerJsonWorker, completedYear1Json),
          isTrue,
        );
        final decoded = await compute(
          decodeCareerJsonWorker,
          completedYear1Json,
        );
        expect(GmCareerCodec.encode(decoded), completedYear1Json);
      },
      // JIT isolate decode of the full Season 1 save; 30 s default is too tight under suite load.
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'malformed career JSON is rejected and decode errors propagate',
      () async {
        final truncated = completedYear1Json.substring(
          0,
          completedYear1Json.length - 10,
        );
        expect(await compute(validateCareerJsonWorker, truncated), isFalse);
        expect(await compute(validateCareerJsonWorker, '   '), isFalse);
        await expectLater(
          compute(decodeCareerJsonWorker, truncated),
          throwsA(isA<FormatException>()),
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'archive decode-and-verify worker accepts genuine and rejects tampered',
      () async {
        final archive = SeasonArchive.fromCareer(completedYear1);
        final encoded = SeasonArchiveCodec.encodeWithDigest(archive);
        final record = archive.toHistoryRecord(encoded.digest);
        ArchiveDecodeVerifyRequest request(String json) =>
            ArchiveDecodeVerifyRequest(
              archiveJson: json,
              expectedDigest: encoded.digest,
              expectedCareerId: completedYear1.id,
              expectedSeasonYear: 1,
              expectedRecord: record,
            );
        final verified = await compute(
          decodeAndVerifyArchiveWorker,
          request(encoded.json),
        );
        expect(
          SeasonArchiveCodec.encodeWithDigest(verified).digest,
          encoded.digest,
        );
        await expectLater(
          compute(decodeAndVerifyArchiveWorker, request('${encoded.json} ')),
          throwsA(anything),
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'controller load and archive verification use workers on large saves',
      () async {
        final storage = FileGmCareerStorage(directoryPath: tempDir.path);
        await storage.write(completedYear1Json);
        final controller = GmCareerController(storage: storage);
        await controller.loadCareer();
        expect(controller.errorMessage, isNull);
        expect(GmCareerCodec.encode(controller.career!), completedYear1Json);
        await controller.persistArchivedSeasonTransition(
          confirmed: true,
          buildNextCareer: _syntheticYear2Shell,
        );
        final raw = await storage.readArchive(seasonYear: 1);
        expect(shouldUseIsolateForLargeDecode(raw!.length), isTrue);
        final archive = await controller.loadSeasonArchive(1);
        expect(archive.seasonYear, 1);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
