import 'dart:async';
import 'dart:convert';

import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_home_screen.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/playoff_tournament_screen.dart';
import 'package:basketball_manager/features/career/rollover_isolate_workers.dart';
import 'package:basketball_manager/features/season/season_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/domain_versions.dart' as domain_versions;

class _TestArchiveCareerStorage extends InMemoryGmCareerStorage {
  int writeCount = 0;
  int archiveWriteCount = 0;
  bool failNextArchiveWrite = false;
  bool failNextActiveWrite = false;
  Completer<void>? pendingWriteGate;

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    if (pendingWriteGate != null) {
      await pendingWriteGate!.future;
    }
    if (failNextActiveWrite) {
      failNextActiveWrite = false;
      throw const GmCareerStorageException('Simulated active save failure');
    }
    writeCount++;
    await super.write(data, slot: slot);
  }

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
    archiveWriteCount++;
    await super.writeArchive(
      seasonYear: seasonYear,
      archiveJson: archiveJson,
      expectedDigest: expectedDigest,
      slot: slot,
    );
  }
}

class _CountingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
    super.didPush(route, previousRoute);
  }
}

({GmCareer completed, GmCareer incompletePlayoffs}) _buildYear1Fixtures() {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: 20261028,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 't05c-d2-ui');
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
  final incompletePlayoffs = c;
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
  return (completed: c, incompletePlayoffs: incompletePlayoffs);
}

