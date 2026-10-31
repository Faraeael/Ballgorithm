/// T016 performance harness: bounded runtime and memory for AC12.
///
/// ```
/// cd packages/simulation_core
/// dart compile exe tool/t016_performance.dart -o build/t016_bench.exe
/// ./build/t016_bench.exe --games=1000 --warmup=60 --out=build/t016.json
/// ```
///
/// Measures complete v4 games on the frozen M001 league fixture. Every result is
/// validated through the reducer and reconciled with event accounting, so the
/// reported per-game cost is the whole measured iteration, (input construction +
/// `GameSimulator().simulate` + reducer validation + accounting), which is a
/// conservative upper bound on engine cost. Pure `simulate` time is reported
/// separately.
///
/// It never changes gameplay, probabilities, brackets or rules, and writes only
/// the file named by `--out`.
///
/// Runtime seeds are `50001 + i`. They exist only to vary game inputs for a
/// performance measurement: they are outside every statistical seed corpus
/// (development `1..1300`, Amendment 003 held-out `2001..2600`, Amendment 004
/// held-out `10001..10600`) and carry no basketball-calibration meaning.
library;

import 'dart:convert';
import 'dart:io';

import 'package:simulation_core/simulation_core.dart';

/// Frozen M001 league fixture used by every M002 artifact.
const int leagueSeed = 20261028;

/// Directed matchups: 28 unordered pairs x 2 orientations.
const int directedMatchups = 56;

/// First runtime seed. Deliberately outside every statistical seed corpus.
const int runtimeSeedBase = 50001;

int percentile(List<int> sortedMicros, int p) {
  if (sortedMicros.isEmpty) return 0;
  final rank = (p / 100 * sortedMicros.length).ceil() - 1;
  return sortedMicros[rank.clamp(0, sortedMicros.length - 1)];
}

/// Outcome of one measured game.
final class RunOutcome {
  const RunOutcome({
    required this.typedFailure,
    required this.accountingFailure,
    required this.boundViolation,
    required this.completed,
    required this.simulateMicros,
  });

  final bool typedFailure;
  final bool accountingFailure;
  final bool boundViolation;
  final bool completed;
  final int simulateMicros;
}

