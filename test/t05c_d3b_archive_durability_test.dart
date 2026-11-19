import 'dart:convert';
import 'dart:io';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/domain_versions.dart' as domain_versions;

final class _ArchiveFaultFileOps implements CareerStorageFileOps {
  FileSystemException? Function(File file)? failOnExists;
  FileSystemException? Function(File file)? failOnRead;
  bool Function(File file)? failOnWrite;
  String? partialWriteBeforeFail;
  bool Function(File source, String newPath)? failOnRename;
  bool Function(File source, String newPath)? failOnCopy;
  String? partialCopyBeforeFail;
  bool Function(File file)? failOnDelete;
  int transientRenameErrorsRemaining = 0;

  @override
  Future<bool> exists(File file) async {
    final err = failOnExists?.call(file);
    if (err != null) throw err;
    return file.exists();
  }

  @override
  Future<int> length(File file) => file.length();

  @override
  Future<String> readAsString(File file) async {
    final err = failOnRead?.call(file);
    if (err != null) throw err;
    return file.readAsString();
  }

  @override
  Future<void> writeAsString(
    File file,
    String contents, {
    bool flush = false,
  }) async {
    if (failOnWrite?.call(file) == true) {
      if (partialWriteBeforeFail != null) {
        await file.writeAsString(partialWriteBeforeFail!, flush: flush);
      }
      throw FileSystemException('Injected write failure', file.path);
    }
    await file.writeAsString(contents, flush: flush);
  }

  @override
  Future<void> rename(File source, String newPath) async {
    if (transientRenameErrorsRemaining > 0) {
      transientRenameErrorsRemaining--;
      throw FileSystemException(
        'Transient sharing violation',
        source.path,
        const OSError('Sharing violation', 32),
      );
    }
    if (failOnRename?.call(source, newPath) == true) {
      throw FileSystemException(
        'Injected rename failure',
        source.path,
        const OSError('Access denied', 5),
      );
    }
    await source.rename(newPath);
  }

  @override
  Future<void> copy(File source, String newPath) async {
    if (failOnCopy?.call(source, newPath) == true) {
      if (partialCopyBeforeFail != null) {
        await File(newPath).writeAsString(partialCopyBeforeFail!, flush: true);
      }
      throw FileSystemException('Injected copy failure', source.path);
    }
    await source.copy(newPath);
  }

  @override
  Future<void> delete(File file) async {
    if (failOnDelete?.call(file) == true) {
      throw FileSystemException('Injected delete failure', file.path);
    }
    await file.delete();
  }

  @override
  Future<void> createParentDir(File file) =>
      file.parent.create(recursive: true);
}

