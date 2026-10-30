import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import '../../tool/t015_metrics.dart';

const home = TeamId('team-1');
const away = TeamId('team-2');

GameEvent possession(String id, int sequence, {int clock = 700}) =>
    PossessionStarted(
      sequence: sequence,
      period: 1,
      gameClock: clock,
      shotClock: 24,
      possessionId: id,
      offenseTeamId: home.value,
    );

GameEvent miss(int sequence, {int clock = 690}) => FieldGoalAttempt(
  sequence: sequence,
  period: 1,
  gameClock: clock,
  shotClock: 14,
  teamId: home.value,
  shooterId: 'p1',
  shotValue: 2,
  made: false,
  andOne: false,
);

GameEvent offenseRebound(int sequence, int missed) => Rebound(
  sequence: sequence,
  period: 1,
  gameClock: 690,
  shotClock: 14,
  teamId: home.value,
  playerId: 'p1',
  offensive: true,
  missedEventSequence: missed,
);

GameEvent turnover(TurnoverReason reason, int sequence, {int clock = 685}) =>
    Turnover(
      sequence: sequence,
      period: 1,
      gameClock: clock,
      shotClock: 9,
      teamId: home.value,
      playerId: 'p1',
      reason: reason,
    );

GameEvent possessionEnd(
  PossessionEndReason reason,
  String id,
  int sequence, {
  int clock = 685,
}) => PossessionEnded(
  sequence: sequence,
  period: 1,
  gameClock: clock,
  shotClock: 9,
  possessionId: id,
  offenseTeamId: home.value,
  reason: reason,
);

