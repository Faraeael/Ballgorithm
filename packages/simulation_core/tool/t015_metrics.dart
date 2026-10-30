/// T015 calibration metrics: pure functions over the published event ledger.
///
/// No second scoreboard: team/player statistics come from `EventAccounting`;
/// these helpers only count event-derived calibration quantities and aggregate
/// them. Deterministic, integer or double arithmetic only.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';

final class PossessionCounts {
  const PossessionCounts({
    required this.started,
    required this.completed,
    required this.periodEnd,
    required this.orebContinuations,
    required this.estimated,
  });

  final int started;
  final int completed;
  final int periodEnd;
  final int orebContinuations;
  final double estimated;

  int get totalClosures => completed + periodEnd;
}

PossessionCounts possessionCounts(List<GameEvent> events, TeamId team) {
  var started = 0;
  var completed = 0;
  var periodEnd = 0;
  var oreb = 0;
  var fga = 0;
  var tov = 0;
  var fta = 0;
  for (final event in events) {
    if (event is PossessionStarted && event.offenseTeamId == team.value) {
      started++;
    } else if (event is PossessionEnded && event.offenseTeamId == team.value) {
      switch (event.reason) {
        case PossessionEndReason.periodEnd:
          periodEnd++;
        case PossessionEndReason.turnover:
        case PossessionEndReason.madeFieldGoal:
        case PossessionEndReason.madeFinalFreeThrow:
        case PossessionEndReason.defensiveRebound:
          completed++;
      }
    } else if (event is Rebound &&
        event.teamId == team.value &&
        event.offensive) {
      oreb++;
    } else if (event is FieldGoalAttempt && event.teamId == team.value) {
      fga++;
    } else if (event is Turnover && event.teamId == team.value) {
      tov++;
    } else if (event is FreeThrowAttempt && event.teamId == team.value) {
      fta++;
    }
  }
  final estimated = fga - oreb + tov + 0.44 * fta;
  return PossessionCounts(
    started: started,
    completed: completed,
    periodEnd: periodEnd,
    orebContinuations: oreb,
    estimated: estimated,
  );
}

final class TurnoverBreakdown {
  const TurnoverBreakdown({
    this.steal = 0,
    this.nonSteal = 0,
    this.offensiveFoul = 0,
    this.shotClock = 0,
  });

  final int steal;
  final int nonSteal;
  final int offensiveFoul;
  final int shotClock;

  int get total => steal + nonSteal + offensiveFoul + shotClock;

  Map<String, int> toMap() => {
    'steal': steal,
    'nonSteal': nonSteal,
    'offensiveFoul': offensiveFoul,
    'shotClock': shotClock,
  };
}

TurnoverBreakdown turnoverBreakdown(List<GameEvent> events, {TeamId? team}) {
  var steal = 0;
  var nonSteal = 0;
  var offensiveFoul = 0;
  var shotClock = 0;
  for (final event in events) {
    if (event is! Turnover) continue;
    if (team != null && event.teamId != team.value) continue;
    switch (event.reason) {
      case TurnoverReason.steal:
        steal++;
      case TurnoverReason.nonSteal:
        nonSteal++;
      case TurnoverReason.offensiveFoul:
        offensiveFoul++;
      case TurnoverReason.shotClock:
        shotClock++;
    }
  }
  return TurnoverBreakdown(
    steal: steal,
    nonSteal: nonSteal,
    offensiveFoul: offensiveFoul,
    shotClock: shotClock,
  );
}

/// Shot-clock reset states, keyed by how the current possession's clock was set.
final class ShotClockAudit {
  ShotClockAudit()
    : entries = {'start24': 0, 'oreb14': 0, 'retainedFoul': 0},
      turnovers = {'start24': 0, 'oreb14': 0, 'retainedFoul': 0, 'other': 0};

  final Map<String, int> entries;
  final Map<String, int> turnovers;

  /// Retained-possession phases keyed by the effective floor clock (14..24).
  final Map<int, int> retainedFloorEntries = {};
  final Map<int, int> retainedFloorTurnovers = {};

  int get totalTurnovers => turnovers.values.fold(0, (a, b) => a + b);
}