GmCareer _buildCompletedSeason1({
  required String careerId,
  int seed = 20261028,
}) {
  final setup = const CareerSetupService().generate(
    CareerSetupRequest(
      selectedTeamId: const TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: seed,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: careerId);
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
  late GmCareer career1;
  late GmCareer career2;
  late SeasonArchive archive1;
  late SeasonArchive archive2;
  late ({String json, String digest}) encoded1;
  late ({String json, String digest}) encoded2;

  setUpAll(() {
    rootTempDir = Directory.systemTemp.createTempSync('t05c_d3b_archive_');
    career1 = _buildCompletedSeason1(careerId: 'd3b-arch-1', seed: 20261028);
    career2 = _buildCompletedSeason1(careerId: 'd3b-arch-2', seed: 20261028);
    archive1 = SeasonArchive.fromCareer(career1);
    archive2 = SeasonArchive.fromCareer(career2);
    encoded1 = SeasonArchiveCodec.encodeWithDigest(archive1);
    encoded2 = SeasonArchiveCodec.encodeWithDigest(archive2);
  });

  tearDownAll(() {
    try {
      if (rootTempDir.existsSync()) {
        rootTempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  FileGmCareerStorage makeStorage(
    String name, {
    CareerStorageFileOps? fileOps,
  }) {
    final dir = Directory('${rootTempDir.path}/$name')
      ..createSync(recursive: true);
    return FileGmCareerStorage(directoryPath: dir.path, fileOps: fileOps);
  }

  group('M009-T05C-C2-D3B-T02 Immutable Archive Durability', () {
    test(
      'Incoming archive validation rejects malformed payload even with matching digest',
      () async {
        final storage = makeStorage('incoming_validation');
        const malformed = '{"malformedArchive":true}';
        final digest = SeasonArchiveCodec.digestOf(malformed);

        await expectLater(
          storage.writeArchive(
            seasonYear: 1,
            archiveJson: malformed,
            expectedDigest: digest,
            slot: 's1',
          ),
          throwsA(isA<GmCareerStorageException>()),
        );
        expect(await storage.hasArchive(seasonYear: 1, slot: 's1'), isFalse);

        // Mismatched digest or seasonYear also rejected before disk mutation
        await expectLater(
          storage.writeArchive(
            seasonYear: 2,
            archiveJson: encoded1.json,
            expectedDigest: encoded1.digest,
            slot: 's1',
          ),
          throwsA(isA<GmCareerStorageException>()),
        );
        expect(await storage.hasArchive(seasonYear: 2, slot: 's1'), isFalse);
      },
    );

    test(
      'Valid matching archive is idempotent and valid conflicting archive is never overwritten or quarantined',
      () async {
        final storage = makeStorage('conflict_and_match');
        await storage.writeArchive(
          seasonYear: 1,
          archiveJson: encoded1.json,
          expectedDigest: encoded1.digest,
          slot: 's1',
        );
        // Stale .tmp alongside valid archive is cleaned up on idempotent retry
        final tmpFile = File('${storage.resolveArchivePath(1, 's1')}.tmp')
          ..writeAsStringSync('{"staleTmp":true');
        await storage.writeArchive(
          seasonYear: 1,
          archiveJson: encoded1.json,
          expectedDigest: encoded1.digest,
          slot: 's1',
        );
        expect(tmpFile.existsSync(), isFalse);
        expect(
          await storage.readArchive(seasonYear: 1, slot: 's1'),
          encoded1.json,
        );

        // Structurally valid conflicting archive (career2) is refused & preserved
        await expectLater(
          storage.writeArchive(
            seasonYear: 1,
            archiveJson: encoded2.json,
            expectedDigest: encoded2.digest,
            slot: 's1',
          ),
          throwsA(isA<GmCareerStorageException>()),
        );
        expect(
          await storage.readArchive(seasonYear: 1, slot: 's1'),
          encoded1.json,
        );
        final dir = Directory('${rootTempDir.path}/conflict_and_match');
        expect(
          dir.listSync().where((f) => f.path.contains('.corrupt.')),
          isEmpty,
        );
      },
    );

    test(
      'Corrupt partial archive is quarantined (collision-safe) and replaced; quarantine failure aborts safely',
      () async {
        final ops = _ArchiveFaultFileOps();
        final storage = makeStorage('corrupt_quarantine', fileOps: ops);
        final archivePath = storage.resolveArchivePath(1, 's1');
        File(archivePath).writeAsStringSync('{"truncatedArchive":');

        // 1. Quarantine failure aborts without touching corrupt evidence
        ops.failOnRename = (_, dst) => dst.contains('.corrupt.');
        ops.failOnCopy = (_, dst) => dst.contains('.corrupt.');
        await expectLater(
          storage.writeArchive(
            seasonYear: 1,
            archiveJson: encoded1.json,
            expectedDigest: encoded1.digest,
            slot: 's1',
          ),
          throwsA(isA<GmCareerStorageException>()),
        );
        expect(File(archivePath).readAsStringSync(), '{"truncatedArchive":');

        // 2. Quarantine succeeds, preserves original bytes, and promotes valid archive
        ops.failOnRename = null;
        ops.failOnCopy = null;
        await storage.writeArchive(
          seasonYear: 1,
          archiveJson: encoded1.json,
          expectedDigest: encoded1.digest,
          slot: 's1',
        );
        expect(
          await storage.readArchive(seasonYear: 1, slot: 's1'),
          encoded1.json,
        );
        final dir = Directory('${rootTempDir.path}/corrupt_quarantine');
        final quarantined = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.contains('.corrupt.'))
            .toList();
        expect(quarantined.length, 1);
        expect(quarantined.single.readAsStringSync(), '{"truncatedArchive":');
      },
    );

    test(
      'Interrupted staging, interrupted promotion, partial copy cleanup, and Windows lock retries',
      () async {
        // A-C. Partial staging write
        final opsA = _ArchiveFaultFileOps();
        final sA = makeStorage('interrupted_staging', fileOps: opsA);
        opsA.failOnWrite = (f) => f.path.endsWith('.tmp');
        opsA.partialWriteBeforeFail = '{"partial":';
        await expectLater(
          sA.writeArchive(
            seasonYear: 1,
            archiveJson: encoded1.json,
            expectedDigest: encoded1.digest,
          ),
          throwsA(isA<GmCareerStorageException>()),
        );
        expect(await sA.hasArchive(seasonYear: 1), isFalse);

        // D-F. Interrupted promotion & partial copy cleanup
        final opsD = _ArchiveFaultFileOps();
        final sD = makeStorage('interrupted_promotion', fileOps: opsD);
        opsD.failOnRename = (src, _) => src.path.endsWith('.tmp');
        opsD.failOnCopy = (src, _) => src.path.endsWith('.tmp');
        opsD.partialCopyBeforeFail = '{"halfCopied":';
        await expectLater(
          sD.writeArchive(
            seasonYear: 1,
            archiveJson: encoded1.json,
            expectedDigest: encoded1.digest,
          ),
          throwsA(isA<GmCareerStorageException>()),
        );
        expect(await sD.hasArchive(seasonYear: 1), isFalse);

        // Clean retry succeeds
        opsD.failOnRename = null;
        opsD.failOnCopy = null;
        await sD.writeArchive(
          seasonYear: 1,
          archiveJson: encoded1.json,
          expectedDigest: encoded1.digest,
        );
        expect(await sD.readArchive(seasonYear: 1), encoded1.json);

        // K-L. Transient Windows lock (32) succeeds; persistent lock fails
        final opsK = _ArchiveFaultFileOps();
        final sK = makeStorage('windows_lock', fileOps: opsK);
        opsK.transientRenameErrorsRemaining = 2;
        await sK.writeArchive(
          seasonYear: 1,
          archiveJson: encoded1.json,
          expectedDigest: encoded1.digest,
        );
        expect(await sK.readArchive(seasonYear: 1), encoded1.json);

        final opsL = _ArchiveFaultFileOps();
        final sL = makeStorage('persistent_lock', fileOps: opsL);
        opsL.transientRenameErrorsRemaining = 100;
        opsL.failOnCopy = (_, _) => true;
        await expectLater(
          sL.writeArchive(
            seasonYear: 1,
            archiveJson: encoded1.json,
            expectedDigest: encoded1.digest,
          ),
          throwsA(isA<GmCareerStorageException>()),
        );
        expect(await sL.hasArchive(seasonYear: 1), isFalse);
      },
    );

    test(
      'hasArchive distinguishes absent from IO errors and never swallows FileSystemException',
      () async {
        final ops = _ArchiveFaultFileOps();
        final storage = makeStorage('has_archive_errors', fileOps: ops);
        expect(await storage.hasArchive(seasonYear: 1), isFalse);

        ops.failOnExists = (f) => FileSystemException(
          'Permission denied',
          f.path,
          const OSError('Access denied', 5),
        );
        await expectLater(
          storage.hasArchive(seasonYear: 1),
          throwsA(
            isA<GmCareerStorageException>().having(
              (e) => e.cause,
              'cause',
              isA<FileSystemException>(),
            ),
          ),
        );

        ops.failOnExists = null;
        File(storage.resolveArchivePath(1)).writeAsStringSync('{"partial":');
        expect(await storage.hasArchive(seasonYear: 1), isTrue);
      },
    );

    test(
      'Cross-file rollover and bundle import preflight conflict protection & retry recovery',
      timeout: const Timeout(Duration(minutes: 4)),
      () async {
        final ops = _ArchiveFaultFileOps();
        final storage = makeStorage('rollover_and_bundle', fileOps: ops);
        const slotRoll = 'roll_slot';
        await storage.write(GmCareerCodec.encode(career1), slot: slotRoll);

        final ctrl = GmCareerController(storage: storage);
        try {
          await ctrl.loadCareer(slot: slotRoll);
          // Simulate interrupted archive promotion leaving corrupt archive on disk
          File(
            storage.resolveArchivePath(1, slotRoll),
          ).writeAsStringSync('{bad');

          // Rollover quarantines corrupt archive, writes valid archive, and publishes Year 2
          await ctrl.continueToNextSeason(confirmed: true, slot: slotRoll);
          expect(ctrl.career!.currentYear, 2);
          expect(ctrl.career!.seasonHistory.length, 1);
          expect(ctrl.career!.seasonSettlements.length, 1);
          expect(ctrl.career!.marketHistory.length, 1);
          expect(
            await storage.readArchive(seasonYear: 1, slot: slotRoll),
            encoded1.json,
          );

          final bundle1 = await ctrl.exportCareerBundle(slot: slotRoll);

          // Bundle preflight rejects conflicting valid archive BEFORE writing anything
          const conflictSlot = 'bundle_conflict_slot';
          await storage.writeArchive(
            seasonYear: 1,
            archiveJson: encoded2.json,
            expectedDigest: encoded2.digest,
            slot: conflictSlot,
          );
          await expectLater(
            ctrl.importCareerBundle(bundle1, slot: conflictSlot),
            throwsA(isA<GmCareerStorageException>()),
          );
          expect(ctrl.draftRecoveryRequired, isFalse);
          expect(
            await storage.readArchive(seasonYear: 1, slot: conflictSlot),
            encoded2.json,
          );

          // Bundle import into slot with corrupt partial archive quarantines & succeeds
          const corruptBundleSlot = 'bundle_corrupt_slot';
          File(storage.resolveArchivePath(1, corruptBundleSlot))
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('{"corruptBundleArchive":');
          await ctrl.importCareerBundle(bundle1, slot: corruptBundleSlot);
          expect(ctrl.career!.id, career1.id);
          expect(
            await storage.readArchive(seasonYear: 1, slot: corruptBundleSlot),
            encoded1.json,
          );
        } finally {
          ctrl.dispose();
        }
      },
    );
  });
}
