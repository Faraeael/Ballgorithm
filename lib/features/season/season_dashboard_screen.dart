import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import '../game/game_runner.dart';
import '../game/game_screen.dart';
import 'season_controller.dart';
import 'season_schedule_screen.dart';
import 'standings_screen.dart';
import 'team_strategy_screen.dart';

class SeasonDashboardScreen extends StatefulWidget {
  const SeasonDashboardScreen({
    super.key,
    required this.league,
    required this.controller,
    this.runner,
  });

  final League league;
  final SeasonController controller;
  final GameRunner? runner;

  @override
  State<SeasonDashboardScreen> createState() => _SeasonDashboardScreenState();
}

class _SeasonDashboardScreenState extends State<SeasonDashboardScreen> {
  int _tabIndex = 0;
  bool _isNavigatingToGame = false;

  Team _findTeam(TeamId id) =>
      widget.league.teams.firstWhere((t) => t.id == id);

  Future<void> _playNextGame(SeasonFixture fixture) async {
    if (_isNavigatingToGame) return;
    _isNavigatingToGame = true;
    final state = widget.controller.state!;
    final homeTeam = _findTeam(fixture.homeTeamId);
    final awayTeam = _findTeam(fixture.awayTeamId);

    final isUserHome = fixture.homeTeamId == state.userFranchiseId;

    final homeLineup = isUserHome
        ? state.userStrategy.startingLineup
        : CourtLineup.defaultFor(homeTeam);
    final awayLineup = !isUserHome
        ? state.userStrategy.startingLineup
        : CourtLineup.defaultFor(awayTeam);
    final homePlan = isUserHome
        ? state.userStrategy.teamPlan
        : FranchiseStrategy.defaultFor(homeTeam).teamPlan;

    final awayPlan = !isUserHome
        ? state.userStrategy.teamPlan
        : FranchiseStrategy.defaultFor(awayTeam).teamPlan;

    final request = GameRequest(
      gameId: fixture.id,
      league: widget.league,
      homeTeamId: fixture.homeTeamId,
      awayTeamId: fixture.awayTeamId,
      seed: fixture.seed,
      homeLineup: homeLineup,
      awayLineup: awayLineup,
      rotationPlan: RotationPlan(home: homePlan, away: awayPlan),
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          request: request,
          runner: widget.runner ?? runGame,
          enableRematch: false,
          returnButtonLabel: 'Continue Season',
          onFinalizeRound: (result) async {
            await widget.controller.commitRoundWithUserResult(result);
          },
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _isNavigatingToGame = false;
      });
    }
  }

  void _confirmNewSeason() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start New Season?'),
        content: const Text(
          'This will clear current season progress and standings. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-new-season-button'),
            onPressed: () async {
              Navigator.pop(context);
              await widget.controller.resetSeason();
            },
            child: const Text('Start New Season'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.controller.isCommitting) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Simulating league games & saving progress...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final state = widget.controller.state;
    if (state == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final userTeam = state.userTeam;
    final userStanding = state.userStanding;
    final ranked = state.standings.ranked;
    final rank = ranked.indexWhere((s) => s.teamId == userTeam.id) + 1;

    final pages = [
      _buildHomeDashboard(context, theme, state, userTeam, userStanding, rank),
      TeamStrategyScreen(league: widget.league, controller: widget.controller),
      StandingsScreen(
        league: widget.league,
        standings: state.standings,
        userFranchiseId: userTeam.id,
      ),
      SeasonScheduleScreen(
        league: widget.league,
        schedule: state.schedule,
        currentRoundNumber: state.currentRoundNumber,
        userFranchiseId: userTeam.id,
      ),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_tabIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) {
          setState(() {
            _tabIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            key: ValueKey('nav-dashboard'),
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            key: ValueKey('nav-team'),
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group),
            label: 'Team',
          ),
          NavigationDestination(
            key: ValueKey('nav-standings'),
            icon: Icon(Icons.leaderboard_outlined),
            selectedIcon: Icon(Icons.leaderboard),
            label: 'Standings',
          ),
          NavigationDestination(
            key: ValueKey('nav-schedule'),
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Schedule',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeDashboard(
    BuildContext context,
    ThemeData theme,
    SeasonState state,
    Team userTeam,
    SeasonStanding userStanding,
    int rank,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        if (widget.controller.hasPendingResult)
          Card(
            color: Colors.red.shade50,
            margin: const EdgeInsets.only(bottom: 16.0),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Round simulated but could not be saved to storage.',
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const ValueKey('retry-pending-save-button'),
                    onPressed: () => widget.controller.retryPendingCommit(),
                    child: const Text('Retry Saving Round'),
                  ),
                ],
              ),
            ),
          ),
        // Franchise Header Card
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  child: Text(
                    userTeam.abbreviation,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userTeam.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${userStanding.wins}W - ${userStanding.losses}L  -  Rank #$rank  -  Streak ${userStanding.streak}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // End of Season Card OR Next Game Card
        if (state.isSeasonCompleted)
          _buildEndOfSeasonCard(context, theme, state)
        else
          _buildNextGameCard(context, theme, state),

        const SizedBox(height: 16),

        // Standings Preview Card
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Standings Snapshot',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('view-full-standings-button'),
                      onPressed: () => setState(() => _tabIndex = 2),
                      child: const Text('View All'),
                    ),
                  ],
                ),
                const Divider(),
                for (final s in state.standings.ranked.take(4))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _findTeam(s.teamId).name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: s.teamId == state.userFranchiseId
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: s.teamId == state.userFranchiseId
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${s.wins}-${s.losses} (${s.streak})',
                          style: TextStyle(
                            fontWeight: s.teamId == state.userFranchiseId
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNextGameCard(
    BuildContext context,
    ThemeData theme,
    SeasonState state,
  ) {
    final fixture = state.nextUserFixture!;
    final isHome = fixture.homeTeamId == state.userFranchiseId;
    final opponentId = isHome ? fixture.awayTeamId : fixture.homeTeamId;
    final opponent = _findTeam(opponentId);
    final oppStanding = state.standings.table[opponentId.value]!;
    final oppRank =
        state.standings.ranked.indexWhere((s) => s.teamId == opponentId) + 1;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'ROUND ${fixture.roundNumber} OF 14',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isHome
                        ? Colors.blue.shade100
                        : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isHome ? 'HOME GAME' : 'AWAY GAME',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isHome
                          ? Colors.blue.shade900
                          : Colors.orange.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: Text(
                    opponent.abbreviation,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isHome ? 'vs ${opponent.name}' : '@ ${opponent.name}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Record: ${oppStanding.wins}W - ${oppStanding.losses}L (Rank #$oppRank)',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                key: const ValueKey('play-next-game'),
                onPressed: _isNavigatingToGame
                    ? null
                    : () => _playNextGame(fixture),
                child: const Text(
                  'PLAY NEXT GAME',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndOfSeasonCard(
    BuildContext context,
    ThemeData theme,
    SeasonState state,
  ) {
    final champStanding = state.champion;
    final champTeam = _findTeam(champStanding.teamId);
    final userWon = champStanding.teamId == state.userFranchiseId;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Icon(Icons.emoji_events, size: 48, color: Colors.amber),
            const SizedBox(height: 8),
            Text(
              'REGULAR SEASON COMPLETED!',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.amber.shade900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              userWon
                  ? 'Congratulations! Your franchise won the championship!'
                  : 'Champion: ${champTeam.name} (${champStanding.wins}-${champStanding.losses})',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: Colors.amber.shade900,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _tabIndex = 2),
                    child: const Text('Final Standings'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('new-season-button'),
                    onPressed: _confirmNewSeason,
                    child: const Text('New Season'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
