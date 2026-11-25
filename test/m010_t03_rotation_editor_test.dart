import 'dart:async';

import 'package:basketball_manager/features/career/widgets/hardwood_components.dart';
import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_home_screen.dart';
import 'package:basketball_manager/features/career/career_rotation_screen.dart';
import 'package:basketball_manager/features/career/career_shell_scaffold.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/theme/hardwood_command_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

class _TestStorage extends InMemoryGmCareerStorage {
  _TestStorage(String initial) : super({'default': initial});

  bool failNextWrite = false;
  Completer<void>? hold;

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    if (hold != null) await hold!.future;
    if (failNextWrite) {
      failNextWrite = false;
      throw const GmCareerStorageException('Simulated save failure');
    }
    await super.write(data, slot: slot);
  }
}

GmCareer? _clearedCache;

GmCareer _cleared() => _clearedCache ??= () {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.contender,
      seed: 20261028,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 'm010-t03-editor');
  const draft = DraftExecutionService();
  c = draft.startDraft(c);
  while (!c.draftExecutionState.isCompleted) {
    final state = c.draftExecutionState;
    if (state.isHumanTurn(order: c.draftOrder, userTeamId: c.userFranchiseId)) {
      final pick = c.draftClass.prospects.firstWhere(
        (p) => !state.isProspectSelected(p.id),
      );
      c = draft.makeHumanSelection(career: c, prospectId: pick.id);
    } else {
      c = draft.executeAiSelection(c);
    }
  }
  const aiSigning = RookieAiSigningService();
  c = aiSigning.initialize(c);
  while (aiSigning.pendingRights(c).isNotEmpty) {
    c = aiSigning.applyNextDecision(c);
  }
  for (final r in c.unsignedDraftRights) {
    if (r.owningTeamId == c.userFranchiseId) {
      c = const RookieSigningService().signDraftedRookie(
        career: c,
        teamId: c.userFranchiseId,
        prospectId: r.prospectId,
        category: RosterCategory.standard,
        durationYears: 2,
      );
    }
  }
  const market = FreeAgentMarketService();
  for (var round = 0; round < 2; round++) {
    c = market.startRound(c);
    c = market.prepareResolution(c);
    while (c.freeAgentMarket.isResolvable) {
      c = market.resolveNext(c);
    }
  }
  const clearance = OffseasonClearanceService();
  c = clearance.start(c);
  c = clearance.prepare(c);
  while (c.offseasonClearance.isResolvable) {
    c = clearance.resolveNext(c);
  }
  const hardship = HardshipSettlementService();
  c = hardship.prepare(c, humanParticipationConfirmed: true);
  while (c.hardshipSettlement.isResolvable) {
    c = hardship.resolveNext(c);
  }
  return clearance.markCleared(c);
}();

GmCareer? _scheduledCache;
GmCareer _scheduled() =>
    _scheduledCache ??= const RegularSeasonScheduleService().generate(
      const RegularSeasonEntryService().start(_cleared()),
    );

Team _team(GmCareer c) => RegularSeasonGameAdapter.standardTeamFor(c.userTeam);

List<String> _defaultStarters(GmCareer c) =>
    CourtLineup.defaultFor(_team(c)).playerIds;

Future<(GmCareerController, _TestStorage)> _controller(GmCareer c) async {
  final storage = _TestStorage(GmCareerCodec.encode(c));
  final controller = GmCareerController(storage: storage);
  await controller.loadCareer();
  return (controller, storage);
}

