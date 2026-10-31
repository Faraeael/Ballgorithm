/// Amendment 004 pilot evidence runner (version-agnostic).
///
/// Deterministic, read-only experimental harness. Runs the pre-registered
/// 280-game DEVELOPMENT pilot cohort (56 directed matchups x first 5 slots) for
/// whichever `simulation_core` package it is compiled against, and emits a
/// complete per-game JSON record set sufficient to independently recompute
/// every frozen Amendment 004 pilot gate.
///
/// Usage (from the package root of the intended version):
///
/// ```
/// cd packages/simulation_core          # or an isolated checkout of 9f8458a
/// dart run tool/amendment_004_pilot_runner.dart <output.json>
/// ```
///
/// The runner never mutates state, never tunes parameters and never chooses
/// seeds: the cohort is fixed by the frozen schedule below.
library;

import 'dart:convert';
import 'dart:io';

import 'package:simulation_core/simulation_core.dart';

import 't015_metrics.dart';

/// Frozen M001 league fixture seed used by every M002 calibration artifact.
const int leagueSeed = 20261028;

/// Directed matchups: 28 unordered pairs x 2 orientations.
const int directedMatchups = 56;

/// Development slots consumed by the pilot (s in 0..4).
const int pilotSlots = 5;

/// Frozen Amendment 003 development seed schedule.
int developmentSeed(int matchupIndex, int slot) =>
    1 + ((97 * matchupIndex + 17 * slot) % 200);

/// Slots per matchup in the fresh held-out cohort (s in 0..19).
const int heldoutSlots = 20;

/// Amendment 004 fresh held-out seed schedule: i = 20*m + s.
int heldoutSeed(int matchupIndex, int slot) =>
    10001 + ((137 * (20 * matchupIndex + slot) + 23) % 600);

