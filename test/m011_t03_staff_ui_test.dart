import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_rotation_screen.dart';
import 'package:basketball_manager/features/career/career_shell_scaffold.dart';
import 'package:basketball_manager/features/career/career_staff_view.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:basketball_manager/features/career/career_ui_labels.dart';
import 'package:basketball_manager/theme/hardwood_command_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

class _TestStorage extends InMemoryGmCareerStorage {
  _TestStorage(String initial) : super({'default': initial});

  bool failNextWrite = false;
  int writes = 0;

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw const GmCareerStorageException('Simulated save failure');
    }
    writes++;
    await super.write(data, slot: slot);
  }
}

GmCareer? _clearedCache;

/// Real Year-1 offseason through clearance (tanking team-1).
GmCareer _cleared() => _clearedCache ??= () {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: 20261028,
    ),
  );
  var c = GmCareer.fromSetupResult(setup, id: 'm011-t03-ui');
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

Team _team(GmCareer c) => RegularSeasonGameAdapter.standardTeamFor(c.userTeam);

Future<(GmCareerController, _TestStorage)> _controller(GmCareer c) async {
  final storage = _TestStorage(GmCareerCodec.encode(c));
  final controller = GmCareerController(storage: storage);
  await controller.loadCareer();
  return (controller, storage);
}

Future<void> _pumpStaff(WidgetTester tester, GmCareerController c) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildHardwoodCommandTheme(),
      home: CareerShellScaffold(
        controller: c,
        onReturnToMainMenu: () {},
        initialTabIndex: 1,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _tapKey(tester, 'team-view-staff');
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String _rowText(WidgetTester tester, String key) {
  final texts = tester
      .widgetList<Text>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Text),
        ),
      )
      .map((t) => t.data ?? '')
      .toList();
  return texts.last;
}

