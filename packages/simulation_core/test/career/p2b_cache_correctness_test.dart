import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/domain_versions.dart' as domain_versions;
import 'package:test/test.dart';

({
  GmCareer career,
  String leagueJson,
  String snapshotId,
  String templateJson,
  RegularSeasonGameResult Function({
    required String gameId,
    required String seasonId,
    required int seasonYear,
    required TeamId homeTeamId,
    required TeamId awayTeamId,
    required int gameSeed,
    String? overrideFingerprint,
    String? overrideSnapshotId,
    String? overrideTemplateJson,
    int? overrideHomeScore,
  })
  buildResult,
})
_buildPlayoffFixture() {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: 20261028,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 'p2b-cache-test');
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

  var sampleTemplate = '';

  RegularSeasonGameResult buildResult({
    required String gameId,
    required String seasonId,
    required int seasonYear,
    required TeamId homeTeamId,
    required TeamId awayTeamId,
    required int gameSeed,
    String? overrideFingerprint,
    String? overrideSnapshotId,
    String? overrideTemplateJson,
    int? overrideHomeScore,
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
    final templateJson = overrideTemplateJson ?? jsonEncode(payload);
    if (sampleTemplate.isEmpty) sampleTemplate = templateJson;
    final idx =
        templateJson.indexOf('"league":$markerJson') + '"league":'.length;
    final canonicalJson = templateJson.replaceRange(
      idx,
      idx + markerJson.length,
      leagueJson,
    );
    final fp =
        overrideFingerprint ??
        sha256.convert(utf8.encode(canonicalJson)).toString();
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
        leagueSnapshotId: overrideSnapshotId ?? snapshotId,
        payloadTemplateJson: templateJson,
      ),
      periodsPlayed: 4,
      summary: SeasonGameSummary(
        homeScore: overrideHomeScore ?? 104,
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
        gameId: f.id,
        seasonId: rs0.seasonId,
        seasonYear: rs0.seasonYear,
        homeTeamId: f.homeTeamId,
        awayTeamId: f.awayTeamId,
        gameSeed: f.gameSeed,
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
      gameId: fix.id,
      seasonId: pi.seasonId,
      seasonYear: pi.seasonYear,
      homeTeamId: fix.homeTeamId,
      awayTeamId: fix.awayTeamId,
      gameSeed: fix.gameSeed,
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
  c = const PlayoffSlateService().simulateNextSlate(c);
  return (
    career: c,
    leagueJson: leagueJson,
    snapshotId: snapshotId,
    templateJson: sampleTemplate,
    buildResult: buildResult,
  );
}

void main() {
  late ({
    GmCareer career,
    String leagueJson,
    String snapshotId,
    String templateJson,
    RegularSeasonGameResult Function({
      required String gameId,
      required String seasonId,
      required int seasonYear,
      required TeamId homeTeamId,
      required TeamId awayTeamId,
      required int gameSeed,
      String? overrideFingerprint,
      String? overrideSnapshotId,
      String? overrideTemplateJson,
      int? overrideHomeScore,
    })
    buildResult,
  })
  fx;

  setUpAll(() {
    fx = _buildPlayoffFixture();
  });

  group('M009-PERF-P2B: Expando cache & lazy snapshot safety', () {
    test(
      'deep immutability prevents post-validation mutation of cached results',
      () {
        final poResult = fx.career.playoffState!.gameResults.values.first;
        expect(
          () => poResult.summary.playerLines['x'] =
              poResult.summary.playerLines.values.first,
          throwsUnsupportedError,
        );
        expect(
          () => poResult.summary.periodScoresHome['Q1'] = 99,
          throwsUnsupportedError,
        );
        expect(
          () => fx.career.playoffState!.gameResults['x'] = poResult,
          throwsUnsupportedError,
        );
        expect(
          () => fx.career.playoffState!.gameInputSnapshots['x'] = '{}',
          throwsUnsupportedError,
        );
        expect(
          () => fx.career.playInState!.gameResults['x'] = poResult,
          throwsUnsupportedError,
        );
        expect(
          () => fx.career.playInState!.gameInputSnapshots['x'] = '{}',
          throwsUnsupportedError,
        );
      },
    );

    test('rejects changed historical snapshot JSON (warm & cold)', () {
      final decoded = GmCareerCodec.decode(GmCareerCodec.encode(fx.career));
      decoded.validate(); // warm caches

      final modifiedJson =
          '${fx.leagueJson.substring(0, fx.leagueJson.length - 1)},"extra":1}';
      final po = decoded.playoffState!;
      expect(
        () => decoded.copyWith(
          playoffState: PlayoffState.fromJson({
            ...po.toJson(),
            'gameInputSnapshots': {fx.snapshotId: modifiedJson},
          }),
        ),
        throwsFormatException,
      );
    });

    test('rejects incorrect snapshot digest (warm & cold)', () {
      final badDigest = List.filled(64, 'b').join();
      final rs = fx.career.regularSeasonState!;
      final firstEntry = rs.gameResults.entries.first;
      final badResult = fx.buildResult(
        gameId: firstEntry.value.fixtureId,
        seasonId: rs.seasonId,
        seasonYear: rs.seasonYear,
        homeTeamId: firstEntry.value.homeTeamId,
        awayTeamId: firstEntry.value.awayTeamId,
        gameSeed: firstEntry.value.gameSeed,
        overrideSnapshotId: badDigest,
      );
      expect(
        () => fx.career.copyWith(
          regularSeasonState: rs.copyWith(
            gameResults: {...rs.gameResults, firstEntry.key: badResult},
            gameInputSnapshots: {badDigest: fx.leagueJson},
          ),
        ),
        throwsFormatException,
      );
    });

    test('rejects changed game result/box score and changed evidence', () {
      final po = fx.career.playoffState!;
      final firstEntry = po.gameResults.entries.first;
      final g = firstEntry.value;

      final badBox = fx.buildResult(
        gameId: g.fixtureId,
        seasonId: g.seasonId,
        seasonYear: g.seasonYear,
        homeTeamId: g.homeTeamId,
        awayTeamId: g.awayTeamId,
        gameSeed: g.gameSeed,
        overrideHomeScore: 999,
      );
      expect(
        () => fx.career.copyWith(
          playoffState: PlayoffState.fromJson({
            ...po.toJson(),
            'gameResults': {
              for (final e in po.gameResults.entries)
                e.key: (e.key == firstEntry.key ? badBox : e.value).toJson(),
            },
          }),
        ),
        throwsFormatException,
      );

      final badEvidence = fx.buildResult(
        gameId: g.fixtureId,
        seasonId: g.seasonId,
        seasonYear: g.seasonYear,
        homeTeamId: g.homeTeamId,
        awayTeamId: g.awayTeamId,
        gameSeed: g.gameSeed,
        overrideTemplateJson: '${g.inputEvidence!.payloadTemplateJson} ',
      );
      expect(
        () => fx.career.copyWith(
          playoffState: PlayoffState.fromJson({
            ...po.toJson(),
            'gameResults': {
              for (final e in po.gameResults.entries)
                e.key: (e.key == firstEntry.key ? badEvidence : e.value)
                    .toJson(),
            },
          }),
        ),
        throwsFormatException,
      );
    });

    test(
      'rejects changed fixture identity/seed and invalid Play-In/Playoff results',
      () {
        final pi = fx.career.playInState!;
        final piFirst = pi.gameResults.entries.first;
        final piRes = piFirst.value;

        // Tampered gameSeed on Play-In result
        final badSeedPi = fx.buildResult(
          gameId: piRes.fixtureId,
          seasonId: piRes.seasonId,
          seasonYear: piRes.seasonYear,
          homeTeamId: piRes.homeTeamId,
          awayTeamId: piRes.awayTeamId,
          gameSeed: piRes.gameSeed + 1,
        );
        expect(
          () => fx.career.copyWith(
            playInState: PlayInState.fromJson({
              ...pi.toJson(),
              'gameResults': {
                for (final e in pi.gameResults.entries)
                  e.key: (e.key == piFirst.key ? badSeedPi : e.value).toJson(),
              },
            }),
          ),
          throwsFormatException,
        );

        // Tampered fingerprint on Playoff result
        final po = fx.career.playoffState!;
        final poFirst = po.gameResults.entries.first;
        final poRes = poFirst.value;
        final badFpPo = fx.buildResult(
          gameId: poRes.fixtureId,
          seasonId: poRes.seasonId,
          seasonYear: poRes.seasonYear,
          homeTeamId: poRes.homeTeamId,
          awayTeamId: poRes.awayTeamId,
          gameSeed: poRes.gameSeed,
          overrideFingerprint: List.filled(64, 'c').join(),
        );
        expect(
          () => fx.career.copyWith(
            playoffState: PlayoffState.fromJson({
              ...po.toJson(),
              'gameResults': {
                for (final e in po.gameResults.entries)
                  e.key: (e.key == poFirst.key ? badFpPo : e.value).toJson(),
              },
            }),
          ),
          throwsFormatException,
        );
      },
    );

    test(
      'rejects previously validated result reused under changed dependencies',
      () {
        // Ensure fx.career's results are warm in Expando caches
        fx.career.validate();
        final warmPoResult = fx.career.playoffState!.gameResults.values.first;
        final warmPiResult = fx.career.playInState!.gameResults.values.first;

        // Reuse warm Playoff result under a different seasonId
        final po = fx.career.playoffState!;
        expect(
          () =>
              PlayoffState.fromJson({
                ...po.toJson(),
                'seasonId': 'other-season',
                'gameResults': {warmPoResult.fixtureId: warmPoResult.toJson()},
              }).validate(
                regularSeason: fx.career.regularSeasonState!,
                playIn: fx.career.playInState!,
              ),
          throwsFormatException,
        );

        // Reuse warm Play-In result under modified openingTeams
        final rs = fx.career.regularSeasonState!;
        final renamedOpening = [
          RegularSeasonTeamIdentity(
            teamId: const TeamId('team-999'),
            name: rs.openingTeams.first.name,
            abbreviation: rs.openingTeams.first.abbreviation,
          ),
          ...rs.openingTeams.skip(1),
        ];
        expect(
          () => fx.career.playInState!.validate(
            regularSeasonState: RegularSeasonState(
              seasonId: rs.seasonId,
              seasonYear: rs.seasonYear,
              scheduleSeed: rs.scheduleSeed,
              openingTeams: renamedOpening,
              gameResults: rs.gameResults,
              gameInputSnapshots: rs.gameInputSnapshots,
              schedule: rs.schedule,
            ),
          ),
          throwsFormatException,
        );
        expect(warmPiResult.fixtureId, isNotEmpty);
      },
    );

    test(
      'rejects unreferenced or missing snapshots and corrupted saved JSON on reload',
      () {
        // Unreferenced snapshot in PlayoffState
        final po = fx.career.playoffState!;
        final extraId = List.filled(64, 'd').join();
        expect(
          () => fx.career.copyWith(
            playoffState: PlayoffState.fromJson({
              ...po.toJson(),
              'gameInputSnapshots': {...po.gameInputSnapshots, extraId: '{}'},
            }),
          ),
          throwsFormatException,
        );

        // Missing snapshot in PlayoffState
        expect(
          () => fx.career.copyWith(
            playoffState: PlayoffState.fromJson({
              ...po.toJson(),
              'gameInputSnapshots': <String, String>{},
            }),
          ),
          throwsFormatException,
        );

        // Corrupted saved career JSON on reload
        final map =
            jsonDecode(GmCareerCodec.encode(fx.career)) as Map<String, dynamic>;
        final poMap = map['playoffState'] as Map<String, dynamic>;
        final grMap = poMap['gameResults'] as Map<String, dynamic>;
        final firstKey = grMap.keys.first;
        (grMap[firstKey] as Map<String, dynamic>)['inputFingerprint'] =
            List.filled(64, 'e').join();
        expect(
          () => GmCareerCodec.decode(jsonEncode(map)),
          throwsFormatException,
        );
      },
    );
  });
}
