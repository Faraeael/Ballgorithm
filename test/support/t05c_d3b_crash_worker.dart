import 'dart:convert';
import 'dart:io';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/domain_versions.dart' as domain_versions;

final class _CheckpointFileOps implements CareerStorageFileOps {
  _CheckpointFileOps({required this.signalDir, required this.checkpoint});

  final String signalDir;
  final String checkpoint;
  bool _triggered = false;

  Future<void> _pauseAtCheckpoint(String name) async {
    if (_triggered || checkpoint != name) return;
    _triggered = true;
    final ready = File('$signalDir/checkpoint.ready');
    await ready.writeAsString(name, flush: true);
    // Block until parent terminates this child process.
    while (!File('$signalDir/resume.go').existsSync()) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  @override
  Future<bool> exists(File file) => file.exists();

  @override
  Future<int> length(File file) => file.length();

  @override
  Future<String> readAsString(File file) => file.readAsString();

  @override
  Future<void> writeAsString(
    File file,
    String contents, {
    bool flush = false,
  }) async {
    await file.writeAsString(contents, flush: flush);
    if (file.path.endsWith('ballgorithm_gm_career.json.tmp')) {
      await _pauseAtCheckpoint('after_active_temp_flush');
    } else if (file.path.contains('_archive_y') &&
        file.path.endsWith('.json.tmp')) {
      await _pauseAtCheckpoint('after_archive_temp_flush');
    }
  }

  @override
  Future<void> rename(File source, String newPath) async {
    await source.rename(newPath);
    if (newPath.endsWith('ballgorithm_gm_career.json.bak')) {
      await _pauseAtCheckpoint('after_active_to_bak');
    } else if (newPath.endsWith('ballgorithm_gm_career.json') &&
        source.path.endsWith('.tmp')) {
      await _pauseAtCheckpoint('after_active_promote_before_bak_delete');
    } else if (newPath.contains('_archive_y') &&
        newPath.contains('.corrupt.')) {
      await _pauseAtCheckpoint('after_archive_quarantine_before_promote');
    } else if (newPath.contains('_archive_y') && newPath.endsWith('.json')) {
      await _pauseAtCheckpoint(
        checkpoint == 'rollover_after_archive_before_active' ||
                checkpoint == 'bundle_after_first_archive'
            ? checkpoint
            : 'after_archive_promote_before_tmp_delete',
      );
    }
  }

  @override
  Future<void> copy(File source, String newPath) async {
    await source.copy(newPath);
    if (newPath.endsWith('ballgorithm_gm_career.json.bak')) {
      await _pauseAtCheckpoint('after_active_to_bak');
    } else if (newPath.endsWith('ballgorithm_gm_career.json') &&
        source.path.endsWith('.tmp')) {
      await _pauseAtCheckpoint('after_active_promote_before_bak_delete');
    } else if (newPath.contains('_archive_y') &&
        newPath.contains('.corrupt.')) {
      await _pauseAtCheckpoint('after_archive_quarantine_before_promote');
    } else if (newPath.contains('_archive_y') && newPath.endsWith('.json')) {
      await _pauseAtCheckpoint(
        checkpoint == 'rollover_after_archive_before_active' ||
                checkpoint == 'bundle_after_first_archive'
            ? checkpoint
            : 'after_archive_promote_before_tmp_delete',
      );
    }
  }

  @override
  Future<void> delete(File file) => file.delete();

  @override
  Future<void> createParentDir(File file) =>
      file.parent.create(recursive: true);
}

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

void main() {
  final testDir = Platform.environment['D3B_CRASH_DIR'];
  final scenario = Platform.environment['D3B_CRASH_SCENARIO'];
  if (testDir == null || scenario == null) {
    // Only executed when invoked as an isolated crash worker subprocess.
    test('D3B crash worker idle guard', () {
      expect(true, isTrue);
    });
    return;
  }

  test(
    'D3B crash worker ($scenario)',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      await File('$testDir/worker.pid').writeAsString('$pid', flush: true);
      final fileOps = _CheckpointFileOps(
        signalDir: testDir,
        checkpoint: scenario,
      );
      final storage = FileGmCareerStorage(
        directoryPath: '$testDir/save',
        fileOps: fileOps,
      );

      if (scenario == 'after_active_temp_flush' ||
          scenario == 'after_active_to_bak' ||
          scenario == 'after_active_promote_before_bak_delete') {
        final jsonB = await File('$testDir/career_b.json').readAsString();
        await storage.write(jsonB);
      } else if (scenario == 'after_archive_temp_flush' ||
          scenario == 'after_archive_promote_before_tmp_delete' ||
          scenario == 'after_archive_quarantine_before_promote') {
        final archiveJson = await File(
          '$testDir/archive_1.json',
        ).readAsString();
        final digest = SeasonArchiveCodec.digestOf(archiveJson);
        await storage.writeArchive(
          seasonYear: 1,
          archiveJson: archiveJson,
          expectedDigest: digest,
        );
      } else if (scenario == 'rollover_after_archive_before_active') {
        final ops = _CheckpointFileOps(
          signalDir: testDir,
          checkpoint: 'rollover_after_archive_before_active',
        );
        final ctrl2 = GmCareerController(
          storage: FileGmCareerStorage(
            directoryPath: '$testDir/save',
            fileOps: ops,
          ),
        );
        await ctrl2.loadCareer();
        await ctrl2.continueToNextSeason(confirmed: true);
      } else if (scenario == 'bundle_after_first_archive') {
        final bundleJson = await File('$testDir/bundle.json').readAsString();
        final ops = _CheckpointFileOps(
          signalDir: testDir,
          checkpoint: 'bundle_after_first_archive',
        );
        final ctrl = GmCareerController(
          storage: FileGmCareerStorage(
            directoryPath: '$testDir/save',
            fileOps: ops,
          ),
        );
        await ctrl.importCareerBundle(bundleJson, slot: 'bundle_slot');
      } else if (scenario == 'hold_lock') {
        final lockPath = Platform.environment['D3B_LOCK_PATH']!;
        final raf = File(lockPath).openSync(mode: FileMode.append);
        raf.lockSync(FileLock.exclusive);
        await File('$testDir/lock.ready').writeAsString('locked', flush: true);
        while (!File('$testDir/release.lock').existsSync()) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        raf.unlockSync();
        raf.closeSync();
      } else {
        // Fallback: build completed season 1 if requested.
        _buildCompletedSeason1(careerId: 'unused');
      }
    },
  );
}
