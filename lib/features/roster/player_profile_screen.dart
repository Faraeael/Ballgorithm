import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

/// UI labels for domain attribute keys. Kept in the presentation layer so the
/// domain stays free of localisation concerns.
const Map<String, String> attributeLabels = {
  'insideScoring': 'Inside Scoring',
  'midrange': 'Midrange',
  'threePoint': 'Three Point',
  'freeThrow': 'Free Throw',
  'passing': 'Passing',
  'ballHandling': 'Ball Handling',
  'perimeterDefense': 'Perimeter Defense',
  'interiorDefense': 'Interior Defense',
  'rebounding': 'Rebounding',
  'athleticism': 'Athleticism',
  'stamina': 'Stamina',
  'basketballIQ': 'Basketball IQ',
};

class PlayerProfileScreen extends StatelessWidget {
  const PlayerProfileScreen({
    super.key,
    required this.team,
    required this.player,
  });

  final Team team;
  final Player player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attributes = player.attributes.asMap;
    return Scaffold(
      appBar: AppBar(title: Text(player.fullName)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(team.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '${player.position.fullName} · ${player.position.shortName}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          for (final entry in attributes.entries)
            _AttributeRow(
              key: ValueKey('attribute-${entry.key}'),
              label: attributeLabels[entry.key] ?? entry.key,
              value: entry.value,
            ),
        ],
      ),
    );
  }
}

class _AttributeRow extends StatelessWidget {
  const _AttributeRow({super.key, required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 150, child: Text(label)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: value / 100, minHeight: 8),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$value',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