void main() {
  late GmCareer completedYear1;
  late String completedYear1Json;
  late String incompletePlayoffsJson;

  setUpAll(() {
    final fixtures = _buildYear1Fixtures();
    completedYear1 = fixtures.completed;
    completedYear1Json = GmCareerCodec.encode(completedYear1);
    incompletePlayoffsJson = GmCareerCodec.encode(fixtures.incompletePlayoffs);
  });

  Widget buildApp({
    required _TestArchiveCareerStorage storage,
    required GmCareerController controller,
  }) => BasketballManagerApp(
    league: completedYear1.league,
    storage: InMemorySeasonStorage(),
    careerStorage: storage,
    careerController: controller,
    seasonMode: true,
  );

  testWidgets(
    '1, 2, 3, 4, 19, 20: Incomplete hides button; completed shows champion & continuation, hides sim button, preserves bracket/results',
    (tester) async {
      final storage = _TestArchiveCareerStorage();
      await storage.write(incompletePlayoffsJson);
      final controller = GmCareerController(storage: storage);
      await controller.loadCareer();

      await tester.pumpWidget(
        MaterialApp(home: PlayoffTournamentScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      // 1. Incomplete playoffs hide continuation and show simulation button.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('simulate-next-playoff-slate')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const ValueKey('continue-to-next-season')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('simulate-next-playoff-slate')),
        findsOneWidget,
      );

      // Switch controller to completed championship.
      await storage.write(completedYear1Json);
      await controller.loadCareer();
      await tester.pumpAndSettle();

      // 2 & 20. Completed playoffs show continuation and hide simulation button.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('continue-to-next-season')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const ValueKey('continue-to-next-season')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('simulate-next-playoff-slate')),
        findsNothing,
      );

      // 3 & 4. Actual champion name shown; non-champion human team not falsely declared champion.
      final championId = completedYear1.playoffState!.champion!;
      final championTeam = completedYear1.league.teams.firstWhere(
        (t) => t.id == championId,
      );
      await tester.scrollUntilVisible(
        find.text(championTeam.name),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(championTeam.name), findsWidgets);
      expect(
        find.text('Your franchise won the Season 1 championship.'),
        findsOneWidget,
      );

      // Verify a losing human franchise is not falsely declared champion.
      final losingHumanId = completedYear1.league.teams
          .firstWhere((t) => t.id != championId)
          .id;
      final teamNames = {
        for (final team in completedYear1.regularSeasonState!.openingTeams)
          team.teamId.value: team.name,
      };
      await tester.pumpWidget(
        MaterialApp(
          home: PlayoffBracketContent(
            state: completedYear1.playoffState!,
            names: teamNames,
            seasonYear: 1,
            userFranchiseId: losingHumanId,
            isLoading: false,
            recoveryRequired: false,
            onSimulate: null,
            onContinueToNextSeason: () {},
            onViewFullBracket: () {},
            onViewResults: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(championTeam.name), findsWidgets);
      expect(
        find.text('Your franchise did not win the Season 1 title.'),
        findsOneWidget,
      );

      // Restore PlayoffTournamentScreen for bracket/results navigation check.
      await tester.pumpWidget(
        MaterialApp(home: PlayoffTournamentScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      // 19. Existing bracket and results navigation still works.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('view-full-playoff-bracket')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('view-full-playoff-bracket')));
      await tester.pumpAndSettle();
      expect(find.text('Full Playoff Bracket'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('view-playoff-game-results')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('view-playoff-game-results')));
      await tester.pumpAndSettle();
      expect(find.text('Playoff Game Results'), findsOneWidget);
    },
  );

  testWidgets(
    '5-12: Cancel leaves career unchanged; confirm disables button during save, blocks duplicates, transitions via root app to Year 2 without transient error or duplicate route',
    (tester) async {
      final storage = _TestArchiveCareerStorage();
      await storage.write(completedYear1Json);
      final controller = GmCareerController(
        storage: storage,
        prepareRolloverWorker: (request) async =>
            prepareSeasonRolloverWorker(request),
      );
      await controller.loadCareer();

      await tester.pumpWidget(
        buildApp(storage: storage, controller: controller),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inspect Playoff Bracket'));
      await tester.pumpAndSettle();

      final writesBeforeCancel = storage.writeCount;
      final archivesBeforeCancel = storage.archiveWriteCount;

      // 5. Tap Continue -> Cancel -> zero writes & Year 1 preserved.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('continue-to-next-season')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('continue-to-next-season')));
      await tester.pumpAndSettle();
      expect(find.text('Start Next Season?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cancel-next-season')));
      await tester.pumpAndSettle();

      expect(storage.writeCount, writesBeforeCancel);
      expect(storage.archiveWriteCount, archivesBeforeCancel);
      expect(controller.career?.currentYear, 1);
      expect(controller.career?.phase, CareerPhase.playoffs);

      // 7 & 8. Gate write with Completer to inspect loading/disabled state and block duplicates.
      final writeGate = Completer<void>();
      storage.pendingWriteGate = writeGate;

      await tester.tap(find.byKey(const ValueKey('continue-to-next-season')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-next-season')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      final btn = tester.widget<FilledButton>(
        find.byKey(const ValueKey('continue-to-next-season')),
      );
      expect(btn.onPressed, isNull);
      expect(find.text('Saving next season…'), findsOneWidget);

      // Attempt duplicate tap while saving -> blocked.
      await tester.tap(
        find.byKey(const ValueKey('continue-to-next-season')),
        warnIfMissed: false,
      );
      await tester.pump();

      // Release write gate and settle.
      writeGate.complete();
      await tester.pumpAndSettle();

      // 6, 9, 10, 11. Transitioned to Year 2 openingOffseason via root routing, no duplicate routes.
      expect(controller.career?.currentYear, 2);
      expect(controller.career?.phase, CareerPhase.openingOffseason);
      expect(storage.archiveWriteCount, archivesBeforeCancel + 1);
      expect(storage.writeCount, writesBeforeCancel + 1);
      expect(find.byType(CareerHomeScreen), findsOneWidget);
      expect(find.byType(PlayoffTournamentScreen), findsNothing);
      expect(find.text('Season 2 • Opening Offseason'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '11-12: Standalone PlayoffTournamentScreen does not throw transient StateError when controller switches phase',
    (tester) async {
      final storage = _TestArchiveCareerStorage();
      await storage.write(completedYear1Json);
      final controller = GmCareerController(
        storage: storage,
        prepareRolloverWorker: (request) async =>
            prepareSeasonRolloverWorker(request),
      );
      await controller.loadCareer();

      final observer = _CountingNavigatorObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: PlayoffTournamentScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      final pushesBefore = observer.pushCount;

      await controller.continueToNextSeason(confirmed: true);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(observer.pushCount, pushesBefore);
      expect(controller.career?.currentYear, 2);
    },
  );

  testWidgets(
    '13-18: Save failure shows error & recovery-required; reload restores Year 1 for safe retry or Year 2 into offseason',
    (tester) async {
      final storage = _TestArchiveCareerStorage();
      await storage.write(completedYear1Json);
      final controller = GmCareerController(
        storage: storage,
        prepareRolloverWorker: (request) async =>
            prepareSeasonRolloverWorker(request),
      );
      await controller.loadCareer();

      await tester.pumpWidget(
        buildApp(storage: storage, controller: controller),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inspect Playoff Bracket'));
      await tester.pumpAndSettle();

      // 13 & 14 & 15. Fail active write -> championship stays visible, error shown, recovery-required disables button.
      storage.failNextActiveWrite = true;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('continue-to-next-season')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('continue-to-next-season')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-next-season')));
      await tester.pumpAndSettle();

      expect(controller.career?.currentYear, 1);
      expect(controller.draftRecoveryRequired, isTrue);
      expect(find.byType(PlayoffTournamentScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Failed to archive completed season'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('Failed to archive completed season'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Save recovery required. Reload the saved career before continuing.',
        ),
        findsOneWidget,
      );
      final disabledBtn = tester.widget<FilledButton>(
        find.byKey(const ValueKey('continue-to-next-season')),
      );
      expect(disabledBtn.onPressed, isNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('reload-playoff-career')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const ValueKey('reload-playoff-career')),
        findsOneWidget,
      );

      // 16 & 17. Tap Reload Saved Career -> restores Year 1, clears recovery, retry succeeds to Year 2.
      await tester.tap(find.byKey(const ValueKey('reload-playoff-career')));
      await tester.pumpAndSettle();

      expect(controller.draftRecoveryRequired, isFalse);
      expect(controller.career?.currentYear, 1);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('continue-to-next-season')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final reenabledBtn = tester.widget<FilledButton>(
        find.byKey(const ValueKey('continue-to-next-season')),
      );
      expect(reenabledBtn.onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('continue-to-next-season')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-next-season')));
      await tester.pumpAndSettle();

      expect(controller.career?.currentYear, 2);
      expect(find.byType(CareerHomeScreen), findsOneWidget);
      expect(find.text('Season 2 • Opening Offseason'), findsOneWidget);

      // 18. Reloaded Year N+1 shows offseason on fresh app mount.
      final reloadedController = GmCareerController(storage: storage);
      await reloadedController.loadCareer();
      await tester.pumpWidget(
        buildApp(storage: storage, controller: reloadedController),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CareerHomeScreen), findsOneWidget);
      expect(find.text('Season 2 • Opening Offseason'), findsOneWidget);
    },
  );
}
