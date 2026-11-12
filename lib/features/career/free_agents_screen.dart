import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'career_controller.dart';
import 'free_agent_offer_screen.dart';

enum _FreeAgentSort { overall, age, name }

const _market = FreeAgentMarketValueService();

/// Free-agent board. Public information plus a formal offer entry point.
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
      final entries =
          [
            for (final entry in career.freeAgentPool.entries)
              if (_position == null || entry.player.position == _position)
                entry,
          ]..sort((a, b) {
            final aView = a.toPublicView();
            final bView = b.toPublicView();
            return switch (_sort) {
              _FreeAgentSort.overall => bView.overallRating.compareTo(
                aView.overallRating,
              ),
              _FreeAgentSort.age => aView.age.compareTo(bView.age),
              _FreeAgentSort.name => aView.fullName.compareTo(bView.fullName),
            };
          });
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
                      Text('${entries.length} shown'),
                    ],
                  ),
                  Text(
                    'Estimated values are public guidance, not a guaranteed '
                    'acceptance threshold.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('No free agents match the filter'))
                  : ListView.builder(
                      key: const ValueKey('free-agent-list'),
                      padding: const EdgeInsets.all(12),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return _FreeAgentCard(
                          entry: entry,
                          valuation: _market.estimate(entry.toPublicView()),
                          remainingAttempts: career.freeAgentOffers
                              .remainingAttempts(
                                teamId: career.userFranchiseId,
                                playerId: entry.id,
                                seasonYear: career.currentYear,
                              ),
                          onMakeOffer: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => GmFreeAgentOfferScreen(
                                controller: widget.controller,
                                freeAgentId: entry.id,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}

class _FreeAgentCard extends StatelessWidget {
  const _FreeAgentCard({
    required this.entry,
    required this.valuation,
    required this.remainingAttempts,
    required this.onMakeOffer,
  });

  final FreeAgentEntry entry;
  final MarketValuation valuation;
  final int remainingAttempts;
  final VoidCallback onMakeOffer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final view = entry.toPublicView();
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
                        'Age ${view.age} • ${view.position.fullName} • '
                        '${valuation.expectedRole.displayName}',
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
            const SizedBox(height: 8),
            Text(
              'Est. market ${valuation.estimatedAnnualSalary} CU • '
              'Preferred ${valuation.preferredDurationYears}y • '
              '$remainingAttempts offer(s) remaining',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                key: ValueKey('make-offer-${view.id.value}'),
                onPressed: remainingAttempts > 0 ? onMakeOffer : null,
                child: Text(
                  remainingAttempts > 0 ? 'Make Offer' : 'No Offers Remaining',
                ),
              ),
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
