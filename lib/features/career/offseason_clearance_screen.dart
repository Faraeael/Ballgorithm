import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import 'career_controller.dart';

const _gate = OffseasonReadinessGate();
const _market = FreeAgentMarketValueService();
const _hardship = HardshipSettlementService();

class GmOffseasonClearanceScreen extends StatelessWidget {
  const GmOffseasonClearanceScreen({super.key, required this.controller});

  final GmCareerController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final career = controller.career;
      if (career == null) {
        return const Scaffold(body: Center(child: Text('No active career')));
      }
      final readiness = _gate.evaluate(
        career,
        recoveryRequired: controller.draftRecoveryRequired,
      );
      final clearance = career.offseasonClearance;
      final hardship = career.hardshipSettlement;
      final humanHardship = _hardship.assessTeam(
        career,
        career.userFranchiseId,
      );
      final canStartHardship =
          clearance.status == OffseasonClearanceStatus.complete &&
          hardship.status == HardshipSettlementStatus.notStarted &&
          readiness.belowMinimumCount > 0;
      final theme = Theme.of(context);
      return Scaffold(
        key: const ValueKey('offseason-clearance'),
        appBar: AppBar(title: const Text('Offseason Clearance')),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      readiness.status.name,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ready ${readiness.readyCount}/30 • below 14 '
                      '${readiness.belowMinimumCount} • shortage '
                      '${readiness.totalShortage} • human shortage '
                      '${readiness.humanShortage}',
                    ),
                    for (final reason in readiness.reasons)
                      Text('• $reason', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            if (controller.draftRecoveryRequired) ...[
              const SizedBox(height: 8),
              const Text('Reload saved career before continuing.'),
              FilledButton(
                key: const ValueKey('reload-after-save-failure'),
                onPressed: controller.isLoading
                    ? null
                    : () => _run(context, () => controller.loadCareer()),
                child: const Text('Reload Saved Career'),
              ),
            ],
            const SizedBox(height: 8),
            if (readiness.status ==
                    OffseasonReadinessStatus.clearanceRequired &&
                clearance.status == OffseasonClearanceStatus.notStarted)
              FilledButton(
                key: const ValueKey('start-clearance'),
                onPressed: () =>
                    _run(context, () => controller.startOffseasonClearance()),
                child: const Text('Start Clearance Pass'),
              ),
            if (clearance.isCollecting) ...[
              Text('Human clearance offers', style: theme.textTheme.titleSmall),
              Text(
                'Only standard 1-year minimum offers are offered here. '
                'The human GM must confirm each offer.',
              ),
              for (final offer in clearance.humanOffers)
                ListTile(
                  dense: true,
                  title: Text(
                    '${_playerName(career, offer.playerId)} • '
                    '${offer.firstYearSalary} CU',
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('prepare-clearance'),
                onPressed: () =>
                    _run(context, () => controller.prepareOffseasonClearance()),
                child: const Text('Lock Clearance Offers'),
              ),
              const SizedBox(height: 8),
              Text('Available players', style: theme.textTheme.titleSmall),
              for (final entry in career.freeAgentPool.entries.take(20))
                ListTile(
                  dense: true,
                  title: Text(
                    '${entry.player.fullName} • '
                    '${entry.player.position.shortName} • OVR '
                    '${entry.player.attributes.overallRating} • est '
                    '${_market.estimate(entry.toPublicView()).estimatedAnnualSalary} CU',
                  ),
                  trailing: TextButton(
                    key: ValueKey('clearance-offer-${entry.id.value}'),
                    onPressed: () => _confirmOffer(context, career, entry),
                    child: const Text('Offer 400'),
                  ),
                ),
            ],
            if (clearance.isResolvable)
              FilledButton(
                key: const ValueKey('resolve-clearance'),
                onPressed: () =>
                    _run(context, () => controller.resolveOffseasonClearance()),
                child: const Text('Resolve Clearance'),
              ),
            if (clearance.outcomes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Clearance outcomes', style: theme.textTheme.titleSmall),
              for (final outcome in clearance.outcomes)
                Text(
                  '${_playerName(career, outcome.playerId)}: '
                  '${outcome.winningTeamId == null ? 'no signing' : 'signed'}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
            if (hardship.isResolvable)
              FilledButton(
                key: const ValueKey('resolve-hardship'),
                onPressed: () =>
                    _run(context, () => controller.resolveHardshipSettlement()),
                child: const Text('Resolve Hardship Settlement'),
              ),
            if (hardship.status == HardshipSettlementStatus.complete &&
                hardship.offers.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Hardship outcomes', style: theme.textTheme.titleSmall),
              for (final outcome in hardship.outcomes)
                Text(
                  '${_playerName(career, outcome.playerId)}: '
                  '${outcome.winningTeamId == null ? 'no signing' : 'signed'}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
            if (canStartHardship) ...[
              const SizedBox(height: 12),
              Text(
                'One-time roster hardship',
                style: theme.textTheme.titleSmall,
              ),
              Text(
                'Only mandatory vacancies qualify. Existing cap room and '
                'ordinary minimum relief must be insufficient.',
              ),
              if (humanHardship.eligible) ...[
                Text(
                  '${humanHardship.missingPlayers} missing standard player(s) • '
                  'payroll ${humanHardship.currentPayroll} CU • '
                  'ordinary exception ${humanHardship.ordinaryRelief} CU',
                ),
                Text(
                  'Additional authority ${humanHardship.additionalAuthority} CU • '
                  'combined overage ${humanHardship.combinedOverage} CU • '
                  'cash after offers ${humanHardship.projectedCashAfterOffers} CU',
                ),
                for (final offer in humanHardship.proposedOffers)
                  _hardshipOfferTile(career, offer),
                FilledButton(
                  key: const ValueKey('confirm-human-hardship'),
                  onPressed: controller.isLoading
                      ? null
                      : () => _confirmHardship(context, career, humanHardship),
                  child: const Text('Review and Confirm Human Participation'),
                ),
              ] else ...[
                Text(
                  humanHardship.blockers.isEmpty
                      ? 'Human franchise has no hardship offer.'
                      : humanHardship.blockers.join('; '),
                ),
              ],
              FilledButton(
                key: const ValueKey('prepare-ai-hardship'),
                onPressed: controller.isLoading
                    ? null
                    : () => _run(
                        context,
                        () => controller.prepareHardshipSettlement(
                          humanParticipationConfirmed: false,
                        ),
                      ),
                child: const Text('Prepare AI Hardship Decisions'),
              ),
            ],
            if (readiness.status ==
                OffseasonReadinessStatus.readyForConfirmation) ...[
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('mark-cleared'),
                onPressed: () =>
                    _run(context, () => controller.markOffseasonCleared()),
                child: const Text('Confirm Offseason Cleared'),
              ),
            ],
            if (readiness.status ==
                OffseasonReadinessStatus.financialExceptionRequired) ...[
              const SizedBox(height: 8),
              const Text(
                'Some franchises remain blocked by approved cap, cash, '
                'player-acceptance, or roster rules.',
              ),
            ],
          ],
        ),
      );
    },
  );
  Future<void> _confirmHardship(
    BuildContext context,
    GmCareer career,
    HardshipTeamAssessment assessment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm hardship participation'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${assessment.missingPlayers} mandatory roster spot(s). '
                'Current payroll ${assessment.currentPayroll} CU.',
              ),
              Text(
                'Existing exception ${assessment.ordinaryRelief} CU; '
                'additional authority ${assessment.additionalAuthority} CU; '
                'combined overage ${assessment.combinedOverage} CU.',
              ),
              Text(
                'Projected cash after offers: '
                '${assessment.projectedCashAfterOffers} CU.',
              ),
              for (final offer in assessment.proposedOffers)
                _hardshipOfferTile(career, offer),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Decline'),
          ),
          FilledButton(
            key: const ValueKey('approve-human-hardship'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _run(
      context,
      () => controller.prepareHardshipSettlement(
        humanParticipationConfirmed: true,
      ),
    );
  }

  Widget _hardshipOfferTile(GmCareer career, HardshipOffer offer) {
    final entry = career.freeAgentPool.byId(offer.playerId);
    final player = entry?.player;
    final name = player?.fullName ?? offer.playerId.value;
    final publicDetails = entry == null
        ? ''
        : ' • ${player!.position.shortName} • age ${entry.profile.age} • '
              'OVR ${player.attributes.overallRating}';
    final future = offer.salarySchedule.skip(1).fold<int>(0, (a, b) => a + b);
    return ListTile(
      dense: true,
      title: Text('$name$publicDetails'),
      subtitle: Text(
        '${offer.durationYears}-year contract • '
        '${offer.salarySchedule.join(' / ')} CU per year • '
        '$future CU future commitment',
      ),
    );
  }

  Future<void> _confirmOffer(
    BuildContext context,
    GmCareer career,
    FreeAgentEntry entry,
  ) async {
    final salaryController = TextEditingController(text: '400');
    final salary = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clearance Offer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${entry.player.fullName}\nStandard • 1 year'),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('clearance-salary'),
              controller: salaryController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'First-year salary (400–8000)',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This is a bounded compliance offer, not a third market round. '
              'AI clubs may compete for the same player.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-clearance-offer'),
            onPressed: () {
              final offered = int.tryParse(salaryController.text.trim());
              if (offered == null) return;
              Navigator.of(context).pop(offered);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    salaryController.dispose();
    if (salary == null || !context.mounted) return;
    await _run(
      context,
      () => controller.stageClearanceOffer(
        freeAgentId: entry.id,
        durationYears: 1,
        firstYearSalary: salary,
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

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
}
