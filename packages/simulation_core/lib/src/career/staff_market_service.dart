import '../finance/career_finances.dart';
import '../finance/financial_rules.dart';
import '../models/ids.dart';
import '../models/staff_commitment.dart';
import 'career_phase.dart';
import 'gm_career.dart';
import 'staff_identity_generator.dart';
import 'staff_member.dart';

/// Typed reasons a staff transaction is refused. A refusal never changes
/// state: every transaction is a pure function that throws before building.
enum StaffRejectionCode {
  coachingDisabled,
  coachingAlreadyEnabled,
  wrongPhase,
  unknownTeam,
  teamHasHeadCoach,
  noHeadCoach,
  candidateUnavailable,
  invalidDuration,
  overOperatingBudget,
  insufficientCash,
  renewalExceedsMaximum,
}

final class StaffTransactionRejected implements Exception {
  const StaffTransactionRejected(this.code, this.message);

  final StaffRejectionCode code;
  final String message;

  @override
  String toString() => 'Staff transaction rejected (${code.name}): $message';
}

/// Affordability of adding [annualCost] of staff salary to one franchise,
/// using only existing authoritative rules (no new exceptions).
final class StaffAffordability {
  const StaffAffordability({
    required this.operatingCommitmentsAfter,
    required this.operatingBudget,
    required this.projectedCashAfter,
    required this.debt,
    required this.rosterReserve,
  });

  /// Existing staff (employed and dismissed-but-payable) + facilities + cost.
  final int operatingCommitmentsAfter;
  final int operatingBudget;

  /// `projectedEndOfSeasonCash` after the cost; player salaries never count
  /// toward this as cap: staff are operating expenses only.
  final int projectedCashAfter;
  final int debt;

  /// Minimum-salary cash for the standard players still required by the
  /// existing readiness rule (`minimumSalary × (14 − standard count)`), the
  /// same threshold `OffseasonReadinessGate` applies to clearance.
  final int rosterReserve;

  bool get withinOperatingBudget =>
      operatingCommitmentsAfter <= operatingBudget;
  bool get preservesRosterReserve => projectedCashAfter - debt >= rosterReserve;
  bool get affordable => withinOperatingBudget && preservesRosterReserve;
}

/// M011 head-coach market and staff transactions (offseason only, D9).
final class StaffMarketService {
  const StaffMarketService();

  /// Standard-tier head-coach rate: the existing bootstrap salary (D7). Only
  /// standard-tier coaches are offered while quality effects are deferred
  /// (D3).
  static const int headCoachAnnualSalary = 2500;
  static const int headCoachCandidatesPerOffseason = 8;
  static const int aiContractYears = 2;

  static String candidateIdFor(int seasonYear, int index) =>
      'staffcand-y$seasonYear-hc-$index';

  /// Deterministic head-coach candidates for the current offseason: freshly
  /// generated fictional coaches not yet in the league's staff records, plus
  /// previously employed head coaches who are now available. Ordered by
  /// experience (desc), then id.
  List<StaffMember> headCoachCandidates(GmCareer career) {
    final staff = career.staff;
    final candidates = <StaffMember>[
      for (var i = 0; i < headCoachCandidatesPerOffseason; i++)
        if (!staff.members.containsKey(candidateIdFor(career.currentYear, i)))
          StaffIdentityGenerator.person(
            id: candidateIdFor(career.currentYear, i),
            generationSeed: career.generationSeed,
            role: StaffCategory.headCoach,
            tier: StaffTier.standard,
          ),
      for (final member in staff.members.values)
        if (member.isAvailable &&
            member.role == StaffCategory.headCoach &&
            member.tier == StaffTier.standard)
          member,
    ];
    candidates.sort((a, b) {
      final byExperience = b.experienceYears.compareTo(a.experienceYears);
      return byExperience != 0 ? byExperience : a.id.compareTo(b.id);
    });
    return candidates;
  }

