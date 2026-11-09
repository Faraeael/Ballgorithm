import 'dart:convert';
import 'dart:io';

import 'package:simulation_core/simulation_core.dart';

/// Version-neutral game runner for M006 paired evaluation.
///
/// Runs cleanly under both the historical v6 checkpoint (`68018db9`) and the
/// current v7 baseline (`ac187b08`) using only common M004/M005 domain contracts.
void main(List<String> args) {
  String? manifestPath;
  String? outPath;
  String? label;

  for (final arg in args) {
    if (arg.startsWith('--manifest=')) {
      manifestPath = arg.substring('--manifest='.length);
    } else if (arg.startsWith('--out=')) {
      outPath = arg.substring('--out='.length);
    } else if (arg.startsWith('--label=')) {
      label = arg.substring('--label='.length);
    }
  }

  if (manifestPath == null || outPath == null) {
    stderr.writeln(
      'Usage: dart run tool/m006_pilot_runner.dart --manifest=<path> --out=<path> [--label=<v6|v7>]',
    );
    exit(1);
  }

  final manifestFile = File(manifestPath);
  if (!manifestFile.existsSync()) {
    stderr.writeln('Manifest not found: $manifestPath');
    exit(1);
  }

  final lines = manifestFile.readAsLinesSync();
  if (lines.isEmpty) {
    stderr.writeln('Manifest is empty');
    exit(1);
  }

  final header = lines.first.split(',');
  final seedIdx = header.indexOf('seed');
  final gameIdIdx = header.indexOf('gameId');
  final leagueSeedIdx = header.indexOf('leagueSeed');
  final homeTeamIdx = header.indexOf('homeTeamId');
  final awayTeamIdx = header.indexOf('awayTeamId');
  final typeIdx = header.indexOf('type');

  if (seedIdx < 0 || leagueSeedIdx < 0) {
    stderr.writeln('Invalid manifest header: ${lines.first}');
    exit(1);
  }

  final rows = lines.skip(1).where((line) => line.trim().isNotEmpty).toList();
  stdout.writeln(
    'Executing ${rows.length} games (label: ${label ?? "unspecified"})...',
  );

  final simulator = GameSimulator();
  final results = <Map<String, dynamic>>[];
  final stopwatch = Stopwatch()..start();

  for (final row in rows) {
    final parts = row.split(',');
    final seed = int.parse(parts[seedIdx].trim());
    final gameId = gameIdIdx >= 0 ? parts[gameIdIdx].trim() : 'game-$seed';
    final leagueSeed = int.parse(parts[leagueSeedIdx].trim());
    final homeTeamId = homeTeamIdx >= 0 ? parts[homeTeamIdx].trim() : 'team-1';
    final awayTeamId = awayTeamIdx >= 0 ? parts[awayTeamIdx].trim() : 'team-2';
    final isSynthetic =
        typeIdx >= 0 && parts[typeIdx].trim() == 'synthetic-stretch-five';

    final input = _buildInput(
      seed: seed,
      gameId: gameId,
      leagueSeed: leagueSeed,
      homeId: homeTeamId,
      awayId: awayTeamId,
      isSynthetic: isSynthetic,
    );
    final result = simulator.simulate(input);
    if (result.events.isEmpty || result.events.last is! GameEnded) {
      throw StateError('Game $gameId failed to reach GameEnded');
    }

    final analyzed = analyzeResult(result);
    results.add(analyzed);
  }

  stopwatch.stop();
  stdout.writeln(
    'Completed ${results.length} games in ${stopwatch.elapsedMilliseconds} ms.',
  );

  final outFile = File(outPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(results),
  );
  stdout.writeln('Wrote results to $outPath');
}

