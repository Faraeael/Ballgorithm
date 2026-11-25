import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import '../../theme/hardwood_command_theme.dart';
import 'career_controller.dart';
import 'career_ui_labels.dart';
import 'draft_board_screen.dart';
import 'free_agents_screen.dart';
import 'offseason_clearance_screen.dart';
import 'play_in_tournament_screen.dart';
import 'playoff_tournament_screen.dart';
import 'regular_season_results_screen.dart';
import 'regular_season_round_screen.dart';
import 'regular_season_schedule_screen.dart';
import 'rookie_signing_screen.dart';
import 'widgets/hardwood_components.dart';

/// Data-driven Career Home dashboard implementing the approved D02 layout.
class CareerHomeScreen extends StatelessWidget {
  const CareerHomeScreen({
    super.key,
    required this.controller,
    required this.onSelectTab,
  });

  final GmCareerController controller;
  final ValueChanged<int> onSelectTab;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final career = controller.career;
    if (career == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final team = career.userTeam;
    final finances = career.finances.financesFor(team.id);
    final capPayroll = career.finances.capPayrollFor(
      team.id,
      career.currentYear,
    );
    final capRoom = FinancialRules.salaryCap - capPayroll;
    final projectedCash = career.finances.projectedEndOfSeasonCash(
      team.id,
      career.currentYear,
    );
    final seasonState = career.regularSeasonState;
    final schedule = seasonState?.schedule;

    return ListView(
      key: const ValueKey('career-home-scroll'),
      padding: EdgeInsets.all(t.space300),
      children: [
        if (controller.errorMessage != null ||
            controller.draftRecoveryRequired) ...[
          _buildErrorBanner(context, t),
          SizedBox(height: t.space300),
        ],

        // 1. Primary Next-Action Hero Card
        _buildNextActionHero(context, t, career),
        SizedBox(height: t.space300),

        if (career.phase == CareerPhase.openingOffseason) ...[
          _buildOffseasonChecklist(t, career),
          SizedBox(height: t.space300),
        ],

        // 2. Roster & Financial Summary Cards
        _buildSummarySection(
          context,
          t,
          career,
          team,
          capPayroll,
          capRoom,
          finances.cash,
          projectedCash,
        ),
        SizedBox(height: t.space300),

        // 3. League Standings Preview (Top 4 of 30)
        _buildStandingsPreview(context, t, career, seasonState),

        // 4. Last Completed Game Strip (if present)
        if (seasonState != null && schedule != null) ...[
          _buildLastGameStrip(context, t, career, seasonState, schedule),
        ],
      ],
    );
  }

