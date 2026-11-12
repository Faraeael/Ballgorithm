import '../models/contract_financials.dart';
import '../models/facility_state.dart';
import '../models/franchise_situation.dart';
import '../models/ids.dart';
import '../models/league.dart';
import '../models/player.dart';
import '../models/player_career_profile.dart';
import '../models/player_contract.dart';
import '../models/rookie_signing_ledger.dart';
import '../models/roster_category.dart';
import '../models/staff_commitment.dart';
import '../models/team.dart';
import '../models/team_finances.dart';
import 'career_finances.dart';
import 'financial_rules.dart';

/// Builds deterministic financial records from existing career state.
///
/// Used both for v1–v7 → v8 migration and for keeping [CareerFinances]
/// consistent when rosters or the rookie signing ledger change. Existing
/// records are preserved when their identity and amounts still match; nothing
/// is regenerated merely because a copy was made.
abstract final class FinancialMigration {
  static CareerFinances reconcile({
    required League league,
    required LeagueCareerProfiles careerProfiles,
    required RookieSigningLedger rookieSigningLedger,
    required int currentYear,
    CareerFinances? previous,
  }) {
    final contracts = <PlayerContract>[];
    final schedules = <ContractFinancials>[];
    for (final team in league.teams) {
      for (final player in team.players) {
        final contract = _contractFor(
          team: team,
          player: player,
          careerProfiles: careerProfiles,
          rookieSigningLedger: rookieSigningLedger,
          currentYear: currentYear,
        );
        final salaryYears = _salariesFor(
          contract: contract,
          player: player,
          careerProfiles: careerProfiles,
          rookieSigningLedger: rookieSigningLedger,
        );
        final prior = previous?.contracts[contract.id];
        final priorSchedule = previous?.schedules[contract.id];
        if (_sameContract(prior, contract) &&
            priorSchedule != null &&
            _sameSalaries(priorSchedule.annualSalaries, salaryYears)) {
          contracts.add(prior!);
          schedules.add(priorSchedule);
        } else {
          contracts.add(contract);
          schedules.add(
            ContractFinancials(
              contractId: contract.id,
              playerId: contract.playerId,
              teamId: contract.teamId,
              annualSalaries: salaryYears,
              guaranteedYears: contract.durationYears,
              source: contract.source,
              signedYear: contract.startYear,
            ),
          );
        }
      }
    }

    final capPayrollByTeam = <String, int>{};
    for (final contract in contracts) {
      if (contract.category != RosterCategory.standard) continue;
      final schedule = schedules.firstWhere(
        (candidate) => candidate.contractId == contract.id,
      );
      capPayrollByTeam[contract.teamId.value] =
          (capPayrollByTeam[contract.teamId.value] ?? 0) +
          schedule.annualSalaries.first;
    }

    final teams = <TeamFinances>[];
    for (final team in league.teams) {
      final prior = previous?.teamFinances[team.id.value];
      final plan = FinancialRules.planFor(
        team.situation ?? FranchiseSituation.playIn,
      );
      final payroll = capPayrollByTeam[team.id.value] ?? 0;
      final grandfathered = previous == null
          ? payroll > FinancialRules.salaryCap
          : prior?.capGrandfathered == true;
      final priorBaseline = prior?.grandfatheredPayroll ?? 0;
      teams.add(
        TeamFinances(
          teamId: team.id,
          operatingBudget: prior?.operatingBudget ?? plan.operatingBudget,
          cash: prior?.cash ?? plan.cash,
          revenueBaseline: prior?.revenueBaseline ?? plan.revenueBaseline,
          season: currentYear,
          capGrandfathered: grandfathered,
          grandfatheredPayroll: grandfathered
              ? (priorBaseline > 0 ? priorBaseline : payroll)
              : 0,
        ),
      );
    }

    final staff = previous == null
        ? [
            for (final team in league.teams)
              ..._initialStaff(team.id, currentYear),
          ]
        : previous.staffCommitments.values.toList();
    final facilities = previous == null
        ? [for (final team in league.teams) ..._initialFacilities(team.id)]
        : previous.facilities.values.toList();

    return CareerFinances(
      contracts: contracts,
      schedules: schedules,
      teamFinances: teams,
      staffCommitments: staff,
      facilities: facilities,
    );
  }

