import 'dart:async';

import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/game/game_runner.dart';
import 'package:basketball_manager/features/game/game_screen.dart';
import 'package:basketball_manager/features/game/game_seed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

import 'game_fixtures.dart';

const _sizes = <String, Size>{
  '360x640': Size(360, 640),
  '393x852': Size(393, 852),
  '430x932': Size(430, 932),
};

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

void _useViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Finder _verticalScrollable() => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);

Finder _horizontalScrollable() => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable &&
      (widget.axisDirection == AxisDirection.right ||
          widget.axisDirection == AxisDirection.left),
);

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    180,
    scrollable: _verticalScrollable().first,
  );
  await tester.pumpAndSettle();
}

void _expectNoOverflow(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

Future<_ControlledRunner> _pumpResult(
  WidgetTester tester,
  GameRequest request,
  GameResult result,
) async {
  final controlled = _ControlledRunner();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey('open-game'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) =>
                    GameScreen(request: request, runner: controlled.run),
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
  controlled.pending.single.complete(result);
  await tester.pump();
  return controlled;
}

/// Walks the whole results page, asserting each section builds without
/// overflow, and that only the player tables scroll horizontally.
Future<void> _walkResults(
  WidgetTester tester,
  GameRequest request,
  GameResult result, {
  required bool expectOvertime,
}) async {
  _expectNoOverflow(tester);

  expect(
    tester.widget<Text>(find.byKey(const ValueKey('result-score-away'))).data,
    '${result.awayScore}',
  );
  expect(
    tester.widget<Text>(find.byKey(const ValueKey('result-score-home'))).data,
    '${result.homeScore}',
  );
  expect(find.byKey(const ValueKey('result-seed')), findsOneWidget);
  if (expectOvertime) {
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('result-overtime'))).data,
      '${result.overtimes} OT',
    );
  } else {
    expect(find.byKey(const ValueKey('result-overtime')), findsNothing);
  }

  await _scrollTo(tester, find.byKey(const ValueKey('period-table')));
  _expectNoOverflow(tester);
  expect(find.text('Q1'), findsOneWidget);
  if (expectOvertime) {
    expect(find.text('OT1'), findsOneWidget);
  } else {
    expect(find.text('OT1'), findsNothing);
  }

  await _scrollTo(tester, find.byKey(const ValueKey('team-stats-table')));
  _expectNoOverflow(tester);
  expect(
    find.text('PTS', skipOffstage: false),
    findsWidgets,
    reason: 'team statistics readable without horizontal scrolling',
  );

  final homeTable = ValueKey('player-table-${request.homeTeamId.value}');
  final awayTable = ValueKey('player-table-${request.awayTeamId.value}');

  // Scrolling is permitted inside the player tables only.
  expect(
    tester
        .widget<ListView>(find.byKey(const ValueKey('game-success')))
        .scrollDirection,
    Axis.vertical,
    reason: 'the results page scrolls vertically only',
  );
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is ListView && widget.scrollDirection == Axis.horizontal,
    ),
    findsNothing,
  );
  for (final key in [awayTable, homeTable]) {
    await _scrollTo(tester, find.byKey(key));
    _expectNoOverflow(tester);
    expect(
      find.descendant(of: find.byKey(key), matching: _horizontalScrollable()),
      findsOneWidget,
      reason: 'only the statistics pane scrolls horizontally',
    );
  }

  await _scrollTo(tester, find.byKey(const ValueKey('disclosure-lineup')));
  _expectNoOverflow(tester);
  expect(
    tester.widget<Text>(find.byKey(const ValueKey('disclosure-lineup'))).data,
    allOf(
      contains('fixed five-player lineup'),
      contains('not a realism claim'),
    ),
  );
  expect(
    find.byKey(const ValueKey('disclosure-rematch-cycle')),
    findsOneWidget,
  );

  await _scrollTo(tester, find.byKey(const ValueKey('rematch-game')));
  _expectNoOverflow(tester);
  await _scrollTo(tester, find.byKey(const ValueKey('return-to-league')));
  _expectNoOverflow(tester);
}

