import 'package:basketball_manager/features/game/game_result_view.dart';
import 'package:basketball_manager/features/game/game_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

import 'game_fixtures.dart';

/// Builds a validated result for the same-clock, zero-second entrant: the
/// substitute enters after a defensive foul and leaves after committing a foul
/// of their own, so `secondsPlayed == 0` while `personalFouls == 1`.
GameResult _zeroSecondEntrantResult(League league) {
  final home = league.teams[testHomeIndex];
  final away = league.teams[testAwayIndex];
  final input = GameInput.create(
    gameId: 't09-zero-second',
    league: league,
    homeTeamId: home.id,
    awayTeamId: away.id,
    homeLineup: CourtLineup.defaultFor(home),
    awayLineup: CourtLineup.defaultFor(away),
    seed: 42,
    rules: GameRules.standard,
  );
  final offense = input.startingTeamId;
  final defense = input.opponentOf(offense);
  final offensePg = input.lineupFor(offense).playerIdAt(Position.pg).value;
  final offenseSg = input.lineupFor(offense).playerIdAt(Position.sg).value;
  final defender = input.lineupFor(defense).playerIdAt(Position.pg).value;
  final defenseTeam = league.teams.firstWhere(
    (team) => team.id.value == defense.value,
  );
  final entrant = defenseTeam.players
      .firstWhere(
        (player) => !input.lineupFor(defense).containsPlayer(player.id),
      )
      .id
      .value;

  final events = <GameEvent>[
    GameStarted(
      sequence: 1,
      period: 1,
      gameClock: 720,
      shotClock: null,
      homeTeamId: input.homeTeamId.value,
      awayTeamId: input.awayTeamId.value,
      startingTeamId: offense.value,
    ),
    PeriodStarted(
      sequence: 2,
      period: 1,
      gameClock: 720,
      shotClock: null,
      startingTeamId: offense.value,
    ),
    PossessionStarted(
      sequence: 3,
      period: 1,
      gameClock: 700,
      shotClock: 24,
      possessionId: 'p1',
      offenseTeamId: offense.value,
    ),
    PersonalFoul(
      sequence: 4,
      period: 1,
      gameClock: 690,
      shotClock: 14,
      committingTeamId: defense.value,
      committingPlayerId: defender,
      drawnByPlayerId: offensePg,
      kind: FoulKind.nonShooting,
      freeThrowsAwarded: 0,
      bonus: false,
    ),
    Substitution(
      sequence: 5,
      period: 1,
      gameClock: 690,
      shotClock: 14,
      teamId: defense.value,
      playerOutId: defender,
      playerInId: entrant,
      reason: SubstitutionReason.tactical,
    ),
    PersonalFoul(
      sequence: 6,
      period: 1,
      gameClock: 690,
      shotClock: 14,
      committingTeamId: defense.value,
      committingPlayerId: entrant,
      drawnByPlayerId: offenseSg,
      kind: FoulKind.nonShooting,
      freeThrowsAwarded: 0,
      bonus: false,
    ),
    Substitution(
      sequence: 7,
      period: 1,
      gameClock: 690,
      shotClock: 14,
      teamId: defense.value,
      playerOutId: entrant,
      playerInId: defender,
      reason: SubstitutionReason.tactical,
    ),
  ];
  final ledger = GameEventLedger(
    gameId: input.gameId,
    inputFingerprint: GameFingerprint.of(input),
    events: events,
  );
  final validated = GameEventReducer.validate(input, ledger);
  final box = EventAccounting.aggregate(validated);
  return GameResult(
    input: input,
    inputFingerprint: GameFingerprint.of(input),
    ledger: ledger,
    state: validated.state,
    boxScore: box,
    homeScore: box.teams[input.homeTeamId.value]!.points,
    awayScore: box.teams[input.awayTeamId.value]!.points,
    periodsPlayed: validated.state.period,
    possessions: validated.events.whereType<PossessionStarted>().length,
    simulationVersion: gameSimulationVersion,
    rulesVersion: gameRulesVersion,
    eventSchemaVersion: gameEventSchemaVersion,
    prngImplementationId: 'xorshift32-v1',
  );
}

