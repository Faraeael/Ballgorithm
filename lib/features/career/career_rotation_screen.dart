import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import '../../theme/hardwood_command_theme.dart';
import '../game/participation_view.dart';
import '../game/rotation_budget.dart';
import 'career_controller.dart';
import 'career_ui_labels.dart';
import 'widgets/hardwood_components.dart';

/// The three approved M010 editor views; all share one unsaved draft.
enum RotationEditorView { startingFive, playingTime, depthChart }

/// Human-readable text for a rotation issue, naming players where the career
/// still knows them (roster, two-way, free agent or retired).
String describeRotationIssue(CareerRotationIssue issue, GmCareer career) {
  final name = issue.playerId == null
      ? null
      : careerPlayerName(career, issue.playerId!.value);
  switch (issue.code) {
    case CareerRotationIssueCode.starterUnavailable:
      return '${issue.slot?.shortName ?? 'Starter'}: $name is no longer on '
          'your standard roster (departed, retired, two-way or unsigned).';
    case CareerRotationIssueCode.targetPlayerUnavailable:
      return '$name still holds ${formatMinutes(issue.seconds ?? 0)} of '
          'planned minutes but is no longer eligible.';
    case CareerRotationIssueCode.planInvalid:
      return switch (issue.validationCode) {
        GameValidationCode.invalidRotationTotal =>
          'Planned minutes must total exactly 240:00.',
        GameValidationCode.starterTargetNotPositive =>
          'Every starter needs planned minutes above 0:00.',
        GameValidationCode.invalidRotationSeconds =>
          'A player is planned above the 48:00 regulation limit.',
        GameValidationCode.invalidRosterSizeForRotation =>
          'A rotation needs at least five standard players.',
        _ => issue.message,
      };
  }
}

/// Resolves a display name for [playerId] anywhere in the career.
String careerPlayerName(GmCareer career, String playerId) {
  for (final team in career.league.teams) {
    for (final player in team.players) {
      if (player.id.value == playerId) return player.fullName;
    }
  }
  for (final entry in career.freeAgentPool.entries) {
    if (entry.id.value == playerId) return entry.player.fullName;
  }
  for (final retired in career.retiredPlayers) {
    if (retired.playerId.value == playerId) return retired.fullName;
  }
  return playerId;
}

/// Opens the Lineup & Rotation editor.
Future<void> openCareerRotationEditor(
  BuildContext context,
  GmCareerController controller, {
  RotationEditorView initialView = RotationEditorView.startingFive,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) =>
        CareerRotationScreen(controller: controller, initialView: initialView),
  ),
);

/// Hardwood Command Lineup & Rotation editor for the human franchise (M010).
class CareerRotationScreen extends StatefulWidget {
  const CareerRotationScreen({
    super.key,
    required this.controller,
    this.initialView = RotationEditorView.startingFive,
  });

  final GmCareerController controller;
  final RotationEditorView initialView;

  @override
  State<CareerRotationScreen> createState() => _CareerRotationScreenState();
}

class _CareerRotationScreenState extends State<CareerRotationScreen> {
  static final GameRules _rules = GameRules.standard;
  static final int _cap = RotationPlan.regulationCap(_rules);
  static final int _teamTotal = RotationPlan.regulationTeamTotal(_rules);

  late RotationEditorView _view = widget.initialView;

  // One shared unsaved draft across all three views.
  bool _manual = false;
  List<String> _starters = const [];
  RotationPreset _preset = RotationPreset.balanced;
  Map<String, int> _customTargets = {};
  bool _dirty = false;

  bool _saving = false;
  String? _status;
  bool _statusIsError = false;

  GmCareerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _loadDraftFromCommitted();
  }

  Team? _standardTeam(GmCareer career) {
    try {
      return RegularSeasonGameAdapter.standardTeamFor(career.userTeam);
    } on FormatException {
      return null;
    }
  }

  List<String> _defaultStarters(Team team) {
    try {
      return CourtLineup.defaultFor(team).playerIds;
    } on GameValidationException {
      return [for (final p in team.players.take(5)) p.id.value];
    }
  }

  void _loadDraftFromCommitted() {
    final career = _controller.career;
    if (career == null) return;
    final team = _standardTeam(career);
    final committed = career.userRotation;
    _loadDraftFrom(committed, team);
    _dirty = false;
  }

  void _loadDraftFrom(CareerRotationSettings settings, Team? team) {
    final rosterIds = {for (final p in team?.players ?? <Player>[]) p.id.value};
    if (settings.isManual) {
      _manual = true;
      _starters = [for (final id in settings.starters) id.value];
      _preset = settings.preset;
      // Departed players' targets stay in the committed save (and are reported
      // as issues) but are not editable rows in the draft.
      _customTargets = {
        for (final entry in settings.customTargets.entries)
          if (rosterIds.contains(entry.key)) entry.key: entry.value,
      };
    } else {
      // AUTO draft mirrors what AUTO will actually use (M011: the head
      // coach's plan when coaching is on), so switching to MANUAL starts
      // from exactly what was shown.
      final decision = team == null ? null : _autoDecision(team);
      _manual = false;
      _starters = team == null
          ? const []
          : decision?.lineup.playerIds ?? _defaultStarters(team);
      _preset = decision?.plan.preset ?? RotationPreset.balanced;
      _customTargets = _preset == RotationPreset.custom
          ? {
              for (final e in decision!.plan.targetSeconds.entries)
                e.key.value: e.value,
            }
          : {};
    }
  }

  /// What AUTO means for the human team now (coach plan or default).
  TeamRotationDecision? _autoDecision(Team team) {
    final career = _controller.career;
    if (career == null) return null;
    try {
      return CareerRotationService.autoDecisionFor(career, team, rules: _rules);
    } on GameValidationException {
      return null;
    }
  }

  List<String> _autoStarters(Team team) =>
      _autoDecision(team)?.lineup.playerIds ?? _defaultStarters(team);

  bool get _busy =>
      _saving ||
      _controller.isLoading ||
      _controller.isBatchSimulating ||
      _controller.seasonTransitionStage != null ||
      _controller.draftRecoveryRequired;

  CareerRotationSettings? _draftSettings() {
    if (!_manual) return CareerRotationSettings.auto;
    try {
      return CareerRotationSettings.manual(
        starters: [for (final id in _starters) PlayerId(id)],
        preset: _preset,
        customTargets: _preset == RotationPreset.custom
            ? Map.of(_customTargets)
            : null,
      );
    } on FormatException {
      return null;
    }
  }

  List<String> _unassigned(Team team) =>
      _manual && _preset == RotationPreset.custom
      ? [
          for (final p in team.players)
            if (!_customTargets.containsKey(p.id.value)) p.id.value,
        ]
      : const [];

  /// Targets shown for the draft. Never invents values: custom shows exactly
  /// what is in the draft (unassigned players render as unassigned).
  Map<String, int> _draftTargets(Team team) {
    if (!_manual) {
      final auto = _autoDecision(team);
      if (auto == null) return const {};
      return {
        for (final e in auto.plan.targetSeconds.entries) e.key.value: e.value,
      };
    }
    if (_preset == RotationPreset.custom) return _customTargets;
    try {
      final byId = {for (final p in team.players) p.id.value: p};
      final lineup = CourtLineup.create(
        team: team,
        slotOrderedPlayers: [for (final id in _starters) byId[id]!],
      );
      return {
        for (final e in RotationPlan.expandPreset(
          preset: _preset,
          team: team,
          lineup: lineup,
          rules: _rules,
        ).entries)
          e.key.value: e.value,
      };
    } catch (_) {
      return const {};
    }
  }

  void _edit(VoidCallback change) {
    if (_busy) return;
    setState(() {
      change();
      _dirty = true;
      _status = null;
    });
  }

  void _setMode(bool manual, Team team) {
    if (manual == _manual || _busy) return;
    final career = _controller.career;
    final retained = career?.userRotation.retainedManual;
    if (manual && career != null && retained != null) {
      final resolution = CareerRotationService.resolve(retained, team);
      if (resolution.isValid) {
        _edit(() => _loadDraftFrom(retained, team));
      } else {
        _loadRetainedRepairDraft(career, team, retained, resolution);
      }
      return;
    }
    _edit(() {
      _manual = manual;
      if (manual && _starters.length != 5) {
        _starters = _defaultStarters(team);
      }
    });
  }

  void _assignStarter(int slotIndex, String playerId) {
    _edit(() {
      final next = List<String>.of(_starters);
      final existing = next.indexOf(playerId);
      if (existing == slotIndex) return;
      if (existing >= 0) {
        // Swap: the displaced starter takes the selected player's old slot.
        next[existing] = next[slotIndex];
      }
      next[slotIndex] = playerId;
      _starters = next;
    });
  }

  void _selectPreset(RotationPreset preset, Team team) {
    if (preset == _preset) return;
    _edit(() {
      if (preset == RotationPreset.custom) {
        // M005: custom starts from the allocation the user was just shown.
        _customTargets = Map.of(_draftTargets(team));
      } else {
        _customTargets = {};
      }
      _preset = preset;
    });
  }

  void _setTarget(String playerId, int seconds, {bool clamp = false}) {
    if (_busy || !_manual || _preset != RotationPreset.custom) return;
    final next = RotationBudget.propose(
      _customTargets,
      playerId,
      seconds,
      cap: _cap,
      teamTotal: _teamTotal,
      clamp: clamp,
    );
    if (next == null) return;
    _edit(() => _customTargets = {..._customTargets, playerId: next});
  }

  Future<void> _save() async {
    final settings = _draftSettings();
    if (settings == null || _busy) return;
    setState(() {
      _saving = true;
      _status = null;
    });
    try {
      if (settings.isManual) {
        await _controller.updateUserRotation(settings);
      } else if (_controller.career?.userRotation.isManual ?? false) {
        // M011: AUTO keeps the saved manual plan for later restoration.
        await _controller.delegateUserRotationKeepingManual();
      }
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _status = 'Rotation saved.';
        _statusIsError = false;
      });
    } catch (error) {
      if (!mounted) return;
      final career = _controller.career;
      setState(() {
        _statusIsError = true;
        _status = error is CareerRotationInvalidException && career != null
            ? error.issues
                  .map((issue) => describeRotationIssue(issue, career))
                  .join('\n')
            : _controller.draftRecoveryRequired
            ? 'Save failed. Your previous rotation is unchanged. Reload the '
                  'saved career before continuing; your unsaved edits stay here.'
            : 'Not saved: $error';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reloadAfterFailure() async {
    await _controller.loadCareer();
    if (!mounted) return;
    setState(() {
      _status = _controller.draftRecoveryRequired
          ? 'Reload failed. Try again.'
          : 'Saved career reloaded. Review and save your edits again.';
      _statusIsError = _controller.draftRecoveryRequired;
    });
  }

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard rotation changes?'),
        content: const Text(
          'Your unsaved lineup and playing-time edits will be lost. The saved '
          'rotation stays unchanged.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('rotation-discard-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            key: const ValueKey('rotation-discard-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _switchCommittedToAuto() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Switch to AUTO?'),
        content: const Text(
          'AUTO takes over the rotation. Your saved manual plan is kept and '
          'can be restored (and repaired) later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('rotation-switch-auto-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Switch to AUTO'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _controller.delegateUserRotationKeepingManual();
      if (!mounted) return;
      setState(() {
        _loadDraftFromCommitted();
        _status = 'Switched to AUTO.';
        _statusIsError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Not saved: $error';
        _statusIsError = true;
      });
    }
  }

  Future<void> _previewRepair(GmCareer career, Team team) async {
    final committed = career.userRotation;
    final proposal = CareerRotationService.proposeRepair(committed, team);
    if (proposal == null) return;
    final changes = <String>[
      for (var i = 0; i < 5; i++)
        if (committed.starters[i] != proposal.settings.starters[i])
          '${Position.values[i].shortName}: '
              '${careerPlayerName(career, committed.starters[i].value)} → '
              '${careerPlayerName(career, proposal.settings.starters[i].value)}',
      for (final key in committed.customTargets.keys)
        if (!proposal.settings.customTargets.containsKey(key) &&
            committed.preset == RotationPreset.custom)
          'Remove ${careerPlayerName(career, key)} '
              '(${formatMinutes(committed.customTargets[key]!)} planned)',
    ];
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('rotation-repair-dialog'),
        title: const Text('Repair Preview'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Proposed changes (not saved yet):'),
              for (final change in changes) Text('• $change'),
              if (proposal.isApplicable)
                const Text(
                  '\nThe repaired rotation is complete and valid.',
                  key: ValueKey('rotation-repair-complete'),
                )
              else ...[
                const Text(
                  '\nStill needs your attention (minutes are never moved '
                  'automatically):',
                  key: ValueKey('rotation-repair-incomplete'),
                ),
                for (final issue in proposal.remainingIssues)
                  Text('• ${describeRotationIssue(issue, career)}'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          if (proposal.isApplicable)
            FilledButton(
              key: const ValueKey('rotation-repair-apply'),
              onPressed: () => Navigator.pop(dialogContext, 'apply'),
              child: const Text('Apply Repair'),
            )
          else
            FilledButton(
              key: const ValueKey('rotation-repair-load'),
              onPressed: () => Navigator.pop(dialogContext, 'load'),
              child: const Text('Load into Editor'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'apply') {
      try {
        await _controller.applyUserRotationRepair();
        if (!mounted) return;
        setState(() {
          _loadDraftFromCommitted();
          _status = 'Repair applied and saved.';
          _statusIsError = false;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _status = 'Repair not saved: $error';
          _statusIsError = true;
        });
      }
    } else if (action == 'load') {
      setState(() {
        _loadDraftFrom(proposal.settings, team);
        _dirty = true;
        _view = RotationEditorView.playingTime;
        _status =
            'Repair loaded into the editor. Complete the minutes, then save.';
        _statusIsError = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final t = context.tokens;
      final career = _controller.career;
      final team = career == null ? null : _standardTeam(career);
      return PopScope(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _confirmDiscard() && context.mounted) {
            setState(() => _dirty = false);
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          key: const ValueKey('career-rotation-screen'),
          appBar: AppBar(title: const Text('Lineup & Rotation')),
          body: career == null
              ? const Center(child: CircularProgressIndicator())
              : team == null
              ? Padding(
                  padding: EdgeInsets.all(t.space400),
                  child: Text(
                    'Your roster needs at least five standard players before '
                    'a rotation can be set.',
                    style: TextStyle(color: t.textSecondary),
                  ),
                )
              : _body(context, t, career, team),
        ),
      );
    },
  );

  Widget _body(
    BuildContext context,
    HardwoodCommandTokens t,
    GmCareer career,
    Team team,
  ) {
    final settings = _draftSettings();
    final resolution = !_manual || settings == null
        ? null
        : CareerRotationService.resolve(settings, team, rules: _rules);
    final unassigned = _unassigned(team);
    final draftValid =
        !_manual ||
        (resolution != null && resolution.isValid && unassigned.isEmpty);
    final canSave = _dirty && !_busy && draftValid;
    final committedResolution = career.userRotation.isManual
        ? CareerRotationService.resolve(career.userRotation, team)
        : null;

    return Column(
      children: [
        Expanded(
          // At most ~15 roster rows: build eagerly so every control stays
          // addressable (tests, accessibility focus traversal).
          child: SingleChildScrollView(
            key: const ValueKey('rotation-scroll'),
            padding: EdgeInsets.all(t.space300),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (committedResolution != null && !committedResolution.isValid)
                  _committedIssuesCard(t, career, team, committedResolution),
                if (_busy && !_saving) _lockedBanner(t),
                _modeCard(t, team),
                SizedBox(height: t.space300),
                _viewSwitcher(t),
                SizedBox(height: t.space300),
                switch (_view) {
                  RotationEditorView.startingFive => _startingFive(t, team),
                  RotationEditorView.playingTime => _playingTime(
                    t,
                    team,
                    unassigned,
                  ),
                  RotationEditorView.depthChart => _depthChart(t, team),
                },
              ],
            ),
          ),
        ),
        _saveBar(t, resolution, unassigned, canSave, career),
      ],
    );
  }

  Widget _card(HardwoodCommandTokens t, {required Widget child, Key? key}) =>
      Container(
        key: key,
        padding: EdgeInsets.all(t.space300),
        decoration: BoxDecoration(
          color: t.bgSurface,
          borderRadius: BorderRadius.circular(t.radiusLg),
          border: Border.all(color: t.borderSubtle),
        ),
        child: child,
      );

  Widget _label(HardwoodCommandTokens t, String text) => Text(
    text,
    style: TextStyle(
      color: t.textSecondary,
      fontSize: 11.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
    ),
  );

  Widget _lockedBanner(HardwoodCommandTokens t) => Padding(
    padding: EdgeInsets.only(bottom: t.space300),
    child: Container(
      key: const ValueKey('rotation-locked'),
      padding: EdgeInsets.all(t.space300),
      decoration: BoxDecoration(
        color: t.statusWarningBg,
        borderRadius: BorderRadius.circular(t.radiusMd),
      ),
      child: Text(
        _controller.draftRecoveryRequired
            ? 'Rotation is locked until the saved career is reloaded.'
            : 'Simulation or save in progress — rotation editing is locked.',
        style: TextStyle(color: t.statusWarningFg, fontWeight: FontWeight.w700),
      ),
    ),
  );

  Widget _committedIssuesCard(
    HardwoodCommandTokens t,
    GmCareer career,
    Team team,
    CareerRotationResolution resolution,
  ) => Padding(
    padding: EdgeInsets.only(bottom: t.space300),
    child: Container(
      key: const ValueKey('rotation-issues'),
      padding: EdgeInsets.all(t.space300),
      decoration: BoxDecoration(
        color: t.statusDangerBg,
        borderRadius: BorderRadius.circular(t.radiusLg),
        border: Border.all(color: t.statusDanger),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SAVED ROTATION NEEDS ATTENTION',
            style: TextStyle(
              color: t.statusDangerFg,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: t.space200),
          for (final issue in resolution.issues)
            Padding(
              padding: EdgeInsets.only(bottom: t.space100),
              child: Text(
                '• ${describeRotationIssue(issue, career)}',
                style: TextStyle(color: t.textPrimary, fontSize: 13),
              ),
            ),
          Text(
            'Your saved preferences are kept until you save a valid '
            'replacement. The season cannot start until this is resolved.',
            style: TextStyle(color: t.textSecondary, fontSize: 12),
          ),
          SizedBox(height: t.space300),
          Wrap(
            spacing: t.space200,
            runSpacing: t.space200,
            children: [
              HardwoodSecondaryButton(
                key: const ValueKey('rotation-edit'),
                label: 'EDIT ROTATION',
                icon: Icons.edit_outlined,
                onPressed: _busy
                    ? null
                    : () => setState(
                        () => _view = RotationEditorView.startingFive,
                      ),
              ),
              HardwoodSecondaryButton(
                key: const ValueKey('rotation-preview-repair'),
                label: 'PREVIEW REPAIR',
                icon: Icons.build_outlined,
                onPressed: _busy ? null : () => _previewRepair(career, team),
              ),
              HardwoodSecondaryButton(
                key: const ValueKey('rotation-switch-auto'),
                label: 'SWITCH TO AUTO',
                icon: Icons.autorenew,
                onPressed: _busy ? null : _switchCommittedToAuto,
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _modeCard(HardwoodCommandTokens t, Team team) => _card(
    t,
    key: const ValueKey('rotation-mode-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(t, 'CONTROL MODE'),
        SizedBox(height: t.space200),
        Row(
          children: [
            Expanded(
              child: _toggle(
                t,
                key: const ValueKey('rotation-mode-auto'),
                label: 'AUTO',
                selected: !_manual,
                onTap: () => _setMode(false, team),
              ),
            ),
            SizedBox(width: t.space200),
            Expanded(
              child: _toggle(
                t,
                key: const ValueKey('rotation-mode-manual'),
                label: 'MANUAL',
                selected: _manual,
                onTap: () => _setMode(true, team),
              ),
            ),
          ],
        ),
        SizedBox(height: t.space200),
        Text(
          _manual
              ? 'You choose the starting five and playing-time targets. They '
                    'apply to every regular-season, Play-In and playoff game '
                    'simulated after you save.'
              : _autoDescription(team),
          key: const ValueKey('rotation-mode-description'),
          style: TextStyle(color: t.textSecondary, fontSize: 12.5),
        ),
        if (!_manual &&
            _controller.career?.userRotation.retainedManual != null) ...[
          SizedBox(height: t.space300),
          Container(
            key: const ValueKey('rotation-retained-manual'),
            padding: EdgeInsets.all(t.space300),
            decoration: BoxDecoration(
              color: t.bgElevated,
              borderRadius: BorderRadius.circular(t.radiusMd),
              border: Border.all(color: t.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Your previous manual plan is saved and is not used while '
                  'AUTO is active.',
                  style: TextStyle(color: t.textPrimary, fontSize: 12.5),
                ),
                SizedBox(height: t.space200),
                HardwoodSecondaryButton(
                  key: const ValueKey('rotation-restore-manual'),
                  label: 'RESTORE MANUAL PLAN',
                  icon: Icons.restore,
                  onPressed: _busy ? null : () => _restoreRetained(team),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  String _autoDescription(Team team) {
    final decision = _autoDecision(team);
    return switch (decision?.authority) {
      RotationAuthority.headCoach =>
        'AUTO delegates to Head Coach ${decision!.coach!.firstName} '
            '${decision.coach!.lastName} '
            '(${CareerUiLabels.coachPhilosophy(decision.coach!.philosophy!)}): '
            '${CareerUiLabels.coachPhilosophyEffect(decision.coach!.philosophy!)} '
            'AI teams use their own head coaches.',
      RotationAuthority.vacantFallback =>
        'No head coach — AUTO uses the default lineup (first standard player '
            'at each natural position) and the balanced nine-player rotation '
            'until you hire one.',
      RotationAuthority.coachPlanUnavailable =>
        'Coach plan unavailable for this roster — AUTO uses the default '
            'lineup and the balanced nine-player rotation.',
      _ =>
        'AUTO uses the default lineup (first standard player at each '
            'natural position, in roster order) and the balanced '
            'nine-player rotation — the same rules as every AI team.',
    };
  }

  /// Restores the retained manual plan. A plan that no longer fits the
  /// roster is never applied or discarded silently: it is loaded into the
  /// draft (with the M010 repair proposal when one applies) for review.
  Future<void> _restoreRetained(Team team) async {
    final career = _controller.career;
    final retained = career?.userRotation.retainedManual;
    if (career == null || retained == null || _busy) return;
    final resolution = CareerRotationService.resolve(retained, team);
    if (!resolution.isValid) {
      _loadRetainedRepairDraft(career, team, retained, resolution);
      return;
    }
    setState(() => _saving = true);
    try {
      await _controller.restoreRetainedManualRotation();
      if (!mounted) return;
      setState(() {
        _loadDraftFromCommitted();
        _status = 'Manual plan restored.';
        _statusIsError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Not restored: $error';
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _loadRetainedRepairDraft(
    GmCareer career,
    Team team,
    CareerRotationSettings retained,
    CareerRotationResolution resolution,
  ) {
    final proposal = CareerRotationService.proposeRepair(retained, team);
    final repaired = proposal != null && proposal.isApplicable;
    setState(() {
      _loadDraftFrom(repaired ? proposal.settings : retained, team);
      _dirty = true;
      _view = RotationEditorView.startingFive;
      _statusIsError = true;
      _status =
          'Your saved manual plan no longer fits the roster:\n'
          '${resolution.issues.map((i) => describeRotationIssue(i, career)).join('\n')}\n'
          '${repaired ? 'A repaired draft is loaded (not saved). Review it and save.' : 'It is loaded as a draft (not saved). Fix it and save.'}';
    });
  }

  Widget _toggle(
    HardwoodCommandTokens t, {
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => AppPressable(
    key: key,
    semanticLabel: label,
    enabled: !_busy,
    onPressed: _busy ? null : onTap,
    child: Container(
      constraints: BoxConstraints(minHeight: t.touchMin),
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: t.space200),
      decoration: BoxDecoration(
        color: selected ? t.accentPrimaryTint : t.bgElevated,
        borderRadius: BorderRadius.circular(t.radiusMd),
        border: Border.all(
          color: selected ? t.accentPrimary : t.borderSubtle,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: selected ? t.accentPrimary : t.textSecondary,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    ),
  );

  Widget _viewSwitcher(HardwoodCommandTokens t) {
    Widget tab(RotationEditorView view, String label, String key) => Expanded(
      child: AppPressable(
        key: ValueKey(key),
        semanticLabel: label,
        onPressed: () => setState(() => _view = view),
        child: Container(
          constraints: BoxConstraints(minHeight: t.touchMin),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: t.space100),
          decoration: BoxDecoration(
            color: _view == view ? t.accentSecondaryBg : t.bgSurface,
            borderRadius: BorderRadius.circular(t.radiusMd),
            border: Border.all(
              color: _view == view ? t.accentSecondary : t.borderSubtle,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _view == view ? t.accentSecondaryFg : t.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
    return Row(
      children: [
        tab(
          RotationEditorView.startingFive,
          'STARTING FIVE',
          'rotation-view-starting-five',
        ),
        SizedBox(width: t.space200),
        tab(
          RotationEditorView.playingTime,
          'PLAYING TIME',
          'rotation-view-playing-time',
        ),
        SizedBox(width: t.space200),
        tab(
          RotationEditorView.depthChart,
          'DEPTH CHART',
          'rotation-view-depth',
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ A. Five

  Widget _startingFive(HardwoodCommandTokens t, Team team) {
    final byId = {for (final p in team.players) p.id.value: p};
    final starters = _manual ? _starters : _autoStarters(team);
    return _card(
      t,
      key: const ValueKey('rotation-starting-five'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(t, 'STARTING FIVE'),
          SizedBox(height: t.space100),
          Text(
            _manual
                ? 'Tap a position to choose a standard-roster player. Choosing '
                      'a current starter swaps the two players.'
                : 'AUTO preview — the lineup AUTO will use. Switch to MANUAL '
                      'to choose your starters.',
            style: TextStyle(color: t.textSecondary, fontSize: 12.5),
          ),
          SizedBox(height: t.space300),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final useList = constraints.maxWidth < 300 || scale > 1.3;
              if (useList) {
                return Column(
                  key: const ValueKey('rotation-five-list'),
                  children: [
                    for (var i = 0; i < 5; i++)
                      Padding(
                        padding: EdgeInsets.only(bottom: t.space200),
                        child: _slotToken(
                          t,
                          i,
                          i < starters.length ? byId[starters[i]] : null,
                          i < starters.length ? starters[i] : null,
                          team,
                          wide: true,
                        ),
                      ),
                  ],
                );
              }
              return _courtLayout(
                t,
                constraints.maxWidth,
                starters,
                byId,
                team,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _courtLayout(
    HardwoodCommandTokens t,
    double width,
    List<String> starters,
    Map<String, Player> byId,
    Team team,
  ) {
    final height = width * 1.25;
    const tokenWidth = 104.0;
    // Relative anchors on an original half court (hoop at the top). Wing and
    // point tokens tile the width without overlap down to 300 dp.
    const anchors = <Offset>[
      Offset(0.5, 0.84), // PG
      Offset(0.15, 0.6), // SG
      Offset(0.85, 0.6), // SF
      Offset(0.27, 0.24), // PF
      Offset(0.73, 0.24), // C
    ];
    return SizedBox(
      key: const ValueKey('rotation-five-court'),
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _HalfCourtPainter(
                lineColor: t.borderSubtle,
                paintColor: t.bgElevated,
                rimColor: t.accentPrimary,
              ),
            ),
          ),
          for (var i = 0; i < 5; i++)
            Positioned(
              left: (anchors[i].dx * width - tokenWidth / 2).clamp(
                0,
                width - tokenWidth,
              ),
              top: (anchors[i].dy * height - 52).clamp(0, height - 116),
              width: tokenWidth,
              child: _slotToken(
                t,
                i,
                i < starters.length ? byId[starters[i]] : null,
                i < starters.length ? starters[i] : null,
                team,
              ),
            ),
        ],
      ),
    );
  }

  Widget _slotToken(
    HardwoodCommandTokens t,
    int index,
    Player? player,
    String? playerId,
    Team team, {
    bool wide = false,
  }) {
    final slot = Position.values[index];
    final outOfPosition = player != null && player.position != slot;
    final missing = player == null;
    final border = missing
        ? t.statusDanger
        : outOfPosition
        ? t.statusWarning
        : t.accentPrimary;
    final info = <Widget>[
      Text(
        missing
            ? (playerId == null ? 'Empty' : 'Unavailable')
            : player.fullName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: wide ? TextAlign.start : TextAlign.center,
        style: TextStyle(
          color: missing ? t.statusDangerFg : t.textPrimary,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (player != null)
        Text(
          'Natural ${player.position.shortName} · OVR '
          '${player.attributes.overallRating}',
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: TextStyle(color: t.textSecondary, fontSize: 11),
        ),
      if (outOfPosition)
        Text(
          'Out of position',
          key: ValueKey('rotation-oop-${slot.shortName}'),
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: TextStyle(
            color: t.statusWarningFg,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
    ];
    final slotBadge = Container(
      padding: EdgeInsets.symmetric(horizontal: t.space200, vertical: 2),
      decoration: BoxDecoration(
        color: t.accentPrimaryTint,
        borderRadius: BorderRadius.circular(t.radiusPill),
      ),
      child: Text(
        slot.shortName,
        style: TextStyle(
          color: t.accentPrimary,
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    return AppPressable(
      key: ValueKey('rotation-slot-${slot.shortName}'),
      semanticLabel:
          '${slot.fullName}: ${player?.fullName ?? 'no player'}'
          '${outOfPosition ? ', out of position' : ''}',
      enabled: _manual && !_busy,
      onPressed: _manual && !_busy ? () => _pickStarter(index, team) : null,
      borderRadius: BorderRadius.circular(t.radiusMd),
      child: Container(
        padding: EdgeInsets.all(t.space200),
        decoration: BoxDecoration(
          color: t.bgSurface,
          borderRadius: BorderRadius.circular(t.radiusMd),
          border: Border.all(color: border, width: 1.5),
        ),
        child: wide
            ? Row(
                children: [
                  slotBadge,
                  SizedBox(width: t.space300),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: info,
                    ),
                  ),
                  if (_manual) Icon(Icons.swap_horiz, color: t.textSecondary),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  slotBadge,
                  SizedBox(height: t.space100),
                  ...info,
                ],
              ),
      ),
    );
  }

  Future<void> _pickStarter(int slotIndex, Team team) async {
    final slot = Position.values[slotIndex];
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.tokens.bgElevated,
      builder: (sheetContext) {
        final t = sheetContext.tokens;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
            ),
            child: SingleChildScrollView(
              key: const ValueKey('rotation-picker'),
              padding: EdgeInsets.all(t.space300),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Choose ${slot.fullName} (${slot.shortName})',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Standard-roster players only. Players at another natural '
                    'position may start here; there is no positional penalty.',
                    style: TextStyle(color: t.textSecondary, fontSize: 12),
                  ),
                  SizedBox(height: t.space200),
                  for (final player in team.players)
                    _pickerRow(t, sheetContext, player, slotIndex),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (picked != null) _assignStarter(slotIndex, picked);
  }

  Widget _pickerRow(
    HardwoodCommandTokens t,
    BuildContext sheetContext,
    Player player,
    int slotIndex,
  ) {
    final slot = Position.values[slotIndex];
    final currentIndex = _starters.indexOf(player.id.value);
    final status = currentIndex == slotIndex
        ? 'Current ${slot.shortName}'
        : currentIndex >= 0
        ? 'Starting ${Position.values[currentIndex].shortName} · will swap'
        : 'Bench';
    return Padding(
      padding: EdgeInsets.only(bottom: t.space100),
      child: AppPressable(
        key: ValueKey('rotation-pick-${player.id.value}'),
        semanticLabel: '${player.fullName}, $status',
        onPressed: () => Navigator.pop(sheetContext, player.id.value),
        child: Container(
          padding: EdgeInsets.all(t.space200),
          decoration: BoxDecoration(
            color: currentIndex == slotIndex
                ? t.accentPrimaryTint
                : t.bgSurface,
            borderRadius: BorderRadius.circular(t.radiusMd),
            border: Border.all(color: t.borderSubtle),
          ),
          child: Row(
            children: [
              PlayerMonogramBadge(fullName: player.fullName, size: 34),
              SizedBox(width: t.space200),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.fullName,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${player.position.shortName} · $status'
                      '${player.position != slot ? ' · out of position at ${slot.shortName}' : ''}',
                      style: TextStyle(color: t.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              OverallRatingBadge(
                overall: player.attributes.overallRating,
                compact: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- B. Playing time

  Widget _playingTime(
    HardwoodCommandTokens t,
    Team team,
    List<String> unassigned,
  ) {
    final targets = _draftTargets(team);
    final total = RotationBudget.total(targets);
    final remaining = _teamTotal - total;
    final starters = _manual ? _starters : _autoStarters(team);
    final ordered = <Player>[
      for (final id in starters) ...team.players.where((p) => p.id.value == id),
      for (final p in team.players)
        if (!starters.contains(p.id.value)) p,
    ];
    final custom = _manual && _preset == RotationPreset.custom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          t,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label(t, 'PLAYING-TIME PRESET'),
              SizedBox(height: t.space200),
              Row(
                children: [
                  for (final (preset, label) in const [
                    (RotationPreset.balanced, 'BALANCED'),
                    (RotationPreset.starterHeavy, 'STARTER-HEAVY'),
                    (RotationPreset.custom, 'CUSTOM'),
                  ]) ...[
                    Expanded(
                      child: _toggle(
                        t,
                        key: ValueKey('rotation-preset-${preset.jsonValue}'),
                        label: label,
                        selected:
                            (_manual
                                ? _preset
                                : _autoDecision(team)?.plan.preset ??
                                      RotationPreset.balanced) ==
                            preset,
                        onTap: () {
                          if (!_manual) _setMode(true, team);
                          _selectPreset(preset, team);
                        },
                      ),
                    ),
                    if (preset != RotationPreset.custom)
                      SizedBox(width: t.space200),
                  ],
                ],
              ),
              SizedBox(height: t.space300),
              _budgetPanel(t, total, remaining),
              SizedBox(height: t.space200),
              Text(
                'Targets guide substitutions; actual minutes vary with fouls, '
                'foul-outs, overtime and game flow.',
                key: const ValueKey('rotation-target-note'),
                style: TextStyle(color: t.textMuted, fontSize: 11.5),
              ),
            ],
          ),
        ),
        SizedBox(height: t.space300),
        if (unassigned.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: t.space300),
            child: Container(
              key: const ValueKey('rotation-unassigned'),
              padding: EdgeInsets.all(t.space300),
              decoration: BoxDecoration(
                color: t.statusWarningBg,
                borderRadius: BorderRadius.circular(t.radiusMd),
              ),
              child: Text(
                '${unassigned.length} new player(s) have no planned minutes. '
                'Assign minutes or confirm 0:00 for each before saving.',
                style: TextStyle(
                  color: t.statusWarningFg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        for (final player in ordered)
          _targetRow(
            t,
            player,
            targets,
            starter: starters.contains(player.id.value),
            editable: custom,
            unassigned: unassigned.contains(player.id.value),
          ),
      ],
    );
  }

  Widget _budgetPanel(HardwoodCommandTokens t, int total, int remaining) {
    final over = remaining < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: t.space300,
          runSpacing: t.space100,
          children: [
            Text(
              'Allocated ${formatMinutes(total)} / ${formatMinutes(_teamTotal)}',
              key: const ValueKey('rotation-budget-allocated'),
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Remaining ${formatMinutes(remaining < 0 ? 0 : remaining)}',
              key: const ValueKey('rotation-budget-remaining'),
              style: TextStyle(
                color: remaining == 0
                    ? t.statusSuccessFg
                    : over
                    ? t.statusDangerFg
                    : t.statusWarningFg,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '$total / $_teamTotal player-seconds',
              key: const ValueKey('rotation-budget-seconds'),
              style: TextStyle(color: t.textMuted, fontSize: 11.5),
            ),
          ],
        ),
        SizedBox(height: t.space200),
        ClipRRect(
          borderRadius: BorderRadius.circular(t.radiusPill),
          child: LinearProgressIndicator(
            value: (total / _teamTotal).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: t.bgElevated,
            color: remaining == 0 ? t.statusSuccess : t.accentPrimary,
          ),
        ),
      ],
    );
  }

  Widget _targetRow(
    HardwoodCommandTokens t,
    Player player,
    Map<String, int> targets, {
    required bool starter,
    required bool editable,
    required bool unassigned,
  }) {
    final id = player.id.value;
    final seconds = targets[id] ?? 0;
    final allowed = RotationBudget.maximumAllowed(
      _customTargets,
      id,
      cap: _cap,
      teamTotal: _teamTotal,
    );
    final enabled = editable && !_busy;
    Widget fine(String key, String label, int delta, bool on) => AppPressable(
      key: ValueKey(key),
      semanticLabel: '$label ${player.fullName}',
      minWidth: 44,
      minHeight: 40,
      enabled: enabled && on,
      onPressed: enabled && on ? () => _setTarget(id, seconds + delta) : null,
      child: Container(
        width: 48,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.bgElevated,
          borderRadius: BorderRadius.circular(t.radiusSm),
          border: Border.all(color: t.borderSubtle),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: t.accentSecondaryFg,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: t.space200),
      child: Container(
        key: ValueKey('rotation-target-row-$id'),
        padding: EdgeInsets.all(t.space200),
        decoration: BoxDecoration(
          color: t.bgSurface,
          borderRadius: BorderRadius.circular(t.radiusMd),
          border: Border.all(
            color: unassigned ? t.statusWarning : t.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    player.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(width: t.space100),
                Text(
                  unassigned
                      ? 'NEW · UNASSIGNED'
                      : '${player.position.shortName} · '
                            '${starter ? 'STARTER' : 'RESERVE'}',
                  key: ValueKey('rotation-role-$id'),
                  style: TextStyle(
                    color: unassigned ? t.statusWarningFg : t.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(width: t.space200),
                Text(
                  unassigned ? '--:--' : formatMinutes(seconds),
                  key: ValueKey('rotation-seconds-$id'),
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            if (editable) ...[
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      key: ValueKey('rotation-slider-$id'),
                      // Fixed 0–48:00 scale for every player (M005).
                      value: seconds.clamp(0, _cap).toDouble(),
                      min: 0,
                      max: _cap.toDouble(),
                      divisions: _cap,
                      label: formatMinutes(seconds),
                      onChanged: enabled
                          ? (value) =>
                                _setTarget(id, value.round(), clamp: true)
                          : null,
                    ),
                  ),
                  fine(
                    'rotation-fine-minus-$id',
                    '-10s',
                    -RotationBudget.fineStepSeconds,
                    seconds > 0,
                  ),
                  SizedBox(width: t.space100),
                  fine(
                    'rotation-fine-plus-$id',
                    '+10s',
                    RotationBudget.fineStepSeconds,
                    seconds + RotationBudget.fineStepSeconds <= allowed,
                  ),
                ],
              ),
              if (unassigned)
                Align(
                  alignment: Alignment.centerLeft,
                  child: HardwoodSecondaryButton(
                    key: ValueKey('rotation-ack-zero-$id'),
                    label: 'CONFIRM 0:00 FOR THIS PLAYER',
                    onPressed: enabled ? () => _setTarget(id, 0) : null,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ C. Depth chart

  Widget _depthChart(HardwoodCommandTokens t, Team team) {
    final targets = _draftTargets(team);
    final starters = _manual ? _starters : _autoStarters(team);
    final byId = {for (final p in team.players) p.id.value: p};
    final rosterIndex = {
      for (var i = 0; i < team.players.length; i++) team.players[i].id.value: i,
    };
    return _card(
      t,
      key: const ValueKey('rotation-depth-chart'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(t, 'DEPTH CHART · PREVIEW'),
          SizedBox(height: t.space100),
          Text(
            'A read-only preview built from your starters and minute targets. '
            'Reserve order here does not control substitutions: the simulator '
            'uses starters, targets and roster order.',
            key: const ValueKey('rotation-depth-disclaimer'),
            style: TextStyle(color: t.textSecondary, fontSize: 12),
          ),
          for (var i = 0; i < Position.values.length; i++)
            _depthGroup(
              t,
              Position.values[i],
              starter: i < starters.length ? byId[starters[i]] : null,
              reserves:
                  [
                    for (final p in team.players)
                      if (!starters.contains(p.id.value) &&
                          p.position == Position.values[i])
                        p,
                  ]..sort((a, b) {
                    final byTarget = (targets[b.id.value] ?? 0).compareTo(
                      targets[a.id.value] ?? 0,
                    );
                    return byTarget != 0
                        ? byTarget
                        : rosterIndex[a.id.value]!.compareTo(
                            rosterIndex[b.id.value]!,
                          );
                  }),
              targets: targets,
            ),
        ],
      ),
    );
  }

  Widget _depthGroup(
    HardwoodCommandTokens t,
    Position position, {
    required Player? starter,
    required List<Player> reserves,
    required Map<String, int> targets,
  }) {
    Widget row(Player p, bool isStarter) => Padding(
      padding: EdgeInsets.only(top: t.space100),
      child: Row(
        key: ValueKey('rotation-depth-row-${p.id.value}'),
        children: [
          Container(
            width: 74,
            padding: const EdgeInsets.symmetric(vertical: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isStarter ? t.accentPrimaryTint : t.bgElevated,
              borderRadius: BorderRadius.circular(t.radiusPill),
            ),
            child: Text(
              isStarter ? 'STARTER' : 'RESERVE',
              style: TextStyle(
                color: isStarter ? t.accentPrimary : t.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(width: t.space200),
          Expanded(
            child: Text(
              '${p.fullName} (${p.position.shortName})',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.textPrimary, fontSize: 13),
            ),
          ),
          Text(
            'OVR ${p.attributes.overallRating}',
            style: TextStyle(color: t.textSecondary, fontSize: 12),
          ),
          SizedBox(width: t.space200),
          Text(
            targets.containsKey(p.id.value)
                ? formatMinutes(targets[p.id.value]!)
                : '--:--',
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    return Padding(
      key: ValueKey('rotation-depth-${position.shortName}'),
      padding: EdgeInsets.only(top: t.space300),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            position.fullName.toUpperCase(),
            style: TextStyle(
              color: t.accentSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          if (starter != null) row(starter, true),
          for (final p in reserves) row(p, false),
          if (starter == null && reserves.isEmpty)
            Text(
              'No standard player',
              style: TextStyle(color: t.textMuted, fontSize: 12),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- Save bar

  Widget _saveBar(
    HardwoodCommandTokens t,
    CareerRotationResolution? resolution,
    List<String> unassigned,
    bool canSave,
    GmCareer career,
  ) {
    final problems = <String>[
      if (resolution != null)
        for (final issue in resolution.issues)
          describeRotationIssue(issue, career),
      if (unassigned.isNotEmpty)
        '${unassigned.length} new player(s) still need minutes or a confirmed 0:00.',
    ];
    final message =
        _status ??
        (problems.isNotEmpty
            ? problems.join('\n')
            : _dirty
            ? 'Unsaved changes.'
            : _manual
            ? 'MANUAL rotation saved.'
            : 'AUTO rotation active.');
    final isError = _status != null ? _statusIsError : problems.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: t.bgGlassHeader,
        border: Border(top: BorderSide(color: t.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.all(t.space300),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 72),
                child: SingleChildScrollView(
                  child: Text(
                    message,
                    key: const ValueKey('rotation-status'),
                    style: TextStyle(
                      color: isError ? t.statusDangerFg : t.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
              if (_controller.draftRecoveryRequired) ...[
                SizedBox(height: t.space200),
                HardwoodSecondaryButton(
                  key: const ValueKey('rotation-reload'),
                  label: 'RELOAD SAVED CAREER',
                  icon: Icons.refresh,
                  onPressed: _controller.isLoading ? null : _reloadAfterFailure,
                ),
              ],
              SizedBox(height: t.space200),
              HardwoodPrimaryCta(
                key: const ValueKey('rotation-save'),
                label: _manual ? 'Save Manual Rotation' : 'Save AUTO Rotation',
                icon: Icons.save_outlined,
                isBusy: _saving,
                onPressed: canSave ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Original procedural half-court markings (hoop at the top).
class _HalfCourtPainter extends CustomPainter {
  const _HalfCourtPainter({
    required this.lineColor,
    required this.paintColor,
    required this.rimColor,
  });

  final Color lineColor;
  final Color paintColor;
  final Color rimColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final line = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final fill = Paint()..color = paintColor;
    final court = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );
    canvas.drawRRect(
      court,
      Paint()..color = paintColor.withValues(alpha: 0.35),
    );
    canvas.drawRRect(court, line);
    final keyRect = Rect.fromLTWH(w * 0.34, 0, w * 0.32, h * 0.44);
    canvas.drawRect(keyRect, fill);
    canvas.drawRect(keyRect, line);
    canvas.drawCircle(Offset(w / 2, h * 0.44), w * 0.12, line);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w / 2, h * 0.08), radius: w * 0.44),
      0.15,
      2.84,
      false,
      line,
    );
    canvas.drawCircle(
      Offset(w / 2, h * 0.07),
      w * 0.03,
      Paint()
        ..color = rimColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawLine(
      Offset(w * 0.44, h * 0.035),
      Offset(w * 0.56, h * 0.035),
      line,
    );
  }

  @override
  bool shouldRepaint(_HalfCourtPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor ||
      oldDelegate.paintColor != paintColor ||
      oldDelegate.rimColor != rimColor;
}
