import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import '../../theme/hardwood_command_theme.dart';
import 'career_controller.dart';
import 'career_season_detail_screen.dart';
import 'career_ui_labels.dart';
import 'widgets/hardwood_components.dart';

/// Career destination showing franchise legacy summary, trophy cabinet,
/// tappable completed-season history, and current career identity.
class CareerCareerTab extends StatelessWidget {
  const CareerCareerTab({
    super.key,
    required this.controller,
    required this.onReturnToMainMenu,
  });

  final GmCareerController controller;
  final VoidCallback onReturnToMainMenu;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final career = controller.career;
    if (career == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final teamsById = {for (final team in career.league.teams) team.id: team};
    final history = career.seasonHistory;
    final championships = history
        .where((r) => r.championTeamId == career.userFranchiseId)
        .length;

    var totalWins = 0;
    var totalLosses = 0;
    var playoffApps = 0;
    SeasonHistoryRecord? bestRecordSeason;
    SeasonStandingSummary? bestStanding;

    for (final record in history) {
      final standing = record.regularSeasonStandings
          .cast<SeasonStandingSummary?>()
          .firstWhere(
            (s) => s?.teamId == career.userFranchiseId,
            orElse: () => null,
          );
      if (standing != null) {
        totalWins += standing.wins;
        totalLosses += standing.losses;
        if (bestStanding == null ||
            standing.wins > bestStanding.wins ||
            (standing.wins == bestStanding.wins &&
                standing.rank < bestStanding.rank)) {
          bestStanding = standing;
          bestRecordSeason = record;
        }
      }
      final madePlayoffs = record.playoffSeries.any(
        (s) =>
            s.firstTeamId == career.userFranchiseId ||
            s.secondTeamId == career.userFranchiseId,
      );
      if (madePlayoffs) playoffApps++;
    }

    final totalGames = totalWins + totalLosses;
    final winPctText = totalGames == 0
        ? '—'
        : (totalWins / totalGames).toStringAsFixed(3).replaceFirst('0.', '.');

    return ListView(
      key: const ValueKey('career-career-tab'),
      padding: EdgeInsets.all(t.space300),
      children: [
        // Franchise Legacy & Trophy Cabinet Summary
        Container(
          key: const ValueKey('career-legacy-card'),
          padding: EdgeInsets.all(t.space300),
          decoration: BoxDecoration(
            color: t.bgSurface,
            borderRadius: BorderRadius.circular(t.radiusLg),
            border: Border.all(
              color: championships > 0 ? t.borderActive : t.borderSubtle,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.emoji_events_rounded,
                    color: championships > 0
                        ? t.accentPrimary
                        : t.accentSecondary,
                    size: 20,
                  ),
                  SizedBox(width: t.space200),
                  Expanded(
                    child: Text(
                      'FRANCHISE LEGACY & TROPHY CABINET',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: t.space300),
              Wrap(
                spacing: t.space400,
                runSpacing: t.space200,
                children: [
                  _metric(t, 'Seasons Completed', '${history.length}'),
                  _metric(
                    t,
                    'Championships',
                    '$championships',
                    valueColor: championships > 0
                        ? t.accentPrimary
                        : t.textPrimary,
                  ),
                  _metric(
                    t,
                    'All-Time Record',
                    history.isEmpty
                        ? '0–0'
                        : '$totalWins–$totalLosses ($winPctText)',
                  ),
                  _metric(t, 'Playoff Appearances', '$playoffApps'),
                  if (bestStanding != null && bestRecordSeason != null)
                    _metric(
                      t,
                      'Best Season',
                      '${bestStanding.wins}–${bestStanding.losses} (#${bestStanding.rank}, Yr ${bestRecordSeason.seasonYear})',
                    ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: t.space300),

        // Recorded Season History
        Container(
          key: const ValueKey('career-history-section'),
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
                      'SEASON HISTORY',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  SizedBox(width: t.space200),
                  Text(
                    '${history.length} Completed',
                    style: TextStyle(
                      color: t.accentSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              SizedBox(height: t.space200),
              if (history.isEmpty)
                Container(
                  key: const ValueKey('career-empty-trophy-cabinet'),
                  padding: EdgeInsets.all(t.space300),
                  decoration: BoxDecoration(
                    color: t.bgElevated,
                    borderRadius: BorderRadius.circular(t.radiusMd),
                    border: Border.all(color: t.borderSubtle),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.emoji_events_outlined,
                        color: t.textMuted,
                        size: 28,
                      ),
                      SizedBox(width: t.space300),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Trophy Cabinet Empty',
                              style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Unfinished seasons are not counted. Complete Season '
                              '${career.currentYear} (Regular Season, Play-In, and '
                              'Playoffs) to archive your franchise record and '
                              'league champion.',
                              style: TextStyle(
                                color: t.textSecondary,
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                for (final record in history.reversed)
                  _historyTile(context, t, career, record, teamsById),
            ],
          ),
        ),
        SizedBox(height: t.space300),

        // Current Career Identity Card
        Container(
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
                'CURRENT CAREER IDENTITY',
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              SizedBox(height: t.space200),
              _infoRow(
                t,
                'Franchise',
                '${career.userTeam.name} (${career.userTeam.abbreviation})',
              ),
              _infoRow(t, 'Current Season', 'Season ${career.currentYear}'),
              _infoRow(
                t,
                'Current Phase',
                CareerUiLabels.phaseName(career.phase),
              ),
              _infoRow(
                t,
                'Starting Situation',
                career.originalSituation.displayName,
              ),
              _infoRow(t, 'Career Seed', '${career.generationSeed}'),
              _infoRow(
                t,
                'Save Storage',
                controller.draftRecoveryRequired
                    ? 'Recovery Required (Reload Needed)'
                    : 'Offline Local Save',
              ),
            ],
          ),
        ),
        SizedBox(height: t.space300),

        HardwoodSecondaryButton(
          key: const ValueKey('career-tab-main-menu-button'),
          label: 'Return to Main Menu',
          icon: Icons.home_outlined,
          onPressed: controller.isLoading || controller.isBatchSimulating
              ? null
              : onReturnToMainMenu,
        ),
      ],
    );
  }

  Widget _metric(
    HardwoodCommandTokens t,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: t.textMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? t.textPrimary,
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _infoRow(HardwoodCommandTokens t, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: t.space300),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTile(
    BuildContext context,
    HardwoodCommandTokens t,
    GmCareer career,
    SeasonHistoryRecord record,
    Map<TeamId, Team> teamsById,
  ) {
    final userStanding = record.regularSeasonStandings
        .cast<SeasonStandingSummary?>()
        .firstWhere(
          (entry) => entry?.teamId == career.userFranchiseId,
          orElse: () => null,
        );
    final championName =
        teamsById[record.championTeamId]?.name ?? record.championTeamId.value;
    final userWon = record.championTeamId == career.userFranchiseId;
    final playoffResult = describePlayoffOutcome(
      record,
      career.userFranchiseId,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: t.space200),
      child: AppPressable(
        key: ValueKey('career-history-season-${record.seasonYear}'),
        minHeight: t.touchMin,
        semanticLabel: 'Inspect Season ${record.seasonYear} history',
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => CareerSeasonDetailScreen(
              controller: controller,
              record: record,
              teamsById: teamsById,
              userTeamId: career.userFranchiseId,
            ),
          ),
        ),
        child: Container(
          padding: EdgeInsets.all(t.space300),
          decoration: BoxDecoration(
            color: userWon ? t.accentPrimaryTint : t.bgElevated,
            borderRadius: BorderRadius.circular(t.radiusMd),
            border: Border.all(
              color: userWon ? t.borderActive : t.borderSubtle,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.emoji_events_rounded,
                color: userWon ? t.accentPrimary : t.textMuted,
                size: 22,
              ),
              SizedBox(width: t.space300),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Season ${record.seasonYear} • $playoffResult',
                      style: TextStyle(
                        color: userWon ? t.accentPrimary : t.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Champion: $championName',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (userStanding != null)
                      Text(
                        '${career.userTeam.abbreviation}: '
                        '${userStanding.wins}–${userStanding.losses} '
                        '(#${userStanding.rank} of 30)',
                        style: TextStyle(
                          color: t.accentSecondaryFg,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: t.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
