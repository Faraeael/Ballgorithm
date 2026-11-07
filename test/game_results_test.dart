import 'dart:async';

import 'package:basketball_manager/features/game/game_runner.dart';
import 'package:basketball_manager/features/game/game_screen.dart';
import 'package:basketball_manager/features/game/game_seed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_manager/features/game/participation_view.dart';
import 'package:simulation_core/simulation_core.dart';

import 'game_fixtures.dart';

const _config = GenerationConfig(seed: 20261028);
const _homeIndex = 3;
const _awayIndex = 5;

class _ControlledRunner {
  final List<GameRequest> requests = <GameRequest>[];
  final List<Completer<GameResult>> pending = <Completer<GameResult>>[];

  Future<GameResult> run(GameRequest request) {
    requests.add(request);
    final completer = Completer<GameResult>();
    pending.add(completer);
    return completer.future;
  }
}

GameRequest _request(League league, int rematchIndex) => GameRequest(
  league: league,
  homeTeamId: league.teams[_homeIndex].id,
  awayTeamId: league.teams[_awayIndex].id,
  seed: deriveGameSeed(
    leagueSeed: league.config.seed,
    homeIndex: _homeIndex,
    awayIndex: _awayIndex,
    rematchIndex: rematchIndex,
  ),
);

/// Deterministic fixture: the same input the worker builds, simulated locally.
GameResult _simulate(GameRequest request) {
  final league = request.league;
  final homeTeam = league.teams.singleWhere(
    (team) => team.id.value == request.homeTeamId.value,
  );
  final awayTeam = league.teams.singleWhere(
    (team) => team.id.value == request.awayTeamId.value,
  );
  return GameSimulator().simulate(
    GameInput.create(
      gameId:
          '${request.homeTeamId.value}-${request.awayTeamId.value}-'
          '${request.seed}',
      league: league,
      homeTeamId: request.homeTeamId,
      awayTeamId: request.awayTeamId,
      homeLineup: request.homeLineup ?? CourtLineup.defaultFor(homeTeam),
      awayLineup: request.awayLineup ?? CourtLineup.defaultFor(awayTeam),
      seed: request.seed,
      rules: GameRules.standard,
      rotationPlan: request.rotationPlan,
    ),
  );
}

