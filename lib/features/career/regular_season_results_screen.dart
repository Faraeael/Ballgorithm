import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

class RegularSeasonResultsScreen extends StatelessWidget {
  const RegularSeasonResultsScreen({super.key, required this.career});
  final GmCareer career;

  @override
  Widget build(BuildContext context) {
    final state = career.regularSeasonState!;
    final fixtures = state.schedule!.rounds.expand((r) => r.fixtures).toList();
    final teams = {for (final t in career.league.teams) t.id.value: t.name};
    return Scaffold(
      appBar: AppBar(title: const Text('League Results')),
      body: ListView.builder(
        itemCount: fixtures.length,
        itemBuilder: (context, i) {
          final f = fixtures[i];
          final result = state.gameResults[f.id];
          return ListTile(
            title: Text(
              '${teams[f.homeTeamId.value]} vs ${teams[f.awayTeamId.value]}',
            ),
            subtitle: Text('Round ${f.roundNumber}'),
            trailing: Text(
              result == null
                  ? 'Scheduled'
                  : 'Final ${result.summary.homeScore}–${result.summary.awayScore}',
            ),
            onTap: result == null
                ? null
                : () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RegularSeasonBoxScoreScreen(
                        career: career,
                        fixtureId: f.id,
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }
}

class RegularSeasonBoxScoreScreen extends StatelessWidget {
  const RegularSeasonBoxScoreScreen({
    super.key,
    required this.career,
    required this.fixtureId,
  });
  final GmCareer career;
  final String fixtureId;

  @override
  Widget build(BuildContext context) {
    final result = career.regularSeasonState!.gameResults[fixtureId]!;
    final summary = result.summary;
    final teams = {for (final t in career.league.teams) t.id.value: t.name};
    final home = teams[result.homeTeamId.value] ?? result.homeTeamId.value;
    final away = teams[result.awayTeamId.value] ?? result.awayTeamId.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Box Score')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            '$away ${summary.awayScore} – ${summary.homeScore} $home',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          for (final label in summary.periodScoresHome.keys)
            ListTile(
              title: Text(label),
              trailing: Text(
                '${summary.periodScoresAway[label]} – ${summary.periodScoresHome[label]}',
              ),
            ),
          const Divider(),
          for (final line in summary.playerLines.values)
            ListTile(
              title: Text(
                career.league.teams
                        .expand((team) => team.roster.players)
                        .where((player) => player.id.value == line.playerId)
                        .map((player) => player.fullName)
                        .firstOrNull ??
                    line.playerId,
              ),
              subtitle: Text(
                '${teams[line.teamId] ?? line.teamId} • ${line.secondsPlayed ~/ 60} min\n'
                'FG ${line.fgm}/${line.fga} • 3P ${line.threePm}/${line.threePa} • '
                'FT ${line.ftm}/${line.fta} • REB ${line.rebounds} '
                '(O ${line.oreb}, D ${line.dreb})\n'
                'AST ${line.assists} • STL ${line.steals} • BLK ${line.blocks} • '
                'TO ${line.turnovers} • PF ${line.personalFouls}',
              ),
              trailing: Text('${line.points} PTS'),
            ),
        ],
      ),
    );
  }
}

class RegularSeasonStandingsScreen extends StatelessWidget {
  const RegularSeasonStandingsScreen({super.key, required this.career});
  final GmCareer career;

  @override
  Widget build(BuildContext context) {
    final state = career.regularSeasonState!;
    final teams = {for (final t in career.league.teams) t.id.value: t.name};
    final table = state.standings.ranked;
    return Scaffold(
      appBar: AppBar(title: const Text('Standings')),
      body: ListView.builder(
        itemCount: table.length,
        itemBuilder: (context, i) {
          final row = table[i];
          return ListTile(
            leading: Text('${i + 1}'),
            title: Text(teams[row.teamId.value] ?? row.teamId.value),
            subtitle: Text(
              'GP ${row.gamesPlayed} • ${row.wins}-${row.losses} • PF ${row.pointsFor} • PA ${row.pointsAgainst} • Diff ${row.pointDifferential}',
            ),
            trailing: Text(
              '${(row.winPercentage * 100).toStringAsFixed(1)}%\n${row.streak}',
            ),
          );
        },
      ),
    );
  }
}
