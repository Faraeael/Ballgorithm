import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'career_controller.dart';

class PlayoffTournamentScreen extends StatefulWidget {
  const PlayoffTournamentScreen({
    super.key,
    required this.controller,
    this.slot = 'default',
  });

  final GmCareerController controller;
  final String slot;

  @override
  State<PlayoffTournamentScreen> createState() =>
      _PlayoffTournamentScreenState();
}

class _PlayoffTournamentScreenState extends State<PlayoffTournamentScreen> {
  bool _isDialogOpen = false;
  bool _isTransitioning = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final career = widget.controller.career;
      if (career == null ||
          career.phase != CareerPhase.playoffs ||
          career.playoffState == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final state = career.playoffState!;
      final names = {
        for (final team in career.regularSeasonState!.openingTeams)
          team.teamId.value: team.name,
      };
      final isBusy = widget.controller.isLoading || _isTransitioning;
      final transitionStage = widget.controller.seasonTransitionStage;
      final isSeasonTransitioning = _isTransitioning || transitionStage != null;
      return PlayoffBracketContent(
        state: state,
        names: names,
        seasonYear: career.currentYear,
        userFranchiseId: career.userFranchiseId,
        isLoading: isBusy,
        transitionStage: transitionStage,
        isTransitioning: isSeasonTransitioning,
        recoveryRequired: widget.controller.draftRecoveryRequired,
        errorMessage: widget.controller.errorMessage,
        onSimulate: state.isComplete || isBusy
            ? null
            : () => _confirmNextSlate(context),
        onContinueToNextSeason:
            state.isComplete &&
                !isBusy &&
                !widget.controller.draftRecoveryRequired &&
                !_isDialogOpen
            ? () => _confirmContinueToNextSeason(context)
            : null,
        onViewFullBracket: isSeasonTransitioning
            ? null
            : () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => PlayoffFullBracketScreen(career: career),
                ),
              ),
        onViewResults: isSeasonTransitioning
            ? null
            : () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => PlayoffGameResultsScreen(career: career),
                ),
              ),
        onReload: isBusy
            ? null
            : () => widget.controller.loadCareer(slot: widget.slot),
      );
    },
  );

  Future<void> _confirmNextSlate(BuildContext context) async {
    if (_isDialogOpen || _isTransitioning || widget.controller.isLoading) {
      return;
    }
    _isDialogOpen = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Simulate next playoff slate?'),
          content: const Text(
            'Simulate and save one next game for each active series in the current round?',
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
      if (confirmed != true || !mounted) return;
      try {
        await widget.controller.simulateNextPlayoffSlate(confirmed: true);
      } catch (_) {}
    } finally {
      _isDialogOpen = false;
    }
  }

  Future<void> _confirmContinueToNextSeason(BuildContext context) async {
    if (_isDialogOpen ||
        _isTransitioning ||
        widget.controller.isLoading ||
        widget.controller.draftRecoveryRequired) {
      return;
    }
    _isDialogOpen = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Start Next Season?'),
          content: const Text(
            'The completed season will be archived and the next season\'s '
            'offseason will begin.\n\n'
            'Rosters, contracts, and financial obligations will carry forward, '
            'and championship results and history will remain available.',
          ),
          actions: [
            TextButton(
              key: const ValueKey('cancel-next-season'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('confirm-next-season'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm & Continue'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      if (_isTransitioning ||
          widget.controller.isLoading ||
          widget.controller.draftRecoveryRequired) {
        return;
      }
      setState(() => _isTransitioning = true);
      try {
        await widget.controller.continueToNextSeason(
          confirmed: true,
          slot: widget.slot,
        );
        if (mounted &&
            widget.controller.career?.phase == CareerPhase.openingOffseason &&
            Navigator.of(this.context).canPop()) {
          Navigator.of(this.context).popUntil((route) => route.isFirst);
        }
      } catch (_) {
        // Error feedback is exposed via controller.errorMessage and draftRecoveryRequired.
      } finally {
        if (mounted) {
          setState(() => _isTransitioning = false);
        }
      }
    } finally {
      _isDialogOpen = false;
    }
  }
}

class PlayoffBracketContent extends StatelessWidget {
  const PlayoffBracketContent({
    super.key,
    required this.state,
    required this.names,
    required this.seasonYear,
    required this.isLoading,
    required this.recoveryRequired,
    required this.onSimulate,
    required this.onViewFullBracket,
    required this.onViewResults,
    this.userFranchiseId,
    this.transitionStage,
    this.isTransitioning = false,
    this.onContinueToNextSeason,
    this.errorMessage,
    this.onReload,
  });

  final PlayoffState state;
  final Map<String, String> names;
  final int seasonYear;
  final TeamId? userFranchiseId;
  final bool isLoading;
  final SeasonTransitionStage? transitionStage;
  final bool isTransitioning;
  final bool recoveryRequired;
  final String? errorMessage;
  final VoidCallback? onSimulate;
  final VoidCallback? onContinueToNextSeason;
  final VoidCallback? onViewFullBracket;
  final VoidCallback? onViewResults;
  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) {
    final currentRound = state.currentRound;
    final currentSeries = currentRound == null
        ? const <PlayoffSeriesIdentity>[]
        : state.series.where((slot) => slot.round == currentRound).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Playoffs')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Season $seasonYear',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.isComplete ? 'Champion' : 'Current round',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.isComplete
                        ? _name(state.champion!, names)
                        : currentRound?.displayName ?? 'Playoffs complete',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (state.isComplete) ...[
                    const Text(
                      'Championship complete. No more games can be simulated.',
                    ),
                    if (userFranchiseId != null)
                      Text(
                        state.champion == userFranchiseId
                            ? 'Your franchise won the Season $seasonYear championship.'
                            : 'Your franchise did not win the Season $seasonYear title.',
                      ),
                  ],
                ],
              ),
            ),
          ),
          ExpansionTile(
            key: const ValueKey('playoff-qualifiers'),
            title: const Text('Qualified teams'),
            subtitle: const Text('Seeds 1–14 plus Play-In seeds 15–16'),
            children: [
              for (final team in state.qualifiedTeams)
                ListTile(
                  dense: true,
                  title: Text(
                    'Seed ${team.playoffSeed} · ${_name(team.teamId, names)}',
                  ),
                  subtitle: Text(
                    'Original regular-season rank ${team.originalRegularSeasonRank}',
                  ),
                ),
            ],
          ),
          if (!state.isComplete && currentRound != null) ...[
            const SizedBox(height: 8),
            Text(
              currentRound.displayName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final slot in currentSeries)
              _SeriesCard(state: state, slot: slot, names: names),
          ],
          if (state.eliminatedTeams.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Eliminated', style: Theme.of(context).textTheme.titleMedium),
            Text(
              state.qualifiedTeams
                  .where((team) => state.eliminatedTeams.contains(team.teamId))
                  .map(
                    (team) =>
                        'Seed ${team.playoffSeed} · ${_name(team.teamId, names)}',
                  )
                  .join('\n'),
            ),
          ],
          if (errorMessage != null || recoveryRequired) ...[
            const SizedBox(height: 12),
            Card(
              key: const ValueKey('playoff-error-card'),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            recoveryRequired
                                ? 'Save Recovery Required'
                                : 'Season Transition Interrupted',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                ),
                          ),
                        ),
                      ],
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        errorMessage!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      recoveryRequired
                          ? 'Save recovery required. Reload the saved career before continuing.'
                          : 'No save files were modified. You can review the error and try again.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (!state.isComplete) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('simulate-next-playoff-slate'),
              onPressed: isLoading || recoveryRequired ? null : onSimulate,
              icon: isLoading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sports_basketball),
              label: Text(
                isLoading
                    ? 'Saving playoff slate…'
                    : 'Simulate Next Playoff Slate',
              ),
            ),
          ] else ...[
            if (isTransitioning || transitionStage != null) ...[
              const SizedBox(height: 12),
              _SeasonTransitionProgressCard(
                completedYear: seasonYear,
                targetYear: seasonYear + 1,
                stage: transitionStage ?? SeasonTransitionStage.preparing,
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('continue-to-next-season'),
              onPressed: isLoading || recoveryRequired
                  ? null
                  : onContinueToNextSeason,
              icon: isLoading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward),
              label: Text(
                isLoading ? 'Saving next season…' : 'Continue to Next Season',
              ),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('view-full-playoff-bracket'),
            onPressed: onViewFullBracket,
            child: const Text('View Full Bracket'),
          ),
          OutlinedButton(
            key: const ValueKey('view-playoff-game-results'),
            onPressed: state.gameResults.isEmpty ? null : onViewResults,
            child: const Text('View Game Results'),
          ),
          if (recoveryRequired) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              key: const ValueKey('reload-playoff-career'),
              onPressed: isLoading ? null : onReload,
              icon: const Icon(Icons.refresh),
              label: const Text('Reload Saved Career'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SeasonTransitionProgressCard extends StatelessWidget {
  const _SeasonTransitionProgressCard({
    required this.completedYear,
    required this.targetYear,
    required this.stage,
  });

  final int completedYear;
  final int targetYear;
  final SeasonTransitionStage stage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      key: const ValueKey('season-transition-progress-card'),
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Season $completedYear → Season $targetYear',
                    key: const ValueKey('season-transition-years'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              stage.label,
              key: const ValueKey('season-transition-stage-label'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              stage.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class PlayoffFullBracketScreen extends StatelessWidget {
  const PlayoffFullBracketScreen({super.key, required this.career});

  final GmCareer career;

  @override
  Widget build(BuildContext context) {
    final state = career.playoffState!;
    final names = _names(career);
    return Scaffold(
      appBar: AppBar(title: const Text('Full Playoff Bracket')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: PlayoffRound.values.length,
        itemBuilder: (context, roundIndex) {
          final round = PlayoffRound.values[roundIndex];
          final slots = state.series
              .where((slot) => slot.round == round)
              .toList();
          return Card(
            child: ExpansionTile(
              key: ValueKey('playoff-round-${round.name}'),
              initiallyExpanded:
                  round == state.currentRound || state.isComplete,
              title: Text(round.displayName),
              subtitle: Text('${slots.length} series'),
              children: [
                for (final slot in slots)
                  _SeriesCard(state: state, slot: slot, names: names),
              ],
            ),
          );
        },
      ),
    );
  }
}

class PlayoffGameResultsScreen extends StatelessWidget {
  const PlayoffGameResultsScreen({super.key, required this.career});

  final GmCareer career;

  @override
  Widget build(BuildContext context) {
    final state = career.playoffState!;
    final names = _names(career);
    final results = state.gameResults.values.toList()
      ..sort((a, b) {
        final first = state.gameIdentities[a.fixtureId]!;
        final second = state.gameIdentities[b.fixtureId]!;
        final bySeries = first.seriesIndex.compareTo(second.seriesIndex);
        return bySeries != 0
            ? bySeries
            : first.gameNumber.compareTo(second.gameNumber);
      });
    return Scaffold(
      appBar: AppBar(title: const Text('Playoff Game Results')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: results.length,
        itemBuilder: (context, index) {
          final result = results[index];
          final winner = result.summary.winnerTeamId;
          final loser = winner == result.homeTeamId
              ? result.awayTeamId
              : result.homeTeamId;
          return Card(
            child: ListTile(
              title: Text(
                '${_name(result.homeTeamId, names)} ${result.summary.homeScore} — '
                '${result.summary.awayScore} ${_name(result.awayTeamId, names)}',
              ),
              subtitle: Text(
                'Series ${state.gameIdentities[result.fixtureId]!.seriesIndex + 1}, '
                'Game ${state.gameIdentities[result.fixtureId]!.gameNumber}\n'
                'Winner · ${_name(winner, names)}  •  Loser · ${_name(loser, names)}',
              ),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: 'View box score',
                icon: const Icon(Icons.scoreboard_outlined),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => PlayoffBoxScoreScreen(
                      career: career,
                      gameId: result.fixtureId,
                    ),
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

class PlayoffBoxScoreScreen extends StatelessWidget {
  const PlayoffBoxScoreScreen({
    super.key,
    required this.career,
    required this.gameId,
  });

  final GmCareer career;
  final String gameId;

  @override
  Widget build(BuildContext context) {
    final state = career.playoffState!;
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
    final teams = {
      for (final team in historicalLeague.teams) team.id.value: team.name,
    };
    final summary = result.summary;
    return Scaffold(
      appBar: AppBar(title: const Text('Playoff Box Score')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${teams[result.homeTeamId.value]} ${summary.homeScore} — '
            '${summary.awayScore} ${teams[result.awayTeamId.value]}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            'Winner · ${teams[summary.winnerTeamId.value] ?? summary.winnerTeamId.value}',
          ),
          const SizedBox(height: 12),
          for (final teamId in [
            result.homeTeamId.value,
            result.awayTeamId.value,
          ]) ...[
            Text(
              teams[teamId] ?? teamId,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final line in summary.playerLines.values.where(
              (line) => line.teamId == teamId,
            ))
              ListTile(
                dense: true,
                title: Text(
                  '${players[line.playerId]?.fullName ?? line.playerId} · '
                  '${line.secondsPlayed ~/ 60} min',
                ),
                subtitle: Text(
                  'PTS ${line.points} · FG ${line.fgm}/${line.fga} · '
                  '3P ${line.threePm}/${line.threePa} · FT ${line.ftm}/${line.fta} · '
                  'OREB ${line.oreb} · DREB ${line.dreb} · REB ${line.rebounds} · '
                  'AST ${line.assists} · STL ${line.steals} · BLK ${line.blocks} · '
                  'TOV ${line.turnovers} · PF ${line.personalFouls}',
                ),
              ),
          ],
          const SizedBox(height: 8),
          const Text('Period totals'),
          for (final period in summary.periodScoresHome.keys)
            Text(
              '$period · ${summary.periodScoresHome[period]} — '
              '${summary.periodScoresAway[period]}',
            ),
        ],
      ),
    );
  }
}

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({
    required this.state,
    required this.slot,
    required this.names,
  });

  final PlayoffState state;
  final PlayoffSeriesIdentity slot;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final first = slot.firstTeamId;
    final second = slot.secondTeamId;
    if (first == null || second == null) {
      return const ListTile(
        title: Text('Series scheduled'),
        subtitle: Text('Waiting for the prior round to finish.'),
      );
    }
    final winner = state.seriesWinner(slot.seriesIndex);
    final loser = winner == first ? second : first;
    final firstSeed = _seed(first, state);
    final secondSeed = _seed(second, state);
    final games =
        state.gameIdentities.values
            .where((game) => game.seriesIndex == slot.seriesIndex)
            .toList()
          ..sort((a, b) => a.gameNumber.compareTo(b.gameNumber));
    final nextGame = state.nextEligibleGames
        .where((game) => game.seriesIndex == slot.seriesIndex)
        .firstOrNull;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Series ${slot.seriesIndex + 1}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              'Seed $firstSeed · ${_name(first, names)}  '
              '${state.seriesWins(slot.seriesIndex, first)} — '
              '${state.seriesWins(slot.seriesIndex, second)}  '
              '${_name(second, names)} · Seed $secondSeed',
            ),
            if (nextGame != null)
              Text(
                'Next · Game ${nextGame.gameNumber} · Home ${_name(nextGame.homeTeamId, names)}',
              ),
            if (winner != null) ...[
              const Text('Completed'),
              Text('Advanced · ${_name(winner, names)}'),
              Text('Eliminated · ${_name(loser, names)}'),
            ] else if (games.any(
              (game) => state.gameResults.containsKey(game.id),
            ))
              const Text('In progress')
            else
              const Text('Scheduled'),
            if (games.isNotEmpty)
              Text(
                'Completed games: ${games.where((game) => state.gameResults.containsKey(game.id)).length} of 7',
              ),
          ],
        ),
      ),
    );
  }
}

int _seed(TeamId teamId, PlayoffState state) => state.qualifiedTeams
    .firstWhere((team) => team.teamId == teamId)
    .playoffSeed;

String _name(TeamId teamId, Map<String, String> names) =>
    names[teamId.value] ?? teamId.value;

Map<String, String> _names(GmCareer career) => {
  for (final team in career.regularSeasonState!.openingTeams)
    team.teamId.value: team.name,
};