/// Taps Rematch (starting a real attempt) and then Return to League.
Future<void> _exerciseActions(
  WidgetTester tester,
  _ControlledRunner controlled,
) async {
  final before = controlled.requests.length;
  final previousSeed = controlled.requests.last.seed;

  await tester.tap(find.byKey(const ValueKey('rematch-game')));
  await tester.pump();

  expect(controlled.requests, hasLength(before + 1));
  expect(controlled.requests.last.seed, isNot(previousSeed));
  expect(find.byKey(const ValueKey('game-loading')), findsOneWidget);
  expect(find.byKey(const ValueKey('game-success')), findsNothing);
  _expectNoOverflow(tester);

  controlled.pending.last.complete(simulateRequest(controlled.requests.last));
  await tester.pump();
  expect(find.byKey(const ValueKey('game-success')), findsOneWidget);
  _expectNoOverflow(tester);

  await _scrollTo(tester, find.byKey(const ValueKey('return-to-league')));
  await tester.tap(find.byKey(const ValueKey('return-to-league')));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('open-game')), findsOneWidget);
  expect(find.byType(GameScreen), findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  late League league;
  late GameRequest baseRequest;
  late GameResult base;
  late GameRequest overtimeRequest;
  late GameResult overtime;

  setUpAll(() {
    league = generateTestLeague();
    baseRequest = testRequest(league);
    base = simulateRequest(baseRequest);
    (overtimeRequest, overtime) = findOvertimeFixture(league);
  });

  for (final entry in _sizes.entries) {
    final size = entry.value;
    final label = entry.key;

    testWidgets('$label: league, setup and loading fit the viewport', (
      tester,
    ) async {
      _useViewport(tester, size);
      await tester.pumpWidget(BasketballManagerApp(league: league));
      await tester.pumpAndSettle();
      _expectNoOverflow(tester);

      await tester.tap(find.byKey(const ValueKey('play-game')));
      await tester.pumpAndSettle();
      _expectNoOverflow(tester);

      for (final pair in [
        ('home', league.teams[testHomeIndex]),
        ('away', league.teams[testAwayIndex]),
      ]) {
        await tester.tap(find.byKey(ValueKey('${pair.$1}-team-select')));
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .byKey(ValueKey('${pair.$1}-option-${pair.$2.id.value}'))
              .hitTestable()
              .last,
        );
        await tester.pumpAndSettle();
        _expectNoOverflow(tester);
      }

      await _scrollTo(tester, find.byKey(const ValueKey('matchup-summary')));
      _expectNoOverflow(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('derived-seed'))).data,
        'Game seed: ${describeGameSeed(baseRequest.seed)}',
      );

      await _scrollTo(tester, find.byKey(const ValueKey('confirm-matchup')));
      await tester.tap(find.byKey(const ValueKey('confirm-matchup')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(GameScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('game-loading')), findsOneWidget);
      _expectNoOverflow(tester);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('$label: validation error and retry fit the viewport', (
      tester,
    ) async {
      _useViewport(tester, size);
      final controlled = _ControlledRunner();
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(request: baseRequest, runner: controlled.run),
        ),
      );
      await tester.pump();

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
      _expectNoOverflow(tester);

      await _scrollTo(tester, find.byKey(const ValueKey('retry-game')));
      _expectNoOverflow(tester);

      await tester.tap(find.byKey(const ValueKey('retry-game')));
      await tester.pump();
      expect(find.byKey(const ValueKey('game-loading')), findsOneWidget);
      _expectNoOverflow(tester);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('$label: regulation result is fully reachable and readable', (
      tester,
    ) async {
      _useViewport(tester, size);
      final controlled = await _pumpResult(tester, baseRequest, base);
      await _walkResults(tester, baseRequest, base, expectOvertime: false);
      await _exerciseActions(tester, controlled);
    });

    testWidgets('$label: overtime result is fully reachable and readable', (
      tester,
    ) async {
      _useViewport(tester, size);
      final controlled = await _pumpResult(tester, overtimeRequest, overtime);
      await _walkResults(
        tester,
        overtimeRequest,
        overtime,
        expectOvertime: true,
      );
      await _exerciseActions(tester, controlled);
    });
  }

  testWidgets('360x640: long names stay complete and scroll inside the table', (
    tester,
  ) async {
    final size = _sizes['360x640']!;
    _useViewport(tester, size);
    final longLeague = leagueWithLongPlayerName(
      league,
      teamIndex: testHomeIndex,
      playerIndex: 0,
      firstName: 'Bartholomew',
      lastName: 'Maximilian Fitzgerald-Washington III',
    );
    final longRequest = GameRequest(
      league: longLeague,
      homeTeamId: longLeague.teams[testHomeIndex].id,
      awayTeamId: longLeague.teams[testAwayIndex].id,
      seed: baseRequest.seed,
    );
    final longResult = simulateRequest(longRequest);
    await _pumpResult(tester, longRequest, longResult);
    _expectNoOverflow(tester);

    final lineupIds = longResult.input
        .lineupFor(longRequest.homeTeamId)
        .playerIds;
    final playerId = longLeague.teams[testHomeIndex].players.first.id.value;
    expect(
      lineupIds,
      contains(playerId),
      reason: 'the renamed player must be on the active lineup',
    );
    final tableKey = ValueKey('player-table-${longRequest.homeTeamId.value}');

    await _scrollTo(tester, find.byKey(tableKey));
    _expectNoOverflow(tester);

    final name = tester.widget<Text>(
      find.byKey(ValueKey('player-name-$playerId')),
    );
    expect(name.data, 'Bartholomew Maximilian Fitzgerald-Washington III');
    expect(name.overflow, isNull, reason: 'no forced ellipsis');

    final tableScrollable = find.descendant(
      of: find.byKey(tableKey),
      matching: _horizontalScrollable(),
    );
    final tableState = tester.state<ScrollableState>(tableScrollable.first);
    expect(
      tableState.position.maxScrollExtent,
      greaterThan(0),
      reason: 'the wide table must be horizontally scrollable',
    );

    await tester.ensureVisible(find.byKey(ValueKey('player-name-$playerId')));
    await tester.pumpAndSettle();

    final pageState = tester.state<ScrollableState>(
      _verticalScrollable().first,
    );
    final pageOffset = pageState.position.pixels;

    final pfCell = find.byKey(ValueKey('player-stat-$playerId-PF'));
    final beforeOffset = tableState.position.pixels;
    final nameBefore = tester.getTopLeft(
      find.byKey(ValueKey('player-name-$playerId')),
    );
    expect(
      tester.getRect(pfCell).left,
      greaterThanOrEqualTo(size.width),
      reason: 'PF is beyond the right edge before scrolling',
    );

    // Start the drag inside the visible part of the name cell; the full text
    // is wider than the viewport, so its centre is not hittable.
    // Drag inside the statistics pane; the identity pane must not move.
    final dragStart =
        tester.getTopLeft(find.byKey(ValueKey('player-stat-$playerId-PTS'))) +
        const Offset(8, 12);
    for (
      var attempt = 0;
      attempt < 5 && tester.getRect(pfCell).left >= size.width;
      attempt++
    ) {
      await tester.dragFrom(dragStart, const Offset(-600, 0));
      await tester.pumpAndSettle();
    }

    expect(
      tableState.position.pixels,
      greaterThan(beforeOffset),
      reason: 'the table moved horizontally',
    );
    expect(
      tester.getRect(pfCell).left,
      lessThan(size.width),
      reason: 'PF became reachable after scrolling',
    );
    expect(
      tester.getTopLeft(find.byKey(ValueKey('player-name-$playerId'))),
      nameBefore,
      reason: 'the identity pane did not move while statistics scrolled',
    );

    expect(
      pageState.position.pixels,
      pageOffset,
      reason: 'table scrolling must not move the page',
    );
    expect(
      tester.widget<Text>(find.byKey(ValueKey('player-name-$playerId'))).data,
      'Bartholomew Maximilian Fitzgerald-Washington III',
    );
    _expectNoOverflow(tester);

    // All five rows remain configured in canonical order, and every player
    // name is still rendered.
    final ordered = [...lineupIds]
      ..sort(
        (a, b) => tester
            .getTopLeft(find.byKey(ValueKey('player-row-$a')))
            .dy
            .compareTo(
              tester.getTopLeft(find.byKey(ValueKey('player-row-$b'))).dy,
            ),
      );
    expect(ordered, lineupIds);
    for (final id in lineupIds) {
      expect(find.byKey(ValueKey('player-name-$id')), findsOneWidget);
    }
  });
}
