import 'dart:convert';

import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/playoff_tournament_screen.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/domain_versions.dart' as domain_versions;

class _FaultyCareerStorage implements GmCareerStorage {
  _FaultyCareerStorage(this.inner);

  final InMemoryGmCareerStorage inner;
  bool failBeforePromotion = false;
  bool failAfterPromotion = false;

  @override
  Future<void> clear({String slot = 'default'}) => inner.clear(slot: slot);

  @override
  Future<bool> hasSave({String slot = 'default'}) => inner.hasSave(slot: slot);

  @override
  Future<String?> read({String slot = 'default'}) => inner.read(slot: slot);

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    if (failBeforePromotion) {
      failBeforePromotion = false;
      throw const GmCareerStorageException('Simulated pre-promotion failure');
    }
    await inner.write(data, slot: slot);
    if (failAfterPromotion) {
      failAfterPromotion = false;
      throw const GmCareerStorageException(
        'Simulated post-promotion uncertain write',
      );
    }
  }
}

GmCareer _buildPlayoffCareer() {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: 20261028,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 'perf-p2a-test');
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

  RegularSeasonGameResult buildResult({
    required String gameId,
    required String seasonId,
    required int seasonYear,
    required TeamId homeTeamId,
    required TeamId awayTeamId,
    required int gameSeed,
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
    final idx = templateJson.indexOf('"league":$markerJson') + '"league":'.length;
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
      RegularSeasonRound(roundNumber: round.roundNumber, fixtures: updatedFixtures),
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
  return const PlayoffEntryService().enter(c);
}

void main() {
  late GmCareer basePlayoffCareer;
  late String basePlayoffJson;

  setUpAll(() {
    basePlayoffCareer = _buildPlayoffCareer();
    basePlayoffJson = GmCareerCodec.encode(basePlayoffCareer);
  });

  Future<GmCareerController> loadedController(_FaultyCareerStorage storage) async {
    await storage.inner.write(basePlayoffJson);
    final controller = GmCareerController(storage: storage);
    await controller.loadCareer();
    return controller;
  }

  group('M009-PERF-P2A: Playoff slate isolate/encoding optimization', () {
    test(
      'matches PlayoffSlateService baseline outcomes, seeds, fingerprints, and canonical v20 JSON',
      () async {
        final storage = _FaultyCareerStorage(InMemoryGmCareerStorage());
        final controller = await loadedController(storage);
        final baseline = const PlayoffSlateService().simulateNextSlate(
          controller.career!,
        );
        final baselineJson = GmCareerCodec.encode(baseline);

        await controller.simulateNextPlayoffSlate(confirmed: true);
        final savedJson = await storage.read();
        final actual = controller.career!;

        expect(savedJson, equals(baselineJson));
        expect(
          actual.playoffState!.gameResults.keys.toList(),
          equals(baseline.playoffState!.gameResults.keys.toList()),
        );
        for (final entry in actual.playoffState!.gameResults.entries) {
          final expected = baseline.playoffState!.gameResults[entry.key]!;
          expect(entry.value.gameSeed, expected.gameSeed);
          expect(entry.value.inputFingerprint, expected.inputFingerprint);
          expect(entry.value.summary.homeScore, expected.summary.homeScore);
          expect(entry.value.summary.awayScore, expected.summary.awayScore);
          expect(
            entry.value.summary.winnerTeamId,
            expected.summary.winnerTeamId,
          );
          expect(
            entry.value.summary.playerLines.length,
            expected.summary.playerLines.length,
          );
          for (final pEntry in expected.summary.playerLines.entries) {
            final actualLine = entry.value.summary.playerLines[pEntry.key]!;
            expect(actualLine.points, pEntry.value.points);
            expect(actualLine.rebounds, pEntry.value.rebounds);
            expect(actualLine.assists, pEntry.value.assists);
            expect(actualLine.secondsPlayed, pEntry.value.secondsPlayed);
          }
          expect(entry.value.inputEvidence, isNotNull);
        }

        // Reload preserves historical evidence
        final reloadedController = GmCareerController(storage: storage);
        await reloadedController.loadCareer();
        expect(
          GmCareerCodec.encode(reloadedController.career!),
          equals(baselineJson),
        );
      },
    );

    test(
      'full bracket parity from cold-start through partial series, round transitions, and championship',
      () async {
        final storage = _FaultyCareerStorage(InMemoryGmCareerStorage());
        final controller = await loadedController(storage);
        var expected = controller.career!;
        var slates = 0;
        var sawPartialSeries = false;
        final seenRounds = <PlayoffRound>{};

        while (!controller.career!.playoffState!.isComplete) {
          final beforeRound = controller.career!.playoffState!.currentRound!;
          seenRounds.add(beforeRound);

          await controller.simulateNextPlayoffSlate(confirmed: true);
          expected = const PlayoffSlateService().simulateNextSlate(expected);
          slates++;

          final actual = controller.career!;
          final po = actual.playoffState!;
          if (po.gameResults.isNotEmpty && !po.isComplete) {
            sawPartialSeries = true;
          }
          expect(
            po.gameResults.keys.toList(),
            equals(expected.playoffState!.gameResults.keys.toList()),
          );
          if (slates == 1 ||
              po.currentRound != beforeRound ||
              po.isComplete) {
            expect(
              await storage.read(),
              equals(GmCareerCodec.encode(expected)),
            );
          }
        }

        expect(slates, greaterThanOrEqualTo(16));
        expect(sawPartialSeries, isTrue);
        expect(seenRounds, equals(PlayoffRound.values.toSet()));
        expect(controller.career!.playoffState!.champion, isNotNull);
        await expectLater(
          controller.simulateNextPlayoffSlate(confirmed: true),
          throwsStateError,
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('rejects tampered worker results and historical evidence', () {
      const service = PlayoffSlateService();
      final order = service.prepareSlate(basePlayoffCareer);
      final validOutput = service.simulatePreparedSlate(order);

      // 1. Tampered inputFingerprint
      final first = validOutput.results.first;
      final badFingerprint = RegularSeasonGameResult(
        fixtureId: first.fixtureId,
        seasonId: first.seasonId,
        seasonYear: first.seasonYear,
        homeTeamId: first.homeTeamId,
        awayTeamId: first.awayTeamId,
        gameSeed: first.gameSeed,
        inputFingerprint: List.filled(64, 'a').join(),
        simulationVersion: first.simulationVersion,
        rulesVersion: first.rulesVersion,
        eventSchemaVersion: first.eventSchemaVersion,
        prngImplementationId: first.prngImplementationId,
        fingerprintVersion: first.fingerprintVersion,
        coreEngineVersion: first.coreEngineVersion,
        leagueSchemaVersion: first.leagueSchemaVersion,
        inputEvidence: first.inputEvidence,
        periodsPlayed: first.periodsPlayed,
        summary: first.summary,
      );
      expect(
        () => service.applyPreparedSlate(
          basePlayoffCareer,
          order: order,
          output: PlayoffSlateWorkerOutput(
            results: [badFingerprint, ...validOutput.results.skip(1)],
            snapshots: validOutput.snapshots,
          ),
        ),
        throwsFormatException,
      );

      // 2. Tampered leagueSnapshotJson
      final snapEntry = validOutput.snapshots.entries.first;
      expect(
        () => service.applyPreparedSlate(
          basePlayoffCareer,
          order: order,
          output: PlayoffSlateWorkerOutput(
            results: validOutput.results,
            snapshots: {snapEntry.key: '${snapEntry.value} '},
          ),
        ),
        throwsFormatException,
      );

      // 3. Tampered payloadTemplateJson
      final badEvidenceResult = RegularSeasonGameResult(
        fixtureId: first.fixtureId,
        seasonId: first.seasonId,
        seasonYear: first.seasonYear,
        homeTeamId: first.homeTeamId,
        awayTeamId: first.awayTeamId,
        gameSeed: first.gameSeed,
        inputFingerprint: first.inputFingerprint,
        simulationVersion: first.simulationVersion,
        rulesVersion: first.rulesVersion,
        eventSchemaVersion: first.eventSchemaVersion,
        prngImplementationId: first.prngImplementationId,
        fingerprintVersion: first.fingerprintVersion,
        coreEngineVersion: first.coreEngineVersion,
        leagueSchemaVersion: first.leagueSchemaVersion,
        inputEvidence: RegularSeasonGameInputEvidence(
          leagueSnapshotId: first.inputEvidence!.leagueSnapshotId,
          payloadTemplateJson: '${first.inputEvidence!.payloadTemplateJson} ',
        ),
        periodsPlayed: first.periodsPlayed,
        summary: first.summary,
      );
      expect(
        () => service.applyPreparedSlate(
          basePlayoffCareer,
          order: order,
          output: PlayoffSlateWorkerOutput(
            results: [badEvidenceResult, ...validOutput.results.skip(1)],
            snapshots: validOutput.snapshots,
          ),
        ),
        throwsFormatException,
      );
    });

    test('respects non-default storage slot when persisting playoff slate', () async {
      final storage = _FaultyCareerStorage(InMemoryGmCareerStorage());
      await storage.inner.write(basePlayoffJson, slot: 'slot-2');
      final controller = GmCareerController(storage: storage);
      await controller.loadCareer(slot: 'slot-2');

      await controller.simulateNextPlayoffSlate(
        confirmed: true,
        slot: 'slot-2',
      );

      final saved = await storage.read(slot: 'slot-2');
      expect(saved, isNotNull);
      expect(await storage.read(slot: 'default'), isNull);
      expect(controller.career!.playoffState!.gameResults, hasLength(8));
    });

    test(
      'pre-promotion failure preserves prior state, marks recovery required, and rejects subsequent commands',
      () async {
        final storage = _FaultyCareerStorage(InMemoryGmCareerStorage());
        final controller = await loadedController(storage);
        final beforeCareer = controller.career!;

        storage.failBeforePromotion = true;
        await expectLater(
          controller.simulateNextPlayoffSlate(confirmed: true),
          throwsA(isA<GmCareerStorageException>()),
        );

        expect(identical(controller.career, beforeCareer), isTrue);
        expect(controller.career!.playoffState!.gameResults, isEmpty);
        expect(controller.draftRecoveryRequired, isTrue);
        await expectLater(
          controller.simulateNextPlayoffSlate(confirmed: true),
          throwsStateError,
        );

        await controller.loadCareer();
        expect(controller.draftRecoveryRequired, isFalse);
        expect(controller.career!.playoffState!.gameResults, isEmpty);
      },
    );

    test(
      'post-promotion uncertain write preserves prior state, requires reload, and recovers persisted slate',
      () async {
        final storage = _FaultyCareerStorage(InMemoryGmCareerStorage());
        final controller = await loadedController(storage);
        final beforeCareer = controller.career!;

        storage.failAfterPromotion = true;
        await expectLater(
          controller.simulateNextPlayoffSlate(confirmed: true),
          throwsA(isA<GmCareerStorageException>()),
        );

        expect(identical(controller.career, beforeCareer), isTrue);
        expect(controller.career!.playoffState!.gameResults, isEmpty);
        expect(controller.draftRecoveryRequired, isTrue);
        await expectLater(
          controller.simulateNextPlayoffSlate(confirmed: true),
          throwsStateError,
        );

        await controller.loadCareer();
        expect(controller.draftRecoveryRequired, isFalse);
        expect(controller.career!.playoffState!.gameResults, hasLength(8));
      },
    );

    test('rejects unconfirmed, duplicate concurrent, and post-championship slates', () async {
      final storage = _FaultyCareerStorage(InMemoryGmCareerStorage());
      final controller = await loadedController(storage);

      await expectLater(
        controller.simulateNextPlayoffSlate(confirmed: false),
        throwsStateError,
      );

      // Concurrent duplicate slate submitted with the same initial career reference
      final first = controller.simulateNextPlayoffSlate(confirmed: true);
      final second = controller.simulateNextPlayoffSlate(confirmed: true);
      await first;
      await expectLater(second, throwsStateError);
      expect(controller.career!.playoffState!.gameResults, hasLength(8));

      // Complete championship via PlayoffSlateService and verify controller rejects another slate
      var completed = controller.career!;
      while (!completed.playoffState!.isComplete) {
        completed = const PlayoffSlateService().simulateNextSlate(completed);
      }
      await storage.inner.write(GmCareerCodec.encode(completed));
      await controller.loadCareer();
      expect(controller.career!.playoffState!.isComplete, isTrue);
      await expectLater(
        controller.simulateNextPlayoffSlate(confirmed: true),
        throwsStateError,
      );
    });

    for (final size in [
      const Size(360, 640),
      const Size(393, 852),
      const Size(800, 1280),
    ]) {
      testWidgets(
        'playoff UI remains functional at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          final storage = _FaultyCareerStorage(InMemoryGmCareerStorage());
          final controller = await loadedController(storage);

          await tester.pumpWidget(
            MaterialApp(home: PlayoffTournamentScreen(controller: controller)),
          );
          await tester.pumpAndSettle();

          final button = find.byKey(
            const ValueKey('simulate-next-playoff-slate'),
          );
          await tester.scrollUntilVisible(
            button,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(button, findsOneWidget);
        },
      );
    }
  });
}
