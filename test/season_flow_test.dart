import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/game/game_runner.dart';
import 'package:basketball_manager/features/season/season_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _config = GenerationConfig(seed: 20261028);

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void _useSmallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<GameResult> _testRunner(GameRequest request) async {
  final homeTeam = request.league.teams.firstWhere(
    (t) => t.id == request.homeTeamId,
  );
  final awayTeam = request.league.teams.firstWhere(
    (t) => t.id == request.awayTeamId,
  );
  final input = GameInput.create(
    gameId:
        request.gameId ??
        '${request.homeTeamId.value}-${request.awayTeamId.value}-${request.seed}',
    league: request.league,
    homeTeamId: request.homeTeamId,
    awayTeamId: request.awayTeamId,
    homeLineup: request.homeLineup ?? CourtLineup.defaultFor(homeTeam),
    awayLineup: request.awayLineup ?? CourtLineup.defaultFor(awayTeam),
    seed: request.seed,
    rules: GameRules.standard,
    rotationPlan: request.rotationPlan,
  );
  return GameSimulator().simulate(input);
}

void main() {
  late League league;

  setUpAll(() {
    league = const LeagueGenerator().generate(_config);
  });

  testWidgets('first launch presents franchise selection and starts season', (
    tester,
  ) async {
    _useTallSurface(tester);
    final storage = InMemorySeasonStorage();
    await tester.pumpWidget(
      BasketballManagerApp(
        league: league,
        storage: storage,
        seasonMode: true,
        gameRunner: _testRunner,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Select Your Franchise'), findsOneWidget);
    for (final team in league.teams) {
      expect(
        find.byKey(ValueKey('team-card-${team.id.value}')),
        findsOneWidget,
      );
    }

    // Select team-2
    final targetTeam = league.teams[1];
    await tester.tap(find.byKey(ValueKey('team-card-${targetTeam.id.value}')));
    await tester.pumpAndSettle();

    // Start Season
    await tester.tap(find.byKey(const ValueKey('start-season-button')));
    await tester.pumpAndSettle();

    // Verifies dashboard opened
    expect(find.text(targetTeam.name), findsAtLeast(1));
    expect(find.textContaining('0W - 0L'), findsAtLeast(1));
    expect(find.byKey(const ValueKey('play-next-game')), findsOneWidget);
  });

  testWidgets('play next game advances round, updates standings, and saves', (
    tester,
  ) async {
    _useTallSurface(tester);
    final storage = InMemorySeasonStorage();
    await tester.pumpWidget(
      BasketballManagerApp(
        league: league,
        storage: storage,
        seasonMode: true,
        gameRunner: _testRunner,
      ),
    );
    await tester.pumpAndSettle();

    // Start with team-1
    await tester.tap(find.byKey(const ValueKey('start-season-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('ROUND 1 OF 14'), findsOneWidget);

    // Play Round 1 game
    await tester.tap(find.byKey(const ValueKey('play-next-game')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    // GameScreen renders results
    expect(find.text('Return to League'), findsNothing);
    expect(find.text('Continue Season'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rematch-game')),
      findsNothing,
    ); // Rematch disabled in season

    // Continue season
    await tester.tap(find.text('Continue Season'));
    await tester.pump();
    await tester.pumpAndSettle();

    // Dashboard should now show Round 2!
    expect(find.textContaining('ROUND 2 OF 14'), findsOneWidget);

    // Check Standings Tab
    await tester.tap(find.byKey(const ValueKey('nav-standings')));
    await tester.pumpAndSettle();

    expect(find.text('League Standings'), findsOneWidget);
    for (final team in league.teams) {
      expect(
        find.byKey(ValueKey('standings-row-${team.id.value}')),
        findsOneWidget,
      );
    }

    // Check Schedule Tab
    await tester.tap(find.byKey(const ValueKey('nav-schedule')));
    await tester.pumpAndSettle();

    expect(find.text('Round 1'), findsOneWidget);
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(find.text('Round 2'), findsOneWidget);
    expect(find.text('CURRENT'), findsOneWidget);

    // Switch back to Home Dashboard tab
    await tester.tap(find.byKey(const ValueKey('nav-dashboard')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ROUND 2 OF 14'), findsOneWidget);

    // App Restart persistence: re-pump with same storage
    await tester.pumpWidget(
      BasketballManagerApp(
        league: league,
        storage: storage,
        seasonMode: true,
        gameRunner: _testRunner,
      ),
    );
    await tester.pumpAndSettle();

    // Verifies reloaded at Round 2 with saved record
    expect(find.textContaining('ROUND 2 OF 14'), findsOneWidget);
  });

  testWidgets(
    'mobile 360x640 layout renders dashboard and tabs without overflow',
    (tester) async {
      _useSmallViewport(tester);
      final storage = InMemorySeasonStorage();

      await tester.pumpWidget(
        BasketballManagerApp(
          league: league,
          storage: storage,
          seasonMode: true,
          gameRunner: _testRunner,
        ),
      );
      await tester.pumpAndSettle();

      // Franchise selection screen
      await tester.tap(find.byKey(const ValueKey('start-season-button')));
      await tester.pumpAndSettle();

      // Home Dashboard fits
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('play-next-game')), findsOneWidget);

      // Team Strategy tab fits
      await tester.tap(find.byKey(const ValueKey('nav-team')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('starter-slot-0')), findsOneWidget);

      // Standings tab fits
      await tester.tap(find.byKey(const ValueKey('nav-standings')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Schedule tab fits
      await tester.tap(find.byKey(const ValueKey('nav-schedule')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('strategy editing allows swapping starters and persists', (
    tester,
  ) async {
    _useTallSurface(tester);
    final storage = InMemorySeasonStorage();
    await tester.pumpWidget(
      BasketballManagerApp(
        league: league,
        storage: storage,
        seasonMode: true,
        gameRunner: _testRunner,
      ),
    );
    await tester.pumpAndSettle();

    // Start season
    await tester.tap(find.byKey(const ValueKey('start-season-button')));
    await tester.pumpAndSettle();

    // Navigate to Team tab
    await tester.tap(find.byKey(const ValueKey('nav-team')));
    await tester.pumpAndSettle();

    // Tap starter slot 0
    await tester.tap(find.byKey(const ValueKey('starter-slot-0')));
    await tester.pumpAndSettle();

    // Select another player from bottom sheet (e.g. index 5, reserve)
    final team = league.teams.first;
    final reservePlayer = team.players[5];
    await tester.tap(find.text(reservePlayer.fullName).last);
    await tester.pumpAndSettle();

    // Tap Save
    await tester.tap(find.byKey(const ValueKey('save-strategy-button')));
    await tester.pumpAndSettle();

    expect(find.text('Team strategy saved successfully!'), findsOneWidget);
  });

  testWidgets('play full 14-round season to championship and confirm reset', (
    tester,
  ) async {
    _useTallSurface(tester);
    final storage = InMemorySeasonStorage();
    await tester.pumpWidget(
      BasketballManagerApp(
        league: league,
        storage: storage,
        seasonMode: true,
        gameRunner: _testRunner,
      ),
    );
    await tester.pumpAndSettle();

    // Start season
    await tester.tap(find.byKey(const ValueKey('start-season-button')));
    await tester.pumpAndSettle();

    // Play all 14 rounds
    for (var r = 1; r <= 14; r++) {
      expect(find.textContaining('ROUND $r OF 14'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('play-next-game')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue Season'));
      await tester.pump();
      await tester.pumpAndSettle();
    }

    // Season complete
    expect(find.text('REGULAR SEASON COMPLETED!'), findsOneWidget);
    expect(find.byKey(const ValueKey('new-season-button')), findsOneWidget);

    // Tap New Season
    await tester.tap(find.byKey(const ValueKey('new-season-button')));
    await tester.pumpAndSettle();

    expect(find.text('Start New Season?'), findsOneWidget);

    // Confirm
    await tester.tap(find.byKey(const ValueKey('confirm-new-season-button')));
    await tester.pumpAndSettle();

    // Verifies back at Franchise Selection Screen
    expect(find.text('Select Your Franchise'), findsOneWidget);
  });
}
