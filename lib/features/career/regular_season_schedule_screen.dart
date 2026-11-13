import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

class RegularSeasonScheduleScreen extends StatelessWidget {
  const RegularSeasonScheduleScreen({super.key, required this.career});

  final GmCareer career;

  @override
  Widget build(BuildContext context) {
    final schedule = career.regularSeasonState?.schedule;
    if (schedule == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Team Schedule')),
        body: const Center(child: Text('Schedule not generated')),
      );
    }
    final team = career.userTeam;
    final fixtures = schedule.fixturesForTeam(team.id).toList(growable: false);
    final teamsById = {
      for (final franchise in career.league.teams)
        franchise.id.value: franchise,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Team Schedule')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: fixtures.length,
        itemBuilder: (context, index) {
          final fixture = fixtures[index];
          final atHome = fixture.homeTeamId == team.id;
          final opponentId = atHome ? fixture.awayTeamId : fixture.homeTeamId;
          final opponent = teamsById[opponentId.value];
          return Card(
            key: ValueKey('schedule-fixture-${fixture.id}'),
            child: ListTile(
              title: Text(opponent?.name ?? opponentId.value),
              subtitle: Text(
                'Round ${fixture.roundNumber} • ${atHome ? 'Home' : 'Away'}',
              ),
              trailing: Text(fixture.status.jsonValue),
            ),
          );
        },
      ),
    );
  }
}