void main() {
  testWidgets('STAFF overview shows real staff, money and a gated market', (
    tester,
  ) async {
    final career = _cleared();
    final (controller, storage) = await _controller(career);
    addTearDown(controller.dispose);
    await _pumpStaff(tester, controller);

    final user = career.userFranchiseId;
    final coach = career.staff.employedHeadCoach(user)!;
    expect(find.byKey(const ValueKey('career-staff-view')), findsOneWidget);
    expect(find.text('OFF'), findsOneWidget);
    expect(find.text('${coach.firstName} ${coach.lastName}'), findsWidgets);
    expect(
      _rowText(tester, 'staff-delegation'),
      'Default rotation (coaching off)',
    );
    // Budget panel values come straight from CareerFinances.
    final s = StaffFinanceSnapshot.of(career, user);
    expect(
      _rowText(tester, 'staff-budget-commitments'),
      CareerUiLabels.formatCu(career.finances.operatingCommitmentsFor(user)),
    );
    expect(
      _rowText(tester, 'staff-budget-cash'),
      CareerUiLabels.formatCu(
        career.finances.projectedEndOfSeasonCash(user, career.currentYear),
      ),
    );
    expect(s.activeStaffSalaries, FinancialRules.initialStaffCost);
    expect(s.dismissedStillPayable, 0);
    // Six named contracts; supporting roles flagged as contract-only.
    for (final c in career.finances.staffCommitments.values) {
      if (c.teamId == user) {
        expect(find.byKey(ValueKey('staff-contract-${c.id}')), findsOneWidget);
      }
    }
    expect(
      find.text('No gameplay effect yet (contract only)'),
      findsNWidgets(5),
    );
    // Market is gated until coaching is on; nothing was written.
    expect(find.byKey(const ValueKey('staff-actions-blocked')), findsOneWidget);
    expect(storage.writes, 0);

    // Profile inspection.
    await _tapKey(tester, 'staff-head-coach-open');
    expect(find.byKey(const ValueKey('staff-coach-profile')), findsOneWidget);
    expect(
      find.text(CareerUiLabels.coachPhilosophy(coach.philosophy!)),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('activation needs explicit confirmation and is persisted', (
    tester,
  ) async {
    final (controller, storage) = await _controller(_cleared());
    addTearDown(controller.dispose);
    await _pumpStaff(tester, controller);

    await _tapKey(tester, 'staff-enable');
    expect(find.byKey(const ValueKey('staff-enable-dialog')), findsOneWidget);
    expect(find.textContaining('permanent'), findsOneWidget);
    expect(
      find.textContaining('first recruit head coaches at the start of next'),
      findsOneWidget,
      reason: 'free agency already opened in this fixture',
    );
    await _tapKey(tester, 'staff-enable-cancel');
    expect(controller.career!.staff.coachingEnabled, isFalse);
    expect(storage.writes, 0);

    await _tapKey(tester, 'staff-enable');
    await _tapKey(tester, 'staff-enable-confirm');
    expect(controller.career!.staff.coachingEnabled, isTrue);
    expect(storage.writes, 1);
    expect(
      GmCareerCodec.decode((await storage.read())!).staff.coachingEnabled,
      isTrue,
    );
    expect(find.byKey(const ValueKey('staff-enable')), findsNothing);
    final coach = controller.career!.staff.employedHeadCoach(
      controller.career!.userFranchiseId,
    )!;
    expect(
      _rowText(tester, 'staff-delegation'),
      startsWith('Head Coach ${coach.firstName} ${coach.lastName}'),
    );
    for (final c in const StaffMarketService().headCoachCandidates(
      controller.career!,
    )) {
      expect(find.byKey(ValueKey('staff-candidate-${c.id}')), findsOneWidget);
    }
  });

  testWidgets(
    'hire preview equals the core transaction; save failure keeps state',
    (tester) async {
      final enabled = const StaffMarketService().enableCoaching(_cleared());
      final (controller, storage) = await _controller(enabled);
      addTearDown(controller.dispose);
      await _pumpStaff(tester, controller);
      final user = enabled.userFranchiseId;
      final candidate = const StaffMarketService()
          .headCoachCandidates(enabled)
          .first;

      await _tapKey(tester, 'staff-candidate-${candidate.id}');
      expect(find.byKey(const ValueKey('staff-hire-sheet')), findsOneWidget);
      await _tapKey(tester, 'staff-years-3');
      expect(
        _rowText(tester, 'staff-hire-total'),
        CareerUiLabels.formatCu(7500),
      );
      final expected = const StaffMarketService().replaceHeadCoach(
        enabled,
        teamId: user,
        candidateId: candidate.id,
        durationYears: 3,
      );
      expect(
        _rowText(tester, 'staff-preview-cash'),
        '${CareerUiLabels.formatCu(enabled.finances.projectedEndOfSeasonCash(user, 1))}'
        ' → '
        '${CareerUiLabels.formatCu(expected.finances.projectedEndOfSeasonCash(user, 1))}',
      );

      // Failed save: nothing changes, recovery offered.
      storage.failNextWrite = true;
      await _tapKey(tester, 'staff-hire-confirm');
      expect(find.textContaining('Save failed'), findsOneWidget);
      expect(
        GmCareerCodec.encode(controller.career!),
        GmCareerCodec.encode(enabled),
      );
      await _tapKey(tester, 'staff-reload');
      expect(controller.draftRecoveryRequired, isFalse);

      // Retry succeeds and matches the core transaction exactly.
      await _tapKey(tester, 'staff-candidate-${candidate.id}');
      await _tapKey(tester, 'staff-years-3');
      await _tapKey(tester, 'staff-hire-confirm');
      expect(
        GmCareerCodec.encode(controller.career!),
        GmCareerCodec.encode(expected),
      );
      expect(
        find.text('Dismissed — salary still paid through Year 1'),
        findsOneWidget,
      );
      expect(
        _rowText(tester, 'staff-budget-dismissed'),
        CareerUiLabels.formatCu(2500),
      );
    },
  );

  testWidgets('dismiss and renew use confirmations with money consequences', (
    tester,
  ) async {
    final enabled = const StaffMarketService().enableCoaching(_cleared());
    final (controller, _) = await _controller(enabled);
    addTearDown(controller.dispose);
    await _pumpStaff(tester, controller);
    final user = enabled.userFranchiseId;

    await _tapKey(tester, 'staff-renew');
    expect(find.byKey(const ValueKey('staff-renew-sheet')), findsOneWidget);
    await _tapKey(tester, 'staff-years-2');
    expect(_rowText(tester, 'staff-renew-end'), 'Year 1 → Year 3');
    await _tapKey(tester, 'staff-renew-confirm');
    final coach = controller.career!.staff.employedHeadCoach(user)!;
    expect(
      controller
          .career!
          .finances
          .staffCommitments[coach.commitmentId]!
          .durationYears,
      3,
    );

    await _tapKey(tester, 'staff-dismiss');
    expect(find.byKey(const ValueKey('staff-dismiss-dialog')), findsOneWidget);
    expect(find.textContaining('does not cancel the contract'), findsOneWidget);
    await _tapKey(tester, 'staff-dismiss-confirm');
    expect(controller.career!.staff.employedHeadCoach(user), isNull);
    expect(
      controller.career!.finances.staffCommitments.containsKey(
        coach.commitmentId,
      ),
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('staff-head-coach-vacant')),
      findsOneWidget,
    );
    expect(
      _rowText(tester, 'staff-delegation'),
      'No head coach — default rotation',
    );
  });

  testWidgets(
    'AUTO preview shows the coach plan; manual is kept and restored',
    (tester) async {
      final enabled = const StaffMarketService().enableCoaching(_cleared());
      final (controller, _) = await _controller(enabled);
      addTearDown(controller.dispose);
      final team = _team(enabled);
      final coachPlan = CareerRotationService.decisionForUser(enabled);
      expect(coachPlan.authority, RotationAuthority.headCoach);

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildHardwoodCommandTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const ValueKey('open-editor'),
                onPressed: () => openCareerRotationEditor(context, controller),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await _tapKey(tester, 'open-editor');
      expect(
        find.textContaining('AUTO delegates to Head Coach'),
        findsOneWidget,
      );
      // Every coach starter appears in the Starting Five preview.
      final byId = {for (final p in team.players) p.id.value: p};
      for (final id in coachPlan.lineup.playerIds) {
        expect(find.textContaining(byId[id]!.lastName), findsWidgets);
      }

      // Save a MANUAL plan, then switch back to AUTO: the plan is kept.
      await _tapKey(tester, 'rotation-mode-manual');
      await _tapKey(tester, 'rotation-view-playing-time');
      final preset = coachPlan.plan.preset == RotationPreset.starterHeavy
          ? RotationPreset.balanced
          : RotationPreset.starterHeavy;
      await _tapKey(tester, 'rotation-preset-${preset.jsonValue}');
      await _tapKey(tester, 'rotation-save');
      final manual = controller.career!.userRotation;
      expect(manual.isManual, isTrue);
      expect(manual.preset, preset);
      await _tapKey(tester, 'rotation-mode-auto');
      await _tapKey(tester, 'rotation-save');
      expect(controller.career!.userRotation.isManual, isFalse);
      expect(controller.career!.userRotation.retainedManual, manual);
      await _tapKey(tester, 'rotation-mode-manual');
      await _tapKey(tester, 'rotation-save');
      expect(controller.career!.userRotation, manual);
      await _tapKey(tester, 'rotation-mode-auto');
      await _tapKey(tester, 'rotation-save');
      await _tapKey(tester, 'rotation-restore-manual');
      expect(controller.career!.userRotation, manual);
    },
  );

  testWidgets('an obsolete retained plan loads as a repair draft, unsaved', (
    tester,
  ) async {
    final base = _cleared();
    final defaults = CourtLineup.defaultFor(_team(base)).playerIds;
    final obsolete = CareerRotationSettings.manual(
      starters: [
        const PlayerId('departed-player'),
        for (final id in defaults.skip(1)) PlayerId(id),
      ],
      preset: RotationPreset.balanced,
    );
    final start = base.copyWith(
      userRotation: CareerRotationSettings.autoRetaining(obsolete),
    );
    final (controller, storage) = await _controller(start);
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildHardwoodCommandTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('open-editor'),
              onPressed: () => openCareerRotationEditor(context, controller),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await _tapKey(tester, 'open-editor');
    await _tapKey(tester, 'rotation-restore-manual');
    expect(find.textContaining('no longer fits the roster'), findsOneWidget);
    expect(find.textContaining('repaired draft is loaded'), findsOneWidget);
    // Nothing saved or erased yet.
    expect(storage.writes, 0);
    expect(
      controller.career!.userRotation,
      CareerRotationSettings.autoRetaining(obsolete),
    );
    await _tapKey(tester, 'rotation-save');
    expect(controller.career!.userRotation.isManual, isTrue);
    expect(
      controller.career!.userRotation.starters.first,
      isNot(const PlayerId('departed-player')),
    );
  });
}
