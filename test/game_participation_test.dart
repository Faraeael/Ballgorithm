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

/// Valid depleted-roster ledger: the sixth foul is a shooting foul at the
/// final horn, followed by the made or missed final free throw and GameEnded.
GameResult _hornShootingResult(League league, {required bool madeFinalFt}) {
  final home = league.teams[0];
  final away = league.teams[1];
  final input = GameInput.create(
    gameId: madeFinalFt ? 't09-horn-made' : 't09-horn-missed',
    league: league,
    homeTeamId: home.id,
    awayTeamId: away.id,
    homeLineup: CourtLineup.defaultFor(home),
    awayLineup: CourtLineup.defaultFor(away),
    seed: 1,
    rules: GameRules(bonusRegulationFouls: 10, bonusOvertimeFouls: 10),
  );
  expect(input.startingTeamId, away.id);
  expect(input.lineupFor(home.id).playerIds, hasLength(5));
  final homePg = input.lineupFor(home.id).playerIdAt(Position.pg).value;
  final awayPg = input.lineupFor(away.id).playerIdAt(Position.pg).value;

  final events = <GameEvent>[];
  var sequence = 0;
  void add(GameEvent event) => events.add(event);
  GameStarted started() => GameStarted(
    sequence: ++sequence,
    period: 1,
    gameClock: 720,
    shotClock: null,
    homeTeamId: input.homeTeamId.value,
    awayTeamId: input.awayTeamId.value,
    startingTeamId: input.startingTeamId.value,
  );
  PeriodStarted periodStart(int period, TeamId starter) => PeriodStarted(
    sequence: ++sequence,
    period: period,
    gameClock: 720,
    shotClock: null,
    startingTeamId: starter.value,
  );
  PeriodEnded periodEnd(int period) => PeriodEnded(
    sequence: ++sequence,
    period: period,
    gameClock: 0,
    shotClock: null,
  );

  add(started());
  add(periodStart(1, away.id));
  add(periodEnd(1));
  add(periodStart(2, home.id));
  add(periodEnd(2));
  add(periodStart(3, away.id));
  add(periodEnd(3));
  add(periodStart(4, home.id));
  add(
    PossessionStarted(
      sequence: ++sequence,
      period: 4,
      gameClock: 2,
      shotClock: 24,
      possessionId: 'p1',
      offenseTeamId: home.id.value,
    ),
  );
  add(
    Turnover(
      sequence: ++sequence,
      period: 4,
      gameClock: 1,
      shotClock: 23,
      teamId: home.id.value,
      playerId: homePg,
      reason: TurnoverReason.nonSteal,
      stolenById: null,
    ),
  );
  add(
    PossessionEnded(
      sequence: ++sequence,
      period: 4,
      gameClock: 1,
      shotClock: 23,
      possessionId: 'p1',
      offenseTeamId: home.id.value,
      reason: PossessionEndReason.turnover,
    ),
  );
  add(
    PossessionStarted(
      sequence: ++sequence,
      period: 4,
      gameClock: 1,
      shotClock: 24,
      possessionId: 'p2',
      offenseTeamId: away.id.value,
    ),
  );
  for (var i = 0; i < 5; i++) {
    add(
      PersonalFoul(
        sequence: ++sequence,
        period: 4,
        gameClock: 0,
        shotClock: 23,
        committingTeamId: home.id.value,
        committingPlayerId: homePg,
        drawnByPlayerId: awayPg,
        kind: FoulKind.nonShooting,
        freeThrowsAwarded: 0,
        bonus: false,
      ),
    );
  }
  add(
    PersonalFoul(
      sequence: ++sequence,
      period: 4,
      gameClock: 0,
      shotClock: 23,
      committingTeamId: home.id.value,
      committingPlayerId: homePg,
      drawnByPlayerId: awayPg,
      kind: FoulKind.shooting,
      freeThrowsAwarded: 2,
      bonus: false,
    ),
  );
  add(
    FreeThrowAttempt(
      sequence: ++sequence,
      period: 4,
      gameClock: 0,
      shotClock: 23,
      teamId: away.id.value,
      shooterId: awayPg,
      groupId: 'g',
      attemptIndex: 1,
      attemptsInGroup: 2,
      made: true,
      lastOfGroup: false,
    ),
  );
  final second = FreeThrowAttempt(
    sequence: ++sequence,
    period: 4,
    gameClock: 0,
    shotClock: 23,
    teamId: away.id.value,
    shooterId: awayPg,
    groupId: 'g',
    attemptIndex: 2,
    attemptsInGroup: 2,
    made: madeFinalFt,
    lastOfGroup: true,
  );
  add(second);
  if (!madeFinalFt) {
    add(
      DeadBallMiss(
        sequence: ++sequence,
        period: 4,
        gameClock: 0,
        shotClock: 23,
        teamId: away.id.value,
        missedEventSequence: second.sequence,
        reason: DeadBallReason.periodEnd,
      ),
    );
  }
  add(
    PossessionEnded(
      sequence: ++sequence,
      period: 4,
      gameClock: 0,
      shotClock: 23,
      possessionId: 'p2',
      offenseTeamId: away.id.value,
      reason: madeFinalFt
          ? PossessionEndReason.madeFinalFreeThrow
          : PossessionEndReason.periodEnd,
    ),
  );
  add(periodEnd(4));
  add(
    GameEnded(
      sequence: ++sequence,
      period: 4,
      gameClock: 0,
      shotClock: null,
      finalPeriod: 4,
    ),
  );

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

/// Valid ledger: starter A is tactically removed in an early W5 window,
/// re-admitted in the period-4 W5 window, then reaches the sixth foul at the
/// final horn with no removal afterwards. A's early removal must not be read
/// as the disqualification replacement.
GameResult _reentryHornResult(League league) {
  final home = league.teams[testHomeIndex];
  final away = league.teams[testAwayIndex];
  final input = GameInput.create(
    gameId: 't09-reentry-horn',
    league: league,
    homeTeamId: home.id,
    awayTeamId: away.id,
    homeLineup: CourtLineup.defaultFor(home),
    awayLineup: CourtLineup.defaultFor(away),
    seed: 1,
    rules: GameRules(bonusRegulationFouls: 10, bonusOvertimeFouls: 10),
  );
  final homePg = input.lineupFor(home.id).playerIdAt(Position.pg).value;
  final awayPg = input.lineupFor(away.id).playerIdAt(Position.pg).value;
  final bench = home.players
      .firstWhere(
        (player) => !input.lineupFor(home.id).containsPlayer(player.id),
      )
      .id
      .value;
  expect(input.startingTeamId, away.id);

  final events = <GameEvent>[];
  var sequence = 0;
  void add(GameEvent event) => events.add(event);
  PeriodStarted periodStart(int period, TeamId starter) => PeriodStarted(
    sequence: ++sequence,
    period: period,
    gameClock: 720,
    shotClock: null,
    startingTeamId: starter.value,
  );
  PeriodEnded periodEnd(int period) => PeriodEnded(
    sequence: ++sequence,
    period: period,
    gameClock: 0,
    shotClock: null,
  );
  Substitution sub(String outId, String inId) => Substitution(
    sequence: ++sequence,
    period: 1,
    gameClock: 720,
    shotClock: null,
    teamId: home.id.value,
    playerOutId: outId,
    playerInId: inId,
    reason: SubstitutionReason.tactical,
  );

  add(
    GameStarted(
      sequence: ++sequence,
      period: 1,
      gameClock: 720,
      shotClock: null,
      homeTeamId: input.homeTeamId.value,
      awayTeamId: input.awayTeamId.value,
      startingTeamId: input.startingTeamId.value,
    ),
  );
  add(periodStart(1, away.id));
  add(sub(homePg, bench));
  add(periodEnd(1));
  add(periodStart(2, home.id));
  add(periodEnd(2));
  add(periodStart(3, away.id));
  add(periodEnd(3));
  add(periodStart(4, home.id));
  final reentry = Substitution(
    sequence: ++sequence,
    period: 4,
    gameClock: 720,
    shotClock: null,
    teamId: home.id.value,
    playerOutId: bench,
    playerInId: homePg,
    reason: SubstitutionReason.tactical,
  );
  add(reentry);
  add(
    PossessionStarted(
      sequence: ++sequence,
      period: 4,
      gameClock: 2,
      shotClock: 24,
      possessionId: 'p1',
      offenseTeamId: home.id.value,
    ),
  );
  add(
    Turnover(
      sequence: ++sequence,
      period: 4,
      gameClock: 1,
      shotClock: 23,
      teamId: home.id.value,
      playerId: homePg,
      reason: TurnoverReason.nonSteal,
      stolenById: null,
    ),
  );
  add(
    PossessionEnded(
      sequence: ++sequence,
      period: 4,
      gameClock: 1,
      shotClock: 23,
      possessionId: 'p1',
      offenseTeamId: home.id.value,
      reason: PossessionEndReason.turnover,
    ),
  );
  add(
    PossessionStarted(
      sequence: ++sequence,
      period: 4,
      gameClock: 1,
      shotClock: 24,
      possessionId: 'p2',
      offenseTeamId: away.id.value,
    ),
  );
  for (var i = 0; i < 5; i++) {
    add(
      PersonalFoul(
        sequence: ++sequence,
        period: 4,
        gameClock: 0,
        shotClock: 23,
        committingTeamId: home.id.value,
        committingPlayerId: homePg,
        drawnByPlayerId: awayPg,
        kind: FoulKind.nonShooting,
        freeThrowsAwarded: 0,
        bonus: false,
      ),
    );
  }
  add(
    PersonalFoul(
      sequence: ++sequence,
      period: 4,
      gameClock: 0,
      shotClock: 23,
      committingTeamId: home.id.value,
      committingPlayerId: homePg,
      drawnByPlayerId: awayPg,
      kind: FoulKind.shooting,
      freeThrowsAwarded: 2,
      bonus: false,
    ),
  );
  add(
    FreeThrowAttempt(
      sequence: ++sequence,
      period: 4,
      gameClock: 0,
      shotClock: 23,
      teamId: away.id.value,
      shooterId: awayPg,
      groupId: 'g',
      attemptIndex: 1,
      attemptsInGroup: 2,
      made: true,
      lastOfGroup: false,
    ),
  );
  add(
    FreeThrowAttempt(
      sequence: ++sequence,
      period: 4,
      gameClock: 0,
      shotClock: 23,
      teamId: away.id.value,
      shooterId: awayPg,
      groupId: 'g',
      attemptIndex: 2,
      attemptsInGroup: 2,
      made: true,
      lastOfGroup: true,
    ),
  );
  add(
    PossessionEnded(
      sequence: ++sequence,
      period: 4,
      gameClock: 0,
      shotClock: 23,
      possessionId: 'p2',
      offenseTeamId: away.id.value,
      reason: PossessionEndReason.madeFinalFreeThrow,
    ),
  );
  add(periodEnd(4));
  add(
    GameEnded(
      sequence: ++sequence,
      period: 4,
      gameClock: 0,
      shotClock: null,
      finalPeriod: 4,
    ),
  );

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

  for (final size in const [
    (label: '360x640', size: Size(360, 640)),
    (label: '393x852', size: Size(393, 852)),
    (label: '430x932', size: Size(430, 932)),
  ]) {
    testWidgets(
      '${size.label}: zero-second entrant is reachable and readable',
      (tester) async {
        final result = _zeroSecondEntrantResult(league);
        final entrant = result.boxScore.players.values.singleWhere(
          (box) => box.secondsPlayed == 0 && box.personalFouls == 1,
        );
        await _pumpView(tester, baseRequest, result, size: size.size);

        final list = find.byKey(const ValueKey('game-success'));
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('player-row-${entrant.playerId}')),
          250,
          scrollable: find
              .descendant(of: list, matching: find.byType(Scrollable))
              .first,
        );
        expect(
          find.byKey(ValueKey('player-row-${entrant.playerId}')),
          findsOneWidget,
        );
        expect(entrant.secondsPlayed, 0);
        expect(entrant.personalFouls, 1);
        expect(
          tester
              .widget<Text>(
                find.byKey(ValueKey('player-stat-${entrant.playerId}-MIN')),
              )
              .data,
          '0:00',
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(ValueKey('player-stat-${entrant.playerId}-PF')),
              )
              .data,
          '1',
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(ValueKey('player-role-${entrant.playerId}')),
              )
              .data,
          'SUBSTITUTE',
        );
        expect(tester.takeException(), isNull, reason: 'no layout overflow');

        final pts = find.byKey(ValueKey('player-stat-${entrant.playerId}-PTS'));
        await tester.ensureVisible(pts);
        await tester.pumpAndSettle();
        final identityBefore = tester.getTopLeft(
          find.byKey(ValueKey('player-name-${entrant.playerId}')),
        );
        await tester.dragFrom(tester.getCenter(pts), const Offset(-420, 0));
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('player-name-${entrant.playerId}')),
          findsOneWidget,
        );
        expect(
          tester.getTopLeft(
            find.byKey(ValueKey('player-name-${entrant.playerId}')),
          ),
          identityBefore,
          reason: 'identity stays fixed while statistics scroll',
        );
        expect(
          tester
              .getRect(
                find.byKey(ValueKey('player-stat-${entrant.playerId}-PF')),
              )
              .left,
          lessThan(size.size.width),
          reason: 'PF reachable at ${size.label}',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'no overflow after scroll',
        );
      },
    );
  }

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

  testWidgets(
    'final-horn shooting foul-out is horn, not depleted, when FT is made',
    (tester) async {
      final smallLeague = depletedRequest.league;
      final result = _hornShootingResult(smallLeague, madeFinalFt: true);
      expect(result.events.whereType<Substitution>(), isEmpty);
      final homePg = result.input
          .lineupFor(result.input.homeTeamId)
          .playerIdAt(Position.pg)
          .value;
      await _pumpView(tester, depletedRequest, result);
      expect(
        _text(tester, ValueKey('player-status-$homePg')),
        'Fouled out at the horn',
      );
      expect(
        _text(tester, ValueKey('player-status-$homePg')),
        isNot(contains('continued')),
      );
    },
  );

  testWidgets(
    'final-horn shooting foul-out is horn, not depleted, when FT is missed',
    (tester) async {
      final smallLeague = depletedRequest.league;
      final result = _hornShootingResult(smallLeague, madeFinalFt: false);
      expect(result.events.whereType<Substitution>(), isEmpty);
      final homePg = result.input
          .lineupFor(result.input.homeTeamId)
          .playerIdAt(Position.pg)
          .value;
      await _pumpView(tester, depletedRequest, result);
      expect(
        _text(tester, ValueKey('player-status-$homePg')),
        'Fouled out at the horn',
      );
      expect(
        _text(tester, ValueKey('player-status-$homePg')),
        isNot(contains('continued')),
      );
    },
  );

  testWidgets(
    're-entry after a tactical removal is not treated as foul-out replacement',
    (tester) async {
      final result = _reentryHornResult(league);
      final homePg = result.input
          .lineupFor(result.input.homeTeamId)
          .playerIdAt(Position.pg)
          .value;
      expect(result.events.whereType<Substitution>(), hasLength(2));
      await _pumpView(tester, baseRequest, result);
      expect(
        _text(tester, ValueKey('player-status-$homePg')),
        'Fouled out at the horn',
      );
      expect(
        _text(tester, ValueKey('player-status-$homePg')),
        isNot('Fouled out'),
      );
    },
  );

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
