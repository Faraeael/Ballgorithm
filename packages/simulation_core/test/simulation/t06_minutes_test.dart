import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';

String _id(GameInput input, TeamId team, Position position) =>
    input.lineupFor(team).playerIdAt(position).value;

String _bench(GameInput input, TeamId team) => input.league.teams
    .firstWhere((candidate) => candidate.id == team)
    .players
    .firstWhere((player) => !input.lineupFor(team).containsPlayer(player.id))
    .id
    .value;

void main() {
  final input = buildInput(seed: 42);
  final home = input.homeTeamId;
  final away = input.awayTeamId;

  test('a full game with a W5 substitution yields exact seconds', () {
    final script = GameScript(input)
      ..startGame()
      ..startPeriod(1, input.startingTeamId, clock: 720);
    final out = _id(input, home, Position.pg);
    final incoming = _bench(input, home);
    script.substitution(
      team: home,
      playerOut: out,
      playerIn: incoming,
      reason: SubstitutionReason.tactical,
    );
    script.startPossession('p1', input.startingTeamId, clock: 700);
    script.fga(
      team: input.startingTeamId,
      shooter: _id(input, input.startingTeamId, Position.sg),
      made: true,
      clock: 690,
      shotClock: 14,
    );
    script.endPossession(
      possessionId: 'p1',
      team: input.startingTeamId,
      reason: PossessionEndReason.madeFieldGoal,
      clock: 690,
      shotClock: 14,
    );
    script.endPeriod(1);
    for (var period = 2; period <= 4; period++) {
      script.startPeriod(
        period,
        period.isOdd
            ? input.startingTeamId
            : input.opponentOf(input.startingTeamId),
        clock: 720,
      );
      script.endPeriod(period);
    }
    script.endGame(4);

    final ledger = GameEventReducer.validate(input, script.ledger());
    final box = EventAccounting.aggregate(ledger);

    expect(box.players, hasLength(24));
    expect(box.players[out]!.secondsPlayed, 0);
    // Enters at 720 in period 1, plays 30 s to the shot, 690 s to the horn,
    // then three full periods.
    expect(box.players[incoming]!.secondsPlayed, 30 + 690 + 3 * 720);
    for (final position in [
      Position.sg,
      Position.sf,
      Position.pf,
      Position.c,
    ]) {
      expect(box.players[_id(input, home, position)]!.secondsPlayed, 4 * 720);
    }
    for (final teamId in [input.homeTeamId, input.awayTeamId]) {
      final teamSeconds = box.players.values
          .where((player) => player.teamId == teamId.value)
          .fold<int>(0, (sum, player) => sum + player.secondsPlayed);
      expect(teamSeconds, 5 * 4 * 720);
    }
    final unused = box.players.values
        .where((player) => player.secondsPlayed == 0)
        .length;
    expect(unused, 14);
  });

  test('a W1 substitution splits the possession interval exactly', () {
    final defense = input.opponentOf(input.startingTeamId);
    final script = GameScript(input)
      ..startGame()
      ..startPeriod(1, input.startingTeamId, clock: 720)
      ..startPossession('p1', input.startingTeamId, clock: 700);
    script.foul(
      team: defense,
      player: _id(input, defense, Position.pg),
      kind: FoulKind.nonShooting,
      drawnBy: _id(input, input.startingTeamId, Position.pg),
      clock: 690,
      shotClock: 14,
    );
    final out = _id(input, defense, Position.pg);
    final incoming = _bench(input, defense);
    script.substitution(
      team: defense,
      playerOut: out,
      playerIn: incoming,
      reason: SubstitutionReason.tactical,
    );
    script.fga(
      team: input.startingTeamId,
      shooter: _id(input, input.startingTeamId, Position.sg),
      made: true,
      clock: 680,
      shotClock: 4,
    );

    final ledger = GameEventReducer.validate(input, script.ledger());
    final box = EventAccounting.aggregate(ledger);
    // Period start 720 -> possession 700 (20 s), foul 690 (10 s), sub at 690,
    // action 680 (10 s).
    expect(box.players[out]!.secondsPlayed, 30);
    expect(box.players[incoming]!.secondsPlayed, 10);
  });

  test('two substitutions on the same clock change no intervals', () {
    final script = GameScript(input)
      ..startGame()
      ..startPeriod(1, input.startingTeamId, clock: 720);
    final outA = _id(input, home, Position.pg);
    final outB = _id(input, home, Position.sg);
    final bench = input.homeTeam.players
        .where((p) => !input.homeLineup.containsPlayer(p.id))
        .toList();
    script.substitution(
      team: home,
      playerOut: outA,
      playerIn: bench[0].id.value,
      reason: SubstitutionReason.tactical,
    );
    script.substitution(
      team: home,
      playerOut: outB,
      playerIn: bench[1].id.value,
      reason: SubstitutionReason.tactical,
    );
    script.startPossession('p1', input.startingTeamId, clock: 700);
    script.fga(
      team: home,
      shooter: _id(input, home, Position.sf),
      made: true,
      clock: 690,
      shotClock: 14,
    );
    script.endPossession(
      possessionId: 'p1',
      team: home,
      reason: PossessionEndReason.madeFieldGoal,
      clock: 690,
      shotClock: 14,
    );
    script.endPeriod(1);
    for (var period = 2; period <= 4; period++) {
      script.startPeriod(
        period,
        period.isOdd
            ? input.startingTeamId
            : input.opponentOf(input.startingTeamId),
        clock: 720,
      );
      script.endPeriod(period);
    }
    script.events.add(
      GameEnded(
        sequence: script.events.last.sequence + 1,
        period: 4,
        gameClock: 0,
        shotClock: 0,
        finalPeriod: 4,
      ),
    );
    final box = EventAccounting.aggregate(
      GameEventReducer.validate(input, script.ledger()),
    );
    expect(box.players[outA]!.secondsPlayed, 0);
    expect(box.players[outB]!.secondsPlayed, 0);
    expect(box.players[bench[0].id.value]!.secondsPlayed, 2880);
    expect(box.players[bench[1].id.value]!.secondsPlayed, 2880);
  });

  test('overtime minutes use the 300-second period length', () {
    final script = GameScript(input)
      ..startGame()
      ..startPeriod(1, input.startingTeamId, clock: 720);
    for (var period = 1; period <= 4; period++) {
      final starter = period.isOdd ? home : away;
      script
        ..startPossession('p$period', starter, clock: 700)
        ..fga(
          team: starter,
          shooter: _id(input, starter, Position.sg),
          made: true,
          clock: 690,
          shotClock: 14,
        )
        ..endPossession(
          possessionId: 'p$period',
          team: starter,
          reason: PossessionEndReason.madeFieldGoal,
          clock: 690,
          shotClock: 14,
        )
        ..endPeriod(period);
      if (period < 4) {
        script.startPeriod(
          period + 1,
          period.isOdd
              ? input.opponentOf(input.startingTeamId)
              : input.startingTeamId,
          clock: 720,
        );
      }
    }
    // Regulation ends tied 4-4; overtime is 300 seconds.
    script
      ..startPeriod(5, home, clock: 300)
      ..startPossession('p5', home, clock: 280)
      ..fga(
        team: home,
        shooter: _id(input, home, Position.sg),
        made: true,
        clock: 270,
        shotClock: 14,
      )
      ..endPossession(
        possessionId: 'p5',
        team: home,
        reason: PossessionEndReason.madeFieldGoal,
        clock: 270,
        shotClock: 14,
      )
      ..endPeriod(5);
    script.events.add(
      GameEnded(
        sequence: script.events.last.sequence + 1,
        period: 5,
        gameClock: 0,
        shotClock: 0,
        finalPeriod: 5,
      ),
    );
    final box = EventAccounting.aggregate(
      GameEventReducer.validate(input, script.ledger()),
    );
    for (final id in input.homeLineup.playerIds) {
      expect(box.players[id]!.secondsPlayed, 4 * 720 + 300);
    }
  });

  test('a horn substitution ends the outgoing interval at zero', () {
    final script = GameScript(input)
      ..startGame()
      ..startPeriod(1, input.startingTeamId, clock: 720)
      ..endPeriod(1);
    final out = _id(input, home, Position.pg);
    script.startPeriod(2, input.opponentOf(input.startingTeamId), clock: 720);
    final incoming = _bench(input, home);
    script.substitution(
      team: home,
      playerOut: out,
      playerIn: incoming,
      reason: SubstitutionReason.tactical,
    );
    script.endPeriod(2);
    final box = EventAccounting.aggregate(
      GameEventReducer.validate(input, script.ledger()),
    );
    expect(box.players[out]!.secondsPlayed, 720);
    expect(box.players[incoming]!.secondsPlayed, 720);
  });

  test('a depleted five-player roster plays every interval', () {
    final league = const LeagueGenerator().generate(
      const GenerationConfig(seed: 20261028, playersPerTeam: 5),
    );
    final teamA = league.teams.first;
    final teamB = league.teams[1];
    final depleted = GameInput.create(
      gameId: 'depleted-minutes',
      league: league,
      homeTeamId: teamA.id,
      awayTeamId: teamB.id,
      homeLineup: CourtLineup.defaultFor(teamA),
      awayLineup: CourtLineup.defaultFor(teamB),
      seed: 42,
      rules: GameRules.standard,
    );
    final script = GameScript(depleted)
      ..startGame()
      ..startPeriod(1, depleted.startingTeamId, clock: 720);
    for (var period = 1; period <= 4; period++) {
      final starter = period.isOdd ? teamA.id : teamB.id;
      script
        ..startPossession('p$period', starter, clock: 700)
        ..fga(
          team: starter,
          shooter: starter == teamA.id
              ? depleted.homeLineup.playerIdAt(Position.sg).value
              : depleted.awayLineup.playerIdAt(Position.sg).value,
          made: true,
          value: period == 3 ? 3 : 2,
          clock: 690,
          shotClock: 14,
        )
        ..endPossession(
          possessionId: 'p$period',
          team: starter,
          reason: PossessionEndReason.madeFieldGoal,
          clock: 690,
          shotClock: 14,
        )
        ..endPeriod(period);
      if (period < 4) {
        script.startPeriod(
          period + 1,
          period.isOdd
              ? depleted.opponentOf(depleted.startingTeamId)
              : depleted.startingTeamId,
          clock: 720,
        );
      }
    }
    script.events.add(
      GameEnded(
        sequence: script.events.last.sequence + 1,
        period: 4,
        gameClock: 0,
        shotClock: 0,
        finalPeriod: 4,
      ),
    );
    final box = EventAccounting.aggregate(
      GameEventReducer.validate(depleted, script.ledger()),
    );
    for (final id in depleted.homeLineup.playerIds) {
      expect(box.players[id]!.secondsPlayed, 4 * 720);
    }
    expect(box.players, hasLength(10));
  });

  test('a substitute keeps the points, rebounds and fouls they record', () {
    final team = input.startingTeamId;
    final opponent = input.opponentOf(team);
    final starter = _id(input, team, Position.pg);
    final incoming = _bench(input, team);
    final script = GameScript(input)
      ..startGame()
      ..startPeriod(1, team, clock: 720);
    script.substitution(
      team: team,
      playerOut: starter,
      playerIn: incoming,
      reason: SubstitutionReason.tactical,
    );
    script.startPossession('p1', team, clock: 700);
    final miss = script.fga(team: team, shooter: incoming, made: false);
    script.rebound(
      team: team,
      player: incoming,
      offensive: true,
      missedEventSequence: miss.sequence,
      clock: 690,
      shotClock: 14,
    );
    script.fga(
      team: team,
      shooter: incoming,
      made: true,
      clock: 680,
      shotClock: 4,
    );
    script.endPossession(
      possessionId: 'p1',
      team: team,
      reason: PossessionEndReason.madeFieldGoal,
      clock: 680,
      shotClock: 4,
    );
    script.startPossession('p2', opponent, clock: 680);
    script.foul(
      team: team,
      player: incoming,
      kind: FoulKind.nonShooting,
      drawnBy: _id(input, opponent, Position.pg),
      clock: 670,
      shotClock: 14,
    );
    script.turnover(
      team: opponent,
      player: _id(input, opponent, Position.pg),
      reason: TurnoverReason.nonSteal,
      clock: 660,
      shotClock: 4,
    );
    script.endPossession(
      possessionId: 'p2',
      team: opponent,
      reason: PossessionEndReason.turnover,
      clock: 660,
      shotClock: 4,
    );
    script.endPeriod(1);
    for (var period = 2; period <= 4; period++) {
      script.startPeriod(period, period.isOdd ? team : opponent, clock: 720);
      script.endPeriod(period);
    }
    script.endGame(4);

    final box = account(input, script.events);
    final substitute = box.players[incoming]!;
    expect(substitute.points, 2);
    expect(substitute.rebounds, 1);
    expect(substitute.personalFouls, 1);
    expect(substitute.secondsPlayed, 4 * 720);
    final departed = box.players[starter]!;
    expect(departed.points, 0);
    expect(departed.rebounds, 0);
    expect(departed.personalFouls, 0);
    expect(departed.secondsPlayed, 0);

    // Every roster player keeps a row; unused bench stays fully zero.
    expect(box.players, hasLength(24));
    for (final teamId in [input.homeTeamId, input.awayTeamId]) {
      final roster = input.league.teams
          .firstWhere((candidate) => candidate.id == teamId)
          .players;
      for (final player in roster) {
        expect(box.players[player.id.value], isNotNull);
      }
    }
    final unused = input.league.teams
        .firstWhere((candidate) => candidate.id == team)
        .players
        .firstWhere(
          (player) =>
              !input.lineupFor(team).containsPlayer(player.id) &&
              player.id.value != incoming,
        );
    final unusedBox = box.players[unused.id.value]!;
    expect(unusedBox.secondsPlayed, 0);
    expect(unusedBox.points, 0);
    expect(unusedBox.rebounds, 0);
    expect(unusedBox.personalFouls, 0);

    // Completed-game conservation: 5 players x four full periods per team.
    for (final teamId in [input.homeTeamId, input.awayTeamId]) {
      final teamSeconds = box.players.values
          .where((player) => player.teamId == teamId.value)
          .fold<int>(0, (sum, player) => sum + player.secondsPlayed);
      expect(teamSeconds, 5 * 4 * 720);
    }
  });

  test('a player can enter and leave at one clock with zero seconds', () {
    final team = input.startingTeamId;
    final defense = input.opponentOf(team);
    final defender = _id(input, defense, Position.pg);
    final incoming = _bench(input, defense);
    final script = GameScript(input)
      ..startGame()
      ..startPeriod(1, team, clock: 720)
      ..startPossession('p1', team, clock: 700);
    script.foul(
      team: defense,
      player: defender,
      kind: FoulKind.nonShooting,
      drawnBy: _id(input, team, Position.pg),
      clock: 690,
      shotClock: 14,
    );
    script.substitution(
      team: defense,
      playerOut: defender,
      playerIn: incoming,
      reason: SubstitutionReason.tactical,
    );
    script.foul(
      team: defense,
      player: incoming,
      kind: FoulKind.nonShooting,
      drawnBy: _id(input, team, Position.sg),
      clock: 690,
      shotClock: 14,
    );
    script.substitution(
      team: defense,
      playerOut: incoming,
      playerIn: defender,
      reason: SubstitutionReason.tactical,
    );

    final box = account(input, script.events);
    final row = box.players[incoming]!;
    expect(row.secondsPlayed, 0);
    expect(row.personalFouls, 1);
    expect(row.points, 0);
    expect(row.rebounds, 0);
    // Each foul stays with its own committer; nothing is re-attributed.
    expect(row.personalFouls, 1);
    expect(box.players[defender]!.personalFouls, 1);
    expect(box.players[defender]!.secondsPlayed, 30);
    expect(
      box.players.values.fold<int>(
        0,
        (sum, player) => sum + player.personalFouls,
      ),
      2,
    );
  });
}
