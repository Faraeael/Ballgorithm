import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'career_controller.dart';
import 'free_agent_offer_screen.dart';
import 'league_market_summary_screen.dart';

enum _FreeAgentSort { overall, age, name }

const _market = FreeAgentMarketValueService();

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
      final market = career.freeAgentMarket;
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
      final canOffer = market.isCollecting;
      return Scaffold(
        key: const ValueKey('free-agents-screen'),
        appBar: AppBar(
          title: Text('Free Agents (${career.freeAgentPool.length})'),
        ),
        body: Column(
          children: [
            _MarketHeader(
              career: career,
              onStart: () =>
                  _run(() => widget.controller.startFreeAgencyRound()),
              onLock: () =>
                  _run(() => widget.controller.prepareFreeAgencyResolution()),
              onResolve: () =>
                  _run(() => widget.controller.resolveFreeAgencyRound()),
              onCancel: (id) => _run(
                () => widget.controller.cancelFreeAgentOffer(freeAgentId: id),
              ),
              onSummary: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GmLeagueMarketSummaryScreen(
                    controller: widget.controller,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
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
                  ),
                  DropdownButton<_FreeAgentSort>(
                    key: const ValueKey('free-agent-sort'),
                    value: _sort,
                    onChanged: (value) {
                      if (value != null) setState(() => _sort = value);
                    },
                    items: const [
                      DropdownMenuItem(
                        value: _FreeAgentSort.overall,
                        child: Text('OVR'),
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
                          canOffer: canOffer,
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

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class _MarketHeader extends StatelessWidget {
  const _MarketHeader({
    required this.career,
    required this.onStart,
    required this.onLock,
    required this.onResolve,
    required this.onCancel,
    required this.onSummary,
  });

  final GmCareer career;
  final VoidCallback onStart;
  final VoidCallback onLock;
  final VoidCallback onResolve;
  final void Function(PlayerId) onCancel;
  final VoidCallback onSummary;

  @override
  Widget build(BuildContext context) {
    final market = career.freeAgentMarket;
    final theme = Theme.of(context);
    final pending = market.humanOffers;
    final acquisitions = career.freeAgentPool.acquisitions;
    final aiAcquisitions = acquisitions.entries.values
        .where((record) => record.teamId != career.userFranchiseId)
        .length;
    final humanAcquisitions = acquisitions.length - aiAcquisitions;
    final ready = LeagueReadinessReport.fromCareer(
      career,
    ).teams.where((team) => team.isReady).length;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Free Agency Round ${market.roundNumber} • '
              '${market.isCollecting && pending.isNotEmpty ? 'Offers Pending' : _statusLabel(market.status)}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${career.freeAgentPool.length} available • '
              '${pending.length} pending human offer(s) • '
              '$humanAcquisitions human / $aiAcquisitions AI signings • '
              '$ready/30 ready',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (market.status == FreeAgentMarketStatus.notStarted)
                  FilledButton(
                    key: const ValueKey('start-free-agency'),
                    onPressed: onStart,
                    child: const Text('Start Free Agency'),
                  ),
                if (market.isCollecting)
                  FilledButton(
                    key: const ValueKey('lock-free-agency'),
                    onPressed: onLock,
                    child: const Text('Lock Offers'),
                  ),
                if (market.isResolvable)
                  FilledButton(
                    key: const ValueKey('resolve-free-agency'),
                    onPressed: onResolve,
                    child: const Text('Resolve Free Agency Round'),
                  ),
                if (market.status == FreeAgentMarketStatus.roundComplete &&
                    market.roundNumber == 1)
                  FilledButton(
                    key: const ValueKey('start-round-2'),
                    onPressed: onStart,
                    child: const Text('Start Round 2'),
                  ),
                if (market.status == FreeAgentMarketStatus.marketComplete)
                  const Chip(label: Text('Market Complete')),
                OutlinedButton(
                  key: const ValueKey('market-summary'),
                  onPressed: onSummary,
                  child: const Text('League Summary'),
                ),
              ],
            ),
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                market.isCollecting ? 'Pending offers' : 'Submitted offers',
                style: theme.textTheme.labelLarge,
              ),
              for (final offer in pending)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${_playerName(career, offer.playerId)} • '
                    '${offer.category == RosterCategory.twoWay ? 'Two-way' : 'Standard'} '
                    '${offer.durationYears}y • ${offer.firstYearSalary} CU',
                  ),
                  trailing: market.isCollecting
                      ? TextButton(
                          key: ValueKey('cancel-offer-${offer.playerId.value}'),
                          onPressed: () => onCancel(offer.playerId),
                          child: const Text('Cancel'),
                        )
                      : null,
                ),
            ],
            if (market.outcomes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Round results', style: theme.textTheme.labelLarge),
              for (final outcome in market.outcomes.take(8))
                Text(
                  _outcomeText(career, outcome),
                  style: theme.textTheme.bodySmall,
                ),
              if (market.outcomes.length > 8)
                Text('… ${market.outcomes.length - 8} more'),
            ],
          ],
        ),
      ),
    );
  }

  static String _statusLabel(FreeAgentMarketStatus status) => switch (status) {
    FreeAgentMarketStatus.notStarted => 'Not Started',
    FreeAgentMarketStatus.collectingHumanOffers => 'Offers Open',
    FreeAgentMarketStatus.preparedForResolution =>
      'Prepared — AI Offers Sealed',
    FreeAgentMarketStatus.resolving => 'Resolving',
    FreeAgentMarketStatus.roundComplete => 'Round Complete',
    FreeAgentMarketStatus.marketComplete => 'Market Complete',
    FreeAgentMarketStatus.recoveryRequired => 'Recovery Required',
  };

  static String _playerName(GmCareer career, PlayerId id) {
    final entry = career.freeAgentPool.byId(id);
    if (entry != null) return entry.player.fullName;
    for (final team in career.league.teams) {
      for (final player in team.players) {
        if (player.id == id) return player.fullName;
      }
    }
    return id.value;
  }

  static String _outcomeText(GmCareer career, FreeAgentMarketOutcome outcome) {
    final player = _playerName(career, outcome.playerId);
    if (outcome.winningTeamId == null) {
      return '$player: no signing';
    }
    final team = career.league.teams.firstWhere(
      (candidate) => candidate.id == outcome.winningTeamId,
    );
    final rejected = outcome.results
        .where(
          (result) => result.outcome == FreeAgentMarketOfferOutcome.rejected,
        )
        .length;
    final outbid = outcome.results
        .where((result) => result.outcome == FreeAgentMarketOfferOutcome.outbid)
        .length;
    return '$player → ${team.abbreviation} · $outbid outbid · $rejected rejected';
  }
}

class _FreeAgentCard extends StatelessWidget {
  const _FreeAgentCard({
    required this.entry,
    required this.valuation,
    required this.remainingAttempts,
    required this.canOffer,
    required this.onMakeOffer,
  });

  final FreeAgentEntry entry;
  final MarketValuation valuation;
  final int remainingAttempts;
  final bool canOffer;
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
                onPressed: canOffer && remainingAttempts > 0
                    ? onMakeOffer
                    : null,
                child: Text(
                  !canOffer
                      ? 'Offers Locked'
                      : (remainingAttempts > 0
                            ? 'Make Offer'
                            : 'No Offers Remaining'),
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
