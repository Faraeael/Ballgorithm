import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

List<RegularSeasonTeamIdentity> _teams() => [
  for (var index = 0; index < 30; index++)
    RegularSeasonTeamIdentity(
      teamId: TeamId('team-$index'),
      name: 'Team $index',
      abbreviation: 'T${index.toString().padLeft(2, '0')}',
    ),
];

RegularSeasonSchedule _schedule(List<RegularSeasonTeamIdentity> teams) =>
    const RegularSeasonScheduleGenerator().generate(
      seasonId: 'career-season-1',
      seasonYear: 1,
      scheduleSeed: 7,
      openingTeams: teams,
    );

RegularSeasonGameResult _result(RegularSeasonFixture fixture) =>
    RegularSeasonGameResult(
      fixtureId: fixture.id,
      seasonId: fixture.seasonId,
      seasonYear: fixture.seasonYear,
      homeTeamId: fixture.homeTeamId,
      awayTeamId: fixture.awayTeamId,
      gameSeed: fixture.gameSeed,
      inputFingerprint:
          '0000000000000000000000000000000000000000000000000000000000000000',
      simulationVersion: 7,
      rulesVersion: 3,
      eventSchemaVersion: 3,
      prngImplementationId: 'xorshift32-v1',
      fingerprintVersion: 5,
      coreEngineVersion: '1.0.0',
      leagueSchemaVersion: 1,
      periodsPlayed: 4,
      summary: SeasonGameSummary(
        homeScore: 2,
        awayScore: 0,
        winnerTeamId: fixture.homeTeamId,
        periodScoresHome: const {'Q1': 0, 'Q2': 0, 'Q3': 0, 'Q4': 2},
        periodScoresAway: const {'Q1': 0, 'Q2': 0, 'Q3': 0, 'Q4': 0},
        playerLines: {
          'home-player': SeasonPlayerGameLine(
            playerId: 'home-player',
            teamId: fixture.homeTeamId.value,
            points: 2,
            fgm: 1,
            fga: 1,
            threePm: 0,
            threePa: 0,
            ftm: 0,
            fta: 0,
            oreb: 0,
            dreb: 0,
            rebounds: 0,
            assists: 0,
            steals: 0,
            blocks: 0,
            turnovers: 0,
            personalFouls: 0,
            secondsPlayed: 100,
          ),
        },
      ),
    );
RegularSeasonGameResult _copyResult(
  RegularSeasonGameResult result, {
  int? simulationVersion,
}) => RegularSeasonGameResult(
  fixtureId: result.fixtureId,
  seasonId: result.seasonId,
  seasonYear: result.seasonYear,
  homeTeamId: result.homeTeamId,
  awayTeamId: result.awayTeamId,
  gameSeed: result.gameSeed,
  inputFingerprint: result.inputFingerprint,
  simulationVersion: simulationVersion ?? result.simulationVersion,
  rulesVersion: result.rulesVersion,
  eventSchemaVersion: result.eventSchemaVersion,
  prngImplementationId: result.prngImplementationId,
  fingerprintVersion: result.fingerprintVersion,
  coreEngineVersion: result.coreEngineVersion,
  leagueSchemaVersion: result.leagueSchemaVersion,
  inputEvidence: result.inputEvidence,
  periodsPlayed: result.periodsPlayed,
  summary: result.summary,
);

GmCareer _scheduledCareer() {
  final career = GmCareer.fromSetupResult(
    const CareerSetupService().generate(
      const CareerSetupRequest(
        selectedTeamId: TeamId('team-1'),
        selectedSituation: FranchiseSituation.tanking,
        seed: 20261028,
      ),
    ),
    id: 'round-engine-test',
  );
  final seasonId = RegularSeasonState.seasonIdFor(
    career.id,
    career.currentYear,
  );
  final teams = [
    for (final team in career.league.teams)
      RegularSeasonTeamIdentity.fromTeam(team),
  ];
  final state = RegularSeasonState(
    seasonId: seasonId,
    seasonYear: career.currentYear,
    scheduleSeed: career.generationSeed,
    openingTeams: teams,
    gameResults: const {},
    schedule: RegularSeasonScheduleGenerator().generate(
      seasonId: seasonId,
      seasonYear: career.currentYear,
      scheduleSeed: career.generationSeed,
      openingTeams: teams,
    ),
  );
  return career.copyWith(
    phase: CareerPhase.regularSeason,
    regularSeasonState: state,
  );
}

