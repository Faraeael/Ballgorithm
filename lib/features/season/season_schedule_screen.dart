import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

class SeasonScheduleScreen extends StatelessWidget {
  const SeasonScheduleScreen({
    super.key,
    required this.league,
    required this.schedule,
    required this.currentRoundNumber,
    required this.userFranchiseId,
  });

  final League league;
  final SeasonSchedule schedule;
  final int currentRoundNumber;
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

    return Scaffold(
      appBar: AppBar(title: const Text('Season Schedule & Results')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12.0),
        itemCount: schedule.rounds.length,
        itemBuilder: (context, index) {
          final round = schedule.rounds[index];
          final isCurrent = round.roundNumber == currentRoundNumber;
          final isCompleted = round.isCompleted;

          return Card(
            key: ValueKey('round-card-${round.roundNumber}'),
            margin: const EdgeInsets.only(bottom: 12.0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isCurrent
                  ? BorderSide(color: theme.colorScheme.primary, width: 2)
                  : BorderSide.none,
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Round ${round.roundNumber}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isCompleted)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'COMPLETED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                          ),
                        )
                      else if (isCurrent)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'CURRENT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 6),
                  for (final fixture in round.fixtures) ...[
                    _buildFixtureRow(context, theme, fixture),
                    const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFixtureRow(
    BuildContext context,
    ThemeData theme,
    SeasonFixture fixture,
  ) {
    final homeAbbr = _teamAbbr(fixture.homeTeamId);
    final awayAbbr = _teamAbbr(fixture.awayTeamId);
    final isUserGame =
        fixture.homeTeamId == userFranchiseId ||
        fixture.awayTeamId == userFranchiseId;

    final summary = fixture.summary;

    return InkWell(
      onTap: summary == null ? null : () => _showBoxScore(context, fixture),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            if (isUserGame) ...[
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
            ] else
              const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$awayAbbr @ $homeAbbr',
                style: TextStyle(
                  fontWeight: isUserGame ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (summary != null) ...[
              Text(
                '${summary.awayScore} - ${summary.homeScore}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 16),
            ] else
              Text(
                'Upcoming',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showBoxScore(BuildContext context, SeasonFixture fixture) {
    final summary = fixture.summary!;
    final homeName = _teamName(fixture.homeTeamId);
    final awayName = _teamName(fixture.awayTeamId);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16.0),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Round ${fixture.roundNumber} Result',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        Text(
                          awayName,
                          style: TextStyle(
                            fontWeight: summary.awayScore > summary.homeScore
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        Text(
                          '${summary.awayScore}',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Text('vs', style: TextStyle(fontSize: 16)),
                    Column(
                      children: [
                        Text(
                          homeName,
                          style: TextStyle(
                            fontWeight: summary.homeScore > summary.awayScore
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        Text(
                          '${summary.homeScore}',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const Text(
                  'Top Scorers',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                for (final line
                    in (summary.playerLines.values.toList()
                          ..sort((a, b) => b.points.compareTo(a.points)))
                        .take(6)) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${line.playerId} (${_teamAbbr(TeamId(line.teamId))}):',
                      ),
                      Text(
                        '${line.points} pts (${line.fgm}/${line.fga} FG, ${line.threePm}/${line.threePa} 3PT)',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
