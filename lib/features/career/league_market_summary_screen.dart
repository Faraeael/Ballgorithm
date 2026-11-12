import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'career_controller.dart';

/// Read-only league market and acquisition summary.
class GmLeagueMarketSummaryScreen extends StatelessWidget {
  const GmLeagueMarketSummaryScreen({super.key, required this.controller});

  final GmCareerController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final career = controller.career;
      if (career == null) {
        return const Scaffold(body: Center(child: Text('No active career')));
      }
      final acquisitions =
          career.freeAgentPool.acquisitions.entries.values.toList()
            ..sort((a, b) => a.transactionId.compareTo(b.transactionId));
      final readiness = LeagueReadinessReport.fromCareer(career);
      final ready = readiness.teams.where((team) => team.isReady).length;
      return Scaffold(
        key: const ValueKey('league-market-summary'),
        appBar: AppBar(title: const Text('League Market Summary')),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Rounds completed: ${career.freeAgentMarket.completedRounds} • '
                  'Acquisitions: ${acquisitions.length} • '
                  'Available: ${career.freeAgentPool.length} • '
                  'Ready: $ready/30',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('Completed acquisitions', style: _heading(context)),
            for (final record in acquisitions)
              ListTile(
                dense: true,
                title: Text(
                  '${_playerName(career, record.playerId)} → '
                  '${_teamAbbreviation(career, record.teamId)}',
                ),
                subtitle: Text(
                  '${record.category == RosterCategory.twoWay ? 'Two-way' : 'Standard'} '
                  '${record.seasonYear} • ${record.transactionId}',
                ),
              ),
            const SizedBox(height: 12),
            Text('Franchise obligations', style: _heading(context)),
            for (final team in career.league.teams)
              ListTile(
                dense: true,
                title: Text(
                  '${team.abbreviation} • '
                  '${team.roster.standardCount} standard / '
                  '${team.roster.twoWayCount} two-way',
                ),
                subtitle: Text(
                  'Cap payroll '
                  '${career.finances.capPayrollFor(team.id, career.currentYear)} CU • '
                  'Cash payroll '
                  '${career.finances.cashPayrollFor(team.id, career.currentYear)} CU • '
                  '${readiness.teams.firstWhere((row) => row.teamId == team.id).isReady ? 'Ready' : 'Below readiness'}',
                ),
              ),
          ],
        ),
      );
    },
  );

  static TextStyle? _heading(BuildContext context) => Theme.of(
    context,
  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold);

  static String _playerName(GmCareer career, PlayerId id) {
    for (final team in career.league.teams) {
      for (final player in team.players) {
        if (player.id == id) return player.fullName;
      }
    }
    return career.freeAgentPool.byId(id)?.player.fullName ?? id.value;
  }

  static String _teamAbbreviation(GmCareer career, TeamId id) =>
      career.league.teams.firstWhere((team) => team.id == id).abbreviation;
}