Future<void> _pumpView(
  WidgetTester tester,
  GameRequest request,
  GameResult result, {
  Size size = const Size(430, 4000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GameResultView(
          request: request,
          result: result,
          seedCycleRepeated: false,
          onRematch: () {},
          onReturnToLeague: () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

String _text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

bool _hasKey(WidgetTester tester, Key key) =>
    find.byKey(key).evaluate().isNotEmpty;

void main() {
  late League league;
  late GameRequest baseRequest;
  late GameResult base;
  late GameRequest depletedRequest;
  late GameResult depleted;
  late GameRequest hornRequest;
  late GameResult horn;

  setUpAll(() {
    league = generateTestLeague();
    baseRequest = testRequest(league);
    base = simulateRequest(baseRequest);

    final smallLeague = const LeagueGenerator().generate(
      const GenerationConfig(seed: 20261028, teamCount: 2, playersPerTeam: 5),
    );
    depletedRequest = GameRequest(
      league: smallLeague,
      homeTeamId: smallLeague.teams[0].id,
      awayTeamId: smallLeague.teams[1].id,
      seed: 1,
    );
    depleted = simulateRequest(depletedRequest);

    // T08 slot 97: final-horn disqualification without replacement.
    hornRequest = GameRequest(
      league: league,
      homeTeamId: league.teams[0].id,
      awayTeamId: league.teams[1].id,
      seed: 20098,
    );
    horn = simulateRequest(hornRequest);
  });

  testWidgets('zero-second entrant with production stays visible', (
    tester,
  ) async {
    final result = _zeroSecondEntrantResult(league);
    final defense = result.input.opponentOf(result.input.startingTeamId);
    final entrant = result.boxScore.players.values
        .where(
          (box) =>
              box.teamId == defense.value &&
              box.secondsPlayed == 0 &&
              box.personalFouls == 1,
        )
        .single;
    await _pumpView(tester, baseRequest, result);

    expect(_hasKey(tester, ValueKey('player-row-${entrant.playerId}')), isTrue);
    expect(
      _text(tester, ValueKey('player-stat-${entrant.playerId}-MIN')),
      '0:00',
    );
    expect(_text(tester, ValueKey('player-stat-${entrant.playerId}-PF')), '1');
    expect(
      _text(tester, ValueKey('player-role-${entrant.playerId}')),
      'SUBSTITUTE',
    );
  });

  testWidgets('replaced foul-outs are labelled as fouled out', (tester) async {
    final substituted = base.events
        .whereType<Substitution>()
        .where((sub) => sub.reason == SubstitutionReason.foulOut)
        .toList();
    expect(substituted, isNotEmpty);
    await _pumpView(tester, baseRequest, base);

    for (final sub in substituted) {
      expect(
        _text(tester, ValueKey('player-status-${sub.playerOutId}')),
        'Fouled out',
        reason: '${sub.playerOutId} was replaced',
      );
    }
  });

  testWidgets('depleted continuation is distinguished from a foul-out', (
    tester,
  ) async {
    final sixFouls = <String>{};
    final counts = <String, int>{};
    for (final event in depleted.events.whereType<PersonalFoul>()) {
      counts[event.committingPlayerId] =
          (counts[event.committingPlayerId] ?? 0) + 1;
      if (counts[event.committingPlayerId] == 6) {
        sixFouls.add(event.committingPlayerId);
      }
    }
    expect(sixFouls, isNotEmpty);
    await _pumpView(tester, depletedRequest, depleted);

    for (final playerId in sixFouls) {
      expect(
        _text(tester, ValueKey('player-status-$playerId')),
        'Fouled out — continued (no bench)',
      );
    }
  });

  testWidgets('final-horn foul-out is not labelled depleted continuation', (
    tester,
  ) async {
    const hornPlayer = 'player-2-1';
    expect(horn.events.whereType<Substitution>(), isNotEmpty);
    await _pumpView(tester, hornRequest, horn);

    expect(
      _text(tester, const ValueKey('player-status-$hornPlayer')),
      'Fouled out at the horn',
    );
    expect(
      _text(tester, const ValueKey('player-status-$hornPlayer')),
      isNot(contains('continued')),
    );
  });
}