/// Shot-clock reset classification.
///
/// `rules` supplies the retained-foul floor and shot-clock cap; when omitted the
/// standard values (14 s floor, 24 s cap) are used. The floor is derived from the
/// foul event's own shot clock, so the distribution is measured, not assumed.
ShotClockAudit shotClockAudit(List<GameEvent> events, {GameRules? rules}) {
  final audit = ShotClockAudit();
  final config = rules ?? GameRules.standard;
  final floor = config.nonBonusFoulResetFloorSeconds;
  final cap = config.shotClockSeconds;
  String? state;
  int? retainedFloor;
  void enter(String name) {
    state = name;
    audit.entries[name] = audit.entries[name]! + 1;
  }

  for (final event in events) {
    if (event is PossessionStarted) {
      enter('start24');
      retainedFloor = null;
    } else if (event is Rebound && event.offensive) {
      enter('oreb14');
      retainedFloor = null;
    } else if (event is PersonalFoul &&
        event.kind == FoulKind.nonShooting &&
        event.freeThrowsAwarded == 0) {
      final previous = event.shotClock ?? floor;
      final effective = previous > floor ? previous : floor;
      retainedFloor = effective > cap ? cap : effective;
      enter('retainedFoul');
      audit.retainedFloorEntries[retainedFloor] =
          (audit.retainedFloorEntries[retainedFloor] ?? 0) + 1;
    } else if (event is Turnover) {
      if (event.reason == TurnoverReason.shotClock) {
        final key = state ?? 'other';
        audit.turnovers[key] = (audit.turnovers[key] ?? 0) + 1;
        if (key == 'retainedFoul' && retainedFloor != null) {
          audit.retainedFloorTurnovers[retainedFloor] =
              (audit.retainedFloorTurnovers[retainedFloor] ?? 0) + 1;
        }
      }
    } else if (event is PossessionEnded) {
      state = null;
      retainedFloor = null;
    }
  }
  return audit;
}

final class FoulBreakdown {
  const FoulBreakdown({
    this.shooting = 0,
    this.nonShooting = 0,
    this.offensive = 0,
    this.bonusAwards = 0,
  });
  final int shooting;
  final int nonShooting;
  final int offensive;
  final int bonusAwards;
}

FoulBreakdown foulBreakdown(List<GameEvent> events, {TeamId? team}) {
  var shooting = 0;
  var nonShooting = 0;
  var offensive = 0;
  var bonus = 0;
  for (final event in events.whereType<PersonalFoul>()) {
    if (team != null && event.committingTeamId != team.value) continue;
    switch (event.kind) {
      case FoulKind.shooting:
        shooting++;
      case FoulKind.nonShooting:
        nonShooting++;
      case FoulKind.offensive:
        offensive++;
    }
    if (event.bonus) bonus++;
  }
  return FoulBreakdown(
    shooting: shooting,
    nonShooting: nonShooting,
    offensive: offensive,
    bonusAwards: bonus,
  );
}

/// Declared T015 team strength: mean of 11 rated attributes over five starters
/// (`stamina` excluded because M002 never reads it).
double teamRating(GameInput input, TeamId team) {
  final lineup = input.lineupFor(team);
  var total = 0;
  for (final player in lineup.players) {
    final map = player.attributes.asMap;
    for (final entry in map.entries) {
      if (entry.key == 'stamina') continue;
      total += entry.value;
    }
  }
  return total / (lineup.players.length * 11);
}

/// Assisted share of made field goals, or null when there are no makes.
double? assistedFgmShare(List<GameEvent> events, TeamId team) {
  var made = 0;
  var assisted = 0;
  for (final event in events.whereType<FieldGoalAttempt>()) {
    if (event.teamId != team.value || !event.made) continue;
    made++;
    if (event.assistedById != null) assisted++;
  }
  if (made == 0) return null;
  return assisted / made;
}

String ledgerDigest(GameEventLedger ledger) =>
    sha256.convert(utf8.encode(jsonEncode(ledger.toJson()))).toString();

final class Stats {
  Stats(this.values);
  final List<double> values;

