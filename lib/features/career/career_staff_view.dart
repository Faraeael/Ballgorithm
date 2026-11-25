import 'package:flutter/material.dart';
import 'package:simulation_core/simulation_core.dart';

import '../../theme/hardwood_command_theme.dart';
import 'career_controller.dart';
import 'career_rotation_screen.dart';
import 'career_ui_labels.dart';
import 'widgets/hardwood_components.dart';

const StaffMarketService _market = StaffMarketService();

/// Authoritative operating-money figures for one team, read straight from
/// [CareerFinances] (no recomputed rules).
final class StaffFinanceSnapshot {
  StaffFinanceSnapshot._({
    required this.operatingBudget,
    required this.operatingCommitments,
    required this.activeStaffSalaries,
    required this.dismissedStillPayable,
    required this.facilityMaintenance,
    required this.projectedCash,
    required this.capRoom,
    required this.rosterReserve,
  });

  factory StaffFinanceSnapshot.of(GmCareer career, TeamId team) {
    final f = career.finances;
    var active = 0;
    var dismissed = 0;
    for (final c in f.staffCommitments.values) {
      if (c.teamId != team) continue;
      final member = career.staff.memberForCommitment(c.id);
      if (member?.status == StaffEmploymentStatus.dismissed) {
        dismissed += c.annualCost;
      } else {
        active += c.annualCost;
      }
    }
    var facilities = 0;
    for (final x in f.facilities.values) {
      if (x.teamId == team) facilities += x.maintenancePerYear;
    }
    return StaffFinanceSnapshot._(
      operatingBudget: f.financesFor(team).operatingBudget,
      operatingCommitments: f.operatingCommitmentsFor(team),
      activeStaffSalaries: active,
      dismissedStillPayable: dismissed,
      facilityMaintenance: facilities,
      projectedCash: f.projectedEndOfSeasonCash(team, career.currentYear),
      capRoom:
          FinancialRules.salaryCap - f.capPayrollFor(team, career.currentYear),
      rosterReserve: _market.affordability(career, team, 0).rosterReserve,
    );
  }

  final int operatingBudget;
  final int operatingCommitments;
  final int activeStaffSalaries;
  final int dismissedStillPayable;
  final int facilityMaintenance;
  final int projectedCash;
  final int capRoom;
  final int rosterReserve;

  int get remainingOperatingBudget => operatingBudget - operatingCommitments;
}

/// M011 TEAM › STAFF sub-view: staff, coaching control, budget, market.
class CareerStaffView extends StatefulWidget {
  const CareerStaffView({super.key, required this.controller});

  final GmCareerController controller;

  @override
  State<CareerStaffView> createState() => _CareerStaffViewState();
}

class _CareerStaffViewState extends State<CareerStaffView> {
  String? _status;
  bool _statusIsError = false;

  GmCareerController get _controller => widget.controller;