void main() {
  group('possession counts', () {
    test('separates started, completed, period-end and OREB continuation', () {
      final events = <GameEvent>[
        possession('p1', 1),
        miss(2),
        offenseRebound(3, 2),
        turnover(TurnoverReason.nonSteal, 4),
        possessionEnd(PossessionEndReason.periodEnd, 'p1', 5, clock: 0),
        possession('p2', 6, clock: 600),
        turnover(TurnoverReason.steal, 7, clock: 590),
        possessionEnd(PossessionEndReason.turnover, 'p2', 8, clock: 590),
      ];
      final counts = possessionCounts(events, home);
      expect(counts.started, 2);
      expect(counts.completed, 1);
      expect(counts.periodEnd, 1);
      expect(counts.orebContinuations, 1);
      expect(counts.estimated, closeTo(2.0, 1e-9));
    });

    test('estimated possessions follow FGA − OREB + TOV + 0.44 FTA', () {
      final events = <GameEvent>[
        possession('p1', 1),
        miss(2),
        offenseRebound(3, 2),
        turnover(TurnoverReason.nonSteal, 4),
        FreeThrowAttempt(
          sequence: 5,
          period: 1,
          gameClock: 685,
          shotClock: 9,
          teamId: home.value,
          shooterId: 'p1',
          groupId: 'g',
          attemptIndex: 1,
          attemptsInGroup: 2,
          made: true,
          lastOfGroup: false,
        ),
      ];
      final counts = possessionCounts(events, home);
      expect(counts.estimated, closeTo(1 - 1 + 1 + 0.44, 1e-9));
    });
  });

  group('turnover and shot-clock classification', () {
    test('turnover breakdown contains all four reasons', () {
      final events = <GameEvent>[
        turnover(TurnoverReason.steal, 1),
        turnover(TurnoverReason.nonSteal, 2),
        turnover(TurnoverReason.offensiveFoul, 3),
        turnover(TurnoverReason.shotClock, 4),
        Turnover(
          sequence: 5,
          period: 1,
          gameClock: 100,
          shotClock: 9,
          teamId: away.value,
          playerId: 'p2',
          reason: TurnoverReason.steal,
        ),
      ];
      final breakdown = turnoverBreakdown(events, team: home);
      expect(breakdown.steal, 1);
      expect(breakdown.nonSteal, 1);
      expect(breakdown.offensiveFoul, 1);
      expect(breakdown.shotClock, 1);
      expect(breakdown.total, 4);
    });

    test('shot-clock audit attributes the reset state', () {
      final events = <GameEvent>[
        possession('p1', 1),
        miss(2),
        offenseRebound(3, 2),
        turnover(TurnoverReason.shotClock, 4, clock: 500),
        possessionEnd(PossessionEndReason.turnover, 'p1', 5, clock: 500),
        possession('p2', 6, clock: 400),
        PersonalFoul(
          sequence: 7,
          period: 1,
          gameClock: 400,
          shotClock: 24,
          committingTeamId: away.value,
          committingPlayerId: 'p2',
          kind: FoulKind.nonShooting,
          freeThrowsAwarded: 0,
          bonus: false,
        ),
        turnover(TurnoverReason.shotClock, 8, clock: 200),
      ];
      final audit = shotClockAudit(events);
      expect(audit.entries['start24'], 2);
      expect(audit.entries['oreb14'], 1);
      expect(audit.entries['retainedFoul'], 1);
      expect(audit.turnovers['oreb14'], 1);
      expect(audit.turnovers['retainedFoul'], 1);
      expect(audit.totalTurnovers, 2);
    });
  });

  group('retained-floor distribution', () {
    test('derives the effective floor clock from the foul event', () {
      GameEvent retained(int sequence, int clock, int shotClock) =>
          PersonalFoul(
            sequence: sequence,
            period: 1,
            gameClock: clock,
            shotClock: shotClock,
            committingTeamId: away.value,
            committingPlayerId: 'p2',
            kind: FoulKind.nonShooting,
            freeThrowsAwarded: 0,
            bonus: false,
          );
      final events = <GameEvent>[
        possession('p1', 1, clock: 700),
        retained(2, 700, 18),
        turnover(TurnoverReason.shotClock, 3, clock: 680),
        possession('p2', 4, clock: 600),
        retained(5, 600, 10),
        turnover(TurnoverReason.shotClock, 6, clock: 586),
      ];
      final audit = shotClockAudit(events);
      expect(audit.retainedFloorEntries[18], 1);
      expect(audit.retainedFloorEntries[14], 1);
      expect(audit.retainedFloorTurnovers[18], 1);
      expect(audit.retainedFloorTurnovers[14], 1);
      expect(audit.turnovers['retainedFoul'], 2);
    });
  });

  group('foul audit', () {
    test('flags a bonus award before the threshold', () {
      final events = <GameEvent>[
        PersonalFoul(
          sequence: 1,
          period: 1,
          gameClock: 600,
          shotClock: 24,
          committingTeamId: away.value,
          committingPlayerId: 'p2',
          kind: FoulKind.nonShooting,
          freeThrowsAwarded: 2,
          bonus: true,
        ),
      ];
      final issues = foulAudit(events, GameRules.standard);
      expect(issues, contains('bonus awarded before threshold at seq 1'));
    });

    test('flags a missed shooting foul sharing an FGA timestamp', () {
      final events = <GameEvent>[
        miss(1, clock: 600),
        PersonalFoul(
          sequence: 2,
          period: 1,
          gameClock: 600,
          shotClock: 14,
          committingTeamId: away.value,
          committingPlayerId: 'p2',
          kind: FoulKind.shooting,
          freeThrowsAwarded: 2,
          bonus: false,
        ),
      ];
      final issues = foulAudit(events, GameRules.standard);
      expect(issues, contains('FGA shares missed-shooting-foul timestamp'));
    });
  });

  group('aggregation helpers', () {
    test('stats use type-7 percentiles and sample SD', () {
      final stats = Stats([1, 2, 3, 4]);
      expect(stats.n, 4);
      expect(stats.mean, 2.5);
      expect(stats.median, 2.5);
      expect(stats.standardDeviation, closeTo(1.2909944, 1e-6));
      expect(stats.percentile(0.05), closeTo(1.15, 1e-9));
      expect(stats.percentile(0.95), closeTo(3.85, 1e-9));
      expect(stats.min, 1);
      expect(stats.max, 4);
      expect(quantile([0, 10], 0.5), 5);
    });

    test('band verdicts classify and handle undefined', () {
      expect(bandVerdict(100, 85, 130), 'within');
      expect(bandVerdict(50, 85, 130), 'below');
      expect(bandVerdict(200, 85, 130), 'above');
      expect(bandVerdict(null, 0, 1), 'undefined');
    });

    test('assisted share is undefined without makes', () {
      final events = <GameEvent>[
        miss(1),
        FieldGoalAttempt(
          sequence: 2,
          period: 1,
          gameClock: 680,
          shotClock: 10,
          teamId: home.value,
          shooterId: 'p1',
          shotValue: 2,
          made: true,
          andOne: false,
          assistedById: 'p2',
        ),
        FieldGoalAttempt(
          sequence: 3,
          period: 1,
          gameClock: 670,
          shotClock: 20,
          teamId: home.value,
          shooterId: 'p1',
          shotValue: 3,
          made: true,
          andOne: false,
        ),
      ];
      expect(assistedFgmShare(events, home), closeTo(0.5, 1e-9));
      expect(assistedFgmShare([miss(1)], home), isNull);
    });

    test('analytic A1 overshoot matches the frozen brackets', () {
      expect(singleDrawOvershoot(0), closeTo(1.0, 1e-9));
      expect(singleDrawOvershoot(24), 0);
      expect(singleDrawOvershoot(14), closeTo(8 / 13 * 0.55, 1e-9));
      expect(singleDrawOvershoot(7), closeTo(0.55 + (4 / 7) * 0.30, 1e-9));
    });
  });
}
