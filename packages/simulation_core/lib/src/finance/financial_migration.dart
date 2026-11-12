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

/// One-time bootstrap of financial records from existing career state.
///
/// Used only when a career is created or a v1–v7 save is migrated and no
/// financial section exists. It is not a runtime contract factory: roster
/// changes after creation must use `FinancialTransactions` instead.
abstract final class FinancialMigration {
  static CareerFinances bootstrapFromCareerState({
    required League league,
    required LeagueCareerProfiles careerProfiles,
    required RookieSigningLedger rookieSigningLedger,
    required int currentYear,
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
        contracts.add(contract);
        schedules.add(
          ContractFinancials(
            contractId: contract.id,
            playerId: contract.playerId,
            teamId: contract.teamId,
            annualSalaries: _salariesFor(
              contract: contract,
              player: player,
              rookieSigningLedger: rookieSigningLedger,
            ),
            guaranteedYears: contract.durationYears,
            source: contract.source,
            signedYear: contract.startYear,
          ),
        );
      }
    }

    final capPayrollByTeam = <String, int>{};
    for (var i = 0; i < contracts.length; i++) {
      final contract = contracts[i];
      if (contract.category != RosterCategory.standard) continue;
      capPayrollByTeam[contract.teamId.value] =
          (capPayrollByTeam[contract.teamId.value] ?? 0) +
          schedules[i].annualSalaries.first;
    }

    final teams = <TeamFinances>[];
    for (final team in league.teams) {
      final plan = FinancialRules.planFor(
        team.situation ?? FranchiseSituation.playIn,
      );
      final payroll = capPayrollByTeam[team.id.value] ?? 0;
      final overCap = payroll > FinancialRules.salaryCap;
      teams.add(
        TeamFinances(
          teamId: team.id,
          operatingBudget: plan.operatingBudget,
          cash: plan.cash,
          revenueBaseline: plan.revenueBaseline,
          season: currentYear,
          capGrandfathered: overCap,
          grandfatheredPayroll: overCap ? payroll : 0,
        ),
      );
    }

    return CareerFinances(
      contracts: contracts,
      schedules: schedules,
      teamFinances: teams,
      staffCommitments: [
        for (final team in league.teams) ..._initialStaff(team.id, currentYear),
      ],
      facilities: [
        for (final team in league.teams) ..._initialFacilities(team.id),
      ],
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
        'Cannot bootstrap financial records: player ${player.id.value} has '
        'no career profile',
      );
    }
    return PlayerContract(
      id: PlayerContract.idFor(player.id, currentYear),
      playerId: player.id,
      teamId: team.id,
      category: team.roster.categoryOf(player.id),
      startYear: currentYear,
      durationYears: FinancialRules.legacyDurationForAge(profile.age),
      source: ContractSource.legacy,
    );
  }

  static List<int> _salariesFor({
    required PlayerContract contract,
    required Player player,
    required RookieSigningLedger rookieSigningLedger,
  }) {
    if (contract.category == RosterCategory.twoWay) {
      return FinancialRules.twoWaySchedule(contract.durationYears);
    }
    if (contract.source == ContractSource.rookie) {
      final rookie = rookieSigningLedger.forPlayer(contract.playerId)!;
      return FinancialRules.standardSchedule(
        FinancialRules.rookieSalaryForPick(rookie.overallPick),
        contract.durationYears,
      );
    }
    return FinancialRules.standardSchedule(
      FinancialRules.legacySalaryForOverall(player.attributes.overallRating),
      contract.durationYears,
    );
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
