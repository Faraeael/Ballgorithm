import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'career_controller.dart';

/// Read-only league-wide offseason readiness and AI signing report.
class GmLeagueReadinessScreen extends StatelessWidget {
  const GmLeagueReadinessScreen({super.key, required this.controller});

  final GmCareerController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final career = controller.career;
      if (career == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('League Readiness')),
          body: const Center(child: Text('No active GM Career.')),
        );
      }
      final report = LeagueReadinessReport.fromCareer(career);
      return Scaffold(
        appBar: AppBar(title: const Text('League Readiness')),
        body: ListView(
          key: const ValueKey('league-readiness-scroll'),
          padding: const EdgeInsets.all(16),
          children: [
            _SummaryCard(report: report),
            const SizedBox(height: 16),
            Text(
              'All Franchises (${report.teams.length})',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final team in report.teams)
              _TeamReadinessCard(
                team: team,
                onTap: () => _openDetails(context, career, team),
              ),
          ],
        ),
      );
    },
  );

  Future<void> _openDetails(
    BuildContext context,
    GmCareer career,
    TeamReadiness team,
  ) async {
    final rosterTeam = career.league.teams.firstWhere(
      (candidate) => candidate.id == team.teamId,
    );
    final contracts = career.rookieSigningLedger.ordered
        .where((contract) => contract.teamId == team.teamId)
        .toList();
    final rights =
        career.draftExecutionState.draftRights.values
            .where(
              (right) =>
                  right.owningTeamId == team.teamId &&
                  !career.rookieSigningLedger.isSigned(right.prospectId),
            )
            .toList()
          ..sort((a, b) => a.overallPick.compareTo(b.overallPick));
    final positionCounts = <Position, int>{
      for (final position in Position.values)
        position: rosterTeam.players
            .where((player) => player.position == position)
            .length,
    };

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => ListView(
          key: const ValueKey('franchise-detail-sheet'),
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              '${team.name} (${team.abbreviation})',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              team.isHuman
                  ? '${team.situation.displayName} • YOUR FRANCHISE'
                  : team.situation.displayName,
            ),
            const SizedBox(height: 12),
            _DetailRow(
              label: 'Standard players',
              value:
                  '${team.standardCount}/${RosterRules.maxOffseasonStandard}',
            ),
            _DetailRow(
              label: 'Two-way players',
              value: '${team.twoWayCount}/${RosterRules.maxOffseasonTwoWay}',
            ),
            _DetailRow(
              label: 'Total offseason roster',
              value: '${team.totalCount}/${RosterRules.maxOffseasonTotal}',
            ),
            _DetailRow(
              label: 'Regular season',
              value: team.isReady
                  ? 'READY'
                  : 'Needs ${team.standardShortage} standard players',
            ),
            const SizedBox(height: 16),
            Text(
              'Readiness Issues',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            if (team.readinessIssues.isEmpty)
              const Text('All regular-season readiness checks are satisfied.')
            else
              for (final issue in team.readinessIssues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $issue'),
                ),
            const SizedBox(height: 16),
            Text(
              'Position Breakdown',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final position in Position.values)
                  Text(
                    '${position.shortName} ${positionCounts[position]}',
                    key: ValueKey(
                      'detail-position-${position.shortName.toLowerCase()}',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Signed Drafted Rookies (${contracts.length})',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            if (contracts.isEmpty)
              const Text('No drafted rookies signed.')
            else
              for (final contract in contracts)
                _RookieDetailCard(
                  key: ValueKey('detail-signed-${contract.playerId.value}'),
                  career: career,
                  playerId: contract.playerId,
                  status: switch (contract.category) {
                    RosterCategory.standard => 'Signed — Standard',
                    RosterCategory.twoWay => 'Signed — Two-Way',
                    RosterCategory.trainingCamp => 'Signed',
                  },
                  detail:
                      'Round ${(contract.overallPick - 1) ~/ 30 + 1} • '
                      'Pick #${contract.overallPick} • '
                      '${contract.durationYears} years',
                ),
            const SizedBox(height: 16),
            Text(
              'Unsigned Drafted Rights (${rights.length})',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            if (rights.isEmpty)
              const Text('No unsigned drafted rights.')
            else
              for (final right in rights)
                _RookieDetailCard(
                  key: ValueKey('detail-unsigned-${right.prospectId.value}'),
                  career: career,
                  playerId: right.prospectId,
                  status:
                      career.aiRookieSigning.forProspect(right.prospectId) ==
                          null
                      ? 'Pending evaluation'
                      : 'Deferred',
                  detail:
                      'Round ${(right.overallPick - 1) ~/ 30 + 1} • '
                      'Pick #${right.overallPick}',
                ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.report});

  final LeagueReadinessReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final human = report.userTeam;
    return Card(
      key: const ValueKey('league-readiness-summary'),
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'League Readiness',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${report.readyCount} ready • ${report.notReadyCount} not ready',
              key: const ValueKey('readiness-counts'),
            ),
            Text(
              'Standard players needed league-wide: '
              '${report.totalStandardShortage}',
              key: const ValueKey('readiness-shortage'),
            ),
            Text(
              'AI signings: ${report.aiStandardSignings} standard • '
              '${report.aiTwoWaySignings} two-way • '
              '${report.aiDeferredRights} deferred',
              key: const ValueKey('readiness-ai-signings'),
            ),
            Text(
              'Pending AI decisions: ${report.pendingAiDecisions} of '
              '${report.totalAiRights}',
              key: const ValueKey('readiness-ai-pending'),
            ),
            const SizedBox(height: 8),
            Text(
              'Your franchise: ${human.name} (${human.abbreviation}) — '
              '${human.isReady ? 'READY' : 'needs ${human.standardShortage} standard players'}',
              key: const ValueKey('readiness-human'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamReadinessCard extends StatelessWidget {
  const _TeamReadinessCard({required this.team, required this.onTap});

  final TeamReadiness team;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('readiness-team-${team.teamId.value}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${team.name} (${team.abbreviation})',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ReadyChip(isReady: team.isReady),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                team.isHuman
                    ? '${team.situation.displayName} • YOUR FRANCHISE'
                    : team.situation.displayName,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Standard ${team.standardCount}/'
                '${RosterRules.maxOffseasonStandard} • Two-way '
                '${team.twoWayCount}/${RosterRules.maxOffseasonTwoWay} • '
                'Total ${team.totalCount}/${RosterRules.maxOffseasonTotal}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                team.isReady
                    ? 'Regular season: READY'
                    : 'Needs ${team.standardShortage} standard '
                          '${team.standardShortage == 1 ? 'player' : 'players'}',
                key: ValueKey('readiness-need-${team.teamId.value}'),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: team.isReady
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
              ),
              Text(
                'Unsigned drafted rights: ${team.unsignedDraftedRights}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadyChip extends StatelessWidget {
  const _ReadyChip({required this.isReady});

  final bool isReady;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isReady ? theme.colorScheme.primary : theme.colorScheme.error,
        ),
      ),
      child: Text(
        isReady ? 'READY' : 'NOT READY',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isReady ? theme.colorScheme.primary : theme.colorScheme.error,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _RookieDetailCard extends StatelessWidget {
  const _RookieDetailCard({
    super.key,
    required this.career,
    required this.playerId,
    required this.status,
    required this.detail,
  });

  final GmCareer career;
  final PlayerId playerId;
  final String status;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prospect = career.draftClass.byId(playerId);
    if (prospect == null) {
      return const SizedBox.shrink();
    }
    final public = prospect.toPublicView();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            public.fullName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            '${public.position.shortName} • Age ${public.age} • '
            'OVR ${public.overallRating} • '
            'Est. POT ${public.estimatedPotentialGrade} '
            '(${public.estimatedPotentialRange})',
            style: theme.textTheme.bodySmall,
          ),
          Text(
            '$detail • $status',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
