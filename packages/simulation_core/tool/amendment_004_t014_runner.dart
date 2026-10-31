/// Amendment 004 T014 attribute-sensitivity evidence runner.
///
/// Re-executes the frozen T014 paired-seed protocol (`t014-analysis-protocol.md`)
/// against whichever `simulation_core` package it is compiled with, and emits
/// the complete per-experiment summary as JSON so gate E1–E6 can be audited
/// from a persisted artifact rather than terminal output.
///
/// The protocol is not modified here: seeds 1..200, the six pre-registered
/// interventions, the +20 rating delta, and the frozen bootstrap/permutation
/// settings all come from `t014_sensitivity.dart`.
///
/// ```
/// cd packages/simulation_core
/// dart run tool/amendment_004_t014_runner.dart <out.json>
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:simulation_core/simulation_core.dart';

import 't014_sensitivity.dart' as t014;

void main(List<String> args) {
  // Optional `--seed-offset=N` shifts the frozen seeds 1..200 to N+1..N+200
  // (Amendment 004 fresh held-out G9 evidence). Default 0 = frozen protocol.
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final offsets = args.where((a) => a.startsWith('--seed-offset='));
  if (positional.length != 1 || offsets.length > 1) {
    stderr.writeln(
      'usage: dart run tool/amendment_004_t014_runner.dart <out.json> [--seed-offset=N]',
    );
    exitCode = 64;
    return;
  }
  final outPath = positional.single;
  final seedOffset = offsets.isEmpty
      ? 0
      : int.parse(offsets.single.split('=').last);
  final seeds = [for (final s in t014.seeds) s + seedOffset];

  final league = const LeagueGenerator().generate(
    const GenerationConfig(seed: t014.leagueFixtureSeed),
  );
  final homeTeam = league.teams[0];
  final lineup = ActiveLineup.defaultFor(homeTeam);
  final subjects = t014.selectSubjects(lineup);
  final experiments = t014.buildExperiments(homeTeam, lineup, subjects);

  // Baseline arm is shared by every experiment and simulated once.
  final baseline = <int, t014.Arm>{};
  for (final seed in seeds) {
    final input = t014.buildInput(league, seed);
    baseline[seed] = t014.Arm(input, GameSimulator().simulate(input));
  }

  final summaries = <Map<String, Object?>>[];
  final perSeed = <Map<String, Object?>>[];

  for (final experiment in experiments) {
    final modified = t014.buildModifiedLeague(league, experiment.attributes);
    final deltas = <double>[];
    final secondaryDeltas = <double>[];
    final baselineRates = <double>[];
    final interventionRates = <double>[];
    final pooled = <String, int>{};
    final descriptiveBaseline = <String, int>{};
    final descriptiveIntervention = <String, int>{};
    var valid = 0;
    var zeroBaseline = 0;
    var zeroIntervention = 0;
    var zeroBoth = 0;

    for (final seed in seeds) {
      final baseArm = baseline[seed]!;
      final interventionInput = t014.buildInput(modified, seed);
      final interventionResult = GameSimulator().simulate(interventionInput);

      final baseObs = experiment.observe(baseArm.result, baseArm.input);
      final intObs = experiment.observe(interventionResult, interventionInput);

      final describe = experiment.describe;
      if (describe != null) {
        for (final entry in describe(baseArm.result, baseArm.input).entries) {
          descriptiveBaseline[entry.key] =
              (descriptiveBaseline[entry.key] ?? 0) + entry.value;
        }
        for (final entry in describe(
          interventionResult,
          interventionInput,
        ).entries) {
          descriptiveIntervention[entry.key] =
              (descriptiveIntervention[entry.key] ?? 0) + entry.value;
        }
      }

      if (baseObs.denominator == 0 && intObs.denominator == 0) {
        zeroBoth++;
        perSeed.add({
          'experiment': experiment.id,
          'seed': seed,
          'status': 'zeroBoth',
        });
        continue;
      }
      if (baseObs.denominator == 0) {
        zeroBaseline++;
        perSeed.add({
          'experiment': experiment.id,
          'seed': seed,
          'status': 'zeroBaseline',
        });
        continue;
      }
      if (intObs.denominator == 0) {
        zeroIntervention++;
        perSeed.add({
          'experiment': experiment.id,
          'seed': seed,
          'status': 'zeroIntervention',
        });
        continue;
      }

      valid++;
      pooled['baselineNumerator'] =
          (pooled['baselineNumerator'] ?? 0) + baseObs.numerator;
      pooled['baselineDenominator'] =
          (pooled['baselineDenominator'] ?? 0) + baseObs.denominator;
      pooled['interventionNumerator'] =
          (pooled['interventionNumerator'] ?? 0) + intObs.numerator;
      pooled['interventionDenominator'] =
          (pooled['interventionDenominator'] ?? 0) + intObs.denominator;

      final baseRate =
          baseObs.numerator / baseObs.denominator * experiment.scale;
      final intRate = intObs.numerator / intObs.denominator * experiment.scale;
      baselineRates.add(baseRate);
      interventionRates.add(intRate);
      deltas.add(intRate - baseRate);

      perSeed.add({
        'experiment': experiment.id,
        'seed': seed,
        'status': 'valid',
        'baselineNumerator': baseObs.numerator,
        'baselineDenominator': baseObs.denominator,
        'interventionNumerator': intObs.numerator,
        'interventionDenominator': intObs.denominator,
        'baselineMetric': baseRate,
        'interventionMetric': intRate,
        'pairedDifference': intRate - baseRate,
      });

      final secondary = experiment.secondary;
      if (secondary != null) {
        final baseSecondary = secondary(baseArm.result, baseArm.input).rate;
        final intSecondary = secondary(
          interventionResult,
          interventionInput,
        ).rate;
        if (baseSecondary != null && intSecondary != null) {
          secondaryDeltas.add((intSecondary - baseSecondary) * 100);
        }
      }
    }

    summaries.add(
      t014.summarize(
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

  t014.applyHolm(summaries);

  final payload = <String, Object?>{
    'runner': 'amendment_004_t014_runner.dart',
    'protocol': 't014-analysis-protocol.md (frozen, unmodified)',
    'leagueFixtureSeed': t014.leagueFixtureSeed,
    'seedOffset': seedOffset,
    'firstSeed': t014.firstSeed + seedOffset,
    'lastSeed': t014.lastSeed + seedOffset,
    'ratingDelta': t014.ratingDelta,
    'bootstrapSeed': t014.bootstrapSeed,
    'permutationSeed': t014.permutationSeed,
    'resamples': t014.resamples,
    'permutations': t014.permutations,
    'minimumValidPairs': t014.minimumValidPairs,
    'simulationVersion': gameSimulationVersion,
    'rulesVersion': gameRulesVersion,
    'eventSchemaVersion': gameEventSchemaVersion,
    'actionDurationModelVersion': gameActionDurationModelVersion,
    'subjects': {
      for (final entry in subjects.entries) entry.key: entry.value.id.value,
    },
    'summaries': summaries,
    'ac09': t014.ac09Verdict(summaries),
    'perSeed': perSeed,
  };

  File(outPath).writeAsStringSync(jsonEncode(payload));
  for (final summary in summaries) {
    stdout.writeln(
      '${summary['id']}: verdict=${summary['verdict']} '
      'meanDiff=${summary['meanDifference']} '
      'p=${summary['pValue']} holm=${summary['holmAdjustedP']}',
    );
  }
  stdout.writeln('ac09=${t014.ac09Verdict(summaries)}');
  stdout.writeln('wrote $outPath');
}
