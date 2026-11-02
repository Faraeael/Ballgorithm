import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'game_runner.dart';
import 'game_seed.dart';

/// Game Day setup (T022): choose two distinct teams, confirm the matchup.
///
/// The screen produces a [GameRequest] with the derived seed and hands it to
/// [onConfirm]. It never runs a game, shows a score or invents a result; game
/// execution belongs to T023.
class GameSetupScreen extends StatefulWidget {
  const GameSetupScreen({
    super.key,
    required this.league,
    required this.onConfirm,
  });

  final League league;
  final ValueChanged<GameRequest> onConfirm;

  @override
  State<GameSetupScreen> createState() => _GameSetupScreenState();
}

class _GameSetupScreenState extends State<GameSetupScreen> {
  Team? _homeTeam;
  Team? _awayTeam;

  int? _indexOf(Team? team) {
    if (team == null) return null;
    final index = widget.league.teams.indexWhere(
      (candidate) => candidate.id.value == team.id.value,
    );
    return index < 0 ? null : index;
  }

  int? get _seed {
    final homeIndex = _indexOf(_homeTeam);
    final awayIndex = _indexOf(_awayTeam);
    if (homeIndex == null || awayIndex == null || homeIndex == awayIndex) {
      return null;
    }
    return deriveGameSeed(
      leagueSeed: widget.league.config.seed,
      homeIndex: homeIndex,
      awayIndex: awayIndex,
      rematchIndex: 0,
    );
  }

  void _select({required bool home, required Team team}) {
    setState(() {
      if (home) {
        _homeTeam = team;
      } else {
        _awayTeam = team;
      }
    });
  }

  void _confirm() {
    final home = _homeTeam;
    final away = _awayTeam;
    final seed = _seed;
    if (home == null || away == null || seed == null) return;
    widget.onConfirm(
      GameRequest(
        league: widget.league,
        homeTeamId: home.id,
        awayTeamId: away.id,
        seed: seed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final home = _homeTeam;
    final away = _awayTeam;
    final seed = _seed;

    return Scaffold(
      appBar: AppBar(title: const Text('Game Day Setup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(widget.league.name, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            '${widget.league.teams.length} teams · seed '
            '${widget.league.config.seed}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          _TeamDropdown(
            label: 'Home team',
            fieldKey: const ValueKey('home-team-select'),
            optionKeyPrefix: 'home-option',
            teams: widget.league.teams,
            excludedTeamId: away?.id,
            selected: home,
            onChanged: (team) => _select(home: true, team: team),
          ),
          const SizedBox(height: 16),
          _TeamDropdown(
            label: 'Away team',
            fieldKey: const ValueKey('away-team-select'),
            optionKeyPrefix: 'away-option',
            teams: widget.league.teams,
            excludedTeamId: home?.id,
            selected: away,
            onChanged: (team) => _select(home: false, team: team),
          ),
          const SizedBox(height: 20),
          if (home != null && away != null)
            Text(
              '${away.name} at ${home.name}',
              key: const ValueKey('matchup-summary'),
              style: theme.textTheme.titleMedium,
            )
          else
            Text(
              'Select a home team and an away team.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            seed == null
                ? 'Game seed: not set'
                : 'Game seed: ${describeGameSeed(seed)}',
            key: const ValueKey('derived-seed'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('confirm-matchup'),
            onPressed: seed != null ? _confirm : null,
            child: const Text('Confirm matchup'),
          ),
        ],
      ),
    );
  }
}

class _TeamDropdown extends StatelessWidget {
  const _TeamDropdown({
    required this.label,
    required this.fieldKey,
    required this.optionKeyPrefix,
    required this.teams,
    required this.excludedTeamId,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final Key fieldKey;
  final String optionKeyPrefix;
  final List<Team> teams;

  /// The team already chosen for the other role; offering it would allow the
  /// same team on both sides.
  final TeamId? excludedTeamId;
  final Team? selected;
  final ValueChanged<Team> onChanged;

  @override
  Widget build(BuildContext context) {
    final available = [
      for (final team in teams)
        if (team.id.value != excludedTeamId?.value) team,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        DropdownButton<Team>(
          key: fieldKey,
          isExpanded: true,
          value: selected,
          hint: Text('Select $label'.toLowerCase()),
          items: [
            for (final team in available)
              DropdownMenuItem<Team>(
                key: ValueKey('$optionKeyPrefix-${team.id.value}'),
                value: team,
                child: Text(
                  '${team.abbreviation} · ${team.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (team) {
            if (team != null) onChanged(team);
          },
        ),
      ],
    );
  }
}
