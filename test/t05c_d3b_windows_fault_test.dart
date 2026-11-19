import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/domain_versions.dart' as domain_versions;

GmCareer _buildCompletedSeason1({required String careerId}) {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: 20261028,
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

Future<void> _killProcessAndWorker(Process process, Directory caseDir) async {
  final pidFile = File('${caseDir.path}/worker.pid');
  if (pidFile.existsSync()) {
    final workerPid = int.tryParse(pidFile.readAsStringSync().trim());
    if (workerPid != null) {
      try {
        Process.killPid(workerPid, ProcessSignal.sigkill);
      } catch (_) {}
    }
  }
  try {
    process.kill(ProcessSignal.sigkill);
  } catch (_) {}
  await process.exitCode.timeout(
    const Duration(seconds: 10),
    onTimeout: () => -1,
  );
}

Future<void> _runCrashScenario({
  required Directory caseDir,
  required String scenario,
  void Function()? beforeKillVerify,
}) async {
  final process = await Process.start(
    'flutter',
    ['test', '--no-pub', 'test/support/t05c_d3b_crash_worker.dart'],
    runInShell: Platform.isWindows,
    environment: {
      'D3B_CRASH_DIR': caseDir.path,
      'D3B_CRASH_SCENARIO': scenario,
    },
  );
  final stdoutBuf = StringBuffer();
  final stderrBuf = StringBuffer();
  process.stdout.transform(utf8.decoder).listen(stdoutBuf.write);
  process.stderr.transform(utf8.decoder).listen(stderrBuf.write);

  try {
    final readyFile = File('${caseDir.path}/checkpoint.ready');
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    while (!readyFile.existsSync()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'Timed out waiting for checkpoint $scenario.\n'
          'stdout: $stdoutBuf\nstderr: $stderrBuf',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(readyFile.readAsStringSync().trim(), scenario);
    beforeKillVerify?.call();
  } finally {
    await _killProcessAndWorker(process, caseDir);
  }
}

void main() {
  late Directory rootTempDir;
  late GmCareer careerA;
  late GmCareer careerB;
  late String jsonA;
  late String jsonB;
  late GmCareer completedY1;
  late ({String json, String digest}) encodedArchive1;

  setUpAll(() {
    rootTempDir = Directory.systemTemp.createTempSync('t05c_d3b_win_fault_');
    final setup = const CareerSetupService().generate(
      const CareerSetupRequest(
        selectedTeamId: TeamId('team-1'),
        selectedSituation: FranchiseSituation.tanking,
        seed: 20261028,
      ),
    );
    careerA = GmCareer.fromSetupResult(setup, id: 'd3b-win-a');
    careerB = const DraftExecutionService().startDraft(careerA);
    jsonA = GmCareerCodec.encode(careerA);
    jsonB = GmCareerCodec.encode(careerB);

    completedY1 = _buildCompletedSeason1(careerId: 'd3b-win-rollover');
    encodedArchive1 = SeasonArchiveCodec.encodeWithDigest(
      SeasonArchive.fromCareer(completedY1),
    );
  });

  tearDownAll(() {
    try {
      if (rootTempDir.existsSync()) {
        rootTempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Directory makeCaseDir(String name) =>
      Directory('${rootTempDir.path}/$name')..createSync(recursive: true);

  group('M009-T05C-C2-D3B-T03 Real Windows Lock & Crash Validation', () {
    test(
      'Real Windows RandomAccessFile contention probe across active, .bak, .tmp, archive, and archive .tmp',
      skip: !Platform.isWindows,
      () async {
        final dir = makeCaseDir('win_locks');
        final storage = FileGmCareerStorage(directoryPath: dir.path);
        await storage.write(jsonA);

        // Probe A: Active career file held open with FileMode.append + exclusive lock
        final activeFile = File(storage.resolvePath());
        final rafActive = activeFile.openSync(mode: FileMode.append);
        rafActive.lockSync(FileLock.exclusive);
        var activeBlocked = false;
        try {
          await storage.write(jsonB);
        } on GmCareerStorageException catch (e) {
          activeBlocked = true;
          final fsErr = e.cause is FileSystemException
              ? (e.cause as FileSystemException).osError?.errorCode
              : null;
          // ignore: avoid_print
          print(
            '[D3B-T03] Active file lock blocked write: osError=$fsErr, msg=$e',
          );
        } finally {
          rafActive.unlockSync();
          rafActive.closeSync();
        }
        // ignore: avoid_print
        print('[D3B-T03] Active file RandomAccessFile blocked=$activeBlocked');
        if (activeBlocked) {
          // Verify previous careerA remains recoverable after persistent lock
          final ctrl = GmCareerController(storage: storage);
          try {
            await ctrl.loadCareer();
            expect(ctrl.career!.id, careerA.id);
          } finally {
            ctrl.dispose();
          }
        }

        // Probe D: Archive destination file held open with FileMode.append + exclusive lock
        final dirArch = makeCaseDir('win_lock_archive');
        final archStorage = FileGmCareerStorage(directoryPath: dirArch.path);
        final archPath = archStorage.resolveArchivePath(1);
        File(archPath).writeAsStringSync('{"corruptPartial":');
        final rafArch = File(archPath).openSync(mode: FileMode.append);
        rafArch.lockSync(FileLock.exclusive);
        var archBlocked = false;
        try {
          await archStorage.writeArchive(
            seasonYear: 1,
            archiveJson: encodedArchive1.json,
            expectedDigest: encodedArchive1.digest,
          );
        } on GmCareerStorageException catch (e) {
          archBlocked = true;
          // ignore: avoid_print
          print('[D3B-T03] Archive quarantine lock blocked write: msg=$e');
        } finally {
          rafArch.unlockSync();
          rafArch.closeSync();
        }
        // ignore: avoid_print
        print('[D3B-T03] Archive file RandomAccessFile blocked=$archBlocked');

        // Probe E: Archive .tmp file held open with exclusive lock
        final dirArchTmp = makeCaseDir('win_lock_archive_tmp');
        final archTmpStorage = FileGmCareerStorage(
          directoryPath: dirArchTmp.path,
        );
        final archTmpPath = '${archTmpStorage.resolveArchivePath(1)}.tmp';
        File(archTmpPath).writeAsStringSync('{"lockedTmp":');
        final rafArchTmp = File(archTmpPath).openSync(mode: FileMode.append);
        rafArchTmp.lockSync(FileLock.exclusive);
        var archTmpBlocked = false;
        try {
          await archTmpStorage.writeArchive(
            seasonYear: 1,
            archiveJson: encodedArchive1.json,
            expectedDigest: encodedArchive1.digest,
          );
        } on GmCareerStorageException catch (e) {
          archTmpBlocked = true;
          // ignore: avoid_print
          print('[D3B-T03] Archive .tmp lock blocked write: msg=$e');
        } finally {
          rafArchTmp.unlockSync();
          rafArchTmp.closeSync();
        }
        // ignore: avoid_print
        print(
          '[D3B-T03] Archive .tmp RandomAccessFile blocked=$archTmpBlocked',
        );

        // Probe F1: Active .tmp locked during writeAsString -> fails cleanly, careerA intact
        final dirTransient = makeCaseDir('win_transient_lock');
        final sTransient = FileGmCareerStorage(
          directoryPath: dirTransient.path,
        );
        await sTransient.write(jsonA);
        final tmpPath = '${sTransient.resolvePath()}.tmp';
        File(tmpPath).writeAsStringSync('{"stale":');
        final rafTransient = File(tmpPath).openSync(mode: FileMode.append);
        rafTransient.lockSync(FileLock.exclusive);
        var activeTmpBlocked = false;
        try {
          await sTransient.write(jsonB);
        } on GmCareerStorageException {
          activeTmpBlocked = true;
        } finally {
          rafTransient.unlockSync();
          rafTransient.closeSync();
        }
        expect(activeTmpBlocked, isTrue);
        expect(GmCareerCodec.decode((await sTransient.read())!).id, careerA.id);

        // Probe F2: Real Windows transient lock on archive .tmp released within
        // _withTransientRetry window (35ms < 105ms) -> retry succeeds
        final dirArchTrans = makeCaseDir('win_transient_archive_tmp');
        final sArchTrans = FileGmCareerStorage(
          directoryPath: dirArchTrans.path,
        );
        final archTransTmp = '${sArchTrans.resolveArchivePath(1)}.tmp';
        File(archTransTmp).writeAsStringSync('{"stale":');
        final rafArchTrans = File(archTransTmp).openSync(mode: FileMode.append);
        rafArchTrans.lockSync(FileLock.exclusive);
        Timer(const Duration(milliseconds: 35), () {
          try {
            rafArchTrans.unlockSync();
            rafArchTrans.closeSync();
          } catch (_) {}
        });
        await sArchTrans.writeArchive(
          seasonYear: 1,
          archiveJson: encodedArchive1.json,
          expectedDigest: encodedArchive1.digest,
        );
        expect(
          await sArchTrans.readArchive(seasonYear: 1),
          encodedArchive1.json,
        );
      },
    );

    test(
      'Subprocess termination: Active save crashes (after temp flush, after active->bak, after promote)',
      timeout: const Timeout(Duration(minutes: 4)),
      () async {
        // A. Crash after temp flush (before active displaced)
        final dirA = makeCaseDir('crash_active_temp_flush');
        final saveDirA = Directory('${dirA.path}/save')..createSync();
        final sA = FileGmCareerStorage(directoryPath: saveDirA.path);
        await sA.write(jsonA);
        await File('${dirA.path}/career_b.json').writeAsString(jsonB);
        await _runCrashScenario(
          caseDir: dirA,
          scenario: 'after_active_temp_flush',
        );
        final ctrlA = GmCareerController(storage: sA);
        try {
          await ctrlA.loadCareer();
          expect(ctrlA.career!.id, careerA.id);
          expect(ctrlA.career!.draftExecutionState.isNotStarted, isTrue);
        } finally {
          ctrlA.dispose();
        }

        // B. Crash after active->bak (before tmp->active)
        final dirB = makeCaseDir('crash_active_to_bak');
        final saveDirB = Directory('${dirB.path}/save')..createSync();
        final sB = FileGmCareerStorage(directoryPath: saveDirB.path);
        await sB.write(jsonA);
        await File('${dirB.path}/career_b.json').writeAsString(jsonB);
        await _runCrashScenario(
          caseDir: dirB,
          scenario: 'after_active_to_bak',
          beforeKillVerify: () {
            expect(File('${sB.resolvePath()}.bak').existsSync(), isTrue);
            expect(File('${sB.resolvePath()}.tmp').existsSync(), isTrue);
          },
        );
        final ctrlB = GmCareerController(storage: sB);
        try {
          await ctrlB.loadCareer();
          expect(ctrlB.career!.id, careerA.id);
          expect(ctrlB.career!.draftExecutionState.isNotStarted, isTrue);
        } finally {
          ctrlB.dispose();
        }

        // D. Crash after tmp->active promote (before .bak delete)
        final dirD = makeCaseDir('crash_active_after_promote');
        final saveDirD = Directory('${dirD.path}/save')..createSync();
        final sD = FileGmCareerStorage(directoryPath: saveDirD.path);
        await sD.write(jsonA);
        await File('${dirD.path}/career_b.json').writeAsString(jsonB);
        await _runCrashScenario(
          caseDir: dirD,
          scenario: 'after_active_promote_before_bak_delete',
          beforeKillVerify: () {
            expect(File(sD.resolvePath()).existsSync(), isTrue);
            expect(File('${sD.resolvePath()}.bak').existsSync(), isTrue);
          },
        );
        final ctrlD = GmCareerController(storage: sD);
        try {
          await ctrlD.loadCareer();
          // Valid active (careerB) wins over stale .bak (careerA)
          expect(ctrlD.career!.draftExecutionState.isNotStarted, isFalse);
        } finally {
          ctrlD.dispose();
        }
      },
    );

    test(
      'Subprocess termination: Archive crashes (temp flush, promote, corrupt quarantine) + rollover & bundle recovery',
      timeout: const Timeout(Duration(minutes: 5)),
      () async {
        // Archive A: Crash after archive temp flush
        final dirArchA = makeCaseDir('crash_archive_temp_flush');
        Directory('${dirArchA.path}/save').createSync();
        final sArchA = FileGmCareerStorage(
          directoryPath: '${dirArchA.path}/save',
        );
        await File(
          '${dirArchA.path}/archive_1.json',
        ).writeAsString(encodedArchive1.json);
        await _runCrashScenario(
          caseDir: dirArchA,
          scenario: 'after_archive_temp_flush',
        );
        expect(await sArchA.hasArchive(seasonYear: 1), isFalse);
        await sArchA.writeArchive(
          seasonYear: 1,
          archiveJson: encodedArchive1.json,
          expectedDigest: encodedArchive1.digest,
        );
        expect(await sArchA.readArchive(seasonYear: 1), encodedArchive1.json);

        // Archive D: Crash after corrupt archive quarantine (before replacement promote)
        final dirArchD = makeCaseDir('crash_archive_quarantine');
        Directory('${dirArchD.path}/save').createSync();
        final sArchD = FileGmCareerStorage(
          directoryPath: '${dirArchD.path}/save',
        );
        File(sArchD.resolveArchivePath(1)).writeAsStringSync('{"corrupt":');
        await File(
          '${dirArchD.path}/archive_1.json',
        ).writeAsString(encodedArchive1.json);
        await _runCrashScenario(
          caseDir: dirArchD,
          scenario: 'after_archive_quarantine_before_promote',
        );
        expect(await sArchD.hasArchive(seasonYear: 1), isFalse);
        await sArchD.writeArchive(
          seasonYear: 1,
          archiveJson: encodedArchive1.json,
          expectedDigest: encodedArchive1.digest,
        );
        expect(await sArchD.readArchive(seasonYear: 1), encodedArchive1.json);

        // Cross-file rollover crash after archive write (before Year 2 active write)
        final dirRoll = makeCaseDir('crash_rollover');
        Directory('${dirRoll.path}/save').createSync();
        final sRoll = FileGmCareerStorage(
          directoryPath: '${dirRoll.path}/save',
        );
        await sRoll.write(GmCareerCodec.encode(completedY1));
        await _runCrashScenario(
          caseDir: dirRoll,
          scenario: 'rollover_after_archive_before_active',
        );
        final ctrlRoll = GmCareerController(storage: sRoll);
        try {
          await ctrlRoll.loadCareer();
          expect(ctrlRoll.career!.currentYear, 1);
          expect(await sRoll.hasArchive(seasonYear: 1), isTrue);

          await ctrlRoll.continueToNextSeason(confirmed: true);
          expect(ctrlRoll.career!.currentYear, 2);
          expect(ctrlRoll.career!.seasonHistory.length, 1);
          expect(ctrlRoll.career!.seasonSettlements.length, 1);
          expect(ctrlRoll.career!.marketHistory.length, 1);

          // Bundle import interruption & retry
          final bundleJson = await ctrlRoll.exportCareerBundle();
          final dirBundle = makeCaseDir('crash_bundle');
          Directory('${dirBundle.path}/save').createSync();
          final sBundle = FileGmCareerStorage(
            directoryPath: '${dirBundle.path}/save',
          );
          await File('${dirBundle.path}/bundle.json').writeAsString(bundleJson);
          await _runCrashScenario(
            caseDir: dirBundle,
            scenario: 'bundle_after_first_archive',
          );
          expect(
            await sBundle.hasArchive(seasonYear: 1, slot: 'bundle_slot'),
            isTrue,
          );
          expect(await sBundle.hasSave(slot: 'bundle_slot'), isFalse);

          final ctrlBundle = GmCareerController(storage: sBundle);
          try {
            await ctrlBundle.importCareerBundle(
              bundleJson,
              slot: 'bundle_slot',
            );
            expect(ctrlBundle.career!.currentYear, 2);
            expect(
              (await ctrlBundle.loadSeasonArchive(
                1,
                slot: 'bundle_slot',
              )).seasonYear,
              1,
            );
          } finally {
            ctrlBundle.dispose();
          }
        } finally {
          ctrlRoll.dispose();
        }
      },
    );
  });
}