  StaffAffordability affordability(
    GmCareer career,
    TeamId teamId,
    int annualCost,
  ) {
    final finances = career.finances;
    final team = career.league.teams.where((t) => t.id == teamId).firstOrNull;
    if (team == null) {
      throw StaffTransactionRejected(
        StaffRejectionCode.unknownTeam,
        'Unknown team ${teamId.value}',
      );
    }
    final missing =
        FinancialRules.minimumStandardRoster - team.roster.standardCount;
    return StaffAffordability(
      operatingCommitmentsAfter:
          finances.operatingCommitmentsFor(teamId) + annualCost,
      operatingBudget: finances.financesFor(teamId).operatingBudget,
      projectedCashAfter:
          finances.projectedEndOfSeasonCash(teamId, career.currentYear) -
          annualCost,
      debt: finances.debtFor(teamId),
      rosterReserve: missing > 0 ? missing * FinancialRules.minimumSalary : 0,
    );
  }

  /// Permanent league-wide activation (D2). Changes no money and hires no one.
  GmCareer enableCoaching(GmCareer career) {
    if (career.staff.coachingEnabled) {
      throw const StaffTransactionRejected(
        StaffRejectionCode.coachingAlreadyEnabled,
        'Coaching is already enabled for this career',
      );
    }
    return career.copyWith(staff: career.staff.copyWith(coachingEnabled: true));
  }

  GmCareer hireHeadCoach(
    GmCareer career, {
    required TeamId teamId,
    required String candidateId,
    required int durationYears,
  }) {
    _requireStaffWindow(career);
    if (career.staff.employedHeadCoach(teamId) != null) {
      throw StaffTransactionRejected(
        StaffRejectionCode.teamHasHeadCoach,
        '${teamId.value} already employs a head coach; dismiss first',
      );
    }
    if (durationYears < 1 || durationYears > StaffCommitment.maxDurationYears) {
      throw StaffTransactionRejected(
        StaffRejectionCode.invalidDuration,
        'Duration must be 1..${StaffCommitment.maxDurationYears}',
      );
    }
    final candidate = headCoachCandidates(
      career,
    ).where((c) => c.id == candidateId).firstOrNull;
    if (candidate == null) {
      throw StaffTransactionRejected(
        StaffRejectionCode.candidateUnavailable,
        'Candidate $candidateId is not available',
      );
    }
    _requireAffordable(career, teamId, headCoachAnnualSalary);
    final commitment = StaffCommitment(
      id: _newCommitmentId(career, teamId),
      teamId: teamId,
      category: StaffCategory.headCoach,
      tier: StaffTier.standard,
      annualCost: headCoachAnnualSalary,
      startYear: career.currentYear,
      durationYears: durationYears,
    );
    return career.copyWith(
      finances: _withCommitments(career.finances, [
        ...career.finances.staffCommitments.values,
        commitment,
      ]),
      staff: career.staff.withMember(
        candidate.withEmployment(
          status: StaffEmploymentStatus.employed,
          teamId: teamId,
          commitmentId: commitment.id,
        ),
      ),
    );
  }

  /// Removes coaching authority; the commitment keeps being paid until it
  /// expires (D6).
  GmCareer dismissHeadCoach(GmCareer career, {required TeamId teamId}) {
    _requireStaffWindow(career);
    final coach = career.staff.employedHeadCoach(teamId);
    if (coach == null) {
      throw StaffTransactionRejected(
        StaffRejectionCode.noHeadCoach,
        '${teamId.value} has no employed head coach',
      );
    }
    return career.copyWith(
      staff: career.staff.withMember(
        coach.withEmployment(
          status: StaffEmploymentStatus.dismissed,
          teamId: coach.teamId,
          commitmentId: coach.commitmentId,
        ),
      ),
    );
  }

  /// Dismiss + hire as one atomic transaction. Affordability counts the
  /// dismissed coach's continuing salary, so replacement cannot bypass the
  /// operating budget.
  GmCareer replaceHeadCoach(
    GmCareer career, {
    required TeamId teamId,
    required String candidateId,
    required int durationYears,
  }) => hireHeadCoach(
    dismissHeadCoach(career, teamId: teamId),
    teamId: teamId,
    candidateId: candidateId,
    durationYears: durationYears,
  );

