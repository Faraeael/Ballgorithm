import 'dart:convert';

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

void main() {
  late GameInput input;
  late TeamId home;
  late TeamId away;
  late TeamId starter;
  late TeamId other;

  setUp(() {
    input = buildInput();
    home = input.homeTeamId;
    away = input.awayTeamId;
    starter = input.startingTeamId;
    other = input.opponentOf(starter);
  });

  GameScript script() => GameScript(input)
    ..startGame()
    ..startPeriod(1, starter);

  String pgFor(TeamId team) => playerAt(input, team, Position.pg);

  Team teamFor(TeamId team) =>
      team == input.homeTeamId ? input.homeTeam : input.awayTeam;

  test('accepts a non-steal turnover and ends the possession', () {
    final s = script();
    s.startPossession('p1', starter);
    s.turnover(
      team: starter,
      player: pgFor(starter),
      reason: TurnoverReason.nonSteal,
      clock: 690,
      shotClock: 14,
    );
    s.endPossession(
      possessionId: 'p1',
      team: starter,
      reason: PossessionEndReason.turnover,
      clock: 690,
      shotClock: 14,
    );
    final state = GameEventReducer.replay(s.input, s.ledger());
    expect(state.hasOpenPossession, isFalse);
  });

  test('rejects a non-steal turnover carrying a stealer', () {
    final s = script();
    s.startPossession('p1', starter);
    s.turnover(
      team: starter,
      player: pgFor(starter),
      reason: TurnoverReason.nonSteal,
      stolenBy: pgFor(other),
      clock: 690,
      shotClock: 14,
    );
    expect(
      () => GameEventReducer.replay(s.input, s.ledger()),
      throwsCode(GameValidationCode.turnoverInvalid),
    );
  });

  test('rejects a non-steal turnover without an open possession', () {
    final s = script();
    s.turnover(
      team: starter,
      player: pgFor(starter),
      reason: TurnoverReason.nonSteal,
      clock: 690,
      shotClock: 14,
    );
    expect(
      () => GameEventReducer.replay(s.input, s.ledger()),
      throwsCode(GameValidationCode.noOpenPossession),
    );
  });

  test('rejects a non-steal turnover attributed to the wrong team', () {
    final s = script();
    s.startPossession('p1', starter);
    s.turnover(
      team: other,
      player: pgFor(other),
      reason: TurnoverReason.nonSteal,
      clock: 690,
      shotClock: 14,
    );
    expect(
      () => GameEventReducer.replay(s.input, s.ledger()),
      throwsCode(GameValidationCode.wrongTeam),
    );
  });

  test('rejects a non-steal turnover attributed to an inactive player', () {
    final s = script();
    s.startPossession('p1', starter);
    final bench = teamFor(starter).players
        .firstWhere((player) => !input.isActive(starter, player.id))
        .id
        .value;
    s.turnover(
      team: starter,
      player: bench,
      reason: TurnoverReason.nonSteal,
      clock: 690,
      shotClock: 14,
    );
    expect(
      () => GameEventReducer.replay(s.input, s.ledger()),
      throwsCode(GameValidationCode.playerNotActive),
    );
  });

  test('rejects a non-steal turnover with unresolved outcomes', () {
    final afterMiss = script();
    afterMiss.startPossession('p1', starter);
    afterMiss.fga(
      team: starter,
      shooter: pgFor(starter),
      made: false,
      clock: 690,
      shotClock: 14,
    );
    afterMiss.turnover(
      team: starter,
      player: pgFor(starter),
      reason: TurnoverReason.nonSteal,
      clock: 690,
      shotClock: 14,
    );
    expect(
      () => GameEventReducer.replay(afterMiss.input, afterMiss.ledger()),
      throwsCode(GameValidationCode.possessionAlreadyOpen),
    );

    final duringFreeThrows = script();
    duringFreeThrows.startPossession('p1', starter, clock: 700, shotClock: 24);
    duringFreeThrows.foul(
      team: other,
      player: pgFor(other),
      kind: FoulKind.shooting,
      freeThrows: 2,
      drawnBy: pgFor(starter),
      clock: 700,
      shotClock: 24,
    );
    duringFreeThrows.ft(
      team: starter,
      shooter: pgFor(starter),
      groupId: 'g1',
      index: 1,
      total: 2,
      made: false,
      clock: 700,
      shotClock: 24,
    );
    duringFreeThrows.turnover(
      team: starter,
      player: pgFor(starter),
      reason: TurnoverReason.nonSteal,
      clock: 690,
      shotClock: 14,
    );
    expect(
      () => GameEventReducer.replay(
        duringFreeThrows.input,
        duringFreeThrows.ledger(),
      ),
      throwsCode(GameValidationCode.possessionAlreadyOpen),
    );
  });

  test('non-steal cannot replace an offensive-foul turnover', () {
    final s = script();
    s.startPossession('p1', starter, clock: 700, shotClock: 24);
    s.foul(
      team: starter,
      player: pgFor(starter),
      kind: FoulKind.offensive,
      clock: 700,
      shotClock: 24,
    );
    s.turnover(
      team: starter,
      player: pgFor(starter),
      reason: TurnoverReason.nonSteal,
      clock: 700,
      shotClock: 24,
    );
    expect(
      () => GameEventReducer.replay(s.input, s.ledger()),
      throwsCode(GameValidationCode.turnoverInvalid),
    );
  });

  test('rejects the same-team restart after a non-steal turnover', () {
    final s = script();
    s.startPossession('p1', starter);
    s.turnover(
      team: starter,
      player: pgFor(starter),
      reason: TurnoverReason.nonSteal,
      clock: 690,
      shotClock: 14,
    );
    s.endPossession(
      possessionId: 'p1',
      team: starter,
      reason: PossessionEndReason.turnover,
      clock: 690,
      shotClock: 14,
    );
    s.startPossession('p2', starter, clock: 680, shotClock: 24);
    expect(
      () => GameEventReducer.replay(s.input, s.ledger()),
      throwsCode(GameValidationCode.wrongTeam),
    );
  });

  test('accepts the opponent restart after a non-steal turnover', () {
    final s = script();
    s.startPossession('p1', starter);
    s.turnover(
      team: starter,
      player: pgFor(starter),
      reason: TurnoverReason.nonSteal,
      clock: 690,
      shotClock: 14,
    );
    s.endPossession(
      possessionId: 'p1',
      team: starter,
      reason: PossessionEndReason.turnover,
      clock: 690,
      shotClock: 14,
    );
    s.startPossession('p2', other, clock: 680, shotClock: 24);
    final state = GameEventReducer.replay(s.input, s.ledger());
    expect(state.hasOpenPossession, isTrue);
    expect(state.offenseTeamId, other.value);
  });

  test('rejects zero-clock non-steal labelling', () {
    final horn = script();
    horn.startPossession('p1', starter, clock: 24, shotClock: 24);
    horn.turnover(
      team: starter,
      player: pgFor(starter),
      reason: TurnoverReason.nonSteal,
      clock: 0,
      shotClock: 0,
    );
    expect(
      () => GameEventReducer.replay(horn.input, horn.ledger()),
      throwsCode(GameValidationCode.periodHornPrecedence),
    );

    final expiry = script();
    expiry.startPossession('p1', starter);
    expiry.turnover(
      team: starter,
      player: pgFor(starter),
      reason: TurnoverReason.nonSteal,
      clock: 676,
      shotClock: 0,
    );
    expect(
      () => GameEventReducer.replay(expiry.input, expiry.ledger()),
      throwsCode(GameValidationCode.turnoverInvalid),
    );
  });

  test('accounts one player and one team turnover with no steal', () {
    final s = script();
    s.startPossession('p1', starter);
    s.turnover(
      team: starter,
      player: pgFor(starter),
      reason: TurnoverReason.nonSteal,
      clock: 690,
      shotClock: 14,
    );
    s.endPossession(
      possessionId: 'p1',
      team: starter,
      reason: PossessionEndReason.turnover,
      clock: 690,
      shotClock: 14,
    );

    final box = account(s.input, s.events);
    final offender = box.players[pgFor(starter)]!;
    expect(offender.turnovers, 1);
    expect(offender.steals, 0);
    final offenseTeam = box.teams[starter.value]!;
    final defenseTeam = box.teams[other.value]!;
    expect(offenseTeam.turnovers, 1);
    expect(defenseTeam.steals, 0);
    expect(offenseTeam.steals, 0);
    expect(offenseTeam.fga, 0);
    expect(offenseTeam.personalFouls, 0);
    expect(offenseTeam.points, 0);
    expect(defenseTeam.points, 0);
    final playerSum = box.players.values
        .where((player) => player.teamId == starter.value)
        .fold(0, (total, player) => total + player.turnovers);
    expect(offenseTeam.turnovers, playerSum);
  });

  test('round-trips canonical JSON with the nonSteal reason', () {
    final event = Turnover(
      sequence: 1,
      period: 1,
      gameClock: 690,
      shotClock: 14,
      teamId: starter.value,
      playerId: pgFor(starter),
      reason: TurnoverReason.nonSteal,
    );
    final json = event.toJson();
    expect(json['reason'], 'nonSteal');
    final decoded = GameEvent.fromJson(json) as Turnover;
    expect(decoded.reason, TurnoverReason.nonSteal);
    expect(decoded.stolenById, isNull);
    expect(decoded.toJson(), json);
  });

  test('header emits event schema v2 and rejects legacy v1 headers', () {
    final ledger = GameEventLedger(
      gameId: 'game-1',
      inputFingerprint: 'a' * 64,
      events: const [],
    );
    final json = ledger.toJson();
    expect(json['eventSchemaVersion'], 2);

    final legacy = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
    legacy['eventSchemaVersion'] = 1;
    expect(
      () => GameEventLedger.fromJson(legacy),
      throwsA(
        isA<GameValidationException>().having(
          (e) => e.codes,
          'codes',
          contains(GameValidationCode.unsupportedEventSchemaVersion),
        ),
      ),
    );
  });

  test('pinned fingerprint matches the actual v2 canonical input', () {
    final canonical = GameFingerprint.canonicalPayload(input);
    expect(canonical['versions'], containsPair('eventSchema', 2));
    expect(GameFingerprint.canonicalJson(input), contains('"eventSchema":2'));
    expect(
      GameFingerprint.of(input),
      'bcb1a58f09500c0d4132b48709962bd44409a25b6e23ee91d27d3c9f30cb97a8',
    );
    expect(
      GameFingerprint.of(input),
      isNot('82618eb22dc59379c64736cc802262eb0643a2b1ede68f1bb2db8606bed2f850'),
    );
  });

  test('existing steal, shot-clock and offensive-foul ledgers still pass', () {
    final steal = script();
    steal.startPossession('p1', starter);
    steal.turnover(
      team: starter,
      player: pgFor(starter),
      reason: TurnoverReason.steal,
      stolenBy: pgFor(other),
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
      player: pgFor(starter),
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
    offensive.startPossession('p1', starter, clock: 700, shotClock: 24);
    offensive.foul(
      team: starter,
      player: pgFor(starter),
      kind: FoulKind.offensive,
      clock: 700,
      shotClock: 24,
    );
    offensive.turnover(
      team: starter,
      player: pgFor(starter),
      reason: TurnoverReason.offensiveFoul,
      clock: 700,
      shotClock: 24,
    );
    offensive.endPossession(
      possessionId: 'p1',
      team: starter,
      reason: PossessionEndReason.turnover,
      clock: 700,
      shotClock: 24,
    );
    expect(
      GameEventReducer.replay(
        offensive.input,
        offensive.ledger(),
      ).hasOpenPossession,
      isFalse,
    );
  });

  test('probability model still emits nonSteal and unchanged coefficients', () {
    final homeLineup = input.homeLineup;
    final awayLineup = input.awayLineup;
    final offense = TeamOnCourt(teamId: home, lineup: homeLineup);
    final defense = TeamOnCourt(teamId: away, lineup: awayLineup);
    final model = BasketballProbabilityModel();
    var sawNonSteal = false;
    for (var seed = 1; seed <= 200 && !sawNonSteal; seed++) {
      final rng = DeterministicRandom(seed);
      for (var i = 0; i < 50; i++) {
        final action = model.selectAction(
          offense: offense,
          defense: defense,
          phase: PhaseKind.halfCourt,
          rng: rng,
        );
        if (action is TurnoverAction && action.kind == TurnoverKind.nonSteal) {
          sawNonSteal = true;
          break;
        }
      }
    }
    expect(sawNonSteal, isTrue);
    expect(TurnoverReason.nonSteal.wire, 'nonSteal');
  });
}
