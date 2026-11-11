import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'career_controller.dart';
import 'rookie_signing_status.dart';

/// Player-facing rookie signing surface for the human franchise.
///
/// Lists only the user's drafted prospects, distinguishes unsigned rights from
/// signed contracts, and routes every signing through [GmCareerController].
class GmRookieSigningScreen extends StatelessWidget {
  const GmRookieSigningScreen({super.key, required this.controller});

  final GmCareerController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final career = controller.career;
      if (career == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Rookie Signing')),
          body: const Center(child: Text('No active GM Career.')),
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Rookie Signing')),
        body: _buildBody(context, career),
      );
    },
  );

  Widget _buildBody(BuildContext context, GmCareer career) {
    final theme = Theme.of(context);
    final draft = career.draftExecutionState;
    if (!draft.isCompleted) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Complete the rookie draft before signing drafted prospects.',
        ),
      );
    }
    final roster = career.userTeam.roster;
    final selections =
        draft.selections
            .where(
              (selection) =>
                  selection.selectingTeamId == career.userFranchiseId,
            )
            .toList()
          ..sort((a, b) => a.overallPick.compareTo(b.overallPick));
    final signedCount = selections
        .where((s) => isSignedRookie(career, s.prospectId))
        .length;
    final unsignedCount = selections.length - signedCount;
    final blocked = controller.isLoading || controller.draftRecoveryRequired;

    return ListView(
      key: const ValueKey('rookie-signing-scroll'),
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          key: const ValueKey('rookie-signing-summary'),
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Drafted Prospects',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${selections.length} drafted • $signedCount signed • '
                  '$unsignedCount unsigned',
                ),
                const SizedBox(height: 8),
                Text(
                  'Standard: ${roster.standardCount}/${RosterRules.maxOffseasonStandard} • '
                  'Two-way: ${roster.twoWayCount}/${RosterRules.maxOffseasonTwoWay} • '
                  'Total: ${roster.totalContractedCount}/${RosterRules.maxOffseasonTotal}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (controller.draftRecoveryRequired) ...[
          const SizedBox(height: 12),
          _RecoveryCard(
            controller: controller,
            message:
                controller.errorMessage ??
                'A save failed unexpectedly. Reload the saved career before '
                    'signing anyone else.',
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Unsigned draft rights occupy no roster slots. '
          'Financial terms are not modeled in this build.',
        ),
        const SizedBox(height: 8),
        if (selections.isEmpty)
          const Text('This franchise has no drafted prospects.')
        else
          for (final selection in selections)
            _RookieRightCard(
              career: career,
              selection: selection,
              onSign: blocked
                  ? null
                  : () => _openSigningSheet(context, career, selection),
            ),
      ],
    );
  }

  Future<void> _openSigningSheet(
    BuildContext context,
    GmCareer career,
    DraftSelection selection,
  ) async {
    final prospect = career.draftClass.byId(selection.prospectId);
    if (prospect == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _RookieSigningSheet(
        controller: controller,
        expectedCareer: career,
        selection: selection,
        prospect: prospect.toPublicView(),
      ),
    );
  }
}

class _RookieRightCard extends StatelessWidget {
  const _RookieRightCard({
    required this.career,
    required this.selection,
    required this.onSign,
  });

