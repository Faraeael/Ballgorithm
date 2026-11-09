import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';

GameInput _balancedInput() {
  final base = buildInput(seed: 42);
  TeamRotationPlan planFor(Team team, CourtLineup lineup) {
    final targets = RotationPlan.expandPreset(
      preset: RotationPreset.balanced,
      team: team,
      lineup: lineup,
      rules: base.rules,
    );
    return TeamRotationPlan.create(
      team: team,
      preset: RotationPreset.balanced,
      targets: [
        for (final player in team.players)
          RotationTarget(playerId: player.id, seconds: targets[player.id]!),
      ],
    );
  }

  return GameInput.create(
    gameId: base.gameId,
    league: base.league,
    homeTeamId: base.homeTeamId,
    awayTeamId: base.awayTeamId,
    homeLineup: base.homeLineup,
    awayLineup: base.awayLineup,
    seed: base.seed,
    rules: base.rules,
    rotationPlan: RotationPlan(
      home: planFor(base.homeTeam, base.homeLineup),
      away: planFor(base.awayTeam, base.awayLineup),
    ),
  );
}

void main() {
  test('ledger metrics reconcile scores and expose denominator boundaries', () {
    final result = GameSimulator().simulate(buildInput(seed: 31));
    final metrics = GameMetricsAnalyzer.analyze(result);

    expect(metrics.accountingConsistent, isTrue);
    expect(metrics.ledgerHomePoints, result.homeScore);
    expect(metrics.ledgerAwayPoints, result.awayScore);
    expect(metrics.possessions, result.possessions);
    expect(metrics.teams[result.homeTeamId.value]!.points, result.homeScore);
    expect(metrics.teams[result.awayTeamId.value]!.points, result.awayScore);
    for (final player in metrics.players.values) {
      expect(player.minutes, player.secondsPlayed / 60);
      if (player.secondsPlayed < 240) {
        expect(player.fgaPer36, isNull);
      } else {
        expect(player.fgaPer36, player.fga * 2160 / player.secondsPlayed);
      }
      expect(
        player.primaryFga + player.secondaryFga + player.neutralFga,
        player.fga,
      );
      if (player.fga == 0) expect(player.fieldGoalPercentage, isNull);
      if (player.threePa == 0) expect(player.threePointPercentage, isNull);
    }
    for (final team in metrics.teams.values) {
      expect(
        team.ratingBuckets.values.fold<int>(
          0,
          (sum, bucket) => sum + bucket.fga,
        ),
        team.fga,
      );
      expect(
        team.ratingBuckets.values.fold<int>(
          0,
          (sum, bucket) => sum + bucket.threePa,
        ),
        team.threePa,
      );
      expect(
        team.threePointShare,
        team.fga == 0 ? isNull : team.threePa / team.fga,
      );
      expect(team.primaryFga + team.secondaryFga + team.neutralFga, team.fga);
      if (team.fga == 0) {
        expect(team.primaryShare, isNull);
        expect(team.secondaryShare, isNull);
        expect(team.neutralShare, isNull);
        expect(team.weakShooterThreePointShare, isNull);
        expect(team.stretchBigThreePointShare, isNull);
        expect(
          team.ratingBuckets.values.every(
            (bucket) => bucket.threePointShare == null,
          ),
          isTrue,
        );
      } else {
        expect(
          team.primaryShare! + team.secondaryShare! + team.neutralShare!,
          closeTo(1, 1e-12),
        );
      }
    }
    expect(() => metrics.players.clear(), throwsUnsupportedError);
    expect(
      () => metrics.teams.values.first.ratingBuckets.clear(),
      throwsUnsupportedError,
    );
  });

  test(
    'role counts replay substitutions and occupied slots, not nominal roles',
    () {
      var input = buildInput(seed: 77);
      final homeTeam = input.league.teams.firstWhere(
        (team) => team.id == input.homeTeamId,
      );
      final shifted = [
        ...input.homeLineup.players.skip(1),
        input.homeLineup.players.first,
      ];
      input = GameInput.create(
        gameId: input.gameId,
        league: input.league,
        homeTeamId: input.homeTeamId,
        awayTeamId: input.awayTeamId,
        homeLineup: CourtLineup.create(
          team: homeTeam,
          slotOrderedPlayers: shifted,
        ),
        awayLineup: input.awayLineup,
        seed: input.seed,
        rules: input.rules,
      );
      final home = input.homeLineup.players;
      final bench = homeTeam.players
          .where((player) => !input.homeLineup.containsPlayer(player.id))
          .toList();

      ({Player out, Player incoming, Player shooter})? change;
      for (final outgoing in home) {
        for (final incoming in bench) {
          final replacement = [...home];
          replacement[replacement.indexWhere((p) => p.id == outgoing.id)] =
              incoming;
          final oldRoles = OffensiveRoleRanking.derive(input.homeLineup);
          final newRoles = OffensiveRoleRanking.derive(
            CourtLineup.create(team: homeTeam, slotOrderedPlayers: replacement),
          );
          for (final shooter in home.where(
            (p) =>
                p.id != outgoing.id &&
                p.position != input.homeLineup.slotOf(p.id),
          )) {
            if (oldRoles.roleOf(shooter.id) != newRoles.roleOf(shooter.id)) {
              change = (out: outgoing, incoming: incoming, shooter: shooter);
              break;
            }
          }
          if (change != null) break;
        }
        if (change != null) break;
      }
      expect(change, isNotNull);
      final selected = change!;
      final oldRole = OffensiveRoleRanking.derive(
        input.homeLineup,
      ).roleOf(selected.shooter.id);
      final replacement = [...home];
      replacement[replacement.indexWhere((p) => p.id == selected.out.id)] =
          selected.incoming;
      final newRole = OffensiveRoleRanking.derive(
        CourtLineup.create(team: homeTeam, slotOrderedPlayers: replacement),
      ).roleOf(selected.shooter.id);
      expect(newRole, isNot(oldRole));

      final events = <GameEvent>[
        GameStarted(
          sequence: 1,
          period: 1,
          gameClock: 720,
          shotClock: null,
          homeTeamId: input.homeTeamId.value,
          awayTeamId: input.awayTeamId.value,
          startingTeamId: input.homeTeamId.value,
        ),
        _shot(
          2,
          input.homeTeamId.value,
          selected.shooter.id.value,
          600,
          made: true,
        ),
        Substitution(
          sequence: 3,
          period: 1,
          gameClock: 500,
          shotClock: null,
          teamId: input.homeTeamId.value,
          playerOutId: selected.out.id.value,
          playerInId: selected.incoming.id.value,
          reason: SubstitutionReason.tactical,
        ),
        _shot(4, input.homeTeamId.value, selected.shooter.id.value, 480),
        PeriodEnded(sequence: 5, period: 1, gameClock: 0, shotClock: null),
      ];
      final result = _result(input, events, homePoints: 3);
      final metrics = GameMetricsAnalyzer.analyze(result);
      final playerMetrics = metrics.players[selected.shooter.id.value]!;
      expect(_roleCount(playerMetrics, oldRole), 1);
      expect(_roleCount(playerMetrics, newRole), 1);
      expect(playerMetrics.fga, 2);
      expect(playerMetrics.fgaPer36, 6);
      expect(metrics.accountingConsistent, isTrue);

      final outgoingMetrics = metrics.players[selected.out.id.value]!;
      expect(outgoingMetrics.secondsPlayed, 220);
      expect(outgoingMetrics.fgaPer36, isNull);
      final occupiedSlot = input.homeLineup.slotOf(selected.shooter.id);
      final stretchEligible =
          (occupiedSlot == Position.pf || occupiedSlot == Position.c) &&
          selected.shooter.attributes.threePoint >= 70;
      expect(playerMetrics.stretchBigFga, stretchEligible ? 2 : 0);
      expect(playerMetrics.stretchBigThreePa, stretchEligible ? 2 : 0);
      expect(playerMetrics.stretchBigShare, stretchEligible ? 1 : 0);
      expect(selected.shooter.position, isNot(occupiedSlot));
    },
  );
  test('pinned v7 metrics replay tactical and foul-out role changes', () {
    final input = _balancedInput();
    final result = GameSimulator().simulate(input);
    expect(
      result.events.whereType<Substitution>().any(
        (event) => event.reason == SubstitutionReason.foulOut,
      ),
      isTrue,
    );

    final metrics = GameMetricsAnalyzer.analyze(result);
    expect(metrics.accountingConsistent, isTrue);
    final player = metrics.players['player-1-2']!;
    expect(player.secondaryFga, greaterThan(0));
    expect(player.neutralFga, greaterThan(0));
    for (final team in metrics.teams.values) {
      expect(team.primaryFga + team.secondaryFga + team.neutralFga, team.fga);
    }
  });
}

