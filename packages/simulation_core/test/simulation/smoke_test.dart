import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('manual smoke fixture replays', () {
    final input = buildInput();
    final home = input.homeTeamId;
    final away = input.awayTeamId;
    final homeStarter = input.startingTeamId;
    final awayStarter = input.opponentOf(homeStarter);
    final homePg = playerAt(input, home, Position.pg);
    final events = <GameEvent>[
      GameStarted(
        sequence: 1,
        period: 1,
        gameClock: 720,
        shotClock: null,
        homeTeamId: home.value,
        awayTeamId: away.value,
        startingTeamId: homeStarter.value,
      ),
      PeriodStarted(
        sequence: 2,
        period: 1,
        gameClock: 720,
        shotClock: null,
        startingTeamId: homeStarter.value,
      ),
      PossessionStarted(
        sequence: 3,
        period: 1,
        gameClock: 24,
        shotClock: 24,
        possessionId: 'p1',
        offenseTeamId: homeStarter.value,
      ),
      FieldGoalAttempt(
        sequence: 4,
        period: 1,
        gameClock: 0,
        shotClock: 0,
        teamId: homeStarter.value,
        shooterId: homePg,
        shotValue: 2,
        made: true,
        andOne: false,
      ),
      PossessionEnded(
        sequence: 5,
        period: 1,
        gameClock: 0,
        shotClock: 0,
        possessionId: 'p1',
        offenseTeamId: homeStarter.value,
        reason: PossessionEndReason.madeFieldGoal,
      ),
      PeriodEnded(sequence: 6, period: 1, gameClock: 0, shotClock: null),
      PeriodStarted(
        sequence: 7,
        period: 2,
        gameClock: 720,
        shotClock: null,
        startingTeamId: awayStarter.value,
      ),
      PossessionStarted(
        sequence: 8,
        period: 2,
        gameClock: 24,
        shotClock: 24,
        possessionId: 'p2',
        offenseTeamId: awayStarter.value,
      ),
      PossessionEnded(
        sequence: 9,
        period: 2,
        gameClock: 0,
        shotClock: 24,
        possessionId: 'p2',
        offenseTeamId: awayStarter.value,
        reason: PossessionEndReason.periodEnd,
      ),
      PeriodEnded(sequence: 10, period: 2, gameClock: 0, shotClock: null),
      PeriodStarted(
        sequence: 11,
        period: 3,
        gameClock: 720,
        shotClock: null,
        startingTeamId: homeStarter.value,
      ),
      PossessionStarted(
        sequence: 12,
        period: 3,
        gameClock: 24,
        shotClock: 24,
        possessionId: 'p3',
        offenseTeamId: homeStarter.value,
      ),
      FieldGoalAttempt(
        sequence: 13,
        period: 3,
        gameClock: 0,
        shotClock: 0,
        teamId: homeStarter.value,
        shooterId: homePg,
        shotValue: 2,
        made: true,
        andOne: false,
      ),
      PossessionEnded(
        sequence: 14,
        period: 3,
        gameClock: 0,
        shotClock: 0,
        possessionId: 'p3',
        offenseTeamId: homeStarter.value,
        reason: PossessionEndReason.madeFieldGoal,
      ),
      PeriodEnded(sequence: 15, period: 3, gameClock: 0, shotClock: null),
      PeriodStarted(
        sequence: 16,
        period: 4,
        gameClock: 720,
        shotClock: null,
        startingTeamId: awayStarter.value,
      ),
      PossessionStarted(
        sequence: 17,
        period: 4,
        gameClock: 24,
        shotClock: 24,
        possessionId: 'p4',
        offenseTeamId: awayStarter.value,
      ),
      PossessionEnded(
        sequence: 18,
        period: 4,
        gameClock: 0,
        shotClock: 24,
        possessionId: 'p4',
        offenseTeamId: awayStarter.value,
        reason: PossessionEndReason.periodEnd,
      ),
      PeriodEnded(sequence: 19, period: 4, gameClock: 0, shotClock: null),
      GameEnded(
        sequence: 20,
        period: 4,
        gameClock: 0,
        shotClock: null,
        finalPeriod: 4,
      ),
    ];
    final state = GameEventReducer.replay(input, buildLedger(input, events));
    expect(state.ended, isTrue);
    final score = account(input, events);
    expect(score.teams[home.value]!.points, 4);
    expect(score.teams[away.value]!.points, 0);
  });
}
