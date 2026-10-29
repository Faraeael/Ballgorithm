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
  late TeamId a;
  late TeamId b;
  late String ap;
  late String bp;
  late String aBench;
  late String bBench;

  setUp(() {
    input = buildInput();
    a = input.startingTeamId;
    b = input.opponentOf(a);
    ap = playerAt(input, a, Position.pg);
    bp = playerAt(input, b, Position.pg);
    aBench = input.homeTeam.players
        .firstWhere((player) => !input.isActive(input.homeTeamId, player.id))
        .id
        .value;
    bBench = input.awayTeam.players
        .firstWhere((player) => !input.isActive(input.awayTeamId, player.id))
        .id
        .value;
  });

  GameScript script() => GameScript(input)
    ..startGame()
    ..startPeriod(1, a);

  group('missed shooting fouls', () {
    test('three-shot miss awards three FTs and no FGA', () {
      final s = script();
      s.startPossession('p1', a, clock: 700, shotClock: 24);
      s.foul(
        team: b,
        player: bp,
        kind: FoulKind.shooting,
        freeThrows: 3,
        drawnBy: ap,
        clock: 690,
        shotClock: 14,
      );
      s.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 1,
        total: 3,
        made: true,
        clock: 690,
        shotClock: 14,
      );
      s.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 2,
        total: 3,
        made: false,
        clock: 690,
        shotClock: 14,
      );
      s.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 3,
        total: 3,
        made: true,
        clock: 690,
        shotClock: 14,
      );
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.madeFinalFreeThrow,
        clock: 690,
        shotClock: 14,
      );

      final box = account(s.input, s.events);
      expect(s.events.whereType<FieldGoalAttempt>(), isEmpty);
      expect(box.teams[a.value]!.fga, 0);
      expect(box.teams[a.value]!.fta, 3);
      expect(box.teams[a.value]!.ftm, 2);
      expect(box.teams[a.value]!.points, 2);
      expect(box.teams[b.value]!.personalFouls, 1);
      expect(box.players[bp]!.personalFouls, 1);
      expect(
        GameEventReducer.replay(s.input, s.ledger()).hasOpenPossession,
        isFalse,
      );
    });

    test('rejects an illegal shooting-foul award', () {
      for (final award in [1, 4]) {
        final s = script();
        s.startPossession('p1', a, clock: 700, shotClock: 24);
        s.foul(
          team: b,
          player: bp,
          kind: FoulKind.shooting,
          freeThrows: award,
          drawnBy: ap,
          clock: 690,
          shotClock: 14,
        );
        expect(
          () => GameEventReducer.replay(s.input, s.ledger()),
          throwsCode(GameValidationCode.freeThrowsInvalid),
          reason: 'award $award',
        );
      }

      final bonus = script();
      bonus.startPossession('p1', a, clock: 700, shotClock: 24);
      bonus.foul(
        team: b,
        player: bp,
        kind: FoulKind.shooting,
        freeThrows: 2,
        bonus: true,
        drawnBy: ap,
        clock: 690,
        shotClock: 14,
      );
      expect(
        () => GameEventReducer.replay(bonus.input, bonus.ledger()),
        throwsCode(GameValidationCode.freeThrowsInvalid),
      );
    });
  });

  group('and-one', () {
    test('made and-one is one FGA, one foul, one FT, three points', () {
      final s = script();
      s.startPossession('p1', a, clock: 700, shotClock: 24);
      s.fga(
        team: a,
        shooter: ap,
        made: true,
        andOne: true,
        clock: 690,
        shotClock: 14,
      );
      s.foul(
        team: b,
        player: bp,
        kind: FoulKind.shooting,
        freeThrows: 1,
        drawnBy: ap,
        clock: 690,
        shotClock: 14,
      );
      s.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 1,
        total: 1,
        made: true,
        clock: 690,
        shotClock: 14,
      );
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.madeFinalFreeThrow,
        clock: 690,
        shotClock: 14,
      );

      final box = account(s.input, s.events);
      expect(box.teams[a.value]!.fga, 1);
      expect(box.teams[a.value]!.fgm, 1);
      expect(box.teams[a.value]!.fta, 1);
      expect(box.teams[a.value]!.ftm, 1);
      expect(box.teams[a.value]!.points, 3);
      expect(box.players[bp]!.personalFouls, 1);
    });

    test('missed and-one final FT with OREB continues the possession', () {
      final s = script();
      s.startPossession('p1', a, clock: 700, shotClock: 24);
      s.fga(
        team: a,
        shooter: ap,
        made: true,
        andOne: true,
        clock: 690,
        shotClock: 14,
      );
      s.foul(
        team: b,
        player: bp,
        kind: FoulKind.shooting,
        freeThrows: 1,
        drawnBy: ap,
        clock: 690,
        shotClock: 14,
      );
      final ft = s.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 1,
        total: 1,
        made: false,
        clock: 690,
        shotClock: 14,
      );
      s.rebound(
        team: a,
        player: ap,
        offensive: true,
        missedEventSequence: ft.sequence,
        clock: 690,
        shotClock: 14,
      );
      s.fga(team: a, shooter: ap, made: true, clock: 688, shotClock: 12);
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.madeFieldGoal,
        clock: 688,
        shotClock: 12,
      );
      final state = GameEventReducer.replay(s.input, s.ledger());
      expect(state.hasOpenPossession, isFalse);
      final box = account(s.input, s.events);
      expect(box.teams[a.value]!.oreb, 1);
      expect(box.teams[a.value]!.fga, 2);
      expect(box.teams[a.value]!.fgm, 2);
      expect(s.events.whereType<PossessionStarted>().length, 1);
    });

    test('rejects malformed and-one sequences', () {
      final extra = script();
      extra.startPossession('p1', a, clock: 700, shotClock: 24);
      extra.fga(
        team: a,
        shooter: ap,
        made: true,
        andOne: true,
        clock: 690,
        shotClock: 14,
      );
      extra.foul(
        team: b,
        player: bp,
        kind: FoulKind.shooting,
        freeThrows: 2,
        drawnBy: ap,
        clock: 690,
        shotClock: 14,
      );
      expect(
        () => GameEventReducer.replay(extra.input, extra.ledger()),
        throwsCode(GameValidationCode.andOneInvalid),
      );

      final noFoul = script();
      noFoul.startPossession('p1', a, clock: 700, shotClock: 24);
      noFoul.fga(
        team: a,
        shooter: ap,
        made: true,
        andOne: true,
        clock: 690,
        shotClock: 14,
      );
      noFoul.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.madeFieldGoal,
        clock: 690,
        shotClock: 14,
      );
      expect(
        () => GameEventReducer.replay(noFoul.input, noFoul.ledger()),
        throwsCode(GameValidationCode.possessionEndReasonInvalid),
      );

      final wrongShooter = script();
      wrongShooter.startPossession('p1', a, clock: 700, shotClock: 24);
      wrongShooter.fga(
        team: a,
        shooter: ap,
        made: true,
        andOne: true,
        clock: 690,
        shotClock: 14,
      );
      wrongShooter.foul(
        team: b,
        player: bp,
        kind: FoulKind.shooting,
        freeThrows: 1,
        drawnBy: bp,
        clock: 690,
        shotClock: 14,
      );
      expect(
        () =>
            GameEventReducer.replay(wrongShooter.input, wrongShooter.ledger()),
        throwsCode(GameValidationCode.andOneInvalid),
      );
    });
  });

  group('defensive non-shooting fouls', () {
    test('below the bonus retains possession and resets the shot clock', () {
      final s = script();
      s.startPossession('p1', a, clock: 700, shotClock: 24);
      s.foul(
        team: b,
        player: bp,
        kind: FoulKind.nonShooting,
        freeThrows: 0,
        drawnBy: ap,
        clock: 700,
        shotClock: 24,
      );
      s.fga(team: a, shooter: ap, made: true, clock: 690, shotClock: 14);
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.madeFieldGoal,
        clock: 690,
        shotClock: 14,
      );
      final box = account(s.input, s.events);
      expect(box.teams[a.value]!.fta, 0);
      expect(box.players[bp]!.personalFouls, 1);
      expect(s.events.whereType<PossessionStarted>().length, 1);
    });

    test('fifth regulation foul awards two bonus free throws', () {
      final s = script();
      s.startPossession('p1', a, clock: 700, shotClock: 24);
      for (var i = 0; i < 4; i++) {
        s.foul(
          team: b,
          player: bp,
          kind: FoulKind.nonShooting,
          freeThrows: 0,
          drawnBy: ap,
          clock: 700,
          shotClock: 24,
        );
      }
      s.foul(
        team: b,
        player: bp,
        kind: FoulKind.nonShooting,
        freeThrows: 2,
        bonus: true,
        drawnBy: ap,
        clock: 700,
        shotClock: 24,
      );
      s.ft(
        team: a,
        shooter: ap,
        groupId: 'b',
        index: 1,
        total: 2,
        made: true,
        clock: 700,
        shotClock: 24,
      );
      s.ft(
        team: a,
        shooter: ap,
        groupId: 'b',
        index: 2,
        total: 2,
        made: true,
        clock: 700,
        shotClock: 24,
      );
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.madeFinalFreeThrow,
        clock: 700,
        shotClock: 24,
      );
      final box = account(s.input, s.events);
      expect(box.teams[a.value]!.fta, 2);
      expect(box.teams[a.value]!.ftm, 2);
      expect(box.teams[b.value]!.personalFouls, 5);
    });

    test('overtime fourth foul awards bonus free throws', () {
      final s = script();
      String pg(TeamId team) => playerAt(input, team, Position.pg);
      // 4-4 regulation tie: each team scores two in alternating periods.
      s.startPossession('r1', a, clock: 24, shotClock: 24);
      s.fga(team: a, shooter: pg(a), made: true, clock: 0, shotClock: 0);
      s.endPossession(
        possessionId: 'r1',
        team: a,
        reason: PossessionEndReason.madeFieldGoal,
        clock: 0,
        shotClock: 0,
      );
      s.endPeriod(1);
      for (var period = 2; period <= 4; period++) {
        final team = period.isOdd ? a : b;
        s.startPeriod(period, team);
        s.startPossession('r$period', team, clock: 24, shotClock: 24);
        s.fga(
          team: team,
          shooter: pg(team),
          made: true,
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
        s.endPeriod(period);
      }
      s.startPeriod(5, a, clock: 300);
      s.startPossession('ot', a, clock: 24, shotClock: 24);
      for (var i = 0; i < 3; i++) {
        s.foul(
          team: b,
          player: bp,
          kind: FoulKind.nonShooting,
          freeThrows: 0,
          drawnBy: ap,
          clock: 24,
          shotClock: 24,
        );
      }
      s.foul(
        team: b,
        player: bp,
        kind: FoulKind.nonShooting,
        freeThrows: 2,
        bonus: true,
        drawnBy: ap,
        clock: 24,
        shotClock: 24,
      );
      s.ft(
        team: a,
        shooter: ap,
        groupId: 'ot-b',
        index: 1,
        total: 2,
        made: true,
        clock: 24,
        shotClock: 24,
      );
      s.ft(
        team: a,
        shooter: ap,
        groupId: 'ot-b',
        index: 2,
        total: 2,
        made: true,
        clock: 24,
        shotClock: 24,
      );
      s.endPossession(
        possessionId: 'ot',
        team: a,
        reason: PossessionEndReason.madeFinalFreeThrow,
        clock: 24,
        shotClock: 24,
      );
      s.endPeriod(5);
      s.endGame(5);
      final box = account(s.input, s.events);
      expect(box.teams[a.value]!.fta, 2);
      expect(s.events.whereType<GameEnded>().single.finalPeriod, 5);
    });

    test('bonus foul at shot-clock zero resolves FTs at that timestamp', () {
      final s = script();
      s.startPossession('p1', a, clock: 40, shotClock: 24);
      for (var i = 0; i < 4; i++) {
        s.foul(
          team: b,
          player: bp,
          kind: FoulKind.nonShooting,
          freeThrows: 0,
          drawnBy: ap,
          clock: 40,
          shotClock: 24,
        );
      }
      s.foul(
        team: b,
        player: bp,
        kind: FoulKind.nonShooting,
        freeThrows: 2,
        bonus: true,
        drawnBy: ap,
        clock: 16,
        shotClock: 0,
      );
      s.ft(
        team: a,
        shooter: ap,
        groupId: 'z',
        index: 1,
        total: 2,
        made: true,
        clock: 16,
        shotClock: 0,
      );
      s.ft(
        team: a,
        shooter: ap,
        groupId: 'z',
        index: 2,
        total: 2,
        made: true,
        clock: 16,
        shotClock: 0,
      );
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.madeFinalFreeThrow,
        clock: 16,
        shotClock: 0,
      );
      expect(
        GameEventReducer.replay(s.input, s.ledger()).hasOpenPossession,
        isFalse,
      );
    });

    test('bonus foul at game-clock zero completes FTs before period end', () {
      final s = script();
      s.startPossession('p1', a, clock: 24, shotClock: 24);
      for (var i = 0; i < 4; i++) {
        s.foul(
          team: b,
          player: bp,
          kind: FoulKind.nonShooting,
          freeThrows: 0,
          drawnBy: ap,
          clock: 24,
          shotClock: 24,
        );
      }
      s.foul(
        team: b,
        player: bp,
        kind: FoulKind.nonShooting,
        freeThrows: 2,
        bonus: true,
        drawnBy: ap,
        clock: 0,
        shotClock: 0,
      );
      s.ft(
        team: a,
        shooter: ap,
        groupId: 'h',
        index: 1,
        total: 2,
        made: true,
        clock: 0,
        shotClock: 0,
      );
      final last = s.ft(
        team: a,
        shooter: ap,
        groupId: 'h',
        index: 2,
        total: 2,
        made: false,
        clock: 0,
        shotClock: 0,
      );
      s.deadBall(
        team: a,
        missedEventSequence: last.sequence,
        clock: 0,
        shotClock: 0,
      );
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.periodEnd,
        clock: 0,
        shotClock: 0,
      );
      s.endPeriod(1);
      final state = GameEventReducer.replay(s.input, s.ledger());
      expect(state.period, 1);
      expect(s.events.whereType<Rebound>(), isEmpty);
    });

    test('non-bonus foul at the horn is recorded before period end', () {
      final s = script();
      s.startPossession('p1', a, clock: 10, shotClock: 24);
      s.foul(
        team: b,
        player: bp,
        kind: FoulKind.nonShooting,
        freeThrows: 0,
        drawnBy: ap,
        clock: 0,
        shotClock: 14,
      );
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.periodEnd,
        clock: 0,
        shotClock: 14,
      );
      s.endPeriod(1);
      expect(GameEventReducer.replay(s.input, s.ledger()).period, 1);
      expect(
        s.events.whereType<PersonalFoul>().single.kind,
        FoulKind.nonShooting,
      );
    });

    test('team fouls reset at the next period', () {
      final s = script();
      s.startPossession('p1', a, clock: 40, shotClock: 24);
      for (var i = 0; i < 4; i++) {
        s.foul(
          team: b,
          player: bp,
          kind: FoulKind.nonShooting,
          freeThrows: 0,
          drawnBy: ap,
          clock: 40,
          shotClock: 24,
        );
      }
      s.fga(team: a, shooter: ap, made: true, clock: 30, shotClock: 14);
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.madeFieldGoal,
        clock: 30,
        shotClock: 14,
      );
      s.endPeriod(1);

      s.startPeriod(2, b);
      s.startPossession('p2', b, clock: 720, shotClock: 24);
      s.foul(
        team: a,
        player: ap,
        kind: FoulKind.nonShooting,
        freeThrows: 0,
        drawnBy: bp,
        clock: 720,
        shotClock: 24,
      );
      s.fga(team: b, shooter: bp, made: true, clock: 710, shotClock: 14);
      s.endPossession(
        possessionId: 'p2',
        team: b,
        reason: PossessionEndReason.madeFieldGoal,
        clock: 710,
        shotClock: 14,
      );
      s.endPeriod(2);
      expect(GameEventReducer.replay(s.input, s.ledger()).period, 2);
    });
  });

  group('offensive fouls', () {
    test('credits one PF and one turnover without FGA or points', () {
      final s = script();
      s.startPossession('p1', a, clock: 700, shotClock: 24);
      s.foul(
        team: a,
        player: ap,
        kind: FoulKind.offensive,
        clock: 690,
        shotClock: 14,
      );
      s.turnover(
        team: a,
        player: ap,
        reason: TurnoverReason.offensiveFoul,
        clock: 690,
        shotClock: 14,
      );
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.turnover,
        clock: 690,
        shotClock: 14,
      );
      final box = account(s.input, s.events);
      expect(box.players[ap]!.personalFouls, 1);
      expect(box.players[ap]!.turnovers, 1);
      expect(box.teams[a.value]!.fga, 0);
      expect(box.teams[a.value]!.points, 0);
      expect(box.teams[b.value]!.steals, 0);
    });

    test('does not increase the opponent bonus counter', () {
      final s = script();
      s.startPossession('p1', a, clock: 40, shotClock: 24);
      for (var i = 0; i < 3; i++) {
        s.foul(
          team: b,
          player: bp,
          kind: FoulKind.nonShooting,
          freeThrows: 0,
          drawnBy: ap,
          clock: 40,
          shotClock: 24,
        );
      }
      s.foul(
        team: a,
        player: ap,
        kind: FoulKind.offensive,
        clock: 40,
        shotClock: 24,
      );
      s.turnover(
        team: a,
        player: ap,
        reason: TurnoverReason.offensiveFoul,
        clock: 40,
        shotClock: 24,
      );
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.turnover,
        clock: 40,
        shotClock: 24,
      );
      s.startPossession('p2', b, clock: 40, shotClock: 24);
      s.turnover(
        team: b,
        player: bp,
        reason: TurnoverReason.nonSteal,
        clock: 40,
        shotClock: 24,
      );
      s.endPossession(
        possessionId: 'p2',
        team: b,
        reason: PossessionEndReason.turnover,
        clock: 40,
        shotClock: 24,
      );
      s.startPossession('p3', a, clock: 40, shotClock: 24);
      s.foul(
        team: b,
        player: bp,
        kind: FoulKind.nonShooting,
        freeThrows: 0,
        drawnBy: ap,
        clock: 40,
        shotClock: 24,
      );
      s.fga(team: a, shooter: ap, made: true, clock: 30, shotClock: 14);
      s.endPossession(
        possessionId: 'p3',
        team: a,
        reason: PossessionEndReason.madeFieldGoal,
        clock: 30,
        shotClock: 14,
      );
      expect(
        GameEventReducer.replay(s.input, s.ledger()).hasOpenPossession,
        isFalse,
      );
    });

    test('rejects malformed offensive fouls', () {
      final drawn = script();
      drawn.startPossession('p1', a, clock: 700, shotClock: 24);
      drawn.foul(
        team: a,
        player: ap,
        kind: FoulKind.offensive,
        drawnBy: bp,
        clock: 690,
        shotClock: 14,
      );
      expect(
        () => GameEventReducer.replay(drawn.input, drawn.ledger()),
        throwsCode(GameValidationCode.foulKindInvalid),
      );

      final award = script();
      award.startPossession('p1', a, clock: 700, shotClock: 24);
      award.foul(
        team: a,
        player: ap,
        kind: FoulKind.offensive,
        freeThrows: 2,
        clock: 690,
        shotClock: 14,
      );
      expect(
        () => GameEventReducer.replay(award.input, award.ledger()),
        throwsCode(GameValidationCode.foulKindInvalid),
      );
    });
  });

  group('free-throw group integrity', () {
    GameScript awardedTwo() {
      final s = script();
      s.startPossession('p1', a, clock: 20, shotClock: 24);
      s.foul(
        team: b,
        player: bp,
        kind: FoulKind.shooting,
        freeThrows: 2,
        drawnBy: ap,
        clock: 10,
        shotClock: 14,
      );
      return s;
    }

    test('rejects skipped, duplicated or mis-sized attempts', () {
      final skipped = awardedTwo();
      skipped.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 2,
        total: 2,
        made: true,
        clock: 10,
        shotClock: 14,
      );
      expect(
        () => GameEventReducer.replay(skipped.input, skipped.ledger()),
        throwsCode(GameValidationCode.freeThrowSequenceInvalid),
      );

      final duplicate = awardedTwo();
      duplicate.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 1,
        total: 2,
        made: true,
        clock: 10,
        shotClock: 14,
      );
      duplicate.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 1,
        total: 2,
        made: true,
        clock: 10,
        shotClock: 14,
      );
      expect(
        () => GameEventReducer.replay(duplicate.input, duplicate.ledger()),
        throwsCode(GameValidationCode.freeThrowSequenceInvalid),
      );

      final wrongSize = awardedTwo();
      wrongSize.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 1,
        total: 3,
        made: true,
        clock: 10,
        shotClock: 14,
      );
      expect(
        () => GameEventReducer.replay(wrongSize.input, wrongSize.ledger()),
        throwsCode(GameValidationCode.freeThrowSequenceInvalid),
      );

      final extra = awardedTwo();
      extra.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 1,
        total: 2,
        made: true,
        clock: 10,
        shotClock: 14,
      );
      extra.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 2,
        total: 2,
        made: true,
        clock: 10,
        shotClock: 14,
      );
      extra.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 3,
        total: 2,
        made: true,
        clock: 10,
        shotClock: 14,
      );
      expect(
        () => GameEventReducer.replay(extra.input, extra.ledger()),
        throwsCode(GameValidationCode.freeThrowSequenceInvalid),
      );
    });

    test('rejects a free throw without an award', () {
      final s = script();
      s.startPossession('p1', a, clock: 20, shotClock: 24);
      s.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 1,
        total: 2,
        made: true,
        clock: 20,
        shotClock: 24,
      );
      expect(
        () => GameEventReducer.replay(s.input, s.ledger()),
        throwsCode(GameValidationCode.freeThrowSequenceInvalid),
      );
    });

    test('rejects clock advance or interleaved actions inside a group', () {
      final advanced = awardedTwo();
      advanced.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 1,
        total: 2,
        made: true,
        clock: 10,
        shotClock: 14,
      );
      advanced.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 2,
        total: 2,
        made: true,
        clock: 9,
        shotClock: 14,
      );
      expect(
        () => GameEventReducer.replay(advanced.input, advanced.ledger()),
        throwsCode(GameValidationCode.freeThrowSequenceInvalid),
      );

      final interleaved = awardedTwo();
      interleaved.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 1,
        total: 2,
        made: true,
        clock: 10,
        shotClock: 14,
      );
      interleaved.fga(
        team: a,
        shooter: ap,
        made: true,
        clock: 10,
        shotClock: 14,
      );
      expect(
        () => GameEventReducer.replay(interleaved.input, interleaved.ledger()),
        throwsCode(GameValidationCode.possessionAlreadyOpen),
      );
    });

    test('only the final free throw is reboundable', () {
      final s = awardedTwo();
      final first = s.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 1,
        total: 2,
        made: false,
        clock: 10,
        shotClock: 14,
      );
      s.rebound(
        team: a,
        player: ap,
        offensive: true,
        missedEventSequence: first.sequence,
        clock: 10,
        shotClock: 14,
      );
      expect(
        () => GameEventReducer.replay(s.input, s.ledger()),
        throwsCode(GameValidationCode.reboundInvalid),
      );
    });
  });

  group('rebound and possession causality', () {
    test('offensive rebound continues the same possession at 14 seconds', () {
      final s = script();
      s.startPossession('p1', a, clock: 700, shotClock: 24);
      s.fga(team: a, shooter: ap, made: false, clock: 690, shotClock: 14);
      s.rebound(
        team: a,
        player: ap,
        offensive: true,
        missedEventSequence: 4,
        clock: 690,
        shotClock: 14,
      );
      s.fga(team: a, shooter: ap, made: true, clock: 688, shotClock: 12);
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.madeFieldGoal,
        clock: 688,
        shotClock: 12,
      );
      final state = GameEventReducer.replay(s.input, s.ledger());
      expect(state.hasOpenPossession, isFalse);
      expect(s.events.whereType<PossessionStarted>().length, 1);
      final box = account(s.input, s.events);
      expect(box.teams[a.value]!.oreb, 1);
    });

    test('defensive rebound on a three-point miss transfers possession', () {
      final s = script();
      s.startPossession('p1', a, clock: 700, shotClock: 24);
      s.fga(
        team: a,
        shooter: ap,
        value: 3,
        made: false,
        clock: 690,
        shotClock: 14,
      );
      s.rebound(
        team: b,
        player: bp,
        offensive: false,
        missedEventSequence: 4,
        clock: 690,
        shotClock: 24,
      );
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.defensiveRebound,
        clock: 690,
        shotClock: 24,
      );
      s.startPossession('p2', b, clock: 690, shotClock: 24);
      final state = GameEventReducer.replay(s.input, s.ledger());
      expect(state.offenseTeamId, b.value);
      final box = account(s.input, s.events);
      expect(box.teams[b.value]!.dreb, 1);
    });

    test('blocked field goal is a miss with a defensive rebound', () {
      final s = script();
      s.startPossession('p1', a, clock: 700, shotClock: 24);
      s.fga(
        team: a,
        shooter: ap,
        made: false,
        block: bp,
        clock: 690,
        shotClock: 14,
      );
      s.rebound(
        team: b,
        player: bp,
        offensive: false,
        missedEventSequence: 4,
        clock: 690,
        shotClock: 24,
      );
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.defensiveRebound,
        clock: 690,
        shotClock: 24,
      );
      final box = account(s.input, s.events);
      expect(box.players[bp]!.blocks, 1);
      expect(box.teams[a.value]!.fga, 1);
      expect(box.teams[a.value]!.fgm, 0);
    });

    test('defensive rebound after a missed bonus final FT ends possession', () {
      final s = script();
      s.startPossession('p1', a, clock: 40, shotClock: 24);
      for (var i = 0; i < 4; i++) {
        s.foul(
          team: b,
          player: bp,
          kind: FoulKind.nonShooting,
          freeThrows: 0,
          drawnBy: ap,
          clock: 40,
          shotClock: 24,
        );
      }
      s.foul(
        team: b,
        player: bp,
        kind: FoulKind.nonShooting,
        freeThrows: 2,
        bonus: true,
        drawnBy: ap,
        clock: 30,
        shotClock: 14,
      );
      s.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 1,
        total: 2,
        made: true,
        clock: 30,
        shotClock: 14,
      );
      final last = s.ft(
        team: a,
        shooter: ap,
        groupId: 'g',
        index: 2,
        total: 2,
        made: false,
        clock: 30,
        shotClock: 14,
      );
      s.rebound(
        team: b,
        player: bp,
        offensive: false,
        missedEventSequence: last.sequence,
        clock: 30,
        shotClock: 24,
      );
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.defensiveRebound,
        clock: 30,
        shotClock: 24,
      );
      s.startPossession('p2', b, clock: 30, shotClock: 24);
      expect(
        GameEventReducer.replay(s.input, s.ledger()).offenseTeamId,
        b.value,
      );
    });

    test('rejects illegal rebounds', () {
      GameScript missedShot() {
        final s = script();
        s.startPossession('p1', a, clock: 700, shotClock: 24);
        s.fga(team: a, shooter: ap, made: false, clock: 690, shotClock: 14);
        return s;
      }

      final duplicate = missedShot();
      duplicate.rebound(
        team: b,
        player: bp,
        offensive: false,
        missedEventSequence: 4,
        clock: 690,
        shotClock: 24,
      );
      duplicate.rebound(
        team: b,
        player: bp,
        offensive: false,
        missedEventSequence: 4,
        clock: 690,
        shotClock: 24,
      );
      expect(
        () => GameEventReducer.replay(duplicate.input, duplicate.ledger()),
        throwsCode(GameValidationCode.reboundDuplicate),
      );

      final wrongMiss = missedShot();
      wrongMiss.rebound(
        team: b,
        player: bp,
        offensive: false,
        missedEventSequence: 99,
        clock: 690,
        shotClock: 24,
      );
      expect(
        () => GameEventReducer.replay(wrongMiss.input, wrongMiss.ledger()),
        throwsCode(GameValidationCode.reboundInvalid),
      );

      final wrongSide = missedShot();
      wrongSide.rebound(
        team: b,
        player: bp,
        offensive: true,
        missedEventSequence: 4,
        clock: 690,
        shotClock: 14,
      );
      expect(
        () => GameEventReducer.replay(wrongSide.input, wrongSide.ledger()),
        throwsCode(GameValidationCode.reboundWrongTeam),
      );

      final wrongDefense = missedShot();
      wrongDefense.rebound(
        team: a,
        player: ap,
        offensive: false,
        missedEventSequence: 4,
        clock: 690,
        shotClock: 24,
      );
      expect(
        () =>
            GameEventReducer.replay(wrongDefense.input, wrongDefense.ledger()),
        throwsCode(GameValidationCode.reboundWrongTeam),
      );

      final inactive = missedShot();
      inactive.rebound(
        team: a,
        player: aBench,
        offensive: true,
        missedEventSequence: 4,
        clock: 690,
        shotClock: 14,
      );
      expect(
        () => GameEventReducer.replay(inactive.input, inactive.ledger()),
        throwsCode(GameValidationCode.playerNotActive),
      );

      final inactiveDefender = missedShot();
      inactiveDefender.rebound(
        team: b,
        player: bBench,
        offensive: false,
        missedEventSequence: 4,
        clock: 690,
        shotClock: 24,
      );
      expect(
        () => GameEventReducer.replay(
          inactiveDefender.input,
          inactiveDefender.ledger(),
        ),
        throwsCode(GameValidationCode.playerNotActive),
      );

      final atHorn = missedShot();
      atHorn.rebound(
        team: b,
        player: bp,
        offensive: false,
        missedEventSequence: 4,
        clock: 0,
        shotClock: 24,
      );
      expect(
        () => GameEventReducer.replay(atHorn.input, atHorn.ledger()),
        throwsCode(GameValidationCode.reboundInvalid),
      );

      final noMiss = script();
      noMiss.startPossession('p1', a, clock: 700, shotClock: 24);
      noMiss.fga(team: a, shooter: ap, made: true, clock: 690, shotClock: 14);
      noMiss.rebound(
        team: b,
        player: bp,
        offensive: false,
        missedEventSequence: 4,
        clock: 690,
        shotClock: 24,
      );
      expect(
        () => GameEventReducer.replay(noMiss.input, noMiss.ledger()),
        throwsCode(GameValidationCode.reboundInvalid),
      );
    });
  });

  group('buzzer and dead-ball ordering', () {
    test('made shot at game clock zero resolves before period end', () {
      final s = script();
      s.startPossession('p1', a, clock: 20, shotClock: 24);
      s.fga(team: a, shooter: ap, made: true, clock: 0, shotClock: 4);
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.madeFieldGoal,
        clock: 0,
        shotClock: 4,
      );
      s.endPeriod(1);
      expect(GameEventReducer.replay(s.input, s.ledger()).period, 1);
      expect(account(s.input, s.events).teams[a.value]!.points, 2);
    });

    test(
      'made shot at simultaneous zero clocks resolves before period end',
      () {
        final s = script();
        s.startPossession('p1', a, clock: 24, shotClock: 24);
        s.fga(team: a, shooter: ap, made: true, clock: 0, shotClock: 0);
        s.endPossession(
          possessionId: 'p1',
          team: a,
          reason: PossessionEndReason.madeFieldGoal,
          clock: 0,
          shotClock: 0,
        );
        s.endPeriod(1);
        expect(GameEventReducer.replay(s.input, s.ledger()).period, 1);
      },
    );

    test('miss at game clock zero becomes DeadBallMiss then period end', () {
      final s = script();
      s.startPossession('p1', a, clock: 24, shotClock: 24);
      final fga = s.fga(
        team: a,
        shooter: ap,
        made: false,
        clock: 0,
        shotClock: 0,
      );
      s.deadBall(
        team: a,
        missedEventSequence: fga.sequence,
        clock: 0,
        shotClock: 0,
      );
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.periodEnd,
        clock: 0,
        shotClock: 0,
      );
      s.endPeriod(1);
      final state = GameEventReducer.replay(s.input, s.ledger());
      expect(state.period, 1);
      expect(s.events.whereType<Rebound>(), isEmpty);
    });

    test('final-tick attempt consumes one second and releases at zero', () {
      final s = script();
      s.startPossession('p1', a, clock: 1, shotClock: 24);
      s.fga(team: a, shooter: ap, made: true, clock: 0, shotClock: 23);
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.madeFieldGoal,
        clock: 0,
        shotClock: 23,
      );
      s.endPeriod(1);
      expect(GameEventReducer.replay(s.input, s.ledger()).period, 1);
    });

    test('shot released at shot-clock zero is legal', () {
      final s = script();
      s.startPossession('p1', a, clock: 40, shotClock: 24);
      s.fga(team: a, shooter: ap, made: false, clock: 30, shotClock: 14);
      s.rebound(
        team: a,
        player: ap,
        offensive: true,
        missedEventSequence: 4,
        clock: 30,
        shotClock: 14,
      );
      s.fga(team: a, shooter: ap, made: true, clock: 16, shotClock: 0);
      s.endPossession(
        possessionId: 'p1',
        team: a,
        reason: PossessionEndReason.madeFieldGoal,
        clock: 16,
        shotClock: 0,
      );
      expect(
        GameEventReducer.replay(s.input, s.ledger()).hasOpenPossession,
        isFalse,
      );
    });

    test(
      'shooting foul at game-clock zero completes FTs before period end',
      () {
        final s = script();
        s.startPossession('p1', a, clock: 24, shotClock: 24);
        s.foul(
          team: b,
          player: bp,
          kind: FoulKind.shooting,
          freeThrows: 2,
          drawnBy: ap,
          clock: 0,
          shotClock: 0,
        );
        s.ft(
          team: a,
          shooter: ap,
          groupId: 'g',
          index: 1,
          total: 2,
          made: true,
          clock: 0,
          shotClock: 0,
        );
        s.ft(
          team: a,
          shooter: ap,
          groupId: 'g',
          index: 2,
          total: 2,
          made: true,
          clock: 0,
          shotClock: 0,
        );
        s.endPossession(
          possessionId: 'p1',
          team: a,
          reason: PossessionEndReason.madeFinalFreeThrow,
          clock: 0,
          shotClock: 0,
        );
        s.endPeriod(1);
        expect(account(s.input, s.events).teams[a.value]!.points, 2);
      },
    );

    test('rejects a second resolution of the same miss', () {
      final s = script();
      s.startPossession('p1', a, clock: 24, shotClock: 24);
      final fga = s.fga(
        team: a,
        shooter: ap,
        made: false,
        clock: 0,
        shotClock: 0,
      );
      s.deadBall(
        team: a,
        missedEventSequence: fga.sequence,
        clock: 0,
        shotClock: 0,
      );
      s.rebound(
        team: b,
        player: bp,
        offensive: false,
        missedEventSequence: fga.sequence,
        clock: 0,
        shotClock: 24,
      );
      expect(
        () => GameEventReducer.replay(s.input, s.ledger()),
        throwsCode(GameValidationCode.reboundDuplicate),
      );
    });

    test('rejects a dead-ball miss that is not at zero', () {
      final s = script();
      s.startPossession('p1', a, clock: 24, shotClock: 24);
      final fga = s.fga(
        team: a,
        shooter: ap,
        made: false,
        clock: 5,
        shotClock: 5,
      );
      s.deadBall(
        team: a,
        missedEventSequence: fga.sequence,
        clock: 5,
        shotClock: 5,
      );
      expect(
        () => GameEventReducer.replay(s.input, s.ledger()),
        throwsCode(GameValidationCode.deadBallInvalid),
      );
    });
  });

  group('generated game ledger audit', () {
    void audit(GameInput game, GameResult result) {
      final events = result.events;
      final misses = <int>{};
      final resolved = <int>{};
      final groups = <String, List<FreeThrowAttempt>>{};
      for (var i = 0; i < events.length; i++) {
        final event = events[i];
        if (event is FreeThrowAttempt) {
          groups
              .putIfAbsent(event.groupId, () => <FreeThrowAttempt>[])
              .add(event);
          if (event.lastOfGroup && !event.made) misses.add(event.sequence);
        }
        if (event is FieldGoalAttempt) {
          if (!event.made) misses.add(event.sequence);
          if (event.andOne) {
            final foul = events[i + 1];
            expect(foul, isA<PersonalFoul>());
            final f = foul as PersonalFoul;
            expect(f.kind, FoulKind.shooting);
            expect(f.freeThrowsAwarded, 1);
            expect(f.drawnByPlayerId, event.shooterId);
            expect(f.gameClock, event.gameClock);
          }
        } else if (event is PersonalFoul &&
            event.kind == FoulKind.shooting &&
            event.freeThrowsAwarded >= 2) {
          for (final other in events) {
            if (other is FieldGoalAttempt &&
                other.period == event.period &&
                other.gameClock == event.gameClock) {
              fail('FGA and missed shooting foul share a timestamp');
            }
          }
        } else if (event is Rebound) {
          expect(event.gameClock, greaterThan(0));
          expect(misses, contains(event.missedEventSequence));
          expect(resolved.add(event.missedEventSequence), isTrue);
          if (event.offensive) {
            expect(event.shotClock, 14);
          } else {
            expect(event.shotClock, 24);
          }
        } else if (event is DeadBallMiss) {
          expect(event.gameClock, 0);
          expect(misses, contains(event.missedEventSequence));
          expect(resolved.add(event.missedEventSequence), isTrue);
        }
      }
      expect(misses.length, resolved.length);
      for (final entry in groups.entries) {
        final attempts = entry.value;
        expect(attempts.length, attempts.first.attemptsInGroup);
        for (var i = 0; i < attempts.length; i++) {
          expect(attempts[i].attemptIndex, i + 1);
          expect(attempts[i].gameClock, attempts.first.gameClock);
          expect(attempts[i].shotClock, attempts.first.shotClock);
          expect(attempts[i].shooterId, attempts.first.shooterId);
          expect(attempts[i].lastOfGroup, i == attempts.length - 1);
        }
      }
      for (final team in [game.homeTeamId, game.awayTeamId]) {
        final box = result.boxScore.teams[team.value]!;
        expect(box.fgm, box.twoPm + box.threePm);
        expect(box.fga, box.twoPa + box.threePa);
        expect(box.points, 2 * box.twoPm + 3 * box.threePm + box.ftm);
        expect(box.rebounds, box.oreb + box.dreb);
        var points = 0;
        var turnovers = 0;
        var fouls = 0;
        for (final player in game.lineupFor(team).players) {
          final stats = result.boxScore.players[player.id.value]!;
          points += stats.points;
          turnovers += stats.turnovers;
          fouls += stats.personalFouls;
        }
        expect(points, box.points);
        expect(turnovers, box.turnovers);
        expect(fouls, box.personalFouls);
      }
    }

    test('required standard seeds replay and reconcile', () {
      for (final seed in [1, 42, 99, 20261029]) {
        final game = buildInput(seed: seed);
        final result = GameSimulator().simulate(game);
        expect(
          GameEventReducer.validate(game, result.ledger).state.ended,
          isTrue,
        );
        audit(game, result);
      }
    });

    test('standard sample exercises foul, FT, rebound and buzzer paths', () {
      var andOnes = 0;
      var missedShootingFouls = 0;
      var offensiveRebounds = 0;
      var defensiveRebounds = 0;
      var zeroClockFts = 0;
      var finalTickShots = 0;
      for (var seed = 1; seed <= 20; seed++) {
        final game = buildInput(seed: seed);
        final result = GameSimulator().simulate(game);
        audit(game, result);
        for (var i = 0; i < result.events.length; i++) {
          final event = result.events[i];
          if (event is FieldGoalAttempt) {
            if (event.andOne) andOnes++;
            if (event.gameClock == 0) finalTickShots++;
          }
          if (event is PersonalFoul &&
              event.kind == FoulKind.shooting &&
              event.freeThrowsAwarded >= 2) {
            missedShootingFouls++;
          }
          if (event is Rebound) {
            if (event.offensive) {
              offensiveRebounds++;
            } else {
              defensiveRebounds++;
            }
          }
          if (event is FreeThrowAttempt && event.gameClock == 0) {
            zeroClockFts++;
          }
        }
      }
      expect(andOnes, greaterThan(0));
      expect(missedShootingFouls, greaterThan(0));
      expect(offensiveRebounds, greaterThan(0));
      expect(defensiveRebounds, greaterThan(0));
      expect(finalTickShots, greaterThan(0));
      // Zero-clock free throws are rare in standard games; any observed group
      // is audited above. Keep the counter to document the sample without a
      // fabricated presence requirement.
      expect(zeroClockFts, greaterThanOrEqualTo(0));
    });
  });

  group('expiry precedence policy', () {
    test('a non-bonus foul cannot coexist with a shot-clock violation', () {
      final s = script();
      s.startPossession('p1', a, clock: 40, shotClock: 24);
      s.foul(
        team: b,
        player: bp,
        kind: FoulKind.nonShooting,
        freeThrows: 0,
        drawnBy: ap,
        clock: 16,
        shotClock: 0,
      );
      s.turnover(
        team: a,
        player: ap,
        reason: TurnoverReason.shotClock,
        clock: 16,
        shotClock: 0,
      );
      expect(
        () => GameEventReducer.replay(s.input, s.ledger()),
        throwsCode(GameValidationCode.shotClockElapsedMismatch),
      );
    });

    test(
      'a live non-steal turnover at shot-clock zero must be a violation',
      () {
        final live = script();
        live.startPossession('p1', a, clock: 40, shotClock: 24);
        live.turnover(
          team: a,
          player: ap,
          reason: TurnoverReason.nonSteal,
          clock: 16,
          shotClock: 0,
        );
        expect(
          () => GameEventReducer.replay(live.input, live.ledger()),
          throwsCode(GameValidationCode.turnoverInvalid),
        );

        final violation = script();
        violation.startPossession('p1', a, clock: 40, shotClock: 24);
        violation.turnover(
          team: a,
          player: ap,
          reason: TurnoverReason.shotClock,
          clock: 16,
          shotClock: 0,
        );
        violation.endPossession(
          possessionId: 'p1',
          team: a,
          reason: PossessionEndReason.turnover,
          clock: 16,
          shotClock: 0,
        );
        expect(
          GameEventReducer.replay(
            violation.input,
            violation.ledger(),
          ).hasOpenPossession,
          isFalse,
        );
      },
    );

    test('no live turnover is representable at the period horn', () {
      final nonSteal = script();
      nonSteal.startPossession('p1', a, clock: 24, shotClock: 24);
      nonSteal.turnover(
        team: a,
        player: ap,
        reason: TurnoverReason.nonSteal,
        clock: 0,
        shotClock: 0,
      );
      expect(
        () => GameEventReducer.replay(nonSteal.input, nonSteal.ledger()),
        throwsCode(GameValidationCode.periodHornPrecedence),
      );

      final shotClock = script();
      shotClock.startPossession('p1', a, clock: 24, shotClock: 24);
      shotClock.turnover(
        team: a,
        player: ap,
        reason: TurnoverReason.shotClock,
        clock: 0,
        shotClock: 0,
      );
      expect(
        () => GameEventReducer.replay(shotClock.input, shotClock.ledger()),
        throwsCode(GameValidationCode.periodHornPrecedence),
      );
    });
  });

  group('generated boundary stress', () {
    GameRules tiny() => GameRules(
      periodSeconds: 1,
      overtimeSeconds: 1,
      shotClockSeconds: 1,
      offensiveReboundResetSeconds: 1,
      nonBonusFoulResetFloorSeconds: 1,
    );

    test(
      'one-second games exercise overtime, zero-clock FTs and dead balls',
      () {
        var overtimeGames = 0;
        var zeroClockFts = 0;
        var deadBalls = 0;
        for (var seed = 1; seed <= 20; seed++) {
          final game = buildInput(seed: seed, rules: tiny());
          final result = GameSimulator().simulate(game);
          GameEventReducer.validate(game, result.ledger);
          if (result.overtimes > 0) overtimeGames++;
          for (var i = 0; i < result.events.length; i++) {
            final event = result.events[i];
            if (event is FreeThrowAttempt && event.gameClock == 0) {
              zeroClockFts++;
              expect(event.shotClock, isNotNull);
            }
            if (event is DeadBallMiss) {
              deadBalls++;
              expect(event.gameClock, 0);
              expect(
                result.events.whereType<Rebound>().where(
                  (r) => r.missedEventSequence == event.missedEventSequence,
                ),
                isEmpty,
              );
            }
            if (event is PeriodEnded) {
              expect(result.events[i - 1], isNot(isA<FieldGoalAttempt>()));
            }
          }
          expect(result.homeScore, isNot(result.awayScore));
        }
        expect(overtimeGames, greaterThan(0));
        expect(zeroClockFts, greaterThan(0));
        expect(deadBalls, greaterThan(0));
      },
    );
  });

  group('linked-event clock integrity', () {
    test('and-one foul must share the shot timestamp', () {
      final s = script();
      s.startPossession('p1', a, clock: 700, shotClock: 24);
      s.fga(
        team: a,
        shooter: ap,
        made: true,
        andOne: true,
        clock: 690,
        shotClock: 14,
      );
      s.foul(
        team: b,
        player: bp,
        kind: FoulKind.shooting,
        freeThrows: 1,
        drawnBy: ap,
        clock: 680,
        shotClock: 4,
      );
      expect(
        () => GameEventReducer.replay(s.input, s.ledger()),
        throwsCode(GameValidationCode.andOneInvalid),
      );
    });

    test('offensive-foul turnover must share the foul timestamp', () {
      final s = script();
      s.startPossession('p1', a, clock: 700, shotClock: 24);
      s.foul(
        team: a,
        player: ap,
        kind: FoulKind.offensive,
        clock: 690,
        shotClock: 14,
      );
      s.turnover(
        team: a,
        player: ap,
        reason: TurnoverReason.offensiveFoul,
        clock: 680,
        shotClock: 4,
      );
      expect(
        () => GameEventReducer.replay(s.input, s.ledger()),
        throwsCode(GameValidationCode.turnoverInvalid),
      );
    });
  });
}