FieldGoalAttempt _shot(
  int sequence,
  String teamId,
  String shooterId,
  int clock, {
  bool made = false,
}) => FieldGoalAttempt(
  sequence: sequence,
  period: 1,
  gameClock: clock,
  shotClock: 10,
  teamId: teamId,
  shooterId: shooterId,
  shotValue: 3,
  made: made,
  andOne: false,
);

int _roleCount(PlayerGameMetrics metrics, OffensiveRole role) => switch (role) {
  OffensiveRole.primary => metrics.primaryFga,
  OffensiveRole.secondary => metrics.secondaryFga,
  OffensiveRole.neutral => metrics.neutralFga,
};

GameResult _result(
  GameInput input,
  List<GameEvent> events, {
  required int homePoints,
}) {
  final attempts = events.whereType<FieldGoalAttempt>().toList();
  final substitution = events.whereType<Substitution>().single;
  final shooterId = attempts.first.shooterId;
  final playerScores = <String, PlayerBoxScore>{};
  for (final team in [input.homeTeamId, input.awayTeamId]) {
    final model = input.league.teams.firstWhere((t) => t.id == team);
    for (final player in model.players) {
      final isHome = team == input.homeTeamId;
      final secondsPlayed = isHome
          ? player.id.value == substitution.playerOutId
                ? 720 - substitution.gameClock
                : player.id.value == substitution.playerInId
                ? substitution.gameClock
                : input.homeLineup.containsPlayer(player.id)
                ? 720
                : 0
          : input.awayLineup.containsPlayer(player.id)
          ? 720
          : 0;
      final shots = attempts.where((shot) => shot.shooterId == player.id.value);
      final playerFga = shots.length;
      final playerFgm = shots.where((shot) => shot.made).length;
      final playerThreePa = shots.where((shot) => shot.shotValue == 3).length;
      final playerThreePm = shots
          .where((shot) => shot.shotValue == 3 && shot.made)
          .length;
      playerScores[player.id.value] = PlayerBoxScore(
        playerId: player.id.value,
        teamId: team.value,
        points: player.id.value == shooterId ? homePoints : 0,
        fgm: playerFgm,
        fga: playerFga,
        twoPm: 0,
        twoPa: 0,
        threePm: playerThreePm,
        threePa: playerThreePa,
        ftm: 0,
        fta: 0,
        assists: 0,
        oreb: 0,
        dreb: 0,
        rebounds: 0,
        turnovers: 0,
        steals: 0,
        blocks: 0,
        personalFouls: 0,
        secondsPlayed: secondsPlayed,
      );
    }
  }
  final home = TeamBoxScore(
    teamId: input.homeTeamId.value,
    points: homePoints,
    fgm: homePoints > 0 ? 1 : 0,
    fga: 2,
    twoPm: 0,
    twoPa: 0,
    threePm: homePoints > 0 ? 1 : 0,
    threePa: 2,
    ftm: 0,
    fta: 0,
    assists: 0,
    oreb: 0,
    dreb: 0,
    rebounds: 0,
    turnovers: 0,
    steals: 0,
    blocks: 0,
    personalFouls: 0,
  );
  final away = TeamBoxScore(
    teamId: input.awayTeamId.value,
    points: 0,
    fgm: 0,
    fga: 0,
    twoPm: 0,
    twoPa: 0,
    threePm: 0,
    threePa: 0,
    ftm: 0,
    fta: 0,
    assists: 0,
    oreb: 0,
    dreb: 0,
    rebounds: 0,
    turnovers: 0,
    steals: 0,
    blocks: 0,
    personalFouls: 0,
  );
  return GameResult(
    input: input,
    inputFingerprint: 'test',
    ledger: GameEventLedger(
      gameId: input.gameId,
      inputFingerprint: 'test',
      events: events,
    ),
    state: GameState.initial,
    boxScore: GameBoxScore(
      players: playerScores,
      teams: {input.homeTeamId.value: home, input.awayTeamId.value: away},
      periodPoints: {
        input.homeTeamId.value: {1: homePoints},
        input.awayTeamId.value: {1: 0},
      },
    ),
    homeScore: homePoints,
    awayScore: 0,
    periodsPlayed: 1,
    possessions: 0,
    simulationVersion: 1,
    rulesVersion: 1,
    eventSchemaVersion: 1,
    prngImplementationId: 'test',
  );
}
