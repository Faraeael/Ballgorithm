import 'package:simulation_core/simulation_core.dart';

const defaultLeagueSeed = 20261028;

GameInput buildInput({
  int seed = 42,
  String gameId = 'game-1',
  GameRules? rules,
}) {
  final league = const LeagueGenerator().generate(
    const GenerationConfig(seed: defaultLeagueSeed),
  );
  final home = league.teams.first;
  final away = league.teams[1];
  return GameInput.create(
    gameId: gameId,
    league: league,
    homeTeamId: home.id,
    awayTeamId: away.id,
    homeLineup: ActiveLineup.defaultFor(home),
    awayLineup: ActiveLineup.defaultFor(away),
    seed: seed,
    rules: rules ?? GameRules.standard,
  );
}

GameBoxScore account(GameInput input, List<GameEvent> events) =>
    EventAccounting.aggregate(
      GameEventReducer.validate(input, buildLedger(input, events)),
    );

GameEventLedger buildLedger(GameInput input, List<GameEvent> events) =>
    GameEventLedger(
      gameId: input.gameId,
      inputFingerprint: GameFingerprint.of(input),
      events: events,
    );

String playerAt(GameInput input, TeamId teamId, Position position) {
  final lineup = input.lineupFor(teamId);
  for (final player in lineup.players) {
    if (player.position == position) return player.id.value;
  }
  throw StateError('missing ${position.shortName}');
}

GameEventStartedBuilder started(GameInput input) =>
    GameEventStartedBuilder(input);

final class GameEventStartedBuilder {
  GameEventStartedBuilder(this.input);
  final GameInput input;

  GameStarted at(int sequence) => GameStarted(
    sequence: sequence,
    period: 1,
    gameClock: input.rules.periodSeconds,
    shotClock: null,
    homeTeamId: input.homeTeamId.value,
    awayTeamId: input.awayTeamId.value,
    startingTeamId: input.startingTeamId.value,
  );
}

/// Small hand-authored ledger builder for reducer/accounting fixtures.
final class GameScript {
  GameScript(this.input);

  final GameInput input;
  final List<GameEvent> events = <GameEvent>[];
  int _sequence = 0;

  int _next() => ++_sequence;

  GameStarted startGame() {
    final event = GameStarted(
      sequence: _next(),
      period: 1,
      gameClock: input.rules.periodSeconds,
      shotClock: null,
      homeTeamId: input.homeTeamId.value,
      awayTeamId: input.awayTeamId.value,
      startingTeamId: input.startingTeamId.value,
    );
    events.add(event);
    return event;
  }

  PeriodStarted startPeriod(int period, TeamId starter, {int clock = 720}) {
    final event = PeriodStarted(
      sequence: _next(),
      period: period,
      gameClock: clock,
      shotClock: null,
      startingTeamId: starter.value,
    );
    events.add(event);
    return event;
  }

  PossessionStarted startPossession(
    String possessionId,
    TeamId offense, {
    int clock = 700,
    int shotClock = 24,
  }) {
    final event = PossessionStarted(
      sequence: _next(),
      period: _period,
      gameClock: clock,
      shotClock: shotClock,
      possessionId: possessionId,
      offenseTeamId: offense.value,
    );
    events.add(event);
    return event;
  }

  FieldGoalAttempt fga({
    required TeamId team,
    required String shooter,
    int value = 2,
    bool made = true,
    bool andOne = false,
    String? assist,
    String? block,
    int clock = 690,
    int shotClock = 14,
  }) {
    final event = FieldGoalAttempt(
      sequence: _next(),
      period: _period,
      gameClock: clock,
      shotClock: shotClock,
      teamId: team.value,
      shooterId: shooter,
      shotValue: value,
      made: made,
      andOne: andOne,
      assistedById: assist,
      blockedById: block,
    );
    events.add(event);
    return event;
  }

  PersonalFoul foul({
    required TeamId team,
    required String player,
    required FoulKind kind,
    int freeThrows = 0,
    bool bonus = false,
    String? drawnBy,
    int clock = 690,
    int shotClock = 14,
  }) {
    final event = PersonalFoul(
      sequence: _next(),
      period: _period,
      gameClock: clock,
      shotClock: shotClock,
      committingTeamId: team.value,
      committingPlayerId: player,
      drawnByPlayerId: drawnBy,
      kind: kind,
      freeThrowsAwarded: freeThrows,
      bonus: bonus,
    );
    events.add(event);
    return event;
  }

  FreeThrowAttempt ft({
    required TeamId team,
    required String shooter,
    required String groupId,
    required int index,
    required int total,
    required bool made,
    int clock = 690,
    int shotClock = 14,
  }) {
    final event = FreeThrowAttempt(
      sequence: _next(),
      period: _period,
      gameClock: clock,
      shotClock: shotClock,
      teamId: team.value,
      shooterId: shooter,
      groupId: groupId,
      attemptIndex: index,
      attemptsInGroup: total,
      made: made,
      lastOfGroup: index == total,
    );
    events.add(event);
    return event;
  }

  Rebound rebound({
    required TeamId team,
    required String player,
    required bool offensive,
    required int missedEventSequence,
    int clock = 690,
    int shotClock = 14,
  }) {
    final event = Rebound(
      sequence: _next(),
      period: _period,
      gameClock: clock,
      shotClock: shotClock,
      teamId: team.value,
      playerId: player,
      offensive: offensive,
      missedEventSequence: missedEventSequence,
    );
    events.add(event);
    return event;
  }

  DeadBallMiss deadBall({
    required TeamId team,
    required int missedEventSequence,
    int clock = 0,
    int shotClock = 0,
  }) {
    final event = DeadBallMiss(
      sequence: _next(),
      period: _period,
      gameClock: clock,
      shotClock: shotClock,
      teamId: team.value,
      missedEventSequence: missedEventSequence,
      reason: DeadBallReason.periodEnd,
    );
    events.add(event);
    return event;
  }

  Turnover turnover({
    required TeamId team,
    required String player,
    required TurnoverReason reason,
    String? stolenBy,
    int clock = 690,
    int shotClock = 14,
  }) {
    final event = Turnover(
      sequence: _next(),
      period: _period,
      gameClock: clock,
      shotClock: shotClock,
      teamId: team.value,
      playerId: player,
      reason: reason,
      stolenById: stolenBy,
    );
    events.add(event);
    return event;
  }

  PossessionEnded endPossession({
    required String possessionId,
    required TeamId team,
    required PossessionEndReason reason,
    int clock = 690,
    int shotClock = 14,
  }) {
    final event = PossessionEnded(
      sequence: _next(),
      period: _period,
      gameClock: clock,
      shotClock: shotClock,
      possessionId: possessionId,
      offenseTeamId: team.value,
      reason: reason,
    );
    events.add(event);
    return event;
  }

  PeriodEnded endPeriod(int period, {int clock = 0}) {
    final event = PeriodEnded(
      sequence: _next(),
      period: period,
      gameClock: clock,
      shotClock: null,
    );
    events.add(event);
    return event;
  }

  GameEnded endGame(int period) {
    final event = GameEnded(
      sequence: _next(),
      period: period,
      gameClock: 0,
      shotClock: null,
      finalPeriod: period,
    );
    events.add(event);
    return event;
  }

  GameEventLedger ledger() => buildLedger(input, events);

  int get _period => events.isEmpty ? 1 : events.last.period;
}