  /// Extends the employed coach's existing commitment in place: same id,
  /// start year and annual cost, so elapsed years and amounts already owed
  /// are preserved. The total term stays within the existing 5-year maximum.
  GmCareer renewHeadCoach(
    GmCareer career, {
    required TeamId teamId,
    required int additionalYears,
  }) {
    _requireStaffWindow(career);
    final coach = career.staff.employedHeadCoach(teamId);
    if (coach == null) {
      throw StaffTransactionRejected(
        StaffRejectionCode.noHeadCoach,
        '${teamId.value} has no employed head coach',
      );
    }
    final current = career.finances.staffCommitments[coach.commitmentId]!;
    final total = current.durationYears + additionalYears;
    if (additionalYears < 1 || total > StaffCommitment.maxDurationYears) {
      throw StaffTransactionRejected(
        StaffRejectionCode.renewalExceedsMaximum,
        'Renewal must add 1+ years with a total term of at most '
        '${StaffCommitment.maxDurationYears} (currently '
        '${current.durationYears})',
      );
    }
    final renewed = StaffCommitment(
      id: current.id,
      teamId: current.teamId,
      category: current.category,
      tier: current.tier,
      annualCost: current.annualCost,
      startYear: current.startYear,
      durationYears: total,
    );
    return career.copyWith(
      finances: _withCommitments(career.finances, [
        for (final c in career.finances.staffCommitments.values)
          c.id == current.id ? renewed : c,
      ]),
    );
  }

  /// AI head-coach recruitment (D8). Runs once per offseason when free agency
  /// opens (after the draft and rookie signing, before player free agency and
  /// clearance). Idempotent: teams that already employ a coach are skipped.
  /// Disabled coaching returns [career] unchanged.
  GmCareer aiRecruitHeadCoaches(GmCareer career) {
    if (!career.staff.coachingEnabled ||
        career.phase != CareerPhase.openingOffseason) {
      return career;
    }
    var current = career;
    final aiTeams = [
      for (final team in career.league.teams)
        if (team.id != career.userFranchiseId) team.id,
    ]..sort((a, b) => a.value.compareTo(b.value));
    for (final teamId in aiTeams) {
      if (current.staff.employedHeadCoach(teamId) != null) continue;
      if (!affordability(current, teamId, headCoachAnnualSalary).affordable) {
        continue; // Vacancy: the default rotation applies (T03).
      }
      final pick = headCoachCandidates(current).firstOrNull;
      if (pick == null) break;
      current = hireHeadCoach(
        current,
        teamId: teamId,
        candidateId: pick.id,
        durationYears: aiContractYears,
      );
    }
    return current;
  }

  /// The reason staff transactions are unavailable now, or `null` when the
  /// window is open (coaching enabled, opening offseason, before entry).
  StaffRejectionCode? windowBlocker(GmCareer career) {
    try {
      _requireStaffWindow(career);
      return null;
    } on StaffTransactionRejected catch (e) {
      return e.code;
    }
  }

  void _requireStaffWindow(GmCareer career) {
    if (!career.staff.coachingEnabled) {
      throw const StaffTransactionRejected(
        StaffRejectionCode.coachingDisabled,
        'Enable coaching before managing staff',
      );
    }
    if (career.phase != CareerPhase.openingOffseason ||
        career.regularSeasonState != null) {
      throw const StaffTransactionRejected(
        StaffRejectionCode.wrongPhase,
        'Staff changes are allowed only in the opening offseason',
      );
    }
  }

  void _requireAffordable(GmCareer career, TeamId teamId, int annualCost) {
    final check = affordability(career, teamId, annualCost);
    if (!check.withinOperatingBudget) {
      throw StaffTransactionRejected(
        StaffRejectionCode.overOperatingBudget,
        'Operating commitments ${check.operatingCommitmentsAfter} would '
        'exceed budget ${check.operatingBudget}',
      );
    }
    if (!check.preservesRosterReserve) {
      throw StaffTransactionRejected(
        StaffRejectionCode.insufficientCash,
        'Projected cash ${check.projectedCashAfter} less debt ${check.debt} '
        'would not keep ${check.rosterReserve} for required roster spots',
      );
    }
  }

  String _newCommitmentId(GmCareer career, TeamId teamId) {
    for (var k = 0; ; k++) {
      final id = 'staff-${teamId.value}-headCoach-y${career.currentYear}-$k';
      if (!career.finances.staffCommitments.containsKey(id)) return id;
    }
  }

  static CareerFinances _withCommitments(
    CareerFinances finances,
    Iterable<StaffCommitment> commitments,
  ) => CareerFinances(
    contracts: finances.contracts.values,
    schedules: finances.schedules.values,
    teamFinances: finances.teamFinances.values,
    staffCommitments: commitments,
    facilities: finances.facilities.values,
    guaranteedLiabilities: finances.guaranteedLiabilities.values,
    debtByTeam: finances.debtByTeam,
  );
}