  Widget _buildErrorBanner(BuildContext context, HardwoodCommandTokens t) {
    return Container(
      key: const ValueKey('home-storage-error-banner'),
      padding: EdgeInsets.all(t.space300),
      decoration: BoxDecoration(
        color: t.statusDangerBg,
        borderRadius: BorderRadius.circular(t.radiusMd),
        border: Border.all(color: t.statusDanger),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            controller.errorMessage ??
                'A save operation did not complete cleanly. Reload the saved '
                    'career before continuing.',
            style: TextStyle(color: t.textPrimary, fontSize: 13),
          ),
          SizedBox(height: t.space200),
          HardwoodSecondaryButton(
            key: const ValueKey('home-reload-career-button'),
            label: 'Reload Saved Career',
            icon: Icons.refresh,
            onPressed: controller.isLoading
                ? null
                : () => controller.loadCareer(),
          ),
        ],
      ),
    );
  }

  Widget _buildNextActionHero(
    BuildContext context,
    HardwoodCommandTokens t,
    GmCareer career,
  ) {
    final batch = controller.batchProgress;
    if (batch != null) {
      return _buildBatchProgressCard(t, batch);
    }

    final blocked = controller.isLoading || controller.draftRecoveryRequired;
    final action = _resolvePrimaryAction(context, career, blocked: blocked);

    return Container(
      key: const ValueKey('home-next-action-card'),
      decoration: BoxDecoration(
        color: t.bgSurface,
        borderRadius: BorderRadius.circular(t.radiusLg),
        border: Border.all(color: t.borderActive, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: CourtWatermarkPainter(
                lineColor: t.textPrimary.withValues(alpha: 0.05),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(t.space300),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: t.space200,
                          vertical: t.space100,
                        ),
                        decoration: BoxDecoration(
                          color: t.accentPrimaryTint,
                          borderRadius: BorderRadius.circular(t.radiusSm),
                          border: Border.all(
                            color: t.accentPrimary.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          action.badgeLabel.toUpperCase(),
                          style: TextStyle(
                            color: t.accentPrimary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: t.space200),
                    Text(
                      action.statusRight,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: t.space300),
                if (action.matchupWidget != null) ...[
                  action.matchupWidget!,
                  SizedBox(height: t.space300),
                ] else ...[
                  Text(
                    action.description,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: t.space300),
                ],
                HardwoodPrimaryCta(
                  key: const ValueKey('home-primary-cta'),
                  label: action.ctaLabel,
                  icon: Icons.play_arrow_rounded,
                  isBusy: controller.isLoading,
                  onPressed: blocked ? null : action.onPressed,
                ),
                if (action.secondaryButtons.isNotEmpty) ...[
                  SizedBox(height: t.space200),
                  Row(
                    children: [
                      for (
                        var i = 0;
                        i < action.secondaryButtons.length;
                        i++
                      ) ...[
                        if (i > 0) SizedBox(width: t.space200),
                        Expanded(child: action.secondaryButtons[i]),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  _HomePrimaryAction _resolvePrimaryAction(
    BuildContext context,
    GmCareer career, {
    required bool blocked,
  }) {
    final t = context.tokens;
    switch (career.phase) {
      case CareerPhase.openingOffseason:
        final draft = career.draftExecutionState;
        if (draft.isNotStarted) {
          return _HomePrimaryAction(
            badgeLabel: 'Next Action • Rookie Draft',
            statusRight: 'Year ${career.currentYear}',
            description:
                'The ${career.draftOrder.totalPicks}-pick Rookie Draft is ready to begin.',
            ctaLabel: 'Start Rookie Draft',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => GmDraftBoardScreen(controller: controller),
              ),
            ),
          );
        }
        if (draft.isInProgress) {
          return _HomePrimaryAction(
            badgeLabel: 'Next Action • Draft Active',
            statusRight:
                '${draft.completedSelectionsCount}/${career.draftOrder.totalPicks} Picks',
            description: 'Resume the Rookie Draft on the draft board.',
            ctaLabel: 'Continue Draft',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => GmDraftBoardScreen(controller: controller),
              ),
            ),
          );
        }
        final readiness = const OffseasonReadinessGate().evaluate(
          career,
          recoveryRequired: controller.draftRecoveryRequired,
        );
        if (readiness.status == OffseasonReadinessStatus.cleared) {
          return _HomePrimaryAction(
            badgeLabel: 'Next Action • Tip-Off Ready',
            statusRight: '30/30 Teams Ready',
            description:
                'All 30 franchises meet roster and cap rules for Season ${career.currentYear}.',
            ctaLabel: 'Start Regular Season',
            onPressed: () => _confirmStartRegularSeason(context, career),
          );
        }
        final unsignedUser = career.unsignedDraftRights
            .where((r) => r.owningTeamId == career.userFranchiseId)
            .length;
        if (unsignedUser > 0) {
          return _HomePrimaryAction(
            badgeLabel: 'Next Action • Rookie Signing',
            statusRight: '$unsignedUser Unsigned',
            description:
                'Review and sign your drafted rookies or defer draft rights.',
            ctaLabel: 'Manage Rookie Signing',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => GmRookieSigningScreen(controller: controller),
              ),
            ),
          );
        }
        if (const RookieAiSigningService().pendingRights(career).isNotEmpty) {
          return _HomePrimaryAction(
            badgeLabel: 'Next Action • AI Rookie Signing',
            statusRight: 'AI Decisions',
            description:
                'Resolve remaining AI franchise rookie signing decisions.',
            ctaLabel: 'Resolve AI Rookie Signing',
            onPressed: blocked
                ? null
                : () async {
                    try {
                      await controller.advanceAiRookieSigning();
                    } catch (_) {}
                  },
          );
        }
        if (career.offseasonClearance.status !=
            OffseasonClearanceStatus.notStarted) {
          return _HomePrimaryAction(
            badgeLabel: 'Next Action • Clearance',
            statusRight: 'Offseason Gate',
            description:
                'Complete remaining league signings and confirm offseason clearance.',
            ctaLabel: 'Review Offseason Clearance',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) =>
                    GmOffseasonClearanceScreen(controller: controller),
              ),
            ),
          );
        }
        final needsPlayers =
            career.userTeam.roster.standardCount <
                RosterRules.minRegularSeasonStandard ||
            Position.values.any((p) => !career.userTeam.roster.covers(p));
        if (needsPlayers) {
          return _HomePrimaryAction(
            badgeLabel: 'Next Action • Free Agency',
            statusRight: 'Round ${career.freeAgentMarket.roundNumber}',
            description:
                'Sign free agents to reach at least ${RosterRules.minRegularSeasonStandard} standard players across all 5 positions.',
            ctaLabel: 'Resolve Free Agency',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => GmFreeAgentsScreen(controller: controller),
              ),
            ),
          );
        }
        return _HomePrimaryAction(
          badgeLabel: 'Next Action • Clearance',
          statusRight: 'Offseason Gate',
          description:
              'Complete remaining league signings and confirm offseason clearance.',
          ctaLabel: 'Review Offseason Clearance',
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) =>
                  GmOffseasonClearanceScreen(controller: controller),
            ),
          ),
        );

      case CareerPhase.regularSeason:
        final state = career.regularSeasonState!;
        final schedule = state.schedule;
        if (schedule == null) {
          return _HomePrimaryAction(
            badgeLabel: 'Next Action • Schedule',
            statusRight: 'Season ${career.currentYear}',
            description:
                'Generate the deterministic 82-game schedule for all 30 franchises.',
            ctaLabel: 'Generate Schedule',
            onPressed: () async {
              try {
                await controller.generateRegularSeasonSchedule();
              } catch (_) {}
            },
          );
        }
        final nextRound = state.nextUnfinishedRoundNumber;
        if (nextRound == null) {
          return _HomePrimaryAction(
            badgeLabel: 'Regular Season Complete',
            statusRight: '82 / 82 Played',
            description:
                'All 82 rounds are final. Enter the Play-In Tournament to begin postseason play.',
            ctaLabel: 'Enter Play-In',
            onPressed: () => _confirmEnterPlayIn(context),
            secondaryButtons: [
              HardwoodSecondaryButton(
                label: 'Full 82-Game Schedule',
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => RegularSeasonScheduleScreen(career: career),
                  ),
                ),
              ),
            ],
          );
        }
        final nextGame = schedule.nextScheduledGame(career.userFranchiseId);
        Widget? matchupWidget;
        if (nextGame != null) {
          final isHome = nextGame.homeTeamId == career.userFranchiseId;
          final oppId = isHome ? nextGame.awayTeamId : nextGame.homeTeamId;
          final oppTeam = career.league.teams.firstWhere((e) => e.id == oppId);
          final ranked = state.standings.ranked;
          final userRank =
              ranked.indexWhere((r) => r.teamId == career.userFranchiseId) + 1;
          final oppRank = ranked.indexWhere((r) => r.teamId == oppId) + 1;
          final userRow = ranked[userRank - 1];
          final oppRow = ranked[oppRank - 1];
          matchupWidget = Container(
            padding: EdgeInsets.all(t.space200),
            decoration: BoxDecoration(
              color: t.bgCanvas,
              borderRadius: BorderRadius.circular(t.radiusMd),
              border: Border.all(color: t.borderSubtle),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      FranchiseCrestBadge(
                        abbreviation: career.userTeam.abbreviation,
                        size: 30,
                      ),
                      SizedBox(width: t.space200),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${career.userTeam.abbreviation} (${isHome ? 'Home' : 'Away'})',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              state.completedRounds == 0
                                  ? 'Preseason • 0–0'
                                  : '${userRow.wins}–${userRow.losses} • #$userRank of 30',
                              style: TextStyle(
                                color: t.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: EdgeInsets.symmetric(horizontal: t.space200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: t.accentSecondaryBg,
                    borderRadius: BorderRadius.circular(t.radiusSm),
                    border: Border.all(
                      color: t.accentSecondary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'VS',
                    style: TextStyle(
                      color: t.accentSecondaryFg,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              oppTeam.abbreviation,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              state.completedRounds == 0
                                  ? 'Preseason • 0–0'
                                  : '${oppRow.wins}–${oppRow.losses} • #$oppRank of 30',
                              style: TextStyle(
                                color: t.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: t.space200),
                      FranchiseCrestBadge(
                        abbreviation: oppTeam.abbreviation,
                        size: 30,
                        primaryColor: t.bgElevated,
                        accentColor: t.statusWarning,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return _HomePrimaryAction(
          badgeLabel: 'Next Action • Round $nextRound of 82',
          statusRight: '${state.completedRounds} / 82 Played',
          description: 'Simulate Round $nextRound across all 15 matchups.',
          matchupWidget: matchupWidget,
          ctaLabel: 'Simulate Next Round',
          onPressed: blocked
              ? null
              : () => _confirmSimulateRound(context, nextRound),
          secondaryButtons: [
            HardwoodSecondaryButton(
              key: const ValueKey('home-sim-options-button'),
              label: 'Sim Options',
              icon: Icons.fast_forward_rounded,
              onPressed: blocked
                  ? null
                  : () => _openSimulationOptionsSheet(
                      context,
                      nextRound: nextRound,
                      totalRounds: schedule.rounds.length,
                    ),
            ),
            HardwoodSecondaryButton(
              key: const ValueKey('home-round-matchups-button'),
              label: 'Rd $nextRound Matchups',
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => RegularSeasonRoundScreen(
                    career: career,
                    roundNumber: nextRound,
                  ),
                ),
              ),
            ),
            HardwoodSecondaryButton(
              key: const ValueKey('home-full-schedule-button'),
              label: '82-Game Schedule',
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => RegularSeasonScheduleScreen(career: career),
                ),
              ),
            ),
          ],
        );

      case CareerPhase.playIn:
        final state = career.playInState!;
        final completedPlayIn = state.gameResults.length;
        final isComplete =
            state.gameResults.containsKey('${state.seasonId}-playin-g1') &&
            state.gameResults.containsKey('${state.seasonId}-playin-g2') &&
            state.gameResults.containsKey('${state.seasonId}-playin-g3');
        if (isComplete) {
          return _HomePrimaryAction(
            badgeLabel: 'Play-In Complete',
            statusRight: '16 Teams Qualified',
            description: 'All Play-In seeds are locked. Advance to Playoffs.',
            ctaLabel: 'Enter Playoffs',
            onPressed: blocked ? null : () => _confirmEnterPlayoffs(context),
            secondaryButtons: [
              HardwoodSecondaryButton(
                label: 'View Play-In Results',
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PlayInTournamentScreen(controller: controller),
                  ),
                ),
              ),
            ],
          );
        }
        return _HomePrimaryAction(
          badgeLabel: 'Next Action • Play-In',
          statusRight: '$completedPlayIn / 3 Games',
          description:
              'Play-In Tournament is underway to decide the final two playoff seeds.',
          ctaLabel: 'Open Play-In Bracket',
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => PlayInTournamentScreen(controller: controller),
            ),
          ),
        );

      case CareerPhase.playoffs:
        final playoff = career.playoffState!;
        if (playoff.isComplete) {
          final champId = playoff.champion;
          final champTeam = champId == null
              ? null
              : career.league.teams.firstWhere((e) => e.id == champId);
          return _HomePrimaryAction(
            badgeLabel: 'Season ${career.currentYear} Complete',
            statusRight: champTeam == null
                ? 'Champion Crowned'
                : '${champTeam.abbreviation} Champion',
            description: champTeam == null
                ? 'Archive Season ${career.currentYear} and advance to Year ${career.currentYear + 1} Offseason.'
                : '${champTeam.name} won the Season ${career.currentYear} Championship! Archive & continue to Year ${career.currentYear + 1}.',
            ctaLabel: 'Continue to Next Season',
            onPressed: blocked
                ? null
                : () => _confirmContinueNextSeason(context),
            secondaryButtons: [
              HardwoodSecondaryButton(
                label: 'Inspect Playoff Bracket',
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PlayoffTournamentScreen(controller: controller),
                  ),
                ),
              ),
            ],
          );
        }
        final activeRound = playoff.currentRound;
        return _HomePrimaryAction(
          badgeLabel: 'Next Action • Playoffs',
          statusRight: activeRound?.displayName ?? 'Best-of-7',
          description: 'Continue simulating active playoff series.',
          ctaLabel: 'Continue Playoffs',
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => PlayoffTournamentScreen(controller: controller),
            ),
          ),
        );
    }
  }

  Widget _buildSummarySection(
    BuildContext context,
    HardwoodCommandTokens t,
    GmCareer career,
    Team team,
    int capPayroll,
    int capRoom,
    int cash,
    int projectedCash,
  ) {
    final textScale = MediaQuery.textScalerOf(context).scale(14);
    final rosterCard = _buildRosterSummaryCard(t, career, team);
    final financeCard = _buildFinanceSummaryCard(
      t,
      capPayroll,
      capRoom,
      cash,
      projectedCash,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 310 || textScale > 19) {
          return Column(
            children: [
              rosterCard,
              SizedBox(height: t.space200),
              financeCard,
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: rosterCard),
              SizedBox(width: t.space200),
              Expanded(child: financeCard),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOffseasonChecklist(HardwoodCommandTokens t, GmCareer career) {
    final draftDone = career.draftExecutionState.isCompleted;
    final unsignedUser = career.unsignedDraftRights
        .where((r) => r.owningTeamId == career.userFranchiseId)
        .length;
    final rookiesDone = draftDone && unsignedUser == 0;
    final userRosterReady =
        career.userTeam.roster.standardCount >=
            RosterRules.minRegularSeasonStandard &&
        Position.values.every(career.userTeam.roster.covers);
    final readiness = const OffseasonReadinessGate().evaluate(
      career,
      recoveryRequired: controller.draftRecoveryRequired,
    );
    final cleared = readiness.status == OffseasonReadinessStatus.cleared;

    final steps = [
      (label: 'Draft', done: draftDone, active: !draftDone),
      (
        label: 'Sign Rookies',
        done: rookiesDone,
        active: draftDone && !rookiesDone,
      ),
      (
        label: 'Free Agency',
        done: rookiesDone && userRosterReady,
        active: rookiesDone && !userRosterReady,
      ),
      (
        label: 'Clearance',
        done: cleared,
        active: rookiesDone && userRosterReady && !cleared,
      ),
      (label: 'Tip-Off', done: false, active: cleared),
    ];

    return Container(
      key: const ValueKey('home-offseason-checklist'),
      padding: EdgeInsets.all(t.space300),
      decoration: BoxDecoration(
        color: t.bgSurface,
        borderRadius: BorderRadius.circular(t.radiusMd),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OFFSEASON CHECKLIST',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: t.space200),
          Wrap(
            spacing: t.space200,
            runSpacing: t.space200,
            children: [
              for (var i = 0; i < steps.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: steps[i].done
                        ? t.statusSuccessBg
                        : steps[i].active
                        ? t.accentPrimaryTint
                        : t.bgElevated,
                    borderRadius: BorderRadius.circular(t.radiusSm),
                    border: Border.all(
                      color: steps[i].done
                          ? t.statusSuccess
                          : steps[i].active
                          ? t.borderActive
                          : t.borderSubtle,
                    ),
                  ),
                  child: Text(
                    '${i + 1}. ${steps[i].label}${steps[i].done ? ' ✓' : ''}',
                    style: TextStyle(
                      color: steps[i].done
                          ? t.statusSuccessFg
                          : steps[i].active
                          ? t.accentPrimary
                          : t.textMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRosterSummaryCard(
    HardwoodCommandTokens t,
    GmCareer career,
    Team team,
  ) {
    final isOffseason = career.phase == CareerPhase.openingOffseason;
    final maxStd = isOffseason
        ? RosterRules.maxOffseasonStandard
        : RosterRules.maxRegularSeasonStandard;
    final maxTwoWay = isOffseason
        ? RosterRules.maxOffseasonTwoWay
        : RosterRules.maxRegularSeasonTwoWay;
    final std = team.roster.standardCount;
    final twoWay = team.roster.twoWayCount;
    final allPositionsCovered = Position.values.every(team.roster.covers);
    final ready =
        std >= RosterRules.minRegularSeasonStandard && allPositionsCovered;

    return AppPressable(
      onPressed: () => onSelectTab(1),
      semanticLabel: 'Open Team Roster',
      borderRadius: BorderRadius.circular(t.radiusMd),
      child: Container(
        padding: EdgeInsets.all(t.space300),
        decoration: BoxDecoration(
          color: t.bgSurface,
          borderRadius: BorderRadius.circular(t.radiusMd),
          border: Border.all(color: t.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ROSTER STATUS',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            SizedBox(height: t.space100),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '$std / $maxStd Std',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: ready ? t.statusSuccessBg : t.statusWarningBg,
                    borderRadius: BorderRadius.circular(t.radiusSm),
                  ),
                  child: Text(
                    ready ? 'Ready' : 'Needs Fill',
                    style: TextStyle(
                      color: ready ? t.statusSuccessFg : t.statusWarningFg,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: t.space100),
            Text(
              'Min ${RosterRules.minRegularSeasonStandard} Std • $twoWay/$maxTwoWay 2-Way • ${team.players.length} Total',
              style: TextStyle(color: t.textSecondary, fontSize: 11.5),
            ),
            SizedBox(height: t.space200),
            Row(
              children: [
                for (var i = 0; i < Position.values.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    child: _coverageChip(
                      t,
                      Position.values[i].shortName,
                      team.roster.covers(Position.values[i]),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverageChip(HardwoodCommandTokens t, String label, bool covered) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: covered
            ? t.statusSuccess.withValues(alpha: 0.14)
            : t.statusDanger.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: covered
              ? t.statusSuccess.withValues(alpha: 0.35)
              : t.statusDanger.withValues(alpha: 0.55),
        ),
      ),
      child: Text(
        '$label${covered ? '✓' : '!'}',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: covered ? t.statusSuccessFg : t.statusDangerFg,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildFinanceSummaryCard(
    HardwoodCommandTokens t,
    int capPayroll,
    int capRoom,
    int cash,
    int projectedCash,
  ) {
    final positiveRoom = capRoom >= 0;
    return Container(
      padding: EdgeInsets.all(t.space300),
      decoration: BoxDecoration(
        color: t.bgSurface,
        borderRadius: BorderRadius.circular(t.radiusMd),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'FRANCHISE FINANCES',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: t.space100),
          Text(
            positiveRoom ? 'Cap Room' : 'Over Cap',
            style: TextStyle(
              color: t.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '${positiveRoom ? '+' : ''}${CareerUiLabels.formatCu(capRoom)}',
            style: TextStyle(
              color: positiveRoom ? t.statusSuccessFg : t.statusWarningFg,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: t.space100),
          Text(
            'Payroll: ${CareerUiLabels.formatCu(capPayroll)} / 41,000',
            style: TextStyle(color: t.textSecondary, fontSize: 11.5),
          ),
          const SizedBox(height: 2),
          Text(
            'Cash: ${CareerUiLabels.formatCu(cash)}',
            style: TextStyle(color: t.textSecondary, fontSize: 11.5),
          ),
          const SizedBox(height: 2),
          Text(
            'Projected Cash: ${CareerUiLabels.formatCu(projectedCash)}',
            style: TextStyle(color: t.textSecondary, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  Widget _buildStandingsPreview(
    BuildContext context,
    HardwoodCommandTokens t,
    GmCareer career,
    RegularSeasonState? seasonState,
  ) {
    if (seasonState == null) {
      final readiness = LeagueReadinessReport.fromCareer(career);
      return Container(
        key: const ValueKey('home-standings-empty'),
        padding: EdgeInsets.all(t.space300),
        decoration: BoxDecoration(
          color: t.bgSurface,
          borderRadius: BorderRadius.circular(t.radiusLg),
          border: Border.all(color: t.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'LEAGUE READINESS (30 TEAMS)',
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                SizedBox(width: t.space200),
                Text(
                  '${readiness.readyCount}/30 Ready',
                  style: TextStyle(
                    color: t.accentSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            SizedBox(height: t.space200),
            Text(
              'Season ${career.currentYear} Regular Season has not tipped off '
              'yet. League-wide standings will populate after Round 1.',
              style: TextStyle(color: t.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final ranked = seasonState.standings.ranked;
    final top4 = ranked.take(4).toList();
    final userIndex = ranked.indexWhere(
      (r) => r.teamId == career.userFranchiseId,
    );
    final teamsById = {
      for (final franchise in career.league.teams) franchise.id: franchise,
    };

    return Container(
      key: const ValueKey('home-standings-preview'),
      padding: EdgeInsets.all(t.space300),
      decoration: BoxDecoration(
        color: t.bgSurface,
        borderRadius: BorderRadius.circular(t.radiusLg),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  seasonState.completedRounds == 0
                      ? 'PRESEASON STANDINGS (ALL 0–0)'
                      : 'LEAGUE STANDINGS (TOP 4 OF 30)',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              AppPressable(
                minHeight: 32,
                minWidth: 64,
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        RegularSeasonStandingsScreen(career: career),
                  ),
                ),
                child: Text(
                  'Full Table (30) ›',
                  style: TextStyle(
                    color: t.accentSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: t.space200),
          Table(
            columnWidths: const {
              0: FixedColumnWidth(26),
              1: FlexColumnWidth(2.2),
              2: FlexColumnWidth(1.1),
              3: FlexColumnWidth(0.9),
              4: FlexColumnWidth(0.8),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: t.borderSubtle)),
                ),
                children: [
                  _tableHeader(t, '#'),
                  _tableHeader(t, 'TEAM'),
                  _tableHeader(t, 'W–L', alignEnd: true),
                  _tableHeader(t, 'PCT', alignEnd: true),
                  _tableHeader(t, 'STRK', alignEnd: true),
                ],
              ),
              for (var i = 0; i < top4.length; i++)
                _buildStandingRow(
                  t,
                  rank: i + 1,
                  row: top4[i],
                  team: teamsById[top4[i].teamId]!,
                  isUser: top4[i].teamId == career.userFranchiseId,
                ),
              if (userIndex >= 4) ...[
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '···',
                        style: TextStyle(color: t.textMuted, fontSize: 11),
                      ),
                    ),
                    const SizedBox.shrink(),
                    const SizedBox.shrink(),
                    const SizedBox.shrink(),
                    const SizedBox.shrink(),
                  ],
                ),
                _buildStandingRow(
                  t,
                  rank: userIndex + 1,
                  row: ranked[userIndex],
                  team: teamsById[ranked[userIndex].teamId]!,
                  isUser: true,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(
    HardwoodCommandTokens t,
    String text, {
    bool alignEnd = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Text(
        text,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: TextStyle(
          color: t.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  TableRow _buildStandingRow(
    HardwoodCommandTokens t, {
    required int rank,
    required SeasonStanding row,
    required Team team,
    required bool isUser,
  }) {
    final textColor = isUser ? t.accentPrimary : t.textPrimary;
    final weight = isUser ? FontWeight.w800 : FontWeight.w600;
    final pctText = row.gamesPlayed == 0
        ? '.000'
        : row.winPercentage.toStringAsFixed(3).replaceFirst('0.', '.');

    return TableRow(
      decoration: isUser
          ? BoxDecoration(color: t.accentPrimaryTint)
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: t.borderSubtle.withValues(alpha: 0.5),
                ),
              ),
            ),
      children: [
        _cell('$rank', textColor, weight),
        _cell('${team.abbreviation} • ${team.name}', textColor, weight),
        _cell('${row.wins}–${row.losses}', textColor, weight, alignEnd: true),
        _cell(pctText, textColor, weight, alignEnd: true),
        _cell(row.streak, textColor, weight, alignEnd: true),
      ],
    );
  }

  Widget _cell(
    String text,
    Color color,
    FontWeight weight, {
    bool alignEnd = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: TextStyle(color: color, fontSize: 12, fontWeight: weight),
      ),
    );
  }

  Widget _buildLastGameStrip(
    BuildContext context,
    HardwoodCommandTokens t,
    GmCareer career,
    RegularSeasonState state,
    RegularSeasonSchedule schedule,
  ) {
    final lastHuman = schedule.rounds.reversed
        .expand((round) => round.fixtures.reversed)
        .where(
          (f) =>
              f.homeTeamId == career.userFranchiseId ||
              f.awayTeamId == career.userFranchiseId,
        )
        .map((f) => state.gameResults[f.id])
        .whereType<RegularSeasonGameResult>()
        .firstOrNull;
    if (lastHuman == null) return const SizedBox.shrink();

    final home = career.league.teams.firstWhere(
      (e) => e.id == lastHuman.homeTeamId,
    );
    final away = career.league.teams.firstWhere(
      (e) => e.id == lastHuman.awayTeamId,
    );
    final won = lastHuman.summary.winnerTeamId == career.userFranchiseId;

    return Padding(
      padding: EdgeInsets.only(top: t.space300),
      child: AppPressable(
        key: const ValueKey('home-last-game-box-score'),
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => RegularSeasonBoxScoreScreen(
              career: career,
              fixtureId: lastHuman.fixtureId,
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(t.radiusMd),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: t.space300,
            vertical: t.space300,
          ),
          decoration: BoxDecoration(
            color: t.bgSurface,
            borderRadius: BorderRadius.circular(t.radiusMd),
            border: Border.all(color: t.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: won ? t.statusSuccessBg : t.statusDangerBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  won ? 'W' : 'L',
                  style: TextStyle(
                    color: won ? t.statusSuccessFg : t.statusDangerFg,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(width: t.space200),
              Expanded(
                child: Text(
                  'Last Game: ${home.abbreviation} ${lastHuman.summary.homeScore} – '
                  '${lastHuman.summary.awayScore} ${away.abbreviation}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                'Box Score ›',
                style: TextStyle(
                  color: t.accentSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmStartRegularSeason(
    BuildContext context,
    GmCareer career,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start Regular Season?'),
        content: Text(
          'Enter Season ${career.currentYear} (82 games per franchise, '
          '41 home and 41 away). All 30 franchises passed offseason readiness.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('cancel-start-regular-season'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-start-regular-season'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Start Season'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.startRegularSeason(confirmed: true);
    } catch (_) {}
  }

  Future<void> _confirmSimulateRound(
    BuildContext context,
    int roundNumber,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Simulate Round $roundNumber?'),
        content: const Text('Simulate and save all 15 games?'),
        actions: [
          TextButton(
            key: const ValueKey('cancel-start-regular-season'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-simulate-round'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Simulate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.simulateNextRegularSeasonRound(
        expectedRoundNumber: roundNumber,
        confirmed: true,
      );
    } catch (_) {}
  }

  Widget _buildBatchProgressCard(
    HardwoodCommandTokens t,
    BatchSimulationProgress batch,
  ) {
    return Container(
      key: const ValueKey('home-batch-progress-card'),
      padding: EdgeInsets.all(t.space300),
      decoration: BoxDecoration(
        color: t.bgSurface,
        borderRadius: BorderRadius.circular(t.radiusLg),
        border: Border.all(color: t.borderActive, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'SIMULATING ROUNDS ${batch.startRound}–${batch.targetRound}',
                  style: TextStyle(
                    color: t.accentPrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              SizedBox(width: t.space200),
              Text(
                'Rd ${batch.currentRound} / ${batch.targetRound}',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SizedBox(height: t.space200),
          ClipRRect(
            borderRadius: BorderRadius.circular(t.radiusPill),
            child: LinearProgressIndicator(
              key: const ValueKey('batch-progress-bar'),
              value: batch.fraction,
              minHeight: 8,
              backgroundColor: t.bgElevated,
              valueColor: AlwaysStoppedAnimation<Color>(t.accentPrimary),
            ),
          ),
          SizedBox(height: t.space200),
          Text(
            '${batch.roundsCompleted} of ${batch.totalRounds} completed • '
            '${batch.roundsRemaining} remaining',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (batch.latestUserGameSummary != null) ...[
            SizedBox(height: t.space100),
            Text(
              'Latest: ${batch.latestUserGameSummary}',
              style: TextStyle(
                color: t.accentSecondaryFg,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          SizedBox(height: t.space300),
          HardwoodSecondaryButton(
            key: const ValueKey('batch-cancel-button'),
            label: batch.isCancelling
                ? 'Stopping After Current Round…'
                : 'Cancel Simulation',
            icon: Icons.stop_circle_outlined,
            onPressed: batch.isCancelling
                ? null
                : controller.requestCancelBatchSimulation,
          ),
        ],
      ),
    );
  }

  Future<void> _openSimulationOptionsSheet(
    BuildContext context, {
    required int nextRound,
    required int totalRounds,
  }) async {
    final t = context.tokens;
    final remaining = (totalRounds - nextRound + 1).clamp(1, totalRounds);
    final tenCount = remaining.clamp(1, 10);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(t.radiusLg)),
        side: BorderSide(color: t.borderSubtle),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          key: const ValueKey('sim-options-sheet'),
          padding: EdgeInsets.all(t.space400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'REGULAR SEASON SIMULATION',
                style: TextStyle(
                  color: t.accentPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              SizedBox(height: t.space100),
              Text(
                'Each round simulates all 15 scheduled league games, including '
                'your team\'s matchup, and saves progress after every round.',
                style: TextStyle(color: t.textSecondary, fontSize: 13.5),
              ),
              SizedBox(height: t.space300),
              HardwoodPrimaryCta(
                key: const ValueKey('sim-option-next-round'),
                label: 'Simulate Next Round (Rd $nextRound)',
                icon: Icons.play_arrow_rounded,
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _confirmSimulateRound(context, nextRound);
                },
              ),
              SizedBox(height: t.space200),
              HardwoodSecondaryButton(
                key: const ValueKey('sim-option-10-rounds'),
                label:
                    'Simulate Next $tenCount Round${tenCount == 1 ? '' : 's'} '
                    '(Rd $nextRound–${nextRound + tenCount - 1})',
                icon: Icons.fast_forward_rounded,
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _confirmSimulateBatch(
                    context,
                    startRound: nextRound,
                    roundCount: tenCount,
                    totalRounds: totalRounds,
                  );
                },
              ),
              if (remaining > tenCount) ...[
                SizedBox(height: t.space200),
                HardwoodSecondaryButton(
                  key: const ValueKey('sim-option-remaining'),
                  label:
                      'Simulate Remaining Regular Season ($remaining Rounds)',
                  icon: Icons.skip_next_rounded,
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _confirmSimulateBatch(
                      context,
                      startRound: nextRound,
                      roundCount: remaining,
                      totalRounds: totalRounds,
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmSimulateBatch(
    BuildContext context, {
    required int startRound,
    required int roundCount,
    required int totalRounds,
  }) async {
    final endRound = (startRound + roundCount - 1).clamp(
      startRound,
      totalRounds,
    );
    final actualCount = endRound - startRound + 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Simulate $actualCount Round${actualCount == 1 ? '' : 's'}?',
        ),
        content: Text(
          'Simulate Rounds $startRound–$endRound (${actualCount * 15} league '
          'games) sequentially? Each completed round is saved immediately and '
          'can be cancelled between rounds.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('cancel-start-regular-season'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-simulate-batch'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm & Simulate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.simulateRegularSeasonBatch(
        expectedStartRound: startRound,
        roundCount: actualCount,
        confirmed: true,
      );
    } catch (_) {}
  }

  Future<void> _confirmEnterPlayIn(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter Play-In Tournament?'),
        content: const Text(
          'Freeze regular-season records and seed teams 15–18.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('cancel-start-regular-season'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-enter-play-in'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enter Play-In'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.enterPlayIn(confirmed: true);
    } catch (_) {}
  }

  Future<void> _confirmEnterPlayoffs(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter Playoffs?'),
        content: const Text(
          'Lock the 16-team playoff bracket and begin Round 1.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('cancel-start-regular-season'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-enter-playoffs'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enter Playoffs'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.enterPlayoffs(confirmed: true);
    } catch (_) {}
  }

  Future<void> _confirmContinueNextSeason(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start Next Season?'),
        content: const Text(
          'The completed season will be archived and the next season\'s '
          'offseason will begin.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('cancel-start-regular-season'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-next-season'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm & Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.continueToNextSeason(confirmed: true);
    } catch (_) {}
  }
}

class _HomePrimaryAction {
  const _HomePrimaryAction({
    required this.badgeLabel,
    required this.statusRight,
    required this.description,
    required this.ctaLabel,
    required this.onPressed,
    this.matchupWidget,
    this.secondaryButtons = const [],
  });

  final String badgeLabel;
  final String statusRight;
  final String description;
  final String ctaLabel;
  final VoidCallback? onPressed;
  final Widget? matchupWidget;
  final List<Widget> secondaryButtons;
}
