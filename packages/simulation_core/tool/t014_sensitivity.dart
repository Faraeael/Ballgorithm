/// T014 paired-seed attribute sensitivity experiment.
///
/// Reproducible research command, not part of the unit-test suite:
///
/// ```
/// cd packages/simulation_core
/// dart run tool/t014_sensitivity.dart
/// ```
///
/// Writes the v2 experiment artifacts
/// `specs/002-possession-simulation/t014-paired-results-v2.csv` and
/// `t014-statistical-summary-v2.json`; the v1 artifacts are historical and must
/// never be overwritten. The protocol in
/// `specs/002-possession-simulation/t014-analysis-protocol.md` is frozen before
/// execution and must not be modified by this tool.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';

import 't014_stats.dart';

const int leagueFixtureSeed = 20261028;
const int firstSeed = 1;
const int lastSeed = 200;
const int ratingDelta = 20;
const int bootstrapSeed = 20261029;
const int permutationSeed = 424242;
const int resamples = 10000;
const int permutations = 10000;
const int minimumValidPairs = 100;

/// Historical v1 baseline (T013). The v2 run records its real parent below.
const String historicalV1Commit = 'fb9636814dc9c187ac5007352b1a3a159c41e201';

const List<String> offensiveSkills = [
  'insideScoring',
  'midrange',
  'threePoint',
  'freeThrow',
  'passing',
  'ballHandling',
  'basketballIQ',
];

final List<int> seeds = List<int>.generate(
  lastSeed - firstSeed + 1,
  (i) => firstSeed + i,
);

/// Raw counts for one arm of one seed pair.
final class Observation {
  const Observation(this.numerator, this.denominator);
  final int numerator;
  final int denominator;

  double? get rate => denominator > 0 ? numerator / denominator : null;
}

final class Experiment {
  Experiment({
    required this.id,
    required this.title,
    required this.expected,
    required this.metric,
    required this.subject,
    required this.attributes,
    required this.scale,
    required this.observe,
    this.secondary,
    this.describe,
  });

  final String id;
  final String title;

  /// `increase` or `decrease`, exactly as pre-registered.
  final String expected;
  final String metric;
  final String subject;
  final Map<String, List<String>> attributes;
  final double scale;
  final Observation Function(GameResult result, GameInput input) observe;
  final Observation Function(GameResult result, GameInput input)? secondary;
  final Map<String, int> Function(GameResult result, GameInput input)? describe;
}

final class Arm {
  Arm(this.input, this.result);
  final GameInput input;
  final GameResult result;
}

