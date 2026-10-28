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
  final input = buildInput();
  final home = input.homeTeamId;
  final away = input.awayTeamId;
  final homePg = playerAt(input, home, Position.pg);
  final homeSg = playerAt(input, home, Position.sg);
  final homeC = playerAt(input, home, Position.c);
  final awayPg = playerAt(input, away, Position.pg);

  final events = <GameEvent>[
    GameStarted(
      sequence: 1,
      period: 1,
      gameClock: 720,
      shotClock: null,
      homeTeamId: home.value,
      awayTeamId: away.value,
      startingTeamId: input.startingTeamId.value,
    ),
    PeriodStarted(
      sequence: 2,
      period: 1,
      gameClock: 720,
      shotClock: null,
      startingTeamId: input.startingTeamId.value,
    ),
    PossessionStarted(
      sequence: 3,
      period: 1,
      gameClock: 700,
      shotClock: 24,
      possessionId: 'p1',
      offenseTeamId: home.value,
    ),
    FieldGoalAttempt(
      sequence: 4,
      period: 1,
      gameClock: 690,
      shotClock: 14,
      teamId: home.value,
      shooterId: homePg,
      shotValue: 2,
      made: true,
      andOne: false,
      assistedById: homeSg,
    ),
    PossessionEnded(
      sequence: 5,
      period: 1,
      gameClock: 690,
      shotClock: 14,
      possessionId: 'p1',
      offenseTeamId: home.value,
      reason: PossessionEndReason.madeFieldGoal,
    ),
    PossessionStarted(
      sequence: 6,
      period: 1,
      gameClock: 680,
      shotClock: 24,
      possessionId: 'p2',
      offenseTeamId: away.value,
    ),
    FieldGoalAttempt(
      sequence: 7,
      period: 1,
      gameClock: 670,
      shotClock: 14,
      teamId: away.value,
      shooterId: awayPg,
      shotValue: 3,
      made: false,
      andOne: false,
      blockedById: homeC,
    ),
    Rebound(
      sequence: 8,
      period: 1,
      gameClock: 670,
      shotClock: 24,
      teamId: home.value,
      playerId: homeC,
      offensive: false,
      missedEventSequence: 7,
    ),
    PossessionEnded(
      sequence: 9,
      period: 1,
      gameClock: 670,
      shotClock: 24,
      possessionId: 'p2',
      offenseTeamId: away.value,
      reason: PossessionEndReason.defensiveRebound,
    ),
    PossessionStarted(
      sequence: 10,
      period: 1,
      gameClock: 660,
      shotClock: 24,
      possessionId: 'p3',
      offenseTeamId: home.value,
    ),
    Turnover(
      sequence: 11,
      period: 1,
      gameClock: 650,
      shotClock: 14,
      teamId: home.value,
      playerId: homePg,
      reason: TurnoverReason.steal,
      stolenById: awayPg,
    ),
    PossessionEnded(
      sequence: 12,
      period: 1,
      gameClock: 650,
      shotClock: 14,
      possessionId: 'p3',
      offenseTeamId: home.value,
      reason: PossessionEndReason.turnover,
    ),
    PossessionStarted(
      sequence: 13,
      period: 1,
      gameClock: 640,
      shotClock: 24,
      possessionId: 'p4',
      offenseTeamId: away.value,
    ),
    PersonalFoul(
      sequence: 14,
      period: 1,
      gameClock: 630,
      shotClock: 14,
      committingTeamId: home.value,
      committingPlayerId: homePg,
      drawnByPlayerId: awayPg,
      kind: FoulKind.shooting,
      freeThrowsAwarded: 2,
      bonus: false,
    ),
    FreeThrowAttempt(
      sequence: 15,
      period: 1,
      gameClock: 630,
      shotClock: 14,
      teamId: away.value,
      shooterId: awayPg,
      groupId: 'g1',
      attemptIndex: 1,
      attemptsInGroup: 2,
      made: true,
      lastOfGroup: false,
    ),
    FreeThrowAttempt(
      sequence: 16,
      period: 1,
      gameClock: 630,
      shotClock: 14,
      teamId: away.value,
      shooterId: awayPg,
      groupId: 'g1',
      attemptIndex: 2,
      attemptsInGroup: 2,
      made: false,
      lastOfGroup: true,
    ),
    Rebound(
      sequence: 17,
      period: 1,
      gameClock: 630,
      shotClock: 24,
      teamId: home.value,
      playerId: homeC,
      offensive: false,
      missedEventSequence: 16,
    ),
    PossessionEnded(
      sequence: 18,
      period: 1,
      gameClock: 630,
      shotClock: 24,
      possessionId: 'p4',
      offenseTeamId: away.value,
      reason: PossessionEndReason.defensiveRebound,
    ),
  ];

  test('derives player, team and period totals from events', () {
    final score = account(input, events);
    final homeTeam = score.teams[home.value]!;
    final awayTeam = score.teams[away.value]!;
    expect(homeTeam.points, 2);
    expect(awayTeam.points, 1);
    expect(score.periodPoints[home.value]![1], 2);
    expect(score.periodPoints[away.value]![1], 1);

    final pg = score.players[homePg]!;
    expect(pg.points, 2);
    expect(pg.fgm, 1);
    expect(pg.fga, 1);
    expect(pg.twoPm, 1);
    expect(pg.twoPa, 1);
    expect(pg.turnovers, 1);
    expect(pg.personalFouls, 1);

    final sg = score.players[homeSg]!;
    expect(sg.assists, 1);

    final center = score.players[homeC]!;
    expect(center.blocks, 1);
    expect(center.dreb, 2);
    expect(center.rebounds, 2);

    final awayPointGuard = score.players[awayPg]!;
    expect(awayPointGuard.threePa, 1);
    expect(awayPointGuard.steals, 1);
    expect(awayPointGuard.ftm, 1);
    expect(awayPointGuard.fta, 2);
    expect(awayPointGuard.points, 1);
  });

  test('team totals reconcile with player totals and equations', () {
    final score = account(input, events);
    for (final team in score.teams.values) {
      final players = score.players.values.where(
        (p) => p.teamId == team.teamId,
      );
      int sum(int Function(PlayerBoxScore) field) =>
          players.fold<int>(0, (total, player) => total + field(player));
      expect(team.points, sum((p) => p.points));
      expect(team.fgm, sum((p) => p.fgm));
      expect(team.fga, sum((p) => p.fga));
      expect(team.ftm, sum((p) => p.ftm));
      expect(team.fta, sum((p) => p.fta));
      expect(team.rebounds, sum((p) => p.rebounds));
      expect(team.turnovers, sum((p) => p.turnovers));
      expect(team.personalFouls, sum((p) => p.personalFouls));
      expect(team.rebounds, team.oreb + team.dreb);
      expect(team.fgm, team.twoPm + team.threePm);
      expect(team.fga, team.twoPa + team.threePa);
      expect(team.points, team.twoPm * 2 + team.threePm * 3 + team.ftm);
    }
  });

  test('rejects an unresolved live miss', () {
    expect(
      () => account(input, events.take(7).toList()),
      throwsCode(GameValidationCode.deadBallInvalid),
    );
  });

  test('rejects rebounds and dead-ball misses with no recorded miss', () {
    final broken = [...events];
    broken.add(
      Rebound(
        sequence: 19,
        period: 1,
        gameClock: 620,
        shotClock: 24,
        teamId: home.value,
        playerId: homeC,
        offensive: false,
        missedEventSequence: 999,
      ),
    );
    expect(
      () => account(input, broken),
      throwsCode(GameValidationCode.reboundInvalid),
    );
  });

  test('attributes offensive-foul turnovers to the offending player', () {
    final offensive = <GameEvent>[
      ...events.take(3),
      PersonalFoul(
        sequence: 4,
        period: 1,
        gameClock: 690,
        shotClock: 14,
        committingTeamId: home.value,
        committingPlayerId: homePg,
        kind: FoulKind.offensive,
        freeThrowsAwarded: 0,
        bonus: false,
      ),
      Turnover(
        sequence: 5,
        period: 1,
        gameClock: 690,
        shotClock: 14,
        teamId: home.value,
        playerId: homePg,
        reason: TurnoverReason.offensiveFoul,
      ),
      PossessionEnded(
        sequence: 6,
        period: 1,
        gameClock: 690,
        shotClock: 14,
        possessionId: 'p1',
        offenseTeamId: home.value,
        reason: PossessionEndReason.turnover,
      ),
    ];
    final score = account(input, offensive);
    expect(score.players[homePg]!.turnovers, 1);
    expect(score.players[homePg]!.personalFouls, 1);
    expect(score.teams[home.value]!.turnovers, 1);
    expect(score.teams[home.value]!.points, 0);
  });

  test('rejects orphan free throws before producing totals', () {
    final orphan = <GameEvent>[
      ...events.take(2),
      PossessionStarted(
        sequence: 3,
        period: 1,
        gameClock: 24,
        shotClock: 24,
        possessionId: 'orphan',
        offenseTeamId: home.value,
      ),
      FreeThrowAttempt(
        sequence: 4,
        period: 1,
        gameClock: 24,
        shotClock: 24,
        teamId: home.value,
        shooterId: homePg,
        groupId: 'g1',
        attemptIndex: 1,
        attemptsInGroup: 1,
        made: true,
        lastOfGroup: true,
      ),
      PossessionEnded(
        sequence: 5,
        period: 1,
        gameClock: 24,
        shotClock: 24,
        possessionId: 'orphan',
        offenseTeamId: home.value,
        reason: PossessionEndReason.madeFinalFreeThrow,
      ),
    ];
    expect(
      () => account(input, orphan),
      throwsCode(GameValidationCode.freeThrowSequenceInvalid),
    );
  });

  test('counts an and-one as FGA/FGM plus one FT', () {
    final andOne = <GameEvent>[
      ...events.take(2),
      PossessionStarted(
        sequence: 3,
        period: 1,
        gameClock: 700,
        shotClock: 24,
        possessionId: 'a1',
        offenseTeamId: home.value,
      ),
      FieldGoalAttempt(
        sequence: 4,
        period: 1,
        gameClock: 690,
        shotClock: 14,
        teamId: home.value,
        shooterId: homePg,
        shotValue: 3,
        made: true,
        andOne: true,
      ),
      PersonalFoul(
        sequence: 5,
        period: 1,
        gameClock: 690,
        shotClock: 14,
        committingTeamId: away.value,
        committingPlayerId: awayPg,
        drawnByPlayerId: homePg,
        kind: FoulKind.shooting,
        freeThrowsAwarded: 1,
        bonus: false,
      ),
      FreeThrowAttempt(
        sequence: 6,
        period: 1,
        gameClock: 690,
        shotClock: 14,
        teamId: home.value,
        shooterId: homePg,
        groupId: 'a1',
        attemptIndex: 1,
        attemptsInGroup: 1,
        made: true,
        lastOfGroup: true,
      ),
      PossessionEnded(
        sequence: 7,
        period: 1,
        gameClock: 690,
        shotClock: 14,
        possessionId: 'a1',
        offenseTeamId: home.value,
        reason: PossessionEndReason.madeFinalFreeThrow,
      ),
    ];
    final score = account(input, andOne);
    expect(score.players[homePg]!.fga, 1);
    expect(score.players[homePg]!.fgm, 1);
    expect(score.players[homePg]!.threePm, 1);
    expect(score.players[homePg]!.ftm, 1);
    expect(score.players[homePg]!.points, 4);
    expect(score.teams[home.value]!.points, 4);
  });
}