void main(List<String> args) {
  var games = 1000;
  var warmup = 60;
  String? outPath;
  for (final arg in args) {
    if (arg.startsWith('--games=')) {
      games = int.parse(arg.split('=').last);
    } else if (arg.startsWith('--warmup=')) {
      warmup = int.parse(arg.split('=').last);
    } else if (arg.startsWith('--out=')) {
      outPath = arg.split('=').last;
    } else {
      stderr.writeln('unknown argument: $arg');
      exitCode = 64;
      return;
    }
  }
  if (games < 1 || warmup < 0) {
    stderr.writeln('games must be >= 1 and warmup >= 0');
    exitCode = 64;
    return;
  }

  final league = const LeagueGenerator().generate(
    const GenerationConfig(seed: leagueSeed),
  );
  final teams = [...league.teams]
    ..sort((a, b) => a.id.value.compareTo(b.id.value));
  if (teams.length < 8) {
    stderr.writeln('expected at least 8 teams, found ${teams.length}');
    exitCode = 2;
    return;
  }
  final rules = GameRules.standard;
  final pairs = <(Team, Team)>[
    for (var i = 0; i < 8; i++)
      for (var j = i + 1; j < 8; j++)
        for (var orientation = 0; orientation < 2; orientation++)
          orientation == 0 ? (teams[i], teams[j]) : (teams[j], teams[i]),
  ];

  final failureSamples = <String>[];

  RunOutcome runOne(int index) {
    final matchupIndex = index % directedMatchups;
    final (home, away) = pairs[matchupIndex];
    try {
      final input = GameInput.create(
        gameId: 't016-$index',
        league: league,
        homeTeamId: home.id,
        awayTeamId: away.id,
        homeLineup: ActiveLineup.defaultFor(home),
        awayLineup: ActiveLineup.defaultFor(away),
        seed: runtimeSeedBase + index,
        rules: rules,
      );

      final watch = Stopwatch()..start();
      final result = GameSimulator().simulate(input);
      watch.stop();

      final validated = GameEventReducer.validate(input, result.ledger);
      final accounted = EventAccounting.aggregate(validated);
      final homePoints = accounted.teams[input.homeTeamId.value]?.points;
      final awayPoints = accounted.teams[input.awayTeamId.value]?.points;
      if (homePoints != result.homeScore || awayPoints != result.awayScore) {
        if (failureSamples.length < 5) {
          failureSamples.add('accounting mismatch: ${input.gameId}');
        }
        return RunOutcome(
          typedFailure: false,
          accountingFailure: true,
          boundViolation: false,
          completed: false,
          simulateMicros: watch.elapsedMicroseconds,
        );
      }

      // AC08-style configured bounds must hold for every completed game.
      final withinBounds =
          result.events.isNotEmpty &&
          result.events.last is GameEnded &&
          result.overtimes <= rules.maxOvertimes &&
          result.periodsPlayed <= rules.periods + rules.maxOvertimes &&
          result.events.length <= rules.maxEvents;
      if (!withinBounds) {
        if (failureSamples.length < 5) {
          failureSamples.add('bound violation: ${input.gameId}');
        }
        return RunOutcome(
          typedFailure: false,
          accountingFailure: false,
          boundViolation: true,
          completed: false,
          simulateMicros: watch.elapsedMicroseconds,
        );
      }

      return RunOutcome(
        typedFailure: false,
        accountingFailure: false,
        boundViolation: false,
        completed: true,
        simulateMicros: watch.elapsedMicroseconds,
      );
    } on GameValidationException catch (e) {
      if (failureSamples.length < 5) {
        failureSamples.add('typed failure: $e');
      }
      return const RunOutcome(
        typedFailure: true,
        accountingFailure: false,
        boundViolation: false,
        completed: false,
        simulateMicros: 0,
      );
    }
  }

  // Warmup: page-in, allocator and code-path warmup; outcomes discarded.
  for (var i = 0; i < warmup; i++) {
    runOne(i);
  }

  final baselineRss = ProcessInfo.currentRss;
  final perGameMicros = <int>[];
  final simulateMicros = <int>[];
  var typedFailures = 0;
  var accountingFailures = 0;
  var boundViolations = 0;
  var completed = 0;

  final loopWatch = Stopwatch()..start();
  for (var i = warmup; i < warmup + games; i++) {
    final watch = Stopwatch()..start();
    final outcome = runOne(i);
    watch.stop();
    perGameMicros.add(watch.elapsedMicroseconds);
    simulateMicros.add(outcome.simulateMicros);
    if (outcome.typedFailure) typedFailures++;
    if (outcome.accountingFailure) accountingFailures++;
    if (outcome.boundViolation) boundViolations++;
    if (outcome.completed) completed++;
  }
  loopWatch.stop();
  final endRss = ProcessInfo.currentRss;
  final maxRss = ProcessInfo.maxRss;

  final sortedPerGame = [...perGameMicros]..sort();
  final sortedSimulate = [...simulateMicros]..sort();
  int mib(int bytes) => bytes ~/ (1024 * 1024);
  double totalMs(List<int> v) => v.fold<int>(0, (a, b) => a + b) / 1000.0;
  bool peakKnown = maxRss > 0;

  final summary = <String, Object?>{
    'harness': 't016_performance.dart',
    'leagueSeed': leagueSeed,
    'runtimeSeedBase': runtimeSeedBase,
    'seedPolicy':
        'seed = 50001 + i for i in [0, games); outside every statistical seed corpus',
    'matchupPolicy':
        'directed matchup i % 56 (28 lexicographic pairs x 2 orientations)',
    'rules': {
      'rulesVersion': rules.rulesVersion,
      'periods': rules.periods,
      'periodSeconds': rules.periodSeconds,
      'overtimeSeconds': rules.overtimeSeconds,
      'maxOvertimes': rules.maxOvertimes,
      'shotClockSeconds': rules.shotClockSeconds,
      'maxEvents': rules.maxEvents,
    },
    'versions': {
      'gameSimulationVersion': gameSimulationVersion,
      'gameRulesVersion': gameRulesVersion,
      'gameEventSchemaVersion': gameEventSchemaVersion,
      'gameActionDurationModelVersion': gameActionDurationModelVersion,
      'gameFingerprintVersion': gameFingerprintVersion,
    },
    'gamesRequested': games,
    'warmupGames': warmup,
    'gamesCompleted': completed,
    'typedFailures': typedFailures,
    'accountingFailures': accountingFailures,
    'boundViolations': boundViolations,
    'failureSamples': failureSamples,
    'timing': {
      // Whole measured iteration: input build + simulate + reducer + accounting.
      'loopWallMs': loopWatch.elapsedMilliseconds,
      'perGameTotalMs': totalMs(perGameMicros),
      'perGameMeanMs': perGameMicros.isEmpty
          ? 0
          : totalMs(perGameMicros) / perGameMicros.length,
      'perGameP50Ms': percentile(sortedPerGame, 50) / 1000.0,
      'perGameP95Ms': percentile(sortedPerGame, 95) / 1000.0,
      'perGameP99Ms': percentile(sortedPerGame, 99) / 1000.0,
      'perGameMaxMs': (sortedPerGame.isEmpty ? 0 : sortedPerGame.last) / 1000.0,
      // Engine only: GameSimulator().simulate.
      'simulateTotalMs': totalMs(simulateMicros),
      'simulateP50Ms': percentile(sortedSimulate, 50) / 1000.0,
      'simulateP95Ms': percentile(sortedSimulate, 95) / 1000.0,
      'simulateMaxMs':
          (sortedSimulate.isEmpty ? 0 : sortedSimulate.last) / 1000.0,
    },
    'memory': {
      'baselineRssMiB': mib(baselineRss),
      'endRssMiB': mib(endRss),
      'processMaxRssMiB': peakKnown ? mib(maxRss) : null,
      'incrementalEndMinusBaselineMiB': mib(endRss - baselineRss),
      'incrementalPeakMinusBaselineMiB': peakKnown
          ? mib(maxRss - baselineRss)
          : null,
    },
  };
  final json = const JsonEncoder.withIndent('  ').convert(summary);
  if (outPath != null) {
    File(outPath).writeAsStringSync('$json\n');
  }
  stdout.writeln(json);
}
