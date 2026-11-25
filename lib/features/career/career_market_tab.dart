import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import '../../theme/hardwood_command_theme.dart';
import 'career_controller.dart';
import 'career_ui_labels.dart';
import 'draft_board_screen.dart';
import 'free_agents_screen.dart';
import 'league_readiness_screen.dart';
import 'offseason_clearance_screen.dart';
import 'rookie_signing_screen.dart';
import 'widgets/hardwood_components.dart';

/// Market destination connecting Rookie Draft, Rookie Signing, Free Agency,
/// and Offseason Clearance with truthful phase restrictions.
class CareerMarketTab extends StatelessWidget {
  const CareerMarketTab({super.key, required this.controller});

  final GmCareerController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final career = controller.career;
    if (career == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final isOffseason = career.phase == CareerPhase.openingOffseason;
    final draft = career.draftExecutionState;
    final unsignedUser = career.unsignedDraftRights
        .where((r) => r.owningTeamId == career.userFranchiseId)
        .length;

    return ListView(
      key: const ValueKey('career-market-tab'),
      padding: EdgeInsets.all(t.space300),
      children: [
        if (!isOffseason) ...[
          Container(
            key: const ValueKey('market-phase-restriction-banner'),
            padding: EdgeInsets.all(t.space300),
            decoration: BoxDecoration(
              color: t.accentSecondaryBg,
              borderRadius: BorderRadius.circular(t.radiusMd),
              border: Border.all(
                color: t.accentSecondary.withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              'Transactions are closed during ${CareerUiLabels.phaseName(career.phase)}. '
              'Draft results and the free-agent pool remain available in '
              'read-only mode until Year ${career.currentYear + 1} Offseason.',
              style: TextStyle(
                color: t.accentSecondaryFg,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(height: t.space300),
        ],

        _marketModuleCard(
          context,
          t,
          title: 'Rookie Draft',
          subtitle:
              'Status: ${CareerUiLabels.draftStatus(draft.status)} • '
              '${draft.completedSelectionsCount}/${career.draftOrder.totalPicks} picks complete',
          buttonKey: const ValueKey('market-open-draft'),
          buttonLabel: isOffseason
              ? (draft.isCompleted ? 'View Draft Results' : 'Open Draft Board')
              : 'View Draft Results (Read-Only)',
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => GmDraftBoardScreen(controller: controller),
            ),
          ),
        ),
        SizedBox(height: t.space200),

        _marketModuleCard(
          context,
          t,
          title: 'Rookie Signing',
          subtitle: draft.isCompleted
              ? '$unsignedUser unsigned draft right${unsignedUser == 1 ? '' : 's'} owned by ${career.userTeam.abbreviation}'
              : 'Unlocks after the Rookie Draft completes.',
          buttonKey: const ValueKey('market-open-rookie-signing'),
          buttonLabel: 'Open Rookie Signing',
          onPressed: isOffseason && draft.isCompleted
              ? () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        GmRookieSigningScreen(controller: controller),
                  ),
                )
              : null,
        ),
        SizedBox(height: t.space200),

        _marketModuleCard(
          context,
          t,
          title: 'Free Agency Pool',
          subtitle:
              '${career.freeAgentPool.length} free agents • '
              'Round ${career.freeAgentMarket.roundNumber}',
          buttonKey: const ValueKey('market-open-free-agents'),
          buttonLabel: isOffseason
              ? 'Open Free Agency'
              : 'Inspect Free Agents (Read-Only)',
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => GmFreeAgentsScreen(controller: controller),
            ),
          ),
        ),
        SizedBox(height: t.space200),

        _marketModuleCard(
          context,
          t,
          title: 'Offseason Clearance & Readiness',
          subtitle:
              'League-wide 30-team roster compliance and hardship settlement.',
          buttonKey: const ValueKey('market-open-clearance'),
          buttonLabel: isOffseason
              ? 'Review Clearance'
              : 'View League Readiness',
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => isOffseason
                  ? GmOffseasonClearanceScreen(controller: controller)
                  : GmLeagueReadinessScreen(controller: controller),
            ),
          ),
        ),
      ],
    );
  }

  Widget _marketModuleCard(
    BuildContext context,
    HardwoodCommandTokens t, {
    required String title,
    required String subtitle,
    required Key buttonKey,
    required String buttonLabel,
    required VoidCallback? onPressed,
  }) {
    return Container(
      padding: EdgeInsets.all(t.space300),
      decoration: BoxDecoration(
        color: t.bgSurface,
        borderRadius: BorderRadius.circular(t.radiusLg),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: t.space100),
          Text(
            subtitle,
            style: TextStyle(color: t.textSecondary, fontSize: 13),
          ),
          SizedBox(height: t.space300),
          HardwoodSecondaryButton(
            key: buttonKey,
            label: buttonLabel,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}
