import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'career_controller.dart';
import 'career_storage.dart';
import 'draft_board_screen.dart';
import 'league_readiness_screen.dart';
import 'rookie_signing_screen.dart';
import 'rookie_signing_status.dart';

/// Screen presenting the Year 1 Opening Offseason overview for a persistent GM Career.
class GmOffseasonOverviewScreen extends StatelessWidget {
  const GmOffseasonOverviewScreen({
    super.key,
    required this.controller,
    this.onExit,
  });

  final GmCareerController controller;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final career = controller.career;
      if (career == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('GM Career')),
          body: Center(
            child: controller.isLoading
                ? const CircularProgressIndicator()
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      controller.errorMessage ??
                          'Career save is missing. No save data was changed.',
                    ),
                  ),
          ),
        );
      }
      return _buildOverview(context, career);
    },
  );

  Widget _buildOverview(BuildContext context, GmCareer career) {
    final theme = Theme.of(context);
    final team = career.userTeam;
    final profiles = career.careerProfiles;
    final draft = career.draftExecutionState;
    final draftLabel = switch (draft.status) {
      DraftExecutionStatus.notStarted => 'Start Rookie Draft',
      DraftExecutionStatus.inProgress => 'Resume Draft',
      DraftExecutionStatus.completed => 'View Draft Results',
    };
    final ownedPicks = career.draftOrder.picksForTeam(career.userFranchiseId);
    final currentPick = draft.currentPick(career.draftOrder);
    final selectingTeam = currentPick == null
        ? null
        : career.league.teams.firstWhere(
            (team) => team.id == currentPick.currentOwnerTeamId,
          );
    final ownedSelections = draft.selections
        .where(
          (selection) => selection.selectingTeamId == career.userFranchiseId,
        )
        .toList();
    final ownedRights = career.unsignedDraftRights
        .where((rights) => rights.owningTeamId == career.userFranchiseId)
        .length;
    final signedRookies = ownedSelections
        .where((selection) => isSignedRookie(career, selection.prospectId))
        .length;
    final readiness = LeagueReadinessReport.fromCareer(career);
    final draftSummary = switch (draft.status) {
      DraftExecutionStatus.notStarted =>
        '${ownedPicks.map((pick) => 'Round ${pick.round}: #${pick.overallPick}').join(' • ')}\n'
            '${career.draftClass.length} available prospects • ${career.draftOrder.totalPicks} selections',
      DraftExecutionStatus.inProgress =>
        'Round ${currentPick!.round} • Pick #${currentPick.overallPick}\n'
            'Selecting: ${selectingTeam!.name} (${selectingTeam.abbreviation})\n'
            '${draft.completedSelectionsCount}/${career.draftOrder.totalPicks} selections complete',
      DraftExecutionStatus.completed =>
        '${draft.completedSelectionsCount}/${career.draftOrder.totalPicks} selections complete\n'
            '${ownedSelections.length} drafted prospects • $ownedRights owned unsigned rights',
    };

    void openDraft() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GmDraftBoardScreen(controller: controller),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${team.abbreviation} Offseason'),
        actions: [
          IconButton(
            key: const ValueKey('exit-career-menu-button'),
            tooltip: 'Return to Main Menu',
            icon: const Icon(Icons.home_outlined),
            onPressed: () {
              if (onExit != null) {
                onExit!();
              } else {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('offseason-overview-scroll'),
        padding: const EdgeInsets.all(16.0),
        children: [
          // Header Card: Franchise, Year & Phase
          Card(
            elevation: 1,
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        child: Text(
                          team.abbreviation,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              team.name,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            Text(
                              'Year ${career.currentYear} • ${career.phase.displayName}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Starting Situation:',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.4,
                              ),
                            ),
                          ),
                          child: Text(
                            career.originalSituation.displayName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Draft Entitlement Card
          Card(
            key: const ValueKey('card-draft-entitlement'),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: openDraft,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Icon(
                        Icons.how_to_reg_outlined,
                        color: Colors.green.shade800,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            draftLabel,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            draftSummary,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        draft.isCompleted
                            ? Icons.check_circle_outline
                            : Icons.chevron_right,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (draft.isCompleted) ...[
            const SizedBox(height: 8),
            Card(
              key: const ValueKey('card-rookie-signing'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rookie Signing',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${ownedSelections.length} drafted prospects • '
                      '$signedRookies signed • $ownedRights unsigned',
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Standard: ${team.roster.standardCount}/'
                      '${RosterRules.maxOffseasonStandard} • Two-way: '
                      '${team.roster.twoWayCount}/'
                      '${RosterRules.maxOffseasonTwoWay} • Total: '
                      '${team.roster.totalContractedCount}/'
                      '${RosterRules.maxOffseasonTotal}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      key: const ValueKey('btn-open-rookie-signing'),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                GmRookieSigningScreen(controller: controller),
                          ),
                        );
                      },
                      child: const Text('Manage Rookie Signing'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Current Roster Section
          Column(
            key: const ValueKey('card-roster-composition'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Current Roster (${team.players.length} Players)',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Total: ${team.roster.totalContractedCount}/${RosterRules.maxOffseasonTotal}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Standard: ${team.roster.standardCount}/${RosterRules.maxOffseasonStandard} • Two-Way: ${team.roster.twoWayCount}/${RosterRules.maxOffseasonTwoWay} • Camp: ${team.roster.trainingCampCount}',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Roster List
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: team.players.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final player = team.players[index];
                final profile = profiles.forPlayer(player.id);
                final overall = player.attributes.overallRating;
                final isStarter = index < 5;
                final contract = career.rookieSigningLedger.forPlayer(
                  player.id,
                );
                final rookie = contract == null
                    ? null
                    : career.draftClass.byId(player.id)?.toPublicView();

                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: isStarter
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    foregroundColor: isStarter
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                    child: Text(
                      player.position.shortName,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                  title: Text(
                    player.fullName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    rookie == null
                        ? 'Age: ${profile?.age ?? "-"} • ${profile?.trajectory.displayName ?? "-"}'
                        : 'Age: ${rookie.age} • Rookie • ${contract!.category.displayName}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'OVR $overall',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        rookie == null
                            ? 'POT ${profile?.potential ?? "-"}'
                            : 'Est. ${rookie.estimatedPotentialGrade}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (draft.isCompleted) ...[
            const SizedBox(height: 8),
            Card(
              key: const ValueKey('card-league-signings'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'League Rookie Signings',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${readiness.evaluatedAiDecisions} / '
                      '${readiness.totalAiRights} decisions processed',
                      key: const ValueKey('league-signings-progress'),
                    ),
                    Text(
                      '${readiness.aiStandardSignings} standard • '
                      '${readiness.aiTwoWaySignings} two-way • '
                      '${readiness.aiDeferredRights} deferred',
                      key: const ValueKey('league-signings-breakdown'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (readiness.aiSigningComplete)
                      const Text(
                        'All AI-owned draft rights have been evaluated.',
                        key: ValueKey('league-signings-complete'),
                      )
                    else
                      Text(
                        '${readiness.pendingAiDecisions} remaining • '
                        '${readiness.aiParticipatingFranchises} AI franchises',
                        key: const ValueKey('league-signings-remaining'),
                      ),
                    if (controller.draftRecoveryRequired) ...[
                      const SizedBox(height: 8),
                      Text(
                        controller.errorMessage ??
                            'A save failed. Reload the saved career before '
                                'continuing.',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        key: const ValueKey('btn-league-signings-reload'),
                        onPressed: controller.isLoading
                            ? null
                            : () => controller.loadCareer(),
                        child: const Text('Reload Saved Career'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      key: const ValueKey('btn-resolve-league-signings'),
                      onPressed:
                          readiness.aiSigningComplete ||
                              controller.isLoading ||
                              controller.draftRecoveryRequired
                          ? null
                          : () => _confirmResolveLeagueSignings(
                              context,
                              readiness,
                            ),
                      child: Text(
                        readiness.aiSigningComplete
                            ? 'League Signings Complete'
                            : readiness.evaluatedAiDecisions == 0
                            ? 'Resolve League Rookie Signings'
                            : 'Resume League Rookie Signings',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Card(
            key: const ValueKey('card-league-readiness'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'League Readiness',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${readiness.readyCount} ready • '
                    '${readiness.notReadyCount} not ready',
                    key: const ValueKey('offseason-readiness-counts'),
                  ),
                  Text(
                    'Standard players needed league-wide: '
                    '${readiness.totalStandardShortage}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    'Your franchise: ${readiness.userTeam.abbreviation} — '
                    '${readiness.userTeam.isReady ? 'READY' : 'needs ${readiness.humanStandardShortage} standard players'}',
                    key: const ValueKey('offseason-human-readiness'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    key: const ValueKey('btn-open-league-readiness'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              GmLeagueReadinessScreen(controller: controller),
                        ),
                      );
                    },
                    child: const Text('View League Readiness'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Future Operations / In Development Section
          Text(
            'Front Office Modules (In Development)',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  // Unlocked Rookie Draft Module
                  Padding(
                    key: const ValueKey('module-rookie-draft'),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onPrimaryContainer,
                              child: const Icon(Icons.assignment_outlined),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Rookie Draft',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(draftSummary),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          key: const ValueKey('btn-open-draft-board'),
                          onPressed: openDraft,
                          child: Text(draftLabel),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  _buildDisabledModuleTile(
                    context,
                    icon: Icons.person_add_outlined,
                    title: 'Free Agency',
                    subtitle: 'Contract signings and market negotiations',
                  ),
                  const Divider(height: 1),
                  _buildDisabledModuleTile(
                    context,
                    icon: Icons.swap_horiz_outlined,
                    title: 'Trades',
                    subtitle: 'Franchise player and pick exchanges',
                  ),
                  const Divider(height: 1),
                  _buildDisabledModuleTile(
                    context,
                    icon: Icons.sports_outlined,
                    title: 'Staff & Coaching',
                    subtitle: 'Head coach hiring and tactical schemes',
                  ),
                  const Divider(height: 1),
                  _buildDisabledModuleTile(
                    context,
                    icon: Icons.domain_outlined,
                    title: 'Facilities',
                    subtitle: 'Training centers, analytics, and medical staff',
                  ),
                  const Divider(height: 1),
                  _buildDisabledModuleTile(
                    context,
                    icon: Icons.account_balance_outlined,
                    title: 'Franchise Finances',
                    subtitle: 'Salary cap, revenue, and payroll management',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _confirmResolveLeagueSignings(
    BuildContext context,
    LeagueReadinessReport report,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Resolve League Rookie Signings?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${report.aiParticipatingFranchises} AI franchises'),
            Text('${report.totalAiRights} AI-owned draft rights'),
            Text('${report.evaluatedAiDecisions} decisions already evaluated'),
            Text('${report.pendingAiDecisions} remaining'),
            const SizedBox(height: 8),
            const Text(
              'Each franchise may sign a standard contract, sign a two-way '
              'contract, or keep its draft rights unsigned. Your own '
              'franchise is never signed automatically.',
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const ValueKey('cancel-resolve-signings'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-resolve-signings'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Resolve Signings'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.advanceAiRookieSigning();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Widget _buildDisabledModuleTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.7,
                    ),
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Locked',
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.7,
                ),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Owns a live controller when entering a career outside the app-owned flow.
class GmOffseasonOverviewRoute extends StatefulWidget {
  const GmOffseasonOverviewRoute({super.key, required this.storage});

  final GmCareerStorage storage;

  @override
  State<GmOffseasonOverviewRoute> createState() =>
      _GmOffseasonOverviewRouteState();
}

class _GmOffseasonOverviewRouteState extends State<GmOffseasonOverviewRoute> {
  late final GmCareerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = GmCareerController(storage: widget.storage);
    _controller.loadCareer();
  }

  @override
  void dispose() {
    _controller.commandsSettled.then((_) => _controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      GmOffseasonOverviewScreen(controller: _controller);
}