  bool get _busy =>
      _controller.isLoading ||
      _controller.isBatchSimulating ||
      _controller.seasonTransitionStage != null ||
      _controller.draftRecoveryRequired;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final career = _controller.career;
    if (career == null) return const SizedBox.shrink();
    final team = career.userFranchiseId;
    final coach = career.staff.employedHeadCoach(team);
    final blocker = _market.windowBlocker(career);
    return Column(
      key: const ValueKey('career-staff-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_status != null) ...[
          _statusBanner(t),
          SizedBox(height: t.space300),
        ],
        _coachingCard(context, t, career),
        SizedBox(height: t.space300),
        _headCoachCard(context, t, career, coach, blocker),
        SizedBox(height: t.space300),
        _budgetPanel(t, StaffFinanceSnapshot.of(career, team)),
        SizedBox(height: t.space300),
        _contractsCard(t, career),
        SizedBox(height: t.space300),
        _marketCard(context, t, career, coach, blocker),
      ],
    );
  }

  // ------------------------------------------------------------- building

  Widget _card(HardwoodCommandTokens t, {required Widget child, Key? key}) =>
      Container(
        key: key,
        padding: EdgeInsets.all(t.space300),
        decoration: BoxDecoration(
          color: t.bgSurface,
          borderRadius: BorderRadius.circular(t.radiusLg),
          border: Border.all(color: t.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [child],
        ),
      );

  Widget _label(HardwoodCommandTokens t, String text) => Text(
    text,
    style: TextStyle(
      color: t.textSecondary,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
    ),
  );

  Widget _body(
    HardwoodCommandTokens t,
    String text, {
    Key? key,
    Color? color,
  }) => Text(
    text,
    key: key,
    style: TextStyle(color: color ?? t.textSecondary, fontSize: 12.5),
  );

  Widget _row(
    HardwoodCommandTokens t,
    String label,
    String value, {
    Key? key,
    Color? valueColor,
  }) => Padding(
    padding: EdgeInsets.symmetric(vertical: t.space100),
    child: Row(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: t.textSecondary, fontSize: 12.5),
          ),
        ),
        SizedBox(width: t.space200),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: valueColor ?? t.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _statusBanner(HardwoodCommandTokens t) => Container(
    key: const ValueKey('staff-status'),
    padding: EdgeInsets.all(t.space300),
    decoration: BoxDecoration(
      color: _statusIsError ? t.statusDangerBg : t.statusSuccessBg,
      borderRadius: BorderRadius.circular(t.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _status!,
          style: TextStyle(
            color: _statusIsError ? t.statusDangerFg : t.statusSuccessFg,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
        if (_controller.draftRecoveryRequired) ...[
          SizedBox(height: t.space200),
          HardwoodSecondaryButton(
            key: const ValueKey('staff-reload'),
            label: 'RELOAD SAVED CAREER',
            icon: Icons.refresh,
            onPressed: _controller.isLoading ? null : _reload,
          ),
        ],
      ],
    ),
  );

  // ------------------------------------------------------- coaching control

  Widget _coachingCard(
    BuildContext context,
    HardwoodCommandTokens t,
    GmCareer career,
  ) {
    final enabled = career.staff.coachingEnabled;
    String delegation;
    try {
      delegation = CareerUiLabels.rotationAuthority(
        CareerRotationService.decisionForUser(career),
      );
    } catch (_) {
      delegation = career.userRotation.isManual
          ? 'You (MANUAL plan) — needs attention'
          : 'Roster not ready for a lineup yet';
    }
    return _card(
      t,
      key: const ValueKey('staff-coaching-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(t, 'COACHING & STAFF'),
          SizedBox(height: t.space200),
          Text(
            enabled ? 'ON — head coaches run AUTO rotations' : 'OFF',
            key: const ValueKey('staff-coaching-state'),
            style: TextStyle(
              color: enabled ? t.statusSuccessFg : t.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: t.space200),
          _row(
            t,
            'Rotation decided by',
            delegation,
            key: const ValueKey('staff-delegation'),
          ),
          SizedBox(height: t.space100),
          if (!enabled) ...[
            _body(
              t,
              'While off, AUTO uses the default lineup and balanced rotation. '
              'Turning coaching on lets head coaches set AUTO rotations for '
              'their teams. Your MANUAL plan still takes precedence.',
            ),
            SizedBox(height: t.space300),
            HardwoodPrimaryCta(
              key: const ValueKey('staff-enable'),
              label: 'Enable Coaching & Staff',
              icon: Icons.sports,
              onPressed: _busy ? null : () => _confirmEnable(context, career),
            ),
          ] else
            HardwoodSecondaryButton(
              key: const ValueKey('staff-open-rotation'),
              label: 'LINEUP & ROTATION',
              icon: Icons.sports_basketball,
              onPressed: () => openCareerRotationEditor(context, _controller),
            ),
        ],
      ),
    );
  }

  /// AI recruitment happens once, when free-agency round 1 opens.
  String _aiTimingNote(GmCareer career) {
    final faOpened =
        career.phase != CareerPhase.openingOffseason ||
        career.freeAgentMarket.status != FreeAgentMarketStatus.notStarted;
    return faOpened
        ? 'Free agency has already opened this offseason, so AI teams will '
              'first recruit head coaches at the start of next offseason\'s '
              'free agency. No AI hires happen immediately.'
        : 'AI teams without an employed head coach recruit one when free-'
              'agency round 1 opens this offseason, only if they can afford '
              'it. Teams that already employ a coach keep them.';
  }

  Future<void> _confirmEnable(BuildContext context, GmCareer career) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('staff-enable-dialog'),
        title: const Text('Enable Coaching & Staff?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• This is permanent for this career.'),
              const Text(
                '• Every franchise, including AI teams, then uses its employed '
                'head coach to set AUTO lineups and playing time. Teams '
                'without one use the default rotation.',
              ),
              Text('• ${_aiTimingNote(career)}'),
              const Text(
                '• New staff contracts add operating costs and reduce '
                'projected cash. Turning this on hires no one and changes no '
                'money by itself.',
              ),
              const Text(
                '• MANUAL rotation stays available at any time and always '
                'takes precedence over your coach.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('staff-enable-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('staff-enable-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enable Permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(_controller.enableCoaching, 'Coaching & Staff enabled.');
  }

  // ------------------------------------------------------------ head coach

  Widget _headCoachCard(
    BuildContext context,
    HardwoodCommandTokens t,
    GmCareer career,
    StaffMember? coach,
    StaffRejectionCode? blocker,
  ) {
    final commitment = coach == null
        ? null
        : career.finances.staffCommitments[coach.commitmentId];
    final canAct = blocker == null && !_busy;
    return _card(
      t,
      key: const ValueKey('staff-head-coach-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(t, 'HEAD COACH'),
          SizedBox(height: t.space200),
          if (coach == null || commitment == null) ...[
            Text(
              'Vacant',
              key: const ValueKey('staff-head-coach-vacant'),
              style: TextStyle(
                color: t.statusWarningFg,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: t.space100),
            _body(
              t,
              'No head coach — AUTO uses the default lineup (first standard '
              'player at each natural position) and the balanced nine-player '
              'rotation.',
            ),
          ] else ...[
            AppPressable(
              key: const ValueKey('staff-head-coach-open'),
              semanticLabel: 'Open head coach profile',
              borderRadius: BorderRadius.circular(t.radiusMd),
              onPressed: () => _showProfile(context, career, coach),
              child: Row(
                children: [
                  _monogram(t, coach),
                  SizedBox(width: t.space300),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${coach.firstName} ${coach.lastName}',
                          key: const ValueKey('staff-head-coach-name'),
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${CareerUiLabels.coachPhilosophy(coach.philosophy!)}'
                          ' · Age ${coach.age} · ${coach.experienceYears} yrs exp',
                          style: TextStyle(
                            color: t.accentSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: t.textSecondary),
                ],
              ),
            ),
            SizedBox(height: t.space200),
            _body(t, CareerUiLabels.coachPhilosophyEffect(coach.philosophy!)),
            if (!career.staff.coachingEnabled) ...[
              SizedBox(height: t.space100),
              _body(
                t,
                'Philosophy applies only after Coaching & Staff is enabled.',
                color: t.statusWarningFg,
              ),
            ],
            SizedBox(height: t.space200),
            _row(t, 'Status', 'Employed'),
            _row(
              t,
              'Contract',
              _contractText(career, commitment),
              key: const ValueKey('staff-head-coach-contract'),
            ),
            _row(
              t,
              'Annual salary',
              '${CareerUiLabels.formatCu(commitment.annualCost)} · '
                  '${CareerUiLabels.staffTier(commitment.tier)}',
            ),
          ],
          SizedBox(height: t.space300),
          if (blocker != null)
            _body(
              t,
              CareerUiLabels.staffRejection(blocker),
              key: const ValueKey('staff-actions-blocked'),
            )
          else if (coach != null && commitment != null)
            Wrap(
              spacing: t.space200,
              runSpacing: t.space200,
              children: [
                HardwoodSecondaryButton(
                  key: const ValueKey('staff-renew'),
                  label: 'RENEW',
                  icon: Icons.event_repeat,
                  onPressed: canAct
                      ? () => _openRenew(context, career, coach, commitment)
                      : null,
                ),
                HardwoodSecondaryButton(
                  key: const ValueKey('staff-dismiss'),
                  label: 'DISMISS',
                  icon: Icons.person_remove_outlined,
                  onPressed: canAct
                      ? () =>
                            _confirmDismiss(context, career, coach, commitment)
                      : null,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _monogram(HardwoodCommandTokens t, StaffMember m) => Container(
    width: t.touchMin,
    height: t.touchMin,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: t.accentSecondaryBg,
      borderRadius: BorderRadius.circular(t.radiusMd),
      border: Border.all(color: t.accentSecondary),
    ),
    child: Text(
      '${m.firstName[0]}${m.lastName[0]}',
      style: TextStyle(color: t.accentSecondaryFg, fontWeight: FontWeight.w800),
    ),
  );

  String _contractText(GmCareer career, StaffCommitment c) {
    final endYear = c.startYear + c.durationYears - 1;
    final left = endYear - career.currentYear + 1;
    final span = c.startYear == endYear
        ? 'Year $endYear only'
        : 'Year ${c.startYear}–$endYear';
    return '$span · $left season${left == 1 ? '' : 's'} left incl. this one';
  }

  Future<void> _showProfile(
    BuildContext context,
    GmCareer career,
    StaffMember m,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.tokens.bgElevated,
    builder: (sheetContext) {
      final t = sheetContext.tokens;
      final commitment = m.commitmentId == null
          ? null
          : career.finances.staffCommitments[m.commitmentId];
      return SafeArea(
        child: SingleChildScrollView(
          key: const ValueKey('staff-coach-profile'),
          padding: EdgeInsets.all(t.space400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _monogram(t, m),
                  SizedBox(width: t.space300),
                  Expanded(
                    child: Text(
                      '${m.firstName} ${m.lastName}',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: t.space300),
              _row(t, 'Role', CareerUiLabels.staffRole(m.role)),
              _row(t, 'Tier', CareerUiLabels.staffTier(m.tier)),
              _row(t, 'Age', '${m.age}'),
              _row(t, 'Experience', '${m.experienceYears} years'),
              _row(t, 'Status', _statusText(m)),
              if (m.philosophy != null)
                _row(
                  t,
                  'Philosophy',
                  CareerUiLabels.coachPhilosophy(m.philosophy!),
                ),
              if (commitment != null) ...[
                _row(t, 'Contract', _contractText(career, commitment)),
                _row(
                  t,
                  'Annual salary',
                  CareerUiLabels.formatCu(commitment.annualCost),
                ),
              ],
              if (m.philosophy != null) ...[
                SizedBox(height: t.space200),
                _body(t, CareerUiLabels.coachPhilosophyEffect(m.philosophy!)),
              ],
              SizedBox(height: t.space200),
              _body(
                t,
                'Coach tier, age and experience have no gameplay effect in '
                'this version; they set nothing but salary and identity.',
                color: t.textMuted,
              ),
            ],
          ),
        ),
      );
    },
  );

  String _statusText(StaffMember m) => switch (m.status) {
    StaffEmploymentStatus.employed => 'Employed',
    StaffEmploymentStatus.dismissed => 'Dismissed — still paid',
    StaffEmploymentStatus.available => 'Available',
  };

  // ---------------------------------------------------------------- budget

  Widget _budgetPanel(HardwoodCommandTokens t, StaffFinanceSnapshot s) => _card(
    t,
    key: const ValueKey('staff-budget-panel'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(t, 'OPERATING BUDGET'),
        SizedBox(height: t.space200),
        _row(t, 'Operating budget', CareerUiLabels.formatCu(s.operatingBudget)),
        _row(
          t,
          'Operating commitments',
          CareerUiLabels.formatCu(s.operatingCommitments),
          key: const ValueKey('staff-budget-commitments'),
        ),
        _row(
          t,
          'Remaining operating budget',
          CareerUiLabels.formatCu(s.remainingOperatingBudget),
          key: const ValueKey('staff-budget-remaining'),
          valueColor: s.remainingOperatingBudget < 0 ? t.statusDangerFg : null,
        ),
        Divider(color: t.borderSubtle, height: t.space400),
        _row(
          t,
          '  Staff salaries',
          CareerUiLabels.formatCu(s.activeStaffSalaries),
        ),
        _row(
          t,
          '  Dismissed staff still payable',
          CareerUiLabels.formatCu(s.dismissedStillPayable),
          key: const ValueKey('staff-budget-dismissed'),
        ),
        _row(
          t,
          '  Facility maintenance',
          CareerUiLabels.formatCu(s.facilityMaintenance),
        ),
        Divider(color: t.borderSubtle, height: t.space400),
        _row(
          t,
          'Projected end-of-season cash',
          CareerUiLabels.formatCu(s.projectedCash),
          key: const ValueKey('staff-budget-cash'),
        ),
        _row(t, 'Player salary-cap room', CareerUiLabels.formatCu(s.capRoom)),
        SizedBox(height: t.space200),
        _body(
          t,
          'Staff are operating expenses: they reduce projected cash and use '
          'operating budget, never player cap room. Salaries are charged at '
          'season settlement.',
          color: t.textMuted,
        ),
      ],
    ),
  );

  // ------------------------------------------------------------- contracts

  Widget _contractsCard(HardwoodCommandTokens t, GmCareer career) {
    final team = career.userFranchiseId;
    final commitments = [
      for (final c in career.finances.staffCommitments.values)
        if (c.teamId == team) c,
    ]..sort((a, b) => a.category.index.compareTo(b.category.index));
    return _card(
      t,
      key: const ValueKey('staff-contracts'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(t, 'STAFF CONTRACTS'),
          SizedBox(height: t.space200),
          if (commitments.isEmpty)
            _body(
              t,
              'No staff under contract. Opening-season staff contracts run '
              'one season and are not renewed automatically.',
            ),
          for (final c in commitments)
            _contractRow(t, career, c, career.staff.memberForCommitment(c.id)),
        ],
      ),
    );
  }

  Widget _contractRow(
    HardwoodCommandTokens t,
    GmCareer career,
    StaffCommitment c,
    StaffMember? m,
  ) {
    final dismissed = m?.status == StaffEmploymentStatus.dismissed;
    final endYear = c.startYear + c.durationYears - 1;
    return Container(
      key: ValueKey('staff-contract-${c.id}'),
      margin: EdgeInsets.only(bottom: t.space200),
      padding: EdgeInsets.all(t.space200),
      decoration: BoxDecoration(
        color: t.bgElevated,
        borderRadius: BorderRadius.circular(t.radiusMd),
        border: Border.all(color: dismissed ? t.statusWarning : t.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  m == null ? 'Unnamed' : '${m.firstName} ${m.lastName}',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
              Text(
                '${CareerUiLabels.formatCu(c.annualCost)}/yr',
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          SizedBox(height: t.space100),
          Text(
            '${CareerUiLabels.staffRole(c.category)} · '
            '${CareerUiLabels.staffTier(c.tier)} · through Year $endYear',
            style: TextStyle(color: t.textSecondary, fontSize: 12),
          ),
          SizedBox(height: t.space100),
          Text(
            dismissed
                ? 'Dismissed — salary still paid through Year $endYear'
                : c.category == StaffCategory.headCoach
                ? 'Sets AUTO rotation when coaching is on'
                : 'No gameplay effect yet (contract only)',
            style: TextStyle(
              color: dismissed ? t.statusWarningFg : t.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- market

  Widget _marketCard(
    BuildContext context,
    HardwoodCommandTokens t,
    GmCareer career,
    StaffMember? coach,
    StaffRejectionCode? blocker,
  ) {
    final candidates = blocker == null
        ? _market.headCoachCandidates(career)
        : const <StaffMember>[];
    return _card(
      t,
      key: const ValueKey('staff-market'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(t, 'HEAD-COACH MARKET'),
          SizedBox(height: t.space200),
          if (blocker != null)
            _body(t, CareerUiLabels.staffRejection(blocker))
          else ...[
            _body(
              t,
              'Standard-tier head coaches at a fixed '
              '${CareerUiLabels.formatCu(StaffMarketService.headCoachAnnualSalary)}'
              ' per year, 1–5 years. ${coach == null ? 'Hiring fills your vacancy.' : 'Hiring replaces your current coach, whose salary keeps being paid until it expires.'}',
            ),
            SizedBox(height: t.space200),
            if (candidates.isEmpty) _body(t, 'No candidates available.'),
            for (final c in candidates)
              Padding(
                padding: EdgeInsets.only(bottom: t.space200),
                child: AppPressable(
                  key: ValueKey('staff-candidate-${c.id}'),
                  semanticLabel: 'Inspect ${c.firstName} ${c.lastName}',
                  enabled: !_busy,
                  borderRadius: BorderRadius.circular(t.radiusMd),
                  onPressed: _busy
                      ? null
                      : () => _openHire(context, career, c, coach != null),
                  child: Container(
                    padding: EdgeInsets.all(t.space200),
                    decoration: BoxDecoration(
                      color: t.bgElevated,
                      borderRadius: BorderRadius.circular(t.radiusMd),
                      border: Border.all(color: t.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        _monogram(t, c),
                        SizedBox(width: t.space300),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${c.firstName} ${c.lastName}',
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${CareerUiLabels.coachPhilosophy(c.philosophy!)} · '
                                '${c.experienceYears} yrs exp · Age ${c.age}',
                                style: TextStyle(
                                  color: t.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '${CareerUiLabels.formatCu(StaffMarketService.headCoachAnnualSalary)}/yr · Available',
                                style: TextStyle(
                                  color: t.statusSuccessFg,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: t.textSecondary),
                      ],
                    ),
                  ),
                ),
              ),
            _body(
              t,
              'Supporting-staff hiring and premium tiers are not available '
              'in this version.',
              color: t.textMuted,
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------- transaction previews

  /// Runs the real core transaction on the current career to preview it.
  ({GmCareer? after, String? rejection}) _preview(
    GmCareer Function() transaction,
  ) {
    try {
      return (after: transaction(), rejection: null);
    } on StaffTransactionRejected catch (e) {
      return (after: null, rejection: CareerUiLabels.staffRejection(e.code));
    }
  }

  Widget _previewTable(
    HardwoodCommandTokens t,
    GmCareer before,
    GmCareer? after,
  ) {
    final team = before.userFranchiseId;
    final b = StaffFinanceSnapshot.of(before, team);
    final a = after == null ? null : StaffFinanceSnapshot.of(after, team);
    String pair(int x, int? y) => y == null
        ? CareerUiLabels.formatCu(x)
        : '${CareerUiLabels.formatCu(x)} → ${CareerUiLabels.formatCu(y)}';
    return Column(
      key: const ValueKey('staff-preview-table'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          t,
          'Operating commitments',
          pair(b.operatingCommitments, a?.operatingCommitments),
        ),
        _row(
          t,
          'Remaining operating budget',
          pair(b.remainingOperatingBudget, a?.remainingOperatingBudget),
        ),
        _row(
          t,
          'Dismissed still payable',
          pair(b.dismissedStillPayable, a?.dismissedStillPayable),
        ),
        _row(
          t,
          'Projected end-of-season cash',
          pair(b.projectedCash, a?.projectedCash),
          key: const ValueKey('staff-preview-cash'),
        ),
        _row(t, 'Player cap room', pair(b.capRoom, a?.capRoom)),
        if (b.rosterReserve > 0)
          _body(
            t,
            'Cash reserve kept for ${CareerUiLabels.formatCu(b.rosterReserve)} '
            'of minimum-salary roster spots still to fill. The reserve does '
            'not guarantee that free agents will sign.',
            color: t.textMuted,
          ),
      ],
    );
  }

  Widget _yearPicker(
    HardwoodCommandTokens t,
    int maxYears,
    int selected,
    ValueChanged<int> onSelect,
  ) => Row(
    children: [
      for (var y = 1; y <= maxYears; y++) ...[
        if (y > 1) SizedBox(width: t.space200),
        Expanded(
          child: AppPressable(
            key: ValueKey('staff-years-$y'),
            semanticLabel: '$y year${y == 1 ? '' : 's'}',
            minHeight: t.touchMin,
            onPressed: () => onSelect(y),
            child: Container(
              constraints: BoxConstraints(minHeight: t.touchMin),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: y == selected ? t.accentPrimaryTint : t.bgSurface,
                borderRadius: BorderRadius.circular(t.radiusMd),
                border: Border.all(
                  color: y == selected ? t.accentPrimary : t.borderSubtle,
                  width: y == selected ? 1.5 : 1,
                ),
              ),
              child: Text(
                '${y}Y',
                style: TextStyle(
                  color: y == selected ? t.accentPrimary : t.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ],
    ],
  );

  Future<void> _openHire(
    BuildContext context,
    GmCareer career,
    StaffMember candidate,
    bool replacing,
  ) async {
    var years = 2;
    final team = career.userFranchiseId;
    final years0 = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.tokens.bgElevated,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final t = sheetContext.tokens;
          final preview = _preview(
            () => replacing
                ? _market.replaceHeadCoach(
                    career,
                    teamId: team,
                    candidateId: candidate.id,
                    durationYears: years,
                  )
                : _market.hireHeadCoach(
                    career,
                    teamId: team,
                    candidateId: candidate.id,
                    durationYears: years,
                  ),
          );
          const salary = StaffMarketService.headCoachAnnualSalary;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.9,
              ),
              child: SingleChildScrollView(
                key: const ValueKey('staff-hire-sheet'),
                padding: EdgeInsets.all(t.space400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${replacing ? 'Replace with' : 'Hire'} '
                      '${candidate.firstName} ${candidate.lastName}',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: t.space200),
                    _row(
                      t,
                      'Philosophy',
                      CareerUiLabels.coachPhilosophy(candidate.philosophy!),
                    ),
                    _body(
                      t,
                      CareerUiLabels.coachPhilosophyEffect(
                        candidate.philosophy!,
                      ),
                    ),
                    _row(t, 'Experience', '${candidate.experienceYears} years'),
                    _row(t, 'Age', '${candidate.age}'),
                    _row(t, 'Tier', 'Standard'),
                    SizedBox(height: t.space300),
                    _label(t, 'CONTRACT LENGTH'),
                    SizedBox(height: t.space200),
                    _yearPicker(
                      t,
                      StaffCommitment.maxDurationYears,
                      years,
                      (y) => setSheet(() => years = y),
                    ),
                    SizedBox(height: t.space200),
                    _row(
                      t,
                      'Annual salary (fixed)',
                      CareerUiLabels.formatCu(salary),
                    ),
                    _row(
                      t,
                      'Total contract value',
                      CareerUiLabels.formatCu(salary * years),
                      key: const ValueKey('staff-hire-total'),
                    ),
                    _row(
                      t,
                      'Contract',
                      'Year ${career.currentYear}–'
                          '${career.currentYear + years - 1}',
                    ),
                    SizedBox(height: t.space300),
                    _label(t, 'FINANCIAL PREVIEW'),
                    SizedBox(height: t.space200),
                    _previewTable(t, career, preview.after),
                    if (replacing)
                      _body(
                        t,
                        'Your current coach is dismissed but keeps being paid '
                        'until their contract expires. Both salaries count '
                        'this season.',
                        color: t.statusWarningFg,
                      ),
                    if (preview.rejection != null) ...[
                      SizedBox(height: t.space200),
                      _body(
                        t,
                        'Unavailable: ${preview.rejection}',
                        key: const ValueKey('staff-hire-rejection'),
                        color: t.statusDangerFg,
                      ),
                    ],
                    SizedBox(height: t.space300),
                    HardwoodPrimaryCta(
                      key: const ValueKey('staff-hire-confirm'),
                      label: replacing ? 'Confirm Replacement' : 'Confirm Hire',
                      icon: Icons.check,
                      onPressed: preview.after == null
                          ? null
                          : () => Navigator.pop(sheetContext, years),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (years0 == null) return;
    await _run(
      () => replacing
          ? _controller.replaceHeadCoach(
              candidateId: candidate.id,
              durationYears: years0,
            )
          : _controller.hireHeadCoach(
              candidateId: candidate.id,
              durationYears: years0,
            ),
      '${candidate.firstName} ${candidate.lastName} hired for $years0 '
      'year${years0 == 1 ? '' : 's'}.',
    );
  }

  Future<void> _openRenew(
    BuildContext context,
    GmCareer career,
    StaffMember coach,
    StaffCommitment commitment,
  ) async {
    final maxExtra =
        StaffCommitment.maxDurationYears - commitment.durationYears;
    var extra = 1;
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.tokens.bgElevated,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final t = sheetContext.tokens;
          final preview = maxExtra < 1
              ? (
                  after: null,
                  rejection: CareerUiLabels.staffRejection(
                    StaffRejectionCode.renewalExceedsMaximum,
                  ),
                )
              : _preview(
                  () => _market.renewHeadCoach(
                    career,
                    teamId: career.userFranchiseId,
                    additionalYears: extra,
                  ),
                );
          final endYear = commitment.startYear + commitment.durationYears - 1;
          return SafeArea(
            child: SingleChildScrollView(
              key: const ValueKey('staff-renew-sheet'),
              padding: EdgeInsets.all(t.space400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Renew ${coach.firstName} ${coach.lastName}',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: t.space200),
                  _body(
                    t,
                    'Extends the existing contract (from Year '
                    '${commitment.startYear}) at the same '
                    '${CareerUiLabels.formatCu(commitment.annualCost)} per '
                    'year. Elapsed years still count toward the 5-year '
                    'maximum.',
                  ),
                  SizedBox(height: t.space300),
                  if (maxExtra >= 1) ...[
                    _label(t, 'ADDITIONAL YEARS'),
                    SizedBox(height: t.space200),
                    _yearPicker(
                      t,
                      maxExtra,
                      extra,
                      (y) => setSheet(() => extra = y),
                    ),
                    SizedBox(height: t.space200),
                    _row(
                      t,
                      'Contract end',
                      'Year $endYear → Year ${endYear + extra}',
                      key: const ValueKey('staff-renew-end'),
                    ),
                    _row(
                      t,
                      'Added contract value',
                      CareerUiLabels.formatCu(commitment.annualCost * extra),
                    ),
                    _body(
                      t,
                      'This season\'s operating costs do not change; the '
                      'salary continues in the added seasons.',
                      color: t.textMuted,
                    ),
                    SizedBox(height: t.space200),
                    _previewTable(t, career, preview.after),
                  ],
                  if (preview.rejection != null)
                    _body(
                      t,
                      'Unavailable: ${preview.rejection}',
                      key: const ValueKey('staff-renew-rejection'),
                      color: t.statusDangerFg,
                    ),
                  SizedBox(height: t.space300),
                  HardwoodPrimaryCta(
                    key: const ValueKey('staff-renew-confirm'),
                    label: 'Confirm Renewal',
                    icon: Icons.check,
                    onPressed: preview.after == null
                        ? null
                        : () => Navigator.pop(sheetContext, extra),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (picked == null) return;
    await _run(
      () => _controller.renewHeadCoach(additionalYears: picked),
      'Contract extended by $picked year${picked == 1 ? '' : 's'}.',
    );
  }

  Future<void> _confirmDismiss(
    BuildContext context,
    GmCareer career,
    StaffMember coach,
    StaffCommitment commitment,
  ) async {
    final endYear = commitment.startYear + commitment.durationYears - 1;
    final preview = _preview(
      () => _market.dismissHeadCoach(career, teamId: career.userFranchiseId),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final t = dialogContext.tokens;
        return AlertDialog(
          key: const ValueKey('staff-dismiss-dialog'),
          title: Text('Dismiss ${coach.firstName} ${coach.lastName}?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Dismissal does not cancel the contract: '
                  '${CareerUiLabels.formatCu(commitment.annualCost)} per year '
                  'is still paid through Year $endYear. Your AUTO rotation '
                  'uses the default plan until you hire a replacement.',
                ),
                SizedBox(height: t.space300),
                _previewTable(t, career, preview.after),
                if (preview.rejection != null)
                  Text('Unavailable: ${preview.rejection}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('staff-dismiss-cancel'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('staff-dismiss-confirm'),
              onPressed: preview.after == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Dismiss'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _run(
      _controller.dismissHeadCoach,
      '${coach.firstName} ${coach.lastName} dismissed. Salary is still paid '
      'through Year $endYear.',
    );
  }

  // ------------------------------------------------------------- commands

  Future<void> _run(Future<void> Function() command, String success) async {
    try {
      await command();
      if (!mounted) return;
      setState(() {
        _status = success;
        _statusIsError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _status = error is StaffTransactionRejected
            ? 'Not done: ${CareerUiLabels.staffRejection(error.code)}'
            : _controller.draftRecoveryRequired
            ? 'Save failed. Nothing changed. Reload the saved career before '
                  'continuing.'
            : 'Not done: $error';
      });
    }
  }

  Future<void> _reload() async {
    await _controller.loadCareer();
    if (!mounted) return;
    setState(() {
      _statusIsError = _controller.draftRecoveryRequired;
      _status = _controller.draftRecoveryRequired
          ? 'Reload failed. Try again.'
          : 'Saved career reloaded.';
    });
  }
}
