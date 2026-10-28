import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';

Matcher throwsCode(GameValidationCode code) => throwsA(
  isA<GameValidationException>().having(
    (e) => e.codes,
    'codes',
    contains(code),
  ),
);

GameScript regulationGame(GameInput input, {required bool tie}) {
  final s = GameScript(input)..startGame();
  final first = input.startingTeamId;
  final second = input.opponentOf(first);
  for (var period = 1; period <= 4; period++) {
    final team = period.isOdd ? first : second;
    s.startPeriod(period, team);
    s.startPossession('r$period', team, clock: 24);
    if (period == 1 || (tie && period == 2)) {
      s.fga(
        team: team,
        shooter: playerAt(input, team, Position.pg),
        clock: 0,
        shotClock: 0,
      );
      s.endPossession(
        possessionId: 'r$period',
        team: team,
        reason: PossessionEndReason.madeFieldGoal,
        clock: 0,
        shotClock: 0,
      );
    } else {
      s.endPossession(
        possessionId: 'r$period',
        team: team,
        reason: PossessionEndReason.periodEnd,
        clock: 0,
        shotClock: 24,
      );
    }
    s.endPeriod(period);
  }
  return s;
}

void main() {
  late GameInput input;
  late TeamId home;
  late TeamId away;
  late String homePg;
  late String awayPg;
  late TeamId starter;
  late TeamId other;

  setUp(() {
    input = buildInput();
    home = input.homeTeamId;
    away = input.awayTeamId;
    homePg = playerAt(input, home, Position.pg);
    awayPg = playerAt(input, away, Position.pg);
    starter = input.startingTeamId;
    other = input.opponentOf(starter);
  });

  GameScript script({GameRules? rules}) {
    final value = input;
    final built = value.rules == rules
        ? buildInput()
        : buildInput(rules: rules);
    // Rebuild dependent ids for custom rules only; tests that use custom rules
    // do not rely on the setUp ids.
    return GameScript(built)
      ..startGame()
      ..startPeriod(1, built.startingTeamId);
  }

  test('rejects a live phase longer than the shot clock', () {
    final s = script();
    s.startPossession('p1', starter, clock: 720, shotClock: 24);
    s.fga(team: starter, shooter: homePg, clock: 0, shotClock: 24);
    expect(
      () => GameEventReducer.replay(s.input, s.ledger()),
      throwsCode(GameValidationCode.shotClockElapsedMismatch),
    );
  });

  test('replays a legal made field goal and closes the possession', () {
    final s = script();
    s.startPossession('p1', starter, clock: 700, shotClock: 24);
    s.fga(team: starter, shooter: homePg, clock: 690, shotClock: 14);
    s.endPossession(
      possessionId: 'p1',
      team: starter,
      reason: PossessionEndReason.madeFieldGoal,
      clock: 690,
      shotClock: 14,
    );
    final state = GameEventReducer.replay(s.input, s.ledger());
    expect(state.hasOpenPossession, isFalse);
    expect(state.period, 1);
    expect(state.gameClock, 690);
  });

  test('replays an overtime game with alternating starters', () {
    final s = GameScript(input)..startGame();
    final first = input.startingTeamId;
    final second = input.opponentOf(first);
    final sequence = [first, second, first, second, first];
    for (var i = 0; i < sequence.length; i++) {
      final period = i + 1;
      final team = sequence[i];
      final clock = period <= 4 ? 720 : 300;
      s.startPeriod(period, team, clock: clock);
      s.startPossession('p$period', team, clock: 24);
      s.fga(
        team: team,
        shooter: playerAt(input, team, Position.pg),
        clock: 0,
        shotClock: 0,
      );
      s.endPossession(
        possessionId: 'p$period',
        team: team,
        reason: PossessionEndReason.madeFieldGoal,
        clock: 0,
        shotClock: 0,
      );
      s.endPeriod(period);
    }
    s.endGame(5);
    final state = GameEventReducer.replay(input, s.ledger());
    expect(state.ended, isTrue);
    final score = account(input, s.events);
    expect(score.teams[first.value]!.points, 6);
    expect(score.teams[second.value]!.points, 4);
  });

  test('rejects a second GameStarted', () {
    final s = script();
    s.startPossession('p1', starter);
    s.events.add(
      GameStarted(
        sequence: s.events.length + 1,
        period: 1,
        gameClock: 700,
        shotClock: null,
        homeTeamId: home.value,
        awayTeamId: away.value,
        startingTeamId: starter.value,
      ),
    );
    expect(
      () => GameEventReducer.replay(s.input, s.ledger()),
      throwsCode(GameValidationCode.duplicateGameStarted),
    );
  });

  test('rejects duplicate, non-increasing and post-game sequences', () {
    final duplicate = <GameEvent>[
      GameStarted(
        sequence: 1,
        period: 1,
        gameClock: 720,
        shotClock: null,
        homeTeamId: home.value,
        awayTeamId: away.value,
        startingTeamId: starter.value,
      ),
      PeriodStarted(
        sequence: 2,
        period: 1,
        gameClock: 720,
        shotClock: null,
        startingTeamId: starter.value,
      ),
      PossessionStarted(
        sequence: 2,
        period: 1,
        gameClock: 700,
        shotClock: 24,
        possessionId: 'p1',
        offenseTeamId: starter.value,
      ),
    ];
    expect(
      () => GameEventReducer.replayEvents(input, duplicate),
      throwsCode(GameValidationCode.invalidEventSequence),
    );

    final s = script();
    s.startPossession('p1', starter, clock: 700);
    s.fga(team: starter, shooter: homePg, clock: 690, shotClock: 14);
    s.endPossession(
      possessionId: 'p1',
      team: starter,
      reason: PossessionEndReason.madeFieldGoal,
      clock: 700,
      shotClock: 14,
    );
    expect(
      () => GameEventReducer.replay(s.input, s.ledger()),
      throwsCode(GameValidationCode.gameClockIncreased),
    );
  });

  test('enforces clock bounds and legal reset-only increases', () {
    final s = script();
    s.startPossession('p1', starter, clock: 700, shotClock: 24);
    s.foul(
      team: other,
      player: awayPg,
      kind: FoulKind.nonShooting,
      freeThrows: 0,
      bonus: false,
      drawnBy: homePg,
      clock: 690,
      shotClock: 14,
    );
    s.fga(team: starter, shooter: homePg, clock: 680, shotClock: 15);
    expect(
      () => GameEventReducer.replay(s.input, s.ledger()),
      throwsCode(GameValidationCode.illegalShotClockIncrease),
    );

    final legal = script();
    legal.startPossession('p1', starter, clock: 700, shotClock: 24);
    legal.foul(
      team: other,
      player: awayPg,
      kind: FoulKind.nonShooting,
      freeThrows: 0,
      bonus: false,
      drawnBy: homePg,
      clock: 690,
      shotClock: 14,
    );
    legal.fga(team: starter, shooter: homePg, clock: 680, shotClock: 4);
    legal.endPossession(
      possessionId: 'p1',
      team: starter,
      reason: PossessionEndReason.madeFieldGoal,
      clock: 680,
      shotClock: 4,
    );
    expect(
      GameEventReducer.replay(legal.input, legal.ledger()).hasOpenPossession,
      isFalse,
    );

    final negative = script();
    negative.startPossession('p1', starter, clock: 700);
    negative.fga(team: starter, shooter: homePg, clock: -1, shotClock: 24);
    expect(
      () => GameEventReducer.replay(negative.input, negative.ledger()),
      throwsCode(GameValidationCode.invalidGameClock),
    );
  });

  test('rejects events without a possession or with wrong attribution', () {
    final noPossession = GameScript(input)
      ..startGame()
      ..startPeriod(1, starter);
    noPossession.fga(team: starter, shooter: homePg);
    expect(
      () => GameEventReducer.replay(noPossession.input, noPossession.ledger()),
      throwsCode(GameValidationCode.noOpenPossession),
    );

    final wrongTeam = script();
    wrongTeam.startPossession('p1', starter);
    wrongTeam.fga(team: other, shooter: awayPg);
    expect(
      () => GameEventReducer.replay(wrongTeam.input, wrongTeam.ledger()),
      throwsCode(GameValidationCode.wrongTeam),
    );
  });

  test('resolves steal, shot-clock and offensive-foul turnovers', () {
    final steal = script();
    steal.startPossession('p1', starter);
    steal.turnover(
      team: starter,
      player: homePg,
      reason: TurnoverReason.steal,
      stolenBy: awayPg,
      clock: 690,
      shotClock: 14,
    );
    steal.endPossession(
      possessionId: 'p1',
      team: starter,
      reason: PossessionEndReason.turnover,
      clock: 690,
      shotClock: 14,
    );
    expect(
      GameEventReducer.replay(steal.input, steal.ledger()).hasOpenPossession,
      isFalse,
    );

    final shotClock = script();
    shotClock.startPossession('p1', starter);
    shotClock.turnover(
      team: starter,
      player: homePg,
      reason: TurnoverReason.shotClock,
      clock: 676,
      shotClock: 0,
    );
    shotClock.endPossession(
      possessionId: 'p1',
      team: starter,
      reason: PossessionEndReason.turnover,
      clock: 676,
      shotClock: 0,
    );
    expect(
      GameEventReducer.replay(
        shotClock.input,
        shotClock.ledger(),
      ).hasOpenPossession,
      isFalse,
    );

    final offensive = script();
    offensive.startPossession('p1', starter);
    offensive.foul(
      team: starter,
      player: homePg,
      kind: FoulKind.offensive,
      clock: 690,
      shotClock: 14,
    );
    offensive.turnover(
      team: starter,
      player: homePg,
      reason: TurnoverReason.offensiveFoul,
      clock: 690,
      shotClock: 14,
    );
    offensive.endPossession(
      possessionId: 'p1',
      team: starter,
      reason: PossessionEndReason.turnover,
      clock: 690,
      shotClock: 14,
    );
    expect(
      GameEventReducer.replay(
        offensive.input,
        offensive.ledger(),
      ).hasOpenPossession,
      isFalse,
    );
  });

  test('replays and-one and missed and-one free-throw offensive rebounds', () {
    final andOne = script();
    andOne.startPossession('p1', starter);
    andOne.fga(
      team: starter,
      shooter: homePg,
      andOne: true,
      clock: 690,
      shotClock: 14,
    );
    andOne.foul(
      team: other,
      player: awayPg,
      kind: FoulKind.shooting,
      freeThrows: 1,
      drawnBy: homePg,
      clock: 690,
      shotClock: 14,
    );
    andOne.ft(
      team: starter,
      shooter: homePg,
      groupId: 'g1',
      index: 1,
      total: 1,
      made: true,
      clock: 690,
      shotClock: 14,
    );
    andOne.endPossession(
      possessionId: 'p1',
      team: starter,
      reason: PossessionEndReason.madeFinalFreeThrow,
      clock: 690,
      shotClock: 14,
    );
    expect(
      GameEventReducer.replay(andOne.input, andOne.ledger()).hasOpenPossession,
      isFalse,
    );

    final missedAndOne = script();
    missedAndOne.startPossession('p1', starter);
    missedAndOne.fga(
      team: starter,
      shooter: homePg,
      andOne: true,
      clock: 690,
      shotClock: 14,
    );
    missedAndOne.foul(
      team: other,
      player: awayPg,
      kind: FoulKind.shooting,
      freeThrows: 1,
      drawnBy: homePg,
      clock: 690,
      shotClock: 14,
    );
    missedAndOne.ft(
      team: starter,
      shooter: homePg,
      groupId: 'g1',
      index: 1,
      total: 1,
      made: false,
      clock: 690,
      shotClock: 14,
    );
    missedAndOne.rebound(
      team: starter,
      player: homePg,
      offensive: true,
      missedEventSequence: 6,
      clock: 690,
      shotClock: 14,
    );
    missedAndOne.fga(team: starter, shooter: homePg, clock: 680, shotClock: 4);
    missedAndOne.endPossession(
      possessionId: 'p1',
      team: starter,
      reason: PossessionEndReason.madeFieldGoal,
      clock: 680,
      shotClock: 4,
    );
    final state = GameEventReducer.replay(
      missedAndOne.input,
      missedAndOne.ledger(),
    );
    expect(state.hasOpenPossession, isFalse);
  });

  test('replays missed shooting-foul final FT offensive rebound', () {
    final s = script();
    s.startPossession('p1', starter);
    s.foul(
      team: other,
      player: awayPg,
      kind: FoulKind.shooting,
      freeThrows: 2,
      drawnBy: homePg,
      clock: 690,
      shotClock: 14,
    );
    s.ft(
      team: starter,
      shooter: homePg,
      groupId: 'g1',
      index: 1,
      total: 2,
      made: true,
      clock: 690,
      shotClock: 14,
    );
    s.ft(
      team: starter,
      shooter: homePg,
      groupId: 'g1',
      index: 2,
      total: 2,
      made: false,
      clock: 690,
      shotClock: 14,
    );
    s.rebound(
      team: starter,
      player: homePg,
      offensive: true,
      missedEventSequence: 6,
      clock: 690,
      shotClock: 14,
    );
    s.fga(team: starter, shooter: homePg, clock: 680, shotClock: 4);
    s.endPossession(
      possessionId: 'p1',
      team: starter,
      reason: PossessionEndReason.madeFieldGoal,
      clock: 680,
      shotClock: 4,
    );
    expect(
      GameEventReducer.replay(s.input, s.ledger()).hasOpenPossession,
      isFalse,
    );
  });

  test('replays defensive rebounds and zero-clock dead-ball misses', () {
    final defensive = script();
    defensive.startPossession('p1', starter);
    defensive.fga(
      team: starter,
      shooter: homePg,
      made: false,
      clock: 690,
      shotClock: 14,
    );
    defensive.rebound(
      team: other,
      player: awayPg,
      offensive: false,
      missedEventSequence: 4,
      clock: 690,
      shotClock: 24,
    );
    defensive.endPossession(
      possessionId: 'p1',
      team: starter,
      reason: PossessionEndReason.defensiveRebound,
      clock: 690,
      shotClock: 24,
    );
    expect(
      GameEventReducer.replay(
        defensive.input,
        defensive.ledger(),
      ).hasOpenPossession,
      isFalse,
    );

    final deadBall = script();
    deadBall.startPossession('p1', starter, clock: 24);
    deadBall.fga(
      team: starter,
      shooter: homePg,
      made: false,
      clock: 0,
      shotClock: 0,
    );
    deadBall.deadBall(team: starter, missedEventSequence: 4);
    deadBall.endPossession(
      possessionId: 'p1',
      team: starter,
      reason: PossessionEndReason.periodEnd,
      clock: 0,
      shotClock: 0,
    );
    deadBall.endPeriod(1);
    expect(
      GameEventReducer.replay(deadBall.input, deadBall.ledger()).period,
      1,
    );
  });

  test('completes zero-clock free throws without a rebound', () {
    final s = script();
    s.startPossession('p1', starter, clock: 10);
    s.foul(
      team: other,
      player: awayPg,
      kind: FoulKind.shooting,
      freeThrows: 2,
      drawnBy: homePg,
      clock: 0,
      shotClock: 14,
    );
    s.ft(
      team: starter,
      shooter: homePg,
      groupId: 'g1',
      index: 1,
      total: 2,
      made: true,
      clock: 0,
      shotClock: 14,
    );
    s.ft(
      team: starter,
      shooter: homePg,
      groupId: 'g1',
      index: 2,
      total: 2,
      made: false,
      clock: 0,
      shotClock: 14,
    );
    s.deadBall(team: starter, missedEventSequence: 6, shotClock: 14);
    s.endPossession(
      possessionId: 'p1',
      team: starter,
      reason: PossessionEndReason.periodEnd,
      clock: 0,
      shotClock: 14,
    );
    s.endPeriod(1);
    expect(GameEventReducer.replay(s.input, s.ledger()).period, 1);

    final invalidRebound = script();
    invalidRebound.startPossession('p1', starter, clock: 10);
    invalidRebound.foul(
      team: other,
      player: awayPg,
      kind: FoulKind.shooting,
      freeThrows: 2,
      drawnBy: homePg,
      clock: 0,
      shotClock: 14,
    );
    invalidRebound.ft(
      team: starter,
      shooter: homePg,
      groupId: 'g1',
      index: 1,
      total: 2,
      made: false,
      clock: 0,
      shotClock: 14,
    );
    invalidRebound.ft(
      team: starter,
      shooter: homePg,
      groupId: 'g1',
      index: 2,
      total: 2,
      made: false,
      clock: 0,
      shotClock: 14,
    );
    invalidRebound.rebound(
      team: starter,
      player: homePg,
      offensive: true,
      missedEventSequence: 6,
      clock: 0,
      shotClock: 14,
    );
    expect(
      () => GameEventReducer.replay(
        invalidRebound.input,
        invalidRebound.ledger(),
      ),
      throwsCode(GameValidationCode.reboundInvalid),
    );
  });

  test('ends periods only after resolving possession and enforces bounds', () {
    final open = script();
    open.startPossession('p1', starter, clock: 700);
    open.endPeriod(1);
    expect(
      () => GameEventReducer.replay(open.input, open.ledger()),
      throwsCode(GameValidationCode.periodEndInvalid),
    );

    final capped = script(rules: GameRules(maxEvents: 5));
    capped.startPossession('p1', capped.input.startingTeamId, clock: 700);
    capped.fga(
      team: capped.input.startingTeamId,
      shooter: playerAt(capped.input, capped.input.startingTeamId, Position.pg),
      clock: 690,
      shotClock: 14,
    );
    capped.endPossession(
      possessionId: 'p1',
      team: capped.input.startingTeamId,
      reason: PossessionEndReason.madeFieldGoal,
      clock: 690,
      shotClock: 14,
    );
    capped.endPeriod(1);
    expect(
      () => GameEventReducer.replay(capped.input, capped.ledger()),
      throwsCode(GameValidationCode.eventLimitExceeded),
    );

    final zeroTime = script(rules: GameRules(maxZeroTimeEvents: 3));
    zeroTime.startPossession('p1', zeroTime.input.startingTeamId, clock: 700);
    final offense = zeroTime.input.startingTeamId;
    final defense = zeroTime.input.opponentOf(offense);
    zeroTime.foul(
      team: defense,
      player: playerAt(zeroTime.input, defense, Position.pg),
      kind: FoulKind.nonShooting,
      drawnBy: playerAt(zeroTime.input, offense, Position.pg),
      clock: 700,
      shotClock: 24,
    );
    zeroTime.foul(
      team: defense,
      player: playerAt(zeroTime.input, defense, Position.pg),
      kind: FoulKind.nonShooting,
      drawnBy: playerAt(zeroTime.input, offense, Position.pg),
      clock: 700,
      shotClock: 24,
    );
    zeroTime.foul(
      team: defense,
      player: playerAt(zeroTime.input, defense, Position.pg),
      kind: FoulKind.nonShooting,
      drawnBy: playerAt(zeroTime.input, offense, Position.pg),
      clock: 700,
      shotClock: 24,
    );
    expect(
      () => GameEventReducer.replay(zeroTime.input, zeroTime.ledger()),
      throwsCode(GameValidationCode.zeroTimeEventLimitExceeded),
    );

    final overtime = GameScript(buildInput(rules: GameRules(maxOvertimes: 1)))
      ..startGame();
    overtime.startPeriod(6, overtime.input.startingTeamId);
    expect(
      () => GameEventReducer.replay(overtime.input, overtime.ledger()),
      throwsCode(GameValidationCode.overtimeLimitExceeded),
    );
  });

  test('applies the regulation bonus threshold and resets', () {
    final s = script();
    s.startPossession('p1', starter, clock: 700);
    for (var i = 1; i <= 4; i++) {
      s.foul(
        team: other,
        player: awayPg,
        kind: FoulKind.nonShooting,
        freeThrows: 0,
        bonus: false,
        drawnBy: homePg,
        clock: 700,
        shotClock: 24,
      );
    }
    s.foul(
      team: other,
      player: awayPg,
      kind: FoulKind.nonShooting,
      freeThrows: 2,
      bonus: true,
      drawnBy: homePg,
      clock: 700,
      shotClock: 24,
    );
    s.ft(
      team: starter,
      shooter: homePg,
      groupId: 'g1',
      index: 1,
      total: 2,
      made: true,
      clock: 700,
      shotClock: 24,
    );
    s.ft(
      team: starter,
      shooter: homePg,
      groupId: 'g1',
      index: 2,
      total: 2,
      made: true,
      clock: 700,
      shotClock: 24,
    );
    s.endPossession(
      possessionId: 'p1',
      team: starter,
      reason: PossessionEndReason.madeFinalFreeThrow,
      clock: 700,
      shotClock: 24,
    );
    final state = GameEventReducer.replay(s.input, s.ledger());
    expect(state.hasOpenPossession, isFalse);
    final score = account(input, s.events);
    expect(score.players[awayPg]!.personalFouls, 5);
    expect(score.teams[other.value]!.personalFouls, 5);
  });

  test('rejects GameEnded on a tied score', () {
    final s = GameScript(input)..startGame();
    final first = input.startingTeamId;
    final second = input.opponentOf(first);
    final starters = [first, second, first, second];
    for (var i = 0; i < 4; i++) {
      final period = i + 1;
      final team = starters[i];
      s.startPeriod(period, team);
      s.startPossession('p$period', team, clock: 24);
      s.fga(
        team: team,
        shooter: playerAt(input, team, Position.pg),
        clock: 0,
        shotClock: 0,
      );
      s.endPossession(
        possessionId: 'p$period',
        team: team,
        reason: PossessionEndReason.madeFieldGoal,
        clock: 0,
        shotClock: 0,
      );
      s.endPeriod(period);
    }
    s.endGame(4);
    expect(
      () => GameEventReducer.replay(input, s.ledger()),
      throwsCode(GameValidationCode.gameEndInvalid),
    );
  });

  test('rejects any event after GameEnded', () {
    final s = GameScript(input)..startGame();
    final first = input.startingTeamId;
    final second = input.opponentOf(first);
    final starters = [first, second, first, second];
    for (var i = 0; i < 4; i++) {
      final period = i + 1;
      final team = starters[i];
      s.startPeriod(period, team);
      s.startPossession('p$period', team, clock: 24);
      if (period == 1) {
        s.fga(
          team: team,
          shooter: playerAt(input, team, Position.pg),
          clock: 0,
          shotClock: 0,
        );
        s.endPossession(
          possessionId: 'p$period',
          team: team,
          reason: PossessionEndReason.madeFieldGoal,
          clock: 0,
          shotClock: 0,
        );
      } else {
        s.endPossession(
          possessionId: 'p$period',
          team: team,
          reason: PossessionEndReason.periodEnd,
          clock: 0,
          shotClock: 24,
        );
      }
      s.endPeriod(period);
    }
    s.endGame(4);
    s.events.add(
      PeriodStarted(
        sequence: s.events.length + 1,
        period: 5,
        gameClock: 300,
        shotClock: null,
        startingTeamId: first.value,
      ),
    );
    expect(
      () => GameEventReducer.replay(input, s.ledger()),
      throwsCode(GameValidationCode.eventAfterGameEnded),
    );
  });

  test('rejects an event labelled with an unstarted period', () {
    final s = script();
    s.startPossession('p1', starter, clock: 700, shotClock: 24);
    final events = <GameEvent>[
      ...s.events,
      FieldGoalAttempt(
        sequence: 4,
        period: 2,
        gameClock: 690,
        shotClock: 14,
        teamId: starter.value,
        shooterId: homePg,
        shotValue: 2,
        made: true,
        andOne: false,
      ),
      PossessionEnded(
        sequence: 5,
        period: 1,
        gameClock: 690,
        shotClock: 14,
        possessionId: 'p1',
        offenseTeamId: starter.value,
        reason: PossessionEndReason.madeFieldGoal,
      ),
    ];
    expect(
      () => GameEventReducer.replayEvents(s.input, events),
      throwsCode(GameValidationCode.periodNotStarted),
    );
  });

  test('rejects periodEnd while any outcome is unresolved', () {
    void expectRejected(GameScript s) {
      expect(
        () => GameEventReducer.replay(s.input, s.ledger()),
        throwsCode(GameValidationCode.possessionEndReasonInvalid),
      );
    }

    final made = script();
    made.startPossession('p', made.input.startingTeamId, clock: 24);
    made.fga(
      team: made.input.startingTeamId,
      shooter: playerAt(made.input, made.input.startingTeamId, Position.pg),
      clock: 0,
      shotClock: 0,
    );
    made.endPossession(
      possessionId: 'p',
      team: made.input.startingTeamId,
      reason: PossessionEndReason.periodEnd,
      clock: 0,
      shotClock: 0,
    );
    expectRejected(made);

    final andOne = script();
    andOne.startPossession('p', andOne.input.startingTeamId, clock: 24);
    andOne.fga(
      team: andOne.input.startingTeamId,
      shooter: playerAt(andOne.input, andOne.input.startingTeamId, Position.pg),
      clock: 0,
      shotClock: 0,
      andOne: true,
    );
    andOne.endPossession(
      possessionId: 'p',
      team: andOne.input.startingTeamId,
      reason: PossessionEndReason.periodEnd,
      clock: 0,
      shotClock: 0,
    );
    expectRejected(andOne);

    final turnover = script();
    turnover.startPossession('p', turnover.input.startingTeamId, clock: 24);
    turnover.turnover(
      team: turnover.input.startingTeamId,
      player: playerAt(
        turnover.input,
        turnover.input.startingTeamId,
        Position.pg,
      ),
      reason: TurnoverReason.steal,
      stolenBy: playerAt(
        turnover.input,
        turnover.input.opponentOf(turnover.input.startingTeamId),
        Position.pg,
      ),
      clock: 0,
      shotClock: 0,
    );
    turnover.endPossession(
      possessionId: 'p',
      team: turnover.input.startingTeamId,
      reason: PossessionEndReason.periodEnd,
      clock: 0,
      shotClock: 0,
    );
    expectRejected(turnover);

    final defensive = script();
    defensive.startPossession('p', defensive.input.startingTeamId, clock: 24);
    final defense = defensive.input.opponentOf(defensive.input.startingTeamId);
    defensive.fga(
      team: defensive.input.startingTeamId,
      shooter: playerAt(
        defensive.input,
        defensive.input.startingTeamId,
        Position.pg,
      ),
      made: false,
      clock: 1,
      shotClock: 1,
    );
    defensive.rebound(
      team: defense,
      player: playerAt(defensive.input, defense, Position.pg),
      offensive: false,
      missedEventSequence: 4,
      clock: 1,
      shotClock: 24,
    );
    defensive.endPossession(
      possessionId: 'p',
      team: defensive.input.startingTeamId,
      reason: PossessionEndReason.periodEnd,
      clock: 0,
      shotClock: 24,
    );
    expectRejected(defensive);

    final madeFt = script();
    madeFt.startPossession('p', madeFt.input.startingTeamId, clock: 10);
    final ftDefense = madeFt.input.opponentOf(madeFt.input.startingTeamId);
    madeFt.foul(
      team: ftDefense,
      player: playerAt(madeFt.input, ftDefense, Position.pg),
      kind: FoulKind.shooting,
      freeThrows: 2,
      drawnBy: playerAt(madeFt.input, madeFt.input.startingTeamId, Position.pg),
      clock: 0,
      shotClock: 14,
    );
    madeFt.ft(
      team: madeFt.input.startingTeamId,
      shooter: playerAt(madeFt.input, madeFt.input.startingTeamId, Position.pg),
      groupId: 'g',
      index: 1,
      total: 2,
      made: true,
      clock: 0,
      shotClock: 14,
    );
    madeFt.ft(
      team: madeFt.input.startingTeamId,
      shooter: playerAt(madeFt.input, madeFt.input.startingTeamId, Position.pg),
      groupId: 'g',
      index: 2,
      total: 2,
      made: true,
      clock: 0,
      shotClock: 14,
    );
    madeFt.endPossession(
      possessionId: 'p',
      team: madeFt.input.startingTeamId,
      reason: PossessionEndReason.periodEnd,
      clock: 0,
      shotClock: 14,
    );
    expectRejected(madeFt);

    final offensive = script();
    offensive.startPossession('p', offensive.input.startingTeamId, clock: 24);
    offensive.foul(
      team: offensive.input.startingTeamId,
      player: playerAt(
        offensive.input,
        offensive.input.startingTeamId,
        Position.pg,
      ),
      kind: FoulKind.offensive,
      clock: 0,
      shotClock: 0,
    );
    offensive.endPossession(
      possessionId: 'p',
      team: offensive.input.startingTeamId,
      reason: PossessionEndReason.periodEnd,
      clock: 0,
      shotClock: 0,
    );
    expectRejected(offensive);

    final missed = script();
    missed.startPossession('p', missed.input.startingTeamId, clock: 24);
    missed.fga(
      team: missed.input.startingTeamId,
      shooter: playerAt(missed.input, missed.input.startingTeamId, Position.pg),
      made: false,
      clock: 0,
      shotClock: 0,
    );
    missed.endPossession(
      possessionId: 'p',
      team: missed.input.startingTeamId,
      reason: PossessionEndReason.periodEnd,
      clock: 0,
      shotClock: 0,
    );
    expectRejected(missed);

    final openFt = script();
    openFt.startPossession('p', openFt.input.startingTeamId, clock: 10);
    openFt.foul(
      team: openFt.input.opponentOf(openFt.input.startingTeamId),
      player: playerAt(
        openFt.input,
        openFt.input.opponentOf(openFt.input.startingTeamId),
        Position.pg,
      ),
      kind: FoulKind.shooting,
      freeThrows: 2,
      drawnBy: playerAt(openFt.input, openFt.input.startingTeamId, Position.pg),
      clock: 0,
      shotClock: 14,
    );
    openFt.endPossession(
      possessionId: 'p',
      team: openFt.input.startingTeamId,
      reason: PossessionEndReason.periodEnd,
      clock: 0,
      shotClock: 14,
    );
    expectRejected(openFt);
  });

  test('allows a legitimate period-ending possession closure', () {
    final direct = script();
    direct.startPossession('p', direct.input.startingTeamId, clock: 24);
    direct.endPossession(
      possessionId: 'p',
      team: direct.input.startingTeamId,
      reason: PossessionEndReason.periodEnd,
      clock: 0,
      shotClock: 24,
    );
    direct.endPeriod(1);
    expect(GameEventReducer.replay(direct.input, direct.ledger()).period, 1);

    final deadBall = script();
    deadBall.startPossession('p', deadBall.input.startingTeamId, clock: 24);
    deadBall.fga(
      team: deadBall.input.startingTeamId,
      shooter: playerAt(
        deadBall.input,
        deadBall.input.startingTeamId,
        Position.pg,
      ),
      made: false,
      clock: 0,
      shotClock: 0,
    );
    deadBall.deadBall(
      team: deadBall.input.startingTeamId,
      missedEventSequence: 4,
    );
    deadBall.endPossession(
      possessionId: 'p',
      team: deadBall.input.startingTeamId,
      reason: PossessionEndReason.periodEnd,
      clock: 0,
      shotClock: 0,
    );
    deadBall.endPeriod(1);
    expect(
      GameEventReducer.replay(deadBall.input, deadBall.ledger()).period,
      1,
    );
  });

  test('rejects or permits overtime only after a tied period', () {
    final nonTied = regulationGame(input, tie: false);
    nonTied.startPeriod(5, input.startingTeamId, clock: 300);
    expect(
      () => GameEventReducer.replay(nonTied.input, nonTied.ledger()),
      throwsCode(GameValidationCode.overtimeNotTied),
    );

    final tied = regulationGame(input, tie: true);
    tied.startPeriod(5, input.startingTeamId, clock: 300);
    expect(GameEventReducer.replay(tied.input, tied.ledger()).period, 5);

    final tiedThenScored = regulationGame(input, tie: true);
    tiedThenScored.startPeriod(5, input.startingTeamId, clock: 300);
    tiedThenScored.startPossession('o1', input.startingTeamId, clock: 24);
    tiedThenScored.fga(
      team: input.startingTeamId,
      shooter: playerAt(input, input.startingTeamId, Position.pg),
      clock: 0,
      shotClock: 0,
    );
    tiedThenScored.endPossession(
      possessionId: 'o1',
      team: input.startingTeamId,
      reason: PossessionEndReason.madeFieldGoal,
      clock: 0,
      shotClock: 0,
    );
    tiedThenScored.endPeriod(5);
    tiedThenScored.startPeriod(
      6,
      input.opponentOf(input.startingTeamId),
      clock: 300,
    );
    expect(
      () => GameEventReducer.replay(
        tiedThenScored.input,
        tiedThenScored.ledger(),
      ),
      throwsCode(GameValidationCode.overtimeNotTied),
    );

    final tiedOvertime = regulationGame(input, tie: true);
    tiedOvertime.startPeriod(5, input.startingTeamId, clock: 300);
    tiedOvertime.endPeriod(5);
    tiedOvertime.startPeriod(
      6,
      input.opponentOf(input.startingTeamId),
      clock: 300,
    );
    expect(
      GameEventReducer.replay(tiedOvertime.input, tiedOvertime.ledger()).period,
      6,
    );

    final tiedFinal = regulationGame(input, tie: true);
    tiedFinal.startPeriod(5, input.startingTeamId, clock: 300);
    tiedFinal.endPeriod(5);
    tiedFinal.endGame(5);
    expect(
      () => GameEventReducer.replay(tiedFinal.input, tiedFinal.ledger()),
      throwsCode(GameValidationCode.gameEndInvalid),
    );
  });

  test('enforces the ten-overtime bound', () {
    final s = regulationGame(input, tie: true);
    for (var period = 5; period <= 14; period++) {
      final team = period.isOdd
          ? input.startingTeamId
          : input.opponentOf(input.startingTeamId);
      s.startPeriod(period, team, clock: 300);
      s.endPeriod(period);
    }
    s.startPeriod(15, input.startingTeamId, clock: 300);
    expect(
      () => GameEventReducer.replay(s.input, s.ledger()),
      throwsCode(GameValidationCode.overtimeLimitExceeded),
    );
  });

  test('rejects simultaneous shot-clock turnover at the horn', () {
    final s = script();
    s.startPossession('p', s.input.startingTeamId, clock: 24);
    s.turnover(
      team: s.input.startingTeamId,
      player: playerAt(s.input, s.input.startingTeamId, Position.pg),
      reason: TurnoverReason.shotClock,
      clock: 0,
      shotClock: 0,
    );
    s.endPossession(
      possessionId: 'p',
      team: s.input.startingTeamId,
      reason: PossessionEndReason.turnover,
      clock: 0,
      shotClock: 0,
    );
    s.endPeriod(1);
    expect(
      () => GameEventReducer.replay(s.input, s.ledger()),
      throwsCode(GameValidationCode.periodHornPrecedence),
    );
  });

  test('allows shot-clock expiry before the period horn', () {
    final s = script();
    s.startPossession('p', s.input.startingTeamId, clock: 100);
    s.turnover(
      team: s.input.startingTeamId,
      player: playerAt(s.input, s.input.startingTeamId, Position.pg),
      reason: TurnoverReason.shotClock,
      clock: 76,
      shotClock: 0,
    );
    s.endPossession(
      possessionId: 'p',
      team: s.input.startingTeamId,
      reason: PossessionEndReason.turnover,
      clock: 76,
      shotClock: 0,
    );
    final state = GameEventReducer.replay(s.input, s.ledger());
    expect(state.hasOpenPossession, isFalse);
  });
}