  final GmCareer career;
  final DraftSelection selection;
  final VoidCallback? onSign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prospect = career.draftClass.byId(selection.prospectId);
    if (prospect == null) {
      return const SizedBox.shrink();
    }
    final public = prospect.toPublicView();
    final signed = isSignedRookie(career, prospect.id);
    return Card(
      key: ValueKey('rookie-right-${selection.overallPick}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    public.fullName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusPill(
                  key: ValueKey('rookie-status-${selection.overallPick}'),
                  label: rookieSigningStatus(career, prospect.id),
                  signed: signed,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${public.position.shortName} • Age ${public.age} • '
              'OVR ${public.overallRating}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              'Round ${selection.round} • Pick #${selection.overallPick} • '
              'Projected #${public.projectedRank}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              'Est. POT: ${public.estimatedPotentialGrade} '
              '(${public.estimatedPotentialRange})',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (!signed) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  key: ValueKey('rookie-sign-button-${selection.overallPick}'),
                  onPressed: onSign,
                  child: const Text('Sign'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({super.key, required this.label, required this.signed});

  final String label;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = signed
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({required this.controller, required this.message});

  final GmCareerController controller;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      key: const ValueKey('rookie-signing-recovery'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('rookie-signing-reload'),
              onPressed: controller.isLoading
                  ? null
                  : () => controller.loadCareer(),
              child: const Text('Reload Saved Career'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RookieSigningSheet extends StatefulWidget {
  const _RookieSigningSheet({
    required this.controller,
    required this.expectedCareer,
    required this.selection,
    required this.prospect,
  });

  final GmCareerController controller;
  final GmCareer expectedCareer;
  final DraftSelection selection;
  final PublicProspectScoutingView prospect;

  @override
  State<_RookieSigningSheet> createState() => _RookieSigningSheetState();
}

class _RookieSigningSheetState extends State<_RookieSigningSheet> {
  RosterCategory _category = RosterCategory.standard;
  int _duration = RookieContract.maxStandardDurationYears;
  bool _pending = false;
  String? _error;

  GmCareer? get _career => widget.controller.career;

  bool get _stale => !identical(_career, widget.expectedCareer);

  bool get _totalFull =>
      _career!.userTeam.roster.totalContractedCount >=
      RosterRules.maxOffseasonTotal;

  bool get _needsReload =>
      widget.controller.draftRecoveryRequired ||
      widget.controller.errorMessage != null;

  bool _categoryAvailable(RosterCategory category) {
    final roster = _career!.userTeam.roster;
    if (_totalFull) return false;
    return switch (category) {
      RosterCategory.standard =>
        roster.standardCount < RosterRules.maxOffseasonStandard,
      RosterCategory.twoWay =>
        roster.twoWayCount < RosterRules.maxOffseasonTwoWay,
      RosterCategory.trainingCamp => false,
    };
  }

  String? _unavailableReason(RosterCategory category) {
    if (_totalFull) {
      return 'Offseason roster limit reached '
          '(${_career!.userTeam.roster.totalContractedCount}'
          '/${RosterRules.maxOffseasonTotal}).';
    }
    final roster = _career!.userTeam.roster;
    return switch (category) {
      RosterCategory.standard =>
        roster.standardCount >= RosterRules.maxOffseasonStandard
            ? 'Standard roster is full '
                  '(${roster.standardCount}/${RosterRules.maxOffseasonStandard}).'
            : null,
      RosterCategory.twoWay =>
        roster.twoWayCount >= RosterRules.maxOffseasonTwoWay
            ? 'Two-way slots are full '
                  '(${roster.twoWayCount}/${RosterRules.maxOffseasonTwoWay}).'
            : null,
      RosterCategory.trainingCamp => 'Training-camp contracts are not offered.',
    };
  }

  int get _maxDuration => RookieContract.maxDurationFor(_category);

  bool get _blocked =>
      _pending ||
      _stale ||
      widget.controller.isLoading ||
      widget.controller.draftRecoveryRequired ||
      widget.controller.errorMessage != null;

  bool get _canConfirm => !_blocked && _categoryAvailable(_category);

  void _selectCategory(RosterCategory category) {
    setState(() {
      _category = category;
      if (_duration > RookieContract.maxDurationFor(category)) {
        _duration = RookieContract.maxDurationFor(category);
      }
    });
  }

  Future<void> _confirm() async {
    if (!_canConfirm) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      await widget.controller.signDraftedRookie(
        prospectId: widget.prospect.id,
        category: _category,
        durationYears: _duration,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pending = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _reload() async {
    await widget.controller.loadCareer();
    if (!mounted) return;
    // The sheet snapshot is now stale; return to the list rebuilt from disk.
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final career = _career;
    if (career == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No active GM Career.'),
      );
    }
    final roster = career.userTeam.roster;
    final standardAvailable = _categoryAvailable(RosterCategory.standard);
    final twoWayAvailable = _categoryAvailable(RosterCategory.twoWay);
    final categoryAvailable = _categoryAvailable(_category);
    final themedError = categoryAvailable
        ? null
        : _unavailableReason(_category);
    return Padding(
      key: const ValueKey('rookie-signing-sheet'),
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sign ${widget.prospect.fullName}',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${career.userTeam.name} (${career.userTeam.abbreviation}) • '
              'Round ${widget.selection.round} • '
              'Pick #${widget.selection.overallPick}',
            ),
            const SizedBox(height: 16),
            Text('Contract category', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const ValueKey('sign-category-standard'),
                  label: const Text('Standard'),
                  selected: _category == RosterCategory.standard,
                  onSelected: standardAvailable && !_pending
                      ? (_) => _selectCategory(RosterCategory.standard)
                      : null,
                ),
                ChoiceChip(
                  key: const ValueKey('sign-category-two-way'),
                  label: const Text('Two-Way'),
                  selected: _category == RosterCategory.twoWay,
                  onSelected: twoWayAvailable && !_pending
                      ? (_) => _selectCategory(RosterCategory.twoWay)
                      : null,
                ),
              ],
            ),
            if (_unavailableReason(RosterCategory.standard) != null &&
                !standardAvailable)
              _Note(
                key: const ValueKey('sign-standard-unavailable'),
                text: _unavailableReason(RosterCategory.standard)!,
                error: true,
              ),
            if (!twoWayAvailable)
              _Note(
                key: const ValueKey('sign-two-way-unavailable'),
                text: _unavailableReason(RosterCategory.twoWay)!,
                error: true,
              ),
            const SizedBox(height: 16),
            Text('Contract duration', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (
                  var years = RookieContract.minDurationYears;
                  years <= _maxDuration;
                  years++
                )
                  ChoiceChip(
                    key: ValueKey('sign-duration-$years'),
                    label: Text('$years ${years == 1 ? 'year' : 'years'}'),
                    selected: _duration == years,
                    onSelected: _pending
                        ? null
                        : (_) => setState(() => _duration = years),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Roster capacity', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              'Standard: ${roster.standardCount}/'
              '${RosterRules.maxOffseasonStandard} • '
              'Two-way: ${roster.twoWayCount}/'
              '${RosterRules.maxOffseasonTwoWay}',
              key: const ValueKey('signing-capacity-current'),
            ),
            Text(
              categoryAvailable
                  ? 'After signing: Standard '
                        '${roster.standardCount + (_category == RosterCategory.standard ? 1 : 0)}/'
                        '${RosterRules.maxOffseasonStandard} • Two-way '
                        '${roster.twoWayCount + (_category == RosterCategory.twoWay ? 1 : 0)}/'
                        '${RosterRules.maxOffseasonTwoWay} • Total '
                        '${roster.totalContractedCount + 1}/'
                        '${RosterRules.maxOffseasonTotal}'
                  : (themedError ?? 'This signing exceeds roster limits.'),
              key: const ValueKey('signing-capacity-preview'),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: categoryAvailable
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            _Note(
              text:
                  'No salary, cap or negotiation model exists yet. '
                  'Category and duration are roster terms only.',
            ),
            if (_stale)
              _Note(
                key: const ValueKey('signing-stale'),
                text:
                    'Career state changed. Close this sheet and reopen the signing flow.',
                error: true,
              ),
            if (_needsReload)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton(
                  key: const ValueKey('signing-reload'),
                  onPressed: widget.controller.isLoading ? null : _reload,
                  child: const Text('Reload Saved Career'),
                ),
              ),
            if (_error != null)
              _Note(
                key: const ValueKey('signing-error'),
                text: _error!,
                error: true,
              ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  key: const ValueKey('cancel-signing'),
                  onPressed: _pending
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const ValueKey('confirm-signing'),
                  onPressed: _canConfirm ? _confirm : null,
                  child: const Text('Confirm Signing'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: error
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
