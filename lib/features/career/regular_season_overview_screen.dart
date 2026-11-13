import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

class RegularSeasonOverviewScreen extends StatelessWidget {
  const RegularSeasonOverviewScreen({super.key, required this.career});

  final GmCareer career;

  @override
  Widget build(BuildContext context) {
    final team = career.userTeam;
    final finances = career.finances.financesFor(team.id);
    final payroll = career.finances.capPayrollFor(team.id, career.currentYear);
    final projectedCash = career.finances.projectedEndOfSeasonCash(
      team.id,
      career.currentYear,
    );
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
                  const Text('Record: 0 wins, 0 losses'),
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
          const SizedBox(height: 8),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Schedule not generated yet'),
                  SizedBox(height: 8),
                  Text(
                    'Schedule generation and game simulation are planned for '
                    'M009-T02. No games have been played.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
