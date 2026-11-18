import '../career/career_phase.dart';
import '../career/gm_career.dart';
import '../career/season_archive.dart';
import '../career/season_rollover_plan.dart';
import '../career/season_settlement_record.dart';
import '../models/contract_financials.dart';
import '../models/guaranteed_liability.dart';
import '../models/player_contract.dart';
import '../models/roster_category.dart';
import '../models/staff_commitment.dart';
import '../models/team_finances.dart';
import 'career_finances.dart';
import 'financial_rollover_plan.dart';
import 'financial_rules.dart';

/// Pure deterministic financial rollover & settlement service (M009-T05C-C2-B).
///
/// Consumes a completed Year N [GmCareer] and [SeasonRolloverPlan] and returns
/// an immutable [FinancialRolloverPlan] without mutating or persisting state.
final class FinancialRolloverService {
  const FinancialRolloverService();

  FinancialRolloverPlan plan({
    required GmCareer career,
    required SeasonRolloverPlan rolloverPlan,
  }) {
    career.validate();
    rolloverPlan.validate();

    final completedYear = career.currentYear;
    final targetYear = completedYear + 1;

    if (rolloverPlan.careerId != career.id ||
        rolloverPlan.completedYear != completedYear ||
        rolloverPlan.targetYear != targetYear) {
      throw StateError(
        'SeasonRolloverPlan (${rolloverPlan.careerId} y${rolloverPlan.completedYear}) '
        'does not match career (${career.id} y$completedYear)',
      );
    }
    if (career.phase != CareerPhase.playoffs) {
      throw StateError(
        'Cannot settle finances outside CareerPhase.playoffs (got ${career.phase.name})',
      );
    }
    if (career.seasonSettlements.any((s) => s.seasonYear == completedYear)) {
      throw StateError(
        'Season $completedYear has already been settled in seasonSettlements',
      );
    }
    if (career.seasonHistory.any((r) => r.seasonYear == completedYear)) {
      throw StateError(
        'Season $completedYear has already been archived in seasonHistory',
      );
    }
    SeasonArchive.fromCareer(career);

    // 1. Validate & extract newly retired guaranteed liabilities (starting Year N+1).
    final existingLiabilities = career.finances.guaranteedLiabilities;
    final newlyExtractedLiabilities = <GuaranteedLiability>[];
    final seenLiabilityContracts = <String>{
      for (final l in existingLiabilities.values) l.originalContractId,
    };

    for (final pending in rolloverPlan.pendingGuaranteedLiabilities) {
      final sourceContract = career.finances.contracts[pending.contractId];
      final sourceSchedule = career.finances.schedules[pending.contractId];
      if (sourceContract == null ||
          sourceSchedule == null ||
          sourceContract.playerId != pending.playerId ||
          sourceContract.teamId != pending.teamId) {
        throw StateError(
          'PendingGuaranteedLiability ${pending.contractId} does not match '
          'career finances',
        );
      }
      final liabilityId = GuaranteedLiability.idFor(pending.contractId);
      if (existingLiabilities.containsKey(liabilityId) ||
          !seenLiabilityContracts.add(pending.contractId)) {
        throw StateError(
          'Duplicate guaranteed liability for contract ${pending.contractId}',
        );
      }
      newlyExtractedLiabilities.add(
        GuaranteedLiability(
          id: liabilityId,
          originalContractId: pending.contractId,
          playerId: pending.playerId,
          teamId: pending.teamId,
          originalCategory: sourceContract.category,
          retirementYear: completedYear,
          salariesByYear: pending.futureYearSalaries,
        ),
      );
    }

    final proposedLiabilities = <GuaranteedLiability>[
      ...existingLiabilities.values,
      ...newlyExtractedLiabilities,
    ];

    final continuingContracts = <PlayerContract>[];
    final continuingSchedules = <ContractFinancials>[];
    for (final d in rolloverPlan.continuingContracts) {
      final sourceContract = career.finances.contracts[d.contract.id];
      final sourceSchedule = career.finances.schedules[d.contract.id];
      if (sourceContract == null ||
          sourceSchedule == null ||
          d.contract.playerId != sourceContract.playerId ||
          d.contract.teamId != sourceContract.teamId ||
          d.contract.category != sourceContract.category ||
          d.contract.startYear != sourceContract.startYear ||
          d.contract.durationYears != sourceContract.durationYears ||
          d.contract.source != sourceContract.source ||
          d.contract.rookieContractId != sourceContract.rookieContractId ||
          d.schedule.signedYear != sourceSchedule.signedYear ||
          d.schedule.guaranteedYears != sourceSchedule.guaranteedYears ||
          d.schedule.annualSalaries.join(',') !=
              sourceSchedule.annualSalaries.join(',')) {
        throw StateError(
          'SeasonRolloverPlan continuing contract ${d.contract.id} does not '
          'match authoritative career finances',
        );
      }
      continuingContracts.add(sourceContract);
      continuingSchedules.add(sourceSchedule);
    }
    final continuingContractIds = {for (final c in continuingContracts) c.id};
    final retiredPlayerIds = {
      for (final r in rolloverPlan.retirements) r.playerId.value,
    };
    for (final contract in career.finances.contracts.values) {
      if (contract.isActiveIn(targetYear) &&
          !retiredPlayerIds.contains(contract.playerId.value) &&
          !continuingContractIds.contains(contract.id)) {
        throw StateError(
          'SeasonRolloverPlan omitted continuing contract ${contract.id}',
        );
      }
    }
    final continuingPlayerIds = {
      for (final c in continuingContracts) c.playerId.value,
    };
    for (final liability in proposedLiabilities) {
      if (continuingContractIds.contains(liability.originalContractId) ||
          continuingPlayerIds.contains(liability.playerId.value)) {
        throw StateError(
          'Double-counted contract/liability for ${liability.originalContractId}',
        );
      }
    }

    // 2. Partition staff commitments and preserve facilities.
    final continuingStaff = <StaffCommitment>[];
    final expiredStaff = <StaffCommitment>[];
    for (final staff in career.finances.staffCommitments.values) {
      if (staff.isActiveIn(targetYear)) {
        continuingStaff.add(staff);
      } else {
        expiredStaff.add(staff);
      }
    }
    final preservedFacilities = career.finances.facilities.values.toList();

    // 3. Per-franchise Year N settlement, debt reconciliation, and Year N+1 cap status.
    final teamsSorted = career.league.teams.toList()
      ..sort((a, b) => a.id.value.compareTo(b.id.value));
    final teamBreakdowns = <String, TeamFinancialRolloverBreakdown>{};
    final settlementEntries = <TeamSettlementEntry>[];
    final nextTeamFinances = <TeamFinances>[];
    final proposedDebtByTeam = <String, int>{};
    var totalRevenue = 0;
    var totalExpenses = 0;

    for (final team in teamsSorted) {
      final tf = career.finances.financesFor(team.id);
      final startCash = tf.cash;
      final startDebt = career.finances.debtFor(team.id);
      final revenue = tf.revenueBaseline;

      // Completed Year N obligations: active standard + two-way + prior retired guarantees + Year N staff + facilities.
      final activeSalaryExpense =
          career.finances.activeStandardPayrollFor(team.id, completedYear) +
          career.finances.twoWayPayrollFor(team.id, completedYear);
      final retiredGuaranteeExpense = career.finances
          .guaranteedLiabilityCashFor(team.id, completedYear);
      var staffExpense = 0;
      for (final staff in career.finances.staffCommitments.values) {
        if (staff.teamId == team.id && staff.isActiveIn(completedYear)) {
          staffExpense += staff.annualCost;
        }
      }
      var facilityExpense = 0;
      for (final facility in preservedFacilities) {
        if (facility.teamId == team.id) {
          facilityExpense += facility.maintenancePerYear;
        }
      }

      final teamExpenses =
          activeSalaryExpense +
          retiredGuaranteeExpense +
          staffExpense +
          facilityExpense;
      final netPosition = startCash - startDebt + revenue - teamExpenses;

      final int endCash;
      final int endDebt;
      if (netPosition < 0) {
        endCash = 0;
        endDebt = -netPosition;
      } else {
        endCash = netPosition;
        endDebt = 0;
      }
      if (endCash > FinancialRules.maximumBalance ||
          endDebt > FinancialRules.maximumBalance) {
        throw StateError(
          'Settlement result for ${team.id.value} exceeds maximumBalance '
          '(${FinancialRules.maximumBalance}): cash=$endCash debt=$endDebt',
        );
      }

      if (endDebt > 0) {
        proposedDebtByTeam[team.id.value] = endDebt;
      }

      final entry = TeamSettlementEntry(
        teamId: team.id,
        startingCash: startCash,
        startingDebt: startDebt,
        revenue: revenue,
        activePlayerSalaryExpense: activeSalaryExpense,
        retiredGuaranteeExpense: retiredGuaranteeExpense,
        staffExpense: staffExpense,
        facilityMaintenanceExpense: facilityExpense,
        endingCash: endCash,
        endingDebt: endDebt,
      );
      settlementEntries.add(entry);
      totalRevenue += revenue;
      totalExpenses += teamExpenses;

      // Year N+1 Cap & Grandfathering reconciliation.
      var nextActiveStandardPayroll = 0;
      for (final schedule in continuingSchedules) {
        if (schedule.teamId != team.id) continue;
        final contract = continuingContracts.firstWhere(
          (c) => c.id == schedule.contractId,
        );
        if (contract.category == RosterCategory.standard) {
          nextActiveStandardPayroll += schedule.salaryForYear(targetYear) ?? 0;
        }
      }
      var nextLiabilityCap = 0;
      for (final liability in proposedLiabilities) {
        if (liability.teamId == team.id &&
            liability.originalCategory == RosterCategory.standard) {
          nextLiabilityCap += liability.salaryForYear(targetYear);
        }
      }
      final nextTotalCapPayroll = nextActiveStandardPayroll + nextLiabilityCap;

      final bool nextGrandfathered;
      final int nextGrandfatheredPayroll;
      if (tf.capGrandfathered) {
        if (nextTotalCapPayroll <= FinancialRules.salaryCap) {
          nextGrandfathered = false;
          nextGrandfatheredPayroll = 0;
        } else {
          if (nextTotalCapPayroll >
              tf.grandfatheredPayroll + FinancialRules.maximumReliefOverage) {
            throw StateError(
              'Team ${team.id.value} Year $targetYear grandfathered payroll '
              '$nextTotalCapPayroll exceeds baseline ${tf.grandfatheredPayroll}',
            );
          }
          nextGrandfathered = true;
          nextGrandfatheredPayroll = tf.grandfatheredPayroll;
        }
      } else {
        nextGrandfathered = false;
        nextGrandfatheredPayroll = 0;
      }

      final nextTf = TeamFinances(
        teamId: team.id,
        operatingBudget: tf.operatingBudget,
        cash: endCash,
        revenueBaseline: tf.revenueBaseline,
        season: targetYear,
        capGrandfathered: nextGrandfathered,
        grandfatheredPayroll: nextGrandfatheredPayroll,
        capException: 0,
      );
      nextTeamFinances.add(nextTf);

      teamBreakdowns[team.id.value] = TeamFinancialRolloverBreakdown(
        teamId: team.id,
        settlementEntry: entry,
        capStatus: TeamCapRolloverStatus(
          teamId: team.id,
          nextYearActiveStandardPayroll: nextActiveStandardPayroll,
          nextYearGuaranteedLiabilityCap: nextLiabilityCap,
          nextYearTotalCapPayroll: nextTotalCapPayroll,
          wasGrandfathered: tf.capGrandfathered,
          isGrandfathered: nextGrandfathered,
          grandfatheredPayroll: nextGrandfatheredPayroll,
        ),
        nextYearTeamFinances: nextTf,
      );
    }

    final proposedCareerFinances = CareerFinances(
      contracts: continuingContracts,
      schedules: continuingSchedules,
      teamFinances: nextTeamFinances,
      staffCommitments: continuingStaff,
      facilities: preservedFacilities,
      guaranteedLiabilities: proposedLiabilities,
      debtByTeam: proposedDebtByTeam,
    );

    final proposedSettlementRecord = SeasonSettlementRecord(
      seasonYear: completedYear,
      settledTeamIds: [for (final t in teamsSorted) t.id],
      totalRevenue: totalRevenue,
      totalExpenses: totalExpenses,
      teamEntries: settlementEntries,
    );

    return FinancialRolloverPlan(
      careerId: career.id,
      completedYear: completedYear,
      targetYear: targetYear,
      teamBreakdowns: teamBreakdowns,
      continuingContracts: continuingContracts,
      continuingSchedules: continuingSchedules,
      newlyExtractedLiabilities: newlyExtractedLiabilities,
      proposedLiabilities: proposedLiabilities,
      continuingStaff: continuingStaff,
      expiredStaff: expiredStaff,
      preservedFacilities: preservedFacilities,
      proposedDebtByTeam: proposedDebtByTeam,
      proposedCareerFinances: proposedCareerFinances,
      proposedSettlementRecord: proposedSettlementRecord,
    );
  }
}
