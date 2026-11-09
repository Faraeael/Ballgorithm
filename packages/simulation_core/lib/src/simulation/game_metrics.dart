import '../models/ids.dart';
import '../models/player.dart';
import '../models/position.dart';
import '../models/team.dart';
import 'court_lineup.dart';
import 'game_event.dart';
import 'game_result.dart';
import 'offensive_role.dart';

/// Immutable ledger-derived shooting and accounting metrics for one game.
///
/// Rates are ratios, not percentages. Nullable rates are undefined when their
/// denominator is zero or exposure fails the minimum threshold.
final class GameMetrics {
  GameMetrics({
    required Map<String, PlayerGameMetrics> players,
    required Map<String, TeamGameMetrics> teams,
    required this.possessions,
    required this.accountingConsistent,
    required this.ledgerHomePoints,
    required this.ledgerAwayPoints,
  }) : players = Map.unmodifiable(players),
       teams = Map.unmodifiable(teams);

  final Map<String, PlayerGameMetrics> players;
  final Map<String, TeamGameMetrics> teams;
  final int possessions;
  final bool accountingConsistent;
  final int ledgerHomePoints;
  final int ledgerAwayPoints;
}

final class PlayerGameMetrics {
  const PlayerGameMetrics({
    required this.playerId,
    required this.teamId,
    required this.points,
    required this.fgm,
    required this.fga,
    required this.threePm,
    required this.threePa,
    required this.fieldGoalPercentage,
    required this.threePointPercentage,
    required this.secondsPlayed,
    required this.minutes,
    required this.fgaPer36,
    required this.primaryFga,
    required this.secondaryFga,
    required this.neutralFga,
    required this.primaryShare,
    required this.secondaryShare,
    required this.neutralShare,
    required this.stretchBigFga,
    required this.stretchBigThreePa,
    required this.stretchBigShare,
  });

  final String playerId;
  final String teamId;
  final int points;
  final int fgm;
  final int fga;
  final int threePm;
  final int threePa;
  final double? fieldGoalPercentage;
  final double? threePointPercentage;
  final int secondsPlayed;
  final double minutes;
  final double? fgaPer36;
  final int primaryFga;
  final int secondaryFga;
  final int neutralFga;
  final double? primaryShare;
  final double? secondaryShare;
  final double? neutralShare;
  final int stretchBigFga;
  final int stretchBigThreePa;
  final double? stretchBigShare;
}

/// Pooled shot-rate bucket; percentages remain null without attempts.
final class ShootingBucketMetrics {
  const ShootingBucketMetrics({
    required this.fga,
    required this.threePa,
    required this.threePointShare,
  });

  final int fga;
  final int threePa;
  final double? threePointShare;
}

final class TeamGameMetrics {
  TeamGameMetrics({
    required this.teamId,
    required this.points,
    required this.fgm,
    required this.fga,
    required this.threePm,
    required this.threePa,
    required this.fta,
    required this.turnovers,
    required this.possessions,
    required this.effectiveFieldGoalPercentage,
    required this.turnoversPer100Possessions,
    required this.primaryFga,
    required this.secondaryFga,
    required this.neutralFga,
    required this.primaryShare,
    required this.secondaryShare,
    required this.neutralShare,
    required this.threePointShare,
    required this.weakShooterFga,
    required this.weakShooterThreePa,
    required this.weakShooterThreePointShare,
    required this.stretchBigFga,
    required this.stretchBigThreePa,
    required this.stretchBigThreePointShare,
    required this.weakShooters,
    required this.stretchBigs,
    required Map<String, ShootingBucketMetrics> ratingBuckets,
  }) : ratingBuckets = Map.unmodifiable(ratingBuckets);