Future<void> _pumpEditor(
  WidgetTester tester,
  GmCareerController controller, {
  Size size = const Size(390, 844),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // Fresh navigator per editor (a rebuilt MaterialApp would keep old routes).
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MaterialApp(
      theme: buildHardwoodCommandTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const ValueKey('open-editor'),
              onPressed: () => openCareerRotationEditor(context, controller),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-editor')));
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

bool _saveEnabled(WidgetTester tester) {
  final pressable = tester.widget<AppPressable>(
    find.descendant(
      of: find.byKey(const ValueKey('rotation-save')),
      matching: find.byType(AppPressable),
    ),
  );
  return pressable.enabled && pressable.onPressed != null;
}

double _sliderValue(WidgetTester tester, String playerId) => tester
    .widget<Slider>(find.byKey(ValueKey('rotation-slider-$playerId')))
    .value;

void main() {
  testWidgets('TEAM tab entry shows mode and readiness and opens AUTO editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final (controller, _) = await _controller(_scheduled());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildHardwoodCommandTheme(),
        home: CareerShellScaffold(
          controller: controller,
          onReturnToMainMenu: () {},
          initialTabIndex: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('LINEUP & ROTATION'), findsOneWidget);
    expect(find.text('AUTO · Ready for simulation'), findsOneWidget);
    expect(find.text('ROSTER & DEPTH'), findsOneWidget);
    expect(find.text('CAP & CONTRACTS'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('team-rotation-entry')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('career-rotation-screen')),
      findsOneWidget,
    );
    expect(find.textContaining('AUTO uses the default lineup'), findsOneWidget);
    // Opening and viewing never persists anything.
    expect(_saveEnabled(tester), isFalse);
    expect(controller.career!.userRotation, CareerRotationSettings.auto);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'starting five: manual pick, out-of-position warning, swap without duplicates',
    (tester) async {
      final career = _scheduled();
      final (controller, _) = await _controller(career);
      addTearDown(controller.dispose);
      await _pumpEditor(tester, controller);
      await _tapKey(tester, 'rotation-mode-manual');
      final team = _team(career);
      final starters = _defaultStarters(career);
      final bench = team.players.firstWhere(
        (p) => !starters.contains(p.id.value) && p.position != Position.pg,
      );

      await _tapKey(tester, 'rotation-slot-PG');
      // Only standard-roster players are offered.
      for (final p in career.userTeam.players) {
        final standard =
            career.userTeam.roster.categoryOf(p.id) == RosterCategory.standard;
        expect(
          find.byKey(ValueKey('rotation-pick-${p.id.value}')),
          standard ? findsOneWidget : findsNothing,
        );
      }
      await _tapKey(tester, 'rotation-pick-${bench.id.value}');
      expect(find.byKey(const ValueKey('rotation-oop-PG')), findsOneWidget);
      expect(find.text(bench.fullName), findsWidgets);

      // Picking the current SG for PG swaps the two: still five unique.
      await _tapKey(tester, 'rotation-slot-PG');
      await _tapKey(tester, 'rotation-pick-${starters[1]}');
      await _tapKey(tester, 'rotation-save');
      final saved = controller.career!.userRotation;
      expect(saved.isManual, isTrue);
      final ids = saved.starters.map((id) => id.value).toList();
      expect(ids.toSet(), hasLength(5));
      expect(ids[0], starters[1]);
      expect(ids[1], bench.id.value);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'playing time: preset expansion, fixed independent sliders, fine steps, exact budget',
    (tester) async {
      final career = _scheduled();
      final (controller, storage) = await _controller(career);
      addTearDown(controller.dispose);
      await _pumpEditor(tester, controller);
      await _tapKey(tester, 'rotation-view-playing-time');
      await _tapKey(tester, 'rotation-preset-starterHeavy');
      final team = _team(career);
      final expanded = RotationPlan.expandPreset(
        preset: RotationPreset.starterHeavy,
        team: team,
        lineup: CourtLineup.defaultFor(team),
        rules: GameRules.standard,
      );
      for (final p in team.players) {
        expect(
          tester
              .widget<Text>(
                find.byKey(ValueKey('rotation-seconds-${p.id.value}')),
              )
              .data,
          _fmt(expanded[p.id]!),
        );
      }

      await _tapKey(tester, 'rotation-preset-custom');
      expect(find.text('Allocated 240:00 / 240:00'), findsOneWidget);
      final a = team.players[0].id.value;
      final b = team.players[1].id.value;
      final slider = tester.widget<Slider>(
        find.byKey(ValueKey('rotation-slider-$a')),
      );
      expect(slider.max, 2880);
      expect(slider.divisions, 2880);
      final bBefore = _sliderValue(tester, b);

      await _tapKey(tester, 'rotation-fine-minus-$a');
      expect(_sliderValue(tester, a), expanded[PlayerId(a)]! - 10);
      expect(_sliderValue(tester, b), bBefore, reason: 'independent sliders');
      expect(find.text('Allocated 239:50 / 240:00'), findsOneWidget);
      expect(
        _saveEnabled(tester),
        isFalse,
        reason: 'incomplete budget blocks save',
      );
      // Budget is a hard limit: +10 on a fully used budget is rejected for b.
      await _tapKey(tester, 'rotation-fine-plus-$a');
      expect(find.text('Allocated 240:00 / 240:00'), findsOneWidget);
      final bFine = find.byKey(ValueKey('rotation-fine-plus-$b'));
      await tester.ensureVisible(bFine);
      await tester.tap(bFine, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_sliderValue(tester, b), bBefore);

      // Slider drag clamps to the remaining budget and moves only that player.
      await tester.ensureVisible(find.byKey(ValueKey('rotation-slider-$a')));
      await tester.drag(
        find.byKey(ValueKey('rotation-slider-$a')),
        const Offset(-60, 0),
      );
      await tester.pumpAndSettle();
      expect(_sliderValue(tester, a), lessThan(expanded[PlayerId(a)]!));
      expect(_sliderValue(tester, b), bBefore);
      expect(_sliderValue(tester, a) % 1, 0, reason: 'integer seconds');

      // A drag far right clamps at the remaining budget: exact fill, no loop.
      await tester.drag(
        find.byKey(ValueKey('rotation-slider-$a')),
        const Offset(400, 0),
      );
      await tester.pumpAndSettle();
      expect(_sliderValue(tester, a), expanded[PlayerId(a)]!);
      expect(_sliderValue(tester, b), bBefore);
      expect(find.text('Allocated 240:00 / 240:00'), findsOneWidget);
      await _tapKey(tester, 'rotation-save');
      expect(find.text('Rotation saved.'), findsOneWidget);
      final saved = controller.career!.userRotation;
      expect(saved.preset, RotationPreset.custom);
      expect(saved.customTargets.values.fold(0, (x, y) => x + y), 14400);

      // Persistence after restart: a fresh controller reads the same plan.
      final reloaded = GmCareerController(storage: storage);
      addTearDown(reloaded.dispose);
      await reloaded.loadCareer();
      expect(reloaded.career!.userRotation, saved);
    },
  );

  testWidgets(
    'unassigned players stay unassigned until explicitly confirmed; draft survives view changes; discard warns',
    (tester) async {
      final career = _scheduled();
      final team = _team(career);
      final starters = _defaultStarters(career);
      final missing = team.players.lastWhere(
        (p) => !starters.contains(p.id.value),
      );
      final targets = <String, int>{
        for (final p in team.players)
          if (p.id != missing.id)
            p.id.value: starters.contains(p.id.value) ? 2880 : 0,
      };
      final committed = CareerRotationSettings.manual(
        starters: [for (final id in starters) PlayerId(id)],
        preset: RotationPreset.custom,
        customTargets: targets,
      );
      final (controller, _) = await _controller(
        career.copyWith(userRotation: committed),
      );
      addTearDown(controller.dispose);
      await _pumpEditor(tester, controller);
      await _tapKey(tester, 'rotation-view-playing-time');
      expect(
        tester
            .widget<Text>(
              find.byKey(ValueKey('rotation-role-${missing.id.value}')),
            )
            .data,
        'NEW · UNASSIGNED',
      );
      expect(find.byKey(const ValueKey('rotation-unassigned')), findsOneWidget);
      // Opening alone does not convert the missing target.
      expect(controller.career!.userRotation, committed);

      // An unrelated edit keeps save blocked until the new player is reviewed.
      await _tapKey(tester, 'rotation-fine-minus-${starters[0]}');
      await _tapKey(tester, 'rotation-view-depth');
      await _tapKey(tester, 'rotation-view-playing-time');
      expect(_sliderValue(tester, starters[0]), 2870, reason: 'draft kept');
      await _tapKey(tester, 'rotation-fine-plus-${starters[0]}');
      expect(_saveEnabled(tester), isFalse);

      await _tapKey(tester, 'rotation-ack-zero-${missing.id.value}');
      expect(_saveEnabled(tester), isTrue);

      // Back with unsaved work asks first; cancel keeps the draft.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.maybePop());
      await tester.pumpAndSettle();
      expect(find.text('Discard rotation changes?'), findsOneWidget);
      await _tapKey(tester, 'rotation-discard-cancel');
      expect(
        find.byKey(const ValueKey('career-rotation-screen')),
        findsOneWidget,
      );

      await _tapKey(tester, 'rotation-save');
      expect(
        controller.career!.userRotation.customTargets[missing.id.value],
        0,
      );
      unawaited(navigator.maybePop());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('career-rotation-screen')),
        findsNothing,
      );
    },
  );

  testWidgets('depth chart is a labelled read-only preview of the draft', (
    tester,
  ) async {
    final career = _scheduled();
    final (controller, _) = await _controller(career);
    addTearDown(controller.dispose);
    await _pumpEditor(tester, controller);
    await _tapKey(tester, 'rotation-view-depth');
    expect(find.text('DEPTH CHART · PREVIEW'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rotation-depth-disclaimer')),
      findsOneWidget,
    );
    for (final pos in Position.values) {
      expect(
        find.byKey(ValueKey('rotation-depth-${pos.shortName}')),
        findsOneWidget,
      );
    }
    expect(find.text('STARTER'), findsNWidgets(5));
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(ReorderableListView), findsNothing);
  });

  testWidgets(
    'obsolete plan: complete repair applies; incomplete repair only loads the draft',
    (tester) async {
      final cleared = _cleared();
      final starters = _defaultStarters(cleared);
      final obsolete = CareerRotationSettings.manual(
        starters: [
          const PlayerId('departed-player'),
          for (final id in starters.skip(1)) PlayerId(id),
        ],
        preset: RotationPreset.balanced,
      );
      final (controller, _) = await _controller(
        cleared.copyWith(userRotation: obsolete),
      );
      addTearDown(controller.dispose);
      await _pumpEditor(tester, controller);
      expect(find.byKey(const ValueKey('rotation-issues')), findsOneWidget);
      expect(
        find.textContaining('no longer on your standard roster'),
        findsWidgets,
      );
      await _tapKey(tester, 'rotation-preview-repair');
      expect(
        find.byKey(const ValueKey('rotation-repair-complete')),
        findsOneWidget,
      );
      await _tapKey(tester, 'rotation-repair-apply');
      final repaired = controller.career!.userRotation;
      expect(repaired.isManual, isTrue);
      expect(repaired.starters.first.value, isNot('departed-player'));
      expect(find.byKey(const ValueKey('rotation-issues')), findsNothing);

      // Incomplete (custom shortfall): load into draft, never persisted.
      final team = _team(cleared);
      final customObsolete = CareerRotationSettings.manual(
        starters: obsolete.starters,
        preset: RotationPreset.custom,
        customTargets: {
          'departed-player': 2880,
          for (final p in team.players)
            p.id.value: starters.skip(1).contains(p.id.value) ? 2880 : 0,
        },
      );
      final (controller2, _) = await _controller(
        cleared.copyWith(userRotation: customObsolete),
      );
      addTearDown(controller2.dispose);
      await _pumpEditor(tester, controller2);
      await _tapKey(tester, 'rotation-preview-repair');
      expect(
        find.byKey(const ValueKey('rotation-repair-incomplete')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('rotation-repair-apply')), findsNothing);
      await _tapKey(tester, 'rotation-repair-load');
      expect(controller2.career!.userRotation, customObsolete);
      expect(
        find.textContaining('Repair loaded into the editor'),
        findsOneWidget,
      );
    },
  );

  testWidgets('blocked season entry routes to AUTO or the editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cleared = _cleared();
    final obsolete = CareerRotationSettings.manual(
      starters: [
        const PlayerId('departed-player'),
        for (final id in _defaultStarters(cleared).skip(1)) PlayerId(id),
      ],
      preset: RotationPreset.balanced,
    );
    final (controller, _) = await _controller(
      cleared.copyWith(userRotation: obsolete),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildHardwoodCommandTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (_, _) =>
                CareerHomeScreen(controller: controller, onSelectTab: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('home-rotation-attention')),
      findsOneWidget,
    );
    await _tapKey(tester, 'home-primary-cta');
    await _tapKey(tester, 'confirm-start-regular-season');
    expect(
      find.byKey(const ValueKey('rotation-blocked-dialog')),
      findsOneWidget,
    );
    expect(controller.career!.phase, CareerPhase.openingOffseason);
    expect(controller.career!.userRotation, obsolete);
    await _tapKey(tester, 'rotation-blocked-auto');
    expect(controller.career!.userRotation, CareerRotationSettings.auto);
    expect(find.byKey(const ValueKey('home-rotation-attention')), findsNothing);
    await _tapKey(tester, 'home-primary-cta');
    await _tapKey(tester, 'confirm-start-regular-season');
    expect(controller.career!.phase, CareerPhase.regularSeason);
  });

  testWidgets(
    'busy controller locks editing; failed save keeps committed plan and offers reload',
    (tester) async {
      final career = _scheduled();
      final (controller, storage) = await _controller(career);
      addTearDown(controller.dispose);
      await _pumpEditor(tester, controller);
      await _tapKey(tester, 'rotation-mode-manual');

      // Failed save.
      storage.failNextWrite = true;
      await _tapKey(tester, 'rotation-save');
      expect(controller.career!.userRotation, CareerRotationSettings.auto);
      expect(find.textContaining('Save failed'), findsOneWidget);
      expect(find.byKey(const ValueKey('rotation-reload')), findsOneWidget);
      expect(find.byKey(const ValueKey('rotation-locked')), findsOneWidget);
      await _tapKey(tester, 'rotation-reload');
      expect(controller.draftRecoveryRequired, isFalse);
      // Draft (MANUAL) survived the failure and reload; saving now succeeds.
      await _tapKey(tester, 'rotation-save');
      expect(controller.career!.userRotation.isManual, isTrue);

      // A running command locks the editor.
      storage.hold = Completer<void>();
      final pending = controller.resetUserRotationToAuto();
      await tester.pump();
      expect(controller.isLoading, isTrue);
      await tester.pump();
      expect(find.byKey(const ValueKey('rotation-locked')), findsOneWidget);
      storage.hold!.complete();
      storage.hold = null;
      await pending;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rotation-locked')), findsNothing);
    },
  );

  for (final (size, scale) in const [
    (Size(320, 640), 1.0),
    (Size(390, 844), 1.6),
  ]) {
    testWidgets('narrow width / large text uses list layout ($size, $scale)', (
      tester,
    ) async {
      final (controller, _) = await _controller(_scheduled());
      addTearDown(controller.dispose);
      await _pumpEditor(tester, controller, size: size, textScale: scale);
      await _tapKey(tester, 'rotation-mode-manual');
      expect(find.byKey(const ValueKey('rotation-five-list')), findsOneWidget);
      await _tapKey(tester, 'rotation-view-playing-time');
      await _tapKey(tester, 'rotation-preset-custom');
      await _tapKey(tester, 'rotation-view-depth');
      expect(tester.takeException(), isNull);
    });
  }
}

String _fmt(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
