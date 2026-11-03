import 'dart:convert';
import 'dart:io';

import 't08_common.dart';

/// Frozen T08 paired analysis. Reads the two raw JSONL arms and writes
/// `t08-paired.csv`, `t08-summary.json` and `t08-mechanism-report.json`.
///
/// Usage: `dart run tool/t08_analyze.dart --v4=<jsonl> --v5=<jsonl>`
/// `--out=<dir> --manifestSha=<sha>`
void main(List<String> args) {
  final v4Path = _required(args, 'v4');
  final v5Path = _required(args, 'v5');
  final outDir = _required(args, 'out');
  final manifestSha = _required(args, 'manifestSha');

  final v4Rows = _readRows(v4Path);
  final v5Rows = _readRows(v5Path);
  _checkRows(v4Rows, 'v4');
  _checkRows(v5Rows, 'v5');

  final v4BySlot = {for (final row in v4Rows) row['slot']! as int: row};
  final v5BySlot = {for (final row in v5Rows) row['slot']! as int: row};
  if (v4BySlot.length != v5BySlot.length ||
      !v4BySlot.keys.toSet().containsAll(v5BySlot.keys)) {
    throw StateError('arms do not cover the same 200 slots');
  }

  const metrics = [
    'homePoints',
    'awayPoints',
    'possessions',
    'turnovers',
    'fga',
    'threePa',
    'fta',
    'personalFouls',
  ];
  final series = <String, List<double>>{for (final m in metrics) m: []};
  final perMatchup = <int, Map<String, List<double>>>{
    for (var m = 0; m < t08MatchupCount; m++)
      m: {for (final metric in metrics) metric: <double>[]},
  };
  final paired = <Map<String, Object?>>[];
  final categoryCounts = {'A': 0, 'B': 0, 'C': 0};
  final mechanismA = <Map<String, Object?>>[];
  final mechanismB = <Map<String, Object?>>[];
  final mechanismC = <Map<String, Object?>>[];
  final firstDivergence = <int>[];
  final disqualificationsPerGame = <int>[];
  final substitutionsPerGame = <int>[];
  final continuationCases = <Map<String, Object?>>[];
  final minutesSecondsByRank = <int, List<double>>{};
  final matchupCategories = {
    for (var m = 0; m < t08MatchupCount; m++) m: {'A': 0, 'B': 0, 'C': 0},
  };
  final matchupDisqualifications = {
    for (var m = 0; m < t08MatchupCount; m++) m: <int>[],
  };
  final matchupSubstitutions = {
    for (var m = 0; m < t08MatchupCount; m++) m: <int>[],
  };
  final matchupDivergence = {
    for (var m = 0; m < t08MatchupCount; m++) m: <int>[],
  };

  for (var slot = 0; slot < t08PairCount; slot++) {
    final v4 = v4BySlot[slot]!;
    final v5 = v5BySlot[slot]!;
    if (v4['seed'] != v5['seed'] ||
        v4['matchup'] != v5['matchup'] ||
        v4['gameId'] != v5['gameId'] ||
        v4['homeTeamId'] != v5['homeTeamId'] ||
        v4['awayTeamId'] != v5['awayTeamId']) {
      throw StateError('slot $slot: registered inputs differ between arms');
    }

    final diffs = <String, double>{};
    for (final metric in metrics) {
      final a = (v4['metrics']! as Map)[metric]! as num;
      final b = (v5['metrics']! as Map)[metric]! as num;
      final diff = (b - a).toDouble();
      diffs[metric] = diff;
      series[metric]!.add(diff);
      perMatchup[v4['matchup']! as int]![metric]!.add(diff);
    }

    final v4Events = (v4['events']! as List).cast<Object?>();
    final v5Events = (v5['events']! as List).cast<Object?>();
    var shared = 0;
    while (shared < v4Events.length &&
        shared < v5Events.length &&
        jsonEncode(v4Events[shared]) == jsonEncode(v5Events[shared])) {
      shared++;
    }
    final equalArrays = shared == v4Events.length && shared == v5Events.length;
    final divergence = equalArrays ? null : shared + 1;
    if (divergence != null) {
      firstDivergence.add(divergence);
      matchupDivergence[v4['matchup']! as int]!.add(divergence);
    }

    final subs = (v5['substitutions']! as List).cast<Object?>();
    final disq = (v5['disqualified']! as List).cast<Object?>();
    final category = disq.isEmpty ? 'A' : (subs.isEmpty ? 'C' : 'B');
    categoryCounts[category] = categoryCounts[category]! + 1;
    final matchupIndex = v4['matchup']! as int;
    matchupCategories[matchupIndex]![category] =
        matchupCategories[matchupIndex]![category]! + 1;
    disqualificationsPerGame.add(disq.length);
    substitutionsPerGame.add(subs.length);
    matchupDisqualifications[matchupIndex]!.add(disq.length);
    matchupSubstitutions[matchupIndex]!.add(subs.length);

    _collectMinutes(v5, minutesSecondsByRank);
    continuationCases.addAll(t08ContinuationCases(v5));

    final record = <String, Object?>{
      'slot': slot,
      'matchup': v4['matchup'],
      'seed': v4['seed'],
      'gameId': v4['gameId'],
      'category': category,
      'sharedPrefixLength': shared,
      'firstDivergenceIndex1Based': divergence,
      'equalArrays': equalArrays,
      'v4EventCount': v4Events.length,
      'v5EventCount': v5Events.length,
      'v5Substitutions': subs.length,
      'v5Disqualifications': disq.length,
      for (final metric in metrics) 'd_$metric': diffs[metric],
    };
    paired.add(record);

    final mechanismRecord = {
      'slot': slot,
      'gameId': v5['gameId'],
      'seed': v5['seed'],
      'matchup': v5['matchup'],
      'sharedPrefixLength': shared,
      'firstDivergenceIndex1Based': divergence,
    };
    switch (category) {
      case 'A':
        mechanismA.add(mechanismRecord);
        if (!equalArrays) {
          mechanismRecord['failure'] = 'category A arrays differ';
          mechanismRecord['v4Event'] = shared < v4Events.length
              ? v4Events[shared]
              : null;
          mechanismRecord['v5Event'] = shared < v5Events.length
              ? v5Events[shared]
              : null;
        }
      case 'B':
        final firstSub = subs.isEmpty
            ? null
            : (subs.first! as Map)['sequence']! as int;
        final requiredPrefix = (firstSub ?? v5Events.length) - 1;
        final prefixOk = shared >= requiredPrefix;
        mechanismRecord['firstV5SubstitutionSequence'] = firstSub;
        mechanismRecord['requiredPrefixLength'] = requiredPrefix;
        mechanismRecord['prefixEqual'] = prefixOk;
        if (!prefixOk) {
          mechanismRecord['failure'] = 'pre-substitution divergence';
          mechanismRecord['v4Event'] = shared < v4Events.length
              ? v4Events[shared]
              : null;
          mechanismRecord['v5Event'] = shared < v5Events.length
              ? v5Events[shared]
              : null;
        }
        mechanismB.add(mechanismRecord);
      case 'C':
        mechanismC.add({
          ...mechanismRecord,
          'disqualified': disq,
          'status': 'unclassified: requires explanation',
        });
    }
  }

  final summary = {
    'design': {
      'pairs': t08PairCount,
      'matchups': t08MatchupCount,
      'firstSeed': t08FirstSeed,
      'lastSeed': t08FirstSeed + t08PairCount - 1,
      'leagueSeed': 20261028,
      'engineV4': v4Rows.first['engineSha'],
      'engineV5': v5Rows.first['engineSha'],
      'manifestSha256': manifestSha,
      'rawV4Sha256': sha256Hex(File(v4Path).readAsStringSync()),
      'rawV5Sha256': sha256Hex(File(v5Path).readAsStringSync()),
    },
    'counts': {
      'v4Rows': v4Rows.length,
      'v5Rows': v5Rows.length,
      'pairedRows': paired.length,
      'simulations': v4Rows.length + v5Rows.length,
    },
    'primary': {
      for (final metric in metrics) metric: t08Describe(series[metric]!),
    },
    'matchupBreakdown': {
      for (var m = 0; m < t08MatchupCount; m++)
        'matchup$m': {
          for (final metric in metrics)
            metric: t08Describe(perMatchup[m]![metric]!),
        },
    },
    'matchupParticipation': {
      for (var m = 0; m < t08MatchupCount; m++)
        'matchup$m': {
          'categories': matchupCategories[m],
          'gamesWithSubstitutions': matchupSubstitutions[m]!
              .where((count) => count > 0)
              .length,
          'gamesWithDisqualifications': matchupDisqualifications[m]!
              .where((count) => count > 0)
              .length,
          'disqualificationsPerGame': t08CountSummary(
            matchupDisqualifications[m]!,
          ),
          'substitutionsPerGame': t08CountSummary(matchupSubstitutions[m]!),
          'firstDivergence': {
            'equalGames': 50 - matchupDivergence[m]!.length,
            'divergedGames': matchupDivergence[m]!.length,
            if (matchupDivergence[m]!.isNotEmpty) ...{
              'min': matchupDivergence[m]!.reduce((a, b) => a < b ? a : b),
              'median': t08Quantile([
                for (final v in matchupDivergence[m]!) v.toDouble(),
              ], 0.5),
              'max': matchupDivergence[m]!.reduce((a, b) => a > b ? a : b),
            },
          },
          'continuationCases': continuationCases
              .where((c) => c['matchup'] == m)
              .toList(),
        },
    },
    'mechanism': {
      'categories': categoryCounts,
      'categoryA': {
        'checked': mechanismA.length,
        'failed': mechanismA.where((r) => r.containsKey('failure')).length,
        'failures': mechanismA.where((r) => r.containsKey('failure')).toList(),
      },
      'categoryB': {
        'checked': mechanismB.length,
        'prefixFailed': mechanismB
            .where((r) => r.containsKey('failure'))
            .length,
        'failures': mechanismB.where((r) => r.containsKey('failure')).toList(),
      },
      'categoryC': {
        'cases': mechanismC.length,
        'details': mechanismC,
        'status': mechanismC.isEmpty
            ? 'no observations'
            : 'unclassified: requires explanation',
      },
      'verdict':
          mechanismA.any((r) => r.containsKey('failure')) ||
              mechanismB.any((r) => r.containsKey('failure')) ||
              mechanismC.isNotEmpty
          ? 'PENDING_OR_FAILED'
          : 'PASS',
    },
    'participation': {
      'disqualificationsPerGame': t08CountSummary(disqualificationsPerGame),
      'substitutionsPerGame': t08CountSummary(substitutionsPerGame),
      'gamesWithSubstitutions': substitutionsPerGame
          .where((count) => count > 0)
          .length,
      'gamesWithDisqualifications': disqualificationsPerGame
          .where((count) => count > 0)
          .length,
      'minutesByRosterRank': {
        for (final entry in minutesSecondsByRank.entries)
          '${entry.key}': t08Distribution(entry.value),
      },
      'firstDivergence': {
        'equalGames': paired.length - firstDivergence.length,
        'divergedGames': firstDivergence.length,
        if (firstDivergence.isNotEmpty) ...{
          'min': firstDivergence.reduce((a, b) => a < b ? a : b),
          'median': t08Quantile([
            for (final v in firstDivergence) v.toDouble(),
          ], 0.5),
          'max': firstDivergence.reduce((a, b) => a > b ? a : b),
        },
      },
      'continuationCases': continuationCases,
      'depletedContinuationCases': continuationCases
          .where((c) => c['kind'] == 'continuedPlay')
          .toList(),
    },
  };

  final out = Directory(outDir)..createSync(recursive: true);
  File('${out.path}/t08-paired.csv').writeAsStringSync(_pairedCsv(paired));
  File(
    '${out.path}/t08-summary.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
  File('${out.path}/t08-mechanism-report.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(summary['mechanism']),
  );
  print(
    const JsonEncoder.withIndent('  ').convert({
      'counts': summary['counts'],
      'categories': categoryCounts,
      'mechanismVerdict': (summary['mechanism']! as Map)['verdict'],
      'primary': {
        for (final metric in metrics)
          metric: {
            'mean': (summary['primary']! as Map)[metric]['mean'],
            'ci': [
              (summary['primary']! as Map)[metric]['ci95Low'],
              (summary['primary']! as Map)[metric]['ci95High'],
            ],
          },
      },
    }),
  );
}

List<Map<String, Object?>> _readRows(String path) {
  final rows = <Map<String, Object?>>[];
  for (final line in File(path).readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    rows.add(jsonDecode(line) as Map<String, Object?>);
  }
  return rows;
}

void _checkRows(List<Map<String, Object?>> rows, String arm) {
  if (rows.length != t08PairCount) {
    throw StateError(
      '$arm arm has ${rows.length} rows, expected $t08PairCount',
    );
  }
  final slots = <int>{};
  for (final row in rows) {
    final slot = row['slot']! as int;
    if (!slots.add(slot)) throw StateError('$arm duplicate slot $slot');
    final metrics = row['metrics']! as Map;
    for (final key in [
      'homePoints',
      'awayPoints',
      'possessions',
      'turnovers',
      'fga',
      'threePa',
      'fta',
      'personalFouls',
    ]) {
      if (metrics[key] is! num) {
        throw StateError('$arm slot $slot missing $key');
      }
    }
  }
}

void _collectMinutes(Map<String, Object?> v5, Map<int, List<double>> acc) {
  final players = v5['players'];
  if (players is! Map) return;
  for (final value in players.values) {
    final player = value! as Map;
    final rank = player['rosterRank']! as int;
    final seconds = (player['secondsPlayed']! as num).toDouble();
    acc.putIfAbsent(rank, () => <double>[]).add(seconds);
  }
}

/// Classifies disqualified players who were never substituted out.
///
/// `hornGameEnd`: the sixth foul is followed only by possession/period/game end
/// events, so no substitution window ever opens (legitimate).
/// `continuedPlay`: any other event follows, which is only legitimate for a
/// depleted roster; reported for explanation, never discarded.
List<Map<String, Object?>> t08ContinuationCases(Map<String, Object?> v5) {
  final fouls = <String, int>{};
  final events = (v5['events']! as List).cast<Object?>();
  final sixth = <String, int>{};
  for (var i = 0; i < events.length; i++) {
    final e = events[i]! as Map;
    if (e['type'] != 'PersonalFoul') continue;
    final player = e['committingPlayerId']! as String;
    fouls[player] = (fouls[player] ?? 0) + 1;
    if (fouls[player] == 6) sixth[player] = i;
  }
  final cases = <Map<String, Object?>>[];
  for (final entry in sixth.entries) {
    var removed = false;
    for (final event in events) {
      final e = event! as Map;
      if (e['type'] == 'Substitution' && e['playerOutId'] == entry.key) {
        removed = true;
        break;
      }
    }
    if (removed) continue;
    final tail = events.skip(entry.value + 1).toList();
    final onlyEnd = tail.every((event) {
      final type = (event! as Map)['type'];
      return type == 'PossessionEnded' ||
          type == 'PeriodEnded' ||
          type == 'GameEnded';
    });
    cases.add({
      'slot': v5['slot'],
      'gameId': v5['gameId'],
      'seed': v5['seed'],
      'matchup': v5['matchup'],
      'playerId': entry.key,
      'foulSequence': (events[entry.value]! as Map)['sequence'],
      'period': (events[entry.value]! as Map)['period'],
      'gameClock': (events[entry.value]! as Map)['gameClock'],
      'kind': onlyEnd ? 'hornGameEnd' : 'continuedPlay',
      'eventsAfterFoul': tail.length,
    });
  }
  return cases;
}

Map<String, Object?> t08CountSummary(List<int> values) => {
  'total': values.fold<int>(0, (a, b) => a + b),
  'gamesWithAtLeastOne': values.where((v) => v > 0).length,
  'mean': values.isEmpty ? 0.0 : values.reduce((a, b) => a + b) / values.length,
  'max': values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b),
};

String _pairedCsv(List<Map<String, Object?>> rows) {
  const columns = [
    'slot',
    'matchup',
    'seed',
    'gameId',
    'category',
    'sharedPrefixLength',
    'firstDivergenceIndex1Based',
    'equalArrays',
    'v4EventCount',
    'v5EventCount',
    'v5Substitutions',
    'v5Disqualifications',
    'd_homePoints',
    'd_awayPoints',
    'd_possessions',
    'd_turnovers',
    'd_fga',
    'd_threePa',
    'd_fta',
    'd_personalFouls',
  ];
  final buffer = StringBuffer()..writeln(columns.join(','));
  for (final row in rows) {
    buffer.writeln(columns.map((c) => row[c] ?? '').join(','));
  }
  return buffer.toString();
}

String _required(List<String> args, String name) {
  final value = _arg(args, name);
  if (value == null) throw ArgumentError('missing --$name');
  return value;
}

String? _arg(List<String> args, String name) {
  for (final arg in args) {
    if (arg.startsWith('--$name=')) return arg.substring(name.length + 3);
  }
  return null;
}
