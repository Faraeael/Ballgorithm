import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

/// Screen displaying the complete Year 1 Opening Rookie Draft ecosystem:
/// 1. Draft Order View (all 60 selections across 2 rounds with ownership and user highlights).
/// 2. Prospect View (all 90 prospects with search, position filters, public rankings, and scouting estimates).
class GmDraftBoardScreen extends StatefulWidget {
  const GmDraftBoardScreen({super.key, required this.career});

  final GmCareer career;

  @override
  State<GmDraftBoardScreen> createState() => _GmDraftBoardScreenState();
}

class _GmDraftBoardScreenState extends State<GmDraftBoardScreen> {
  final TextEditingController _searchController = TextEditingController();
  Position? _selectedPosition;
  int _selectedRoundFilter = 0; // 0: All, 1: Round 1, 2: Round 2
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Team _findTeam(TeamId id) {
    return widget.career.league.teams.firstWhere(
      (t) => t.id == id,
      orElse: () => Team(
        id: id,
        name: id.value,
        abbreviation: id.value.toUpperCase(),
        roster: Roster(const []),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Rookie Draft Board'),
          bottom: const TabBar(
            key: ValueKey('draft-board-tab-bar'),
            tabs: [
              Tab(
                icon: Icon(Icons.format_list_numbered, size: 20),
                text: 'Draft Order (60)',
              ),
              Tab(
                icon: Icon(Icons.people_outline, size: 20),
                text: 'Prospects (90)',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [_buildDraftOrderTab(theme), _buildProspectsTab(theme)],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: DRAFT ORDER VIEW (60 PICKS)
  // ---------------------------------------------------------------------------

  Widget _buildDraftOrderTab(ThemeData theme) {
    final draftOrder = widget.career.draftOrder;
    final allPicks = draftOrder.picks;

    final filteredPicks = allPicks.where((p) {
      if (_selectedRoundFilter == 1) return p.round == 1;
      if (_selectedRoundFilter == 2) return p.round == 2;
      return true;
    }).toList();

    return Column(
      key: const ValueKey('draft-order-view'),
      children: [
        // Round Filter Segmented Control
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('All (60)')),
              ButtonSegment(value: 1, label: Text('Round 1 (30)')),
              ButtonSegment(value: 2, label: Text('Round 2 (30)')),
            ],
            selected: {_selectedRoundFilter},
            onSelectionChanged: (set) {
              setState(() {
                _selectedRoundFilter = set.first;
              });
            },
          ),
        ),

        // Pick List
        Expanded(
          child: ListView.separated(
            key: const ValueKey('draft-order-list'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: filteredPicks.length,
            separatorBuilder: (context, index) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final pick = filteredPicks[index];
              final isUserPick =
                  pick.currentOwnerTeamId == widget.career.userFranchiseId;
              final currentTeam = _findTeam(pick.currentOwnerTeamId);
              final originalTeam = _findTeam(pick.originalOwnerTeamId);

              return Card(
                key: ValueKey('draft-pick-${pick.overallPick}'),
                elevation: isUserPick ? 3 : 0.5,
                color: isUserPick
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.7)
                    : theme.colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: isUserPick
                      ? BorderSide(color: theme.colorScheme.primary, width: 2)
                      : BorderSide(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      // Overall Pick Badge
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isUserPick
                              ? theme.colorScheme.primary
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '#${pick.overallPick}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isUserPick
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Team & Round Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    currentTeam.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: isUserPick
                                          ? FontWeight.bold
                                          : FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                if (isUserPick) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'YOUR PICK',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.onPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Round ${pick.round} • Pick ${pick.pickInRound}'
                              '${pick.originalOwnerTeamId != pick.currentOwnerTeamId ? ' (via ${originalTeam.abbreviation})' : ' (Original)'}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Team Abbreviation Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          currentTeam.abbreviation,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: PROSPECT VIEW (90 PROSPECTS)
  // ---------------------------------------------------------------------------

  Widget _buildProspectsTab(ThemeData theme) {
    final allProspects = widget.career.draftClass.prospects;

    final filteredProspects = allProspects.where((p) {
      if (_selectedPosition != null && p.position != _selectedPosition) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final name = p.fullName.toLowerCase();
        if (!name.contains(_searchQuery)) {
          return false;
        }
      }
      return true;
    }).toList();

    return Column(
      key: const ValueKey('prospect-view'),
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            key: const ValueKey('prospect-search-field'),
            controller: _searchController,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search prospects by name...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
          ),
        ),

        // Position filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              FilterChip(
                key: const ValueKey('prospect-filter-all'),
                label: const Text('ALL'),
                selected: _selectedPosition == null,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _selectedPosition = null;
                    });
                  }
                },
              ),
              const SizedBox(width: 6),
              ...Position.values.map(
                (pos) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    key: ValueKey(
                      'prospect-filter-${pos.shortName.toLowerCase()}',
                    ),
                    label: Text(pos.shortName),
                    selected: _selectedPosition == pos,
                    onSelected: (selected) {
                      setState(() {
                        _selectedPosition = selected ? pos : null;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        // Count banner
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Showing ${filteredProspects.length} of ${allProspects.length} Prospects',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'By Projected Rank',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),

        // Prospect List
        Expanded(
          child: filteredProspects.isEmpty
              ? Center(
                  child: Text(
                    'No prospects match your criteria',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  key: const ValueKey('prospect-list'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: filteredProspects.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final prospect = filteredProspects[index];
                    return _buildProspectCard(context, theme, prospect);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProspectCard(
    BuildContext context,
    ThemeData theme,
    RookieProspect prospect,
  ) {
    return Card(
      key: ValueKey('prospect-card-${prospect.projectedRank}'),
      elevation: 0.5,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showProspectDetails(context, prospect),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Projected Rank Badge
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#${prospect.projectedRank}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Prospect Identification & Public Scouting Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prospect.fullName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${prospect.position.shortName} • Age ${prospect.age} • Est. POT: ${prospect.estimatedPotentialGrade} (${prospect.estimatedPotentialRange})',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // Visible Overall Rating
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'OVR ${prospect.overallRating}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'Grade ${prospect.estimatedPotentialGrade}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PROSPECT DETAILS BOTTOM SHEET (READ-ONLY)
  // ---------------------------------------------------------------------------

  void _showProspectDetails(BuildContext context, RookieProspect prospect) {
    final theme = Theme.of(context);
    final attrs = prospect.attributes;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: ListView(
                controller: scrollController,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                        child: Text(
                          prospect.position.shortName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              prospect.fullName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Age ${prospect.age} • Projected Rank #${prospect.projectedRank}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'OVR ${prospect.overallRating}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Grade: ${prospect.estimatedPotentialGrade}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // Public Scouting Evaluation Box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Public Scouting Evaluation',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text('Consensus Draft Rank:'),
                            ),
                            Text(
                              '#${prospect.projectedRank} Overall',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text('Estimated Potential Grade:'),
                            ),
                            Text(
                              prospect.estimatedPotentialGrade,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text('Estimated Ceiling Range:'),
                            ),
                            Text(
                              prospect.estimatedPotentialRange,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Visible Ratings Section
                  Text(
                    'Observed Abilities',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),

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

                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'Internal ceiling and development curve are hidden from public board.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.outline,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAttributeRow(String name, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name, style: const TextStyle(fontSize: 12)),
          Text(
            '$value',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