void main() {
  test('result validation rejects player ownership corruption', () {
    final teams = _teams();
    final fixture = _schedule(teams).rounds.first.fixtures.first;
    final result = _result(fixture);
    result.validateFor(
      fixture: fixture,
      expectedSeasonId: fixture.seasonId,
      expectedSeasonYear: fixture.seasonYear,
      standardPlayers: const {'home-player'},
      playerTeams: {'home-player': fixture.homeTeamId.value},
    );
    expect(
      () => result.validateFor(
        fixture: fixture,
        expectedSeasonId: fixture.seasonId,
        expectedSeasonYear: fixture.seasonYear,
        standardPlayers: const {},
        playerTeams: const {},
      ),
      throwsFormatException,
    );
  });
  test('result validation binds exact fixture seed and teams', () {
    final fixture = _schedule(_teams()).rounds.first.fixtures.first;
    final result = _result(fixture);
    void validate(RegularSeasonGameResult candidate) => candidate.validateFor(
      fixture: fixture,
      expectedSeasonId: fixture.seasonId,
      expectedSeasonYear: fixture.seasonYear,
      standardPlayers: const {'home-player'},
      playerTeams: {'home-player': fixture.homeTeamId.value},
      legacyCompatibility: true,
    );

    Map<String, dynamic> legacyJson(RegularSeasonGameResult candidate) =>
        Map<String, dynamic>.from(candidate.toJson())
          ..remove('fingerprintVersion')
          ..remove('coreEngineVersion')
          ..remove('leagueSchemaVersion');
    final wrongSeed = legacyJson(result)..['gameSeed'] = fixture.gameSeed + 1;
    final wrongTeam = legacyJson(result)
      ..['homeTeamId'] = fixture.awayTeamId.value;
    validate(result);
    expect(
      () => validate(
        RegularSeasonGameResult.fromJson(wrongSeed, schemaVersion: 17),
      ),
      throwsFormatException,
    );
    expect(
      () => validate(
        RegularSeasonGameResult.fromJson(wrongTeam, schemaVersion: 17),
      ),
      throwsFormatException,
    );
  });

  test('completed fixture ledger derives round and standings progress', () {
    final teams = _teams();
    final schedule = _schedule(teams);
    final results = <String, RegularSeasonGameResult>{};
    final completed = RegularSeasonSchedule(
      seasonId: schedule.seasonId,
      seasonYear: schedule.seasonYear,
      scheduleSeed: schedule.scheduleSeed,
      rounds: [
        for (final round in schedule.rounds)
          RegularSeasonRound(
            roundNumber: round.roundNumber,
            fixtures: [
              for (final fixture in round.fixtures)
                if (round.roundNumber == 1) ...[
                  RegularSeasonFixture(
                    id: fixture.id,
                    seasonId: fixture.seasonId,
                    seasonYear: fixture.seasonYear,
                    roundNumber: fixture.roundNumber,
                    fixturePosition: fixture.fixturePosition,
                    homeTeamId: fixture.homeTeamId,
                    awayTeamId: fixture.awayTeamId,
                    gameSeed: fixture.gameSeed,
                    status: RegularSeasonFixtureStatus.completed,
                  ),
                ] else
                  fixture,
            ],
          ),
      ],
    );
    for (final fixture in completed.rounds.first.fixtures) {
      results[fixture.id] = _result(fixture);
    }
    final state = RegularSeasonState(
      seasonId: schedule.seasonId,
      seasonYear: schedule.seasonYear,
      scheduleSeed: schedule.scheduleSeed,
      openingTeams: teams,
      gameResults: results,
      schedule: completed,
    );
    expect(state.completedGames, 15);
    expect(state.completedRounds, 1);
    expect(state.remainingGames, 1215);
    expect(state.nextUnfinishedRoundNumber, 2);
    expect(
      state.gamesPlayedForTeam(
        completed.rounds.first.fixtures.first.homeTeamId,
      ),
      1,
    );
    expect(
      state.standings.table.values.fold<int>(
        0,
        (sum, standing) => sum + standing.wins,
      ),
      15,
    );
    expect(
      () => RegularSeasonState(
        seasonId: schedule.seasonId,
        seasonYear: schedule.seasonYear,
        scheduleSeed: schedule.scheduleSeed,
        openingTeams: teams,
        gameResults: const {},
        schedule: completed,
      ),
      throwsFormatException,
    );
  });

  test(
    'v16 schedule state migrates with scheduled fixtures and empty results',
    () {
      final teams = _teams();
      final schedule = _schedule(teams);
      final decoded = RegularSeasonState.fromJson({
        'seasonId': schedule.seasonId,
        'seasonYear': schedule.seasonYear,
        'scheduleSeed': schedule.scheduleSeed,
        'openingTeams': [for (final team in teams) team.toJson()],
        'gameResults': <String, Object?>{},
        'schedule': schedule.toJson(),
      }, schemaVersion: 16);
      expect(decoded.gameResults, isEmpty);
      expect(decoded.completedGames, 0);
      expect(decoded.schedule!.remainingGamesCount, 1230);
    },
  );
  test('progress accepts the final scheduled round without a short limit', () {
    final teams = _teams();
    final schedule = _schedule(teams);
    final completed = RegularSeasonSchedule(
      seasonId: schedule.seasonId,
      seasonYear: schedule.seasonYear,
      scheduleSeed: schedule.scheduleSeed,
      rounds: [
        for (final round in schedule.rounds)
          RegularSeasonRound(
            roundNumber: round.roundNumber,
            fixtures: [
              for (final fixture in round.fixtures)
                if (round.roundNumber < 82)
                  RegularSeasonFixture(
                    id: fixture.id,
                    seasonId: fixture.seasonId,
                    seasonYear: fixture.seasonYear,
                    roundNumber: fixture.roundNumber,
                    fixturePosition: fixture.fixturePosition,
                    homeTeamId: fixture.homeTeamId,
                    awayTeamId: fixture.awayTeamId,
                    gameSeed: fixture.gameSeed,
                    status: RegularSeasonFixtureStatus.completed,
                  )
                else
                  fixture,
            ],
          ),
      ],
    );
    final results = {
      for (final fixture in completed.allFixtures)
        if (fixture.status == RegularSeasonFixtureStatus.completed)
          fixture.id: _result(fixture),
    };
    final state = RegularSeasonState(
      seasonId: schedule.seasonId,
      seasonYear: schedule.seasonYear,
      scheduleSeed: schedule.scheduleSeed,
      openingTeams: teams,
      gameResults: results,
      schedule: completed,
    );

    expect(state.completedRounds, 81);
    expect(state.completedGames, 1215);
    expect(state.remainingGames, 15);
    expect(state.nextUnfinishedRoundNumber, 82);
    final fullSchedule = RegularSeasonSchedule(
      seasonId: schedule.seasonId,
      seasonYear: schedule.seasonYear,
      scheduleSeed: schedule.scheduleSeed,
      rounds: [
        for (final round in schedule.rounds)
          RegularSeasonRound(
            roundNumber: round.roundNumber,
            fixtures: [
              for (final fixture in round.fixtures)
                RegularSeasonFixture(
                  id: fixture.id,
                  seasonId: fixture.seasonId,
                  seasonYear: fixture.seasonYear,
                  roundNumber: fixture.roundNumber,
                  fixturePosition: fixture.fixturePosition,
                  homeTeamId: fixture.homeTeamId,
                  awayTeamId: fixture.awayTeamId,
                  gameSeed: fixture.gameSeed,
                  status: RegularSeasonFixtureStatus.completed,
                ),
            ],
          ),
      ],
    );
    final fullResults = <String, RegularSeasonGameResult>{
      ...results,
      for (final fixture in fullSchedule.rounds.last.fixtures)
        fixture.id: _result(fixture),
    };
    final finishedState = RegularSeasonState(
      seasonId: schedule.seasonId,
      seasonYear: schedule.seasonYear,
      scheduleSeed: schedule.scheduleSeed,
      openingTeams: teams,
      gameResults: fullResults,
      schedule: fullSchedule,
    );
    expect(finishedState.completedRounds, 82);
    expect(finishedState.completedGames, 1230);
    expect(finishedState.remainingGames, 0);
    expect(finishedState.nextUnfinishedRoundNumber, isNull);
    expect(finishedState.gamesPlayedForTeam(teams.first.teamId), 82);
  });
  test(
    'round simulation is deterministic and completes exactly 15 fixtures',
    () {
      final career = _scheduledCareer();
      final service = const RegularSeasonRoundService();
      final first = service.simulateNextRound(career, expectedRoundNumber: 1);
      final second = service.simulateNextRound(career, expectedRoundNumber: 1);
      expect(first.regularSeasonState!.gameResults.length, 15);
      expect(
        jsonEncode({
          for (final entry in first.regularSeasonState!.gameResults.entries)
            entry.key: entry.value.toJson(),
        }),
        jsonEncode({
          for (final entry in second.regularSeasonState!.gameResults.entries)
            entry.key: entry.value.toJson(),
        }),
      );
      expect(career.regularSeasonState!.gameResults, isEmpty);
      expect(first.league, same(career.league));
      expect(first.finances, same(career.finances));
      expect(first.currentYear, career.currentYear);
    },
  );

  test('a failed fixture leaves input career wholly unplayed', () {
    final career = _scheduledCareer();
    var calls = 0;
    expect(
      () => const RegularSeasonRoundService().simulateNextRoundForTesting(
        career,
        expectedRoundNumber: 1,
        beforeGame: () {
          calls++;
          if (calls == 2) throw StateError('injected game failure');
        },
      ),
      throwsStateError,
    );
    expect(calls, 2);
    expect(career.regularSeasonState!.gameResults, isEmpty);
    expect(career.regularSeasonState!.completedGames, 0);
  });
  test('historical game evidence survives public player progression', () {
    final service = const RegularSeasonRoundService();
    final career = service.simulateNextRound(
      _scheduledCareer(),
      expectedRoundNumber: 1,
    );
    final state = career.regularSeasonState!;
    expect(state.gameInputSnapshots, hasLength(1));
    final team = career.league.teams.first;
    final player = team.roster.standardPlayers.first;
    final ratings = Map<String, Object?>.from(player.attributes.asMap)
      ..['threePoint'] = (player.attributes.threePoint + 1) % 101;
    final progressedPlayer = Player(
      id: player.id,
      firstName: player.firstName,
      lastName: player.lastName,
      position: player.position,
      attributes: PlayerAttributes.fromJson(ratings),
    );
    final progressedTeam = team.copyWith(
      roster: Roster([
        for (final rostered in team.players)
          if (rostered.id == player.id) progressedPlayer else rostered,
      ], categories: team.roster.categories),
    );

    final progressedCareer = career.withUpdatedTeam(progressedTeam);

    expect(() => progressedCareer.validate(), returnsNormally);
    expect(
      progressedCareer
          .regularSeasonState!
          .gameResults
          .values
          .first
          .inputFingerprint,
      state.gameResults.values.first.inputFingerprint,
    );
  });

  test('unsupported versions and altered snapshots are rejected', () {
    final career = const RegularSeasonRoundService().simulateNextRound(
      _scheduledCareer(),
      expectedRoundNumber: 1,
    );
    final state = career.regularSeasonState!;
    final first = state.gameResults.entries.first;
    final unsupportedResults = Map<String, RegularSeasonGameResult>.of(
      state.gameResults,
    )..[first.key] = _copyResult(first.value, simulationVersion: 99);
    expect(
      () => career.copyWith(
        regularSeasonState: state.copyWith(gameResults: unsupportedResults),
      ),
      throwsFormatException,
    );

    final snapshotId = state.gameInputSnapshots.keys.first;
    final alteredSnapshot =
        jsonDecode(state.gameInputSnapshots[snapshotId]!)
              as Map<String, dynamic>
          ..['name'] = 'Altered historical league';
    final alteredSnapshots = Map<String, String>.of(state.gameInputSnapshots)
      ..[snapshotId] = jsonEncode(alteredSnapshot);
    expect(
      () => career.copyWith(
        regularSeasonState: state.copyWith(
          gameInputSnapshots: alteredSnapshots,
        ),
      ),
      throwsFormatException,
    );
  });
}