  static PlayerContract _contractFor({
    required Team team,
    required Player player,
    required LeagueCareerProfiles careerProfiles,
    required RookieSigningLedger rookieSigningLedger,
    required int currentYear,
  }) {
    final rookie = rookieSigningLedger.forPlayer(player.id);
    if (rookie != null) {
      return PlayerContract(
        id: PlayerContract.idFor(player.id, rookie.startYear),
        playerId: player.id,
        teamId: team.id,
        category: team.roster.categoryOf(player.id),
        startYear: rookie.startYear,
        durationYears: rookie.durationYears,
        source: ContractSource.rookie,
        rookieContractId: rookie.id,
      );
    }
    final profile = careerProfiles.forPlayer(player.id);
    if (profile == null) {
      throw StateError(
        'Cannot build financial records: player ${player.id.value} has no '
        'career profile',
      );
    }
    final duration = FinancialRules.legacyDurationForAge(profile.age);
    return PlayerContract(
      id: PlayerContract.idFor(player.id, currentYear),
      playerId: player.id,
      teamId: team.id,
      category: team.roster.categoryOf(player.id),
      startYear: currentYear,
      durationYears: duration,
      source: ContractSource.legacy,
    );
  }

  static List<int> _salariesFor({
    required PlayerContract contract,
    required Player player,
    required LeagueCareerProfiles careerProfiles,
    required RookieSigningLedger rookieSigningLedger,
  }) {
    if (contract.source == ContractSource.rookie) {
      final rookie = rookieSigningLedger.forPlayer(contract.playerId)!;
      return contract.category == RosterCategory.twoWay
          ? FinancialRules.twoWaySchedule(contract.durationYears)
          : FinancialRules.standardSchedule(
              FinancialRules.rookieSalaryForPick(rookie.overallPick),
              contract.durationYears,
            );
    }
    if (contract.category == RosterCategory.twoWay) {
      return FinancialRules.twoWaySchedule(contract.durationYears);
    }
    return FinancialRules.standardSchedule(
      FinancialRules.legacySalaryForOverall(player.attributes.overallRating),
      contract.durationYears,
    );
  }

  static bool _sameContract(PlayerContract? left, PlayerContract right) =>
      left != null &&
      left.id == right.id &&
      left.playerId == right.playerId &&
      left.teamId == right.teamId &&
      left.category == right.category &&
      left.startYear == right.startYear &&
      left.durationYears == right.durationYears &&
      left.source == right.source &&
      left.rookieContractId == right.rookieContractId;

  static bool _sameSalaries(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  static List<StaffCommitment> _initialStaff(TeamId teamId, int startYear) {
    StaffCommitment record(StaffCategory category, int index, int cost) =>
        StaffCommitment(
          id: StaffCommitment.idFor(teamId, category, index),
          teamId: teamId,
          category: category,
          tier: StaffTier.standard,
          annualCost: cost,
          startYear: startYear,
          durationYears: 1,
        );
    return [
      record(StaffCategory.headCoach, 0, 2500),
      record(StaffCategory.assistant, 0, 1800),
      record(StaffCategory.assistant, 1, 1800),
      record(StaffCategory.playerDevelopment, 0, 1200),
      record(StaffCategory.scout, 0, 900),
      record(StaffCategory.medical, 0, 1300),
    ];
  }

  static List<FacilityState> _initialFacilities(TeamId teamId) => [
    FacilityState(
      teamId: teamId,
      kind: FacilityKind.training,
      level: 2,
      maintenancePerYear: FinancialRules.facilityMaintenance(
        FacilityKind.training,
        2,
      ),
    ),
    for (final kind in const [
      FacilityKind.medical,
      FacilityKind.scouting,
      FacilityKind.arena,
    ])
      FacilityState(
        teamId: teamId,
        kind: kind,
        level: 1,
        maintenancePerYear: FinancialRules.facilityMaintenance(kind, 1),
      ),
  ];
}