League buildSyntheticStretchFiveLeague(League baseLeague) {
  final team1CenterAttributes = PlayerAttributes(
    insideScoring: 75,
    midrange: 55,
    threePoint: 80,
    freeThrow: 75,
    passing: 60,
    ballHandling: 55,
    perimeterDefense: 50,
    interiorDefense: 65,
    rebounding: 70,
    athleticism: 60,
    stamina: 70,
    basketballIQ: 62,
  );

  final team2CenterAttributes = PlayerAttributes(
    insideScoring: 70,
    midrange: 65,
    threePoint: 78,
    freeThrow: 75,
    passing: 55,
    ballHandling: 50,
    perimeterDefense: 50,
    interiorDefense: 65,
    rebounding: 70,
    athleticism: 65,
    stamina: 70,
    basketballIQ: 60,
  );

  Player modCenter(Player orig, PlayerAttributes attributes) => Player(
    id: orig.id,
    firstName: orig.firstName,
    lastName: orig.lastName,
    position: orig.position,
    attributes: attributes,
  );

  Team modTeam(Team orig, String cId, PlayerAttributes attributes) => Team(
    id: orig.id,
    name: orig.name,
    abbreviation: orig.abbreviation,
    roster: Roster([
      for (final p in orig.players)
        if (p.id.value == cId) modCenter(p, attributes) else p,
    ]),
  );

  final home = modTeam(
    baseLeague.teams.first,
    'player-1-8',
    team1CenterAttributes,
  );
  final away = modTeam(
    baseLeague.teams[1],
    'player-2-5',
    team2CenterAttributes,
  );
  return League.create(
    id: baseLeague.id,
    name: baseLeague.name,
    config: baseLeague.config,
    teams: [home, away, ...baseLeague.teams.skip(2)],
  );
}

GameInput _buildInput({
  required int seed,
  required String gameId,
  required int leagueSeed,
  required String homeId,
  required String awayId,
  bool isSynthetic = false,
}) {
  final baseLeague = const LeagueGenerator().generate(
    GenerationConfig(seed: leagueSeed),
  );

  final league = isSynthetic
      ? buildSyntheticStretchFiveLeague(baseLeague)
      : baseLeague;

  final home = league.teams.firstWhere((t) => t.id.value == homeId);
  final away = league.teams.firstWhere((t) => t.id.value == awayId);
  final rules = GameRules.standard;

  TeamRotationPlan planFor(Team team, CourtLineup lineup) {
    final targets = RotationPlan.expandPreset(
      preset: RotationPreset.balanced,
      team: team,
      lineup: lineup,
      rules: rules,
    );
    return TeamRotationPlan.create(
      team: team,
      preset: RotationPreset.balanced,
      targets: [
        for (final player in team.players)
          RotationTarget(playerId: player.id, seconds: targets[player.id]!),
      ],
    );
  }

  final homeLineup = CourtLineup.defaultFor(home);
  final awayLineup = CourtLineup.defaultFor(away);

  return GameInput.create(
    gameId: gameId,
    league: league,
    homeTeamId: home.id,
    awayTeamId: away.id,
    homeLineup: homeLineup,
    awayLineup: awayLineup,
    seed: seed,
    rules: rules,
    rotationPlan: RotationPlan(
      home: planFor(home, homeLineup),
      away: planFor(away, awayLineup),
    ),
  );
}

final class _PlayerAcc {
  _PlayerAcc(this.playerId, this.teamId);
  final String playerId;
  final String teamId;
  int points = 0, fgm = 0, fga = 0, threePm = 0, threePa = 0;
  int secondsPlayed = 0, primaryFga = 0, secondaryFga = 0, neutralFga = 0;
  int stretchBigFga = 0, stretchBigThreePa = 0;
  int genuineCenterFga = 0, genuineCenterThreePa = 0;
  int registeredCenterBigFga = 0, registeredCenterBigThreePa = 0;
}

final class _TeamAcc {
  _TeamAcc(this.teamId);
  final String teamId;
  int points = 0, fgm = 0, fga = 0, threePm = 0, threePa = 0;
  int primaryFga = 0, secondaryFga = 0, neutralFga = 0;
  int fta = 0, turnovers = 0, possessions = 0;
  int stretchBigFga = 0, stretchBigThreePa = 0;
  int genuineCenterFga = 0, genuineCenterThreePa = 0;
  int registeredCenterBigFga = 0, registeredCenterBigThreePa = 0;
  int weakShooterFga = 0, weakShooterThreePa = 0;
}

