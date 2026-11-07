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

Future<String> _budgetText(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await _scrollToTop(tester);
  await _scrollTo(tester, finder);
  return tester.widget<Text>(finder).data!;
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
      await _budgetText(tester, 'budget-allocated'),
      'Allocated: 240:00 / 240:00',
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
      await _budgetText(tester, 'budget-allocated'),
      'Allocated: 240:00 / 240:00',
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
      await _budgetText(tester, 'budget-allocated'),
      'Allocated: 240:00 / 240:00',
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
    await _scrollTo(tester, find.byKey(ValueKey('fine-minus-$donor')));
    await tester.tap(find.byKey(ValueKey('fine-minus-$donor')));
    await tester.pumpAndSettle();
    expect(await _budgetText(tester, 'budget-available'), 'Available: 00:10');
    await _scrollTo(tester, find.byKey(ValueKey('fine-plus-$receiver')));
    await tester.tap(find.byKey(ValueKey('fine-plus-$receiver')));
    await tester.pumpAndSettle();

    expect(
      await _budgetText(tester, 'budget-allocated'),
      'Allocated: 240:00 / 240:00',
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
      balanced[PlayerId(donor)]! - 10,
    );
    expect(
      plan.home.targetSeconds[PlayerId(receiver)],
      balanced[PlayerId(receiver)]! + 10,
    );
  });

  testWidgets('an unallocated budget blocks confirmation', (tester) async {
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
    await _scrollTo(tester, find.byKey(ValueKey('fine-minus-$starter')));
    await tester.tap(find.byKey(ValueKey('fine-minus-$starter')));
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.byKey(const ValueKey('confirm-matchup')));
    expect(_confirmEnabled(tester), isFalse);
    expect(find.byKey(const ValueKey('plan-error')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('plan-error'))).data,
      contains('still available'),
    );
    expect(await _budgetText(tester, 'budget-available'), 'Available: 00:10');
  });

  testWidgets('a single slider drag frees several minutes', (tester) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);
    await _openCustomEditor(tester);

    final donor = CourtLineup.defaultFor(home).slots.first.playerId.value;
    final sliderFinder = find.byKey(ValueKey('target-slider-$donor'));
    await _scrollTo(tester, sliderFinder);
    final before = tester.widget<Slider>(sliderFinder).value;

    await tester.drag(sliderFinder, const Offset(-90, 0));
    await tester.pumpAndSettle();

    final after = tester.widget<Slider>(sliderFinder).value;
    expect(after, lessThan(before - 60), reason: 'several minutes per drag');
    expect(
      await _budgetText(tester, 'budget-available'),
      isNot('Available: 00:00'),
    );
    expect(
      await _budgetText(tester, 'budget-allocated'),
      startsWith('Allocated: '),
    );
    expect(await _budgetText(tester, 'budget-allocated'), endsWith('/ 240:00'));
  });

  testWidgets('a slider proposal beyond the available budget clamps', (
    tester,
  ) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);
    await _openCustomEditor(tester);

    final base = CourtLineup.defaultFor(home);
    final donorId = base.slots.first.playerId.value;
    final receiverId = base.slots[1].playerId.value;

    final donorSlider = find.byKey(ValueKey('target-slider-$donorId'));
    final receiverSlider = find.byKey(ValueKey('target-slider-$receiverId'));
    await _scrollTo(tester, donorSlider);
    final donorValue = tester.widget<Slider>(donorSlider).value.round();
    final receiverBefore = tester.widget<Slider>(receiverSlider).value.round();

    // Fully allocated: an increase proposal clamps back to the same value.
    tester.widget<Slider>(donorSlider).onChanged!((donorValue + 1.0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(donorSlider).value.round(), donorValue);
    expect(await _budgetText(tester, 'budget-available'), 'Available: 00:00');

    // Free 60 seconds from another player.
    final receiverMinus = find.byKey(ValueKey('fine-minus-$receiverId'));
    await _scrollTo(tester, receiverMinus);
    for (var tap = 0; tap < 6; tap++) {
      tester.widget<TextButton>(receiverMinus).onPressed!();
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(await _budgetText(tester, 'budget-available'), 'Available: 01:00');

    // 61 seconds of increase is clamped to the 60 seconds actually available.
    await _scrollTo(tester, donorSlider);
    tester.widget<Slider>(donorSlider).onChanged!((donorValue + 61.0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(donorSlider).value.round(), donorValue + 60);
    expect(await _budgetText(tester, 'budget-available'), 'Available: 00:00');
    expect(
      tester.widget<Slider>(receiverSlider).value.round(),
      receiverBefore - 60,
    );
  });

  testWidgets('all sliders share the fixed 0..2880-second scale', (
    tester,
  ) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);
    await _openCustomEditor(tester);

    final base = CourtLineup.defaultFor(home);
    for (final playerId in base.playerIds) {
      final finder = find.byKey(ValueKey('target-slider-$playerId'));
      await _scrollTo(tester, finder);
      final slider = tester.widget<Slider>(finder);
      expect(slider.min, 0);
      expect(slider.max, 2880);
      expect(slider.divisions, 2880);
      expect(slider.value, lessThanOrEqualTo(2880));
    }
  });

  testWidgets('dragging one slider leaves every other slider untouched', (
    tester,
  ) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);
    await _openCustomEditor(tester);

    final base = CourtLineup.defaultFor(home);
    final dragged = base.playerIds.first;
    final other = base.playerIds[1];
    final draggedFinder = find.byKey(ValueKey('target-slider-$dragged'));
    final otherFinder = find.byKey(ValueKey('target-slider-$other'));
    await _scrollTo(tester, draggedFinder);

    expect(otherFinder.evaluate(), isNotEmpty, reason: 'both rows built');
    final otherBefore = tester.widget<Slider>(otherFinder);
    final otherValueBefore = otherBefore.value;
    final otherMaxBefore = otherBefore.max;
    final otherRectBefore = tester.getRect(otherFinder);
    final otherTextBefore = tester
        .widget<Text>(find.byKey(ValueKey('target-seconds-$other')))
        .data;

    await tester.drag(draggedFinder, const Offset(-70, 0));
    await tester.pumpAndSettle();

    final otherAfter = tester.widget<Slider>(otherFinder);
    expect(otherAfter.value, otherValueBefore);
    expect(otherAfter.max, otherMaxBefore);
    expect(otherAfter.min, 0);
    expect(tester.getRect(otherFinder), otherRectBefore);
    expect(
      tester.widget<Text>(find.byKey(ValueKey('target-seconds-$other'))).data,
      otherTextBefore,
    );
    expect(
      tester.widget<Slider>(draggedFinder).value.round(),
      lessThan(otherValueBefore.round()),
    );
  });

  testWidgets('fine buttons leave every other slider untouched', (
    tester,
  ) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);
    await _openCustomEditor(tester);

    final base = CourtLineup.defaultFor(home);
    final edited = base.playerIds.first;
    final other = base.playerIds[1];
    final otherFinder = find.byKey(ValueKey('target-slider-$other'));
    await _scrollTo(tester, find.byKey(ValueKey('fine-minus-$edited')));

    final otherBefore = tester.widget<Slider>(otherFinder);
    final otherValueBefore = otherBefore.value;
    final otherRectBefore = tester.getRect(otherFinder);
    final editedBefore = tester
        .widget<Slider>(find.byKey(ValueKey('target-slider-$edited')))
        .value
        .round();

    tester
        .widget<TextButton>(find.byKey(ValueKey('fine-minus-$edited')))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(otherFinder.evaluate(), isNotEmpty);
    final otherAfter = tester.widget<Slider>(otherFinder);
    expect(otherAfter.value, otherValueBefore);
    expect(otherAfter.max, 2880);
    expect(tester.getRect(otherFinder), otherRectBefore);
    expect(
      tester
          .widget<Slider>(find.byKey(ValueKey('target-slider-$edited')))
          .value
          .round(),
      editedBefore - 10,
    );
  });

  testWidgets('a slider still decreases when the budget is fully allocated', (
    tester,
  ) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);
    await _openCustomEditor(tester);

    final base = CourtLineup.defaultFor(home);
    final dragged = base.playerIds.first;
    final other = base.playerIds[1];
    final draggedFinder = find.byKey(ValueKey('target-slider-$dragged'));
    await _scrollTo(tester, draggedFinder);
    expect(await _budgetText(tester, 'budget-available'), 'Available: 00:00');
    final otherBefore = tester
        .widget<Slider>(find.byKey(ValueKey('target-slider-$other')))
        .value;

    await tester.drag(draggedFinder, const Offset(-40, 0));
    await tester.pumpAndSettle();

    expect(
      await _budgetText(tester, 'budget-available'),
      isNot('Available: 00:00'),
    );
    expect(tester.widget<Slider>(draggedFinder).value.round(), lessThan(2880));
    expect(
      tester.widget<Slider>(find.byKey(ValueKey('target-slider-$other'))).value,
      otherBefore,
    );
  });

  testWidgets('rapid slider changes never exceed the team budget', (
    tester,
  ) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);
    await _openCustomEditor(tester);

    final base = CourtLineup.defaultFor(home);
    final first = base.slots.first.playerId.value;
    final second = base.slots[1].playerId.value;
    final firstSlider = find.byKey(ValueKey('target-slider-$first'));
    await _scrollTo(tester, firstSlider);

    for (var step = 0; step < 20; step++) {
      final finder = step.isEven
          ? firstSlider
          : find.byKey(ValueKey('target-slider-$second'));
      if (finder.evaluate().isEmpty) continue;
      final slider = tester.widget<Slider>(finder);
      slider.onChanged!(slider.value + (step.isEven ? 400 : 900));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final allocated = await _budgetText(tester, 'budget-allocated');
    expect(allocated, endsWith('/ 240:00'));
    final available = await _budgetText(tester, 'budget-available');
    expect(available, isNot(contains('-')));
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('budget-progress')),
          )
          .value,
      lessThanOrEqualTo(1.0),
    );
  });

  testWidgets('the per-player cap is enforced at 2,880 seconds', (
    tester,
  ) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);
    await _openCustomEditor(tester);

    final base = CourtLineup.defaultFor(home);
    final capped = base.slots.first.playerId.value;
    final donor = base.slots[1].playerId.value;

    final donorSlider = find.byKey(ValueKey('target-slider-$donor'));
    await _scrollTo(tester, donorSlider);
    await tester.drag(donorSlider, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(donorSlider).value.round(), 0);

    final cappedSlider = find.byKey(ValueKey('target-slider-$capped'));
    await _scrollTo(tester, cappedSlider);
    tester.widget<Slider>(cappedSlider).onChanged!(2880);
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(cappedSlider).value.round(), 2880);
    expect(tester.widget<Slider>(cappedSlider).max, lessThanOrEqualTo(2880));

    tester.widget<Slider>(cappedSlider).onChanged!(2881);
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(cappedSlider).value.round(), 2880);
    final available = await _budgetText(tester, 'budget-available');
    expect(available, isNot(contains('-')));
  });

  testWidgets('unallocated minutes are shown and gate confirmation', (
    tester,
  ) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);
    await _openCustomEditor(tester);

    final base = CourtLineup.defaultFor(home);
    final donorId = base.slots.first.playerId.value;
    final receiverId = base.slots[1].playerId.value;

    final donorMinus = find.byKey(ValueKey('fine-minus-$donorId'));
    await _scrollTo(tester, donorMinus);
    for (var tap = 0; tap < 3; tap++) {
      tester.widget<TextButton>(donorMinus).onPressed!();
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(await _budgetText(tester, 'budget-available'), 'Available: 00:30');
    await _scrollTo(tester, find.byKey(const ValueKey('confirm-matchup')));
    expect(_confirmEnabled(tester), isFalse);
    expect(find.byKey(const ValueKey('plan-error')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('plan-error'))).data,
      contains('still available'),
    );

    final receiverPlus = find.byKey(ValueKey('fine-plus-$receiverId'));
    await _scrollTo(tester, receiverPlus);
    for (var tap = 0; tap < 3; tap++) {
      tester.widget<TextButton>(receiverPlus).onPressed!();
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const ValueKey('confirm-matchup')));
    expect(_confirmEnabled(tester), isTrue);
    expect(await _budgetText(tester, 'budget-available'), 'Available: 00:00');

    await _confirm(tester);
    final plan = confirmed.single.rotationPlan!;
    expect(plan.home.preset, RotationPreset.custom);
    expect(
      plan.home.targetSeconds[PlayerId(donorId)],
      _expanded(home, base, RotationPreset.balanced)[PlayerId(donorId)]! - 30,
    );
    expect(
      plan.home.targetSeconds[PlayerId(receiverId)],
      _expanded(home, base, RotationPreset.balanced)[PlayerId(receiverId)]! +
          30,
    );
  });

  testWidgets('a completed drag re-enables confirmation without a drag end', (
    tester,
  ) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);
    await _openCustomEditor(tester);

    final base = CourtLineup.defaultFor(home);
    final donorId = base.slots.first.playerId.value;
    final receiverId = base.slots[1].playerId.value;
    final donorSlider = find.byKey(ValueKey('target-slider-$donorId'));
    await _scrollTo(tester, donorSlider);
    int valueOf(Finder finder) => tester.widget<Slider>(finder).value.round();
    final donorStart = valueOf(donorSlider);

    // Simulate an interrupted drag: only onChanged fires, never onChangeEnd.
    tester.widget<Slider>(donorSlider).onChanged!((donorStart - 60).toDouble());
    await tester.pump();
    expect(await _budgetText(tester, 'budget-available'), 'Available: 01:00');

    final receiverSlider = find.byKey(ValueKey('target-slider-$receiverId'));
    await _scrollTo(tester, receiverSlider);
    final receiverStart = valueOf(receiverSlider);
    tester.widget<Slider>(receiverSlider).onChanged!(
      (receiverStart + 60).toDouble(),
    );
    await tester.pumpAndSettle();

    expect(await _budgetText(tester, 'budget-available'), 'Available: 00:00');
    await _scrollTo(tester, find.byKey(const ValueKey('confirm-matchup')));
    expect(_confirmEnabled(tester), isTrue);
  });

  testWidgets('a zero-target starter gets a named, friendly message', (
    tester,
  ) async {
    await _pumpSetup(tester, league, onConfirm: confirmed.add);
    await _pickTeam(tester, 'home', home);
    await _pickTeam(tester, 'away', away);
    await _openCustomEditor(tester);

    final base = CourtLineup.defaultFor(home);
    final zeroTargetReserve = home.players.firstWhere(
      (player) =>
          !base.containsPlayer(player.id) &&
          _expanded(home, base, RotationPreset.balanced)[player.id] == 0,
    );
    final slotKey = base.slots.first.slot.shortName.toLowerCase();
    await _scrollToTop(tester);
    await tester.tap(find.byKey(ValueKey('starter-slot-$slotKey')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .byKey(
            ValueKey('starter-option-$slotKey-${zeroTargetReserve.id.value}'),
          )
          .hitTestable()
          .last,
    );
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const ValueKey('plan-error')));

    final message = tester
        .widget<Text>(find.byKey(const ValueKey('plan-error')))
        .data!;
    expect(message, contains(zeroTargetReserve.fullName));
    expect(message, contains('reduce another player'));
    expect(message, isNot(contains('player-')));
    expect(_confirmEnabled(tester), isFalse);
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

      final adjust = find.byKey(ValueKey('fine-plus-${reserve.id.value}'));
      await _scrollTo(tester, adjust);
      await tester.tap(adjust);
      await tester.pumpAndSettle();
      final slider = find.byKey(ValueKey('target-slider-${reserve.id.value}'));
      await _scrollTo(tester, slider);
      await tester.drag(slider, const Offset(-40, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _scrollTo(tester, find.byKey(const ValueKey('budget-allocated')));
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
