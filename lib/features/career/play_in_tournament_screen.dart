import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'career_controller.dart';

class PlayInTournamentScreen extends StatelessWidget {
  const PlayInTournamentScreen({super.key, required this.controller});

  final GmCareerController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final career = controller.career;
      if (career?.phase == CareerPhase.playoffs) {
        // Transient frame after enterPlayoffs; the screen pops back to the shell.
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (career == null ||
          career.phase != CareerPhase.playIn ||
          career.playInState == null) {
        throw StateError('Play-In career is not loaded');
      }
      final state = career.playInState!;
      final season = career.regularSeasonState!;
      final teams = {
        for (final team in season.openingTeams) team.teamId.value: team.name,
      };
      final nextGame = _nextGame(state, season.scheduleSeed);
      return Scaffold(
        appBar: AppBar(title: const Text('Play-In Tournament')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Season ${state.seasonYear}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _qualificationCard(context, state, teams),
            const SizedBox(height: 12),
            for (var number = 1; number <= 3; number++) ...[
              _gameCard(context, career, state, number, teams),
              const SizedBox(height: 8),
            ],
            if (controller.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                controller.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (nextGame != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                key: ValueKey('simulate-play-in-${nextGame.id}'),
                onPressed:
                    controller.isLoading || controller.draftRecoveryRequired
                    ? null
                    : () => _confirmAndSimulate(context, nextGame),
                icon: controller.isLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sports_basketball),
                label: Text('Play Game ${nextGame.gameNumber}'),
              ),
            ] else ...[
              const SizedBox(height: 12),
              const Text('Play-In complete — 16 playoff teams qualified.'),
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('btn-enter-playoffs'),
                onPressed:
                    controller.isLoading || controller.draftRecoveryRequired
                    ? null
                    : () => _confirmAndEnterPlayoffs(context),
                child: Text(
                  controller.isLoading ? 'Saving…' : 'Enter Playoffs',
                ),
              ),
            ],
            if (controller.draftRecoveryRequired)
              TextButton(
                key: const ValueKey('btn-play-in-reload'),
                onPressed: controller.isLoading
                    ? null
                    : () => controller.loadCareer(),
                child: const Text('Reload Saved Career'),
              ),
          ],
        ),
      );
    },
  );

  Widget _qualificationCard(
    BuildContext context,
    PlayInState state,
    Map<String, String> teams,
  ) {
    final qualifiers = state.qualifiedTeams;
    final eliminated = state.eliminatedTeams.toList()
      ..sort(
        (a, b) => state.originalRanking
            .indexOf(a)
            .compareTo(state.originalRanking.indexOf(b)),
      );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Playoff-qualified teams',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final (seed, teamId, originalSeed) in qualifiers)
              Text(
                'Seed $seed · ${_name(teamId, teams)} (original seed $originalSeed) — Qualified',
              ),
            if (qualifiers.length < 16)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Seeds 15 and 16 qualify as Play-In results are completed.',
                ),
              ),
            const Divider(height: 24),
            Text('Eliminated', style: Theme.of(context).textTheme.titleSmall),
            Text(
              eliminated.isEmpty
                  ? 'Seeds 19–30 are eliminated when Play-In entry begins.'
                  : eliminated
                        .map(
                          (team) =>
                              'Seed ${state.originalRanking.indexOf(team) + 1} · '
                              '${_name(team, teams)} — Eliminated',
                        )
                        .join('\n'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gameCard(
    BuildContext context,
    GmCareer career,
    PlayInState state,
    int gameNumber,
    Map<String, String> teams,
  ) {
    final season = career.regularSeasonState!;
    final fixture = state.fixture(
      gameNumber: gameNumber,
      scheduleSeed: season.scheduleSeed,
    );
    final result = state.gameResults['${state.seasonId}-playin-g$gameNumber'];
    if (fixture == null) {
      return Card(
        child: ListTile(
          title: Text('Game $gameNumber'),
          subtitle: const Text('Scheduled — awaiting Games 1 and 2.'),
          trailing: const Chip(label: Text('Scheduled')),
        ),
      );
    }
    final winner = result?.summary.winnerTeamId;
    final loser = result == null
        ? null
        : winner == result.homeTeamId
        ? result.awayTeamId
        : result.homeTeamId;
    final loserStatus = gameNumber == 1 ? 'Advances to Game 3' : 'Eliminated';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Game $gameNumber',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(result == null ? 'Scheduled' : 'Completed')),
              ],
            ),
            Text(
              'Home · Seed ${state.originalRanking.indexOf(fixture.homeTeamId) + 1} · ${_name(fixture.homeTeamId, teams)}',
            ),
            Text(
              'Away · Seed ${state.originalRanking.indexOf(fixture.awayTeamId) + 1} · ${_name(fixture.awayTeamId, teams)}',
            ),
            if (result != null) ...[
              const SizedBox(height: 6),
              Text('${result.summary.homeScore} — ${result.summary.awayScore}'),
              Text(
                'Winner · ${_name(winner!, teams)} — ${gameNumber == 1
                    ? 'Qualified as seed 15'
                    : gameNumber == 3
                    ? 'Qualified as seed 16'
                    : 'Advances to Game 3'}',
              ),
              Text('Loser · ${_name(loser!, teams)} — $loserStatus'),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey('play-in-boxscore-$gameNumber'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlayInBoxScoreScreen(
                        career: career,
                        gameId: fixture.id,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.scoreboard_outlined),
                  label: const Text('View box score'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  PlayInFixture? _nextGame(PlayInState state, int scheduleSeed) {
    for (var gameNumber = 1; gameNumber <= 3; gameNumber++) {
      final id = '${state.seasonId}-playin-g$gameNumber';
      if (state.gameResults.containsKey(id)) continue;
      return state.fixture(gameNumber: gameNumber, scheduleSeed: scheduleSeed);
    }
    return null;
  }

  Future<void> _confirmAndEnterPlayoffs(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter playoffs?'),
        content: const Text(
          'The 16 qualified teams and original regular-season ranks will be frozen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.enterPlayoffs(confirmed: true);
      if (context.mounted &&
          controller.career?.phase == CareerPhase.playoffs &&
          Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (_) {}
  }

  Future<void> _confirmAndSimulate(
    BuildContext context,
    PlayInFixture game,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Play Game ${game.gameNumber}?'),
        content: const Text('Simulate and save this Play-In game?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.simulatePlayInGame(
        expectedGameId: game.id,
        confirmed: true,
      );
    } catch (_) {}
  }

  static String _name(TeamId team, Map<String, String> teams) =>
      teams[team.value] ?? team.value;
}

class PlayInBoxScoreScreen extends StatelessWidget {
  const PlayInBoxScoreScreen({
    super.key,
    required this.career,
    required this.gameId,
  });

  final GmCareer career;
  final String gameId;

  @override
  Widget build(BuildContext context) {
    final state = career.playInState!;
    final result = state.gameResults[gameId]!;
    final evidence = result.inputEvidence!;
    final historicalLeague = RegularSeasonGameInputEvidence.parseLeagueSnapshot(
      snapshotId: evidence.leagueSnapshotId,
      leagueSnapshotJson: state.gameInputSnapshots[evidence.leagueSnapshotId]!,
      openingTeamIds: {
        for (final team in career.regularSeasonState!.openingTeams)
          team.teamId.value,
      },
    );
    final players = {
      for (final team in historicalLeague.teams)
        for (final player in team.players) player.id.value: player,
    };
    final names = {
      for (final team in career.regularSeasonState!.openingTeams)
        team.teamId.value: team.name,
    };
    final summary = result.summary;
    return Scaffold(
      appBar: AppBar(title: const Text('Play-In Box Score')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${names[result.homeTeamId.value]} ${summary.homeScore} — ${summary.awayScore} ${names[result.awayTeamId.value]}',
          ),
          const SizedBox(height: 12),
          for (final teamId in [
            result.homeTeamId.value,
            result.awayTeamId.value,
          ]) ...[
            Text(
              names[teamId] ?? teamId,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final line in summary.playerLines.values.where(
              (line) => line.teamId == teamId,
            ))
              ListTile(
                dense: true,
                title: Text(players[line.playerId]?.fullName ?? line.playerId),
                subtitle: Text(
                  'PTS ${line.points} · REB ${line.rebounds} · AST ${line.assists}',
                ),
                trailing: Text('${line.secondsPlayed ~/ 60} min'),
              ),
          ],
          const SizedBox(height: 8),
          const Text('Period totals'),
          for (final period in summary.periodScoresHome.keys)
            Text(
              '$period · ${summary.periodScoresHome[period]} — ${summary.periodScoresAway[period]}',
            ),
        ],
      ),
    );
  }
}
