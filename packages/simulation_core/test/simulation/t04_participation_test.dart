import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';

final _customRules = GameRules(
  bonusRegulationFouls: 10,
  bonusOvertimeFouls: 10,
);

String _starter(GameInput input, TeamId team, Position position) =>
    input.lineupFor(team).playerIdAt(position).value;

String _bench(GameInput input, TeamId team, {String? differentFromSlotOf}) {
  final lineup = input.lineupFor(team);
  final candidates = [
    for (final player
        in input.league.teams
            .firstWhere((t) => t.id.value == team.value)
            .players)
      if (!lineup.containsPlayer(player.id)) player,
  ];
  if (differentFromSlotOf != null) {
    final slot = lineup.slotOf(PlayerId(differentFromSlotOf));
    for (final player in candidates) {
      if (player.position != slot) return player.id.value;
    }
  }
  return candidates.first.id.value;
}

GameInput _input({GameRules? rules, int seed = 42}) =>
    buildInput(rules: rules, seed: seed);

void _expectCode(
  GameEventLedger ledger,
  GameInput input,
  GameValidationCode code,
) {
  expect(
    () => GameEventReducer.validate(input, ledger),
    throwsA(
      isA<GameValidationException>().having(
        (e) => e.codes,
        'codes',
        contains(code),
      ),
    ),
  );
}

GameEvent resequenceEvent(GameEvent event, int sequence) {
  if (event is Substitution) {
    return Substitution(
      sequence: sequence,
      period: event.period,
      gameClock: event.gameClock,
      shotClock: event.shotClock,
      teamId: event.teamId,
      playerOutId: event.playerOutId,
      playerInId: event.playerInId,
      reason: event.reason,
    );
  }
  final json = event.toJson();
  json['sequence'] = sequence;
  return GameEvent.fromJson(json);
}

