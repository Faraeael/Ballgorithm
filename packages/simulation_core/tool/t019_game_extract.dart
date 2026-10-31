/// T019 game evidence extractor (deterministic reproduction, read-only).
///
/// ```
/// cd packages/simulation_core
/// dart run tool/t019_game_extract.dart \
///   --raw=../../specs/002-possession-simulation/amendment-004-heldout/v4-heldout-raw.json \
///   --slots=55,68,117,153,455,771 --out=<dir>/t019-games.json
/// ```
///
/// For each requested slot this tool:
///   1. rebuilds the EXACT historical v4 input (gameId, seed, matchupIndex,
///      orientation) recorded in the committed held-out artifact,
///   2. executes the pinned v4 model exactly once,
///   3. compares every deterministically recorded aggregate against that record,
///   4. emits team box scores, player box scores, period scores and turnover /
///      foul breakdowns read from the authoritative ledger and accounting.
///
/// It is evidence extraction, not a new cohort: it accepts no seed, team or
/// matchup arguments, never writes gameplay state and fails loudly on any
/// aggregate mismatch. It does not change simulation behaviour.
library;

import 'dart:convert';
import 'dart:io';

import 'package:simulation_core/simulation_core.dart';

import 't015_metrics.dart';

const int leagueSeed = 20261028;

/// Fields compared verbatim against the committed record.
const List<String> comparedIntFields = [
  'homeScore',
  'awayScore',
  'combinedPoints',
  'periods',
  'overtimes',
  'events',
  'homeStarted',
  'awayStarted',
  'homeCompleted',
  'awayCompleted',
  'completed',
  'homePeriodEnd',
  'awayPeriodEnd',
  'homeFga',
  'awayFga',
  'fga',
  'homeFgm',
  'awayFgm',
  'fgm',
  'homeThreePa',
  'awayThreePa',
  'threePa',
  'homeThreePm',
  'awayThreePm',
  'threePm',
  'homeFta',
  'awayFta',
  'fta',
  'homeFtm',
  'awayFtm',
  'ftm',
  'homeOreb',
  'awayOreb',
  'oreb',
  'homeDreb',
  'awayDreb',
  'dreb',
  'homeTov',
  'awayTov',
  'tov',
  'homePf',
  'awayPf',
  'personalFouls',
  'homeNonShootingFouls',
  'awayNonShootingFouls',
  'nonShootingFouls',
  'shotClockTov',
  'stealTov',
  'nonStealTov',
  'offensiveFoulTov',
  'sampledPhases',
  'actionPhases',
  'freshPhases',
  'freshViolations',
  'orebPhases',
  'orebViolations',
  'retFoulPhases',
  'retFoulViolations',
  'retFoul14Phases',
  'retFoul14Violations',
];

const List<String> comparedStringFields = [
  'gameId',
  'homeTeamId',
  'awayTeamId',
  'inputFingerprint',
];

Map<String, Object?> playerStats(
  PlayerBoxScore box,
  Player player, {
  required bool started,
}) => {
  'playerId': box.playerId,
  'name': '${player.firstName} ${player.lastName}',
  'position': player.position.name,
  'started': started,
  'minutes': 'NOT_MODELED',
  'points': box.points,
  'fgm': box.fgm,
  'fga': box.fga,
  'twoPm': box.twoPm,
  'twoPa': box.twoPa,
  'threePm': box.threePm,
  'threePa': box.threePa,
  'ftm': box.ftm,
  'fta': box.fta,
  'oreb': box.oreb,
  'dreb': box.dreb,
  'rebounds': box.rebounds,
  'assists': box.assists,
  'steals': box.steals,
  'blocks': box.blocks,
  'turnovers': box.turnovers,
  'personalFouls': box.personalFouls,
  'ratings': {
    'insideScoring': player.attributes.insideScoring,
    'midrange': player.attributes.midrange,
    'threePoint': player.attributes.threePoint,
    'freeThrow': player.attributes.freeThrow,
    'passing': player.attributes.passing,
    'ballHandling': player.attributes.ballHandling,
    'perimeterDefense': player.attributes.perimeterDefense,
    'interiorDefense': player.attributes.interiorDefense,
    'rebounding': player.attributes.rebounding,
    'athleticism': player.attributes.athleticism,
    'stamina': player.attributes.stamina,
    'basketballIQ': player.attributes.basketballIQ,
  },
};