Map<PlayerId, int> _deriveRoles(CourtLineup lineup) {
  final entries = <({PlayerId playerId, int score, int slotIndex})>[];
  for (var i = 0; i < lineup.slots.length; i++) {
    final p = lineup.playerAtSlotIndex(i);
    final score =
        3 * p.attributes.ballHandling +
        p.attributes.passing +
        p.attributes.basketballIQ;
    entries.add((playerId: p.id, score: score, slotIndex: i));
  }
  entries.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.slotIndex.compareTo(b.slotIndex);
  });
  // 0 -> primary, 1 -> secondary, 2 -> neutral
  final roles = <PlayerId, int>{};
  for (var i = 0; i < entries.length; i++) {
    roles[entries[i].playerId] = i == 0 ? 0 : (i == 1 ? 1 : 2);
  }
  return roles;
}

Team _findTeam(GameResult result, TeamId id) =>
    result.input.league.teams.firstWhere((team) => team.id == id);

Map<String, dynamic> analyzeResult(GameResult result) {
  final playerById = <String, Player>{};
  final players = <String, _PlayerAcc>{};
  final teams = <String, _TeamAcc>{};

  for (final teamId in [result.input.homeTeamId, result.input.awayTeamId]) {
    final team = _findTeam(result, teamId);
    teams[teamId.value] = _TeamAcc(teamId.value);
    for (final player in team.players) {
      playerById[player.id.value] = player;
      players[player.id.value] = _PlayerAcc(player.id.value, teamId.value);
    }
  }

  final active = <String, CourtLineup>{
    result.input.homeTeamId.value: result.input.homeLineup,
    result.input.awayTeamId.value: result.input.awayLineup,
  };
  final activeRoles = <String, Map<PlayerId, int>>{
    result.input.homeTeamId.value: _deriveRoles(result.input.homeLineup),
    result.input.awayTeamId.value: _deriveRoles(result.input.awayLineup),
  };

  var ledgerHomePoints = 0;
  var ledgerAwayPoints = 0;
  var currentPeriod = 0;
  var lastClock = 0;

  void accrue(int delta) {
    for (final lineup in active.values) {
      for (final p in lineup.players) {
        players[p.id.value]!.secondsPlayed += delta;
      }
    }
  }

  for (final event in result.ledger.events) {
    if (event is GameStarted || event is PeriodStarted) {
      currentPeriod = event.period;
      lastClock = event.gameClock;
    } else if (event is PeriodEnded) {
      accrue(lastClock);
      lastClock = 0;
    } else if (event.period == currentPeriod) {
      accrue(lastClock - event.gameClock);
      lastClock = event.gameClock;
    }

    if (event is Substitution) {
      final lineup = active[event.teamId]!;
      final slots = lineup.players;
      final index = lineup.slotIndexForPlayer(PlayerId(event.playerOutId));
      slots[index] = playerById[event.playerInId]!;
      final updated = CourtLineup.create(
        team: _findTeam(result, TeamId(event.teamId)),
        slotOrderedPlayers: slots,
      );
      active[event.teamId] = updated;
      activeRoles[event.teamId] = _deriveRoles(updated);
    } else if (event is FieldGoalAttempt) {
      final player = playerById[event.shooterId]!;
      final pMetric = players[event.shooterId]!;
      final tMetric = teams[event.teamId]!;
      pMetric.fga++;
      tMetric.fga++;
      if (event.made) {
        pMetric.fgm++;
        pMetric.points += event.shotValue;
        tMetric.fgm++;
        tMetric.points += event.shotValue;
        if (event.teamId == result.input.homeTeamId.value) {
          ledgerHomePoints += event.shotValue;
        } else {
          ledgerAwayPoints += event.shotValue;
        }
      }
      if (event.shotValue == 3) {
        pMetric.threePa++;
        tMetric.threePa++;
        if (event.made) {
          pMetric.threePm++;
          tMetric.threePm++;
        }
      }
      final role = activeRoles[event.teamId]![player.id] ?? 2;
      switch (role) {
        case 0:
          pMetric.primaryFga++;
          tMetric.primaryFga++;
          break;
        case 1:
          pMetric.secondaryFga++;
          tMetric.secondaryFga++;
          break;
        default:
          pMetric.neutralFga++;
          tMetric.neutralFga++;
          break;
      }
      final lineup = active[event.teamId]!;
      final occupiedSlot = lineup.slotOf(player.id);
      if ((occupiedSlot == Position.pf || occupiedSlot == Position.c) &&
          player.attributes.threePoint >= 70) {
        pMetric.stretchBigFga++;
        tMetric.stretchBigFga++;
        if (event.shotValue == 3) {
          pMetric.stretchBigThreePa++;
          tMetric.stretchBigThreePa++;
        }
      }
      final isGenuineCenter =
          (player.id.value == 'player-1-8' ||
              player.id.value == 'player-2-5') &&
          occupiedSlot == Position.c;
      if (isGenuineCenter) {
        pMetric.genuineCenterFga++;
        tMetric.genuineCenterFga++;
        if (event.shotValue == 3) {
          pMetric.genuineCenterThreePa++;
          tMetric.genuineCenterThreePa++;
        }
      }
      final isRegisteredCenterBig =
          (player.id.value == 'player-1-8' ||
              player.id.value == 'player-2-5') &&
          (occupiedSlot == Position.c || occupiedSlot == Position.pf);
      if (isRegisteredCenterBig) {
        pMetric.registeredCenterBigFga++;
        tMetric.registeredCenterBigFga++;
        if (event.shotValue == 3) {
          pMetric.registeredCenterBigThreePa++;
          tMetric.registeredCenterBigThreePa++;
        }
      }
      if (player.attributes.threePoint < 40) {
        tMetric.weakShooterFga++;
        if (event.shotValue == 3) {
          tMetric.weakShooterThreePa++;
        }
      }
    } else if (event is FreeThrowAttempt) {
      final tMetric = teams[event.teamId]!;
      tMetric.fta++;
      if (event.made) {
        players[event.shooterId]!.points++;
        tMetric.points++;
        if (event.teamId == result.input.homeTeamId.value) {
          ledgerHomePoints++;
        } else {
          ledgerAwayPoints++;
        }
      }
    } else if (event is Turnover) {
      teams[event.teamId]!.turnovers++;
    } else if (event is PossessionStarted) {
      teams[event.offenseTeamId]!.possessions++;
    }
  }

  final home = teams[result.input.homeTeamId.value]!;
  final away = teams[result.input.awayTeamId.value]!;

  final gamePossessions = home.possessions + away.possessions;
  var consistent =
      ledgerHomePoints == result.homeScore &&
      ledgerAwayPoints == result.awayScore &&
      gamePossessions == result.possessions;

  for (final entry in players.entries) {
    final p = entry.value;
    final box = result.boxScore.players[entry.key];
    consistent =
        consistent &&
        box != null &&
        box.points == p.points &&
        box.fgm == p.fgm &&
        box.fga == p.fga &&
        box.threePm == p.threePm &&
        box.threePa == p.threePa &&
        box.secondsPlayed == p.secondsPlayed;
  }
  for (final entry in teams.entries) {
    final t = entry.value;
    final box = result.boxScore.teams[entry.key];
    consistent =
        consistent &&
        box != null &&
        box.points == t.points &&
        box.fgm == t.fgm &&
        box.fga == t.fga &&
        box.threePm == t.threePm &&
        box.threePa == t.threePa &&
        box.fta == t.fta &&
        box.turnovers == t.turnovers;
  }

  if (!consistent) {
    throw StateError('Accounting inconsistent for seed ${result.input.seed}');
  }

  final gameFga = home.fga + away.fga;
  final gameFgm = home.fgm + away.fgm;
  final game3Pa = home.threePa + away.threePa;
  final game3Pm = home.threePm + away.threePm;
  final gameFta = home.fta + away.fta;
  final gameTov = home.turnovers + away.turnovers;

  final gamePrimaryFga = home.primaryFga + away.primaryFga;
  final gameSecondaryFga = home.secondaryFga + away.secondaryFga;
  final gameNeutralFga = home.neutralFga + away.neutralFga;

  final gameWeakFga = home.weakShooterFga + away.weakShooterFga;
  final gameWeak3Pa = home.weakShooterThreePa + away.weakShooterThreePa;

  final gameStretchFga = home.stretchBigFga + away.stretchBigFga;
  final gameStretch3Pa = home.stretchBigThreePa + away.stretchBigThreePa;

  double? share(int num, int den) => den == 0 ? null : num / den;

  final gameGenuineCenterFga = home.genuineCenterFga + away.genuineCenterFga;
  final gameGenuineCenterThreePa =
      home.genuineCenterThreePa + away.genuineCenterThreePa;
  final gameGenuineCenterThreePointShare = share(
    gameGenuineCenterThreePa,
    gameGenuineCenterFga,
  );

  final gameRegisteredCenterBigFga =
      home.registeredCenterBigFga + away.registeredCenterBigFga;
  final gameRegisteredCenterBigThreePa =
      home.registeredCenterBigThreePa + away.registeredCenterBigThreePa;
  final gameRegisteredCenterBigThreePointShare = share(
    gameRegisteredCenterBigThreePa,
    gameRegisteredCenterBigFga,
  );

  final c1Fga = players['player-1-8']?.genuineCenterFga ?? 0;
  final c2Fga = players['player-2-5']?.genuineCenterFga ?? 0;
  final centerExposureAny = (c1Fga >= 10 || c2Fga >= 10);
  final center1Exposure = (c1Fga >= 10);
  final center2Exposure = (c2Fga >= 10);
  final centerExposureBoth = (c1Fga >= 10 && c2Fga >= 10);

  final c1BigFga = players['player-1-8']?.registeredCenterBigFga ?? 0;
  final c2BigFga = players['player-2-5']?.registeredCenterBigFga ?? 0;
  final regCenterBigExposureAny = (c1BigFga >= 10 || c2BigFga >= 10);
  final regCenterBigExposureSame = (c1BigFga >= 10 && c2BigFga >= 10);
  var maxStretchPlayerFga = 0;
  for (final p in players.values) {
    if (p.stretchBigFga > maxStretchPlayerFga) {
      maxStretchPlayerFga = p.stretchBigFga;
    }
  }

  Map<String, dynamic> teamMap(_TeamAcc t) => {
    'teamId': t.teamId,
    'points': t.points,
    'fgm': t.fgm,
    'fga': t.fga,
    'threePm': t.threePm,
    'threePa': t.threePa,
    'fta': t.fta,
    'turnovers': t.turnovers,
    'possessions': t.possessions,
    'eFG': t.fga == 0 ? null : (t.fgm + 0.5 * t.threePm) / t.fga,
    'turnoversPer100': t.possessions == 0
        ? null
        : t.turnovers * 100 / t.possessions,
    'threePointShare': share(t.threePa, t.fga),
    'primaryFga': t.primaryFga,
    'secondaryFga': t.secondaryFga,
    'neutralFga': t.neutralFga,
    'primaryShare': share(t.primaryFga, t.fga),
    'secondaryShare': share(t.secondaryFga, t.fga),
    'neutralShare': share(t.neutralFga, t.fga),
    'weakShooterFga': t.weakShooterFga,
    'weakShooterThreePa': t.weakShooterThreePa,
    'weakShooterThreePointShare': share(t.weakShooterThreePa, t.weakShooterFga),
    'stretchBigFga': t.stretchBigFga,
    'stretchBigThreePa': t.stretchBigThreePa,
    'stretchBigThreePointShare': share(t.stretchBigThreePa, t.stretchBigFga),
    'genuineCenterFga': t.genuineCenterFga,
    'genuineCenterThreePa': t.genuineCenterThreePa,
    'genuineCenterThreePointShare': share(
      t.genuineCenterThreePa,
      t.genuineCenterFga,
    ),
    'registeredCenterBigFga': t.registeredCenterBigFga,
    'registeredCenterBigThreePa': t.registeredCenterBigThreePa,
    'registeredCenterBigThreePointShare': share(
      t.registeredCenterBigThreePa,
      t.registeredCenterBigFga,
    ),
  };

  return {
    'seed': result.input.seed,
    'gameId': result.input.gameId,
    'homeScore': result.homeScore,
    'awayScore': result.awayScore,
    'totalPoints': result.homeScore + result.awayScore,
    'possessions': gamePossessions,
    'fgm': gameFgm,
    'fga': gameFga,
    'threePm': game3Pm,
    'threePa': game3Pa,
    'fta': gameFta,
    'turnovers': gameTov,
    'eFG': gameFga == 0 ? null : (gameFgm + 0.5 * game3Pm) / gameFga,
    'turnoversPer100': gamePossessions == 0
        ? null
        : gameTov * 100 / gamePossessions,
    'threePointShare': share(game3Pa, gameFga),
    'primaryFga': gamePrimaryFga,
    'secondaryFga': gameSecondaryFga,
    'neutralFga': gameNeutralFga,
    'primaryShare': share(gamePrimaryFga, gameFga),
    'secondaryShare': share(gameSecondaryFga, gameFga),
    'neutralShare': share(gameNeutralFga, gameFga),
    'weakShooterFga': gameWeakFga,
    'weakShooterThreePa': gameWeak3Pa,
    'weakShooterThreePointShare': share(gameWeak3Pa, gameWeakFga),
    'weakEligible': gameWeakFga >= 20,
    'stretchBigFga': gameStretchFga,
    'stretchBigThreePa': gameStretch3Pa,
    'stretchBigThreePointShare': share(gameStretch3Pa, gameStretchFga),
    'stretchEligible': maxStretchPlayerFga >= 10,
    'maxStretchPlayerFga': maxStretchPlayerFga,
    'stretchCenterFga': gameGenuineCenterFga,
    'stretchCenterThreePa': gameGenuineCenterThreePa,
    'stretchCenterThreePointShare': gameGenuineCenterThreePointShare,
    'centerExposureAny': centerExposureAny,
    'center1Exposure': center1Exposure,
    'center2Exposure': center2Exposure,
    'centerExposureBoth': centerExposureBoth,
    'center1Fga': c1Fga,
    'center2Fga': c2Fga,
    'registeredCenterBigFga': gameRegisteredCenterBigFga,
    'registeredCenterBigThreePa': gameRegisteredCenterBigThreePa,
    'registeredCenterBigThreePointShare':
        gameRegisteredCenterBigThreePointShare,
    'regCenter1BigFga': c1BigFga,
    'regCenter2BigFga': c2BigFga,
    'regCenterBigExposureAny': regCenterBigExposureAny,
    'regCenterBigExposureSame': regCenterBigExposureSame,
    'accountingConsistent': consistent,
    'homeTeam': teamMap(home),
    'awayTeam': teamMap(away),
    'players': [
      for (final p in players.values)
        {
          'playerId': p.playerId,
          'teamId': p.teamId,
          'points': p.points,
          'fgm': p.fgm,
          'fga': p.fga,
          'threePm': p.threePm,
          'threePa': p.threePa,
          'secondsPlayed': p.secondsPlayed,
          'minutes': p.secondsPlayed / 60,
          'fgaPer36': p.secondsPlayed < 240
              ? null
              : p.fga * 2160 / p.secondsPlayed,
          'primaryFga': p.primaryFga,
          'secondaryFga': p.secondaryFga,
          'neutralFga': p.neutralFga,
          'stretchBigFga': p.stretchBigFga,
          'stretchBigThreePa': p.stretchBigThreePa,
          'genuineCenterFga': p.genuineCenterFga,
          'genuineCenterThreePa': p.genuineCenterThreePa,
          'registeredCenterBigFga': p.registeredCenterBigFga,
          'registeredCenterBigThreePa': p.registeredCenterBigThreePa,
        },
    ],
  };
}
