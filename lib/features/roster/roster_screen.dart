import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'player_profile_screen.dart';

class RosterScreen extends StatelessWidget {
  const RosterScreen({super.key, required this.team});

  final Team team;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(team.name)),
      body: ListView.separated(
        itemCount: team.players.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final player = team.players[index];
          return ListTile(
            key: ValueKey('player-${player.id.value}'),
            leading: _PositionBadge(position: player.position),
            title: Text(player.fullName),
            subtitle: Text(player.position.fullName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) =>
                    PlayerProfileScreen(team: team, player: player),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PositionBadge extends StatelessWidget {
  const _PositionBadge({required this.position});

  final Position position;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        position.shortName,
        style: TextStyle(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
