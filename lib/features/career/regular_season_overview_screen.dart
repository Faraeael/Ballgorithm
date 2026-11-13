import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'career_controller.dart';
import 'regular_season_schedule_screen.dart';

class RegularSeasonOverviewScreen extends StatelessWidget {
  const RegularSeasonOverviewScreen({super.key, required this.controller});

  final GmCareerController controller;

  @override
  Widget build(BuildContext context) {
    final career = controller.career;
    if (career == null) throw StateError('GM Career is not loaded');
    final team = career.userTeam;
    final finances = career.finances.financesFor(team.id);
    final payroll = career.finances.capPayrollFor(team.id, career.currentYear);
    final projectedCash = career.finances.projectedEndOfSeasonCash(
      team.id,
      career.currentYear,
    );
    final schedule = career.regularSeasonState?.schedule;
    final teamFixtures =
        schedule?.fixturesForTeam(team.id).toList(growable: false) ?? const [];
    final teamsById = {
      for (final franchise in career.league.teams)
        franchise.id.value: franchise,
    };
    final nextGame = schedule?.nextScheduledGame(team.id);
    final nextOpponentId = nextGame == null
        ? null
        : nextGame.homeTeamId == team.id
        ? nextGame.awayTeamId
        : nextGame.homeTeamId;

    return Scaffold(
      appBar: AppBar(title: const Text('Regular Season')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    team.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('Season ${career.currentYear} • Regular season'),
                  Text(
                    '${team.roster.standardCount} standard • '
                    '${team.roster.twoWayCount} two-way players',
                  ),
                  const SizedBox(height: 8),
                  const Text('Record: 0–0'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            key: const ValueKey('card-regular-season-schedule'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Regular-season schedule',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (schedule == null) ...[
                    const Text('Schedule not generated'),
                    const SizedBox(height: 8),
                    const Text(
                      'Generate the approved 82-game calendar. '
                      'No games will be simulated.',
                    ),
                    if (controller.draftRecoveryRequired) ...[
                      const SizedBox(height: 12),
                      FilledButton(
                        key: const ValueKey('btn-schedule-reload'),
                        onPressed: controller.isLoading
                            ? null
                            : () => controller.loadCareer(),
                        child: const Text('Reload Saved Career'),
                      ),
                    ] else ...[
                      if (controller.isLoading)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(
                            key: ValueKey('schedule-generation-progress'),
                          ),
                        ),
                      const SizedBox(height: 12),
                      FilledButton(
                        key: const ValueKey('btn-generate-schedule'),
                        onPressed: controller.isLoading
                            ? null
                            : () => _generateSchedule(context),
                        child: Text(
                          controller.isLoading
                              ? 'Generating Schedule…'
                              : 'Generate Schedule',
                        ),
                      ),
                    ],
                  ] else ...[
                    Text('Games scheduled: ${teamFixtures.length}'),
                    if (nextGame != null && nextOpponentId != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Next opponent: '
                        '${teamsById[nextOpponentId.value]?.name ?? nextOpponentId.value}',
                      ),
                      Text(
                        '${nextGame.homeTeamId == team.id ? 'Home' : 'Away'} '
                        '• Round ${nextGame.roundNumber}',
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Upcoming five',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    for (final fixture in teamFixtures.take(5))
                      Text(_fixtureLabel(fixture, team.id, teamsById)),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      key: const ValueKey('btn-view-full-schedule'),
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              RegularSeasonScheduleScreen(career: career),
                        ),
                      ),
                      child: const Text('View Full Schedule'),
                    ),
                  ],
                  if (controller.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        controller.errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Franchise finances',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('Current cash: ${finances.cash} CU'),
                  Text('Season payroll: $payroll CU'),
                  Text('Projected year-end cash: $projectedCash CU'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fixtureLabel(
    RegularSeasonFixture fixture,
    TeamId teamId,
    Map<String, Team> teamsById,
  ) {
    final atHome = fixture.homeTeamId == teamId;
    final opponentId = atHome ? fixture.awayTeamId : fixture.homeTeamId;
    final opponentName = teamsById[opponentId.value]?.name ?? opponentId.value;
    return 'Round ${fixture.roundNumber} • '
        '${atHome ? 'Home vs' : 'Away at'} $opponentName • Scheduled';
  }

  Future<void> _generateSchedule(BuildContext context) async {
    try {
      await controller.generateRegularSeasonSchedule();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}
