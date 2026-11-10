import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import '../game/game_setup_screen.dart';
import '../game/game_screen.dart';
import 'season_controller.dart';

class FranchiseSelectScreen extends StatefulWidget {
  const FranchiseSelectScreen({
    super.key,
    required this.league,
    required this.controller,
  });

  final League league;
  final SeasonController controller;

  @override
  State<FranchiseSelectScreen> createState() => _FranchiseSelectScreenState();
}

class _FranchiseSelectScreenState extends State<FranchiseSelectScreen> {
  TeamId? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.league.teams.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ballgorithm Season'),
        actions: [
          TextButton(
            key: const ValueKey('open-exhibition'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GameSetupScreen(
                    league: widget.league,
                    onConfirm: (request) => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GameScreen(request: request),
                      ),
                    ),
                  ),
                ),
              );
            },
            child: const Text('Exhibition'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Your Franchise',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose one of 8 teams to manage through a 14-game regular season.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: widget.league.teams.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final team = widget.league.teams[index];
                final isSelected = team.id == _selectedId;

                return ListTile(
                  key: ValueKey('team-card-${team.id.value}'),
                  selected: isSelected,
                  selectedTileColor: theme.colorScheme.primaryContainer
                      .withValues(alpha: 0.3),
                  leading: CircleAvatar(
                    backgroundColor: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    foregroundColor: isSelected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                    child: Text(
                      team.abbreviation,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(
                    team.name,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    '${team.players.length} Players',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: isSelected
                      ? Icon(
                          Icons.check_circle,
                          color: theme.colorScheme.primary,
                        )
                      : const Icon(Icons.radio_button_unchecked),
                  onTap: () {
                    setState(() {
                      _selectedId = team.id;
                    });
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                key: const ValueKey('start-season-button'),
                onPressed: _selectedId == null
                    ? null
                    : () async {
                        await widget.controller.startNewSeason(_selectedId!);
                      },
                child: const Text('Start Season'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
