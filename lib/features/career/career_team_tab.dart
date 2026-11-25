import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import '../../theme/hardwood_command_theme.dart';
import 'career_controller.dart';
import 'career_player_profile_screen.dart';
import 'career_rotation_screen.dart';
import 'career_ui_labels.dart';
import 'widgets/hardwood_components.dart';

enum _TeamSubView { rosterAndDepth, capAndContracts }

/// D02 Team Roster & Depth + Cap & Contracts destination.
class CareerTeamTab extends StatefulWidget {
  const CareerTeamTab({super.key, required this.controller});

  final GmCareerController controller;

  @override
  State<CareerTeamTab> createState() => _CareerTeamTabState();
}

class _CareerTeamTabState extends State<CareerTeamTab> {
  _TeamSubView _subView = _TeamSubView.rosterAndDepth;
  Position? _selectedPosition; // null == ALL
  bool _showLimitsHelp = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final career = widget.controller.career;
    if (career == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final team = career.userTeam;
    final finances = career.finances.financesFor(team.id);
    final capPayroll = career.finances.capPayrollFor(
      team.id,
      career.currentYear,
    );
    final capRoom = FinancialRules.salaryCap - capPayroll;
    final projectedCash = career.finances.projectedEndOfSeasonCash(
      team.id,
      career.currentYear,
    );

    return ListView(
      key: const ValueKey('career-team-tab'),
      padding: EdgeInsets.all(t.space300),
      children: [
        _buildSubViewSwitcher(t),
        SizedBox(height: t.space300),
        if (_subView == _TeamSubView.rosterAndDepth) ...[
          // M010: lineup/rotation lives with roster & depth, above the roster.
          _buildRotationEntry(context, t, career),
          SizedBox(height: t.space300),
          _buildRosterSummaryCard(t, career, team, capRoom),
          SizedBox(height: t.space200),
          _buildPositionFilterBar(t, team),
          SizedBox(height: t.space200),
          for (final pos
              in _selectedPosition == null
                  ? Position.values
                  : <Position>[_selectedPosition!])
            _buildPositionGroup(context, t, career, team, pos),
        ] else ...[
          _buildCapOverviewCard(
            t,
            career: career,
            team: team,
            finances: finances,
            capPayroll: capPayroll,
            capRoom: capRoom,
            projectedCash: projectedCash,
          ),
          SizedBox(height: t.space300),
          _buildMultiYearCommitmentsCard(t, career, team),
          SizedBox(height: t.space300),
          _buildExpiringContractsSection(context, t, career, team),
          SizedBox(height: t.space300),
          _buildAllContractsSection(context, t, career, team),
        ],
      ],
    );
  }