  int get n => values.length;
  double? get mean => n == 0 ? null : values.reduce((a, b) => a + b) / n;
  double? get median {
    if (n == 0) return null;
    final sorted = [...values]..sort();
    final middle = n ~/ 2;
    return n.isOdd ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  double? get standardDeviation {
    if (n < 2) return null;
    final average = mean!;
    var sum = 0.0;
    for (final value in values) {
      final diff = value - average;
      sum += diff * diff;
    }
    return math.sqrt(sum / (n - 1));
  }

  double? get min => n == 0 ? null : values.reduce(math.min);
  double? get max => n == 0 ? null : values.reduce(math.max);
  double? percentile(double q) => n == 0 ? null : quantile(values, q);

  Map<String, Object?> toJson() => {
    'n': n,
    'mean': mean,
    'median': median,
    'sd': standardDeviation,
    'min': min,
    'max': max,
    'p5': percentile(0.05),
    'p95': percentile(0.95),
  };
}

double quantile(List<double> values, double q) {
  final sorted = [...values]..sort();
  if (sorted.isEmpty) throw ArgumentError('quantile of empty sample');
  if (q <= 0) return sorted.first;
  if (q >= 1) return sorted.last;
  final position = (sorted.length - 1) * q;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  final weight = position - lower;
  return sorted[lower] * (1 - weight) + sorted[upper] * weight;
}

String bandVerdict(double? value, double low, double high) {
  if (value == null) return 'undefined';
  if (value < low) return 'below';
  if (value > high) return 'above';
  return 'within';
}

/// Structural checks for a completed game; returns an empty list when clean.
List<String> verifyGame(GameInput input, GameResult result) {
  final issues = <String>[];
  try {
    final validated = GameEventReducer.validate(input, result.ledger);
    final box = EventAccounting.aggregate(validated);
    if (!validated.state.ended) issues.add('state not ended');
    if (box.teams[input.homeTeamId.value]!.points != result.homeScore ||
        box.teams[input.awayTeamId.value]!.points != result.awayScore) {
      issues.add('accounting mismatch');
    }
    if (result.homeScore == result.awayScore) issues.add('tied game');
    if (result.events.isEmpty) issues.add('empty ledger');
    if (result.events.first.type != 'GameStarted') {
      issues.add('first event not GameStarted');
    }
    if (result.events.last.type != 'GameEnded') {
      issues.add('last event not GameEnded');
    }
    for (final team in [input.homeTeamId, input.awayTeamId]) {
      final teamBox = box.teams[team.value]!;
      var points = 0;
      var turnovers = 0;
      var fouls = 0;
      for (final player in input.lineupFor(team).players) {
        final stats = box.players[player.id.value]!;
        points += stats.points;
        turnovers += stats.turnovers;
        fouls += stats.personalFouls;
      }
      if (points != teamBox.points) issues.add('player points mismatch');
      if (turnovers != teamBox.turnovers) {
        issues.add('player turnovers mismatch');
      }
      if (fouls != teamBox.personalFouls) issues.add('player fouls mismatch');
      if (teamBox.fgm != teamBox.twoPm + teamBox.threePm) {
        issues.add('team FGM equation');
      }
      if (teamBox.fga != teamBox.twoPa + teamBox.threePa) {
        issues.add('team FGA equation');
      }
      if (teamBox.rebounds != teamBox.oreb + teamBox.dreb) {
        issues.add('team rebound equation');
      }
    }
  } on GameValidationException catch (error) {
    issues.add('reducer: ${error.codes}');
  } on Object catch (error) {
    issues.add('exception: $error');
  }
  return issues;
}

/// Bonus, missed-shooting-foul, and-one and clock-boundary audit.
List<String> foulAudit(List<GameEvent> events, GameRules rules) {
  final issues = <String>[];
  final defensiveFouls = <String, int>{};
  final fgaTimestamps = <String>{
    for (final event in events.whereType<FieldGoalAttempt>())
      '${event.period}:${event.gameClock}',
  };
  for (final event in events.whereType<PersonalFoul>()) {
    final key = '${event.period}:${event.committingTeamId}';
    final committedBefore = defensiveFouls[key] ?? 0;
    if (event.kind == FoulKind.offensive) continue;
    if (event.bonus) {
      final threshold = rules.bonusThreshold(event.period);
      if (committedBefore + 1 < threshold) {
        issues.add('bonus awarded before threshold at seq ${event.sequence}');
      }
    }
    defensiveFouls[key] = committedBefore + 1;
    if (event.kind == FoulKind.shooting &&
        event.freeThrowsAwarded >= 2 &&
        fgaTimestamps.contains('${event.period}:${event.gameClock}')) {
      issues.add('FGA shares missed-shooting-foul timestamp');
    }
  }
  return issues;
}

/// Analytic single-draw overshoot probability for the frozen A1 brackets.
double singleDrawOvershoot(int shotClock, {GameRules? rules}) {
  final brackets = (rules ?? GameRules.standard).phaseDurations;
  final weights = (rules ?? GameRules.standard).phaseWeights;
  final totalWeight = weights.reduce((a, b) => a + b);
  var weighted = 0.0;
  for (var i = 0; i < brackets.length; i++) {
    final bracket = brackets[i];
    final values = bracket[1] - bracket[0] + 1;
    final overshoot = math.max(
      0,
      bracket[1] - math.max(shotClock, bracket[0] - 1),
    );
    weighted += weights[i] * (overshoot / values);
  }
  return weighted / totalWeight;
}
