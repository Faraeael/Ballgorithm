import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import '../roster/roster_screen.dart';

class LeagueScreen extends StatelessWidget {
  const LeagueScreen({super.key, required this.league});

  final League league;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Basketball Manager')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(league.name, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  '${league.teams.length} teams · seed ${league.config.seed}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          for (final team in league.teams)
            ListTile(
              key: ValueKey('team-${team.id.value}'),
              leading: _AbbreviationBadge(abbreviation: team.abbreviation),
              title: Text(team.name),
              subtitle: Text('${team.players.length} players'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => RosterScreen(team: team),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AbbreviationBadge extends StatelessWidget {
  const _AbbreviationBadge({required this.abbreviation});

  final String abbreviation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: Text(
        abbreviation,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
