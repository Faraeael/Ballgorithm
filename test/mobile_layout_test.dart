import 'package:basketball_manager/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _config = GenerationConfig(seed: 20261028);

/// Portrait logical sizes of common Android phones.
const _sizes = <String, Size>{
  '360x640 (small phone)': Size(360, 640),
  '393x852 (Pixel-class)': Size(393, 852),
  '430x932 (large phone)': Size(430, 932),
};

void _usePortraitViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Finder _scrollable() => find.byType(Scrollable).first;

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 160, scrollable: _scrollable());
  await tester.pumpAndSettle();
}

Future<void> _verifyProfile(
  WidgetTester tester,
  Team team,
  Player player,
) async {
  await tester.tap(find.byKey(ValueKey('player-${player.id.value}')));
  await tester.pumpAndSettle();

  expect(
    find.text(player.fullName),
    findsOneWidget,
    reason: '${team.name}: profile title for ${player.fullName}',
  );
  expect(
    find.text(team.name),
    findsOneWidget,
    reason: '${team.name}: profile header',
  );
  expect(
    find.byKey(const ValueKey('attribute-insideScoring')),
    findsOneWidget,
    reason: '${team.name}: ${player.fullName}',
  );

  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('attribute-basketballIQ')),
    300,
    scrollable: _scrollable(),
  );
  await tester.pumpAndSettle();
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('attribute-basketballIQ')),
      matching: find.text('${player.attributes.basketballIQ}'),
    ),
    findsOneWidget,
    reason: '${team.name}: ${player.fullName}',
  );
  expect(tester.takeException(), isNull);

  await tester.pageBack();
  await tester.pumpAndSettle();
  expect(find.text(team.name), findsOneWidget);
}

void main() {
  late League league;

  setUpAll(() {
    league = const LeagueGenerator().generate(_config);
  });

  for (final entry in _sizes.entries) {
    testWidgets('${entry.key}: league, roster and profile fit and scroll', (
      tester,
    ) async {
      _usePortraitViewport(tester, entry.value);
      await tester.pumpWidget(BasketballManagerApp(league: league));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final firstTeam = league.teams.first;
      final lastTeam = league.teams.last;

      expect(find.text('Basketball Manager'), findsOneWidget);
      expect(
        find.byKey(ValueKey('team-${firstTeam.id.value}')),
        findsOneWidget,
      );

      // Every team must be reachable by scrolling at this width.
      await _scrollTo(
        tester,
        find.byKey(ValueKey('team-${lastTeam.id.value}')),
      );
      expect(tester.takeException(), isNull);

      // Touch navigation into the last team's roster.
      await tester.tap(find.byKey(ValueKey('team-${lastTeam.id.value}')));
      await tester.pumpAndSettle();
      expect(find.text(lastTeam.name), findsOneWidget);
      expect(tester.takeException(), isNull);

      final lastPlayer = lastTeam.players.last;
      await _scrollTo(
        tester,
        find.byKey(ValueKey('player-${lastPlayer.id.value}')),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(ValueKey('player-${lastPlayer.id.value}')));
      await tester.pumpAndSettle();
      expect(find.text(lastPlayer.fullName), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Profile scrolls to the final attribute without overflow.
      await _scrollTo(
        tester,
        find.byKey(const ValueKey('attribute-basketballIQ')),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('attribute-basketballIQ')),
          matching: find.text('${lastPlayer.attributes.basketballIQ}'),
        ),
        findsOneWidget,
      );

      // Back to the roster, then back to the league list.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(lastTeam.name), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Basketball Manager'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('all 8 teams are reachable at 360 logical px', (tester) async {
    _usePortraitViewport(tester, _sizes.values.first);
    await tester.pumpWidget(BasketballManagerApp(league: league));
    await tester.pumpAndSettle();

    for (final team in league.teams) {
      await _scrollTo(tester, find.byKey(ValueKey('team-${team.id.value}')));
      expect(
        find.byKey(ValueKey('team-${team.id.value}')),
        findsOneWidget,
        reason: team.name,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('every roster and player profile opens at 360x640', (
    tester,
  ) async {
    _usePortraitViewport(tester, _sizes.values.first);
    await tester.pumpWidget(BasketballManagerApp(league: league));
    await tester.pumpAndSettle();

    for (final team in league.teams) {
      await _scrollTo(tester, find.byKey(ValueKey('team-${team.id.value}')));
      await tester.tap(find.byKey(ValueKey('team-${team.id.value}')));
      await tester.pumpAndSettle();

      expect(find.text(team.name), findsOneWidget, reason: team.name);
      for (final player in team.players) {
        await _scrollTo(
          tester,
          find.byKey(ValueKey('player-${player.id.value}')),
        );
        expect(
          find.byKey(ValueKey('player-${player.id.value}')),
          findsOneWidget,
          reason: '${team.name}: ${player.fullName}',
        );
        await _verifyProfile(tester, team, player);
      }
      expect(tester.takeException(), isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });
}
