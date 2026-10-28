import '../models/ids.dart';
import 'box_score.dart';
import 'game_event.dart';
import 'game_input.dart';
import 'game_reducer.dart';
import 'game_validation.dart';

/// The only authoritative derivation of M002 statistics from events.
abstract final class EventAccounting {
  static GameBoxScore aggregate(ValidatedGameLedger ledger) {
    final input = ledger.input;
    final events = ledger.events;
    final accumulators = <String, _PlayerAccumulator>{};
    for (final teamId in [input.homeTeamId.value, input.awayTeamId.value]) {
      final lineup = input.lineupFor(TeamId(teamId));
      for (final player in lineup.players) {
        accumulators[player.id.value] = _PlayerAccumulator(
          playerId: player.id.value,
          teamId: teamId,
        );
      }
    }

    final periodPoints = <String, Map<int, int>>{
      input.homeTeamId.value: <int, int>{},
      input.awayTeamId.value: <int, int>{},
    };
    final missValues = <int, int>{};

    void addPoints(String teamId, int period, int points) {
      final map = periodPoints[teamId]!;
      map[period] = (map[period] ?? 0) + points;
    }

    for (final event in events) {
      if (event is FieldGoalAttempt) {
        final player = _player(
          input,
          accumulators,
          event.teamId,
          event.shooterId,
        );
        player.fga++;
        if (event.shotValue == 2) {
          player.twoPa++;
        } else if (event.shotValue == 3) {
          player.threePa++;
        } else {
          _fail(
            GameValidationCode.malformedEventJson,
            'event ${event.sequence}',
            'invalid shot value ${event.shotValue}',
          );
        }
        if (event.made) {
          player.fgm++;
          if (event.shotValue == 2) {
            player.twoPm++;
          } else {
            player.threePm++;
          }
          player.points += event.shotValue;
          addPoints(event.teamId, event.period, event.shotValue);
          if (event.assistedById != null) {
            final passer = _player(
              input,
              accumulators,
              event.teamId,
              event.assistedById!,
            );
            passer.assists++;
          }
        } else {
          missValues[event.sequence] = event.shotValue;
          if (event.blockedById != null) {
            final blocker = _player(
              input,
              accumulators,
              input.opponentOf(TeamId(event.teamId)).value,
              event.blockedById!,
            );
            blocker.blocks++;
          }
        }
      } else if (event is FreeThrowAttempt) {
        final shooter = _player(
          input,
          accumulators,
          event.teamId,
          event.shooterId,
        );
        shooter.fta++;
        if (event.made) {
          shooter.ftm++;
          shooter.points++;
          addPoints(event.teamId, event.period, 1);
        } else if (event.lastOfGroup) {
          missValues[event.sequence] = 1;
        }
      } else if (event is Rebound) {
        final rebounder = _player(
          input,
          accumulators,
          event.teamId,
          event.playerId,
        );
        if (event.offensive) {
          rebounder.oreb++;
        } else {
          rebounder.dreb++;
        }
        rebounder.rebounds++;
        if (!missValues.containsKey(event.missedEventSequence)) {
          _fail(
            GameValidationCode.reboundInvalid,
            'event ${event.sequence}',
            'rebound does not link to a recorded miss',
          );
        }
        missValues.remove(event.missedEventSequence);
      } else if (event is DeadBallMiss) {
        if (!missValues.containsKey(event.missedEventSequence)) {
          _fail(
            GameValidationCode.deadBallInvalid,
            'event ${event.sequence}',
            'dead-ball miss does not link to a recorded miss',
          );
        }
        missValues.remove(event.missedEventSequence);
      } else if (event is Turnover) {
        final player = _player(
          input,
          accumulators,
          event.teamId,
          event.playerId,
        );
        player.turnovers++;
        if (event.stolenById != null) {
          final thief = _player(
            input,
            accumulators,
            input.opponentOf(TeamId(event.teamId)).value,
            event.stolenById!,
          );
          thief.steals++;
        }
      } else if (event is PersonalFoul) {
        final player = _player(
          input,
          accumulators,
          event.committingTeamId,
          event.committingPlayerId,
        );
        player.personalFouls++;
      }
    }

    if (missValues.isNotEmpty) {
      _fail(
        GameValidationCode.deadBallInvalid,
        'events',
        'live misses remain unresolved: ${missValues.keys.join(', ')}',
      );
    }

    final players = <String, PlayerBoxScore>{
      for (final entry in accumulators.entries) entry.key: entry.value.freeze(),
    };
    final teams = <String, TeamBoxScore>{};
    for (final teamId in [input.homeTeamId.value, input.awayTeamId.value]) {
      teams[teamId] = _teamTotals(teamId, players.values);
    }

    for (final teamId in teams.keys) {
      final team = teams[teamId]!;
      final playerPoints = players.values
          .where((player) => player.teamId == teamId)
          .fold<int>(0, (sum, player) => sum + player.points);
      final periodTotal = periodPoints[teamId]!.values.fold<int>(
        0,
        (a, b) => a + b,
      );
      if (team.points != playerPoints || team.points != periodTotal) {
        _fail(
          GameValidationCode.periodEndInvalid,
          'boxScore.$teamId',
          'team points do not reconcile with players and periods',
        );
      }
    }

    return GameBoxScore(
      players: players,
      teams: teams,
      periodPoints: periodPoints,
    );
  }