Map<String, Object?> teamBox(TeamBoxScore box) => {
  'points': box.points,
  'fgm': box.fgm,
  'fga': box.fga,
  'twoPm': box.twoPm,
  'twoPa': box.twoPa,
  'threePm': box.threePm,
  'threePa': box.threePa,
  'ftm': box.ftm,
  'fta': box.fta,
  'assists': box.assists,
  'oreb': box.oreb,
  'dreb': box.dreb,
  'rebounds': box.rebounds,
  'turnovers': box.turnovers,
  'steals': box.steals,
  'blocks': box.blocks,
  'personalFouls': box.personalFouls,
};

void main(List<String> args) {
  String? rawPath;
  String? outPath;
  final slots = <int>[];
  for (final arg in args) {
    if (arg.startsWith('--raw=')) {
      rawPath = arg.split('=').last;
    } else if (arg.startsWith('--out=')) {
      outPath = arg.split('=').last;
    } else if (arg.startsWith('--slots=')) {
      slots.addAll(arg.split('=').last.split(',').map(int.parse));
    } else {
      stderr.writeln('unknown argument: $arg');
      exitCode = 64;
      return;
    }
  }
  if (rawPath == null || outPath == null || slots.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/t019_game_extract.dart --raw=<heldout json> '
      '--slots=a,b,c --out=<output json>',
    );
    exitCode = 64;
    return;
  }

  final raw =
      jsonDecode(File(rawPath).readAsStringSync()) as Map<String, Object?>;
  final rows = (raw['rows']! as List).cast<Map<String, Object?>>();
  final bySlot = {for (final row in rows) row['slot']! as int: row};

  final league = const LeagueGenerator().generate(
    const GenerationConfig(seed: leagueSeed),
  );
  final teams = [...league.teams]
    ..sort((a, b) => a.id.value.compareTo(b.id.value));
  final pairs = <(Team, Team)>[
    for (var i = 0; i < 8; i++)
      for (var j = i + 1; j < 8; j++)
        for (var orientation = 0; orientation < 2; orientation++)
          orientation == 0 ? (teams[i], teams[j]) : (teams[j], teams[i]),
  ];
  final playersById = <String, Player>{
    for (final team in teams)
      for (final player in team.roster.players) player.id.value: player,
  };

  final games = <Map<String, Object?>>[];
  final allMismatches = <String>[];

  for (final slot in slots) {
    final recorded = bySlot[slot];
    if (recorded == null) {
      stderr.writeln('slot $slot not present in $rawPath');
      exitCode = 66;
      return;
    }
    final matchupIndex = recorded['matchupIndex']! as int;
    final orientation = recorded['orientation']! as int;
    final seed = recorded['seed']! as int;
    final gameId = recorded['gameId']! as String;
    final (home, away) = pairs[matchupIndex];
    if ((matchupIndex % 2) != orientation) {
      stderr.writeln(
        'slot $slot: orientation $orientation inconsistent with matchup',
      );
      exitCode = 66;
      return;
    }

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
    // Replay and accounting must reconcile before any evidence is emitted.
    final validated = GameEventReducer.validate(input, result.ledger);
    final accounted = EventAccounting.aggregate(validated);
    final accountedHome = accounted.teams[home.id.value]!.points;
    final accountedAway = accounted.teams[away.id.value]!.points;
    if (accountedHome != result.homeScore ||
        accountedAway != result.awayScore) {
      stderr.writeln('slot $slot: accounting mismatch');
      exitCode = 68;
      return;
    }

    // Phase counters, recomputed exactly as the held-out runner did.
    var sampledPhases = 0;
    var actionPhases = 0;
    var freshPhases = 0;
    var freshViolations = 0;
    var orebPhases = 0;
    var orebViolations = 0;
    var retFoulPhases = 0;
    var retFoulViolations = 0;
    var retFoul14Phases = 0;
    var retFoul14Violations = 0;
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

    final homeBox = result.boxScore.teams[home.id.value]!;
    final awayBox = result.boxScore.teams[away.id.value]!;
    final homePoss = possessionCounts(result.events, home.id);
    final awayPoss = possessionCounts(result.events, away.id);

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
      } else if (event is PersonalFoul && event.kind == FoulKind.nonShooting) {
        if (event.committingTeamId == home.id.value) {
          homeNonShootingFouls++;
        } else {
          awayNonShootingFouls++;
        }
      }
    }

    final observed = <String, Object?>{
      'homeScore': result.homeScore,
      'awayScore': result.awayScore,
      'combinedPoints': result.homeScore + result.awayScore,
      'periods': result.periodsPlayed,
      'overtimes': result.overtimes,
      'events': result.events.length,
      'homeStarted': homePoss.started,
      'awayStarted': awayPoss.started,
      'homeCompleted': homePoss.completed,
      'awayCompleted': awayPoss.completed,
      'completed': homePoss.completed + awayPoss.completed,
      'homePeriodEnd': homePoss.periodEnd,
      'awayPeriodEnd': awayPoss.periodEnd,
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
      'homeOreb': homeBox.oreb,
      'awayOreb': awayBox.oreb,
      'oreb': homeBox.oreb + awayBox.oreb,
      'homeDreb': homeBox.dreb,
      'awayDreb': awayBox.dreb,
      'dreb': homeBox.dreb + awayBox.dreb,
      'homeTov': homeBox.turnovers,
      'awayTov': awayBox.turnovers,
      'tov': homeBox.turnovers + awayBox.turnovers,
      'homePf': homeBox.personalFouls,
      'awayPf': awayBox.personalFouls,
      'personalFouls': homeBox.personalFouls + awayBox.personalFouls,
      'homeNonShootingFouls': homeNonShootingFouls,
      'awayNonShootingFouls': awayNonShootingFouls,
      'nonShootingFouls': homeNonShootingFouls + awayNonShootingFouls,
      'shotClockTov': shotClockTov,
      'stealTov': stealTov,
      'nonStealTov': nonStealTov,
      'offensiveFoulTov': offensiveFoulTov,
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
      'gameId': input.gameId,
      'homeTeamId': home.id.value,
      'awayTeamId': away.id.value,
      'inputFingerprint': GameFingerprint.of(input),
    };

    final mismatches = <Map<String, Object?>>[];
    for (final field in comparedIntFields) {
      if (observed[field] != recorded[field]) {
        mismatches.add({
          'field': field,
          'recorded': recorded[field],
          'observed': observed[field],
        });
      }
    }
    for (final field in comparedStringFields) {
      if (observed[field] != recorded[field]) {
        mismatches.add({
          'field': field,
          'recorded': recorded[field],
          'observed': observed[field],
        });
      }
    }
    for (final mismatch in mismatches) {
      allMismatches.add(
        'slot $slot: ${mismatch['field']} recorded='
        '${mismatch['recorded']} observed=${mismatch['observed']}',
      );
    }

    // --- turnout / foul detail from the authoritative ledger ---
    final turnoverByTeam = <String, Map<String, int>>{};
    for (final teamId in [home.id.value, away.id.value]) {
      turnoverByTeam[teamId] = {
        'steal': 0,
        'nonSteal': 0,
        'offensiveFoul': 0,
        'shotClock': 0,
      };
    }
    final stealCreditedTo = <String, int>{};
    final stealTakenFrom = <String, int>{};
    final offensiveFoulsByPlayer = <String, int>{};
    final foulsByPlayerAndKind = <String, Map<String, int>>{};
    var liveMisses = 0;
    var andOnes = 0;
    for (final event in result.events) {
      if (event is Turnover) {
        final bucket = turnoverByTeam[event.teamId]!;
        switch (event.reason) {
          case TurnoverReason.steal:
            bucket['steal'] = bucket['steal']! + 1;
            stealTakenFrom[event.playerId] =
                (stealTakenFrom[event.playerId] ?? 0) + 1;
          case TurnoverReason.nonSteal:
            bucket['nonSteal'] = bucket['nonSteal']! + 1;
          case TurnoverReason.offensiveFoul:
            bucket['offensiveFoul'] = bucket['offensiveFoul']! + 1;
            offensiveFoulsByPlayer[event.playerId] =
                (offensiveFoulsByPlayer[event.playerId] ?? 0) + 1;
          case TurnoverReason.shotClock:
            bucket['shotClock'] = bucket['shotClock']! + 1;
        }
        final thief = event.stolenById;
        if (thief != null) {
          stealCreditedTo[thief] = (stealCreditedTo[thief] ?? 0) + 1;
        }
      } else if (event is PersonalFoul) {
        final perPlayer = foulsByPlayerAndKind.putIfAbsent(
          event.committingPlayerId,
          () => {'shooting': 0, 'nonShooting': 0, 'offensive': 0},
        );
        perPlayer[event.kind.name] = (perPlayer[event.kind.name] ?? 0) + 1;
      } else if (event is FieldGoalAttempt) {
        if (!event.made) liveMisses++;
        if (event.andOne) andOnes++;
      }
    }

    // Every modelled lineup is the five positional starters; there are no
    // substitutions, so all dressed players are starters for the whole game.
    final starters = <String>{
      ...ActiveLineup.defaultFor(home).playerIds,
      ...ActiveLineup.defaultFor(away).playerIds,
    };

    games.add({
      'slot': slot,
      'matchupIndex': matchupIndex,
      'pairIndex': matchupIndex ~/ 2,
      'orientation': orientation,
      'seed': seed,
      'gameId': gameId,
      'inputFingerprint': observed['inputFingerprint'],
      'homeTeamId': home.id.value,
      'awayTeamId': away.id.value,
      'simulationVersion': gameSimulationVersion,
      'rulesVersion': gameRulesVersion,
      'actionDurationModelVersion': gameActionDurationModelVersion,
      'inputFingerprintMatchesRecord':
          observed['inputFingerprint'] == recorded['inputFingerprint'],
      'aggregateMismatches': mismatches,
      'result': {
        'homeScore': result.homeScore,
        'awayScore': result.awayScore,
        'periods': result.periodsPlayed,
        'overtimes': result.overtimes,
        'events': result.events.length,
        'periodPoints': {
          for (final entry in result.boxScore.periodPoints.entries)
            entry.key: {
              for (final period in entry.value.keys.toList()..sort())
                '$period': entry.value[period],
            },
        },
      },
      'teamBox': {
        home.id.value: teamBox(homeBox),
        away.id.value: teamBox(awayBox),
      },
      'players': [
        for (final entry
            in result.boxScore.players.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key)))
          if (playersById.containsKey(entry.key))
            playerStats(
              entry.value,
              playersById[entry.key]!,
              started: starters.contains(entry.key),
            ),
      ],
      'turnoversByTeam': turnoverByTeam,
      'stealsCreditedTo': stealCreditedTo,
      'stealsTakenFrom': stealTakenFrom,
      'offensiveFoulsByPlayer': offensiveFoulsByPlayer,
      'foulsByPlayerAndKind': foulsByPlayerAndKind,
      'liveMisses': liveMisses,
      'andOnes': andOnes,
      'phaseTrace': {
        'sampledPhases': sampledPhases,
        'actionPhases': actionPhases,
        'contexts': {
          'fresh': {'phases': freshPhases, 'violations': freshViolations},
          'oreb': {'phases': orebPhases, 'violations': orebViolations},
          'retainedFoul': {
            'phases': retFoulPhases,
            'violations': retFoulViolations,
          },
          'retainedFoulAt14': {
            'phases': retFoul14Phases,
            'violations': retFoul14Violations,
          },
        },
      },
    });
  }

  final payload = <String, Object?>{
    'tool': 't019_game_extract.dart',
    'purpose': 'deterministic reproduction of already-selected held-out games',
    'sourceArtifact': rawPath,
    'leagueSeed': leagueSeed,
    'selectionRule':
        'slots pre-selected by the documented T019 rule (median / min / max '
        'combined points, most shot-clock violations, most offensive fouls, '
        'most overtimes); this tool accepts no seed, team or matchup input',
    'versions': {
      'simulation': gameSimulationVersion,
      'rules': gameRulesVersion,
      'eventSchema': gameEventSchemaVersion,
      'actionDurationModel': gameActionDurationModelVersion,
      'fingerprint': gameFingerprintVersion,
    },
    'games': games,
    'mismatchCount': allMismatches.length,
    'mismatches': allMismatches,
  };
  File(outPath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
  );
  stdout.writeln('wrote ${games.length} games to $outPath');
  stdout.writeln('aggregate mismatches: ${allMismatches.length}');
  for (final mismatch in allMismatches) {
    stdout.writeln('  MISMATCH $mismatch');
  }
  if (allMismatches.isNotEmpty) exitCode = 67;
}
