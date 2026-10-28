import 'package:basketball_manager/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _config = GenerationConfig(seed: 20261028);

/// Tall surface so every roster row is built without scrolling.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  late League league;

  setUpAll(() {
    league = const LeagueGenerator().generate(_config);
  });

  testWidgets('league screen lists every generated team', (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(BasketballManagerApp(league: league));

    expect(find.text('Basketball Manager'), findsOneWidget);
    expect(find.text(league.name), findsOneWidget);
    for (final team in league.teams) {
      expect(
        find.byKey(ValueKey('team-${team.id.value}')),
        findsOneWidget,
        reason: team.name,
      );
    }
  });

  testWidgets('navigates league -> roster -> player profile and back', (
    tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(BasketballManagerApp(league: league));

    final team = league.teams.first;
    final player = team.players.first;

    await tester.tap(find.byKey(ValueKey('team-${team.id.value}')));
    await tester.pumpAndSettle();

    expect(find.text(team.name), findsOneWidget);
    expect(find.text(player.fullName), findsOneWidget);
    for (final rosterPlayer in team.players) {
      expect(
        find.byKey(ValueKey('player-${rosterPlayer.id.value}')),
        findsOneWidget,
        reason: rosterPlayer.fullName,
      );
    }

    await tester.tap(find.byKey(ValueKey('player-${player.id.value}')));
    await tester.pumpAndSettle();

    expect(find.text(player.fullName), findsOneWidget);
    expect(find.text(team.name), findsOneWidget);
    for (final attribute in PlayerAttributes.attributeNames) {
      expect(
        find.byKey(ValueKey('attribute-$attribute')),
        findsOneWidget,
        reason: attribute,
      );
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('attribute-threePoint')),
        matching: find.text('${player.attributes.threePoint}'),
      ),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(team.name), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Basketball Manager'), findsOneWidget);
  });

  testWidgets('other teams lead to their own rostered players', (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(BasketballManagerApp(league: league));

    final team = league.teams[5];
    final player = team.players.first;

    await tester.tap(find.byKey(ValueKey('team-${team.id.value}')));
    await tester.pumpAndSettle();

    expect(find.text(team.name), findsOneWidget);
    expect(find.text(player.fullName), findsOneWidget);
    expect(
      find.byKey(
        ValueKey('player-${league.teams.first.players.first.id.value}'),
      ),
      findsNothing,
    );
  });
}
