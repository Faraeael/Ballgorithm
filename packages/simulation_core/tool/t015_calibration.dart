/// T015 calibration harness: 1,120-game deterministic sample.
///
/// ```
/// cd packages/simulation_core
/// dart run tool/t015_calibration.dart
/// ```
///
/// Writes `specs/002-possession-simulation/t015-game-sample.csv`,
/// `t015-statistical-summary.json` and `t015-diagnostic-cases.md`.
/// It never writes ledgers, never changes gameplay and never prints to the
/// repository outside those three artifact paths.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';

import 't015_metrics.dart';

const int leagueSeed = 20261028;
const int seedsPerMatchup = 20;
const int expectedGames = 1120;

List<int> seedsFor(int matchupIndex) => [
  for (var slot = 0; slot < seedsPerMatchup; slot++)
    1 + ((97 * matchupIndex + 17 * slot) % 200),
];

void main() {
  final league = const LeagueGenerator().generate(
    const GenerationConfig(seed: leagueSeed),
  );
  final teams = [...league.teams]
    ..sort((a, b) => a.id.value.compareTo(b.id.value));
  if (teams.length < 8) {
    stderr.writeln('Expected 8 teams, found ${teams.length}');
    exitCode = 2;
    return;
  }

  final rows = <GameRow>[];
  final failures = <Map<String, Object?>>[];
  final foulIssues = <Map<String, Object?>>[];
  final structuralIssues = <Map<String, Object?>>[];
  var gameIndex = 0;

  final teamMetric = <String, List<double>>{};
  final homeMetric = <String, List<double>>{};
  final awayMetric = <String, List<double>>{};
  final gameMetric = <String, List<double>>{};
  final positionMetric = <String, Map<String, List<double>>>{};
  final teamAggregate = <String, List<double>>{};
  final strongMetric = <String, List<double>>{};
  final weakMetric = <String, List<double>>{};
  final turnoverTotals = <String, int>{
    'steal': 0,
    'nonSteal': 0,
    'offensiveFoul': 0,
    'shotClock': 0,
  };
  final shotEntries = <String, int>{
    'start24': 0,
    'oreb14': 0,
    'retainedFoul': 0,
  };
  final floorEntries = <int, int>{};
  final floorTurnovers = <int, int>{};
  final shotTurnovers = <String, int>{
    'start24': 0,
    'oreb14': 0,
    'retainedFoul': 0,
    'other': 0,
  };
  final foulTotals = <String, int>{
    'shooting': 0,
    'nonShooting': 0,
    'offensive': 0,
    'bonusAwards': 0,
  };
  var homeWins = 0;
  var overtimeGames = 0;
  var maxOvertimes = 0;
  var pointsOutsideRange = 0;
  var combinedPointsTotal = 0.0;
  var completedGames = 0;
  final representatives = <String, GameRow>{};
  final traceAggregate = TraceAggregate();

  var pairIndex = 0;
  for (var i = 0; i < teams.length; i++) {
    for (var j = i + 1; j < teams.length; j++) {
      for (var orientation = 0; orientation < 2; orientation++) {
        final home = orientation == 0 ? teams[i] : teams[j];
        final away = orientation == 0 ? teams[j] : teams[i];
        final matchupIndex = pairIndex * 2 + orientation;
        for (final seed in seedsFor(matchupIndex)) {
          final gameId = 't015-$matchupIndex-$seed';
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
          gameIndex++;
          try {
            final trace = <PhaseTraceRecord>[];
            final result = GameSimulator(
              onPhaseTrace: trace.add,
            ).simulate(input);
            traceAggregate.add(trace, input, result, gameId);
            final issues = verifyGame(input, result);
            if (issues.isNotEmpty) {
              structuralIssues.add({
                'gameId': gameId,
                'seed': seed,
                'issues': issues,
              });
            }
            final audit = foulAudit(result.events, input.rules);
            if (audit.isNotEmpty) {
              foulIssues.add({'gameId': gameId, 'seed': seed, 'issues': audit});
            }
            final row = GameRow(
              index: gameIndex,
              matchupIndex: matchupIndex,
              seed: seed,
              input: input,
              result: result,
              digest: ledgerDigest(result.ledger),
            );
            rows.add(row);
            completedGames++;
            _accumulate(
              row,
              teamMetric: teamMetric,
              homeMetric: homeMetric,
              awayMetric: awayMetric,
              gameMetric: gameMetric,
              positionMetric: positionMetric,
              teamAggregate: teamAggregate,
              strongMetric: strongMetric,
              weakMetric: weakMetric,
              turnoverTotals: turnoverTotals,
              shotEntries: shotEntries,
              floorEntries: floorEntries,
              floorTurnovers: floorTurnovers,
              shotTurnovers: shotTurnovers,
              foulTotals: foulTotals,
            );
            if (result.homeScore > result.awayScore) homeWins++;
            if (result.overtimes > 0) overtimeGames++;
            maxOvertimes = math.max(maxOvertimes, result.overtimes);
            final combined = result.homeScore + result.awayScore;
            combinedPointsTotal += combined;
            if (combined < 90 || combined > 340) pointsOutsideRange++;
            _considerRepresentative(representatives, row, combined);
          } on GameValidationException catch (error) {
            failures.add({
              'gameId': gameId,
              'matchupIndex': matchupIndex,
              'seed': seed,
              'codes': [for (final code in error.codes) code.name],
              'firstIssue': error.issues.first.toString(),
            });
          }
        }
      }
      pairIndex++;
    }
  }

  // Determinism: ten pinned corpus games re-simulated and compared.
  final determinism = <Map<String, Object?>>[];
  for (var i = 0; i < 10; i++) {
    final index = (i * (rows.length - 1)) ~/ 9;
    final row = rows[index];
    final again = GameSimulator().simulate(row.input);
    final sameDigest = ledgerDigest(again.ledger) == row.digest;
    determinism.add({
      'gameId': row.input.gameId,
      'seed': row.input.seed,
      'digest': row.digest,
      'identical': sameDigest,
    });
  }

  final summary = _buildSummary(
    rows: rows,
    failures: failures,
    structuralIssues: structuralIssues,
    foulIssues: foulIssues,
    teamMetric: teamMetric,
    homeMetric: homeMetric,
    awayMetric: awayMetric,
    gameMetric: gameMetric,
    positionMetric: positionMetric,
    teamAggregate: teamAggregate,
    strongMetric: strongMetric,
    weakMetric: weakMetric,
    turnoverTotals: turnoverTotals,
    shotEntries: shotEntries,
    floorEntries: floorEntries,
    floorTurnovers: floorTurnovers,
    shotTurnovers: shotTurnovers,
    foulTotals: foulTotals,
    homeWins: homeWins,
    overtimeGames: overtimeGames,
    maxOvertimes: maxOvertimes,
    pointsOutsideRange: pointsOutsideRange,
    combinedPointsTotal: combinedPointsTotal,
    completedGames: completedGames,
    determinism: determinism,
    traceAggregate: traceAggregate,
    league: league,
    teams: teams,
  );

  final outDir = Directory(
    '${Directory.current.path}/../../specs/002-possession-simulation',
  );
  File('${outDir.path}/t015-game-sample.csv').writeAsStringSync(_csv(rows));
  File(
    '${outDir.path}/t015-statistical-summary.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
  File('${outDir.path}/t015-diagnostic-cases.md').writeAsStringSync(
    _diagnostics(representatives, rows, league, traceAggregate),
  );

  stdout.writeln(
    'T015: planned=$expectedGames completed=$completedGames '
    'failures=${failures.length} homeWins=$homeWins '
    'overtimeGames=$overtimeGames structural=${structuralIssues.length} '
    'foulAudit=${foulIssues.length}',
  );
  stdout.writeln('artifacts written to ${outDir.path}');
}

final class TraceAggregate {
  int records = 0;
  final Map<String, int> kindCounts = {};
  final Map<String, Map<int, int>> durationByKind = {};
  final Map<PhaseResolution, int> resolutionCounts = {};
  final Map<int, int> exactExpiryByShotClock = {};
  final Map<int, int> sampledPhasesByShotClock = {};
  final Map<int, int> overshootByShotClock = {};
  final Map<int, int> gameClockFirstByShotClock = {};
  final Map<int, int> simultaneousByShotClock = {};
  final Map<int, int> hornEligiblePhases = {};
  final List<Map<String, Object?>> floor22Cases = [];

  void _bump(Map<int, int> map, int key) => map[key] = (map[key] ?? 0) + 1;

  void add(
    List<PhaseTraceRecord> trace,
    GameInput input,
    GameResult result,
    String gameId,
  ) {
    for (final record in trace) {
      records++;
      kindCounts[record.kind] = (kindCounts[record.kind] ?? 0) + 1;
      durationByKind.putIfAbsent(record.kind, () => {})[record.plannedSeconds] =
          (durationByKind[record.kind]![record.plannedSeconds] ?? 0) + 1;
      resolutionCounts[record.resolution] =
          (resolutionCounts[record.resolution] ?? 0) + 1;
      _bump(sampledPhasesByShotClock, record.shotClockBefore);
      if (record.gameClockBefore <= record.shotClockBefore) {
        _bump(hornEligiblePhases, record.shotClockBefore);
      }
      if (record.resolution == PhaseResolution.shotClockExpiryNoAttempt) {
        exactExpiryByShotClock[record.shotClockBefore] =
            (exactExpiryByShotClock[record.shotClockBefore] ?? 0) + 1;
      }
      if (record.resolution == PhaseResolution.shotClockOvershoot) {
        _bump(overshootByShotClock, record.shotClockBefore);
      }
      if (record.resolution == PhaseResolution.gameClockFirst) {
        _bump(gameClockFirstByShotClock, record.shotClockBefore);
      }
      if (record.resolution == PhaseResolution.simultaneousExpiry) {
        _bump(simultaneousByShotClock, record.shotClockBefore);
      }
      if (record.shotClockBefore == 22 &&
          record.resolution == PhaseResolution.shotClockExpiryNoAttempt) {
        final expectedClock = record.gameClockBefore - record.plannedSeconds;
        final turnover = result.events
            .whereType<Turnover>()
            .where(
              (event) =>
                  event.reason == TurnoverReason.shotClock &&
                  event.period == record.period &&
                  event.gameClock == expectedClock,
            )
            .firstOrNull;
        floor22Cases.add({
          'gameId': gameId,
          'seed': input.seed,
          'period': record.period,
          'kind': record.kind,
          'plannedSeconds': record.plannedSeconds,
          'gameClockBefore': record.gameClockBefore,
          'shotClockBefore': record.shotClockBefore,
          'resolution': record.resolution.name,
          'turnoverSequence': turnover?.sequence,
          'turnoverGameClock': turnover?.gameClock,
        });
      }
    }
  }

  Map<String, Object?> toJson() => {
    'records': records,
    'kindCounts': kindCounts,
    'kindShare': records == 0
        ? null
        : {
            for (final entry in kindCounts.entries)
              entry.key: entry.value / records,
          },
    'durationByKind': {
      for (final entry in durationByKind.entries)
        entry.key: {
          for (final bucket in entry.value.entries)
            '${bucket.key}': bucket.value,
        },
    },
    'resolutionCounts': {
      for (final entry in resolutionCounts.entries) entry.key.name: entry.value,
    },
    'exactExpiryByShotClock': {
      for (final entry in exactExpiryByShotClock.entries)
        '${entry.key}': entry.value,
    },
    'byPreDrawShotClock': [
      for (var seconds = 1; seconds <= 24; seconds++)
        {
          'shotClockSeconds': seconds,
          'sampledPhases': sampledPhasesByShotClock[seconds] ?? 0,
          'shotClockEligiblePhases':
              (sampledPhasesByShotClock[seconds] ?? 0) -
              (hornEligiblePhases[seconds] ?? 0),
          'overshoots': overshootByShotClock[seconds] ?? 0,
          'overshootRate':
              ((sampledPhasesByShotClock[seconds] ?? 0) -
                      (hornEligiblePhases[seconds] ?? 0)) <=
                  0
              ? null
              : (overshootByShotClock[seconds] ?? 0) /
                    ((sampledPhasesByShotClock[seconds] ?? 0) -
                        (hornEligiblePhases[seconds] ?? 0)),
          'analyticSingleDrawOvershoot': singleDrawOvershoot(seconds),
          'exactExhaustions': exactExpiryByShotClock[seconds] ?? 0,
          'gameClockFirst': gameClockFirstByShotClock[seconds] ?? 0,
          'simultaneousExpiry': simultaneousByShotClock[seconds] ?? 0,
          'hornEligiblePhases': hornEligiblePhases[seconds] ?? 0,
        },
    ],
    'totalsReconcile': {
      'sampledPhases': sampledPhasesByShotClock.values.fold(0, (a, b) => a + b),
      'overshoots': overshootByShotClock.values.fold(0, (a, b) => a + b),
      'exactExhaustions': exactExpiryByShotClock.values.fold(
        0,
        (a, b) => a + b,
      ),
      'shotClockTurnovers':
          (overshootByShotClock.values.fold(0, (a, b) => a + b)) +
          (exactExpiryByShotClock.values.fold(0, (a, b) => a + b)),
    },
    'floor22Cases': floor22Cases,
  };
}

final class GameRow {
  GameRow({
    required this.index,
    required this.matchupIndex,
    required this.seed,
    required this.input,
    required this.result,
    required this.digest,
  });

  final int index;
  final int matchupIndex;
  final int seed;
  final GameInput input;
  final GameResult result;
  final String digest;

  TeamBoxScore get homeBox => result.boxScore.teams[input.homeTeamId.value]!;
  TeamBoxScore get awayBox => result.boxScore.teams[input.awayTeamId.value]!;
}

void _accumulate(
  GameRow row, {
  required Map<String, List<double>> teamMetric,
  required Map<String, List<double>> homeMetric,
  required Map<String, List<double>> awayMetric,
  required Map<String, List<double>> gameMetric,
  required Map<String, Map<String, List<double>>> positionMetric,
  required Map<String, List<double>> teamAggregate,
  required Map<String, List<double>> strongMetric,
  required Map<String, List<double>> weakMetric,
  required Map<String, int> turnoverTotals,
  required Map<String, int> shotEntries,
  required Map<int, int> floorEntries,
  required Map<int, int> floorTurnovers,
  required Map<String, int> shotTurnovers,
  required Map<String, int> foulTotals,
}) {
  final homeRating = teamRating(row.input, row.input.homeTeamId);
  final awayRating = teamRating(row.input, row.input.awayTeamId);

  for (final team in [row.input.homeTeamId, row.input.awayTeamId]) {
    final box = row.result.boxScore.teams[team.value]!;
    final counts = possessionCounts(row.result.events, team);
    final turnovers = turnoverBreakdown(row.result.events, team: team);
    final fouls = foulBreakdown(row.result.events, team: team);
    final assisted = assistedFgmShare(row.result.events, team);
    final isHome = team == row.input.homeTeamId;
    final rating = isHome ? homeRating : awayRating;
    final opponentRating = isHome ? awayRating : homeRating;

    void put(String name, double? value) {
      if (value == null) return;
      teamMetric.putIfAbsent(name, () => []).add(value);
      (isHome ? homeMetric : awayMetric).putIfAbsent(name, () => []).add(value);
      (rating >= opponentRating ? strongMetric : weakMetric)
          .putIfAbsent(name, () => [])
          .add(value);
    }

    put('points', box.points.toDouble());
    put('fga', box.fga.toDouble());
    put('fgm', box.fgm.toDouble());
    put('fgPct', box.fga == 0 ? null : box.fgm / box.fga);
    put('twoPa', box.twoPa.toDouble());
    put('twoPm', box.twoPm.toDouble());
    put('twoPct', box.twoPa == 0 ? null : box.twoPm / box.twoPa);
    put('threePa', box.threePa.toDouble());
    put('threePm', box.threePm.toDouble());
    put('threePct', box.threePa == 0 ? null : box.threePm / box.threePa);
    put('threePaShare', box.fga == 0 ? null : box.threePa / box.fga);
    put('fta', box.fta.toDouble());
    put('ftm', box.ftm.toDouble());
    put('ftPct', box.fta == 0 ? null : box.ftm / box.fta);
    put('ftaPerFga', box.fga == 0 ? null : box.fta / box.fga);
    put('pf', box.personalFouls.toDouble());
    put('oreb', box.oreb.toDouble());
    put('dreb', box.dreb.toDouble());
    put('reb', box.rebounds.toDouble());
    final opponent =
        row.result.boxScore.teams[row.input.opponentOf(team).value]!;
    put(
      'orebPct',
      box.oreb + opponent.dreb == 0
          ? null
          : box.oreb / (box.oreb + opponent.dreb),
    );
    put('assists', box.assists.toDouble());
    put('assistedFgmShare', assisted);
    put('assistedFgm', (assisted ?? 0) * box.fgm);
    put('steals', box.steals.toDouble());
    put('blocks', box.blocks.toDouble());
    put('blkPerFga', box.fga == 0 ? null : box.blocks / box.fga);
    put('tov', box.turnovers.toDouble());
    put(
      'tovPer100Completed',
      counts.completed == 0 ? null : 100 * box.turnovers / counts.completed,
    );
    put('startedPossessions', counts.started.toDouble());
    put('completedPossessions', counts.completed.toDouble());
    put('periodEndPossessions', counts.periodEnd.toDouble());
    put('orebContinuations', counts.orebContinuations.toDouble());
    put('estimatedPossessions', counts.estimated);
    put(
      'liveReboundOpportunities',
      row.result.events.whereType<Rebound>().length.toDouble(),
    );
    put('stealTov', turnovers.steal.toDouble());
    put('nonStealTov', turnovers.nonSteal.toDouble());
    put('offensiveFoulTov', turnovers.offensiveFoul.toDouble());
    put('shotClockTov', turnovers.shotClock.toDouble());
    put('shootingFouls', fouls.shooting.toDouble());
    put('nonShootingFouls', fouls.nonShooting.toDouble());
    put('offensiveFouls', fouls.offensive.toDouble());
    put('bonusAwards', fouls.bonusAwards.toDouble());

    var playerPoints = 0;
    var maxPlayerPoints = 0;
    var pgTurnovers = 0;
    var centerRebounds = 0;
    for (final player in row.input.lineupFor(team).players) {
      final stats = row.result.boxScore.players[player.id.value]!;
      playerPoints += stats.points;
      maxPlayerPoints = math.max(maxPlayerPoints, stats.points);
      final position = player.position.shortName;
      final metrics = positionMetric.putIfAbsent(position, () => {});
      void putPosition(String name, double value) =>
          metrics.putIfAbsent(name, () => []).add(value);
      putPosition('fga', stats.fga.toDouble());
      putPosition('threePa', stats.threePa.toDouble());
      putPosition('fta', stats.fta.toDouble());
      putPosition('points', stats.points.toDouble());
      putPosition('tov', stats.turnovers.toDouble());
      putPosition('reb', stats.rebounds.toDouble());
      putPosition('pf', stats.personalFouls.toDouble());
      if (player.position == Position.pg) {
        pgTurnovers += stats.turnovers;
      }
      if (player.position == Position.c) {
        centerRebounds += stats.rebounds;
      }
    }
    if (playerPoints != box.points) {
      throw StateError('player points do not reconcile');
    }
    put(
      'maxPlayerPointShare',
      box.points == 0 ? null : maxPlayerPoints / box.points,
    );
    put('pgTovShare', box.turnovers == 0 ? null : pgTurnovers / box.turnovers);
    put(
      'centerRebShare',
      box.rebounds == 0 ? null : centerRebounds / box.rebounds,
    );

    teamAggregate.putIfAbsent(team.value, () => []).add(box.points.toDouble());
    for (final entry in turnovers.toMap().entries) {
      turnoverTotals[entry.key] = turnoverTotals[entry.key]! + entry.value;
    }
    for (final entry in {
      'shooting': fouls.shooting,
      'nonShooting': fouls.nonShooting,
      'offensive': fouls.offensive,
      'bonusAwards': fouls.bonusAwards,
    }.entries) {
      foulTotals[entry.key] = foulTotals[entry.key]! + entry.value;
    }
  }

  final audit = shotClockAudit(row.result.events, rules: row.input.rules);
  for (final entry in audit.entries.entries) {
    shotEntries[entry.key] = shotEntries[entry.key]! + entry.value;
  }
  for (final entry in audit.turnovers.entries) {
    shotTurnovers[entry.key] = (shotTurnovers[entry.key] ?? 0) + entry.value;
  }
  for (final entry in audit.retainedFloorEntries.entries) {
    floorEntries[entry.key] = (floorEntries[entry.key] ?? 0) + entry.value;
  }
  for (final entry in audit.retainedFloorTurnovers.entries) {
    floorTurnovers[entry.key] = (floorTurnovers[entry.key] ?? 0) + entry.value;
  }

  for (var period = 1; period <= 4; period++) {
    final points =
        (row.result.homePeriodScores[period] ?? 0) +
        (row.result.awayPeriodScores[period] ?? 0);
    gameMetric
        .putIfAbsent('period${period}Points', () => [])
        .add(points.toDouble());
    final fouls = row.result.events
        .whereType<PersonalFoul>()
        .where((event) => event.period == period)
        .length;
    gameMetric
        .putIfAbsent('period${period}Fouls', () => [])
        .add(fouls.toDouble());
  }
  final overtimePoints =
      row.result.homePeriodScores.entries
          .where((entry) => entry.key > 4)
          .fold(0, (sum, entry) => sum + entry.value) +
      row.result.awayPeriodScores.entries
          .where((entry) => entry.key > 4)
          .fold(0, (sum, entry) => sum + entry.value);
  if (row.result.overtimes > 0) {
    gameMetric
        .putIfAbsent('overtimePoints', () => [])
        .add(overtimePoints.toDouble());
  }
  final totalTov = row.homeBox.turnovers + row.awayBox.turnovers;
  gameMetric
      .putIfAbsent('combinedPoints', () => [])
      .add((row.result.homeScore + row.result.awayScore).toDouble());
  gameMetric.putIfAbsent('totalTurnovers', () => []).add(totalTov.toDouble());
  gameMetric
      .putIfAbsent('totalFouls', () => [])
      .add((row.homeBox.personalFouls + row.awayBox.personalFouls).toDouble());
  gameMetric
      .putIfAbsent('events', () => [])
      .add(row.result.events.length.toDouble());
  gameMetric
      .putIfAbsent('overtimes', () => [])
      .add(row.result.overtimes.toDouble());
  gameMetric
      .putIfAbsent('startedPossessions', () => [])
      .add(
        (possessionCounts(row.result.events, row.input.homeTeamId).started +
                possessionCounts(
                  row.result.events,
                  row.input.awayTeamId,
                ).started)
            .toDouble(),
      );
}

void _considerRepresentative(
  Map<String, GameRow> representatives,
  GameRow row,
  int combined,
) {
  if (!representatives.containsKey('low')) representatives['low'] = row;
  if (!representatives.containsKey('median')) representatives['median'] = row;
  if (!representatives.containsKey('high')) representatives['high'] = row;
  final low = representatives['low']!;
  final high = representatives['high']!;
  if (combined < low.result.totalPoints) representatives['low'] = row;
  if (combined > high.result.totalPoints) representatives['high'] = row;
  // Median placeholder replaced after the corpus using the full distribution.
}

Map<String, Object?> _buildSummary({
  required List<GameRow> rows,
  required List<Map<String, Object?>> failures,
  required List<Map<String, Object?>> structuralIssues,
  required List<Map<String, Object?>> foulIssues,
  required Map<String, List<double>> teamMetric,
  required Map<String, List<double>> homeMetric,
  required Map<String, List<double>> awayMetric,
  required Map<String, List<double>> gameMetric,
  required Map<String, Map<String, List<double>>> positionMetric,
  required Map<String, List<double>> teamAggregate,
  required Map<String, List<double>> strongMetric,
  required Map<String, List<double>> weakMetric,
  required Map<String, int> turnoverTotals,
  required Map<String, int> shotEntries,
  required Map<int, int> floorEntries,
  required Map<int, int> floorTurnovers,
  required Map<String, int> shotTurnovers,
  required Map<String, int> foulTotals,
  required int homeWins,
  required int overtimeGames,
  required int maxOvertimes,
  required int pointsOutsideRange,
  required double combinedPointsTotal,
  required int completedGames,
  required List<Map<String, Object?>> determinism,
  required TraceAggregate traceAggregate,
  required League league,
  required List<Team> teams,
}) {
  final sorted = [...rows]
    ..sort((a, b) => a.result.totalPoints.compareTo(b.result.totalPoints));
  final medianRow = sorted[sorted.length ~/ 2];
  final metricsByRole = <String, Object?>{
    for (final entry in teamMetric.entries)
      entry.key: {
        'all': Stats(entry.value).toJson(),
        'home': Stats(homeMetric[entry.key] ?? const []).toJson(),
        'away': Stats(awayMetric[entry.key] ?? const []).toJson(),
        'strongerSide': Stats(strongMetric[entry.key] ?? const []).toJson(),
        'weakerSide': Stats(weakMetric[entry.key] ?? const []).toJson(),
      },
  };
  final teamStats = <String, Object?>{
    for (final team in teams)
      team.id.value: {
        'games': teamAggregate[team.id.value]!.length,
        'rating': teamRating(_firstInputForTeam(rows, team.id), team.id),
        'points': Stats(teamAggregate[team.id.value]!).toJson(),
      },
  };
  final positionStats = <String, Object?>{
    for (final entry in positionMetric.entries)
      entry.key: {
        for (final metric in entry.value.entries)
          metric.key: Stats(metric.value).toJson(),
      },
  };

  double sum(String name) =>
      (teamMetric[name] ?? const []).fold(0.0, (a, b) => a + b);
  double? ratio(String numerator, String denominator) {
    final d = sum(denominator);
    return d == 0 ? null : sum(numerator) / d;
  }

  final bands = <String, Object?>{
    'perTeamMedianPoints': {
      'value': Stats(teamMetric['points']!).median,
      'band': [85, 130],
    },
    'perTeamMedianFga': {
      'value': Stats(teamMetric['fga']!).median,
      'band': [70, 105],
    },
    'aggregateThreePaShare': {
      'value': ratio('threePa', 'fga'),
      'band': [0.20, 0.55],
    },
    'aggregateFgPct': {
      'value': ratio('fgm', 'fga'),
      'band': [0.36, 0.57],
    },
    'aggregateFtPct': {
      'value': ratio('ftm', 'fta'),
      'band': [0.55, 0.90],
    },
    'aggregateFtaPerFga': {
      'value': ratio('fta', 'fga'),
      'band': [0.10, 0.50],
    },
    'aggregateOrebPct': {
      'value': sum('oreb') / (sum('oreb') + _sumOpponentDreb(rows)),
      'band': [0.12, 0.40],
    },
    'tovPer100Completed': {
      'value': sum('tov') / sum('completedPossessions') * 100,
      'band': [7, 24],
    },
    'assistedFgmShare': {
      'value': ratio('assistedFgm', 'fgm'),
      'band': [0.25, 0.85],
    },
  };
  final bandReport = <String, Object?>{
    for (final entry in bands.entries)
      entry.key: () {
        final value = (entry.value as Map)['value'] as double?;
        final band = ((entry.value as Map)['band'] as List).cast<num>();
        return {
          'value': value,
          'band': band,
          'verdict': bandVerdict(value, band[0].toDouble(), band[1].toDouble()),
        };
      }(),
  };

  final totalTov = turnoverTotals.values.reduce((a, b) => a + b);
  final overshoot = <String, Object?>{
    for (final shotClock in [24, 22, 20, 18, 16, 14])
      '$shotClock': singleDrawOvershoot(shotClock),
  };

  return {
    'protocol': 't015-calibration-protocol.md',
    'amendments': 'Amendment 002 (Candidate B), simulation v2',
    'baselineCommit': _git(['rev-parse', 'HEAD']),
    'gitStatus': _git([
      'status',
      '--porcelain',
    ]).split('\n').where((line) => line.trim().isNotEmpty).toList(),
    'versions': {
      'simulation': gameSimulationVersion,
      'rules': gameRulesVersion,
      'eventSchema': gameEventSchemaVersion,
      'fingerprint': gameFingerprintVersion,
      'durationModel': gameActionDurationModelVersion,
      'prng': 'xorshift32-v1',
      'coreEngine': coreEngineVersion,
      'leagueSchema': snapshotSchemaVersion,
    },
    'seedAlgorithm':
        'seed(m,s) = 1 + ((97*m + 17*s) mod 200); m=directed matchup 0..55, s=slot 0..19',
    'schedule': {
      'leagueFixtureSeed': leagueSeed,
      'teams': [for (final team in teams) team.id.value],
      'matchups': 28,
      'orientations': 2,
      'seedsPerDirectedMatchup': seedsPerMatchup,
      'plannedGames': expectedGames,
    },
    'corpus': {
      'attempted': rows.length + failures.length,
      'completed': completedGames,
      'typedFailures': failures.length,
      'failures': failures,
      'sampleSizeGateMet': completedGames >= 1000,
      'structuralIssues': structuralIssues,
      'foulAuditIssues': foulIssues,
      'homeWins': homeWins,
      'awayWins': completedGames - homeWins,
      'homeWinRate': completedGames == 0 ? null : homeWins / completedGames,
      'overtimeGames': overtimeGames,
      'maxOvertimes': maxOvertimes,
      'combinedPointsMean': completedGames == 0
          ? null
          : combinedPointsTotal / completedGames,
      'combinedPointsOutside90To340': pointsOutsideRange,
      'medianCombinedPointsGame': {
        'gameId': medianRow.input.gameId,
        'seed': medianRow.input.seed,
        'combinedPoints': medianRow.result.totalPoints,
      },
    },
    'metrics': metricsByRole,
    'gameMetrics': {
      for (final entry in gameMetric.entries)
        entry.key: Stats(entry.value).toJson(),
    },
    'teams': teamStats,
    'positions': positionStats,
    'bands': bandReport,
    'turnovers': {
      'totals': turnoverTotals,
      'total': totalTov,
      'liveShare': totalTov == 0
          ? null
          : (turnoverTotals['steal']! + turnoverTotals['nonSteal']!) / totalTov,
      'shotClockShare': totalTov == 0
          ? null
          : turnoverTotals['shotClock']! / totalTov,
      'offensiveFoulShare': totalTov == 0
          ? null
          : turnoverTotals['offensiveFoul']! / totalTov,
      'shotClockStates': {
        'entries': shotEntries,
        'turnovers': shotTurnovers,
        'analyticSingleDrawOvershoot': overshoot,
        'retainedFloorPhases': [
          for (var seconds = 14; seconds <= 24; seconds++)
            {
              'floorSeconds': seconds,
              'eligiblePhases': floorEntries[seconds] ?? 0,
              'shotClockTurnovers': floorTurnovers[seconds] ?? 0,
              'observedRate': (floorEntries[seconds] ?? 0) == 0
                  ? null
                  : (floorTurnovers[seconds] ?? 0) / floorEntries[seconds]!,
              'analyticSingleDrawOvershoot': singleDrawOvershoot(seconds),
            },
        ],
      },
    },
    'fouls': foulTotals,
    'determinism': determinism,
    'a1Trace': traceAggregate.toJson(),
    'environment': {
      'dart': Platform.version,
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'cpus': Platform.numberOfProcessors,
    },
    'sourceSha256': _sourceHashes(),
  };
}

double _sumOpponentDreb(List<GameRow> rows) {
  var total = 0;
  for (final row in rows) {
    for (final team in [row.input.homeTeamId, row.input.awayTeamId]) {
      total +=
          row.result.boxScore.teams[row.input.opponentOf(team).value]!.dreb;
    }
  }
  return total.toDouble();
}

GameInput _firstInputForTeam(List<GameRow> rows, TeamId team) => rows
    .firstWhere(
      (row) => row.input.homeTeamId == team || row.input.awayTeamId == team,
    )
    .input;

String _git(List<String> arguments) {
  try {
    final result = Process.runSync('git', arguments);
    return result.exitCode == 0 ? (result.stdout as String).trim() : '';
  } on ProcessException {
    return '';
  }
}

const List<String> _hashPaths = [
  'lib/src/simulation/game_simulator.dart',
  'lib/src/simulation/probability_model.dart',
  'lib/src/simulation/game_event.dart',
  'lib/src/simulation/game_reducer.dart',
  'lib/src/simulation/event_accounting.dart',
  'lib/src/simulation/game_versions.dart',
  'lib/src/simulation/phase_trace.dart',
  'lib/src/generation/league_generator.dart',
  'lib/src/generation/deterministic_random.dart',
  'tool/t015_calibration.dart',
  'tool/t015_metrics.dart',
  'test/simulation/support.dart',
];

Map<String, String> _sourceHashes() => {
  for (final path in _hashPaths)
    if (File(path).existsSync())
      path: sha256.convert(File(path).readAsBytesSync()).toString(),
};

String _csv(List<GameRow> rows) {
  const columns = [
    'gameIndex',
    'matchupIndex',
    'pairIndex',
    'orientation',
    'gameId',
    'seed',
    'homeTeamId',
    'awayTeamId',
    'homeScore',
    'awayScore',
    'combinedPoints',
    'periods',
    'overtimes',
    'events',
    'digest',
    'inputFingerprint',
    'homeRating',
    'awayRating',
    'combinedStarted',
    'combinedCompleted',
    'homeStarted',
    'homeCompleted',
    'homePeriodEnd',
    'homeOrebCont',
    'homeEstPoss',
    'homeFgm',
    'homeFga',
    'homeTwoPm',
    'homeTwoPa',
    'homeThreePm',
    'homeThreePa',
    'homeFtm',
    'homeFta',
    'homeAst',
    'homeOreb',
    'homeDreb',
    'homeReb',
    'homeTov',
    'homeStl',
    'homeBlk',
    'homePf',
    'homeStealTov',
    'homeNonStealTov',
    'homeOfTov',
    'homeScTov',
    'homeShootingFouls',
    'homeNonShootingFouls',
    'homeOffensiveFouls',
    'homeBonusAwards',
    'awayStarted',
    'awayCompleted',
    'awayPeriodEnd',
    'awayOrebCont',
    'awayEstPoss',
    'awayFgm',
    'awayFga',
    'awayTwoPm',
    'awayTwoPa',
    'awayThreePm',
    'awayThreePa',
    'awayFtm',
    'awayFta',
    'awayAst',
    'awayOreb',
    'awayDreb',
    'awayReb',
    'awayTov',
    'awayStl',
    'awayBlk',
    'awayPf',
    'awayStealTov',
    'awayNonStealTov',
    'awayOfTov',
    'awayScTov',
    'awayShootingFouls',
    'awayNonShootingFouls',
    'awayOffensiveFouls',
    'awayBonusAwards',
    'scEntriesStart24',
    'scEntriesOreb14',
    'scEntriesRetainedFoul',
    'scTovStart24',
    'scTovOreb14',
    'scTovRetainedFoul',
    'scTovOther',
  ];
  final buffer = StringBuffer()..writeln(columns.join(','));
  String f(double? value) => value == null ? '' : value.toStringAsFixed(6);
  for (final row in rows) {
    final input = row.input;
    final result = row.result;
    final home = result.boxScore.teams[input.homeTeamId.value]!;
    final away = result.boxScore.teams[input.awayTeamId.value]!;
    final homeCounts = possessionCounts(result.events, input.homeTeamId);
    final awayCounts = possessionCounts(result.events, input.awayTeamId);
    final homeTov = turnoverBreakdown(result.events, team: input.homeTeamId);
    final awayTov = turnoverBreakdown(result.events, team: input.awayTeamId);
    final homeFouls = foulBreakdown(result.events, team: input.homeTeamId);
    final awayFouls = foulBreakdown(result.events, team: input.awayTeamId);
    final audit = shotClockAudit(result.events);
    final values = <Object?>[
      row.index,
      row.matchupIndex,
      row.matchupIndex ~/ 2,
      row.matchupIndex % 2,
      input.gameId,
      row.seed,
      input.homeTeamId.value,
      input.awayTeamId.value,
      result.homeScore,
      result.awayScore,
      result.totalPoints,
      result.periodsPlayed,
      result.overtimes,
      result.events.length,
      row.digest,
      GameFingerprint.of(input),
      f(teamRating(input, input.homeTeamId)),
      f(teamRating(input, input.awayTeamId)),
      homeCounts.started + awayCounts.started,
      homeCounts.completed + awayCounts.completed,
      homeCounts.started,
      homeCounts.completed,
      homeCounts.periodEnd,
      homeCounts.orebContinuations,
      f(homeCounts.estimated),
      home.fgm,
      home.fga,
      home.twoPm,
      home.twoPa,
      home.threePm,
      home.threePa,
      home.ftm,
      home.fta,
      home.assists,
      home.oreb,
      home.dreb,
      home.rebounds,
      home.turnovers,
      home.steals,
      home.blocks,
      home.personalFouls,
      homeTov.steal,
      homeTov.nonSteal,
      homeTov.offensiveFoul,
      homeTov.shotClock,
      homeFouls.shooting,
      homeFouls.nonShooting,
      homeFouls.offensive,
      homeFouls.bonusAwards,
      awayCounts.started,
      awayCounts.completed,
      awayCounts.periodEnd,
      awayCounts.orebContinuations,
      f(awayCounts.estimated),
      away.fgm,
      away.fga,
      away.twoPm,
      away.twoPa,
      away.threePm,
      away.threePa,
      away.ftm,
      away.fta,
      away.assists,
      away.oreb,
      away.dreb,
      away.rebounds,
      away.turnovers,
      away.steals,
      away.blocks,
      away.personalFouls,
      awayTov.steal,
      awayTov.nonSteal,
      awayTov.offensiveFoul,
      awayTov.shotClock,
      awayFouls.shooting,
      awayFouls.nonShooting,
      awayFouls.offensive,
      awayFouls.bonusAwards,
      audit.entries['start24'],
      audit.entries['oreb14'],
      audit.entries['retainedFoul'],
      audit.turnovers['start24'],
      audit.turnovers['oreb14'],
      audit.turnovers['retainedFoul'],
      audit.turnovers['other'] ?? 0,
    ];
    buffer.writeln(values.join(','));
  }
  return buffer.toString();
}

String _diagnostics(
  Map<String, GameRow> representatives,
  List<GameRow> rows,
  League league,
  TraceAggregate trace,
) {
  final sorted = [...rows]
    ..sort((a, b) => a.result.totalPoints.compareTo(b.result.totalPoints));
  representatives['median'] = sorted[sorted.length ~/ 2];
  final buffer = StringBuffer()
    ..writeln('# T015 — Event-linked diagnostic games')
    ..writeln()
    ..writeln(
      'Generated by `tool/t015_calibration.dart`. Reproduce a game with',
    )
    ..writeln(
      'the explicit fixture below — **not** `buildInput`, which is pinned to',
    )
    ..writeln('teams 1/2 and cannot reproduce other matchups:')
    ..writeln()
    ..writeln('```dart')
    ..writeln('final league = const LeagueGenerator().generate(')
    ..writeln('  const GenerationConfig(seed: 20261028),')
    ..writeln(');')
    ..writeln(
      "final home = league.teams.firstWhere((t) => t.id.value == '<homeId>');",
    )
    ..writeln(
      "final away = league.teams.firstWhere((t) => t.id.value == '<awayId>');",
    )
    ..writeln('final input = GameInput.create(')
    ..writeln("  gameId: '<gameId>', league: league,")
    ..writeln('  homeTeamId: home.id, awayTeamId: away.id,')
    ..writeln('  homeLineup: ActiveLineup.defaultFor(home),')
    ..writeln('  awayLineup: ActiveLineup.defaultFor(away),')
    ..writeln('  seed: <seed>, rules: GameRules.standard,')
    ..writeln(');')
    ..writeln('final result = GameSimulator().simulate(input);')
    ..writeln('```')
    ..writeln()
    ..writeln('Fixture: `${league.id.value}` (8 teams).')
    ..writeln();
  for (final label in ['low', 'median', 'high']) {
    final row = representatives[label]!;
    _writeGame(buffer, label, row, league);
  }
  // Edge-case references.
  GameRow? firstWhere(bool Function(GameRow) test) {
    for (final row in rows) {
      if (test(row)) return row;
    }
    return null;
  }

  final overtime = firstWhere((row) => row.result.overtimes > 0);
  final deadBall = firstWhere(
    (row) => row.result.events.any((event) => event is DeadBallMiss),
  );
  final andOne = firstWhere(
    (row) => row.result.events.any(
      (event) => event is FieldGoalAttempt && event.andOne,
    ),
  );
  final buzzer = firstWhere(
    (row) => row.result.events.any(
      (event) =>
          event is FieldGoalAttempt && event.gameClock == 0 && event.made,
    ),
  );
  buffer
    ..writeln('## Edge-case references')
    ..writeln()
    ..writeln('| Case | Game | Seed | Event refs |')
    ..writeln('|---|---|---|---|');
  void ref(String name, GameRow? row, String detail) {
    buffer.writeln(
      '| $name | ${row?.input.gameId ?? 'not observed'} | '
      '${row?.seed ?? '-'} | $detail |',
    );
  }

  ref(
    'Overtime',
    overtime,
    overtime == null ? '-' : 'overtimes=${overtime.result.overtimes}',
  );
  ref(
    'Dead-ball miss',
    deadBall,
    deadBall == null
        ? '-'
        : 'sequence=${deadBall.result.events.whereType<DeadBallMiss>().first.sequence}',
  );
  ref(
    'And-one',
    andOne,
    andOne == null
        ? '-'
        : 'sequence=${andOne.result.events.firstWhere((e) => e is FieldGoalAttempt && e.andOne).sequence}',
  );
  ref(
    'Buzzer make',
    buzzer,
    buzzer == null
        ? '-'
        : 'sequence=${buzzer.result.events.firstWhere((e) => e is FieldGoalAttempt && e.gameClock == 0 && e.made).sequence}',
  );
  buffer
    ..writeln()
    ..writeln('## A1 trace: exact shot-clock expiry at a 22-second floor')
    ..writeln()
    ..writeln(
      'Records with `shotClockBefore == 22`, resolution '
      '`shotClockExpiryNoAttempt`, and planned duration equal to the clock:',
    )
    ..writeln()
    ..writeln(
      '| Game | Seed | Period | Kind | D | Game clock before | Turnover seq |',
    )
    ..writeln('|---|---|---|---|---|---|---|');
  for (final caseRow in trace.floor22Cases) {
    buffer.writeln(
      '| ${caseRow['gameId']} | ${caseRow['seed']} | ${caseRow['period']} | '
      '${caseRow['kind']} | ${caseRow['plannedSeconds']} | '
      '${caseRow['gameClockBefore']} | ${caseRow['turnoverSequence'] ?? '-'} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## A1 trace: sampled frequency and duration summary')
    ..writeln()
    ..writeln('Kind counts: ${trace.kindCounts} over ${trace.records} records.')
    ..writeln(
      'Resolution counts: '
      '${trace.resolutionCounts.map((k, v) => MapEntry(k.name, v))}.',
    );
  return buffer.toString();
}

void _writeGame(StringBuffer buffer, String label, GameRow row, League league) {
  final result = row.result;
  final input = row.input;
  buffer
    ..writeln('## ${label.toUpperCase()} game — `${input.gameId}`')
    ..writeln()
    ..writeln(
      'Seed ${input.seed}; ${input.homeTeamId.value} (home) '
      '${result.homeScore}–${result.awayScore} '
      '${input.awayTeamId.value} (away); periods ${result.periodsPlayed}; '
      'events ${result.events.length}; digest `${row.digest}`.',
    )
    ..writeln()
    ..writeln(
      'Period scores: home ${result.homePeriodScores}, '
      'away ${result.awayPeriodScores}.',
    )
    ..writeln();
  for (final team in [input.homeTeamId, input.awayTeamId]) {
    final box = result.boxScore.teams[team.value]!;
    final counts = possessionCounts(result.events, team);
    final turnovers = turnoverBreakdown(result.events, team: team);
    final fouls = foulBreakdown(result.events, team: team);
    buffer
      ..writeln('### ${team.value} box')
      ..writeln()
      ..writeln(
        'PTS ${box.points}; FGM/FGA ${box.fgm}/${box.fga}; '
        '2P ${box.twoPm}/${box.twoPa}; 3P ${box.threePm}/${box.threePa}; '
        'FT ${box.ftm}/${box.fta}; AST ${box.assists}; '
        'OREB/DREB/REB ${box.oreb}/${box.dreb}/${box.rebounds}; '
        'TOV ${box.turnovers} (steal ${turnovers.steal}, '
        'nonSteal ${turnovers.nonSteal}, shot clock ${turnovers.shotClock}, '
        'offensive foul ${turnovers.offensiveFoul}); '
        'STL ${box.steals}; BLK ${box.blocks}; PF ${box.personalFouls} '
        '(shooting ${fouls.shooting}, non-shooting ${fouls.nonShooting}, '
        'offensive ${fouls.offensive}, bonus awards ${fouls.bonusAwards}); '
        'possessions started ${counts.started}, completed ${counts.completed}, '
        'period-end ${counts.periodEnd}, OREB continuations '
        '${counts.orebContinuations}, estimated ${counts.estimated.toStringAsFixed(1)}.',
      )
      ..writeln()
      ..writeln('| Player | Pos | PTS | FGM/FGA | 3P | FT | REB | TOV | PF |')
      ..writeln('|---|---|---|---|---|---|---|---|---|');
    for (final player in input.lineupFor(team).players) {
      final stats = result.boxScore.players[player.id.value]!;
      buffer.writeln(
        '| ${player.id.value} | ${player.position.shortName} | '
        '${stats.points} | ${stats.fgm}/${stats.fga} | '
        '${stats.threePm}/${stats.threePa} | ${stats.ftm}/${stats.fta} | '
        '${stats.rebounds} | ${stats.turnovers} | ${stats.personalFouls} |',
      );
    }
    buffer.writeln();
  }
  final events = result.events;
  final firstScore = events
      .whereType<FieldGoalAttempt>()
      .where((event) => event.made)
      .firstOrNull;
  final firstTurnover = events.whereType<Turnover>().firstOrNull;
  final firstOreb = events
      .whereType<Rebound>()
      .where((event) => event.offensive)
      .firstOrNull;
  final firstFt = events.whereType<FreeThrowAttempt>().firstOrNull;
  final firstShotClock = events
      .whereType<Turnover>()
      .where((event) => event.reason == TurnoverReason.shotClock)
      .firstOrNull;
  final lastEvent = events.last;
  final lastPeriodEnd = events.lastWhere((event) => event is PeriodEnded);
  buffer
    ..writeln('### Notable sequences')
    ..writeln()
    ..writeln(
      '- First made FG: '
      '${firstScore == null ? 'not observed' : 'sequence ${firstScore.sequence}'}.',
    )
    ..writeln(
      '- First turnover: '
      '${firstTurnover == null ? 'not observed' : 'sequence ${firstTurnover.sequence} (${firstTurnover.reason.wire})'}.',
    )
    ..writeln(
      '- First offensive rebound: '
      '${firstOreb == null ? 'not observed' : 'sequence ${firstOreb.sequence} (continues miss ${firstOreb.missedEventSequence})'}.',
    )
    ..writeln(
      '- First free throw: '
      '${firstFt == null ? 'not observed' : 'sequence ${firstFt.sequence}, group ${firstFt.groupId}, attempt ${firstFt.attemptIndex}/${firstFt.attemptsInGroup}'}.',
    )
    ..writeln(
      '- First shot-clock expiry: '
      '${firstShotClock == null ? 'not observed' : 'sequence ${firstShotClock.sequence} at clock ${firstShotClock.gameClock}'}.',
    )
    ..writeln(
      '- Final period end: sequence ${lastPeriodEnd.sequence}; '
      'game end: sequence ${lastEvent.sequence} '
      '(${lastEvent.type}).',
    )
    ..writeln()
    ..writeln(
      'Reproduce with the explicit `GameInput.create` block above: '
      'league seed ${league.config.seed}, home ${input.homeTeamId.value}, '
      'away ${input.awayTeamId.value}, seed ${input.seed}, '
      '`GameRules.standard`, simulation v2.',
    );
  buffer.writeln();
}