  /// Prominent M010 entry: current control mode and real readiness.
  Widget _buildRotationEntry(
    BuildContext context,
    HardwoodCommandTokens t,
    GmCareer career,
  ) {
    final manual = career.userRotation.isManual;
    String readiness;
    var ready = true;
    try {
      final resolution = CareerRotationService.resolveForCareer(career);
      ready = resolution.isValid;
      readiness = ready
          ? (resolution.unassignedPlayerIds.isEmpty
                ? 'Ready for simulation'
                : '${resolution.unassignedPlayerIds.length} new player(s) at 0:00')
          : '${resolution.issues.length} issue(s) — needs attention';
    } catch (_) {
      // Early offseason: fewer than five standard players or an uncovered
      // position. Roster readiness rules handle this before tip-off.
      ready = false;
      readiness = 'Roster not ready for a lineup yet';
    }
    return AppPressable(
      key: const ValueKey('team-rotation-entry'),
      semanticLabel: 'Open Lineup and Rotation',
      onPressed: () => openCareerRotationEditor(context, widget.controller),
      borderRadius: BorderRadius.circular(t.radiusLg),
      child: Container(
        padding: EdgeInsets.all(t.space300),
        decoration: BoxDecoration(
          color: t.bgSurface,
          borderRadius: BorderRadius.circular(t.radiusLg),
          border: Border.all(
            color: ready ? t.accentPrimary : t.statusDanger,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.sports_basketball, color: t.accentPrimary),
            SizedBox(width: t.space300),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LINEUP & ROTATION',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                  SizedBox(height: t.space100),
                  Text(
                    '${manual ? 'MANUAL' : 'AUTO'} · $readiness',
                    key: const ValueKey('team-rotation-status'),
                    style: TextStyle(
                      color: ready ? t.textSecondary : t.statusDangerFg,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: t.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildSubViewSwitcher(HardwoodCommandTokens t) {
    return Row(
      children: [
        Expanded(
          child: _subViewButton(
            t,
            key: const ValueKey('team-view-roster'),
            label: 'ROSTER & DEPTH',
            selected: _subView == _TeamSubView.rosterAndDepth,
            onTap: () => setState(() => _subView = _TeamSubView.rosterAndDepth),
          ),
        ),
        SizedBox(width: t.space200),
        Expanded(
          child: _subViewButton(
            t,
            key: const ValueKey('team-view-cap'),
            label: 'CAP & CONTRACTS',
            selected: _subView == _TeamSubView.capAndContracts,
            onTap: () =>
                setState(() => _subView = _TeamSubView.capAndContracts),
          ),
        ),
      ],
    );
  }

  Widget _subViewButton(
    HardwoodCommandTokens t, {
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return AppPressable(
      key: key,
      minHeight: t.touchMin,
      semanticLabel: label,
      onPressed: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: t.touchMin),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: t.space200),
        decoration: BoxDecoration(
          color: selected ? t.accentSecondaryBg : t.bgSurface,
          borderRadius: BorderRadius.circular(t.radiusMd),
          border: Border.all(
            color: selected ? t.accentSecondary : t.borderSubtle,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? t.accentSecondaryFg : t.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }

  Widget _buildRosterSummaryCard(
    HardwoodCommandTokens t,
    GmCareer career,
    Team team,
    int capRoom,
  ) {
    final isOffseason = career.phase == CareerPhase.openingOffseason;
    final maxStd = isOffseason
        ? RosterRules.maxOffseasonStandard
        : RosterRules.maxRegularSeasonStandard;
    final maxTwoWay = isOffseason
        ? RosterRules.maxOffseasonTwoWay
        : RosterRules.maxRegularSeasonTwoWay;
    final maxTotal = isOffseason
        ? RosterRules.maxOffseasonTotal
        : RosterRules.maxRegularSeasonTotal;
    const minStd = RosterRules.minRegularSeasonStandard;
    final meetsMinStd = team.roster.standardCount >= minStd;

    return Container(
      key: const ValueKey('team-roster-summary-card'),
      padding: EdgeInsets.symmetric(
        horizontal: t.space300,
        vertical: t.space200,
      ),
      decoration: BoxDecoration(
        color: t.bgSurface,
        borderRadius: BorderRadius.circular(t.radiusLg),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'ROSTER & PHASE LIMITS',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              SizedBox(width: t.space200),
              Text(
                CareerUiLabels.phaseName(career.phase),
                style: TextStyle(
                  color: t.accentSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: t.space300,
            runSpacing: 6,
            children: [
              _metric(
                t,
                'Standard (Min $minStd)',
                '${team.roster.standardCount} / $maxStd',
                valueColor: meetsMinStd ? t.statusSuccessFg : t.statusWarningFg,
              ),
              _metric(t, 'Two-Way', '${team.roster.twoWayCount} / $maxTwoWay'),
              _metric(t, 'Total', '${team.players.length} / $maxTotal'),
              _metric(
                t,
                capRoom >= 0 ? 'Cap Room' : 'Over Cap',
                '${capRoom >= 0 ? '+' : ''}${CareerUiLabels.formatCu(capRoom)}',
                valueColor: capRoom >= 0
                    ? t.statusSuccessFg
                    : t.statusWarningFg,
              ),
            ],
          ),
          const SizedBox(height: 4),
          AppPressable(
            key: const ValueKey('team-roster-limits-toggle'),
            minHeight: t.touchMin,
            semanticLabel: 'Toggle roster category limits info',
            onPressed: () => setState(() => _showLimitsHelp = !_showLimitsHelp),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: t.accentSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isOffseason
                          ? 'Min $minStd Std across 5 pos to enter season • Category limits'
                          : 'Active limits: $minStd–$maxStd Std, up to $maxTwoWay 2-Way ($maxTotal total)',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _showLimitsHelp
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: t.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_showLimitsHelp) ...[
            const SizedBox(height: 4),
            Container(
              key: const ValueKey('team-roster-limits-detail'),
              padding: EdgeInsets.all(t.space200),
              decoration: BoxDecoration(
                color: t.bgElevated,
                borderRadius: BorderRadius.circular(t.radiusMd),
                border: Border.all(color: t.borderSubtle),
              ),
              child: Text(
                isOffseason
                    ? 'Offseason limits: max ${RosterRules.maxOffseasonStandard} '
                          'Standard, max ${RosterRules.maxOffseasonTwoWay} Two-Way, '
                          'and ${RosterRules.maxOffseasonTotal} total combined '
                          '(the 21-player ceiling does not override individual '
                          'category limits). Entering the Regular Season requires '
                          'at least $minStd Standard players covering all 5 positions.'
                    : 'Regular-season limits: $minStd–${RosterRules.maxRegularSeasonStandard} '
                          'Standard players, max ${RosterRules.maxRegularSeasonTwoWay} '
                          'Two-Way players, and ${RosterRules.maxRegularSeasonTotal} total.',
                style: TextStyle(color: t.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPositionFilterBar(HardwoodCommandTokens t, Team team) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(
                  t,
                  key: const ValueKey('team-filter-ALL'),
                  label: 'ALL (${team.players.length})',
                  selected: _selectedPosition == null,
                  onTap: () => setState(() => _selectedPosition = null),
                ),
                for (final pos in Position.values) ...[
                  SizedBox(width: t.space200),
                  _filterChip(
                    t,
                    key: ValueKey('team-filter-${pos.shortName}'),
                    label:
                        '${pos.shortName} (${team.players.where((p) => p.position == pos).length})',
                    selected: _selectedPosition == pos,
                    onTap: () => setState(() => _selectedPosition = pos),
                  ),
                ],
              ],
            ),
          ),
        ),
        SizedBox(width: t.space100),
        Icon(Icons.chevron_right_rounded, size: 18, color: t.textMuted),
      ],
    );
  }

  Widget _filterChip(
    HardwoodCommandTokens t, {
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return AppPressable(
      key: key,
      minWidth: 52,
      minHeight: t.touchMin,
      semanticLabel: 'Filter $label',
      onPressed: onTap,
      child: Container(
        constraints: BoxConstraints(minWidth: 52, minHeight: t.touchMin),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: t.space300),
        decoration: BoxDecoration(
          color: selected ? t.accentPrimaryTint : t.bgSurface,
          borderRadius: BorderRadius.circular(t.radiusMd),
          border: Border.all(
            color: selected ? t.borderActive : t.borderSubtle,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? t.accentPrimary : t.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildPositionGroup(
    BuildContext context,
    HardwoodCommandTokens t,
    GmCareer career,
    Team team,
    Position pos,
  ) {
    final players =
        team.players.where((player) => player.position == pos).toList()..sort(
          (a, b) =>
              b.attributes.overallRating.compareTo(a.attributes.overallRating),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: t.space300),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${pos.fullName.toUpperCase()} (${players.length})',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          if (players.isEmpty)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(t.space300),
              decoration: BoxDecoration(
                color: t.statusDangerBg,
                borderRadius: BorderRadius.circular(t.radiusMd),
                border: Border.all(color: t.statusDanger),
              ),
              child: Text(
                'No ${pos.fullName} currently signed.',
                style: TextStyle(color: t.statusDangerFg, fontSize: 14),
              ),
            )
          else
            for (final player in players)
              _buildPlayerRow(context, t, career, team, player),
        ],
      ),
    );
  }

  Widget _buildPlayerRow(
    BuildContext context,
    HardwoodCommandTokens t,
    GmCareer career,
    Team team,
    Player player,
  ) {
    final profile = career.careerProfiles.forPlayer(player.id);
    final category = team.roster.categoryOf(player.id);
    final contract = career.finances.contractForPlayer(player.id);
    final schedule = contract == null
        ? null
        : career.finances.scheduleFor(contract.id);
    final salary = schedule?.salaryForYear(career.currentYear);
    final yearsLeft = contract == null
        ? null
        : (contract.startYear + contract.durationYears) - career.currentYear;
    final isTwoWay = category == RosterCategory.twoWay;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AppPressable(
        key: ValueKey('team-player-row-${player.id.value}'),
        minHeight: t.touchMin,
        semanticLabel: '${player.fullName} profile',
        onPressed: () =>
            _openPlayerProfile(context, career, team, player, initialTab: 0),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: t.space300, vertical: 6),
          decoration: BoxDecoration(
            color: t.bgSurface,
            borderRadius: BorderRadius.circular(t.radiusMd),
            border: Border.all(color: t.borderSubtle),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              OverallRatingBadge(
                overall: player.attributes.overallRating,
                subLabel: player.position.shortName,
                compact: true,
              ),
              SizedBox(width: t.space200),
              PlayerMonogramBadge(fullName: player.fullName, size: 34),
              SizedBox(width: t.space200),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            player.fullName,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        SizedBox(width: t.space200),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isTwoWay
                                ? t.accentSecondaryBg
                                : t.accentPrimaryTint,
                            borderRadius: BorderRadius.circular(t.radiusSm),
                            border: Border.all(
                              color: isTwoWay
                                  ? t.accentSecondary
                                  : t.accentPrimary.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            isTwoWay ? '2-WAY' : 'STD',
                            style: TextStyle(
                              color: isTwoWay
                                  ? t.accentSecondaryFg
                                  : t.accentPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Age ${profile?.age ?? '-'} • POT ${profile?.potential ?? '-'} • '
                      '${salary == null ? 'N/A' : CareerUiLabels.formatCu(salary)} '
                      '(${yearsLeft == null || yearsLeft <= 0 ? 'Exp' : '${yearsLeft}y'})',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: t.textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapOverviewCard(
    HardwoodCommandTokens t, {
    required GmCareer career,
    required Team team,
    required TeamFinances finances,
    required int capPayroll,
    required int capRoom,
    required int projectedCash,
  }) {
    final twoWayPayroll = career.finances.twoWayPayrollFor(
      team.id,
      career.currentYear,
    );
    final operatingCommitments = career.finances.operatingCommitmentsFor(
      team.id,
    );
    final guaranteedTotal = career.finances.guaranteedLiabilityCapFor(
      team.id,
      career.currentYear,
    );
    final debt = career.finances.debtFor(team.id);

    return Container(
      key: const ValueKey('team-cap-overview-card'),
      padding: EdgeInsets.all(t.space300),
      decoration: BoxDecoration(
        color: t.bgSurface,
        borderRadius: BorderRadius.circular(t.radiusLg),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SEASON ${career.currentYear} CAP & FINANCES',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: t.space200),
          Wrap(
            spacing: t.space400,
            runSpacing: t.space300,
            children: [
              _metric(
                t,
                'Salary Cap',
                CareerUiLabels.formatCu(FinancialRules.salaryCap),
              ),
              _metric(t, 'Cap Payroll', CareerUiLabels.formatCu(capPayroll)),
              _metric(
                t,
                capRoom >= 0 ? 'Cap Room' : 'Over Cap',
                '${capRoom >= 0 ? '+' : ''}${CareerUiLabels.formatCu(capRoom)}',
                valueColor: capRoom >= 0
                    ? t.statusSuccessFg
                    : t.statusWarningFg,
              ),
              _metric(
                t,
                'Two-Way Payroll',
                CareerUiLabels.formatCu(twoWayPayroll),
              ),
              _metric(
                t,
                'Team Cash',
                CareerUiLabels.formatCu(finances.cash),
                valueColor: finances.cash >= 0
                    ? t.textPrimary
                    : t.statusDangerFg,
              ),
              _metric(
                t,
                'Projected End Cash',
                CareerUiLabels.formatCu(projectedCash),
                valueColor: projectedCash >= 0
                    ? t.textPrimary
                    : t.statusWarningFg,
              ),
              _metric(
                t,
                'Operating Commitments',
                CareerUiLabels.formatCu(operatingCommitments),
              ),
              _metric(
                t,
                'Guaranteed Liabilities',
                CareerUiLabels.formatCu(guaranteedTotal),
              ),
              if (debt > 0)
                _metric(
                  t,
                  'Franchise Debt',
                  CareerUiLabels.formatCu(debt),
                  valueColor: t.statusDangerFg,
                ),
              _metric(
                t,
                'Cap Exception',
                finances.capException > 0
                    ? CareerUiLabels.formatCu(finances.capException)
                    : 'None',
              ),
              if (finances.capGrandfathered)
                _metric(
                  t,
                  'Cap Rule Status',
                  'Grandfathered',
                  valueColor: t.accentPrimary,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMultiYearCommitmentsCard(
    HardwoodCommandTokens t,
    GmCareer career,
    Team team,
  ) {
    final years = [for (var i = 0; i < 4; i++) career.currentYear + i];
    final schedules = career.finances.schedulesForTeam(team.id);

    int totalForYear(int year) {
      var sum = 0;
      for (final s in schedules) {
        final sal = s.salaryForYear(year);
        if (sal != null) {
          sum += sal;
        }
      }
      return sum;
    }

    return Container(
      key: const ValueKey('team-multiyear-commitments-card'),
      padding: EdgeInsets.all(t.space300),
      decoration: BoxDecoration(
        color: t.bgSurface,
        borderRadius: BorderRadius.circular(t.radiusLg),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MULTI-YEAR PAYROLL COMMITMENTS',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: t.space200),
          for (var i = 0; i < years.length; i++) ...[
            if (i > 0) SizedBox(height: t.space100),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: t.space200,
                vertical: t.space200,
              ),
              decoration: BoxDecoration(
                color: i == 0 ? t.accentPrimaryTint : t.bgElevated,
                borderRadius: BorderRadius.circular(t.radiusSm),
                border: Border.all(
                  color: i == 0 ? t.borderActive : t.borderSubtle,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Season ${years[i]}${i == 0 ? ' (Current)' : ''}',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 14,
                        fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(width: t.space200),
                  Text(
                    CareerUiLabels.formatCu(totalForYear(years[i])),
                    style: TextStyle(
                      color: i == 0 ? t.accentPrimary : t.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpiringContractsSection(
    BuildContext context,
    HardwoodCommandTokens t,
    GmCareer career,
    Team team,
  ) {
    final expiring = <Player>[];
    for (final player in team.players) {
      final contract = career.finances.contractForPlayer(player.id);
      if (contract != null &&
          contract.startYear + contract.durationYears - 1 ==
              career.currentYear) {
        expiring.add(player);
      }
    }
    expiring.sort((a, b) {
      final salA =
          career.finances
              .scheduleFor(career.finances.contractForPlayer(a.id)!.id)
              ?.salaryForYear(career.currentYear) ??
          0;
      final salB =
          career.finances
              .scheduleFor(career.finances.contractForPlayer(b.id)!.id)
              ?.salaryForYear(career.currentYear) ??
          0;
      return salB.compareTo(salA);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'EXPIRING CONTRACTS (${expiring.length})',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
        if (expiring.isEmpty)
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(t.space300),
            decoration: BoxDecoration(
              color: t.bgSurface,
              borderRadius: BorderRadius.circular(t.radiusMd),
              border: Border.all(color: t.borderSubtle),
            ),
            child: Text(
              'No contracts expiring after Season ${career.currentYear}.',
              style: TextStyle(color: t.textSecondary, fontSize: 14),
            ),
          )
        else
          for (final player in expiring)
            _buildContractRow(context, t, career, team, player),
      ],
    );
  }

  Widget _buildAllContractsSection(
    BuildContext context,
    HardwoodCommandTokens t,
    GmCareer career,
    Team team,
  ) {
    final players = List<Player>.from(team.players)
      ..sort((a, b) {
        final salA = _salaryFor(career, a) ?? 0;
        final salB = _salaryFor(career, b) ?? 0;
        return salB.compareTo(salA);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'ACTIVE CONTRACT COMMITMENTS (${players.length})',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
        for (final player in players)
          _buildContractRow(context, t, career, team, player),
      ],
    );
  }

  Widget _buildContractRow(
    BuildContext context,
    HardwoodCommandTokens t,
    GmCareer career,
    Team team,
    Player player,
  ) {
    final contract = career.finances.contractForPlayer(player.id);
    final schedule = contract == null
        ? null
        : career.finances.scheduleFor(contract.id);
    final salary = schedule?.salaryForYear(career.currentYear);
    final yearsLeft = contract == null
        ? 0
        : (contract.startYear + contract.durationYears) - career.currentYear;
    final category = team.roster.categoryOf(player.id);
    final isTwoWay = category == RosterCategory.twoWay;

    return Padding(
      padding: EdgeInsets.only(bottom: t.space200),
      child: AppPressable(
        minHeight: t.touchMin,
        semanticLabel: '${player.fullName} contract',
        onPressed: () =>
            _openPlayerProfile(context, career, team, player, initialTab: 2),
        child: Container(
          padding: EdgeInsets.all(t.space300),
          decoration: BoxDecoration(
            color: t.bgSurface,
            borderRadius: BorderRadius.circular(t.radiusMd),
            border: Border.all(color: t.borderSubtle),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.fullName,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${player.position.shortName} • ${isTwoWay ? '2-Way' : 'Standard'} • '
                      '${yearsLeft <= 1 ? 'Expiring' : '$yearsLeft yrs left'} • '
                      '${schedule?.guaranteedYears ?? 0} gtd',
                      style: TextStyle(color: t.textSecondary, fontSize: 13.5),
                    ),
                  ],
                ),
              ),
              SizedBox(width: t.space200),
              Text(
                salary == null ? 'N/A' : CareerUiLabels.formatCu(salary),
                style: TextStyle(
                  color: t.accentPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: t.space100),
              Icon(Icons.chevron_right_rounded, color: t.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  int? _salaryFor(GmCareer career, Player player) {
    final contract = career.finances.contractForPlayer(player.id);
    if (contract == null) return null;
    return career.finances
        .scheduleFor(contract.id)
        ?.salaryForYear(career.currentYear);
  }

  void _openPlayerProfile(
    BuildContext context,
    GmCareer career,
    Team team,
    Player player, {
    required int initialTab,
  }) {
    final contract = career.finances.contractForPlayer(player.id);
    final schedule = contract == null
        ? null
        : career.finances.scheduleFor(contract.id);
    final totals = computeRegularSeasonPlayerTotals(
      seasonState: career.regularSeasonState,
      playerId: player.id.value,
      teamId: team.id.value,
    );

    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CareerPlayerProfileScreen(
          initialTabIndex: initialTab,
          dossier: RosteredPlayerDossier(
            player: player,
            team: team,
            category: team.roster.categoryOf(player.id),
            currentYear: career.currentYear,
            isUserTeam: true,
            profile: career.careerProfiles.forPlayer(player.id),
            contract: contract,
            schedule: schedule,
            seasonTotals: totals,
          ),
        ),
      ),
    );
  }

  Widget _metric(
    HardwoodCommandTokens t,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: t.textMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? t.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