/// Tall surface so the whole results list is built; layout acceptance at phone
/// widths is T025 work.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pumpGame(
  WidgetTester tester,
  GameRequest request,
  Future<GameResult> Function(GameRequest) runner,
) async {
  _useTallSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: GameScreen(
        key: ValueKey('game-${request.seed}'),
        request: request,
        runner: runner,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpGameOnRoute(
  WidgetTester tester,
  GameRequest request,
  Future<GameResult> Function(GameRequest) runner,
) async {
  _useTallSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey('open-game'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) =>
                    GameScreen(request: request, runner: runner),
              ),
            ),
            child: const Text('league'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-game')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _goBack(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Copy of the generated league with one renamed player, built through the
/// canonical JSON round trip so no model is mutated.
League _leagueWithLongPlayerName(
  League league, {
  required int teamIndex,
  required int playerIndex,
  required String firstName,
  required String lastName,
}) {
  final json = league.toJson();
  final teams = json['teams']! as List<Object?>;
  final team = teams[teamIndex]! as Map<String, Object?>;
  final roster = team['roster']! as Map<String, Object?>;
  final players = roster['players']! as List<Object?>;
  final player = players[playerIndex]! as Map<String, Object?>;
  player['firstName'] = firstName;
  player['lastName'] = lastName;
  return League.fromJson(json);
}

String _text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

void main() {
  late League league;
  late GameRequest baseRequest;
  late GameResult base;
  late GameRequest overtimeRequest;
  late GameResult overtime;

  setUpAll(() {
    league = const LeagueGenerator().generate(_config);
    baseRequest = _request(league, 0);
    base = _simulate(baseRequest);

    overtimeRequest = baseRequest;
    overtime = base;
    outer:
    for (var home = 0; home < league.teams.length; home++) {
      for (var away = 0; away < league.teams.length; away++) {
        if (home == away) continue;
        for (var rematch = 0; rematch < 48; rematch++) {
          final candidate = GameRequest(
            league: league,
            homeTeamId: league.teams[home].id,
            awayTeamId: league.teams[away].id,
            seed: deriveGameSeed(
              leagueSeed: league.config.seed,
              homeIndex: home,
              awayIndex: away,
              rematchIndex: rematch,
            ),
          );
          final result = _simulate(candidate);
          if (result.overtimes > 0) {
            overtimeRequest = candidate;
            overtime = result;
            break outer;
          }
        }
      }
    }
  });

  testWidgets('scoreboard shows team identity, scores and seed', (
    tester,
  ) async {
    final controlled = _ControlledRunner();
    await _pumpGame(tester, baseRequest, controlled.run);
    controlled.pending.single.complete(base);
    await tester.pump();

    final home = league.teams[_homeIndex];
    final away = league.teams[_awayIndex];
    expect(
      _text(tester, const ValueKey('result-score-away')),
      '${base.awayScore}',
    );
    expect(
      _text(tester, const ValueKey('result-score-home')),
      '${base.homeScore}',
    );
    expect(find.text('${away.abbreviation} · ${away.name}'), findsOneWidget);
    expect(find.text('${home.abbreviation} · ${home.name}'), findsOneWidget);
    expect(
      _text(tester, const ValueKey('result-seed')),
      'Seed ${describeGameSeed(baseRequest.seed)}',
    );
    expect(find.byKey(const ValueKey('result-overtime')), findsNothing);
  });

  testWidgets('winner is the team with the higher score', (tester) async {
    final controlled = _ControlledRunner();
    await _pumpGame(tester, baseRequest, controlled.run);
    controlled.pending.single.complete(base);
    await tester.pump();

    final winner = league.teams.singleWhere(
      (team) => team.id.value == base.winnerTeamId.value,
    );
    expect(
      _text(tester, const ValueKey('result-winner')),
      'Winner: ${winner.name}',
    );
  });

  testWidgets('period table shows the authoritative period points', (
    tester,
  ) async {
    final controlled = _ControlledRunner();
    await _pumpGame(tester, baseRequest, controlled.run);
    controlled.pending.single.complete(base);
    await tester.pump();

    expect(base.periodsPlayed, 4);
    for (final role in ['home', 'away']) {
      final teamId = role == 'home'
          ? baseRequest.homeTeamId.value
          : baseRequest.awayTeamId.value;
      final points = base.boxScore.periodPoints[teamId]!;
      for (var period = 1; period <= base.periodsPlayed; period++) {
        expect(
          _text(tester, ValueKey('period-$role-$teamId-$period')),
          '${points[period]}',
          reason: '$role period $period',
        );
      }
    }
    expect(find.text('OT1'), findsNothing);
  });

  testWidgets('overtime game shows OT periods and indicator', (tester) async {
    expect(overtime.overtimes, greaterThan(0), reason: 'overtime fixture');
    final controlled = _ControlledRunner();
    await _pumpGame(tester, overtimeRequest, controlled.run);
    controlled.pending.single.complete(overtime);
    await tester.pump();

    expect(
      _text(tester, const ValueKey('result-overtime')),
      '${overtime.overtimes} OT',
    );
    expect(find.text('OT1'), findsOneWidget);
    for (final role in ['home', 'away']) {
      final teamId = role == 'home'
          ? overtimeRequest.homeTeamId.value
          : overtimeRequest.awayTeamId.value;
      final points = overtime.boxScore.periodPoints[teamId]!;
      for (var period = 1; period <= overtime.periodsPlayed; period++) {
        expect(
          _text(tester, ValueKey('period-$role-$teamId-$period')),
          '${points[period]}',
          reason: '$role period $period',
        );
      }
    }
  });

  testWidgets('team statistics match the TeamBoxScore fields', (tester) async {
    final controlled = _ControlledRunner();
    await _pumpGame(tester, baseRequest, controlled.run);
    controlled.pending.single.complete(base);
    await tester.pump();

    final homeId = baseRequest.homeTeamId.value;
    final awayId = baseRequest.awayTeamId.value;
    final home = base.boxScore.teams[homeId]!;
    final away = base.boxScore.teams[awayId]!;

    final expected = <String, (String, String)>{
      'PTS': ('${home.points}', '${away.points}'),
      'FG': ('${home.fgm}/${home.fga}', '${away.fgm}/${away.fga}'),
      '3PT': (
        '${home.threePm}/${home.threePa}',
        '${away.threePm}/${away.threePa}',
      ),
      'FT': ('${home.ftm}/${home.fta}', '${away.ftm}/${away.fta}'),
      'REB': ('${home.rebounds}', '${away.rebounds}'),
      'AST': ('${home.assists}', '${away.assists}'),
      'STL': ('${home.steals}', '${away.steals}'),
      'BLK': ('${home.blocks}', '${away.blocks}'),
      'TOV': ('${home.turnovers}', '${away.turnovers}'),
      'PF': ('${home.personalFouls}', '${away.personalFouls}'),
    };
    for (final entry in expected.entries) {
      expect(
        _text(tester, ValueKey('team-stat-${entry.key}-$homeId')),
        entry.value.$1,
        reason: '${entry.key} home',
      );
      expect(
        _text(tester, ValueKey('team-stat-${entry.key}-$awayId')),
        entry.value.$2,
        reason: '${entry.key} away',
      );
    }
  });

  testWidgets('participants list starters then entrants, without duplicates', (
    tester,
  ) async {
    final controlled = _ControlledRunner();
    await _pumpGame(tester, baseRequest, controlled.run);
    controlled.pending.single.complete(base);
    await tester.pump();

    List<String> participants(TeamId teamId) {
      final starters = base.input.lineupFor(teamId).playerIds;
      final entrants = <String>[];
      final seen = {...starters};
      for (final event in base.events) {
        if (event is Substitution &&
            event.teamId == teamId.value &&
            seen.add(event.playerInId)) {
          entrants.add(event.playerInId);
        }
      }
      return [...starters, ...entrants];
    }

    final totalEntrants = [
      for (final team in [league.teams[_awayIndex], league.teams[_homeIndex]])
        participants(team.id).length - 5,
    ].fold<int>(0, (sum, count) => sum + count);
    expect(totalEntrants, greaterThan(0), reason: 'fixture has substitutes');

    for (final team in [league.teams[_awayIndex], league.teams[_homeIndex]]) {
      final expected = participants(team.id);
      expect(expected.length, greaterThanOrEqualTo(5));
      final ordered = [...expected]
        ..sort(
          (a, b) => tester
              .getTopLeft(find.byKey(ValueKey('player-row-$a')))
              .dy
              .compareTo(
                tester.getTopLeft(find.byKey(ValueKey('player-row-$b'))).dy,
              ),
        );
      expect(ordered, expected, reason: 'entry order for ${team.id.value}');
      expect(expected.toSet(), hasLength(expected.length));

      for (final (index, id) in expected.indexed) {
        expect(
          _text(tester, ValueKey('player-role-$id')),
          index < 5 ? 'STARTER' : 'SUBSTITUTE',
        );
        expect(
          _text(tester, ValueKey('player-stat-$id-MIN')),
          allOf(matches(RegExp(r'^\d+:\d{2}$'))),
        );
      }

      final nonParticipant = team.players
          .map((player) => player.id.value)
          .firstWhere((id) => !expected.contains(id));
      expect(
        find.byKey(ValueKey('player-row-$nonParticipant')),
        findsNothing,
        reason: 'non-participants are hidden for ${team.id.value}',
      );
    }
  });

  testWidgets(
    'player names, positions and statistics come from the box score',
    (tester) async {
      final controlled = _ControlledRunner();
      await _pumpGame(tester, baseRequest, controlled.run);
      controlled.pending.single.complete(base);
      await tester.pump();

      final teams = [league.teams[_homeIndex], league.teams[_awayIndex]];
      for (final team in teams) {
        final lineup = base.input.lineupFor(team.id).playerIds;
        final shown = <String>[...lineup];
        final seen = {...lineup};
        for (final event in base.events) {
          if (event is Substitution &&
              event.teamId == team.id.value &&
              seen.add(event.playerInId)) {
            shown.add(event.playerInId);
          }
        }
        for (final playerId in shown) {
          final player = team.players.singleWhere(
            (candidate) => candidate.id.value == playerId,
          );
          final box = base.boxScore.players[playerId]!;
          expect(
            _text(tester, ValueKey('player-name-$playerId')),
            player.fullName,
          );
          expect(
            _text(tester, ValueKey('player-stat-$playerId-POS')),
            player.position.shortName,
          );
          expect(
            _text(tester, ValueKey('player-stat-$playerId-PTS')),
            '${box.points}',
          );
          expect(
            _text(tester, ValueKey('player-stat-$playerId-FG')),
            '${box.fgm}/${box.fga}',
          );
          expect(
            _text(tester, ValueKey('player-stat-$playerId-3PT')),
            '${box.threePm}/${box.threePa}',
          );
          expect(
            _text(tester, ValueKey('player-stat-$playerId-FT')),
            '${box.ftm}/${box.fta}',
          );
          expect(
            _text(tester, ValueKey('player-stat-$playerId-REB')),
            '${box.rebounds}',
          );
          expect(
            _text(tester, ValueKey('player-stat-$playerId-AST')),
            '${box.assists}',
          );
          expect(
            _text(tester, ValueKey('player-stat-$playerId-STL')),
            '${box.steals}',
          );
          expect(
            _text(tester, ValueKey('player-stat-$playerId-BLK')),
            '${box.blocks}',
          );
          expect(
            _text(tester, ValueKey('player-stat-$playerId-TOV')),
            '${box.turnovers}',
          );
          expect(
            _text(tester, ValueKey('player-stat-$playerId-PF')),
            '${box.personalFouls}',
          );
          expect(
            _text(tester, ValueKey('player-stat-$playerId-MIN')),
            _minutes(box.secondsPlayed),
          );
        }
      }
    },
  );

  testWidgets('long player names render in full without ellipsis', (
    tester,
  ) async {
    const longName = ('Bartholomew', 'Maximilian Fitzgerald-Washington III');
    final longLeague = _leagueWithLongPlayerName(
      league,
      teamIndex: _homeIndex,
      playerIndex: 0,
      firstName: longName.$1,
      lastName: longName.$2,
    );
    final longRequest = GameRequest(
      league: longLeague,
      homeTeamId: longLeague.teams[_homeIndex].id,
      awayTeamId: longLeague.teams[_awayIndex].id,
      seed: baseRequest.seed,
    );
    final playerId = longLeague.teams[_homeIndex].players.first.id.value;
    final expectedName = '${longName.$1} ${longName.$2}';
    final controlled = _ControlledRunner();
    await _pumpGame(tester, longRequest, controlled.run);
    controlled.pending.single.complete(_simulate(longRequest));
    await tester.pump();

    final nameWidget = tester.widget<Text>(
      find.byKey(ValueKey('player-name-$playerId')),
    );
    expect(nameWidget.data, expectedName);
    expect(
      nameWidget.overflow,
      isNull,
      reason: 'a full name must not be clipped with an ellipsis',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mandatory disclosures render; zero-seed note is conditional', (
    tester,
  ) async {
    final controlled = _ControlledRunner();
    await _pumpGame(tester, baseRequest, controlled.run);
    controlled.pending.single.complete(base);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('disclosure-participation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('disclosure-rematch-cycle')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('disclosure-zero-seed')), findsNothing);
    final disclosure = _text(
      tester,
      const ValueKey('disclosure-participation'),
    );
    expect(
      disclosure,
      allOf(
        contains('Minutes are derived from recorded game events'),
        contains('substituted after disqualification'),
        contains('no eligible bench player remains'),
        contains('Technical-foul penalties'),
      ),
    );
    expect(
      disclosure,
      allOf(
        contains('not modelled'),
        contains('never entered'),
        contains('full box model'),
        contains('not a claim of NBA realism'),
      ),
    );

    final zeroRequest = GameRequest(
      league: league,
      homeTeamId: baseRequest.homeTeamId,
      awayTeamId: baseRequest.awayTeamId,
      seed: 0,
    );
    final zeroControlled = _ControlledRunner();
    await _pumpGame(tester, zeroRequest, zeroControlled.run);
    zeroControlled.pending.single.complete(_simulate(zeroRequest));
    await tester.pump();

    expect(find.byKey(const ValueKey('disclosure-zero-seed')), findsOneWidget);
    expect(
      _text(tester, const ValueKey('result-seed')),
      'Seed ${describeGameSeed(0)}',
    );
  });

  testWidgets(
    'rematch preserves lineups and plans and advances only the seed',
    (tester) async {
      final home = league.teams[_homeIndex];
      final away = league.teams[_awayIndex];
      final homeLineup = nonDefaultLineup(home);
      final awayLineup = CourtLineup.defaultFor(away);
      final plan = managedPlan(
        league: league,
        homeIndex: _homeIndex,
        awayIndex: _awayIndex,
        manageHome: true,
        managedLineup: homeLineup,
      );
      final planned = GameRequest(
        league: league,
        homeTeamId: home.id,
        awayTeamId: away.id,
        seed: baseRequest.seed,
        homeLineup: homeLineup,
        awayLineup: awayLineup,
        rotationPlan: plan,
      );
      final controlled = _ControlledRunner();
      await _pumpGame(tester, planned, controlled.run);
      controlled.pending.single.complete(_simulate(planned));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('rematch-game')));
      await tester.pump();

      expect(controlled.requests, hasLength(2));
      final rematch = controlled.requests.last;
      expect(rematch.league, same(league));
      expect(rematch.homeTeamId.value, home.id.value);
      expect(rematch.awayTeamId.value, away.id.value);
      expect(rematch.homeLineup!.playerIds, homeLineup.playerIds);
      expect(rematch.awayLineup!.playerIds, awayLineup.playerIds);
      expect(rematch.rotationPlan!.home.targetSeconds, plan.home.targetSeconds);
      expect(rematch.rotationPlan!.away.targetSeconds, plan.away.targetSeconds);
      expect(rematch.rotationPlan!.home.preset, plan.home.preset);
      expect(
        rematch.seed,
        deriveGameSeed(
          leagueSeed: league.config.seed,
          homeIndex: _homeIndex,
          awayIndex: _awayIndex,
          rematchIndex: 1,
        ),
      );
      expect(rematch.seed, isNot(planned.seed));

      final next = _simulate(rematch);
      expect(next.input.lineupFor(home.id).playerIds, homeLineup.playerIds);
      expect(
        next.input.rotationPlan!.home.targetSeconds,
        plan.home.targetSeconds,
      );
    },
  );

  testWidgets('planned targets render separately from actual minutes', (
    tester,
  ) async {
    final home = league.teams[_homeIndex];
    final away = league.teams[_awayIndex];
    final homeLineup = nonDefaultLineup(home);
    final plan = managedPlan(
      league: league,
      homeIndex: _homeIndex,
      awayIndex: _awayIndex,
      manageHome: true,
      managedLineup: homeLineup,
    );
    final planned = GameRequest(
      league: league,
      homeTeamId: home.id,
      awayTeamId: away.id,
      seed: baseRequest.seed,
      homeLineup: homeLineup,
      awayLineup: CourtLineup.defaultFor(away),
      rotationPlan: plan,
    );
    final result = _simulate(planned);
    final controlled = _ControlledRunner();
    await _pumpGame(tester, planned, controlled.run);
    controlled.pending.single.complete(result);
    await tester.pump();

    final target = plan.home.targetSeconds.entries.first;
    final actual = result.boxScore.players[target.key.value]!.secondsPlayed;
    expect(
      _text(tester, ValueKey('player-stat-${target.key.value}-TGT')),
      formatMinutes(target.value),
    );
    expect(
      _text(tester, ValueKey('player-stat-${target.key.value}-MIN')),
      formatMinutes(actual),
    );
    expect(target.value, isNot(actual));

    final disclosure = _text(
      tester,
      const ValueKey('disclosure-participation'),
    );
    expect(
      disclosure,
      contains(
        'Targets are best-effort. Foul-outs, disqualification rules and the '
        'limited dead-ball windows can change minutes.',
      ),
    );
    expect(
      disclosure,
      isNot(contains('rotations and fatigue are not modelled')),
    );
    expect(disclosure, contains('Fatigue is not modelled'));
  });

  testWidgets('rematch advances the seed and changes the fingerprint', (
    tester,
  ) async {
    final controlled = _ControlledRunner();
    await _pumpGame(tester, baseRequest, controlled.run);
    controlled.pending.single.complete(base);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('rematch-game')));
    await tester.pump();

    expect(controlled.requests, hasLength(2));
    final rematch = controlled.requests.last;
    final expectedSeed = deriveGameSeed(
      leagueSeed: league.config.seed,
      homeIndex: _homeIndex,
      awayIndex: _awayIndex,
      rematchIndex: 1,
    );
    expect(rematch.seed, expectedSeed);
    expect(rematch.seed, isNot(baseRequest.seed));
    expect(rematch.homeTeamId.value, baseRequest.homeTeamId.value);
    expect(rematch.awayTeamId.value, baseRequest.awayTeamId.value);
    expect(find.byKey(const ValueKey('game-loading')), findsOneWidget);

    final next = _simulate(rematch);
    controlled.pending[1].complete(next);
    await tester.pump();

    expect(
      _text(tester, const ValueKey('result-seed')),
      'Seed ${describeGameSeed(expectedSeed)}',
    );
    expect(next.inputFingerprint, isNot(base.inputFingerprint));
  });

  testWidgets('rematch result is reproducible from its seed', (tester) async {
    final controlled = _ControlledRunner();
    await _pumpGame(tester, baseRequest, controlled.run);
    controlled.pending.single.complete(base);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rematch-game')));
    await tester.pump();

    final rematch = controlled.requests.last;
    final first = _simulate(rematch);
    final second = _simulate(rematch);
    expect(second.inputFingerprint, first.inputFingerprint);
    expect(second.homeScore, first.homeScore);
    expect(second.awayScore, first.awayScore);
  });

  testWidgets('wrap-around rematch discloses the repeated cycle', (
    tester,
  ) async {
    final lastRequest = _request(league, 255);
    final firstSeed = _request(league, 0).seed;
    final controlled = _ControlledRunner();
    await _pumpGame(tester, lastRequest, controlled.run);
    controlled.pending.single.complete(_simulate(lastRequest));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('disclosure-cycle-repeated')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('rematch-game')));
    await tester.pump();

    final wrapped = controlled.requests.last;
    expect(wrapped.seed, firstSeed);
    controlled.pending[1].complete(_simulate(wrapped));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('disclosure-cycle-repeated')),
      findsOneWidget,
    );
    expect(
      _text(tester, const ValueKey('result-seed')),
      'Seed ${describeGameSeed(firstSeed)}',
    );
  });

  testWidgets('rematch failure offers retry and retries the new seed', (
    tester,
  ) async {
    final controlled = _ControlledRunner();
    await _pumpGame(tester, baseRequest, controlled.run);
    controlled.pending.single.complete(base);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('rematch-game')));
    await tester.pump();
    expect(find.byKey(const ValueKey('game-loading')), findsOneWidget);

    controlled.pending[1].completeError(StateError('rematch failed'));
    await tester.pump();
    expect(find.byKey(const ValueKey('game-error')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('retry-game')));
    await tester.pump();
    expect(find.byKey(const ValueKey('game-loading')), findsOneWidget);
    expect(controlled.requests, hasLength(3));
    expect(controlled.requests[2].seed, controlled.requests[1].seed);

    final retried = _simulate(controlled.requests[2]);
    controlled.pending[2].complete(retried);
    await tester.pump();

    expect(find.byKey(const ValueKey('game-success')), findsOneWidget);
    expect(
      _text(tester, const ValueKey('result-seed')),
      'Seed ${describeGameSeed(controlled.requests[2].seed)}',
    );
  });

  testWidgets('abandoned rematch cannot overwrite a disposed screen', (
    tester,
  ) async {
    final controlled = _ControlledRunner();
    await _pumpGameOnRoute(tester, baseRequest, controlled.run);
    controlled.pending.single.complete(base);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('rematch-game')));
    await tester.pump();
    expect(find.byKey(const ValueKey('game-loading')), findsOneWidget);

    await _goBack(tester);
    expect(find.byKey(const ValueKey('open-game')), findsOneWidget);

    controlled.pending[1].complete(_simulate(controlled.requests.last));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('rematch fixture identity is recorded', () {
    final rematch = _request(league, 1);
    final rematchResult = _simulate(rematch);
    debugPrint(
      'T024 fixtures: base seed ${baseRequest.seed} '
      'fingerprint ${base.inputFingerprint}; '
      'rematch seed ${rematch.seed} '
      'fingerprint ${rematchResult.inputFingerprint}',
    );
    expect(rematch.seed, isNot(baseRequest.seed));
    expect(rematchResult.inputFingerprint, isNot(base.inputFingerprint));
  });

  testWidgets('Return to League pops back to the root route', (tester) async {
    final controlled = _ControlledRunner();
    await _pumpGameOnRoute(tester, baseRequest, controlled.run);
    controlled.pending.single.complete(base);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('return-to-league')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('open-game')), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

String _minutes(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
