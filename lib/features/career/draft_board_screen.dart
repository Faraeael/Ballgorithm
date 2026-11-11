import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'career_controller.dart';
import 'rookie_signing_status.dart';

/// Live draft commands and public scouting, backed only by committed career state.
class GmDraftBoardScreen extends StatefulWidget {
  const GmDraftBoardScreen({super.key, required this.controller});

  final GmCareerController controller;

  @override
  State<GmDraftBoardScreen> createState() => _GmDraftBoardScreenState();
}

class _GmDraftBoardScreenState extends State<GmDraftBoardScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _commandPending = ValueNotifier<bool>(false);
  late final _tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex:
        widget.controller.career?.draftExecutionState.isCompleted == true
        ? 2
        : 0,
  );
  final _orderScroll = ScrollController();
  Position? _selectedPosition;
  int _selectedRoundFilter = 0;
  String _availabilityFilter = 'All';
  String _searchQuery = '';
  String? _localError;

  bool get _blocked =>
      _commandPending.value ||
      widget.controller.isLoading ||
      widget.controller.draftRecoveryRequired ||
      widget.controller.errorMessage != null;

  @override
  void dispose() {
    _searchController.dispose();
    _commandPending.dispose();
    _tabs.dispose();
    _orderScroll.dispose();
    super.dispose();
  }

  Team _findTeam(GmCareer career, TeamId id) =>
      career.league.teams.firstWhere((team) => team.id == id);

  bool _isHumanTurn(GmCareer career) => career.draftExecutionState.isHumanTurn(
    order: career.draftOrder,
    userTeamId: career.userFranchiseId,
  );

  bool _canDraft(PlayerId id) {
    final career = widget.controller.career;
    return career != null &&
        !_blocked &&
        _isHumanTurn(career) &&
        !career.draftExecutionState.isProspectSelected(id);
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(() => _localError = error.toString());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 120),
          child: SingleChildScrollView(child: Text(error.toString())),
        ),
      ),
    );
  }

  // Revalidate the exact committed career and immutable pick IDs after a dialog.
  bool _confirmationIsCurrent(
    GmCareerController controller,
    GmCareer expected,
  ) {
    final current = controller.career;
    return identical(controller, widget.controller) &&
        identical(current, expected) &&
        current?.id == expected.id &&
        current?.currentYear == expected.currentYear &&
        current?.userFranchiseId == expected.userFranchiseId &&
        current?.draftExecutionState.currentOverallPick ==
            expected.draftExecutionState.currentOverallPick &&
        !controller.isLoading &&
        !controller.draftRecoveryRequired &&
        controller.errorMessage == null;
  }

  Future<bool> _confirm({
    required String title,
    required Widget content,
    required String confirmLabel,
    required String confirmKey,
    required String cancelKey,
  }) async {
    var closed = false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            void close(bool confirmed) {
              if (closed) return;
              closed = true;
              Navigator.pop(dialogContext, confirmed);
            }

            return AlertDialog(
              scrollable: true,
              title: Text(title),
              content: content,
              actions: [
                TextButton(
                  key: ValueKey(cancelKey),
                  onPressed: () => close(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: ValueKey(confirmKey),
                  onPressed: () => close(true),
                  child: Text(confirmLabel),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _startDraft() async {
    final controller = widget.controller;
    final career = controller.career;
    if (_blocked ||
        career == null ||
        !career.draftExecutionState.isNotStarted) {
      return;
    }
    _commandPending.value = true;
    try {
      final confirmed = await _confirm(
        title: 'Start Rookie Draft?',
        content: Text(
          '${career.userTeam.name} (${career.userTeam.abbreviation})\n'
          '${_ownedPicks(career)}\n\n'
          '90 available prospects • 60 selections across two rounds.\n\n'
          'AI teams will draft until your next pick. Each selection is saved. '
          'Draft rights do not add players to your active roster.',
        ),
        confirmLabel: 'Start Draft',
        confirmKey: 'confirm-start-draft',
        cancelKey: 'cancel-start-draft',
      );
      if (!mounted || !confirmed) return;
      if (!_confirmationIsCurrent(controller, career) ||
          !controller.career!.draftExecutionState.isNotStarted) {
        throw StateError('Career changed. Review the draft before starting.');
      }
      setState(() => _localError = null);
      await controller.startDraft();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) _commandPending.value = false;
    }
  }

  Future<void> _draftPlayer(
    PublicProspectScoutingView prospect,
    BuildContext sheetContext,
  ) async {
    if (!_canDraft(prospect.id)) return;
    final controller = widget.controller;
    final career = controller.career!;
    final pick = career.draftExecutionState.currentPick(career.draftOrder)!;
    final prospectId = prospect.id;
    _commandPending.value = true;
    try {
      final confirmed = await _confirm(
        title: 'Draft ${prospect.fullName}?',
        content: Text(
          '${prospect.position.shortName} • Age ${prospect.age}\n'
          'Overall ${prospect.overallRating} • Projected Rank #${prospect.projectedRank}\n'
          'Estimated Potential Grade: ${prospect.estimatedPotentialGrade}\n'
          'Estimated Ceiling Range: ${prospect.estimatedPotentialRange}\n\n'
          '${career.userTeam.name} (${career.userTeam.abbreviation})\n'
          'Round ${pick.round} • Pick ${pick.pickInRound} • Overall #${pick.overallPick}\n\n'
          'This selection will be saved before AI drafting continues. '
          'The player remains unsigned, outside your active roster.',
        ),
        confirmLabel: 'Draft Player',
        confirmKey: 'confirm-draft-player',
        cancelKey: 'cancel-draft-player',
      );
      if (!mounted || !confirmed) return;
      if (!_confirmationIsCurrent(controller, career) ||
          !_isHumanTurn(controller.career!) ||
          controller.career!.draftExecutionState
                  .currentPick(controller.career!.draftOrder)
                  ?.currentOwnerTeamId !=
              pick.currentOwnerTeamId ||
          controller.career!.draftExecutionState.isProspectSelected(
            prospectId,
          )) {
        throw StateError(
          'Draft pick changed. Review the current pick and choose again.',
        );
      }
      setState(() => _localError = null);
      if (sheetContext.mounted &&
          ModalRoute.of(sheetContext)?.isCurrent == true) {
        Navigator.pop(sheetContext);
      }
      _tabs.index = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _orderScroll.hasClients) _orderScroll.jumpTo(0);
      });
      await controller.makeHumanSelection(prospectId: prospectId);
      if (mounted && controller.career!.draftExecutionState.isCompleted) {
        _tabs.index = 2;
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) _commandPending.value = false;
    }
  }

  Future<void> _resumeDraft() async {
    final controller = widget.controller;
    final career = controller.career;
    if (_blocked ||
        career == null ||
        !career.draftExecutionState.isInProgress) {
      return;
    }
    if (_isHumanTurn(career)) {
      _tabs.index = 1;
      return;
    }
    _commandPending.value = true;
    try {
      setState(() => _localError = null);
      await controller.advanceDraft();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) _commandPending.value = false;
    }
  }

  Future<void> _reloadCareer() async {
    if (_commandPending.value || widget.controller.isLoading) return;
    _commandPending.value = true;
    try {
      setState(() => _localError = null);
      await widget.controller.loadCareer();
      final error = widget.controller.errorMessage;
      if (error != null) _showError(error);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) _commandPending.value = false;
    }
  }

  String _ownedPicks(GmCareer career) => career.draftOrder.picks
      .where((pick) => pick.currentOwnerTeamId == career.userFranchiseId)
      .map((pick) => 'Round ${pick.round}: #${pick.overallPick} overall')
      .join(' • ');

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.controller, _commandPending]),
    builder: (context, _) {
      final career = widget.controller.career;
      // No presentation helper accepts the hidden prospect model.
      final prospects = <String, PublicProspectScoutingView>{
        if (career != null)
          for (final prospect in career.draftClass.prospects)
            prospect.id.value: prospect.toPublicView(),
      };
      return Scaffold(
        appBar: AppBar(
          title: const Text('Rookie Draft Board'),
          bottom: TabBar(
            controller: _tabs,
            key: ValueKey('draft-board-tab-bar'),
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            tabs: const [
              Tab(
                icon: Icon(Icons.format_list_numbered, size: 20),
                text: 'Draft Order (60)',
              ),
              Tab(
                icon: Icon(Icons.people_outline, size: 20),
                text: 'Prospects (90)',
              ),
              Tab(
                icon: Icon(Icons.fact_check_outlined, size: 20),
                text: 'Results',
              ),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: career == null
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'No active GM Career. Reload the saved career or return to career setup.',
                    ),
                    if (widget.controller.errorMessage != null)
                      Text(widget.controller.errorMessage!),
                    FilledButton(
                      key: const ValueKey('draft-reload-button'),
                      onPressed:
                          _commandPending.value || widget.controller.isLoading
                          ? null
                          : _reloadCareer,
                      child: const Text('Reload Saved Career'),
                    ),
                  ],
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildDraftOrderTab(career, prospects),
                    _buildProspectsTab(career, prospects),
                    _buildResultsTab(career, prospects),
                  ],
                ),
        ),
      );
    },
  );

  Widget _buildStatus(
    GmCareer career,
    Map<String, PublicProspectScoutingView> prospects,
  ) {
    final theme = Theme.of(context);
    final state = career.draftExecutionState;
    final pick = state.currentPick(career.draftOrder);
    final team = pick == null
        ? null
        : _findTeam(career, pick.currentOwnerTeamId);
    final recovery = widget.controller.draftRecoveryRequired;
    final error = widget.controller.errorMessage ?? _localError;
    final status = recovery
        ? 'Reload required'
        : widget.controller.isLoading
        ? (state.isInProgress && !_isHumanTurn(career)
              ? 'AI Drafting'
              : 'Saving / Loading Draft')
        : state.isCompleted
        ? 'Draft Complete'
        : state.isNotStarted
        ? 'Draft Not Started'
        : _isHumanTurn(career)
        ? 'Your Pick'
        : 'AI Drafting — paused';
    final latest = state.selections.isEmpty ? null : state.selections.last;
    final latestProspect = latest == null
        ? null
        : prospects[latest.prospectId.value];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status,
            key: const ValueKey('draft-status'),
            style: theme.textTheme.titleMedium,
          ),
          Text(career.userTeam.name, style: theme.textTheme.bodyMedium),
          Text(
            '${state.completedSelectionsCount} / 60 selections committed',
            key: const ValueKey('draft-progress'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            state.isCompleted
                ? 'Both rounds complete'
                : 'Round ${pick!.round} • Pick ${pick.pickInRound} • Overall #${pick.overallPick}\n'
                      '${team!.name} (${team.abbreviation})${_isHumanTurn(career) ? ' • YOUR PICK' : ''}',
            key: const ValueKey('draft-current-pick'),
          ),
          if (latest != null && latestProspect != null) ...[
            const SizedBox(height: 8),
            Text(
              'Latest committed: #${latest.overallPick} • '
              '${_findTeam(career, latest.selectingTeamId).name} '
              '(${_findTeam(career, latest.selectingTeamId).abbreviation})\n'
              '${latestProspect.fullName} • ${latestProspect.position.shortName} • OVR ${latestProspect.overallRating}',
              key: const ValueKey('draft-latest-selection'),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (state.isNotStarted) ...[
            const SizedBox(height: 8),
            Text(_ownedPicks(career)),
            const Text('90 available prospects • 60 selections'),
            FilledButton.icon(
              key: const ValueKey('draft-start-button'),
              onPressed: _blocked ? null : _startDraft,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Draft'),
            ),
          ] else if (state.isInProgress) ...[
            if (_isHumanTurn(career))
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Open Prospects, inspect a player, then choose Draft Player.',
                ),
              ),
            OutlinedButton.icon(
              key: const ValueKey('draft-resume-button'),
              onPressed: _blocked ? null : _resumeDraft,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Resume Draft'),
            ),
          ],
          if (widget.controller.isLoading) const LinearProgressIndicator(),
          if (error != null || recovery) ...[
            const SizedBox(height: 8),
            Text(
              error ??
                  'The last save may have committed. Reload before continuing.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            if (recovery)
              const Text(
                'Draft commands are blocked. Reload to reconcile saved selections; do not retry the pick.',
              ),
            if (recovery || widget.controller.errorMessage != null)
              OutlinedButton.icon(
                key: const ValueKey('draft-reload-button'),
                onPressed: _commandPending.value || widget.controller.isLoading
                    ? null
                    : _reloadCareer,
                icon: const Icon(Icons.refresh),
                label: const Text('Reload Saved Career'),
              ),
          ],
          const Divider(),
        ],
      ),
    );
  }

  Widget _buildDraftOrderTab(
    GmCareer career,
    Map<String, PublicProspectScoutingView> prospects,
  ) {
    final picks = career.draftOrder.picks
        .where(
          (pick) =>
              _selectedRoundFilter == 0 || pick.round == _selectedRoundFilter,
        )
        .toList();
    return KeyedSubtree(
      key: const ValueKey('draft-order-view'),
      child: ListView.builder(
        key: const ValueKey('draft-order-list'),
        controller: _orderScroll,
        padding: const EdgeInsets.all(16),
        itemCount: picks.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatus(career, prospects),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('All (60)')),
                      ButtonSegment(value: 1, label: Text('Round 1 (30)')),
                      ButtonSegment(value: 2, label: Text('Round 2 (30)')),
                    ],
                    selected: {_selectedRoundFilter},
                    onSelectionChanged: (selection) =>
                        setState(() => _selectedRoundFilter = selection.first),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            );
          }
          return _buildPick(career, picks[index - 1], prospects);
        },
      ),
    );
  }

  Widget _buildPick(
    GmCareer career,
    DraftPick pick,
    Map<String, PublicProspectScoutingView> prospects,
  ) {
    final theme = Theme.of(context);
    final state = career.draftExecutionState;
    final own = pick.currentOwnerTeamId == career.userFranchiseId;
    final current =
        state.isInProgress && state.currentOverallPick == pick.overallPick;
    final team = _findTeam(career, pick.currentOwnerTeamId);
    final selection = pick.overallPick <= state.selections.length
        ? state.selections[pick.overallPick - 1]
        : null;
    final prospect = selection == null
        ? null
        : prospects[selection.prospectId.value];
    return Card(
      key: ValueKey('draft-pick-${pick.overallPick}'),
      color: own
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerLow,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Text(
          '#${pick.overallPick}',
          style: theme.textTheme.titleSmall,
        ),
        title: Text('${team.name} (${team.abbreviation})'),
        subtitle: Text(
          'Round ${pick.round} • Pick ${pick.pickInRound}'
          '${own ? ' • YOUR PICK' : ''}${current ? ' • CURRENT PICK' : ''}\n'
          '${pick.originalOwnerTeamId == pick.currentOwnerTeamId ? 'Original' : 'via ${_findTeam(career, pick.originalOwnerTeamId).abbreviation}'}\n'
          '${prospect == null ? 'Remaining selection' : '${prospect.fullName} • ${prospect.position.shortName} • OVR ${prospect.overallRating}'}',
        ),
        onTap: prospect == null ? null : () => _showProspectDetails(prospect),
      ),
    );
  }

  String _availability(GmCareer career, PublicProspectScoutingView prospect) {
    final rights = career.draftExecutionState.draftRights[prospect.id.value];
    if (rights == null) {
      return career.draftExecutionState.isCompleted
          ? 'Undrafted • Available'
          : 'Available';
    }
    return 'Selected #${rights.overallPick} • ${_findTeam(career, rights.owningTeamId).abbreviation}'
        ' • ${rookieSigningStatus(career, prospect.id)}';
  }

  Widget _buildProspectsTab(
    GmCareer career,
    Map<String, PublicProspectScoutingView> prospects,
  ) {
    final filtered = prospects.values.where((prospect) {
      final selected = career.draftExecutionState.isProspectSelected(
        prospect.id,
      );
      return (_selectedPosition == null ||
              prospect.position == _selectedPosition) &&
          prospect.fullName.toLowerCase().contains(_searchQuery) &&
          (_availabilityFilter == 'All' ||
              (_availabilityFilter == 'Available' && !selected) ||
              (_availabilityFilter == 'Selected' && selected));
    }).toList()..sort((a, b) => a.projectedRank.compareTo(b.projectedRank));
    return KeyedSubtree(
      key: const ValueKey('prospect-view'),
      child: ListView.builder(
        key: const ValueKey('prospect-list'),
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: filtered.length + 1,
        itemBuilder: (context, index) {
          if (index > 0) return _buildProspectCard(career, filtered[index - 1]);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatus(career, prospects),
              TextField(
                key: const ValueKey('prospect-search-field'),
                controller: _searchController,
                onChanged: (query) =>
                    setState(() => _searchQuery = query.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search prospects by name...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  spacing: 6,
                  children: [
                    FilterChip(
                      key: const ValueKey('prospect-filter-all'),
                      label: const Text('ALL'),
                      selected: _selectedPosition == null,
                      onSelected: (_) =>
                          setState(() => _selectedPosition = null),
                    ),
                    for (final position in Position.values)
                      FilterChip(
                        key: ValueKey(
                          'prospect-filter-${position.shortName.toLowerCase()}',
                        ),
                        label: Text(position.shortName),
                        selected: _selectedPosition == position,
                        onSelected: (selected) => setState(
                          () => _selectedPosition = selected ? position : null,
                        ),
                      ),
                  ],
                ),
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (final availability in ['All', 'Available', 'Selected'])
                    ChoiceChip(
                      key: ValueKey(
                        'prospect-status-${availability.toLowerCase()}',
                      ),
                      label: Text(availability),
                      selected: _availabilityFilter == availability,
                      onSelected: (_) =>
                          setState(() => _availabilityFilter = availability),
                    ),
                ],
              ),
              Text(
                'Showing ${filtered.length} of ${prospects.length} Prospects • By Projected Rank',
              ),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No prospects match your criteria'),
                ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProspectCard(
    GmCareer career,
    PublicProspectScoutingView prospect,
  ) => Card(
    key: ValueKey('prospect-card-${prospect.projectedRank}'),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Text(
        '#${prospect.projectedRank}',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      title: Text(prospect.fullName),
      subtitle: Text(
        '${prospect.position.shortName} • Age ${prospect.age} • OVR ${prospect.overallRating}\n'
        'Est. POT: ${prospect.estimatedPotentialGrade} (${prospect.estimatedPotentialRange})\n'
        '${_availability(career, prospect)}',
      ),
      onTap: () => _showProspectDetails(prospect),
    ),
  );

  Widget _buildResultsTab(
    GmCareer career,
    Map<String, PublicProspectScoutingView> prospects,
  ) {
    final state = career.draftExecutionState;
    final rights =
        state.draftRights.values
            .where((right) => right.owningTeamId == career.userFranchiseId)
            .toList()
          ..sort((a, b) => a.overallPick.compareTo(b.overallPick));
    final undrafted =
        prospects.values
            .where((prospect) => !state.isProspectSelected(prospect.id))
            .toList()
          ..sort((a, b) => a.projectedRank.compareTo(b.projectedRank));
    final signedCount = rights
        .where((right) => isSignedRookie(career, right.prospectId))
        .length;
    return ListView.builder(
      key: const ValueKey('draft-results'),
      padding: const EdgeInsets.all(16),
      itemCount:
          2 +
          rights.length +
          career.draftOrder.totalPicks +
          (state.isCompleted ? 1 + undrafted.length : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatus(career, prospects),
              Text(
                state.isCompleted
                    ? '60 selections • 30 undrafted prospects'
                    : '${state.selections.length} selections • Draft in progress',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Text(
                'Your Drafted Prospects • ${rights.length - signedCount} unsigned • '
                '$signedCount signed',
                key: const ValueKey('draft-owned-rights'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Text(
                'Unsigned draft rights are not Active Roster Players and consume no roster slots. '
                'Signed rookies remain part of draft history.',
              ),
              if (rights.isEmpty) const Text('No owned draft rights yet.'),
            ],
          );
        }
        index--;
        if (index < rights.length) {
          final right = rights[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Year ${right.seasonYear} • Round ${(right.overallPick - 1) ~/ 30 + 1} • '
                'Pick ${(right.overallPick - 1) % 30 + 1} • Overall #${right.overallPick}',
              ),
              _buildProspectCard(career, prospects[right.prospectId.value]!),
            ],
          );
        }
        index -= rights.length;
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              'Complete Draft Order / History',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          );
        }
        index--;
        if (index < career.draftOrder.totalPicks) {
          return _buildPick(career, career.draftOrder.picks[index], prospects);
        }
        index -= career.draftOrder.totalPicks;
        if (index == 0) {
          return Text(
            'Undrafted Prospects (${undrafted.length})',
            style: Theme.of(context).textTheme.titleSmall,
          );
        }
        return _buildProspectCard(career, undrafted[index - 1]);
      },
    );
  }

  Future<void> _showProspectDetails(
    PublicProspectScoutingView initialProspect,
  ) async {
    final careerId = widget.controller.career?.id;
    final year = widget.controller.career?.currentYear;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => ListenableBuilder(
            listenable: Listenable.merge([widget.controller, _commandPending]),
            builder: (context, _) {
              final career = widget.controller.career;
              final currentProspect = career?.draftClass
                  .byId(initialProspect.id)
                  ?.toPublicView();
              final prospect = currentProspect ?? initialProspect;
              final attrs = prospect.attributes;
              final sameDraft =
                  career?.id == careerId &&
                  career?.currentYear == year &&
                  currentProspect != null;
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          prospect.fullName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close prospect details',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Text(
                    '${prospect.position.shortName} • Age ${prospect.age} • OVR ${prospect.overallRating}',
                  ),
                  if (career != null && sameDraft)
                    Text(_availability(career, prospect)),
                  if (!sameDraft)
                    const Text(
                      'Career changed. Close details and inspect the current prospect board.',
                    ),
                  FilledButton.icon(
                    key: const ValueKey('draft-player-button'),
                    onPressed: sameDraft && _canDraft(prospect.id)
                        ? () => _draftPlayer(prospect, sheetContext)
                        : null,
                    icon: const Icon(Icons.how_to_reg),
                    label: const Text('Draft Player'),
                  ),
                  if (widget.controller.isLoading)
                    Text(
                      career != null &&
                              career.draftExecutionState.isInProgress &&
                              !_isHumanTurn(career)
                          ? 'AI Drafting — committed picks update live.'
                          : 'Saving / Loading Draft',
                    ),
                  if (widget.controller.errorMessage != null)
                    Text(
                      widget.controller.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (widget.controller.draftRecoveryRequired ||
                      widget.controller.errorMessage != null) ...[
                    const Text(
                      'Reload saved career to reconcile selections before drafting again.',
                    ),
                    OutlinedButton(
                      key: const ValueKey('draft-reload-button'),
                      onPressed:
                          _commandPending.value || widget.controller.isLoading
                          ? null
                          : _reloadCareer,
                      child: const Text('Reload Saved Career'),
                    ),
                  ],
                  const Divider(height: 24),
                  Text(
                    'Public Scouting Evaluation',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    'Consensus Draft Rank: #${prospect.projectedRank} Overall',
                  ),
                  Text(
                    'Estimated Potential Grade: ${prospect.estimatedPotentialGrade}',
                  ),
                  Text(
                    'Estimated Ceiling Range: ${prospect.estimatedPotentialRange}',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Observed Abilities',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  _buildAttributeRow('Inside Scoring', attrs.insideScoring),
                  _buildAttributeRow('Midrange', attrs.midrange),
                  _buildAttributeRow('Three-Point', attrs.threePoint),
                  _buildAttributeRow('Free Throw', attrs.freeThrow),
                  _buildAttributeRow('Passing', attrs.passing),
                  _buildAttributeRow('Ball Handling', attrs.ballHandling),
                  _buildAttributeRow(
                    'Perimeter Defense',
                    attrs.perimeterDefense,
                  ),
                  _buildAttributeRow('Interior Defense', attrs.interiorDefense),
                  _buildAttributeRow('Rebounding', attrs.rebounding),
                  _buildAttributeRow('Athleticism', attrs.athleticism),
                  _buildAttributeRow('Stamina', attrs.stamina),
                  _buildAttributeRow('Basketball IQ', attrs.basketballIQ),
                ],
              );
            },
          ),
        ),
      );
    } catch (error) {
      _showError(error);
    }
  }

  Widget _buildAttributeRow(String name, int value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(name)),
        const SizedBox(width: 12),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    ),
  );
}
