import '../career/season_settlement_record.dart';
import '../models/contract_financials.dart';
import '../models/facility_state.dart';
import '../models/guaranteed_liability.dart';
import '../models/ids.dart';
import '../models/player_contract.dart';
import '../models/staff_commitment.dart';
import '../models/team_finances.dart';
import 'career_finances.dart';

/// Next-season salary-cap and grandfathering status for one franchise.
final class TeamCapRolloverStatus {
  const TeamCapRolloverStatus({
    required this.teamId,
    required this.nextYearActiveStandardPayroll,
    required this.nextYearGuaranteedLiabilityCap,
    required this.nextYearTotalCapPayroll,
    required this.wasGrandfathered,
    required this.isGrandfathered,
    required this.grandfatheredPayroll,
  });

  final TeamId teamId;
  final int nextYearActiveStandardPayroll;
  final int nextYearGuaranteedLiabilityCap;
  final int nextYearTotalCapPayroll;
  final bool wasGrandfathered;
  final bool isGrandfathered;
  final int grandfatheredPayroll;
}

/// Complete per-franchise financial settlement and rollover breakdown.
final class TeamFinancialRolloverBreakdown {
  const TeamFinancialRolloverBreakdown({
    required this.teamId,
    required this.settlementEntry,
    required this.capStatus,
    required this.nextYearTeamFinances,
  });

  final TeamId teamId;
  final TeamSettlementEntry settlementEntry;
  final TeamCapRolloverStatus capStatus;
  final TeamFinances nextYearTeamFinances;
}

/// Pure, immutable financial rollover output for Year N -> Year N+1 (M009-T05C-C2-B).
///
/// Consumes a completed [GmCareer] and [SeasonRolloverPlan] without mutating
/// or persisting any career state.
final class FinancialRolloverPlan {
  FinancialRolloverPlan({
    required this.careerId,
    required this.completedYear,
    required this.targetYear,
    required Map<String, TeamFinancialRolloverBreakdown> teamBreakdowns,
    required List<PlayerContract> continuingContracts,
    required List<ContractFinancials> continuingSchedules,
    required List<GuaranteedLiability> newlyExtractedLiabilities,
    required List<GuaranteedLiability> proposedLiabilities,
    required List<StaffCommitment> continuingStaff,
    required List<StaffCommitment> expiredStaff,
    required List<FacilityState> preservedFacilities,
    required Map<String, int> proposedDebtByTeam,
    required this.proposedCareerFinances,
    required this.proposedSettlementRecord,
  }) : teamBreakdowns = Map.unmodifiable({
         for (final key in teamBreakdowns.keys.toList()..sort())
           key: teamBreakdowns[key]!,
       }),
       continuingContracts = List.unmodifiable(
         List<PlayerContract>.from(continuingContracts)
           ..sort((a, b) => a.id.compareTo(b.id)),
       ),
       continuingSchedules = List.unmodifiable(
         List<ContractFinancials>.from(continuingSchedules)
           ..sort((a, b) => a.contractId.compareTo(b.contractId)),
       ),
       newlyExtractedLiabilities = List.unmodifiable(
         List<GuaranteedLiability>.from(newlyExtractedLiabilities)
           ..sort((a, b) => a.id.compareTo(b.id)),
       ),
       proposedLiabilities = List.unmodifiable(
         List<GuaranteedLiability>.from(proposedLiabilities)
           ..sort((a, b) => a.id.compareTo(b.id)),
       ),
       continuingStaff = List.unmodifiable(
         List<StaffCommitment>.from(continuingStaff)
           ..sort((a, b) => a.id.compareTo(b.id)),
       ),
       expiredStaff = List.unmodifiable(
         List<StaffCommitment>.from(expiredStaff)
           ..sort((a, b) => a.id.compareTo(b.id)),
       ),
       preservedFacilities = List.unmodifiable(
         List<FacilityState>.from(preservedFacilities)..sort((a, b) {
           final byTeam = a.teamId.value.compareTo(b.teamId.value);
           return byTeam != 0 ? byTeam : a.kind.index.compareTo(b.kind.index);
         }),
       ),
       proposedDebtByTeam = Map.unmodifiable({
         for (final key in proposedDebtByTeam.keys.toList()..sort())
           key: proposedDebtByTeam[key]!,
       }) {
    validate();
  }

  final String careerId;
  final int completedYear;
  final int targetYear;
  final Map<String, TeamFinancialRolloverBreakdown> teamBreakdowns;
  final List<PlayerContract> continuingContracts;
  final List<ContractFinancials> continuingSchedules;
  final List<GuaranteedLiability> newlyExtractedLiabilities;
  final List<GuaranteedLiability> proposedLiabilities;
  final List<StaffCommitment> continuingStaff;
  final List<StaffCommitment> expiredStaff;
  final List<FacilityState> preservedFacilities;
  final Map<String, int> proposedDebtByTeam;
  final CareerFinances proposedCareerFinances;
  final SeasonSettlementRecord proposedSettlementRecord;

  void validate() {
    if (careerId.trim().isEmpty ||
        completedYear < 1 ||
        targetYear != completedYear + 1) {
      throw const FormatException(
        'Invalid FinancialRolloverPlan year metadata',
      );
    }
    if (teamBreakdowns.length != 30) {
      throw FormatException(
        'FinancialRolloverPlan requires 30 team breakdowns, got '
        '${teamBreakdowns.length}',
      );
    }
    if (proposedSettlementRecord.seasonYear != completedYear ||
        proposedSettlementRecord.teamEntries.length != 30) {
      throw const FormatException(
        'FinancialRolloverPlan settlement record mismatch',
      );
    }
  }
}
