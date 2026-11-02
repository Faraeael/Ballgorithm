import 'package:basketball_manager/app.dart';
import 'package:basketball_manager/features/game/game_runner.dart';
import 'package:basketball_manager/features/game/game_seed.dart';
import 'package:basketball_manager/features/game/game_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _config = GenerationConfig(seed: 20261028);

const _sizes = <String, Size>{
  '360x640 (small phone)': Size(360, 640),
  '393x852 (Pixel-class)': Size(393, 852),
  '430x932 (large phone)': Size(430, 932),
};

Future<void> _pumpSetup(
  WidgetTester tester,
  League league, {
  required ValueChanged<GameRequest> onConfirm,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: GameSetupScreen(league: league, onConfirm: onConfirm),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String role, Team team) async {
  await tester.tap(find.byKey(ValueKey('$role-team-select')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('$role-option-${team.id.value}')).last);
  await tester.pumpAndSettle();
}

String? _seedText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('derived-seed'))).data;

bool _confirmEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('confirm-matchup')))
        .onPressed !=
    null;

void main() {
  late League league;
  late List<GameRequest> confirmed;

  setUpAll(() {
    league = const LeagueGenerator().generate(_config);
  });

  setUp(() => confirmed = <GameRequest>[]);

  testWidgets('league screen exposes Play Game and opens setup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(BasketballManagerApp(league: league));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('play-game')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('play-game')));
    await tester.pumpAndSettle();

    expect(find.text('Game Day Setup'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-team-select')), findsOneWidget);
    expect(find.byKey(const ValueKey('away-team-select')), findsOneWidget);
    expect(_confirmEnabled(tester), isFalse);
  });

  testWidgets('selecting both teams shows matchup and derived seed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pumpSetup(tester, league, onConfirm: confirmed.add);

    final home = league.teams[3];
    final away = league.teams[5];

    await _pick(tester, 'home', home);
    expect(find.byKey(const ValueKey('matchup-summary')), findsNothing);

    await _pick(tester, 'away', away);

    expect(
      find.text('${away.name} at ${home.name}'),
      findsOneWidget,
      reason: 'away at home orientation',
    );

    final seed = deriveGameSeed(
      leagueSeed: league.config.seed,
      homeIndex: 3,
      awayIndex: 5,
      rematchIndex: 0,
    );
    expect(_seedText(tester), 'Game seed: ${describeGameSeed(seed)}');
    expect(_confirmEnabled(tester), isTrue);
  });

  testWidgets('the same team cannot occupy both roles', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pumpSetup(tester, league, onConfirm: confirmed.add);

    final team = league.teams.first;
    await _pick(tester, 'home', team);
    await _pick(tester, 'away', team);

    expect(
      find.byKey(const ValueKey('selection-error')),
      findsOneWidget,
      reason: 'duplicate selection must be rejected with a message',
    );
    expect(_seedText(tester), 'Game seed: not set');
    expect(_confirmEnabled(tester), isFalse);
    expect(confirmed, isEmpty);
  });

  testWidgets('confirm passes the selected TeamIds, indices and seed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pumpSetup(tester, league, onConfirm: confirmed.add);

    final home = league.teams[3];
    final away = league.teams[5];
    await _pick(tester, 'home', home);
    await _pick(tester, 'away', away);

    await tester.tap(find.byKey(const ValueKey('confirm-matchup')));
    await tester.pumpAndSettle();

    expect(confirmed, hasLength(1));
    final request = confirmed.single;
    expect(request.league, same(league));
    expect(request.homeTeamId.value, home.id.value);
    expect(request.awayTeamId.value, away.id.value);
    expect(request.homeTeamId.value, isNot(request.awayTeamId.value));
    expect(
      request.seed,
      deriveGameSeed(
        leagueSeed: league.config.seed,
        homeIndex: league.teams.indexOf(home),
        awayIndex: league.teams.indexOf(away),
        rematchIndex: 0,
      ),
    );
    expect(league.teams[3].id.value, request.homeTeamId.value);
    expect(league.teams[5].id.value, request.awayTeamId.value);
  });

  testWidgets('swapping home and away changes the derived seed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pumpSetup(tester, league, onConfirm: confirmed.add);

    final third = league.teams[3];
    final fifth = league.teams[5];
    final sixth = league.teams[6];

    await _pick(tester, 'home', third);
    await _pick(tester, 'away', fifth);
    final forward = _seedText(tester);

    // Reach the reversed orientation through valid intermediate states.
    await _pick(tester, 'away', sixth);
    await _pick(tester, 'home', fifth);
    await _pick(tester, 'away', third);
    final reversed = _seedText(tester);

    expect(reversed, isNot(forward));
    expect(
      reversed,
      'Game seed: '
      '${describeGameSeed(deriveGameSeed(leagueSeed: league.config.seed, homeIndex: 5, awayIndex: 3, rematchIndex: 0))}',
    );
    expect(find.text('${third.name} at ${fifth.name}'), findsOneWidget);
  });

  testWidgets('confirm stays disabled until both roles are valid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pumpSetup(tester, league, onConfirm: confirmed.add);

    expect(_confirmEnabled(tester), isFalse);
    await _pick(tester, 'home', league.teams[2]);
    expect(_confirmEnabled(tester), isFalse);
    await _pick(tester, 'away', league.teams[4]);
    expect(_confirmEnabled(tester), isTrue);
  });

  testWidgets('back navigation preserves the league and roster flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(BasketballManagerApp(league: league));
    await tester.pumpAndSettle();

    final team = league.teams[2];
    await tester.tap(find.byKey(const ValueKey('play-game')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text(league.name), findsOneWidget);
    expect(find.byKey(ValueKey('team-${team.id.value}')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('team-${team.id.value}')));
    await tester.pumpAndSettle();

    final player = team.players.first;
    expect(find.byKey(ValueKey('player-${player.id.value}')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Basketball Manager'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final entry in _sizes.entries) {
    testWidgets('${entry.key}: setup fits without overflow', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpSetup(tester, league, onConfirm: confirmed.add);
      expect(tester.takeException(), isNull);

      await _pick(tester, 'home', league.teams.first);
      await _pick(tester, 'away', league.teams.last);
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('confirm-matchup')),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(_confirmEnabled(tester), isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
