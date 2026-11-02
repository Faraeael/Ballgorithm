import 'dart:async';

import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/game/game_runner.dart';
import 'package:basketball_manager/features/game/game_screen.dart';
import 'package:basketball_manager/features/game/game_seed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _config = GenerationConfig(seed: 20261028);

/// Runner whose completions the test controls; one completer per attempt.
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

/// Builds the same input the worker builds and simulates on this isolate.
/// Used only to obtain a real `GameResult`; no values are synthesised.
GameResult _realResult(GameRequest request) {
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
      homeLineup: CourtLineup.defaultFor(homeTeam),
      awayLineup: CourtLineup.defaultFor(awayTeam),
      seed: request.seed,
      rules: GameRules.standard,
    ),
  );
}

Future<void> _pumpGame(
  WidgetTester tester,
  GameRequest request,
  Future<GameResult> Function(GameRequest) runner,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: GameScreen(request: request, runner: runner),
    ),
  );
  await tester.pump();
}

Future<void> _pumpGameOnRoute(
  WidgetTester tester,
  GameRequest request,
  Future<GameResult> Function(GameRequest) runner,
) async {
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
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-game')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Pops the current route without settling: a visible spinner never settles.
Future<void> _goBack(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void _expectOnlyState(String state) {
  for (final other in ['game-loading', 'game-error', 'game-success']) {
    expect(
      find.byKey(ValueKey(other)),
      other == state ? findsOneWidget : findsNothing,
      reason: 'state $other while $state is expected',
    );
  }
}

void main() {
  late League league;
  late GameRequest request;
  late GameResult real;

  setUpAll(() {
    league = const LeagueGenerator().generate(_config);
    request = GameRequest(
      league: league,
      homeTeamId: league.teams[3].id,
      awayTeamId: league.teams[5].id,
      seed: deriveGameSeed(
        leagueSeed: league.config.seed,
        homeIndex: 3,
        awayIndex: 5,
        rematchIndex: 0,
      ),
    );
    real = _realResult(request);
  });

  testWidgets('confirming a valid matchup opens GameScreen', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(BasketballManagerApp(league: league));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('play-game')));
    await tester.pumpAndSettle();

    final home = league.teams[3];
    final away = league.teams[5];
    for (final entry in {'home': home, 'away': away}.entries) {
      await tester.tap(find.byKey(ValueKey('${entry.key}-team-select')));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byKey(ValueKey('${entry.key}-option-${entry.value.id.value}'))
            .hitTestable()
            .last,
      );
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const ValueKey('confirm-matchup')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('game-loading')), findsOneWidget);

    // Dispose while the worker may still be running; must stay silent.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading renders only the loading state', (tester) async {
    final controlled = _ControlledRunner();
    await _pumpGame(tester, request, controlled.run);

    _expectOnlyState('game-loading');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(controlled.requests, hasLength(1));
    expect(controlled.requests.single.seed, request.seed);
  });

  testWidgets('success replaces loading and shows real values', (tester) async {
    final controlled = _ControlledRunner();
    await _pumpGame(tester, request, controlled.run);

    controlled.pending.single.complete(real);
    await tester.pump();

    _expectOnlyState('game-success');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('result-score-away'))).data,
      '${real.awayScore}',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('result-score-home'))).data,
      '${real.homeScore}',
    );
    expect(
      find.textContaining('${real.periodsPlayed} periods'),
      findsOneWidget,
    );
  });

  testWidgets('validation failure replaces loading and offers Retry', (
    tester,
  ) async {
    final controlled = _ControlledRunner();
    await _pumpGame(tester, request, controlled.run);

    controlled.pending.single.completeError(
      GameValidationException(const [
        GameValidationIssue(
          code: GameValidationCode.teamsNotDistinct,
          path: 'teams',
          message: 'home and away teams must differ',
        ),
      ]),
    );
    await tester.pump();

    _expectOnlyState('game-error');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.textContaining(GameValidationCode.teamsNotDistinct.name),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('retry-game')), findsOneWidget);
  });

  testWidgets('unexpected failure is readable and exposes no stack trace', (
    tester,
  ) async {
    final controlled = _ControlledRunner();
    await _pumpGame(tester, request, controlled.run);

    controlled.pending.single.completeError(StateError('boom'));
    await tester.pump();

    _expectOnlyState('game-error');
    final message = tester
        .widget<Text>(find.byKey(const ValueKey('game-error-message')))
        .data!;
    expect(message, contains('Unexpected error'));
    expect(message, isNot(contains('package:')));
    expect(message, isNot(contains('#0')));
  });

  testWidgets('retry re-enters loading and can succeed', (tester) async {
    final controlled = _ControlledRunner();
    await _pumpGame(tester, request, controlled.run);

    controlled.pending.single.completeError(StateError('first attempt'));
    await tester.pump();
    _expectOnlyState('game-error');

    await tester.tap(find.byKey(const ValueKey('retry-game')));
    await tester.pump();
    _expectOnlyState('game-loading');
    expect(controlled.requests, hasLength(2));

    controlled.pending[1].complete(real);
    await tester.pump();
    _expectOnlyState('game-success');
  });

  testWidgets('rapid retry taps do not launch duplicate simulations', (
    tester,
  ) async {
    final controlled = _ControlledRunner();
    await _pumpGame(tester, request, controlled.run);

    controlled.pending.single.completeError(StateError('boom'));
    await tester.pump();

    // Two taps before any frame: the second must be ignored.
    await tester.tap(find.byKey(const ValueKey('retry-game')));
    await tester.tap(
      find.byKey(const ValueKey('retry-game')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(controlled.requests, hasLength(2));
    expect(controlled.pending, hasLength(2));
  });

  testWidgets('back navigation works during loading and after an error', (
    tester,
  ) async {
    final loading = _ControlledRunner();
    await _pumpGameOnRoute(tester, request, loading.run);
    _expectOnlyState('game-loading');
    await _goBack(tester);
    expect(find.byKey(const ValueKey('open-game')), findsOneWidget);

    final failing = _ControlledRunner();
    await _pumpGameOnRoute(tester, request, failing.run);
    failing.pending.single.completeError(StateError('boom'));
    await tester.pump();
    _expectOnlyState('game-error');
    await _goBack(tester);
    expect(find.byKey(const ValueKey('open-game')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late completion after disposal raises nothing', (tester) async {
    final controlled = _ControlledRunner();
    await _pumpGameOnRoute(tester, request, controlled.run);

    await _goBack(tester);
    expect(find.byKey(const ValueKey('open-game')), findsOneWidget);

    controlled.pending.single.complete(real);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a later failure after disposal raises nothing', (tester) async {
    final controlled = _ControlledRunner();
    await _pumpGameOnRoute(tester, request, controlled.run);

    await _goBack(tester);

    controlled.pending.single.completeError(StateError('late'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  test(
    'real worker runner completes a game with the generated league',
    () async {
      final result = await runGame(request);

      expect(result.inputFingerprint, hasLength(64));
      expect(result.ledger.events, isNotEmpty);
      expect(result.periodsPlayed, greaterThanOrEqualTo(4));
      expect(result.homeScore + result.awayScore, greaterThan(0));
      expect(result.homeTeamId.value, request.homeTeamId.value);
      expect(result.awayTeamId.value, request.awayTeamId.value);
      expect(result.boxScore.players, hasLength(10));
    },
  );
}