  static _PlayerAccumulator _player(
    GameInput input,
    Map<String, _PlayerAccumulator> accumulators,
    String teamId,
    String playerId,
  ) {
    final player = accumulators[playerId];
    if (player == null || player.teamId != teamId) {
      _fail(
        GameValidationCode.playerNotActive,
        'events',
        'player $playerId is not credited to team $teamId',
      );
    }
    return player;
  }

  static TeamBoxScore _teamTotals(
    String teamId,
    Iterable<PlayerBoxScore> players,
  ) {
    var points = 0;
    var fgm = 0;
    var fga = 0;
    var twoPm = 0;
    var twoPa = 0;
    var threePm = 0;
    var threePa = 0;
    var ftm = 0;
    var fta = 0;
    var assists = 0;
    var oreb = 0;
    var dreb = 0;
    var rebounds = 0;
    var turnovers = 0;
    var steals = 0;
    var blocks = 0;
    var personalFouls = 0;
    for (final player in players) {
      if (player.teamId != teamId) continue;
      points += player.points;
      fgm += player.fgm;
      fga += player.fga;
      twoPm += player.twoPm;
      twoPa += player.twoPa;
      threePm += player.threePm;
      threePa += player.threePa;
      ftm += player.ftm;
      fta += player.fta;
      assists += player.assists;
      oreb += player.oreb;
      dreb += player.dreb;
      rebounds += player.rebounds;
      turnovers += player.turnovers;
      steals += player.steals;
      blocks += player.blocks;
      personalFouls += player.personalFouls;
    }
    if (rebounds != oreb + dreb ||
        fgm != twoPm + threePm ||
        fga != twoPa + threePa) {
      _fail(
        GameValidationCode.periodEndInvalid,
        'boxScore.$teamId',
        'team box-score equations do not reconcile',
      );
    }
    return TeamBoxScore(
      teamId: teamId,
      points: points,
      fgm: fgm,
      fga: fga,
      twoPm: twoPm,
      twoPa: twoPa,
      threePm: threePm,
      threePa: threePa,
      ftm: ftm,
      fta: fta,
      assists: assists,
      oreb: oreb,
      dreb: dreb,
      rebounds: rebounds,
      turnovers: turnovers,
      steals: steals,
      blocks: blocks,
      personalFouls: personalFouls,
    );
  }
}

final class _PlayerAccumulator {
  _PlayerAccumulator({required this.playerId, required this.teamId});

  final String playerId;
  final String teamId;
  int points = 0;
  int fgm = 0;
  int fga = 0;
  int twoPm = 0;
  int twoPa = 0;
  int threePm = 0;
  int threePa = 0;
  int ftm = 0;
  int fta = 0;
  int assists = 0;
  int oreb = 0;
  int dreb = 0;
  int rebounds = 0;
  int turnovers = 0;
  int steals = 0;
  int blocks = 0;
  int personalFouls = 0;

  PlayerBoxScore freeze() => PlayerBoxScore(
    playerId: playerId,
    teamId: teamId,
    points: points,
    fgm: fgm,
    fga: fga,
    twoPm: twoPm,
    twoPa: twoPa,
    threePm: threePm,
    threePa: threePa,
    ftm: ftm,
    fta: fta,
    assists: assists,
    oreb: oreb,
    dreb: dreb,
    rebounds: rebounds,
    turnovers: turnovers,
    steals: steals,
    blocks: blocks,
    personalFouls: personalFouls,
  );
}

Never _fail(GameValidationCode code, String path, String message) {
  throw GameValidationException([
    GameValidationIssue(code: code, path: path, message: message),
  ]);
}