  final String teamId;
  final int points;
  final int fgm;
  final int fga;
  final int threePm;
  final int threePa;
  final int fta;
  final int turnovers;
  final int possessions;
  final double? effectiveFieldGoalPercentage;
  final double? turnoversPer100Possessions;
  final int primaryFga;
  final int secondaryFga;
  final int neutralFga;
  final double? primaryShare;
  final double? secondaryShare;
  final double? neutralShare;
  final double? threePointShare;
  final int weakShooterFga;
  final int weakShooterThreePa;
  final double? weakShooterThreePointShare;
  final int stretchBigFga;
  final int stretchBigThreePa;
  final double? stretchBigThreePointShare;
  final ShootingBucketMetrics weakShooters;
  final ShootingBucketMetrics stretchBigs;
  final Map<String, ShootingBucketMetrics> ratingBuckets;
}

abstract final class GameMetricsAnalyzer {
  /// Analyzes a validated result without changing its ledger or box score.
  static GameMetrics analyze(GameResult result) {
    final playerById = <String, Player>{};
    final players = <String, _PlayerAccumulator>{};
    final teamAcc = <String, _TeamAccumulator>{};
    for (final team in [result.input.homeTeamId, result.input.awayTeamId]) {
      final model = _team(result, team);
      teamAcc[team.value] = _TeamAccumulator(team.value);
      for (final player in model.players) {
        playerById[player.id.value] = player;
        players[player.id.value] = _PlayerAccumulator(
          player.id.value,
          team.value,
        );
      }
    }

    final active = <String, CourtLineup>{
      result.homeTeamId.value: result.input.homeLineup,
      result.awayTeamId.value: result.input.awayLineup,
    };

    final activeRoles = <String, OffensiveRoleAssignment>{
      result.homeTeamId.value: OffensiveRoleRanking.derive(
        result.input.homeLineup,
      ),
      result.awayTeamId.value: OffensiveRoleRanking.derive(
        result.input.awayLineup,
      ),
    };
    var ledgerHomePoints = 0;
    var ledgerAwayPoints = 0;
    var currentPeriod = 0;
    var lastClock = 0;
    void accrue(int delta) {
      for (final lineup in active.values) {
        for (final player in lineup.players) {
          players[player.id.value]!.secondsPlayed += delta;
        }
      }
    }

    for (final event in result.ledger.events) {
      if (event is GameStarted || event is PeriodStarted) {
        currentPeriod = event.period;
        lastClock = event.gameClock;
      } else if (event is PeriodEnded) {
        accrue(lastClock);
        lastClock = 0;
      } else if (event.period == currentPeriod) {
        accrue(lastClock - event.gameClock);
        lastClock = event.gameClock;
      }

      if (event is Substitution) {
        final lineup = active[event.teamId]!;
        final slots = lineup.players;
        final index = lineup.slotIndexForPlayer(PlayerId(event.playerOutId));
        slots[index] = playerById[event.playerInId]!;
        final updated = CourtLineup.create(
          team: _team(result, TeamId(event.teamId)),
          slotOrderedPlayers: slots,
        );
        active[event.teamId] = updated;
        activeRoles[event.teamId] = OffensiveRoleRanking.derive(updated);
      } else if (event is FieldGoalAttempt) {
        final player = playerById[event.shooterId]!;
        final metric = players[event.shooterId]!;
        final team = teamAcc[event.teamId]!;
        metric.fga++;
        team.fga++;
        if (event.made) {
          metric.fgm++;
          metric.points += event.shotValue;
          team.fgm++;
          team.points += event.shotValue;
          if (event.teamId == result.homeTeamId.value) {
            ledgerHomePoints += event.shotValue;
          } else {
            ledgerAwayPoints += event.shotValue;
          }
        }
        if (event.shotValue == 3) {
          metric.threePa++;
          team.threePa++;
          if (event.made) {
            metric.threePm++;
            team.threePm++;
          }
        }
        final lineup = active[event.teamId]!;
        switch (activeRoles[event.teamId]!.roleOf(player.id)) {
          case OffensiveRole.primary:
            metric.primaryFga++;
            team.primaryFga++;
            break;
          case OffensiveRole.secondary:
            metric.secondaryFga++;
            team.secondaryFga++;
            break;
          case OffensiveRole.neutral:
            metric.neutralFga++;
            team.neutralFga++;
            break;
        }
        final occupiedPosition = lineup.slotOf(player.id);
        if ((occupiedPosition == Position.pf ||
                occupiedPosition == Position.c) &&
            player.attributes.threePoint >= 70) {
          metric.stretchBigFga++;
          team.stretchBigFga++;
          if (event.shotValue == 3) {
            metric.stretchBigThreePa++;
            team.stretchBigThreePa++;
          }
        }
        final bucket = switch (player.attributes.threePoint) {
          < 40 => '<40',
          < 70 => '40..69',
          _ => '>=70',
        };
        final bucketCounts = team.ratingBuckets[bucket]!;
        bucketCounts.fga++;
        if (event.shotValue == 3) bucketCounts.threePa++;
      } else if (event is FreeThrowAttempt) {
        final team = teamAcc[event.teamId]!;
        team.fta++;
        if (event.made) {
          players[event.shooterId]!.points++;
          team.points++;
          if (event.teamId == result.homeTeamId.value) {
            ledgerHomePoints++;
          } else {
            ledgerAwayPoints++;
          }
        }
      } else if (event is Turnover) {
        teamAcc[event.teamId]!.turnovers++;
      } else if (event is PossessionStarted) {
        teamAcc[event.offenseTeamId]!.possessions++;
      }
    }

    final playerMetrics = <String, PlayerGameMetrics>{};
    final possessionCount = teamAcc.values.fold<int>(
      0,
      (sum, team) => sum + team.possessions,
    );
    var consistent =
        ledgerHomePoints == result.homeScore &&
        ledgerAwayPoints == result.awayScore &&
        possessionCount == result.possessions;
    for (final entry in players.entries) {
      final p = entry.value;
      final box = result.boxScore.players[entry.key];
      consistent =
          consistent &&
          box != null &&
          box.points == p.points &&
          box.fgm == p.fgm &&
          box.fga == p.fga &&
          box.threePm == p.threePm &&
          box.threePa == p.threePa &&
          box.secondsPlayed == p.secondsPlayed;
      playerMetrics[entry.key] = PlayerGameMetrics(
        playerId: p.playerId,
        teamId: p.teamId,
        points: p.points,
        fgm: p.fgm,
        fga: p.fga,
        threePm: p.threePm,
        threePa: p.threePa,
        fieldGoalPercentage: _share(p.fgm, p.fga),
        threePointPercentage: _share(p.threePm, p.threePa),
        secondsPlayed: p.secondsPlayed,
        minutes: p.secondsPlayed / 60,
        fgaPer36: p.secondsPlayed < 240 ? null : p.fga * 2160 / p.secondsPlayed,
        primaryFga: p.primaryFga,
        secondaryFga: p.secondaryFga,
        neutralFga: p.neutralFga,
        primaryShare: _share(p.primaryFga, p.fga),
        secondaryShare: _share(p.secondaryFga, p.fga),
        neutralShare: _share(p.neutralFga, p.fga),
        stretchBigFga: p.stretchBigFga,
        stretchBigThreePa: p.stretchBigThreePa,
        stretchBigShare: _share(p.stretchBigFga, p.fga),
      );
    }
    final teamMetrics = <String, TeamGameMetrics>{};
    for (final entry in teamAcc.entries) {
      final t = entry.value;
      final box = result.boxScore.teams[entry.key];
      consistent =
          consistent &&
          box != null &&
          box.points == t.points &&
          box.fgm == t.fgm &&
          box.fga == t.fga &&
          box.threePm == t.threePm &&
          box.threePa == t.threePa &&
          box.fta == t.fta &&
          box.turnovers == t.turnovers &&
          t.primaryFga + t.secondaryFga + t.neutralFga == t.fga &&
          t.ratingBuckets.values.fold<int>(
                0,
                (sum, bucket) => sum + bucket.fga,
              ) ==
              t.fga &&
          t.ratingBuckets.values.fold<int>(
                0,
                (sum, bucket) => sum + bucket.threePa,
              ) ==
              t.threePa;
      final weakCounts = t.ratingBuckets['<40']!;
      final weak = ShootingBucketMetrics(
        fga: weakCounts.fga,
        threePa: weakCounts.threePa,
        threePointShare: _share(weakCounts.threePa, weakCounts.fga),
      );
      final stretch = ShootingBucketMetrics(
        fga: t.stretchBigFga,
        threePa: t.stretchBigThreePa,
        threePointShare: _share(t.stretchBigThreePa, t.stretchBigFga),
      );
      final ratingBuckets = <String, ShootingBucketMetrics>{
        for (final entry in t.ratingBuckets.entries)
          entry.key: ShootingBucketMetrics(
            fga: entry.value.fga,
            threePa: entry.value.threePa,
            threePointShare: _share(entry.value.threePa, entry.value.fga),
          ),
      };
      teamMetrics[entry.key] = TeamGameMetrics(
        teamId: t.teamId,
        points: t.points,
        fgm: t.fgm,
        fga: t.fga,
        threePm: t.threePm,
        threePa: t.threePa,
        fta: t.fta,
        turnovers: t.turnovers,
        possessions: t.possessions,
        primaryFga: t.primaryFga,
        secondaryFga: t.secondaryFga,
        neutralFga: t.neutralFga,
        primaryShare: _share(t.primaryFga, t.fga),
        secondaryShare: _share(t.secondaryFga, t.fga),
        neutralShare: _share(t.neutralFga, t.fga),
        effectiveFieldGoalPercentage: t.fga == 0
            ? null
            : (t.fgm + .5 * t.threePm) / t.fga,
        turnoversPer100Possessions: t.possessions == 0
            ? null
            : t.turnovers * 100 / t.possessions,
        threePointShare: _share(t.threePa, t.fga),
        weakShooterFga: weak.fga,
        weakShooterThreePa: weak.threePa,
        weakShooterThreePointShare: weak.threePointShare,
        stretchBigFga: t.stretchBigFga,
        stretchBigThreePa: t.stretchBigThreePa,
        stretchBigThreePointShare: stretch.threePointShare,
        weakShooters: weak,
        stretchBigs: stretch,
        ratingBuckets: ratingBuckets,
      );
    }
    return GameMetrics(
      players: playerMetrics,
      teams: teamMetrics,
      possessions: result.possessions,
      accountingConsistent: consistent,
      ledgerHomePoints: ledgerHomePoints,
      ledgerAwayPoints: ledgerAwayPoints,
    );
  }

