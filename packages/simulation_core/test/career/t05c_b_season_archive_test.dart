import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/domain_versions.dart' as domain_versions;
import 'package:test/test.dart';

GmCareer _completedYear1Championship() {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: 20261028,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 't05c-b-test');
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
  // Simulate real Play-In games using PlayInGameService
  const piService = PlayInGameService();
  for (var g = 1; g <= 3; g++) {
    c = piService.simulateGame(c, expectedGameId: '${rs0.seasonId}-playin-g$g');
  }
  c = const PlayoffEntryService().enter(c);
  // Simulate real Playoff games using PlayoffSlateService
  const poService = PlayoffSlateService();
  while (!c.playoffState!.isComplete) {
    c = poService.simulateNextSlate(c);
  }
  return c;
}

void main() {
  late GmCareer completedChamp;

  setUpAll(() {
    completedChamp = _completedYear1Championship();
  });

  group('M009-T05C-B: SeasonArchive & CareerBundleService', () {
    test(
      'encodes canonical JSON with real SHA-256 and preserves full season payload',
      () {
        final archive = SeasonArchive.fromCareer(completedChamp);
        final encoded1 = SeasonArchiveCodec.encodeWithDigest(archive);
        final encoded2 = SeasonArchiveCodec.encodeWithDigest(archive);

        expect(encoded1.json, equals(encoded2.json));
        expect(encoded1.digest, equals(encoded2.digest));
        expect(
          encoded1.digest,
          equals(sha256.convert(utf8.encode(encoded1.json)).toString()),
        );

        final decoded = SeasonArchiveCodec.decodeAndVerify(
          encoded1.json,
          expectedDigest: encoded1.digest,
          expectedCareerId: completedChamp.id,
          expectedSeasonYear: 1,
        );
        expect(decoded.regularSeasonState.gameResults, hasLength(1230));
        expect(decoded.playInState.gameResults, hasLength(3));
        expect(
          decoded.playoffState.gameResults.length,
          completedChamp.playoffState!.gameResults.length,
        );
        expect(
          decoded.playoffState.champion,
          equals(completedChamp.playoffState!.champion),
        );
        expect(
          decoded.playoffState.gameResults.values.first.inputEvidence,
          isNotNull,
        );

        final record = archive.toHistoryRecord(encoded1.digest);
        expect(record.archiveDigest, equals(encoded1.digest));
        expect(
          record.championTeamId,
          equals(completedChamp.playoffState!.champion),
        );
        expect(record.regularSeasonStandings, hasLength(30));
        expect(record.playoffSeries, hasLength(15));
      },
    );

    test(
      'rejects corrupted archive digest, malformed JSON, and incomplete season states',
      () {
        final archive = SeasonArchive.fromCareer(completedChamp);
        final encoded = SeasonArchiveCodec.encodeWithDigest(archive);

        // Corrupted digest
        expect(
          () => SeasonArchiveCodec.decodeAndVerify(
            encoded.json,
            expectedDigest: List.filled(64, '0').join(),
          ),
          throwsFormatException,
        );

        // Tampered JSON bytes
        expect(
          () => SeasonArchiveCodec.decodeAndVerify(
            '${encoded.json} ',
            expectedDigest: encoded.digest,
          ),
          throwsFormatException,
        );

        // Malformed / incomplete playoff state inside archive
        final map = jsonDecode(encoded.json) as Map<String, dynamic>;
        (map['playoffState'] as Map<String, dynamic>)['gameResults'] =
            <String, dynamic>{};
        final tamperedJson = jsonEncode(map);
        final tamperedDigest = SeasonArchiveCodec.digestOf(tamperedJson);
        expect(
          () => SeasonArchiveCodec.decodeAndVerify(
            tamperedJson,
            expectedDigest: tamperedDigest,
          ),
          throwsFormatException,
        );
      },
    );

    test(
      'CareerBundleService export/import round-trip verifies all archives',
      () {
        final archive = SeasonArchive.fromCareer(completedChamp);
        final encodedArchive = SeasonArchiveCodec.encodeWithDigest(archive);
        final record = archive.toHistoryRecord(encodedArchive.digest);

        // Build a valid Year 2 career referencing Year 1 history record
        final base = GmCareer.fromSetupResult(
          const CareerSetupService().generate(
            const CareerSetupRequest(
              selectedTeamId: TeamId('team-1'),
              selectedSituation: FranchiseSituation.tanking,
              seed: 20261028,
            ),
          ),
          id: completedChamp.id,
        );
        final y2Career = base.copyWith(
          currentYear: 2,
          draftClass: const DraftGenerator().generateDraftClass(
            league: base.league,
            seed: base.generationSeed,
            seasonYear: 2,
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
          seasonHistory: [record],
        );
        final y2Json = GmCareerCodec.encode(y2Career);

        const bundleService = CareerBundleService();
        final bundle = bundleService.exportBundle(
          activeCareerJson: y2Json,
          archivesByYear: {1: encodedArchive.json},
        );
        final imported = bundleService.importBundle(bundle);
        expect(imported.career.seasonHistory, hasLength(1));
        expect(
          imported.career.seasonHistory.first.archiveDigest,
          equals(encodedArchive.digest),
        );
        expect(imported.verifiedArchivesByYear[1], equals(encodedArchive.json));

        // Missing archive rejected on export and import
        expect(
          () => bundleService.exportBundle(
            activeCareerJson: y2Json,
            archivesByYear: const {},
          ),
          throwsFormatException,
        );
        final bundleMap = jsonDecode(bundle) as Map<String, dynamic>;
        (bundleMap['archivesByYear'] as Map<String, dynamic>)['1'] =
            '{"corrupt":true}';
        expect(
          () => bundleService.importBundle(jsonEncode(bundleMap)),
          throwsFormatException,
        );
      },
    );

    test(
      'FIX 1: rejects SeasonHistoryRecord mismatch even when archive SHA-256 is valid',
      () {
        final archive = SeasonArchive.fromCareer(completedChamp);
        final encodedArchive = SeasonArchiveCodec.encodeWithDigest(archive);
        final realRecord = archive.toHistoryRecord(encodedArchive.digest);

        final finals = realRecord.playoffSeries[14];
        final alteredChampion = finals.winnerTeamId == finals.firstTeamId
            ? finals.secondTeamId
            : finals.firstTeamId;
        final tamperedPlayoffSeries = [
          for (var i = 0; i < realRecord.playoffSeries.length; i++)
            if (i == 14)
              PlayoffSeriesSummary(
                seriesIndex: 14,
                round: finals.round,
                firstTeamId: finals.firstTeamId,
                secondTeamId: finals.secondTeamId,
                winnerTeamId: alteredChampion,
                firstTeamWins: finals.firstTeamId == alteredChampion ? 4 : 0,
                secondTeamWins: finals.secondTeamId == alteredChampion ? 4 : 0,
              )
            else
              realRecord.playoffSeries[i],
        ];
        final tamperedRecord = SeasonHistoryRecord(
          seasonYear: realRecord.seasonYear,
          seasonId: realRecord.seasonId,
          championTeamId: alteredChampion,
          regularSeasonStandings: realRecord.regularSeasonStandings,
          playInOutcome: realRecord.playInOutcome,
          playoffSeries: tamperedPlayoffSeries,
          archiveId: realRecord.archiveId,
          archiveDigest: encodedArchive.digest,
        );

        // Direct decodeAndVerify with expectedRecord rejects mismatch
        expect(
          () => SeasonArchiveCodec.decodeAndVerify(
            encodedArchive.json,
            expectedDigest: encodedArchive.digest,
            expectedCareerId: completedChamp.id,
            expectedSeasonYear: 1,
            expectedRecord: tamperedRecord,
          ),
          throwsFormatException,
        );

        // CareerBundleService import/export rejects mismatched record even with valid archive SHA-256
        final base = GmCareer.fromSetupResult(
          const CareerSetupService().generate(
            const CareerSetupRequest(
              selectedTeamId: TeamId('team-1'),
              selectedSituation: FranchiseSituation.tanking,
              seed: 20261028,
            ),
          ),
          id: completedChamp.id,
        );
        final tamperedCareer = base.copyWith(
          currentYear: 2,
          draftClass: const DraftGenerator().generateDraftClass(
            league: base.league,
            seed: base.generationSeed,
            seasonYear: 2,
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
          seasonHistory: [tamperedRecord],
        );
        final tamperedCareerJson = GmCareerCodec.encode(tamperedCareer);
        const bundleService = CareerBundleService();
        expect(
          () => bundleService.exportBundle(
            activeCareerJson: tamperedCareerJson,
            archivesByYear: {1: encodedArchive.json},
          ),
          throwsFormatException,
        );
        final forgedBundle = jsonEncode({
          'bundleSchemaVersion': CareerBundleService.currentBundleSchemaVersion,
          'activeCareerJson': tamperedCareerJson,
          'archivesByYear': {'1': encodedArchive.json},
        });
        expect(
          () => bundleService.importBundle(forgedBundle),
          throwsFormatException,
        );
      },
    );

    test(
      'FIX 6: canonical encodeWithDigest is invariant to map insertion order while preserving periodScores order',
      () {
        final archive = SeasonArchive.fromCareer(completedChamp);
        final rs = archive.regularSeasonState;
        final reversedRsResults =
            Map<String, RegularSeasonGameResult>.fromEntries(
              rs.gameResults.entries.toList().reversed,
            );
        final reversedRsSnapshots = Map<String, String>.fromEntries(
          rs.gameInputSnapshots.entries.toList().reversed,
        );
        final po = archive.playoffState;
        final poJson = po.toJson();
        poJson['gameIdentities'] = Map<String, Object?>.fromEntries(
          (poJson['gameIdentities']! as Map<String, Object?>).entries
              .toList()
              .reversed,
        );
        poJson['gameResults'] = Map<String, Object?>.fromEntries(
          (poJson['gameResults']! as Map<String, Object?>).entries
              .toList()
              .reversed,
        );
        poJson['gameInputSnapshots'] = Map<String, Object?>.fromEntries(
          (poJson['gameInputSnapshots']! as Map<String, Object?>).entries
              .toList()
              .reversed,
        );

        final reorderedArchive = SeasonArchive(
          archiveSchemaVersion: archive.archiveSchemaVersion,
          careerId: archive.careerId,
          seasonId: archive.seasonId,
          seasonYear: archive.seasonYear,
          archiveId: archive.archiveId,
          regularSeasonState: rs.copyWith(
            gameResults: reversedRsResults,
            gameInputSnapshots: reversedRsSnapshots,
          ),
          playInState: archive.playInState,
          playoffState: PlayoffState.fromJson(poJson),
        );

        final encodedOriginal = SeasonArchiveCodec.encodeWithDigest(archive);
        final encodedReordered = SeasonArchiveCodec.encodeWithDigest(
          reorderedArchive,
        );
        expect(encodedReordered.json, equals(encodedOriginal.json));
        expect(encodedReordered.digest, equals(encodedOriginal.digest));

        // Verify periodScoresHome/periodScoresAway key order stays Q1..Q4..OTn
        final decoded = SeasonArchiveCodec.decodeAndVerify(
          encodedReordered.json,
          expectedDigest: encodedReordered.digest,
        );
        final sampleResult =
            decoded.regularSeasonState.gameResults.values.first;
        expect(
          sampleResult.summary.periodScoresHome.keys.take(4).toList(),
          equals(['Q1', 'Q2', 'Q3', 'Q4']),
        );
      },
    );
  });
}