void main() {
  late GameInput input;
  late TeamId home;
  late TeamId offense;
  late TeamId defense;

  setUp(() {
    input = _input(rules: _customRules);
    home = input.homeTeamId;
    offense = input.startingTeamId;
    defense = input.opponentOf(offense);
  });

  group('W5 after PeriodStarted', () {
    test('accepts a tactical substitution before the first possession', () {
      final script = GameScript(input)
        ..startGame()
        ..startPeriod(1, input.startingTeamId, clock: 720);
      script.substitution(
        team: home,
        playerOut: _starter(input, home, Position.pg),
        playerIn: _bench(input, home),
        reason: SubstitutionReason.tactical,
      );
      script.startPossession('p1', input.startingTeamId, clock: 700);
      expect(
        () => GameEventReducer.validate(input, script.ledger()),
        returnsNormally,
      );
    });

    test('accepts a mismatched primary position in the occupied slot', () {
      final script = GameScript(input)
        ..startGame()
        ..startPeriod(1, input.startingTeamId, clock: 720);
      final out = _starter(input, home, Position.pg);
      script.substitution(
        team: home,
        playerOut: out,
        playerIn: _bench(input, home, differentFromSlotOf: out),
        reason: SubstitutionReason.tactical,
      );
      expect(
        () => GameEventReducer.validate(input, script.ledger()),
        returnsNormally,
      );
    });

    test('rejects a second appearance by the same player in one window', () {
      final script = GameScript(input)
        ..startGame()
        ..startPeriod(1, input.startingTeamId, clock: 720);
      final out = _starter(input, home, Position.pg);
      final first = _bench(input, home);
      final second = [
        for (final player in input.homeTeam.players)
          if (!input.homeLineup.containsPlayer(player.id) &&
              player.id.value != first)
            player.id.value,
      ].first;
      script.substitution(
        team: home,
        playerOut: out,
        playerIn: first,
        reason: SubstitutionReason.tactical,
      );
      script.substitution(
        team: home,
        playerOut: first,
        playerIn: second,
        reason: SubstitutionReason.tactical,
      );
      _expectCode(script.ledger(), input, GameValidationCode.deadBallInvalid);
    });

    test('rejects an inactive outgoing player and active incoming player', () {
      final script = GameScript(input)
        ..startGame()
        ..startPeriod(1, input.startingTeamId, clock: 720);
      script.substitution(
        team: home,
        playerOut: _bench(input, home),
        playerIn: _bench(input, home),
        reason: SubstitutionReason.tactical,
      );
      _expectCode(script.ledger(), input, GameValidationCode.playerNotActive);
    });
  });

  group('W1 after a retained non-bonus foul', () {
    GameScript scriptWithRetainedFoul() {
      final script = GameScript(input)
        ..startGame()
        ..startPeriod(1, input.startingTeamId, clock: 720)
        ..startPossession('p1', offense, clock: 700);
      script.foul(
        team: defense,
        player: _starter(input, defense, Position.pg),
        kind: FoulKind.nonShooting,
        drawnBy: _starter(input, offense, Position.pg),
        clock: 690,
        shotClock: 14,
      );
      return script;
    }

    test('accepts a substitution and preserves the shot-clock ceiling', () {
      final script = scriptWithRetainedFoul();
      script.substitution(
        team: defense,
        playerOut: _starter(input, defense, Position.pg),
        playerIn: _bench(input, defense),
        reason: SubstitutionReason.tactical,
      );
      script.fga(
        team: offense,
        shooter: _starter(input, offense, Position.pg),
        made: true,
        clock: 689,
        shotClock: 13,
      );
      expect(
        () => GameEventReducer.validate(input, script.ledger()),
        returnsNormally,
      );
    });

    test('does not consume the pending ceiling', () {
      final script = scriptWithRetainedFoul();
      script.substitution(
        team: defense,
        playerOut: _starter(input, defense, Position.pg),
        playerIn: _bench(input, defense),
        reason: SubstitutionReason.tactical,
      );
      script.fga(
        team: offense,
        shooter: _starter(input, offense, Position.pg),
        made: true,
        clock: 689,
        shotClock: 20,
      );
      _expectCode(
        script.ledger(),
        input,
        GameValidationCode.illegalShotClockIncrease,
      );
    });

    test('rejects a substitution that moves the clock', () {
      final script = scriptWithRetainedFoul();
      script.substitution(
        team: defense,
        playerOut: _starter(input, defense, Position.pg),
        playerIn: _bench(input, defense),
        reason: SubstitutionReason.tactical,
        clock: 688,
      );
      _expectCode(
        script.ledger(),
        input,
        GameValidationCode.deadBallClockAdvanced,
      );
    });
  });

  group('W0 before awarded free throws', () {
    GameScript w0Script({
      int priorFouls = 5,
      bool includeFreeThrows = true,
      int ftFoulClock = 690,
      int ftFoulShotClock = 14,
      bool includeSubstitution = true,
      SubstitutionReason reason = SubstitutionReason.foulOut,
      TeamId? substitutionTeam,
    }) {
      final script = GameScript(input)
        ..startGame()
        ..startPeriod(1, input.startingTeamId, clock: 720)
        ..startPossession('p1', offense, clock: 700);
      final defender = _starter(input, defense, Position.pg);
      final drawer = _starter(input, offense, Position.pg);
      for (var i = 0; i < priorFouls; i++) {
        script.foul(
          team: defense,
          player: defender,
          kind: FoulKind.nonShooting,
          drawnBy: drawer,
          clock: 690,
          shotClock: 14,
        );
      }
      script.foul(
        team: defense,
        player: defender,
        kind: FoulKind.shooting,
        freeThrows: 2,
        drawnBy: drawer,
        clock: ftFoulClock,
        shotClock: ftFoulShotClock,
      );
      if (includeSubstitution) {
        script.substitution(
          team: substitutionTeam ?? defense,
          playerOut: defender,
          playerIn: _bench(input, defense),
          reason: reason,
          clock: ftFoulClock,
          shotClock: ftFoulShotClock,
        );
      }
      if (includeFreeThrows) {
        script.ft(
          team: offense,
          shooter: drawer,
          groupId: 'ft1',
          index: 1,
          total: 2,
          made: true,
          clock: ftFoulClock,
          shotClock: ftFoulShotClock,
        );
        script.ft(
          team: offense,
          shooter: drawer,
          groupId: 'ft1',
          index: 2,
          total: 2,
          made: true,
          clock: ftFoulClock,
          shotClock: ftFoulShotClock,
        );
        script.endPossession(
          possessionId: 'p1',
          team: offense,
          reason: PossessionEndReason.madeFinalFreeThrow,
          clock: ftFoulClock,
          shotClock: ftFoulShotClock,
        );
      }
      return script;
    }

    test('sixth foul awarding free throws opens W0', () {
      final script = w0Script();
      expect(
        () => GameEventReducer.validate(input, script.ledger()),
        returnsNormally,
      );
    });

    test('mandatory foul-out replacement is accepted at W0', () {
      final script = w0Script(includeSubstitution: true);
      expect(
        () => GameEventReducer.validate(input, script.ledger()),
        returnsNormally,
      );
      final substitution = script.events.whereType<Substitution>().single;
      expect(substitution.reason, SubstitutionReason.foulOut);
    });

    test('wrong-team substitution is rejected on a disqualifying W0 foul', () {
      final script = w0Script(substitutionTeam: offense);
      _expectCode(script.ledger(), input, GameValidationCode.wrongTeam);
    });

    test(
      'tactical substitution before FTs without disqualification is rejected',
      () {
        final script = w0Script(
          priorFouls: 0,
          reason: SubstitutionReason.tactical,
        );
        _expectCode(script.ledger(), input, GameValidationCode.deadBallInvalid);
      },
    );

    test('a fifth foul does not open W0', () {
      final script = w0Script(
        priorFouls: 4,
        includeSubstitution: false,
        includeFreeThrows: false,
      );
      // No W0 exists; a tactical substitution here is illegal.
      final defender = _starter(input, defense, Position.pg);
      script.substitution(
        team: defense,
        playerOut: defender,
        playerIn: _bench(input, defense),
        reason: SubstitutionReason.tactical,
        clock: 690,
        shotClock: 14,
      );
      _expectCode(script.ledger(), input, GameValidationCode.deadBallInvalid);
    });

    test('W0 cannot occur at clock zero', () {
      final script = GameScript(input)
        ..startGame()
        ..startPeriod(1, input.startingTeamId, clock: 720)
        ..startPossession('p1', offense, clock: 1, shotClock: 24);
      final defender = _starter(input, defense, Position.pg);
      final drawer = _starter(input, offense, Position.pg);
      for (var i = 0; i < 5; i++) {
        script.foul(
          team: defense,
          player: defender,
          kind: FoulKind.nonShooting,
          drawnBy: drawer,
          clock: 1,
          shotClock: 24,
        );
      }
      script.foul(
        team: defense,
        player: defender,
        kind: FoulKind.shooting,
        freeThrows: 2,
        drawnBy: drawer,
        clock: 0,
        shotClock: 23,
      );
      script.substitution(
        team: defense,
        playerOut: defender,
        playerIn: _bench(input, defense),
        reason: SubstitutionReason.foulOut,
        clock: 0,
        shotClock: 23,
      );
      _expectCode(script.ledger(), input, GameValidationCode.deadBallInvalid);
    });

    test('W0 preserves the awarded free-throw group', () {
      final script = w0Script();
      final freeThrows = script.events.whereType<FreeThrowAttempt>().toList();
      expect(freeThrows, hasLength(2));
      expect(freeThrows.first.groupId, freeThrows.last.groupId);
      expect(freeThrows.first.attemptsInGroup, 2);
      expect(freeThrows.last.attemptIndex, 2);
      expect(
        () => GameEventReducer.validate(input, script.ledger()),
        returnsNormally,
      );
    });
  });

  group('W2 after a made final free throw', () {
    test('accepts a substitution after the possession ends', () {
      final script = GameScript(input)
        ..startGame()
        ..startPeriod(1, input.startingTeamId, clock: 720)
        ..startPossession('p1', offense, clock: 700);
      script.foul(
        team: defense,
        player: _starter(input, defense, Position.pg),
        kind: FoulKind.shooting,
        freeThrows: 2,
        drawnBy: _starter(input, offense, Position.pg),
        clock: 690,
        shotClock: 14,
      );
      script.ft(
        team: offense,
        shooter: _starter(input, offense, Position.pg),
        groupId: 'ft1',
        index: 1,
        total: 2,
        made: true,
        clock: 690,
        shotClock: 14,
      );
      script.ft(
        team: offense,
        shooter: _starter(input, offense, Position.pg),
        groupId: 'ft1',
        index: 2,
        total: 2,
        made: true,
        clock: 690,
        shotClock: 14,
      );
      script.endPossession(
        possessionId: 'p1',
        team: offense,
        reason: PossessionEndReason.madeFinalFreeThrow,
        clock: 690,
        shotClock: 14,
      );
      script.substitution(
        team: offense,
        playerOut: _starter(input, offense, Position.pg),
        playerIn: _bench(input, offense),
        reason: SubstitutionReason.tactical,
        clearShotClock: true,
      );
      expect(
        () => GameEventReducer.validate(input, script.ledger()),
        returnsNormally,
      );
    });

    test('rejects a substitution after a defensive rebound', () {
      final script = GameScript(input)
        ..startGame()
        ..startPeriod(1, input.startingTeamId, clock: 720)
        ..startPossession('p1', offense, clock: 700);
      script.foul(
        team: defense,
        player: _starter(input, defense, Position.pg),
        kind: FoulKind.shooting,
        freeThrows: 2,
        drawnBy: _starter(input, offense, Position.pg),
        clock: 690,
        shotClock: 14,
      );
      script.ft(
        team: offense,
        shooter: _starter(input, offense, Position.pg),
        groupId: 'ft1',
        index: 1,
        total: 2,
        made: true,
        clock: 690,
        shotClock: 14,
      );
      final miss = script.ft(
        team: offense,
        shooter: _starter(input, offense, Position.pg),
        groupId: 'ft1',
        index: 2,
        total: 2,
        made: false,
        clock: 690,
        shotClock: 14,
      );
      script.rebound(
        team: defense,
        player: _starter(input, defense, Position.c),
        offensive: false,
        missedEventSequence: miss.sequence,
        clock: 690,
        shotClock: 24,
      );
      script.endPossession(
        possessionId: 'p1',
        team: offense,
        reason: PossessionEndReason.defensiveRebound,
        clock: 690,
        shotClock: 24,
      );
      script.substitution(
        team: defense,
        playerOut: _starter(input, defense, Position.pg),
        playerIn: _bench(input, defense),
        reason: SubstitutionReason.tactical,
      );
      _expectCode(script.ledger(), input, GameValidationCode.deadBallInvalid);
    });
  });

  group('W4 after an offensive-foul turnover', () {
    test('accepts a substitution after the possession ends', () {
      final script = GameScript(input)
        ..startGame()
        ..startPeriod(1, input.startingTeamId, clock: 720)
        ..startPossession('p1', offense, clock: 700);
      final offender = _starter(input, offense, Position.pf);
      script.foul(
        team: offense,
        player: offender,
        kind: FoulKind.offensive,
        clock: 690,
        shotClock: 14,
      );
      script.turnover(
        team: offense,
        player: offender,
        reason: TurnoverReason.offensiveFoul,
        clock: 690,
        shotClock: 14,
      );
      script.endPossession(
        possessionId: 'p1',
        team: offense,
        reason: PossessionEndReason.turnover,
        clock: 690,
        shotClock: 14,
      );
      script.substitution(
        team: offense,
        playerOut: offender,
        playerIn: _bench(input, offense),
        reason: SubstitutionReason.tactical,
        clearShotClock: true,
      );
      expect(
        () => GameEventReducer.validate(input, script.ledger()),
        returnsNormally,
      );
    });
  });

  group('horn P1/P2/P3 obligation', () {
    GameScript hornFoul({
      required GameInput withInput,
      required bool retainedFoul,
      required bool madeFinalFt,
      bool substitute = true,
      bool nextPossession = true,
      bool startNextPeriod = true,
    }) {
      final custom = withInput;
      final offenseTeam = custom.startingTeamId;
      final defenseTeam = custom.opponentOf(offenseTeam);
      final script = GameScript(custom)
        ..startGame()
        ..startPeriod(1, offenseTeam, clock: 720)
        ..startPossession('p1', offenseTeam, clock: 1, shotClock: 24);
      final defender = _starter(custom, defenseTeam, Position.pg);
      final drawer = _starter(custom, offenseTeam, Position.pg);
      for (var i = 0; i < 5; i++) {
        script.foul(
          team: defenseTeam,
          player: defender,
          kind: FoulKind.nonShooting,
          drawnBy: drawer,
          clock: 1,
          shotClock: 24,
        );
      }
      script.foul(
        team: defenseTeam,
        player: defender,
        kind: retainedFoul ? FoulKind.nonShooting : FoulKind.shooting,
        freeThrows: retainedFoul ? 0 : 2,
        drawnBy: drawer,
        clock: 0,
        shotClock: 23,
      );
      if (retainedFoul) {
        script.endPossession(
          possessionId: 'p1',
          team: offenseTeam,
          reason: PossessionEndReason.periodEnd,
          clock: 0,
          shotClock: 23,
        );
      } else {
        script.ft(
          team: offenseTeam,
          shooter: drawer,
          groupId: 'ft1',
          index: 1,
          total: 2,
          made: true,
          clock: 0,
          shotClock: 23,
        );
        if (madeFinalFt) {
          script.ft(
            team: offenseTeam,
            shooter: drawer,
            groupId: 'ft1',
            index: 2,
            total: 2,
            made: true,
            clock: 0,
            shotClock: 23,
          );
          script.endPossession(
            possessionId: 'p1',
            team: offenseTeam,
            reason: PossessionEndReason.madeFinalFreeThrow,
            clock: 0,
            shotClock: 23,
          );
        } else {
          final miss = script.ft(
            team: offenseTeam,
            shooter: drawer,
            groupId: 'ft1',
            index: 2,
            total: 2,
            made: false,
            clock: 0,
            shotClock: 23,
          );
          script.deadBall(
            team: offenseTeam,
            missedEventSequence: miss.sequence,
            clock: 0,
            shotClock: 23,
          );
          script.endPossession(
            possessionId: 'p1',
            team: offenseTeam,
            reason: PossessionEndReason.periodEnd,
            clock: 0,
            shotClock: 23,
          );
        }
      }
      script.endPeriod(1);
      if (startNextPeriod) {
        script.startPeriod(2, custom.opponentOf(offenseTeam), clock: 720);
      }
      if (substitute) {
        script.substitution(
          team: defenseTeam,
          playerOut: defender,
          playerIn: _bench(custom, defenseTeam),
          reason: SubstitutionReason.foulOut,
        );
      }
      if (nextPossession) {
        script.startPossession(
          'p2',
          custom.opponentOf(offenseTeam),
          clock: 700,
        );
      }
      return script;
    }

    test('P1 made final free throw resolves and replaces at W5', () {
      final custom = _input(rules: _customRules);
      final script = hornFoul(
        withInput: custom,
        retainedFoul: false,
        madeFinalFt: true,
      );
      expect(
        () => GameEventReducer.validate(custom, script.ledger()),
        returnsNormally,
      );
    });

    test('P1 missed final free throw resolves and replaces at W5', () {
      final custom = _input(rules: _customRules);
      final script = hornFoul(
        withInput: custom,
        retainedFoul: false,
        madeFinalFt: false,
      );
      expect(
        () => GameEventReducer.validate(custom, script.ledger()),
        returnsNormally,
      );
    });

    test('P2 retained foul resolves and replaces at W5', () {
      final custom = _input(rules: _customRules);
      final script = hornFoul(
        withInput: custom,
        retainedFoul: true,
        madeFinalFt: true,
      );
      expect(
        () => GameEventReducer.validate(custom, script.ledger()),
        returnsNormally,
      );
    });

    test('rejects a live event before the W5 replacement', () {
      final custom = _input(rules: _customRules);
      final script = hornFoul(
        withInput: custom,
        retainedFoul: false,
        madeFinalFt: true,
        substitute: false,
        nextPossession: false,
      );
      script.startPossession(
        'p2',
        custom.opponentOf(custom.startingTeamId),
        clock: 700,
      );
      _expectCode(script.ledger(), custom, GameValidationCode.playerNotActive);
    });

    test('rejects a substitution between PeriodEnded and PeriodStarted', () {
      final custom = _input(rules: _customRules);
      final script = hornFoul(
        withInput: custom,
        retainedFoul: false,
        madeFinalFt: true,
        substitute: false,
        nextPossession: false,
        startNextPeriod: false,
      );
      final defender = _starter(
        custom,
        custom.opponentOf(custom.startingTeamId),
        Position.pg,
      );
      script.substitution(
        team: custom.opponentOf(custom.startingTeamId),
        playerOut: defender,
        playerIn: _bench(custom, custom.opponentOf(custom.startingTeamId)),
        reason: SubstitutionReason.foulOut,
        clock: 0,
      );
      _expectCode(script.ledger(), custom, GameValidationCode.deadBallInvalid);
    });
  });

  group('additional frozen rejection cases', () {
    GameScript basePossession() => GameScript(input)
      ..startGame()
      ..startPeriod(1, input.startingTeamId, clock: 720)
      ..startPossession('p1', offense, clock: 700);

    test('rejects a null shot clock during an open possession', () {
      final script = basePossession();
      script.foul(
        team: defense,
        player: _starter(input, defense, Position.pg),
        kind: FoulKind.nonShooting,
        drawnBy: _starter(input, offense, Position.pg),
        clock: 690,
        shotClock: 14,
      );
      script.substitution(
        team: defense,
        playerOut: _starter(input, defense, Position.pg),
        playerIn: _bench(input, defense),
        reason: SubstitutionReason.tactical,
        clearShotClock: true,
      );
      _expectCode(script.ledger(), input, GameValidationCode.invalidShotClock);
    });

    test('rejects a W0 substitution that alters the free-throw group', () {
      final custom = _input(rules: _customRules);
      final script = GameScript(custom)
        ..startGame()
        ..startPeriod(1, custom.startingTeamId, clock: 720)
        ..startPossession('p1', custom.startingTeamId, clock: 700);
      final offenseTeam = custom.startingTeamId;
      final defenseTeam = custom.opponentOf(offenseTeam);
      final defender = _starter(custom, defenseTeam, Position.pg);
      final drawer = _starter(custom, offenseTeam, Position.pg);
      for (var i = 0; i < 5; i++) {
        script.foul(
          team: defenseTeam,
          player: defender,
          kind: FoulKind.nonShooting,
          drawnBy: drawer,
          clock: 690,
          shotClock: 14,
        );
      }
      script.foul(
        team: defenseTeam,
        player: defender,
        kind: FoulKind.shooting,
        freeThrows: 2,
        drawnBy: drawer,
        clock: 690,
        shotClock: 14,
      );
      script.substitution(
        team: defenseTeam,
        playerOut: defender,
        playerIn: _bench(custom, defenseTeam),
        reason: SubstitutionReason.foulOut,
      );
      script.ft(
        team: offenseTeam,
        shooter: drawer,
        groupId: 'g1',
        index: 1,
        total: 2,
        made: true,
        clock: 690,
        shotClock: 14,
      );
      script.ft(
        team: offenseTeam,
        shooter: drawer,
        groupId: 'g2',
        index: 2,
        total: 2,
        made: true,
        clock: 690,
        shotClock: 14,
      );
      _expectCode(
        script.ledger(),
        custom,
        GameValidationCode.freeThrowSequenceInvalid,
      );
    });

    test(
      'rejects a substitution after a steal turnover ends the possession',
      () {
        final script = basePossession();
        final offender = _starter(input, offense, Position.pg);
        script.turnover(
          team: offense,
          player: offender,
          reason: TurnoverReason.steal,
          stolenBy: _starter(input, defense, Position.pg),
          clock: 690,
          shotClock: 14,
        );
        script.endPossession(
          possessionId: 'p1',
          team: offense,
          reason: PossessionEndReason.turnover,
          clock: 690,
          shotClock: 14,
        );
        script.substitution(
          team: offense,
          playerOut: offender,
          playerIn: _bench(input, offense),
          reason: SubstitutionReason.tactical,
          clearShotClock: true,
        );
        _expectCode(script.ledger(), input, GameValidationCode.deadBallInvalid);
      },
    );

    test('rejects a substitution after a made field goal (no W3)', () {
      final script = basePossession();
      final shooter = _starter(input, offense, Position.sg);
      script.fga(
        team: offense,
        shooter: shooter,
        made: true,
        clock: 690,
        shotClock: 14,
      );
      script.endPossession(
        possessionId: 'p1',
        team: offense,
        reason: PossessionEndReason.madeFieldGoal,
        clock: 690,
        shotClock: 14,
      );
      script.substitution(
        team: offense,
        playerOut: shooter,
        playerIn: _bench(input, offense),
        reason: SubstitutionReason.tactical,
        clearShotClock: true,
      );
      _expectCode(script.ledger(), input, GameValidationCode.deadBallInvalid);
    });

    test('rejects a substitution after DeadBallMiss', () {
      final script = GameScript(input)
        ..startGame()
        ..startPeriod(1, input.startingTeamId, clock: 720)
        ..startPossession('p1', offense, clock: 1, shotClock: 24);
      final shooter = _starter(input, offense, Position.sg);
      final miss = script.fga(
        team: offense,
        shooter: shooter,
        made: false,
        clock: 0,
        shotClock: 23,
      );
      script.deadBall(
        team: offense,
        missedEventSequence: miss.sequence,
        clock: 0,
        shotClock: 23,
      );
      script.substitution(
        team: offense,
        playerOut: shooter,
        playerIn: _bench(input, offense),
        reason: SubstitutionReason.tactical,
        clock: 0,
        shotClock: 23,
      );
      _expectCode(script.ledger(), input, GameValidationCode.deadBallInvalid);
    });

    test('rejects a foreign incoming player', () {
      final script = GameScript(input)
        ..startGame()
        ..startPeriod(1, input.startingTeamId, clock: 720);
      script.substitution(
        team: home,
        playerOut: _starter(input, home, Position.pg),
        playerIn: input.awayTeam.players
            .firstWhere((player) => !input.awayLineup.containsPlayer(player.id))
            .id
            .value,
        reason: SubstitutionReason.tactical,
      );
      _expectCode(
        script.ledger(),
        input,
        GameValidationCode.foreignLineupPlayer,
      );
    });

    test('rejects foulOut for a player below the limit', () {
      final script = GameScript(input)
        ..startGame()
        ..startPeriod(1, input.startingTeamId, clock: 720);
      script.substitution(
        team: home,
        playerOut: _starter(input, home, Position.pg),
        playerIn: _bench(input, home),
        reason: SubstitutionReason.foulOut,
      );
      _expectCode(script.ledger(), input, GameValidationCode.playerNotActive);
    });

    test('rejects a substitution whose period does not match', () {
      final script = GameScript(input)
        ..startGame()
        ..startPeriod(1, input.startingTeamId, clock: 720);
      script.substitution(
        team: home,
        playerOut: _starter(input, home, Position.pg),
        playerIn: _bench(input, home),
        reason: SubstitutionReason.tactical,
      );
      final events = script.events;
      final sub = events.removeLast() as Substitution;
      events.add(
        Substitution(
          sequence: sub.sequence,
          period: 2,
          gameClock: sub.gameClock,
          shotClock: sub.shotClock,
          teamId: sub.teamId,
          playerOutId: sub.playerOutId,
          playerInId: sub.playerInId,
          reason: sub.reason,
        ),
      );
      _expectCode(script.ledger(), input, GameValidationCode.periodNotStarted);
    });

    test('rejects possession end with a conflicting reason', () {
      final script = basePossession();
      script.fga(
        team: offense,
        shooter: _starter(input, offense, Position.sg),
        made: false,
        clock: 690,
        shotClock: 14,
      );
      script.endPossession(
        possessionId: 'p1',
        team: offense,
        reason: PossessionEndReason.turnover,
        clock: 690,
        shotClock: 14,
      );
      _expectCode(
        script.ledger(),
        input,
        GameValidationCode.possessionEndReasonInvalid,
      );
    });

    test('rejects possession end for an unknown possession', () {
      final script = basePossession();
      script.endPossession(
        possessionId: 'nope',
        team: offense,
        reason: PossessionEndReason.turnover,
        clock: 690,
        shotClock: 14,
      );
      _expectCode(
        script.ledger(),
        input,
        GameValidationCode.possessionEndReasonInvalid,
      );
    });

    test('rejects an early GameEnded before the final period', () {
      final script = GameScript(input)
        ..startGame()
        ..startPeriod(1, input.startingTeamId, clock: 720)
        ..endPeriod(1);
      script.events.add(
        GameEnded(
          sequence: script.events.last.sequence + 1,
          period: 1,
          gameClock: 0,
          shotClock: 0,
          finalPeriod: 1,
        ),
      );
      _expectCode(script.ledger(), input, GameValidationCode.gameEndInvalid);
    });

    test('rejects any event after GameEnded', () {
      final result = GameSimulator().simulate(input);
      final events = result.events.toList();
      final last = events.last;
      events.add(
        Substitution(
          sequence: last.sequence + 1,
          period: last.period,
          gameClock: last.gameClock,
          shotClock: last.shotClock,
          teamId: home.value,
          playerOutId: _starter(input, home, Position.pg),
          playerInId: _bench(input, home),
          reason: SubstitutionReason.tactical,
        ),
      );
      _expectCode(
        GameEventLedger(
          gameId: input.gameId,
          inputFingerprint: result.inputFingerprint,
          events: events,
        ),
        input,
        GameValidationCode.eventAfterGameEnded,
      );
    });

    test('rejects replay while a disqualified player remains active', () {
      final result = GameSimulator().simulate(input);
      final events = result.events.toList();
      final subIndexes = [
        for (var i = 0; i < events.length; i++)
          if (events[i] is Substitution) i,
      ];
      expect(subIndexes.length, greaterThanOrEqualTo(2));
      events.removeAt(subIndexes[1]);
      events.removeAt(subIndexes[0]);
      for (var i = 0; i < events.length; i++) {
        events[i] = resequenceEvent(events[i], i + 1);
      }
      _expectCode(
        GameEventLedger(
          gameId: input.gameId,
          inputFingerprint: result.inputFingerprint,
          events: events,
        ),
        input,
        GameValidationCode.playerNotActive,
      );
    });

    test('rejects a window closing with two disqualified players', () {
      // Two disqualifications can coexist only while a window is open; the
      // window-close guard must reject the ledger before it can validate.
      final input = _input(rules: _customRules);
      final offense = input.startingTeamId;
      final defense = input.opponentOf(offense);
      final first = _starter(input, defense, Position.pg);
      final second = _starter(input, defense, Position.sg);
      final drawer = _starter(input, offense, Position.pg);
      final script = GameScript(input)
        ..startGame()
        ..startPeriod(1, offense, clock: 720);
      for (var i = 0; i < 5; i++) {
        final clock = 700 - i * 10;
        script
          ..startPossession('h$i', offense, clock: clock, shotClock: 24)
          ..foul(
            team: defense,
            player: first,
            kind: FoulKind.nonShooting,
            drawnBy: drawer,
            clock: clock - 5,
            shotClock: 19,
          )
          ..turnover(
            team: offense,
            player: drawer,
            reason: TurnoverReason.nonSteal,
            clock: clock - 5,
            shotClock: 19,
          )
          ..endPossession(
            possessionId: 'h$i',
            team: offense,
            reason: PossessionEndReason.turnover,
            clock: clock - 5,
            shotClock: 19,
          )
          ..startPossession('a$i', defense, clock: clock - 5, shotClock: 24)
          ..turnover(
            team: defense,
            player: first,
            reason: TurnoverReason.nonSteal,
            clock: clock - 10,
            shotClock: 19,
          )
          ..endPossession(
            possessionId: 'a$i',
            team: defense,
            reason: PossessionEndReason.turnover,
            clock: clock - 10,
            shotClock: 19,
          );
      }
      script
        ..startPossession('h5', offense, clock: 600, shotClock: 24)
        ..foul(
          team: defense,
          player: first,
          kind: FoulKind.nonShooting,
          drawnBy: drawer,
          clock: 595,
          shotClock: 19,
        )
        ..foul(
          team: defense,
          player: second,
          kind: FoulKind.nonShooting,
          drawnBy: drawer,
          clock: 590,
          shotClock: 14,
        )
        ..turnover(
          team: offense,
          player: drawer,
          reason: TurnoverReason.nonSteal,
          clock: 590,
          shotClock: 14,
        )
        ..endPossession(
          possessionId: 'h5',
          team: offense,
          reason: PossessionEndReason.turnover,
          clock: 590,
          shotClock: 14,
        );
      _expectCode(script.ledger(), input, GameValidationCode.playerNotActive);
    });

    test(
      'rejects an event crediting a departed starter after substitution',
      () {
        final script = GameScript(input)
          ..startGame()
          ..startPeriod(1, input.startingTeamId, clock: 720);
        final out = _starter(input, home, Position.pg);
        script.substitution(
          team: home,
          playerOut: out,
          playerIn: _bench(input, home),
          reason: SubstitutionReason.tactical,
        );
        script.startPossession('p1', input.startingTeamId, clock: 700);
        // A made-shot assist by the departed starter must fail eligibility.
        script.events.add(
          FieldGoalAttempt(
            sequence: script.events.last.sequence + 1,
            period: 1,
            gameClock: 690,
            shotClock: 14,
            teamId: home.value,
            shooterId: _starter(input, home, Position.sg),
            shotValue: 2,
            made: true,
            andOne: false,
            assistedById: out,
          ),
        );
        _expectCode(script.ledger(), input, GameValidationCode.playerNotActive);
      },
    );
  });

  group('mandatory replacement and depletion', () {
    GameScript sixFouls({
      required GameInput withInput,
      required bool replace,
      bool closeWindow = true,
    }) {
      final script = GameScript(withInput)
        ..startGame()
        ..startPeriod(1, withInput.startingTeamId, clock: 720)
        ..startPossession('p1', withInput.startingTeamId, clock: 700);
      final defender = _starter(
        withInput,
        withInput.opponentOf(withInput.startingTeamId),
        Position.pg,
      );
      for (var i = 0; i < 6; i++) {
        script.foul(
          team: withInput.opponentOf(withInput.startingTeamId),
          player: defender,
          kind: FoulKind.nonShooting,
          drawnBy: _starter(withInput, withInput.startingTeamId, Position.pg),
          clock: 690,
          shotClock: 14,
        );
      }
      if (replace) {
        script.substitution(
          team: withInput.opponentOf(withInput.startingTeamId),
          playerOut: defender,
          playerIn: _bench(
            withInput,
            withInput.opponentOf(withInput.startingTeamId),
          ),
          reason: SubstitutionReason.foulOut,
        );
      }
      if (!closeWindow) return script;
      // Any further event closes the window and triggers the mandatory check.
      script.foul(
        team: withInput.opponentOf(withInput.startingTeamId),
        player: _starter(
          withInput,
          withInput.opponentOf(withInput.startingTeamId),
          Position.sg,
        ),
        kind: FoulKind.nonShooting,
        drawnBy: _starter(withInput, withInput.startingTeamId, Position.sg),
        clock: 690,
        shotClock: 14,
      );
      return script;
    }

    test('accepts a foul-out replacement before the window closes', () {
      final custom = _input(rules: _customRules);
      final script = sixFouls(withInput: custom, replace: true);
      expect(
        () => GameEventReducer.validate(custom, script.ledger()),
        returnsNormally,
      );
    });

    test('rejects a missing mandatory replacement', () {
      final custom = _input(rules: _customRules);
      final script = sixFouls(withInput: custom, replace: false);
      _expectCode(script.ledger(), custom, GameValidationCode.playerNotActive);
    });

    test('allows depleted continuation with no eligible bench', () {
      final league = const LeagueGenerator().generate(
        const GenerationConfig(seed: 20261028, playersPerTeam: 5),
      );
      final customLeague = league;
      final homeTeam = customLeague.teams.first;
      final awayTeam = customLeague.teams[1];
      final depletedInput = GameInput.create(
        gameId: 'depleted',
        league: customLeague,
        homeTeamId: homeTeam.id,
        awayTeamId: awayTeam.id,
        homeLineup: CourtLineup.defaultFor(homeTeam),
        awayLineup: CourtLineup.defaultFor(awayTeam),
        seed: 42,
        rules: _customRules,
      );
      final script = sixFouls(withInput: depletedInput, replace: false);
      expect(
        () => GameEventReducer.validate(depletedInput, script.ledger()),
        returnsNormally,
      );
    });

    test(
      'rejects a tactical substitution that removes a disqualified player',
      () {
        final custom = _input(rules: _customRules);
        final script = sixFouls(
          withInput: custom,
          replace: false,
          closeWindow: false,
        );
        final defender = _starter(
          custom,
          custom.opponentOf(custom.startingTeamId),
          Position.pg,
        );
        script.substitution(
          team: custom.opponentOf(custom.startingTeamId),
          playerOut: defender,
          playerIn: _bench(custom, custom.opponentOf(custom.startingTeamId)),
          reason: SubstitutionReason.tactical,
        );
        _expectCode(
          script.ledger(),
          custom,
          GameValidationCode.playerNotActive,
        );
      },
    );
  });
}
