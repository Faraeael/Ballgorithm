import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'career_controller.dart';

enum _FreeAgentSort { overall, age, name }

/// Read-only free-agent board. No offer or signing action exists in T08D.
class GmFreeAgentsScreen extends StatefulWidget {
  const GmFreeAgentsScreen({super.key, required this.controller});

  final GmCareerController controller;

  @override
  State<GmFreeAgentsScreen> createState() => _GmFreeAgentsScreenState();
}

class _GmFreeAgentsScreenState extends State<GmFreeAgentsScreen> {
  Position? _position;
  _FreeAgentSort _sort = _FreeAgentSort.overall;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final career = widget.controller.career;
      if (career == null) {
        return const Scaffold(body: Center(child: Text('No active career')));
      }
      final views = [
        for (final entry in career.freeAgentPool.entries) entry.toPublicView(),
      ];
      final filtered =
          [
            for (final view in views)
              if (_position == null || view.position == _position) view,
          ]..sort(
            (a, b) => switch (_sort) {
              _FreeAgentSort.overall => b.overallRating.compareTo(
                a.overallRating,
              ),
              _FreeAgentSort.age => a.age.compareTo(b.age),
              _FreeAgentSort.name => a.fullName.compareTo(b.fullName),
            },
          );
      return Scaffold(
        key: const ValueKey('free-agents-screen'),
        appBar: AppBar(
          title: Text('Free Agents (${career.freeAgentPool.length})'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('All'),
                          selected: _position == null,
                          onSelected: (_) => setState(() => _position = null),
                        ),
                        for (final position in Position.values) ...[
                          const SizedBox(width: 6),
                          ChoiceChip(
                            key: ValueKey(
                              'free-agent-filter-${position.shortName}',
                            ),
                            label: Text(position.shortName),
                            selected: _position == position,
                            onSelected: (_) =>
                                setState(() => _position = position),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Sort'),
                      const SizedBox(width: 8),
                      DropdownButton<_FreeAgentSort>(
                        key: const ValueKey('free-agent-sort'),
                        value: _sort,
                        onChanged: (value) {
                          if (value != null) setState(() => _sort = value);
                        },
                        items: const [
                          DropdownMenuItem(
                            value: _FreeAgentSort.overall,
                            child: Text('Overall'),
                          ),
                          DropdownMenuItem(
                            value: _FreeAgentSort.age,
                            child: Text('Age'),
                          ),
                          DropdownMenuItem(
                            value: _FreeAgentSort.name,
                            child: Text('Name'),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text('${filtered.length} shown'),
                    ],
                  ),
                  Text(
                    'Read-only board. No contract offers yet.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No free agents match the filter'))
                  : ListView.builder(
                      key: const ValueKey('free-agent-list'),
                      padding: const EdgeInsets.all(12),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) =>
                          _FreeAgentCard(view: filtered[index]),
                    ),
            ),
          ],
        ),
      );
    },
  );
}

class _FreeAgentCard extends StatelessWidget {
  const _FreeAgentCard({required this.view});

  final PublicFreeAgentView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attributes = view.attributes;
    return Card(
      key: ValueKey('free-agent-${view.id.value}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  child: Text(
                    view.position.shortName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        view.fullName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Age ${view.age} • ${view.position.fullName}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${view.overallRating}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                _Attribute(label: 'INS', value: attributes.insideScoring),
                _Attribute(label: 'MID', value: attributes.midrange),
                _Attribute(label: '3PT', value: attributes.threePoint),
                _Attribute(label: 'PAS', value: attributes.passing),
                _Attribute(label: 'DEF', value: attributes.perimeterDefense),
                _Attribute(label: 'REB', value: attributes.rebounding),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Attribute extends StatelessWidget {
  const _Attribute({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) =>
      Text('$label $value', style: Theme.of(context).textTheme.bodySmall);
}