void main(List<String> args) {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final cohorts = args.where((a) => a.startsWith('--cohort='));
  final cohort = cohorts.isEmpty ? 'pilot' : cohorts.single.split('=').last;
  if (positional.length != 1 ||
      cohorts.length > 1 ||
      (cohort != 'pilot' && cohort != 'heldout')) {
    stderr.writeln(
      'usage: dart run tool/amendment_004_pilot_runner.dart <out.json> [--cohort=pilot|heldout]',
    );
    exitCode = 64;
    return;
  }
  final outPath = positional.single;
  final isHeldout = cohort == 'heldout';
  final slots = isHeldout ? heldoutSlots : pilotSlots;

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

  final rows = <Map<String, Object?>>[];
  var pairIndex = 0;

  for (var i = 0; i < 8; i++) {
    for (var j = i + 1; j < 8; j++) {
      for (var orientation = 0; orientation < 2; orientation++) {
        final home = orientation == 0 ? teams[i] : teams[j];
        final away = orientation == 0 ? teams[j] : teams[i];
        final matchupIndex = pairIndex * 2 + orientation;

        for (var slot = 0; slot < slots; slot++) {
          final globalSlot = 20 * matchupIndex + slot;
          final seed = isHeldout
              ? heldoutSeed(matchupIndex, slot)
              : developmentSeed(matchupIndex, slot);
          final gameId =
              '${isHeldout ? 'am4h' : 'am4'}-$globalSlot-$matchupIndex-$seed';

          final input = GameInput.create(
            gameId: gameId,
            league: league,
            homeTeamId: home.id,
            awayTeamId: away.id,
            homeLineup: ActiveLineup.defaultFor(home),
            awayLineup: ActiveLineup.defaultFor(away),
            seed: seed,
            rules: GameRules.standard,
          );

          final trace = <PhaseTraceRecord>[];
          final result = GameSimulator(onPhaseTrace: trace.add).simulate(input);

          // Replay and accounting must reconcile before any row is recorded.
          final validated = GameEventReducer.validate(input, result.ledger);
          final accounted = EventAccounting.aggregate(validated);
          final accountedHome = accounted.teams[home.id.value]!.points;
          final accountedAway = accounted.teams[away.id.value]!.points;
          if (accountedHome != result.homeScore ||
              accountedAway != result.awayScore) {
            throw StateError('accounting mismatch in $gameId');
          }

          final homePoss = possessionCounts(result.events, home.id);
          final awayPoss = possessionCounts(result.events, away.id);
          final homeBox = result.boxScore.teams[home.id.value]!;
          final awayBox = result.boxScore.teams[away.id.value]!;

          var shotClockTov = 0;
          var stealTov = 0;
          var nonStealTov = 0;
          var offensiveFoulTov = 0;
          var homeNonShootingFouls = 0;
          var awayNonShootingFouls = 0;

          for (final event in result.events) {
            if (event is Turnover) {
              switch (event.reason) {
                case TurnoverReason.shotClock:
                  shotClockTov++;
                case TurnoverReason.steal:
                  stealTov++;
                case TurnoverReason.nonSteal:
                  nonStealTov++;
                case TurnoverReason.offensiveFoul:
                  offensiveFoulTov++;
              }
            } else if (event is PersonalFoul &&
                event.kind == FoulKind.nonShooting) {
              if (event.committingTeamId == home.id.value) {
                homeNonShootingFouls++;
              } else {
                awayNonShootingFouls++;
              }
            }
          }

          // Phase denominators. A sampled phase "reaches action selection" when
          // the orchestrator actually draws a terminal action for it.
          var sampledPhases = 0;
          var actionPhases = 0;
          var orebPhases = 0;
          var orebViolations = 0;
          var retFoulPhases = 0;
          var retFoulViolations = 0;
          var retFoul14Phases = 0;
          var retFoul14Violations = 0;
          var freshPhases = 0;
          var freshViolations = 0;

          for (final record in trace) {
            sampledPhases++;
            final violation =
                record.resolution == PhaseResolution.shotClockOvershoot ||
                record.resolution == PhaseResolution.shotClockExpiryNoAttempt;

            switch (record.resolution) {
              case PhaseResolution.shotClockOvershoot:
              case PhaseResolution.gameClockFirst:
              case PhaseResolution.simultaneousExpiry:
                break;
              case PhaseResolution.legalShot:
              case PhaseResolution.legalFoul:
              case PhaseResolution.legalTurnover:
              case PhaseResolution.shotClockExpiryNoAttempt:
              case PhaseResolution.actionDiscardedAtHorn:
                actionPhases++;
            }

            switch (record.context) {
              case 'oreb':
                orebPhases++;
                if (violation) orebViolations++;
              case 'retainedFoul':
                retFoulPhases++;
                if (violation) retFoulViolations++;
                if (record.shotClockBefore == 14) {
                  retFoul14Phases++;
                  if (violation) retFoul14Violations++;
                }
              case 'fresh':
                freshPhases++;
                if (violation) freshViolations++;
              default:
                break;
            }
          }

          rows.add(<String, Object?>{
            'slot': globalSlot,
            'matchupIndex': matchupIndex,
            'pairIndex': pairIndex,
            'orientation': orientation,
            'seed': seed,
            'gameId': gameId,
            'homeTeamId': home.id.value,
            'awayTeamId': away.id.value,
            // --- result header ---
            'simulationVersion': gameSimulationVersion,
            'rulesVersion': gameRulesVersion,
            'eventSchemaVersion': gameEventSchemaVersion,
            'actionDurationModelVersion': gameActionDurationModelVersion,
            'fingerprintVersion': gameFingerprintVersion,
            'inputFingerprint': GameFingerprint.of(input),
            // --- score / clocks ---
            'homeScore': result.homeScore,
            'awayScore': result.awayScore,
            'combinedPoints': result.homeScore + result.awayScore,
            'periods': result.periodsPlayed,
            'overtimes': result.overtimes,
            'events': result.events.length,
            // --- possessions ---
            'homeStarted': homePoss.started,
            'awayStarted': awayPoss.started,
            'homeCompleted': homePoss.completed,
            'awayCompleted': awayPoss.completed,
            'completed': homePoss.completed + awayPoss.completed,
            'homePeriodEnd': homePoss.periodEnd,
            'awayPeriodEnd': awayPoss.periodEnd,
            // --- shooting ---
            'homeFga': homeBox.fga,
            'awayFga': awayBox.fga,
            'fga': homeBox.fga + awayBox.fga,
            'homeFgm': homeBox.fgm,
            'awayFgm': awayBox.fgm,
            'fgm': homeBox.fgm + awayBox.fgm,
            'homeThreePa': homeBox.threePa,
            'awayThreePa': awayBox.threePa,
            'threePa': homeBox.threePa + awayBox.threePa,
            'homeThreePm': homeBox.threePm,
            'awayThreePm': awayBox.threePm,
            'threePm': homeBox.threePm + awayBox.threePm,
            'homeFta': homeBox.fta,
            'awayFta': awayBox.fta,
            'fta': homeBox.fta + awayBox.fta,
            'homeFtm': homeBox.ftm,
            'awayFtm': awayBox.ftm,
            'ftm': homeBox.ftm + awayBox.ftm,
            // --- rebounds ---
            'homeOreb': homeBox.oreb,
            'awayOreb': awayBox.oreb,
            'oreb': homeBox.oreb + awayBox.oreb,
            'homeDreb': homeBox.dreb,
            'awayDreb': awayBox.dreb,
            'dreb': homeBox.dreb + awayBox.dreb,
            // --- turnovers ---
            'homeTov': homeBox.turnovers,
            'awayTov': awayBox.turnovers,
            'tov': homeBox.turnovers + awayBox.turnovers,
            'shotClockTov': shotClockTov,
            'stealTov': stealTov,
            'nonStealTov': nonStealTov,
            'offensiveFoulTov': offensiveFoulTov,
            // --- fouls ---
            'homePf': homeBox.personalFouls,
            'awayPf': awayBox.personalFouls,
            'personalFouls': homeBox.personalFouls + awayBox.personalFouls,
            'homeNonShootingFouls': homeNonShootingFouls,
            'awayNonShootingFouls': awayNonShootingFouls,
            'nonShootingFouls': homeNonShootingFouls + awayNonShootingFouls,
            // --- phase denominators ---
            'sampledPhases': sampledPhases,
            'actionPhases': actionPhases,
            'freshPhases': freshPhases,
            'freshViolations': freshViolations,
            'orebPhases': orebPhases,
            'orebViolations': orebViolations,
            'retFoulPhases': retFoulPhases,
            'retFoulViolations': retFoulViolations,
            'retFoul14Phases': retFoul14Phases,
            'retFoul14Violations': retFoul14Violations,
          });
        }
      }
      // One unordered pair was just played in both orientations; advance once.
      pairIndex++;
    }
  }

  if (rows.length != directedMatchups * slots) {
    stderr.writeln(
      'expected ${directedMatchups * slots} rows, produced ${rows.length}',
    );
    exitCode = 3;
    return;
  }

  final payload = <String, Object?>{
    'runner': 'amendment_004_pilot_runner.dart',
    'leagueSeed': leagueSeed,
    'cohort': cohort,
    'seedSchedule': isHeldout
        ? '10001 + ((137*(20*m + s) + 23) mod 600)'
        : '1 + ((97*m + 17*s) mod 200)',
    'directedMatchups': directedMatchups,
    'slotsPerMatchup': slots,
    'rows': rows,
    'totals': {
      'sampledPhases': rows.fold<int>(
        0,
        (a, r) => a + (r['sampledPhases']! as int),
      ),
      'actionPhases': rows.fold<int>(
        0,
        (a, r) => a + (r['actionPhases']! as int),
      ),
      'freshPhases': rows.fold<int>(
        0,
        (a, r) => a + (r['freshPhases']! as int),
      ),
      'orebPhases': rows.fold<int>(0, (a, r) => a + (r['orebPhases']! as int)),
      'orebViolations': rows.fold<int>(
        0,
        (a, r) => a + (r['orebViolations']! as int),
      ),
      'retFoulPhases': rows.fold<int>(
        0,
        (a, r) => a + (r['retFoulPhases']! as int),
      ),
      'retFoul14Phases': rows.fold<int>(
        0,
        (a, r) => a + (r['retFoul14Phases']! as int),
      ),
      'retFoul14Violations': rows.fold<int>(
        0,
        (a, r) => a + (r['retFoul14Violations']! as int),
      ),
      'completed': rows.fold<int>(0, (a, r) => a + (r['completed']! as int)),
      'tov': rows.fold<int>(0, (a, r) => a + (r['tov']! as int)),
      'offensiveFoulTov': rows.fold<int>(
        0,
        (a, r) => a + (r['offensiveFoulTov']! as int),
      ),
      'stealTov': rows.fold<int>(0, (a, r) => a + (r['stealTov']! as int)),
      'nonStealTov': rows.fold<int>(
        0,
        (a, r) => a + (r['nonStealTov']! as int),
      ),
      'shotClockTov': rows.fold<int>(
        0,
        (a, r) => a + (r['shotClockTov']! as int),
      ),
      'fga': rows.fold<int>(0, (a, r) => a + (r['fga']! as int)),
      'fgm': rows.fold<int>(0, (a, r) => a + (r['fgm']! as int)),
      'threePa': rows.fold<int>(0, (a, r) => a + (r['threePa']! as int)),
      'threePm': rows.fold<int>(0, (a, r) => a + (r['threePm']! as int)),
    },
  };

  File(outPath).writeAsStringSync(jsonEncode(payload));
  stdout.writeln(
    'wrote ${rows.length} rows for simulation v$gameSimulationVersion to $outPath',
  );
}
