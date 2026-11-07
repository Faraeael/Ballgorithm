import 'package:basketball_manager/features/game/game_runner.dart';
import 'package:basketball_manager/features/game/game_setup_screen.dart';
import 'package:basketball_manager/features/game/participation_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _config = GenerationConfig(seed: 20261028);
const _homeIndex = 3;
const _awayIndex = 5;

Future<void> _pumpSetup(
  WidgetTester tester,
  League league, {
  required ValueChanged<GameRequest> onConfirm,
  Size size = const Size(430, 932),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: GameSetupScreen(league: league, onConfirm: onConfirm),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pickTeam(WidgetTester tester, String role, Team team) async {
  await tester.tap(find.byKey(ValueKey('$role-team-select')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(ValueKey('$role-option-${team.id.value}')).hitTestable().last,
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollToTop(WidgetTester tester) async {
  final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
  if (state.position.pixels > 0) {
    state.position.jumpTo(0);
    await tester.pumpAndSettle();
  }
}

Future<void> _confirm(WidgetTester tester) async {
  await _scrollTo(tester, find.byKey(const ValueKey('confirm-matchup')));
  await tester.tap(find.byKey(const ValueKey('confirm-matchup')));
  await tester.pumpAndSettle();
}

bool _confirmEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('confirm-matchup')))
        .onPressed !=
    null;

Map<PlayerId, int> _expanded(
  Team team,
  CourtLineup lineup,
  RotationPreset preset,
) => RotationPlan.expandPreset(
  preset: preset,
  team: team,
  lineup: lineup,
  rules: GameRules.standard,
);

Future<String> _targetText(WidgetTester tester, String playerId) async {
  final finder = find.byKey(ValueKey('target-preview-$playerId'));
  await _scrollTo(tester, finder);
  return tester.widget<Text>(finder).data!;
}

Future<void> _openCustomEditor(WidgetTester tester) async {
  await _scrollTo(tester, find.byKey(const ValueKey('preset-custom')));
  await tester.tap(find.byKey(const ValueKey('preset-custom')));
  await tester.pumpAndSettle();
  await _scrollTo(tester, find.byKey(const ValueKey('custom-editor')));
  await tester.tap(find.byKey(const ValueKey('custom-editor')));
  await tester.pumpAndSettle();
}

Future<void> _expectCustomTargets(
  WidgetTester tester,
  Team team,
  Map<PlayerId, int> expected,
) async {
  for (final player in team.players) {
    final finder = find.byKey(ValueKey('target-seconds-${player.id.value}'));
    await _scrollTo(tester, finder);
    expect(
      tester.widget<Text>(finder).data,
      formatMinutes(expected[player.id]!),
      reason: 'custom target for ${player.id.value}',
    );
  }
}

void main() {
  late League league;
  late Team home;
  late Team away;
  late List<GameRequest> confirmed;

  setUpAll(() {
    league = const LeagueGenerator().generate(_config);
    home = league.teams[_homeIndex];
    away = league.teams[_awayIndex];
  });

  setUp(() => confirmed = <GameRequest>[]);

  testWidgets('home management sends both default lineups and plans', (
    tester,
  ) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);
    await _confirm(tester);

    final request = confirmed.single;
    expect(request.homeTeamId.value, home.id.value);
    expect(request.awayTeamId.value, away.id.value);
    expect(
      request.homeLineup!.playerIds,
      CourtLineup.defaultFor(home).playerIds,
    );
    expect(
      request.awayLineup!.playerIds,
      CourtLineup.defaultFor(away).playerIds,
    );
    final plan = request.rotationPlan!;
    expect(plan.home.preset, RotationPreset.balanced);
    expect(plan.away.preset, RotationPreset.balanced);
    expect(
      plan.home.targetSeconds,
      _expanded(home, request.homeLineup!, RotationPreset.balanced),
    );
    expect(
      plan.away.targetSeconds,
      _expanded(away, request.awayLineup!, RotationPreset.balanced),
    );
  });

  testWidgets('away management moves the editable plan to the away side', (
    tester,
  ) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);
    await tester.tap(find.byKey(const ValueKey('managed-team-away')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const ValueKey('preset-starterHeavy')));
    await tester.tap(find.byKey(const ValueKey('preset-starterHeavy')));
    await tester.pumpAndSettle();
    await _confirm(tester);

    final plan = confirmed.single.rotationPlan!;
    expect(plan.away.preset, RotationPreset.starterHeavy);
    expect(plan.home.preset, RotationPreset.balanced);
    expect(
      plan.away.targetSeconds,
      _expanded(
        away,
        CourtLineup.defaultFor(away),
        RotationPreset.starterHeavy,
      ),
    );
    expect(
      plan.home.targetSeconds,
      _expanded(home, CourtLineup.defaultFor(home), RotationPreset.balanced),
    );
    expect(
      confirmed.single.awayLineup!.playerIds,
      CourtLineup.defaultFor(away).playerIds,
    );
  });

  testWidgets('a non-default starter reaches the transported lineup', (
    tester,
  ) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);

    final base = CourtLineup.defaultFor(home);
    final reserve = home.players.firstWhere(
      (player) => !base.containsPlayer(player.id),
    );
    final slotKey = base.slots.first.slot.shortName.toLowerCase();
    await _scrollTo(tester, find.byKey(ValueKey('starter-slot-$slotKey')));
    await tester.tap(find.byKey(ValueKey('starter-slot-$slotKey')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .byKey(ValueKey('starter-option-$slotKey-${reserve.id.value}'))
          .hitTestable()
          .last,
    );
    await tester.pumpAndSettle();
    await _confirm(tester);

    final lineup = confirmed.single.homeLineup!;
    expect(lineup.playerIds, hasLength(5));
    expect(lineup.playerIds.toSet(), hasLength(5));
    expect(lineup.playerIds, contains(reserve.id.value));
    expect(lineup.playerIds, contains(base.slots[1].playerId.value));
    expect(lineup.playerIds, isNot(contains(base.slots.first.playerId.value)));
    final plan = confirmed.single.rotationPlan!;
    expect(
      plan.home.targetSeconds,
      _expanded(home, lineup, RotationPreset.balanced),
    );
  });

  testWidgets('starter slots never offer an already selected player', (
    tester,
  ) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);

    final base = CourtLineup.defaultFor(home);
    final sg = base.slots[1];
    final sgKey = sg.slot.shortName.toLowerCase();
    final pgKey = base.slots.first.slot.shortName.toLowerCase();
    final pgDropdown = tester.widget<DropdownButton<String>>(
      find.byKey(ValueKey('starter-slot-$pgKey')),
    );
    final pgValues = [for (final item in pgDropdown.items!) item.value];
    expect(pgValues, isNot(contains(sg.playerId.value)));
    expect(pgValues, contains(base.slots.first.playerId.value));

    final sgDropdown = tester.widget<DropdownButton<String>>(
      find.byKey(ValueKey('starter-slot-$sgKey')),
    );
    final sgValues = [for (final item in sgDropdown.items!) item.value];
    expect(sgValues, isNot(contains(base.slots.first.playerId.value)));
    expect(sgValues, contains(sg.playerId.value));
  });

  testWidgets('balanced and starter-heavy previews differ per player', (
    tester,
  ) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);

    final starter = CourtLineup.defaultFor(home).slots.first.playerId.value;
    final balanced = await _targetText(tester, starter);

    await _scrollTo(tester, find.byKey(const ValueKey('preset-starterHeavy')));
    await tester.tap(find.byKey(const ValueKey('preset-starterHeavy')));
    await tester.pumpAndSettle();
    final heavy = await _targetText(tester, starter);
    expect(heavy, isNot(balanced));
    expect(
      heavy,
      formatMinutes(
        _expanded(
          home,
          CourtLineup.defaultFor(home),
          RotationPreset.starterHeavy,
        )[PlayerId(starter)]!,
      ),
    );
  });

  testWidgets('starter-heavy targets seed custom editing exactly', (
    tester,
  ) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);

    await _scrollTo(tester, find.byKey(const ValueKey('preset-starterHeavy')));
    await tester.tap(find.byKey(const ValueKey('preset-starterHeavy')));
    await tester.pumpAndSettle();

    final base = CourtLineup.defaultFor(home);
    final starterHeavy = _expanded(home, base, RotationPreset.starterHeavy);
    final balanced = _expanded(home, base, RotationPreset.balanced);
    expect(starterHeavy, isNot(balanced));

    await _openCustomEditor(tester);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('target-total'))).data,
      'Team total: 14400 / 14400 player-seconds',
    );
    await _expectCustomTargets(tester, home, starterHeavy);

    await _confirm(tester);
    final plan = confirmed.single.rotationPlan!;
    expect(plan.home.preset, RotationPreset.custom);
    expect(plan.home.targetSeconds, starterHeavy);
    expect(
      plan.home.targetSeconds.values.fold<int>(0, (sum, value) => sum + value),
      5 * 720 * 4,
    );
  });

  testWidgets('balanced targets seed custom editing exactly', (tester) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);

    final base = CourtLineup.defaultFor(home);
    final balanced = _expanded(home, base, RotationPreset.balanced);

    await _openCustomEditor(tester);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('target-total'))).data,
      'Team total: 14400 / 14400 player-seconds',
    );
    await _expectCustomTargets(tester, home, balanced);

    await _confirm(tester);
    final plan = confirmed.single.rotationPlan!;
    expect(plan.home.preset, RotationPreset.custom);
    expect(plan.home.targetSeconds, balanced);
  });

  testWidgets('custom editing conserves the exact team total', (tester) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);
    await _scrollTo(tester, find.byKey(const ValueKey('preset-custom')));
    await tester.tap(find.byKey(const ValueKey('preset-custom')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('target-total'))).data,
      'Team total: 14400 / 14400 player-seconds',
    );

    final base = CourtLineup.defaultFor(home);
    final donor = base.slots.first.playerId.value;
    final receiver = home.players
        .firstWhere((player) => !base.containsPlayer(player.id))
        .id
        .value;
    await _scrollTo(tester, find.byKey(const ValueKey('custom-editor')));
    await tester.tap(find.byKey(const ValueKey('custom-editor')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(ValueKey('custom-adjust-$donor--60')));
    await tester.tap(find.byKey(ValueKey('custom-adjust-$donor--60')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(ValueKey('custom-adjust-$receiver-60')));
    await tester.tap(find.byKey(ValueKey('custom-adjust-$receiver-60')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('target-total'))).data,
      'Team total: 14400 / 14400 player-seconds',
    );
    await _confirm(tester);
    final plan = confirmed.single.rotationPlan!;
    expect(plan.home.preset, RotationPreset.custom);
    final total = plan.home.targetSeconds.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    expect(total, 5 * 720 * 4);
    final balanced = _expanded(
      home,
      CourtLineup.defaultFor(home),
      RotationPreset.balanced,
    );
    expect(
      plan.home.targetSeconds[PlayerId(donor)],
      balanced[PlayerId(donor)]! - 60,
    );
    expect(
      plan.home.targetSeconds[PlayerId(receiver)],
      balanced[PlayerId(receiver)]! + 60,
    );
  });

  testWidgets('an unbalanced custom total blocks confirmation', (tester) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);
    await _scrollTo(tester, find.byKey(const ValueKey('preset-custom')));
    await tester.tap(find.byKey(const ValueKey('preset-custom')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const ValueKey('custom-editor')));
    await tester.tap(find.byKey(const ValueKey('custom-editor')));
    await tester.pumpAndSettle();

    final starter = CourtLineup.defaultFor(home).slots.first.playerId.value;
    await _scrollTo(tester, find.byKey(ValueKey('custom-adjust-$starter-60')));
    await tester.tap(find.byKey(ValueKey('custom-adjust-$starter-60')));
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.byKey(const ValueKey('confirm-matchup')));
    expect(_confirmEnabled(tester), isFalse);
    expect(find.byKey(const ValueKey('plan-error')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('plan-error'))).data,
      contains('14400'),
    );
  });

  for (final entry in const <String, Size>{
    '360x640': Size(360, 640),
    '393x852': Size(393, 852),
    '430x932': Size(430, 932),
  }.entries) {
    testWidgets('${entry.key}: management controls fit without overflow', (
      tester,
    ) async {
      await _pumpSetup(
        tester,
        league,
        onConfirm: confirmed.add,
        size: entry.value,
      );
      await _pickTeam(tester, 'home', home);
      await _pickTeam(tester, 'away', away);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('managed-team-away')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final base = CourtLineup.defaultFor(away);
      final reserve = away.players.firstWhere(
        (player) => !base.containsPlayer(player.id),
      );
      final slotKey = base.slots.first.slot.shortName.toLowerCase();
      await _scrollTo(tester, find.byKey(ValueKey('starter-slot-$slotKey')));
      await tester.tap(find.byKey(ValueKey('starter-slot-$slotKey')));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byKey(ValueKey('starter-option-$slotKey-${reserve.id.value}'))
            .hitTestable()
            .last,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await _scrollTo(tester, find.byKey(const ValueKey('preset-custom')));
      await tester.tap(find.byKey(const ValueKey('preset-custom')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await _scrollTo(tester, find.byKey(const ValueKey('custom-editor')));
      await tester.tap(find.byKey(const ValueKey('custom-editor')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final adjust = find.byKey(
        ValueKey('custom-adjust-${reserve.id.value}-60'),
      );
      await _scrollTo(tester, adjust);
      await tester.tap(adjust);
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.byKey(const ValueKey('target-total')));
      expect(tester.takeException(), isNull);
      await _scrollTo(tester, find.byKey(const ValueKey('confirm-matchup')));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('changing only the opponent keeps the managed five', (
    tester,
  ) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);

    final base = CourtLineup.defaultFor(home);
    final reserve = home.players.firstWhere(
      (player) => !base.containsPlayer(player.id),
    );
    final slotKey = base.slots.first.slot.shortName.toLowerCase();
    await _scrollTo(tester, find.byKey(ValueKey('starter-slot-$slotKey')));
    await tester.tap(find.byKey(ValueKey('starter-slot-$slotKey')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .byKey(ValueKey('starter-option-$slotKey-${reserve.id.value}'))
          .hitTestable()
          .last,
    );
    await tester.pumpAndSettle();

    await _scrollToTop(tester);
    await _pickTeam(tester, 'away', league.teams[6]);
    await _confirm(tester);

    expect(confirmed.single.homeLineup!.playerIds, contains(reserve.id.value));
    expect(confirmed.single.awayTeamId.value, league.teams[6].id.value);
  });

  testWidgets('switching the managed side rebuilds lineup and targets', (
    tester,
  ) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);
    await tester.tap(find.byKey(const ValueKey('managed-team-away')));
    await tester.pumpAndSettle();
    await _confirm(tester);

    final request = confirmed.single;
    expect(
      request.awayLineup!.playerIds,
      CourtLineup.defaultFor(away).playerIds,
    );
    expect(request.rotationPlan!.away.targetSeconds.keys.toSet(), {
      for (final player in away.players) player.id,
    });
    expect(request.rotationPlan!.home.targetSeconds.keys.toSet(), {
      for (final player in home.players) player.id,
    });
  });
}
