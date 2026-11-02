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
}
