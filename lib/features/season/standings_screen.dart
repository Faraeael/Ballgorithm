import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

class StandingsScreen extends StatelessWidget {
  const StandingsScreen({
    super.key,
    required this.league,
    required this.standings,
    required this.userFranchiseId,
  });

  final League league;
  final LeagueStandings standings;
  final TeamId userFranchiseId;

  String _teamAbbr(TeamId id) {
    for (final t in league.teams) {
      if (t.id == id) return t.abbreviation;
    }
    return id.value;
  }

  String _teamName(TeamId id) {
    for (final t in league.teams) {
      if (t.id == id) return t.name;
    }
    return id.value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ranked = standings.ranked;

    return Scaffold(
      appBar: AppBar(title: const Text('League Standings')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row
              Container(
                color: theme.colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 10.0,
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '#',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Team',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(
                      width: 28,
                      child: Text(
                        'W',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(
                      width: 28,
                      child: Text(
                        'L',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        'PCT',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        'DIFF',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        'STRK',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              // Team Rows
              for (var i = 0; i < ranked.length; i++) ...[
                _buildRow(context, theme, i + 1, ranked[i]),
                const Divider(height: 1),
              ],
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Tie-break rules: 1. Wins  2. Point Differential  3. Points Scored  4. Team ID',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    ThemeData theme,
    int rank,
    SeasonStanding standing,
  ) {
    final isUser = standing.teamId == userFranchiseId;
    final rowColor = isUser
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
        : Colors.transparent;

    final pctStr = standing.gamesPlayed == 0
        ? '.000'
        : standing.winPercentage.toStringAsFixed(3).replaceFirst('0.', '.');

    final diffStr = standing.pointDifferential > 0
        ? '+${standing.pointDifferential}'
        : '${standing.pointDifferential}';

    return Container(
      key: ValueKey('standings-row-${standing.teamId.value}'),
      color: rowColor,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: TextStyle(
                fontWeight: isUser ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Text(
                  _teamAbbr(standing.teamId),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isUser ? theme.colorScheme.primary : null,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _teamName(standing.teamId),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isUser ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '${standing.wins}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: isUser ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '${standing.losses}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: isUser ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              pctStr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isUser ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              diffStr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: standing.pointDifferential > 0
                    ? Colors.green.shade700
                    : (standing.pointDifferential < 0
                          ? Colors.red.shade700
                          : null),
                fontWeight: isUser ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              standing.streak,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isUser ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
