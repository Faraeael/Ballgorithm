import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import '../../theme/hardwood_command_theme.dart';
import 'career_controller.dart';
import 'career_player_profile_screen.dart';
import 'career_rotation_screen.dart';
import 'widgets/hardwood_components.dart';

class CareerTradeScreen extends StatefulWidget {
  const CareerTradeScreen({super.key, required this.controller});

  final GmCareerController controller;

  @override
  State<CareerTradeScreen> createState() => _CareerTradeScreenState();
}

class _CareerTradeScreenState extends State<CareerTradeScreen> {
  TeamId? _partner;
  final Set<String> _selected = {};
  TradeOfferQuote? _quote;
  PlayerTradeProposal? _proposal;
  GmCareer? _quotedCareer;
  String? _message;

  GmCareerController get controller => widget.controller;

  void _invalidate() {
    _quote = null;
    _proposal = null;
    _quotedCareer = null;
    _message = null;
  }

  String? _windowReason(GmCareer career) {
    if (career.phase != CareerPhase.openingOffseason ||
        career.regularSeasonState != null) {
      return 'Trades are available only during the opening offseason.';
    }
    final draft = career.draftExecutionState;
    if (!draft.isNotStarted && !draft.isCompleted) {
      return 'Trades are locked while the draft is in progress.';
    }
    if (draft.isCompleted &&
        const RookieAiSigningService().pendingRights(career).isNotEmpty) {
      return 'Trades unlock after AI rookie signing decisions are complete.';
    }
    final market = career.freeAgentMarket.status;
    if (market != FreeAgentMarketStatus.notStarted &&
        market != FreeAgentMarketStatus.marketComplete) {
      return 'Trades are locked between free agency rounds.';
    }
    if (career.offseasonClearance.status !=
            OffseasonClearanceStatus.notStarted ||
        career.hardshipSettlement.status !=
            HardshipSettlementStatus.notStarted) {
      return 'Trades are closed after clearance or hardship begins.';
    }
    return null;
  }