void main() {
  final league = const LeagueGenerator().generate(
    const GenerationConfig(seed: leagueFixtureSeed),
  );
  final homeTeam = league.teams[0];
  final awayTeam = league.teams[1];
  final lineup = ActiveLineup.defaultFor(homeTeam);

  final subjects = selectSubjects(lineup);
  final experiments = buildExperiments(homeTeam, lineup, subjects);

  stdout.writeln(
    'T014 fixture: ${homeTeam.id.value} vs ${awayTeam.id.value}, '
    'league seed $leagueFixtureSeed',
  );
  for (final entry in subjects.entries) {
    stdout.writeln(
      '  ${entry.key}: ${entry.value.id.value} '
      '(${entry.value.position.shortName}) highest-rating subject selected',
    );
  }

  // The baseline arm is identical for every experiment and runs once.
  final baseline = <int, Arm>{};
  for (final seed in seeds) {
    final input = buildInput(league, seed);
    baseline[seed] = Arm(input, GameSimulator().simulate(input));
  }
  verifyGameplay(baseline.values);

  final rows = <Map<String, Object?>>[];
  final summaries = <Map<String, Object?>>[];

  for (final experiment in experiments) {
    final modified = buildModifiedLeague(league, experiment.attributes);
    final deltas = <double>[];
    final secondaryDeltas = <double>[];
    final baselineRates = <double>[];
    final interventionRates = <double>[];
    final pooled = <String, int>{};
    final descriptiveBaseline = <String, int>{};
    final descriptiveIntervention = <String, int>{};
    var zeroBaseline = 0;
    var zeroIntervention = 0;
    var zeroBoth = 0;
    var valid = 0;

    for (final seed in seeds) {
      final baseArm = baseline[seed]!;
      final interventionInput = buildInput(modified, seed);
      final interventionArm = Arm(
        interventionInput,
        GameSimulator().simulate(interventionInput),
      );

      final baseObs = experiment.observe(baseArm.result, baseArm.input);
      final intObs = experiment.observe(
        interventionArm.result,
        interventionArm.input,
      );
      final baseRate = baseObs.rate;
      final intRate = intObs.rate;

      String status;
      if (baseRate == null && intRate == null) {
        status = 'zero-both';
        zeroBoth++;
        zeroBaseline++;
        zeroIntervention++;
      } else if (baseRate == null) {
        status = 'zero-baseline';
        zeroBaseline++;
      } else if (intRate == null) {
        status = 'zero-intervention';
        zeroIntervention++;
      } else {
        status = 'valid';
        valid++;
        deltas.add((intRate - baseRate) * experiment.scale);
        baselineRates.add(baseRate * experiment.scale);
        interventionRates.add(intRate * experiment.scale);
      }

      _accumulate(pooled, {
        'baselineNumerator': baseObs.numerator,
        'baselineDenominator': baseObs.denominator,
        'interventionNumerator': intObs.numerator,
        'interventionDenominator': intObs.denominator,
      });

      final describe = experiment.describe;
      if (describe != null) {
        _accumulate(
          descriptiveBaseline,
          describe(baseArm.result, baseArm.input),
        );
        _accumulate(
          descriptiveIntervention,
          describe(interventionArm.result, interventionArm.input),
        );
      }

      final secondary = experiment.secondary;
      if (secondary != null) {
        final baseSecondary = secondary(baseArm.result, baseArm.input).rate;
        final intSecondary = secondary(
          interventionArm.result,
          interventionArm.input,
        ).rate;
        if (baseSecondary != null && intSecondary != null) {
          secondaryDeltas.add((intSecondary - baseSecondary) * 100);
        }
      }

      rows.add({
        'experiment': experiment.id,
        'seed': seed,
        'leagueFixtureSeed': leagueFixtureSeed,
        'homeTeamId': homeTeam.id.value,
        'awayTeamId': awayTeam.id.value,
        'subjectId': experiment.subject,
        'subjectPosition': _subjectPosition(lineup, experiment.subject),
        'baselineInputFingerprint': GameFingerprint.of(baseArm.input),
        'interventionInputFingerprint': GameFingerprint.of(interventionInput),
        'baselineNumerator': baseObs.numerator,
        'baselineDenominator': baseObs.denominator,
        'interventionNumerator': intObs.numerator,
        'interventionDenominator': intObs.denominator,
        'baselineMetric':
            scaledRate(
              baseObs.numerator,
              baseObs.denominator,
              experiment.scale,
            ) ??
            '',
        'interventionMetric':
            scaledRate(
              intObs.numerator,
              intObs.denominator,
              experiment.scale,
            ) ??
            '',
        'pairedDifference':
            pairedScaledDifference(
              baseObs.numerator,
              baseObs.denominator,
              intObs.numerator,
              intObs.denominator,
              experiment.scale,
            ) ??
            '',
        'status': status,
        'appliedRatingDelta': experiment.attributes.entries
            .expand(
              (entry) =>
                  entry.value.map((attribute) => '$attribute+$ratingDelta'),
            )
            .toSet()
            .join(';'),
        'simulationVersion': gameSimulationVersion,
        'rulesVersion': gameRulesVersion,
        'eventSchemaVersion': gameEventSchemaVersion,
        'prngImplementationId': 'xorshift32-v1',
      });
    }

    verifyCsvReconciliation(rows, experiment);
    summaries.add(
      summarize(
        experiment: experiment,
        valid: valid,
        zeroBaseline: zeroBaseline,
        zeroIntervention: zeroIntervention,
        zeroBoth: zeroBoth,
        deltas: deltas,
        baselineRates: baselineRates,
        interventionRates: interventionRates,
        pooled: pooled,
        descriptiveBaseline: descriptiveBaseline,
        descriptiveIntervention: descriptiveIntervention,
        secondaryDeltas: secondaryDeltas,
      ),
    );
  }

  applyHolm(summaries);

  final outDir = Directory(
    '${Directory.current.path}/../../specs/002-possession-simulation',
  );
  File(
    '${outDir.path}/t014-paired-results-v2.csv',
  ).writeAsStringSync(buildCsv(rows));
  final summary = <String, Object?>{
    'protocol': 't014-analysis-protocol.md (unchanged v1 preregistration)',
    'simulationVersion': gameSimulationVersion,
    'amendment': '002 (player-exposure turnover hazard)',
    'historicalV1Commit': historicalV1Commit,
    'parentCommit': _git(['rev-parse', 'HEAD']),
    'workingTreeStatus': _git([
      'status',
      '--porcelain',
    ]).split('\n').where((line) => line.trim().isNotEmpty).toList(),
    'modelSourcesAreUncommitted': true,
    'sourceSha256': {
      for (final path in _sourcePaths)
        path: sha256.convert(File(path).readAsBytesSync()).toString(),
    },
    'baselineCommit': historicalV1Commit,
    'baselineCommitMeaning':
        'historical v1 T013 baseline; this v2 run used uncommitted working-tree '
        'changes on parentCommit',
    'leagueFixtureSeed': leagueFixtureSeed,
    'matchup': {
      'homeTeamId': homeTeam.id.value,
      'awayTeamId': awayTeam.id.value,
    },
    'subjects': {
      for (final entry in subjects.entries)
        entry.key: {
          'playerId': entry.value.id.value,
          'position': entry.value.position.shortName,
          'baselineRatings': entry.value.attributes.asMap,
        },
    },
    'seeds': {
      'first': firstSeed,
      'last': lastSeed,
      'plannedPairs': seeds.length,
    },
    'games': {
      'baselineGames': seeds.length,
      'interventionGames': seeds.length * experiments.length,
      'totalGames': seeds.length + seeds.length * experiments.length,
      'baselineReusedAcrossExperiments': true,
    },
    'statistics': {
      'bootstrap': {
        'method': 'paired percentile',
        'resamples': resamples,
        'seed': bootstrapSeed,
        'quantile': 'type-7',
        'confidence': 0.95,
      },
      'permutation': {
        'test': 'two-sided paired sign-flip',
        'permutations': permutations,
        'seed': permutationSeed,
      },
      'correction': 'Holm-Bonferroni across six confirmatory experiments',
      'minimumValidPairs': minimumValidPairs,
      'rng': 'xorshift32-v1 (analysis copy, independent of game PRNG)',
    },
    'experiments': summaries,
    'ac09': ac09Verdict(summaries),
  };
  File(
    '${outDir.path}/t014-statistical-summary-v2.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));

  stdout.writeln('');
  for (final experiment in summaries) {
    stdout.writeln(
      '${experiment['id']}: mean=${_fmt(experiment['meanDifference'])} '
      'ci=[${_fmt(experiment['ciLow'])}, ${_fmt(experiment['ciHigh'])}] '
      'p=${_fmt(experiment['pValue'])} '
      'holm=${_fmt(experiment['holmAdjustedP'])} '
      'dz=${_fmt(experiment['standardizedEffect'])} '
      'valid=${experiment['validPairs']} '
      'verdict=${experiment['verdict']}',
    );
  }
  stdout.writeln('AC09: ${summary['ac09']}');
  stdout.writeln('results written to ${outDir.path}');
}

/// Fails fast if any CSV row's scaled metrics and difference disagree.
void verifyCsvReconciliation(
  List<Map<String, Object?>> rows,
  Experiment experiment,
) {
  for (final row in rows.where((row) => row['experiment'] == experiment.id)) {
    if (row['status'] != 'valid') {
      if (row['baselineMetric'] != '' ||
          row['interventionMetric'] != '' ||
          row['pairedDifference'] != '') {
        throw StateError(
          'excluded row ${row['experiment']}/${row['seed']} carries a metric',
        );
      }
      continue;
    }
    final baseline = row['baselineMetric']! as double;
    final intervention = row['interventionMetric']! as double;
    final difference = row['pairedDifference']! as double;
    if ((difference - (intervention - baseline)).abs() > 1e-9) {
      throw StateError(
        'unreconciled row ${row['experiment']}/${row['seed']}: '
        '$difference != $intervention - $baseline',
      );
    }
  }
}

const List<String> _sourcePaths = [
  'lib/src/simulation/probability_model.dart',
  'lib/src/simulation/game_versions.dart',
  'lib/src/simulation/game_simulator.dart',
  'tool/t014_sensitivity.dart',
  'tool/t014_stats.dart',
  'test/simulation/support.dart',
];

String _git(List<String> arguments) {
  try {
    final result = Process.runSync('git', arguments);
    if (result.exitCode != 0) return '';
    return (result.stdout as String).trim();
  } on ProcessException {
    return '';
  }
}

String _fmt(Object? value) =>
    value is double ? value.toStringAsFixed(5) : '$value';

String _subjectPosition(ActiveLineup lineup, String subjectId) => subjectId
    .split('+')
    .map(
      (id) => lineup.players
          .firstWhere((player) => player.id.value == id)
          .position
          .shortName,
    )
    .join('+');

void _accumulate(Map<String, int> target, Map<String, int> values) {
  for (final entry in values.entries) {
    target[entry.key] = (target[entry.key] ?? 0) + entry.value;
  }
}

/// Deterministic rating-based subject selection (protocol §2).
Map<String, Player> selectSubjects(ActiveLineup lineup) {
  Player best(String attribute) {
    var chosen = lineup.players.first;
    var bestValue = chosen.attributes.asMap[attribute]!;
    for (final player in lineup.players.skip(1)) {
      final value = player.attributes.asMap[attribute]!;
      if (value > bestValue) {
        chosen = player;
        bestValue = value;
      }
    }
    return chosen;
  }

  return {
    'E1': best('threePoint'),
    'E2': best('freeThrow'),
    'E3': lineup.players[4],
    'E4': lineup.players[0],
    'E5': best('perimeterDefense'),
  };
}

List<Experiment> buildExperiments(
  Team home,
  ActiveLineup lineup,
  Map<String, Player> subjects,
) => [
  Experiment(
    id: 'E1',
    title: 'threePoint +20 on the highest-rated three-point shooter',
    expected: 'increase',
    metric: 'player 3PT%',
    subject: subjects['E1']!.id.value,
    attributes: {
      subjects['E1']!.id.value: ['threePoint'],
    },
    scale: 1,
    observe: (result, input) {
      final stats = result.boxScore.players[subjects['E1']!.id.value]!;
      return Observation(stats.threePm, stats.threePa);
    },
    describe: (result, input) {
      final stats = result.boxScore.players[subjects['E1']!.id.value]!;
      final team = result.boxScore.teams[input.homeTeamId.value]!;
      return {
        'fga': stats.fga,
        'threePa': stats.threePa,
        'threePm': stats.threePm,
        'teamThreePa': team.threePa,
      };
    },
  ),
  Experiment(
    id: 'E2',
    title: 'freeThrow +20 on the highest-rated free-throw shooter',
    expected: 'increase',
    metric: 'player FT%',
    subject: subjects['E2']!.id.value,
    attributes: {
      subjects['E2']!.id.value: ['freeThrow'],
    },
    scale: 1,
    observe: (result, input) {
      final stats = result.boxScore.players[subjects['E2']!.id.value]!;
      return Observation(stats.ftm, stats.fta);
    },
    describe: (result, input) {
      final stats = result.boxScore.players[subjects['E2']!.id.value]!;
      return {'fta': stats.fta, 'ftm': stats.ftm};
    },
  ),
  Experiment(
    id: 'E3',
    title: 'rebounding +20 on the starting center',
    expected: 'increase',
    metric: 'player share of live rebound opportunities',
    subject: subjects['E3']!.id.value,
    attributes: {
      subjects['E3']!.id.value: ['rebounding'],
    },
    scale: 1,
    observe: (result, input) {
      final stats = result.boxScore.players[subjects['E3']!.id.value]!;
      return Observation(
        stats.rebounds,
        result.events.whereType<Rebound>().length,
      );
    },
    describe: (result, input) {
      final stats = result.boxScore.players[subjects['E3']!.id.value]!;
      final team = result.boxScore.teams[input.homeTeamId.value]!;
      return {
        'rebounds': stats.rebounds,
        'oreb': stats.oreb,
        'dreb': stats.dreb,
        'liveOpportunities': result.events.whereType<Rebound>().length,
        'teamRebounds': team.rebounds,
      };
    },
  ),
  Experiment(
    id: 'E4',
    title: 'ballHandling +20 on the starting point guard',
    expected: 'decrease',
    metric: 'player turnovers per 100 started possessions',
    subject: subjects['E4']!.id.value,
    attributes: {
      subjects['E4']!.id.value: ['ballHandling'],
    },
    scale: 100,
    observe: (result, input) {
      final stats = result.boxScore.players[subjects['E4']!.id.value]!;
      return Observation(
        stats.turnovers,
        startedPossessions(result, input.homeTeamId),
      );
    },
    describe: (result, input) {
      final id = subjects['E4']!.id.value;
      final stats = result.boxScore.players[id]!;
      final team = result.boxScore.teams[input.homeTeamId.value]!;
      var stealLinked = 0;
      var nonSteal = 0;
      var shotClock = 0;
      for (final turnover in result.events.whereType<Turnover>()) {
        if (turnover.playerId != id) continue;
        switch (turnover.reason) {
          case TurnoverReason.steal:
            stealLinked++;
          case TurnoverReason.nonSteal:
            nonSteal++;
          case TurnoverReason.shotClock:
            shotClock++;
          case TurnoverReason.offensiveFoul:
            break;
        }
      }
      return {
        'playerTurnovers': stats.turnovers,
        'teamTurnovers': team.turnovers,
        'startedPossessions': startedPossessions(result, input.homeTeamId),
        'completedPossessions': completedPossessions(result, input.homeTeamId),
        'stealLinked': stealLinked,
        'nonSteal': nonSteal,
        'shotClock': shotClock,
      };
    },
  ),
  Experiment(
    id: 'E5',
    title: 'perimeterDefense +20 on the highest-rated perimeter defender',
    expected: 'decrease',
    metric: 'opponent eFG% on the defender positional matchup',
    subject: subjects['E5']!.id.value,
    attributes: {
      subjects['E5']!.id.value: ['perimeterDefense'],
    },
    scale: 1,
    observe: (result, input) =>
        _opponentMatchup(result, input, subjects['E5']!.position),
    describe: (result, input) {
      final position = subjects['E5']!.position;
      final shooterIds = {
        for (final player in input.awayLineup.players)
          if (player.position == position) player.id.value,
      };
      var fgm = 0;
      var threePm = 0;
      var fga = 0;
      for (final event in result.events.whereType<FieldGoalAttempt>()) {
        if (event.teamId != input.awayTeamId.value) continue;
        if (!shooterIds.contains(event.shooterId)) continue;
        fga++;
        if (event.made) {
          fgm++;
          if (event.shotValue == 3) threePm++;
        }
      }
      final opponent = result.boxScore.teams[input.awayTeamId.value]!;
      return {
        'oppFga': fga,
        'oppFgm': fgm,
        'oppThreePm': threePm,
        'oppTurnovers': opponent.turnovers,
        'oppStartedPossessions': startedPossessions(result, input.awayTeamId),
      };
    },
    secondary: (result, input) {
      final team = result.boxScore.teams[input.awayTeamId.value]!;
      return Observation(
        team.turnovers,
        startedPossessions(result, input.awayTeamId),
      );
    },
  ),
  Experiment(
    id: 'E6',
    title: 'seven offensive skills +20 on all five starting players',
    expected: 'increase',
    metric: 'home points per 100 completed possessions',
    subject: lineup.playerIds.join('+'),
    attributes: {
      for (final player in lineup.players) player.id.value: offensiveSkills,
    },
    scale: 100,
    observe: (result, input) => Observation(
      result.homeScore,
      completedPossessions(result, input.homeTeamId),
    ),
    describe: (result, input) {
      final team = result.boxScore.teams[input.homeTeamId.value]!;
      final opponent = result.boxScore.teams[input.awayTeamId.value]!;
      final shotClockViolations = result.events
          .whereType<Turnover>()
          .where(
            (turnover) =>
                turnover.reason == TurnoverReason.shotClock &&
                turnover.teamId == input.homeTeamId.value,
          )
          .length;
      return {
        'points': result.homeScore,
        'completedPossessions': completedPossessions(result, input.homeTeamId),
        'startedPossessions': startedPossessions(result, input.homeTeamId),
        'fga': team.fga,
        'fgm': team.fgm,
        'threePa': team.threePa,
        'fta': team.fta,
        'ftm': team.ftm,
        'turnovers': team.turnovers,
        'shotClockViolations': shotClockViolations,
        'oreb': team.oreb,
        'oppDreb': opponent.dreb,
      };
    },
  ),
];

Observation _opponentMatchup(
  GameResult result,
  GameInput input,
  Position position,
) {
  final shooterIds = {
    for (final player in input.awayLineup.players)
      if (player.position == position) player.id.value,
  };
  var fgm = 0;
  var threePm = 0;
  var fga = 0;
  for (final event in result.events.whereType<FieldGoalAttempt>()) {
    if (event.teamId != input.awayTeamId.value) continue;
    if (!shooterIds.contains(event.shooterId)) continue;
    fga++;
    if (event.made) {
      fgm++;
      if (event.shotValue == 3) threePm++;
    }
  }
  // eFG% = (FGM + 0.5 * 3PM) / FGA, kept as doubled integers.
  return Observation(2 * fgm + threePm, 2 * fga);
}

GameInput buildInput(League league, int seed) {
  final home = league.teams[0];
  final away = league.teams[1];
  return GameInput.create(
    gameId: 'game-1',
    league: league,
    homeTeamId: home.id,
    awayTeamId: away.id,
    homeLineup: ActiveLineup.defaultFor(home),
    awayLineup: ActiveLineup.defaultFor(away),
    seed: seed,
    rules: GameRules.standard,
  );
}

/// Bumps the requested attributes and proves nothing else changed.
League buildModifiedLeague(League base, Map<String, List<String>> attributes) {
  final json = jsonDecode(jsonEncode(base.toJson())) as Map<String, Object?>;
  final expectedPaths = <String>{};
  for (final entry in attributes.entries) {
    final playerPath = _playerPath(json, entry.key);
    final player = _findPlayerJson(json, entry.key);
    final values = player['attributes']! as Map<String, Object?>;
    for (final attribute in entry.value) {
      final old = values[attribute]! as int;
      values[attribute] = math.min(100, old + ratingDelta);
      expectedPaths.add('${playerPath}attributes.$attribute');
    }
  }
  final modified = League.fromJson(json);
  assertOnlyExpectedLeagueDiff(base.toJson(), json, expectedPaths);
  return modified;
}

Map<String, Object?> _findPlayerJson(
  Map<String, Object?> leagueJson,
  String playerId,
) {
  final teams = leagueJson['teams']! as List<Object?>;
  for (final team in teams) {
    final roster =
        (team! as Map<String, Object?>)['roster']! as Map<String, Object?>;
    for (final player in roster['players']! as List<Object?>) {
      final map = player! as Map<String, Object?>;
      if (map['id'] == playerId) return map;
    }
  }
  throw StateError('player $playerId not found');
}

String _playerPath(Map<String, Object?> leagueJson, String playerId) {
  final teams = leagueJson['teams']! as List<Object?>;
  for (var teamIndex = 0; teamIndex < teams.length; teamIndex++) {
    final roster =
        (teams[teamIndex]! as Map<String, Object?>)['roster']!
            as Map<String, Object?>;
    final players = roster['players']! as List<Object?>;
    for (var playerIndex = 0; playerIndex < players.length; playerIndex++) {
      final map = players[playerIndex]! as Map<String, Object?>;
      if (map['id'] == playerId) {
        return 'teams[$teamIndex].roster.players[$playerIndex].';
      }
    }
  }
  throw StateError('player $playerId not found');
}

void collectDiffs(
  Object? base,
  Object? modified,
  String path,
  Set<String> out,
) {
  if (base is Map<String, Object?> && modified is Map<String, Object?>) {
    final keys = {...base.keys, ...modified.keys};
    for (final key in keys) {
      collectDiffs(
        base[key],
        modified[key],
        path.isEmpty ? key : '$path.$key',
        out,
      );
    }
    return;
  }
  if (base is List<Object?> && modified is List<Object?>) {
    final length = math.max(base.length, modified.length);
    for (var i = 0; i < length; i++) {
      collectDiffs(
        i < base.length ? base[i] : null,
        i < modified.length ? modified[i] : null,
        '$path[$i]',
        out,
      );
    }
    return;
  }
  if (base != modified) out.add(path);
}

void assertOnlyExpectedLeagueDiff(
  Map<String, Object?> base,
  Map<String, Object?> modified,
  Set<String> expected,
) {
  final diffs = <String>{};
  collectDiffs(base, modified, '', diffs);
  final unexpected = diffs.difference(expected);
  if (unexpected.isNotEmpty) {
    throw StateError('unexpected league differences: $unexpected');
  }
  if (diffs.isEmpty) {
    throw StateError('no league difference was applied');
  }
}

void verifyGameplay(Iterable<Arm> arms) {
  for (final arm in arms) {
    final validated = GameEventReducer.validate(arm.input, arm.result.ledger);
    if (!validated.state.ended) {
      throw StateError('game did not end: seed ${arm.input.seed}');
    }
    final box = EventAccounting.aggregate(validated);
    if (box.teams[arm.input.homeTeamId.value]!.points != arm.result.homeScore ||
        box.teams[arm.input.awayTeamId.value]!.points != arm.result.awayScore) {
      throw StateError('accounting mismatch: seed ${arm.input.seed}');
    }
    if (arm.result.homeScore == arm.result.awayScore) {
      throw StateError('tied game: seed ${arm.input.seed}');
    }
    if (GameFingerprint.of(arm.input) != arm.result.ledger.inputFingerprint) {
      throw StateError('fingerprint mismatch: seed ${arm.input.seed}');
    }
  }
}

int startedPossessions(GameResult result, TeamId team) => result.events
    .whereType<PossessionStarted>()
    .where((event) => event.offenseTeamId == team.value)
    .length;

int completedPossessions(GameResult result, TeamId team) => result.events
    .whereType<PossessionEnded>()
    .where((event) => event.offenseTeamId == team.value)
    .where(
      (event) => const {
        PossessionEndReason.turnover,
        PossessionEndReason.madeFieldGoal,
        PossessionEndReason.madeFinalFreeThrow,
        PossessionEndReason.defensiveRebound,
      }.contains(event.reason),
    )
    .length;

Map<String, Object?> summarize({
  required Experiment experiment,
  required int valid,
  required int zeroBaseline,
  required int zeroIntervention,
  required int zeroBoth,
  required List<double> deltas,
  required List<double> baselineRates,
  required List<double> interventionRates,
  required Map<String, int> pooled,
  required Map<String, int> descriptiveBaseline,
  required Map<String, int> descriptiveIntervention,
  required List<double> secondaryDeltas,
}) {
  final expectedSign = experiment.expected == 'increase' ? 1 : -1;
  final result = <String, Object?>{
    'id': experiment.id,
    'title': experiment.title,
    'metric': experiment.metric,
    'expectedDirection': experiment.expected,
    'subject': experiment.subject,
    'attributes': experiment.attributes,
    'plannedPairs': seeds.length,
    'validPairs': valid,
    'zeroBaseline': zeroBaseline,
    'zeroIntervention': zeroIntervention,
    'zeroBoth': zeroBoth,
    'zeroBaselineInclusive': zeroBaseline,
    'zeroInterventionInclusive': zeroIntervention,
    'zeroBaselineExclusive': zeroBaseline - zeroBoth,
    'zeroInterventionExclusive': zeroIntervention - zeroBoth,
    'zeroCountingNote':
        'zeroBaseline/zeroIntervention are inclusive: they count every seed '
        'with zero opportunities in that arm, including seeds that are zero in '
        'both arms. Exclusive counts subtract zeroBoth.',
    'pooled': pooled,
    'pooledBaselineRate': pooled['baselineDenominator']! > 0
        ? pooled['baselineNumerator']! /
              pooled['baselineDenominator']! *
              experiment.scale
        : null,
    'pooledInterventionRate': pooled['interventionDenominator']! > 0
        ? pooled['interventionNumerator']! /
              pooled['interventionDenominator']! *
              experiment.scale
        : null,
    'descriptiveBaseline': descriptiveBaseline,
    'descriptiveIntervention': descriptiveIntervention,
  };

  if (deltas.isEmpty) {
    result.addAll({
      'meanBaseline': null,
      'meanIntervention': null,
      'meanDifference': null,
      'medianDifference': null,
      'standardDeviation': null,
      'standardizedEffect': null,
      'ciLow': null,
      'ciHigh': null,
      'pValue': 1.0,
      'verdict': 'INCONCLUSIVE',
      'reason': 'no valid opportunity pairs',
    });
    return result;
  }

  final average = mean(deltas);
  final medianDelta = median(deltas);
  final sd = sampleStandardDeviation(deltas);
  final interval = bootstrapMeanInterval(deltas, seed: bootstrapSeed);
  final pValue = pairedPermutationP(deltas, seed: permutationSeed);
  final dz = sd == 0 ? null : average / sd;

  final verdict = pairedVerdict(
    validPairs: valid,
    minimumValidPairs: minimumValidPairs,
    expectedSign: expectedSign,
    meanDifference: average,
    ciLow: interval.low,
    ciHigh: interval.high,
    pValue: pValue,
  );

  result.addAll({
    'meanBaseline': mean(baselineRates),
    'meanIntervention': mean(interventionRates),
    'meanDifference': average,
    'medianDifference': medianDelta,
    'standardDeviation': sd,
    'standardizedEffect': dz,
    'ciLow': interval.low,
    'ciHigh': interval.high,
    'pValue': pValue,
    'expectedSign': expectedSign,
    'verdict': verdict,
  });

  if (experiment.secondary != null) {
    if (secondaryDeltas.isEmpty) {
      result['secondaryDiagnostic'] = {
        'verdict': 'INCONCLUSIVE',
        'reason': 'no valid pairs',
      };
    } else {
      final secondaryMean = mean(secondaryDeltas);
      final secondaryInterval = bootstrapMeanInterval(
        secondaryDeltas,
        seed: bootstrapSeed,
      );
      final secondaryP = pairedPermutationP(
        secondaryDeltas,
        seed: permutationSeed,
      );
      result['secondaryDiagnostic'] = {
        'metric': 'opponent turnovers per 100 opponent started possessions',
        'expectedDirection': 'increase',
        'validPairs': secondaryDeltas.length,
        'meanDifference': secondaryMean,
        'ciLow': secondaryInterval.low,
        'ciHigh': secondaryInterval.high,
        'unadjustedP': secondaryP,
        'directionMatches': secondaryMean > 0,
        'note': 'exploratory; outside the six-hypothesis family',
      };
    }
  }

  return result;
}

void applyHolm(List<Map<String, Object?>> summaries) {
  final pValues = [
    for (final summary in summaries)
      (summary['pValue'] as num?)?.toDouble() ?? 1.0,
  ];
  final adjusted = holmAdjust(pValues);
  for (var i = 0; i < summaries.length; i++) {
    summaries[i]['holmAdjustedP'] = adjusted[i];
    final revised = pairedVerdict(
      validPairs: summaries[i]['validPairs']! as int,
      minimumValidPairs: minimumValidPairs,
      expectedSign: summaries[i]['expectedSign']! as int,
      meanDifference: summaries[i]['meanDifference']! as double,
      ciLow: summaries[i]['ciLow']! as double,
      ciHigh: summaries[i]['ciHigh']! as double,
      pValue: summaries[i]['pValue']! as double,
      holmAdjustedP: adjusted[i],
    );
    if (revised != summaries[i]['verdict']) {
      summaries[i]['verdict'] = revised;
      summaries[i]['reason'] = 'Holm-adjusted p >= 0.05';
    }
  }
}

String ac09Verdict(List<Map<String, Object?>> summaries) {
  final verdicts = [
    for (final summary in summaries) summary['verdict'] as String,
  ];
  if (verdicts.every((verdict) => verdict == 'PASSED')) return 'PASSED';
  if (verdicts.contains('FAILED')) return 'FAILED';
  return 'INCONCLUSIVE';
}

String buildCsv(List<Map<String, Object?>> rows) {
  const columns = [
    'experiment',
    'seed',
    'leagueFixtureSeed',
    'homeTeamId',
    'awayTeamId',
    'subjectId',
    'subjectPosition',
    'baselineInputFingerprint',
    'interventionInputFingerprint',
    'baselineNumerator',
    'baselineDenominator',
    'interventionNumerator',
    'interventionDenominator',
    'baselineMetric',
    'interventionMetric',
    'pairedDifference',
    'status',
    'appliedRatingDelta',
    'simulationVersion',
    'rulesVersion',
    'eventSchemaVersion',
    'prngImplementationId',
  ];
  final buffer = StringBuffer()..writeln(columns.join(','));
  for (final row in rows) {
    buffer.writeln(columns.map((column) => row[column]).join(','));
  }
  return buffer.toString();
}
