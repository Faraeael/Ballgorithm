import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import '../../theme/hardwood_command_theme.dart';
import 'career_controller.dart';
import 'career_ui_labels.dart';
import 'league_readiness_screen.dart';
import 'play_in_tournament_screen.dart';
import 'playoff_tournament_screen.dart';
import 'regular_season_results_screen.dart';
import 'regular_season_schedule_screen.dart';
import 'widgets/hardwood_components.dart';

/// League destination connecting implemented standings, schedule, results,
/// and postseason inspection.
class CareerLeagueTab extends StatelessWidget {
  const CareerLeagueTab({super.key, required this.controller});

  final GmCareerController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final career = controller.career;
    if (career == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final season = career.regularSeasonState;
    final readiness = LeagueReadinessReport.fromCareer(career);

    return ListView(
      key: const ValueKey('career-league-tab'),
      padding: EdgeInsets.all(t.space300),
      children: [
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
                'SEASON ${career.currentYear} • ${CareerUiLabels.phaseName(career.phase).toUpperCase()}',
                style: TextStyle(
                  color: t.accentSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              SizedBox(height: t.space200),
              if (season == null) ...[
                Text(
                  'Regular season standings and schedule unlock after offseason '
                  'clearance and tip-off.',
                  style: TextStyle(color: t.textSecondary, fontSize: 13.5),
                ),
                SizedBox(height: t.space300),
                HardwoodSecondaryButton(
                  key: const ValueKey('league-open-readiness'),
                  label:
                      'View 30-Team Readiness (${readiness.readyCount}/30 Ready)',
                  icon: Icons.fact_check_outlined,
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          GmLeagueReadinessScreen(controller: controller),
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  season.schedule == null
                      ? 'Regular season active — schedule has not been generated yet.'
                      : 'Completed rounds: ${season.completedRounds} of 82 • '
                            'Games played: ${season.completedGames}',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: t.space300),
                HardwoodSecondaryButton(
                  key: const ValueKey('league-open-standings'),
                  label: '30-Team League Standings',
                  icon: Icons.leaderboard_outlined,
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          RegularSeasonStandingsScreen(career: career),
                    ),
                  ),
                ),
                if (season.schedule != null) ...[
                  SizedBox(height: t.space200),
                  HardwoodSecondaryButton(
                    key: const ValueKey('league-open-schedule'),
                    label: 'Full 82-Game Schedule',
                    icon: Icons.calendar_month_outlined,
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            RegularSeasonScheduleScreen(career: career),
                      ),
                    ),
                  ),
                ],
                if (season.gameResults.isNotEmpty) ...[
                  SizedBox(height: t.space200),
                  HardwoodSecondaryButton(
                    key: const ValueKey('league-open-results'),
                    label: 'League Game Results & Box Scores',
                    icon: Icons.receipt_long_outlined,
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            RegularSeasonResultsScreen(career: career),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        SizedBox(height: t.space300),

        // Postseason Section
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
                'POSTSEASON',
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              SizedBox(height: t.space200),
              if (career.phase == CareerPhase.playIn)
                HardwoodPrimaryCta(
                  key: const ValueKey('league-open-play-in'),
                  label: 'Open Play-In Tournament',
                  icon: Icons.emoji_events_outlined,
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PlayInTournamentScreen(controller: controller),
                    ),
                  ),
                )
              else if (career.phase == CareerPhase.playoffs)
                HardwoodPrimaryCta(
                  key: const ValueKey('league-open-playoffs'),
                  label: 'Open Playoff Bracket',
                  icon: Icons.emoji_events_outlined,
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PlayoffTournamentScreen(controller: controller),
                    ),
                  ),
                )
              else
                Text(
                  'Play-In (seeds 15–18) and the 16-team Best-of-7 Playoffs '
                  'begin after Round 82 of the Regular Season.',
                  style: TextStyle(color: t.textSecondary, fontSize: 13),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