  List<_TradeAsset> _assets(GmCareer career, Team team) {
    final previouslyTraded = {
      for (final record in career.tradeHistory)
        if (record.seasonYear == career.currentYear)
          for (final asset in record.assets) asset.canonicalKey,
    };
    final assets = <_TradeAsset>[];
    for (final player in team.players) {
      final contract = career.finances.contractForPlayer(player.id);
      if (contract == null ||
          contract.teamId != team.id ||
          !contract.isActiveIn(career.currentYear) ||
          contract.category == RosterCategory.trainingCamp ||
          career.finances.scheduleFor(contract.id) == null) {
        continue;
      }
      final schedule = career.finances.scheduleFor(contract.id)!;
      final age = career.careerProfiles.forPlayer(player.id)?.age;
      final key = 'player:${player.id.value}';
      assets.add(
        _TradeAsset(
          key: key,
          title: player.fullName,
          detail:
              '${player.position.shortName} • ${age == null ? 'Age unknown' : 'Age $age'} • OVR ${player.attributes.overallRating} • ${contract.category.jsonValue} • '
              'Year ${career.currentYear}: ${schedule.salaryForYear(career.currentYear)} CU • '
              'expires Year ${contract.startYear + contract.durationYears - 1} • ${schedule.guaranteedYears} guaranteed years • '
              'salary schedule: ${[for (var i = 0; i < schedule.annualSalaries.length; i++) 'Year ${schedule.signedYear + i}: ${schedule.annualSalaries[i]} CU'].join(', ')}',
          player: player,
          contract: contract,
          unavailable: previouslyTraded.contains(key),
        ),
      );
    }
    if (career.draftExecutionState.isNotStarted) {
      for (final pick in career.draftOrder.picksForTeam(team.id)) {
        final key = 'pick:${career.currentYear}:${pick.overallPick}';
        assets.add(
          _TradeAsset(
            key: key,
            title: 'Year ${career.currentYear} pick #${pick.overallPick}',
            detail:
                'Round ${pick.round} • original owner ${_teamName(career, pick.originalOwnerTeamId)}',
            pick: pick,
            unavailable: previouslyTraded.contains(key),
          ),
        );
      }
    }
    final rights = <DraftRights>[
      ...career.unsignedDraftRights,
      ...career.careerDraftRights.values.where(
        (r) => !career.rookieSigningLedger.isSigned(r.prospectId),
      ),
    ];
    for (final right in rights.where((r) => r.owningTeamId == team.id)) {
      final key = 'rights:${right.seasonYear}:${right.prospectId.value}';
      final prospect = career.draftClass.prospects
          .where((p) => p.id == right.prospectId)
          .firstOrNull;
      final carried = career.carriedUnsignedProspects[right.prospectId.value];
      final name =
          prospect?.fullName ??
          (carried == null
              ? right.prospectId.value
              : '${carried.firstName} ${carried.lastName}');
      assets.add(
        _TradeAsset(
          key: key,
          title: '$name draft rights',
          detail:
              'Year ${right.seasonYear} • pick #${right.overallPick} • no roster slot'
              '${prospect != null
                  ? ' • ${prospect.position.shortName}, age ${prospect.age}, public grade ${prospect.estimatedPotentialGrade}'
                  : carried != null
                  ? ' • ${carried.position.shortName}, age ${carried.age}, public grade ${carried.estimatedPotentialGrade}'
                  : ''}',
          rights: right,
          unavailable: previouslyTraded.contains(key),
        ),
      );
    }
    return assets;
  }

  String _teamName(GmCareer career, TeamId id) =>
      career.league.teams.where((t) => t.id == id).firstOrNull?.name ??
      id.value;

  PlayerTradeProposal _makeProposal(GmCareer career, Team other) {
    final first = _assets(
      career,
      career.userTeam,
    ).where((a) => _selected.contains(a.key)).toList();
    final second = _assets(
      career,
      other,
    ).where((a) => _selected.contains(a.key)).toList();
    List<PlayerTradeAsset> players(List<_TradeAsset> items) => [
      for (final a in items)
        if (a.player != null)
          (playerId: a.player!.id, contractId: a.contract!.id),
    ];
    List<DraftPickTradeAsset> picks(List<_TradeAsset> items, TeamId owner) => [
      for (final a in items)
        if (a.pick != null)
          (
            draftYear: career.currentYear,
            overallPick: a.pick!.overallPick,
            expectedOwner: owner,
          ),
    ];
    List<DraftRightsTradeAsset> rights(List<_TradeAsset> items, TeamId owner) =>
        [
          for (final a in items)
            if (a.rights != null)
              (
                draftYear: a.rights!.seasonYear,
                overallPick: a.rights!.overallPick,
                prospectId: a.rights!.prospectId,
                expectedOwner: owner,
              ),
        ];
    return PlayerTradeProposal(
      careerId: career.id,
      seasonYear: career.currentYear,
      expectedTradeCount: career.tradeHistory.length,
      firstTeam: career.userFranchiseId,
      secondTeam: other.id,
      fromFirst: players(first),
      fromSecond: players(second),
      picksFromFirst: picks(first, career.userFranchiseId),
      picksFromSecond: picks(second, other.id),
      rightsFromFirst: rights(first, career.userFranchiseId),
      rightsFromSecond: rights(second, other.id),
    );
  }

  void _preview(GmCareer career, Team other) {
    try {
      final proposal = _makeProposal(career, other);
      final quote = controller.evaluateTrade(proposal);
      setState(() {
        _proposal = proposal;
        _quote = quote;
        _quotedCareer = career;
        _message = null;
      });
    } catch (error) {
      setState(() {
        _invalidate();
        _message = 'Unable to preview trade: $error';
      });
    }
  }

  Future<void> _confirm(GmCareer career, Team other) async {
    final quote = _quote;
    final proposal = _proposal;
    if (quote == null ||
        proposal == null ||
        !identical(career, controller.career)) {
      return;
    }
    final first = _assets(
      career,
      career.userTeam,
    ).where((a) => _selected.contains(a.key));
    final second = _assets(
      career,
      other,
    ).where((a) => _selected.contains(a.key));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm trade'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Year ${career.currentYear} • YOU SEND (${career.userTeam.name}):',
              ),
              for (final asset in first)
                Text('• ${asset.title} — ${asset.detail}'),
              const SizedBox(height: 12),
              Text('YOU RECEIVE (${other.name} sends):'),
              for (final asset in second)
                Text('• ${asset.title} — ${asset.detail}'),
              const SizedBox(height: 12),
              const Text(
                'Existing contracts and their guaranteed salaries transfer with the players.',
              ),
              for (final team in [career.userTeam, other])
                if (quote.teamPreviews[team.id] case final preview?)
                  _teamPreview(career, team, preview),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm trade'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!identical(career, controller.career) ||
        controller.isLoading ||
        controller.draftRecoveryRequired) {
      setState(() {
        _invalidate();
        _message = 'Trade quote is stale. Preview again before confirming.';
      });
      return;
    }
    try {
      await controller.executeTrade(proposal, quote);
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _invalidate();
        _message = controller.draftRecoveryRequired
            ? 'Save failed or its outcome is uncertain. Reload and check trade history before retrying.'
            : 'Trade saved. See trade history below.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _invalidate();
        _message = controller.draftRecoveryRequired
            ? 'Save failed or its outcome is uncertain. Reload and check trade history before retrying.'
            : 'Trade not completed. The quote may be stale; preview again. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final career = controller.career;
      if (career == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final t = context.tokens;
      final teams = career.league.teams
          .where((team) => team.id != career.userFranchiseId)
          .toList();
      final other = teams.where((team) => team.id == _partner).firstOrNull;
      final reason = _windowReason(career);
      final blocked =
          reason != null ||
          controller.isLoading ||
          controller.draftRecoveryRequired;
      final stale = _quote != null && !identical(_quotedCareer, career);
      final quote = stale ? null : _quote;
      return Scaffold(
        appBar: AppBar(title: const Text('Trade Center')),
        body: SafeArea(
          child: ListView(
            key: const ValueKey('trade-center-scroll'),
            padding: EdgeInsets.all(t.space300),
            children: [
              if (reason != null)
                Text(reason, key: const ValueKey('trade-window-reason')),
              if (controller.draftRecoveryRequired) ...[
                Text(
                  controller.errorMessage ??
                      'Save failed or its outcome is uncertain. Reload and check trade history before retrying.',
                ),
                HardwoodSecondaryButton(
                  label: 'Reload saved career',
                  onPressed: controller.isLoading
                      ? null
                      : () => controller.loadCareer(),
                ),
              ],
              if (controller.isLoading) const LinearProgressIndicator(),
              if (_message != null)
                Text(_message!, key: const ValueKey('trade-message')),
              if (stale)
                const Text(
                  'Trade quote is stale. Preview again before confirming.',
                  key: ValueKey('trade-stale'),
                ),
              const SizedBox(height: 16),
              DropdownButtonFormField<TeamId>(
                initialValue: other?.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Trade partner'),
                items: [
                  for (final team in teams)
                    DropdownMenuItem(
                      value: team.id,
                      child: Text(team.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: blocked
                    ? null
                    : (id) => setState(() {
                        _partner = id;
                        _selected.clear();
                        _invalidate();
                      }),
              ),
              if (other != null) ...[
                const SizedBox(height: 16),
                _assetSection(career, career.userTeam, blocked),
                _assetSection(career, other, blocked),
                HardwoodSecondaryButton(
                  key: const ValueKey('trade-preview'),
                  label: 'Preview trade',
                  onPressed: blocked ? null : () => _preview(career, other),
                ),
                if (quote != null) ...[
                  const SizedBox(height: 16),
                  _quoteView(career, other, quote),
                  if (quote.status == TradeOfferStatus.legalAccepted)
                    HardwoodSecondaryButton(
                      key: const ValueKey('trade-confirm'),
                      label: 'Review and confirm trade',
                      onPressed: blocked ? null : () => _confirm(career, other),
                    ),
                ],
              ],
              const SizedBox(height: 16),
              const Text(
                'Trades can leave manual rotation assignments unassigned. Review your plan before playing.',
              ),
              HardwoodSecondaryButton(
                key: const ValueKey('trade-rotation-repair'),
                label: 'Open Lineup & Rotation',
                onPressed: controller.isLoading
                    ? null
                    : () => openCareerRotationEditor(context, controller),
              ),
              const SizedBox(height: 24),
              Text(
                'TRADE HISTORY',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (career.tradeHistory.isEmpty)
                const Text('No completed trades yet.'),
              for (final receipt in career.tradeHistory.reversed)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Year ${receipt.seasonYear} • ${receipt.id}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          '${_teamName(career, receipt.firstTeam)} / ${_teamName(career, receipt.secondTeam)}',
                        ),
                        Text(
                          '${_teamName(career, receipt.firstTeam)} recorded payroll impact: cap ${receipt.firstTeamImpact.capPayrollDelta} CU; cash ${receipt.firstTeamImpact.cashPayrollDelta} CU',
                        ),
                        for (final asset in receipt.assets)
                          Text(
                            '${_receiptAsset(career, asset.kind.name, asset.playerId, asset.draftYear, asset.overallPick, asset.contractId, asset.startYear, asset.endYear)}: ${_teamName(career, asset.from)} → ${_teamName(career, asset.to)}',
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  String _receiptAsset(
    GmCareer career,
    String kind,
    PlayerId? playerId,
    int? draftYear,
    int? overallPick,
    String? contractId,
    int? startYear,
    int? endYear,
  ) {
    if (kind == 'pick') return 'Year $draftYear pick #$overallPick';
    final id = playerId!;
    final player = career.league.teams
        .expand((t) => t.players)
        .where((p) => p.id == id)
        .firstOrNull;
    final prospect = career.draftClass.prospects
        .where((p) => p.id == id)
        .firstOrNull;
    final carried = career.carriedUnsignedProspects[id.value];
    final name =
        player?.fullName ??
        prospect?.fullName ??
        (carried == null
            ? id.value
            : '${carried.firstName} ${carried.lastName}');
    return kind == 'rights'
        ? '$name rights (Year $draftYear, #$overallPick)'
        : '$name (contract $contractId, Years $startYear–$endYear)';
  }

  Widget _assetSection(GmCareer career, Team team, bool blocked) {
    final assets = _assets(career, team);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${team.id == career.userFranchiseId ? 'YOU SEND' : 'YOU RECEIVE'} • ${team.name}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (assets.isEmpty) const Text('No available trade assets.'),
        for (final asset in assets)
          Card(
            child: Column(
              children: [
                CheckboxListTile(
                  key: ValueKey('trade-asset-${asset.key}'),
                  value: _selected.contains(asset.key),
                  title: Text(asset.title),
                  subtitle: Text(
                    '${asset.detail}${asset.unavailable ? ' • Already traded this offseason' : ''}',
                  ),
                  onChanged: blocked || asset.unavailable
                      ? null
                      : (value) => setState(() {
                          if (value == true) {
                            _selected.add(asset.key);
                          } else {
                            _selected.remove(asset.key);
                          }
                          _invalidate();
                        }),
                ),
                if (asset.player != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => CareerPlayerProfileScreen(
                            dossier: RosteredPlayerDossier(
                              player: asset.player!,
                              team: team,
                              category: asset.contract!.category,
                              currentYear: career.currentYear,
                              isUserTeam: team.id == career.userFranchiseId,
                              profile: career.careerProfiles.forPlayer(
                                asset.player!.id,
                              ),
                              contract: asset.contract,
                              schedule: career.finances.scheduleFor(
                                asset.contract!.id,
                              ),
                            ),
                          ),
                        ),
                      ),
                      child: const Text('Inspect player and contract'),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _quoteView(GmCareer career, Team other, TradeOfferQuote quote) {
    final decision = switch (quote.status) {
      TradeOfferStatus.illegal =>
        'Illegal trade: ${_legalReason(quote.legalReason)}',
      TradeOfferStatus.legalRejected =>
        'Legal trade, rejected: ${_valuationReason(quote.valuation!.reason)}',
      TradeOfferStatus.legalAccepted =>
        'Legal trade, accepted by ${other.name}.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          decision,
          key: const ValueKey('trade-quote-status'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final team in [career.userTeam, other])
          if (quote.teamPreviews[team.id] case final preview?)
            _teamPreview(career, team, preview),
        const Text(
          'Projected cash includes operating commitments; cap payroll does not.',
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _teamPreview(
    GmCareer career,
    Team team,
    TradeTeamPreview preview,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      Text(team.name, style: Theme.of(context).textTheme.titleSmall),
      Text(
        'Cap payroll: ${preview.capPayrollBefore} → ${preview.capPayrollAfter} CU',
      ),
      Text(
        'Cap room: ${FinancialRules.salaryCap - preview.capPayrollBefore} → ${FinancialRules.salaryCap - preview.capPayrollAfter} CU',
      ),
      Text(
        'Cash payroll (including guarantees): ${preview.cashPayrollBefore} → ${preview.cashPayrollAfter} CU',
      ),
      Text(
        'Projected cash after debt: ${preview.projectedCashAfterDebtBefore} → ${preview.projectedCashAfterDebtAfter} CU',
      ),
      Text(
        'Minimum roster reserve: ${preview.minimumRosterReserveBefore} → ${preview.minimumRosterReserveAfter} CU',
      ),
      Text(
        'Standard slots: ${preview.standardPlayersBefore} → ${preview.standardPlayersAfter}; two-way: ${preview.twoWayPlayersBefore} → ${preview.twoWayPlayersAfter}',
      ),
      Text(
        'Missing standard slots: ${(FinancialRules.minimumStandardRoster - preview.standardPlayersBefore).clamp(0, FinancialRules.minimumStandardRoster)} → ${(FinancialRules.minimumStandardRoster - preview.standardPlayersAfter).clamp(0, FinancialRules.minimumStandardRoster)}',
      ),
      _positions(career, team),
    ],
  );

  Widget _positions(GmCareer career, Team team) {
    final otherId = team.id == career.userFranchiseId
        ? _partner
        : career.userFranchiseId;
    final other = career.league.teams.firstWhere((t) => t.id == otherId);
    final departing = _assets(
      career,
      team,
    ).where((a) => _selected.contains(a.key) && a.player != null).toList();
    final arriving = _assets(
      career,
      other,
    ).where((a) => _selected.contains(a.key) && a.player != null).toList();
    final before = team.roster.standardPlayers;
    final after = [
      ...before.where((p) => !departing.any((a) => a.player!.id == p.id)),
      for (final a in arriving)
        if (a.contract!.category == RosterCategory.standard) a.player!,
    ];
    String missing(Iterable<Player> players) {
      final absent = Position.values
          .where((p) => !players.any((player) => player.position == p))
          .map((p) => p.shortName)
          .join(', ');
      return absent.isEmpty ? 'none' : absent;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Missing positions: ${missing(before)} → ${missing(after)}'),
      ],
    );
  }

  String _legalReason(PlayerTradeRejection? reason) => switch (reason) {
    PlayerTradeRejection.windowClosed => 'Trade window is closed.',
    PlayerTradeRejection.invalidFranchises => 'Choose a valid trade partner.',
    PlayerTradeRejection.emptySide => 'Each team must send at least one asset.',
    PlayerTradeRejection.duplicateAsset => 'An asset appears more than once.',
    PlayerTradeRejection.staleProposal =>
      'Career changed; compose and preview again.',
    PlayerTradeRejection.unavailableAsset => 'An asset is unavailable.',
    PlayerTradeRejection.staleOwnership => 'Asset ownership changed.',
    PlayerTradeRejection.staleContract => 'A player contract changed.',
    PlayerTradeRejection.alreadyTraded =>
      'An asset was already traded this offseason.',
    PlayerTradeRejection.rosterLimit => 'A roster would exceed its limits.',
    PlayerTradeRejection.capPayroll =>
      'Current cap payroll rules would be violated.',
    PlayerTradeRejection.futureCapPayroll =>
      'Future scheduled cap payroll would be violated.',
    PlayerTradeRejection.cashReserve =>
      'Projected cash cannot cover the minimum roster reserve.',
    PlayerTradeRejection.invalidCareer =>
      'The resulting career would be invalid.',
    null => 'The trade cannot be evaluated.',
  };

  String _valuationReason(TradeEvaluationReason reason) => switch (reason) {
    TradeEvaluationReason.accepted => 'Accepted.',
    TradeEvaluationReason.missingNaturalPosition =>
      'The team would lose its last natural option at a position.',
    TradeEvaluationReason.eliteReplacement =>
      'The team needs a comparable replacement for a top starter.',
    TradeEvaluationReason.guaranteeBurden =>
      'Additional guarantees lack enough compensation.',
    TradeEvaluationReason.insufficientValue =>
      'The package does not provide enough value.',
  };
}

class _TradeAsset {
  const _TradeAsset({
    required this.key,
    required this.title,
    required this.detail,
    required this.unavailable,
    this.player,
    this.contract,
    this.pick,
    this.rights,
  });
  final String key;
  final String title;
  final String detail;
  final bool unavailable;
  final Player? player;
  final PlayerContract? contract;
  final DraftPick? pick;
  final DraftRights? rights;
}
