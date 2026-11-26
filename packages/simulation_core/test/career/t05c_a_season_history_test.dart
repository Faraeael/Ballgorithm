import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/domain_versions.dart' as domain_versions;
import 'package:test/test.dart';

GmCareer _baseCareer({String id = 't05c-a-test'}) => GmCareer.fromSetupResult(
  const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: 20261028,
    ),
  ),
  id: id,
);

GmCareer _completedOffseason(GmCareer c) {
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
  return rsScheduleService.generate(c);
}

GmCareer _advanceToCompletedChampionship(GmCareer c) {
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

SeasonHistoryRecord _syntheticHistoryRecord({
  required List<Team> teams,
  required String careerId,
  required int year,
  TeamId? overrideChampion,
  String? overrideDigest,
}) {
  final standings = [
    for (var i = 0; i < 30; i++)
      SeasonStandingSummary(
        rank: i + 1,
        teamId: teams[i].id,
        wins: 60 - i,
        losses: 22 + i,
      ),
  ];
  final series = [
    for (var i = 0; i < 15; i++)
      PlayoffSeriesSummary(
        seriesIndex: i,
        round: i < 8
            ? PlayoffRound.roundOf16
            : i < 12
            ? PlayoffRound.quarterfinals
            : i < 14
            ? PlayoffRound.semifinals
            : PlayoffRound.finals,
        firstTeamId: teams[0].id,
        secondTeamId: teams[1].id,
        winnerTeamId: i == 14 ? (overrideChampion ?? teams[0].id) : teams[0].id,
        firstTeamWins: 4,
        secondTeamWins: 1,
      ),
  ];
  return SeasonHistoryRecord(
    seasonYear: year,
    seasonId: '$careerId-season-$year',
    championTeamId: overrideChampion ?? teams[0].id,
    regularSeasonStandings: standings,
    playInOutcome: PlayInOutcomeSummary(
      game1WinnerTeamId: teams[14].id,
      game2WinnerTeamId: teams[16].id,
      game3WinnerTeamId: teams[16].id,
      seed15TeamId: teams[14].id,
      seed16TeamId: teams[16].id,
    ),
    playoffSeries: series,
    archiveId: '$careerId-season-$year-archive',
    archiveDigest:
        overrideDigest ??
        sha256.convert(utf8.encode('archive-$year')).toString(),
  );
}

String _asV20Json(GmCareer career) {
  final map = jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
  map['schemaVersion'] = 20;
  map.remove('seasonHistory');
  map.remove('retiredPlayers');
  map.remove('seasonSettlements');
  map.remove('careerDraftRights');
  map.remove('carriedUnsignedProspects');
  map.remove('marketHistory');
  map.remove('userRotation');
  map.remove('staff');
  map.remove('tradeHistory');
  map.remove('emergencySettlement');
  return jsonEncode(map);
}

void main() {
  late GmCareer opening;
  late GmCareer completedRs;
  late GmCareer playInCareer;
  late GmCareer completedChamp;

  setUpAll(() {
    opening = _baseCareer();
    final rs0 = _completedOffseason(opening);
    final champ = _advanceToCompletedChampionship(rs0);
    completedChamp = champ;
    completedRs = champ.copyWith(
      phase: CareerPhase.regularSeason,
      playInState: null,
      playoffState: null,
    );
    playInCareer = champ.copyWith(
      phase: CareerPhase.playIn,
      playoffState: null,
    );
  });

  group('M009-T05C-A: SeasonHistoryRecord & Schema v21', () {
    test(
      'migrates v20 careers across phases with empty seasonHistory and intact state',
      () {
        for (final c in [opening, completedRs, playInCareer, completedChamp]) {
          final v20Json = _asV20Json(c);
          final decoded = GmCareerCodec.decode(v20Json);
          expect(decoded.schemaVersion, GmCareerCodec.currentSchemaVersion);
          expect(decoded.seasonHistory, isEmpty);
          expect(decoded.phase, c.phase);
          expect(
            decoded.finances.contracts.length,
            c.finances.contracts.length,
          );

          // Canonical v21 encode/decode stability
          final v21Json = GmCareerCodec.encode(decoded);
          expect(
            GmCareerCodec.encode(GmCareerCodec.decode(v21Json)),
            equals(v21Json),
          );
        }

        // Completed champion remains active in playoffState, not moved to seasonHistory
        final decodedChamp = GmCareerCodec.decode(_asV20Json(completedChamp));
        expect(decodedChamp.playoffState!.isComplete, isTrue);
        expect(decodedChamp.playoffState!.champion, isNotNull);
        expect(decodedChamp.seasonHistory, isEmpty);
        expect(
          decodedChamp
              .regularSeasonState!
              .gameResults
              .values
              .first
              .inputEvidence,
          isNotNull,
        );
        expect(
          decodedChamp.playoffState!.gameResults.values.first.inputFingerprint,
          equals(
            completedChamp
                .playoffState!
                .gameResults
                .values
                .first
                .inputFingerprint,
          ),
        );

        // Pre-v21 save containing non-null seasonHistory (even empty list) is rejected
        final badV20 =
            jsonDecode(GmCareerCodec.encode(opening)) as Map<String, dynamic>
              ..['schemaVersion'] = 20;
        expect(
          () => GmCareerCodec.decode(jsonEncode(badV20)),
          throwsFormatException,
        );
        // v21 save missing seasonHistory is rejected
        final missingV21 =
            jsonDecode(GmCareerCodec.encode(opening)) as Map<String, dynamic>
              ..remove('seasonHistory')
              ..remove('retiredPlayers')
              ..remove('seasonSettlements')
              ..remove('careerDraftRights')
              ..remove('carriedUnsignedProspects')
              ..remove('marketHistory')
              ..remove('userRotation')
              ..remove('staff')
              ..remove('tradeHistory')
              ..remove('emergencySettlement');
        expect(
          () => GmCareerCodec.decode(jsonEncode(missingV21)),
          throwsFormatException,
        );
      },
    );

    test(
      'supports multiple chronological SeasonHistoryRecords and immutability',
      () {
        final y1 = _syntheticHistoryRecord(
          teams: opening.league.teams,
          careerId: opening.id,
          year: 1,
        );
        final y2 = _syntheticHistoryRecord(
          teams: opening.league.teams,
          careerId: opening.id,
          year: 2,
        );
        final y3Career = GmCareer(
          id: opening.id,
          generationSeed: opening.generationSeed,
          userFranchiseId: opening.userFranchiseId,
          originalSituation: opening.originalSituation,
          currentYear: 3,
          league: opening.league,
          careerProfiles: opening.careerProfiles,
          userOpeningDraftPick: opening.userOpeningDraftPick,
          draftOrder: opening.draftOrder,
          seasonHistory: [y1, y2],
        );
        final roundTripped = GmCareerCodec.decode(
          GmCareerCodec.encode(y3Career),
        );
        expect(roundTripped.seasonHistory, hasLength(2));
        expect(roundTripped.seasonHistory[0].seasonYear, 1);
        expect(roundTripped.seasonHistory[1].seasonYear, 2);

        expect(
          () => roundTripped.seasonHistory.add(y1),
          throwsUnsupportedError,
        );
        expect(
          () => roundTripped.seasonHistory[0].regularSeasonStandings.add(
            roundTripped.seasonHistory[0].regularSeasonStandings.first,
          ),
          throwsUnsupportedError,
        );
        expect(
          () => roundTripped.seasonHistory[0].playoffSeries.add(
            roundTripped.seasonHistory[0].playoffSeries.first,
          ),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'rejects duplicate years, future years, invalid franchise/champion, and bad digests',
      () {
        final y1 = _syntheticHistoryRecord(
          teams: opening.league.teams,
          careerId: opening.id,
          year: 1,
        );
        // Future/current year rejected
        expect(
          () => opening.copyWith(currentYear: 1, seasonHistory: [y1]),
          throwsFormatException,
        );
        // Duplicate year rejected
        expect(
          () => GmCareer(
            id: opening.id,
            generationSeed: opening.generationSeed,
            userFranchiseId: opening.userFranchiseId,
            originalSituation: opening.originalSituation,
            currentYear: 3,
            league: opening.league,
            careerProfiles: opening.careerProfiles,
            userOpeningDraftPick: opening.userOpeningDraftPick,
            draftOrder: opening.draftOrder,
            seasonHistory: [y1, y1],
          ),
          throwsFormatException,
        );
        // Champion mismatch with Finals series winner rejected
        expect(
          () => SeasonHistoryRecord(
            seasonYear: 1,
            seasonId: '${opening.id}-season-1',
            championTeamId: opening.league.teams[1].id,
            regularSeasonStandings: y1.regularSeasonStandings,
            playInOutcome: y1.playInOutcome,
            playoffSeries: y1.playoffSeries,
            archiveId: y1.archiveId,
            archiveDigest: y1.archiveDigest,
          ),
          throwsFormatException,
        );
        // Unknown franchise rejected by GmCareer.validate
        final unknownTeams = [
          Team(
            id: const TeamId('nonexistent-team'),
            name: 'Ghost',
            abbreviation: 'GHO',
            roster: opening.league.teams.first.roster,
          ),
          ...opening.league.teams.skip(1),
        ];
        final badChamp = _syntheticHistoryRecord(
          teams: unknownTeams,
          careerId: opening.id,
          year: 1,
        );
        expect(
          () => GmCareer(
            id: opening.id,
            generationSeed: opening.generationSeed,
            userFranchiseId: opening.userFranchiseId,
            originalSituation: opening.originalSituation,
            currentYear: 2,
            league: opening.league,
            careerProfiles: opening.careerProfiles,
            userOpeningDraftPick: opening.userOpeningDraftPick,
            draftOrder: opening.draftOrder,
            seasonHistory: [badChamp],
          ),
          throwsFormatException,
        );
        // Invalid archive digest rejected
        expect(
          () => _syntheticHistoryRecord(
            teams: opening.league.teams,
            careerId: opening.id,
            year: 1,
            overrideDigest: 'NOT-A-VALID-SHA256',
          ),
          throwsFormatException,
        );
      },
    );

    test(
      'copyWith preserves omitted nullable fields, clears explicit null, and enforces phase/state invariants',
      () {
        // Omitted fields preserved
        final preserved = completedChamp.copyWith(currentYear: 1);
        expect(preserved.regularSeasonState, isNotNull);
        expect(preserved.playInState, isNotNull);
        expect(preserved.playoffState, isNotNull);

        // Explicit null clears fields when phase is compatible
        final cleared = completedChamp.copyWith(
          phase: CareerPhase.openingOffseason,
          regularSeasonState: null,
          playInState: null,
          playoffState: null,
        );
        expect(cleared.regularSeasonState, isNull);
        expect(cleared.playInState, isNull);
        expect(cleared.playoffState, isNull);

        // Invalid phase/state combinations rejected
        expect(
          () => completedChamp.copyWith(regularSeasonState: null),
          throwsFormatException,
        );
        expect(
          () => completedChamp.copyWith(playInState: null),
          throwsFormatException,
        );
        expect(
          () => completedChamp.copyWith(playoffState: null),
          throwsFormatException,
        );
      },
    );

    test('preserves v17 migration compatibility', () {
      final played = const RegularSeasonRoundService().simulateNextRound(
        _completedOffseason(opening),
        expectedRoundNumber: 1,
      );
      final v21Json = GmCareerCodec.encode(played);
      final v17Map = jsonDecode(v21Json) as Map<String, dynamic>;
      v17Map['schemaVersion'] = 17;
      v17Map.remove('seasonHistory');
      v17Map.remove('retiredPlayers');
      v17Map.remove('seasonSettlements');
      v17Map.remove('careerDraftRights');
      v17Map.remove('carriedUnsignedProspects');
      v17Map.remove('marketHistory');
      v17Map.remove('userRotation');
      v17Map.remove('staff');
      v17Map.remove('tradeHistory');
      v17Map.remove('emergencySettlement');
      final rsMap = v17Map['regularSeasonState'] as Map<String, dynamic>;
      rsMap.remove('gameInputSnapshots');
      final grMap = rsMap['gameResults'] as Map<String, dynamic>;
      for (final rawResult in grMap.values.cast<Map<String, dynamic>>()) {
        rawResult
          ..remove('inputEvidence')
          ..remove('fingerprintVersion')
          ..remove('coreEngineVersion')
          ..remove('leagueSchemaVersion');
      }
      final migrated = GmCareerCodec.decode(jsonEncode(v17Map));
      expect(migrated.schemaVersion, GmCareerCodec.currentSchemaVersion);
      expect(migrated.seasonHistory, isEmpty);
      expect(GmCareerCodec.encode(migrated), equals(v21Json));
    });
  });
}