  static Team _team(GameResult result, TeamId id) =>
      result.input.league.teams.firstWhere((team) => team.id == id);

  static double? _share(int numerator, int denominator) =>
      denominator == 0 ? null : numerator / denominator;
}

final class _PlayerAccumulator {
  _PlayerAccumulator(this.playerId, this.teamId);
  final String playerId;
  final String teamId;
  int points = 0, fgm = 0, fga = 0, threePm = 0, threePa = 0;
  int secondsPlayed = 0, primaryFga = 0, secondaryFga = 0, neutralFga = 0;
  int stretchBigFga = 0, stretchBigThreePa = 0;
}

final class _TeamAccumulator {
  _TeamAccumulator(this.teamId);
  final String teamId;
  int points = 0, fgm = 0, fga = 0, threePm = 0, threePa = 0;
  int primaryFga = 0, secondaryFga = 0, neutralFga = 0;
  int fta = 0, turnovers = 0, possessions = 0;
  final Map<String, _BucketAccumulator> ratingBuckets = {
    '<40': _BucketAccumulator(),
    '40..69': _BucketAccumulator(),
    '>=70': _BucketAccumulator(),
  };
  int stretchBigFga = 0, stretchBigThreePa = 0;
}

final class _BucketAccumulator {
  int fga = 0;
  int threePa = 0;
}
