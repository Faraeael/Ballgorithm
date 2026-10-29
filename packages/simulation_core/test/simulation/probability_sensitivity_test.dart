import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'probability_support.dart';

/// Aggregate, paired-seed directional probes (T008 development diagnostics).
///
/// These are NOT the formal T014/AC09 experiments: no bootstrap confidence
/// intervals, no Holm correction, no pre-registered acceptance thresholds. They
/// only show that the documented coefficient signs survive aggregate sampling.
const int _seeds = 400;
const int _drawsPerSeed = 50;

typedef _Probe = ({double mean, int counted, int skipped});

void main() {
  final model = BasketballProbabilityModel();

  _Probe pairedMean(
    String label,
    double Function(int seed) baseline,
    double Function(int seed) mutant,
  ) {
    var total = 0.0;
    var counted = 0;
    var skipped = 0;
    for (var seed = 1; seed <= _seeds; seed++) {
      final base = baseline(seed);
      final changed = mutant(seed);
      if (base.isNaN || changed.isNaN) {
        skipped++;
        continue;
      }
      total += changed - base;
      counted++;
    }
    final mean = counted == 0 ? double.nan : total / counted;
    // ignore: avoid_print
    print(
      'PROBE $label seeds=$counted skipped=$skipped '
      'meanDiff=${mean.toStringAsFixed(5)}',
    );
    return (mean: mean, counted: counted, skipped: skipped);
  }

  double rate(int hits, int attempts) =>
      attempts == 0 ? double.nan : hits / attempts;

  group('paired-seed sensitivity probes', () {
    test('threePoint raises three-point conversion', () {
      final base = teamOnCourt('home');
      final mutant = teamOnCourt(
        'home',
        overrides: {Position.pg: attrs(threePoint: 70)},
      );
      final defense = teamOnCourt('away');

      double shooter3pt(TeamOnCourt squad, int seed) {
        var attempts = 0;
        var makes = 0;
        final rng = DeterministicRandom(seed);
        for (var i = 0; i < _drawsPerSeed; i++) {
          final action = model.selectFinalTickAction(
            offense: squad,
            defense: defense,
            rng: rng,
          );
          if (action.shooterId.value != 'home-PG') continue;
          if (action.zone != ShotZone.three) continue;
          attempts++;
          if (action.made) makes++;
        }
        return rate(makes, attempts);
      }

      final probe = pairedMean(
        'threePoint +20 -> PG 3PT%',
        (seed) => shooter3pt(base, seed),
        (seed) => shooter3pt(mutant, seed),
      );
      expect(probe.counted, greaterThan(_seeds ~/ 2));
      expect(probe.mean, greaterThan(0));
    });

    test('insideScoring raises rim conversion', () {
      final base = teamOnCourt('home');
      final mutant = teamOnCourt(
        'home',
        overrides: {Position.pg: attrs(insideScoring: 70)},
      );
      final defense = teamOnCourt('away');

      double rimPct(TeamOnCourt squad, int seed) {
        var attempts = 0;
        var makes = 0;
        final rng = DeterministicRandom(seed);
        for (var i = 0; i < _drawsPerSeed; i++) {
          final action = model.selectFinalTickAction(
            offense: squad,
            defense: defense,
            rng: rng,
          );
          if (action.shooterId.value != 'home-PG') continue;
          if (action.zone != ShotZone.inside) continue;
          attempts++;
          if (action.made) makes++;
        }
        return rate(makes, attempts);
      }

      final probe = pairedMean(
        'insideScoring +20 -> PG rim FG%',
        (seed) => rimPct(base, seed),
        (seed) => rimPct(mutant, seed),
      );
      expect(probe.counted, greaterThan(_seeds ~/ 2));
      expect(probe.mean, greaterThan(0));
    });

    test('midrange raises midrange selection', () {
      final base = teamOnCourt('home');
      final mutant = teamOnCourt(
        'home',
        overrides: {Position.pg: attrs(midrange: 70)},
      );
      final defense = teamOnCourt('away');

      double midrangeShare(TeamOnCourt squad, int seed) {
        var attempts = 0;
        var midrange = 0;
        final rng = DeterministicRandom(seed);
        for (var i = 0; i < _drawsPerSeed; i++) {
          final action = model.selectFinalTickAction(
            offense: squad,
            defense: defense,
            rng: rng,
          );
          if (action.shooterId.value != 'home-PG') continue;
          attempts++;
          if (action.zone == ShotZone.midrange) midrange++;
        }
        return rate(midrange, attempts);
      }

      final probe = pairedMean(
        'midrange +20 -> PG midrange share',
        (seed) => midrangeShare(base, seed),
        (seed) => midrangeShare(mutant, seed),
      );
      expect(probe.counted, greaterThan(_seeds ~/ 2));
      expect(probe.mean, greaterThan(0));
    });

    test('freeThrow raises free-throw accuracy', () {
      final base = teamOnCourt('home');
      final mutant = teamOnCourt(
        'home',
        overrides: {Position.c: attrs(freeThrow: 70)},
      );

      double ftPct(TeamOnCourt squad, int seed) {
        var attempts = 0;
        var makes = 0;
        final rng = DeterministicRandom(seed);
        for (var i = 0; i < _drawsPerSeed ~/ 2; i++) {
          final group = model.resolveFreeThrows(
            offense: squad,
            shooter: squad.lineup.players[4],
            attempts: 2,
            rng: rng,
          );
          attempts += group.attempts;
          makes += group.madeCount;
        }
        return rate(makes, attempts);
      }

      final probe = pairedMean(
        'freeThrow +20 -> C FT%',
        (seed) => ftPct(base, seed),
        (seed) => ftPct(mutant, seed),
      );
      expect(probe.counted, _seeds);
      expect(probe.mean, greaterThan(0));
    });

    test('rebounding raises the big man rebound share', () {
      final base = teamOnCourt('home');
      final mutant = teamOnCourt(
        'home',
        overrides: {Position.c: attrs(rebounding: 70)},
      );
      final defense = teamOnCourt('away');

      double centerShare(TeamOnCourt squad, int seed) {
        var rebounds = 0;
        final rng = DeterministicRandom(seed);
        for (var i = 0; i < _drawsPerSeed; i++) {
          final rebound = model.resolveRebound(
            offense: squad,
            defense: defense,
            zone: ShotZone.midrange,
            rng: rng,
          );
          if (rebound.playerId.value == 'home-C') rebounds++;
        }
        return rebounds / _drawsPerSeed;
      }

      final probe = pairedMean(
        'rebounding +20 -> C rebound share',
        (seed) => centerShare(base, seed),
        (seed) => centerShare(mutant, seed),
      );
      expect(probe.counted, _seeds);
      expect(probe.mean, greaterThan(0));
    });

    test('perimeterDefense lowers opponent three-point accuracy', () {
      final shooters = teamOnCourt('home');
      final base = teamOnCourt('away');
      final mutant = teamOnCourt(
        'away',
        overrides: {
          for (final position in Position.values)
            position: attrs(perimeterDefense: 70),
        },
      );

      double threePct(TeamOnCourt defenders, int seed) {
        var attempts = 0;
        var makes = 0;
        final rng = DeterministicRandom(seed);
        for (var i = 0; i < _drawsPerSeed; i++) {
          final action = model.selectFinalTickAction(
            offense: shooters,
            defense: defenders,
            rng: rng,
          );
          if (action.zone != ShotZone.three) continue;
          attempts++;
          if (action.made) makes++;
        }
        return rate(makes, attempts);
      }

      final probe = pairedMean(
        'perimeterDefense +20 -> opponent 3PT%',
        (seed) => threePct(base, seed),
        (seed) => threePct(mutant, seed),
      );
      expect(probe.counted, _seeds);
      expect(probe.mean, lessThan(0));
    });

    test('interiorDefense raises the block rate', () {
      final shooters = teamOnCourt('home');
      final base = teamOnCourt('away');
      final mutant = teamOnCourt(
        'away',
        overrides: {
          for (final position in Position.values)
            position: attrs(interiorDefense: 70),
        },
      );

      double blockRate(TeamOnCourt defenders, int seed) {
        var attempts = 0;
        var blocks = 0;
        final rng = DeterministicRandom(seed);
        for (var i = 0; i < _drawsPerSeed; i++) {
          final action = model.selectFinalTickAction(
            offense: shooters,
            defense: defenders,
            rng: rng,
          );
          attempts++;
          if (action.blockedById != null) blocks++;
        }
        return blocks / attempts;
      }

      final probe = pairedMean(
        'interiorDefense +20 -> block rate',
        (seed) => blockRate(base, seed),
        (seed) => blockRate(mutant, seed),
      );
      expect(probe.counted, _seeds);
      expect(probe.mean, greaterThan(0));
    });

    test('ballHandling lowers team turnover rate', () {
      final base = teamOnCourt('home');
      final mutant = teamOnCourt(
        'home',
        overrides: {
          for (final position in Position.values)
            position: attrs(ballHandling: 70),
        },
      );
      final defense = teamOnCourt('away');

      double turnoverRate(TeamOnCourt squad, int seed) {
        var turnovers = 0;
        final rng = DeterministicRandom(seed);
        for (var i = 0; i < _drawsPerSeed; i++) {
          final action = model.selectAction(
            offense: squad,
            defense: defense,
            phase: PhaseKind.halfCourt,
            rng: rng,
          );
          if (action is TurnoverAction) turnovers++;
        }
        return turnovers / _drawsPerSeed;
      }

      final probe = pairedMean(
        'ballHandling +20 -> team TOV/action',
        (seed) => turnoverRate(base, seed),
        (seed) => turnoverRate(mutant, seed),
      );
      expect(probe.counted, _seeds);
      expect(probe.mean, lessThan(0));
    });

    test('passing raises the assisted-shot share', () {
      final base = teamOnCourt('home');
      final mutant = teamOnCourt(
        'home',
        overrides: {
          for (final position in Position.values) position: attrs(passing: 70),
        },
      );
      final defense = teamOnCourt('away');

      double assistShare(TeamOnCourt squad, int seed) {
        var makes = 0;
        var assisted = 0;
        final rng = DeterministicRandom(seed);
        for (var i = 0; i < _drawsPerSeed; i++) {
          final action = model.selectFinalTickAction(
            offense: squad,
            defense: defense,
            rng: rng,
          );
          if (!action.made) continue;
          makes++;
          if (action.assistedById != null) assisted++;
        }
        return rate(assisted, makes);
      }

      final probe = pairedMean(
        'passing +20 -> assisted FGM share',
        (seed) => assistShare(base, seed),
        (seed) => assistShare(mutant, seed),
      );
      expect(probe.counted, _seeds);
      expect(probe.mean, greaterThan(0));
    });

    test('athleticism raises the offensive-rebound share', () {
      final base = teamOnCourt('home');
      final mutant = teamOnCourt(
        'home',
        overrides: {
          for (final position in Position.values)
            position: attrs(athleticism: 70),
        },
      );
      final defense = teamOnCourt('away');

      double orebShare(TeamOnCourt squad, int seed) {
        var offensive = 0;
        final rng = DeterministicRandom(seed);
        for (var i = 0; i < _drawsPerSeed; i++) {
          final rebound = model.resolveRebound(
            offense: squad,
            defense: defense,
            zone: ShotZone.inside,
            rng: rng,
          );
          if (rebound.offensive) offensive++;
        }
        return offensive / _drawsPerSeed;
      }

      final probe = pairedMean(
        'athleticism +20 -> OREB share',
        (seed) => orebShare(base, seed),
        (seed) => orebShare(mutant, seed),
      );
      expect(probe.counted, _seeds);
      expect(probe.mean, greaterThan(0));
    });

    test('basketballIQ lowers team turnover rate', () {
      final base = teamOnCourt('home');
      final mutant = teamOnCourt(
        'home',
        overrides: {
          for (final position in Position.values)
            position: attrs(basketballIQ: 70),
        },
      );
      final defense = teamOnCourt('away');

      double turnoverRate(TeamOnCourt squad, int seed) {
        var turnovers = 0;
        final rng = DeterministicRandom(seed);
        for (var i = 0; i < _drawsPerSeed; i++) {
          final action = model.selectAction(
            offense: squad,
            defense: defense,
            phase: PhaseKind.halfCourt,
            rng: rng,
          );
          if (action is TurnoverAction) turnovers++;
        }
        return turnovers / _drawsPerSeed;
      }

      final probe = pairedMean(
        'basketballIQ +20 -> team TOV/action',
        (seed) => turnoverRate(base, seed),
        (seed) => turnoverRate(mutant, seed),
      );
      expect(probe.counted, _seeds);
      expect(probe.mean, lessThan(0));
    });
  });
}
