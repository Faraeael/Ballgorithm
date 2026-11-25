import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/domain_versions.dart' as domain_versions;

const _adapter = RegularSeasonGameAdapter();

/// Real draft and rookie signings; free agency not started yet.
GmCareer preFreeAgencyOffseason({
  String teamId = 'team-1',
  int seed = 20261028,
  FranchiseSituation situation = FranchiseSituation.tanking,
}) {
  final setup = const CareerSetupService().generate(
    CareerSetupRequest(
      selectedTeamId: TeamId(teamId),
      selectedSituation: situation,
      seed: seed,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 'fixture-$teamId-$seed');
  const draft = DraftExecutionService();
  const aiSigning = RookieAiSigningService();
  const signing = RookieSigningService();
  c = draft.startDraft(c);
  while (!c.draftExecutionState.isCompleted) {
    if (c.draftExecutionState.isHumanTurn(
      order: c.draftOrder,
      userTeamId: c.userFranchiseId,
    )) {
      final pick = c.draftClass.prospects.firstWhere(
        (p) => !c.draftExecutionState.draftRights.containsKey(p.id.value),
      );
      c = draft.makeHumanSelection(career: c, prospectId: pick.id);
    } else {
      c = draft.executeAiSelection(c);
    }
  }
  c = aiSigning.initialize(c);
  while (aiSigning.pendingRights(c).isNotEmpty) {
    c = aiSigning.applyNextDecision(c);
  }
  for (final r in c.unsignedDraftRights) {
    if (r.owningTeamId == c.userFranchiseId) {
      c = signing.signDraftedRookie(
        career: c,
        teamId: c.userFranchiseId,
        prospectId: r.prospectId,
        category: RosterCategory.standard,
        durationYears: 2,
      );
    }
  }
  return c;
}

/// Free agency (two rounds), clearance and hardship from [c].
GmCareer clearOffseason(GmCareer c) {
  const market = FreeAgentMarketService();
  const clearance = OffseasonClearanceService();
  const hardship = HardshipSettlementService();
  for (var round = 0; round < 2; round++) {
    c = market.startRound(c);
    c = market.prepareResolution(c);
    while (c.freeAgentMarket.isResolvable) {
      c = market.resolveNext(c);
    }
  }
  c = clearance.start(c);
  c = clearance.prepare(c);
  while (c.offseasonClearance.isResolvable) {
    c = clearance.resolveNext(c);
  }
  c = hardship.prepare(c, humanParticipationConfirmed: true);
  while (c.hardshipSettlement.isResolvable) {
    c = hardship.resolveNext(c);
  }
  return clearance.markCleared(c);
}

GmCareer scheduledSeason(GmCareer cleared) =>
    const RegularSeasonScheduleService().generate(
      const RegularSeasonEntryService().start(cleared),
    );

/// Fabricated (home 104–96) regular season whose inputs still come from the
/// production adapter, then real Play-In and playoffs.
GmCareer completeSeason(GmCareer scheduled) {
  var c = _fabricateRegularSeason(scheduled);
  c = const PlayInEntryService().enter(c);
  for (var g = 1; g <= 3; g++) {
    c = const PlayInGameService().simulateGame(
      c,
      expectedGameId: '${c.regularSeasonState!.seasonId}-playin-g$g',
    );
  }
  c = const PlayoffEntryService().enter(c);
  while (!c.playoffState!.isComplete) {
    c = const PlayoffSlateService().simulateNextSlate(c);
  }
  return c;
}

GmCareer _fabricateRegularSeason(GmCareer c) {
  final simLeague = _adapter.simulationLeagueFor(c);
  final rs0 = c.regularSeasonState!;
  final schedule = rs0.schedule!;
  final teamById = {for (final t in simLeague.teams) t.id: t};
  String? leagueJson;
  String? snapshotId;
  final results = <String, RegularSeasonGameResult>{};
  final rounds = <RegularSeasonRound>[];
  for (final round in schedule.rounds) {
    final fixtures = <RegularSeasonFixture>[];
    for (final f in round.fixtures) {
      final input = _adapter.createInput(c, f, simulationLeague: simLeague);
      final captured = RegularSeasonGameInputEvidence.capture(input);
      leagueJson ??= captured.leagueSnapshotJson;
      snapshotId ??= captured.evidence.leagueSnapshotId;
      final lines = <SeasonPlayerGameLine>[];
      void addLines(Team team, int total) {
        final players = team.players.take(8).toList();
        for (var i = 0; i < players.length; i++) {
          final pts = total ~/ players.length + (i < total % 8 ? 1 : 0);
          lines.add(
            SeasonPlayerGameLine(
              playerId: players[i].id.value,
              teamId: team.id.value,
              secondsPlayed: 1440,
              points: pts,
              fgm: pts ~/ 2,
              fga: pts ~/ 2 + 4,
              threePm: 0,
              threePa: 2,
              ftm: pts % 2,
              fta: pts % 2,
              oreb: 1,
              dreb: 3,
              rebounds: 4,
              assists: 2,
              steals: 1,
              blocks: 0,
              turnovers: 1,
              personalFouls: 2,
            ),
          );
        }
      }

      addLines(teamById[f.homeTeamId]!, 104);
      addLines(teamById[f.awayTeamId]!, 96);
      results[f.id] = RegularSeasonGameResult(
        fixtureId: f.id,
        seasonId: rs0.seasonId,
        seasonYear: rs0.seasonYear,
        homeTeamId: f.homeTeamId,
        awayTeamId: f.awayTeamId,
        gameSeed: f.gameSeed,
        inputFingerprint: GameFingerprint.of(input),
        simulationVersion: gameSimulationVersion,
        rulesVersion: gameRulesVersion,
        eventSchemaVersion: gameEventSchemaVersion,
        prngImplementationId: 'xorshift32-v1',
        fingerprintVersion: gameFingerprintVersion,
        coreEngineVersion: domain_versions.coreEngineVersion,
        leagueSchemaVersion: domain_versions.snapshotSchemaVersion,
        inputEvidence: captured.evidence,
        periodsPlayed: 4,
        summary: SeasonGameSummary(
          homeScore: 104,
          awayScore: 96,
          winnerTeamId: f.homeTeamId,
          periodScoresHome: const {'Q1': 26, 'Q2': 26, 'Q3': 26, 'Q4': 26},
          periodScoresAway: const {'Q1': 24, 'Q2': 24, 'Q3': 24, 'Q4': 24},
          playerLines: {for (final l in lines) l.playerId: l},
        ),
      );
      fixtures.add(
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
    rounds.add(
      RegularSeasonRound(roundNumber: round.roundNumber, fixtures: fixtures),
    );
  }
  return c.copyWith(
    regularSeasonState: rs0.copyWith(
      gameResults: results,
      gameInputSnapshots: {snapshotId!: leagueJson!},
      schedule: RegularSeasonSchedule(
        seasonId: schedule.seasonId,
        seasonYear: schedule.seasonYear,
        scheduleSeed: schedule.scheduleSeed,
        rounds: rounds,
      ),
    ),
  );
}
