import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'regular_season_results_screen.dart';

class RegularSeasonRoundScreen extends StatelessWidget {
  const RegularSeasonRoundScreen({
    super.key,
    required this.career,
    required this.roundNumber,
  });

  final GmCareer career;
  final int roundNumber;

  @override
  Widget build(BuildContext context) {
    final state = career.regularSeasonState!;
    final round = state.schedule!.rounds.firstWhere(
      (round) => round.roundNumber == roundNumber,
    );
    final teams = {
      for (final team in career.league.teams) team.id.value: team.name,
    };
    return Scaffold(
      appBar: AppBar(title: Text('Round $roundNumber')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: round.fixtures.length,
        itemBuilder: (context, index) {
          final fixture = round.fixtures[index];
          final result = state.gameResults[fixture.id];
          return Card(
            child: ListTile(
              title: Text(
                '${teams[fixture.homeTeamId.value] ?? fixture.homeTeamId.value} '
                'vs ${teams[fixture.awayTeamId.value] ?? fixture.awayTeamId.value}',
              ),
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
                          fixtureId: fixture.id,
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}
