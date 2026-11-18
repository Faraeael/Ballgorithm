import '../models/contract_financials.dart';
import '../models/carried_unsigned_prospect.dart';
import '../models/draft_rights.dart';
import '../models/ids.dart';
import '../models/player.dart';
import '../models/player_career_profile.dart';
import '../models/player_contract.dart';
import '../models/roster_category.dart';
import '../models/roster_rules.dart';
import 'career_phase.dart';
import 'retired_player_record.dart';

/// Deterministic classification of an active Year N contract during rollover.
enum ContractClassification {
  continuing('continuing'),
  expired('expired'),
  retiredWithGuarantees('retiredWithGuarantees');

  const ContractClassification(this.jsonValue);
  final String jsonValue;
}

/// Immutable snapshot of a surviving player aged +1 year with frozen attributes.
final class AgedPlayerSnapshot {
  AgedPlayerSnapshot({
    required this.player,
    required this.previousProfile,
    required this.nextProfile,
  }) {
    validate();
  }

  final Player player;
  final PlayerCareerProfile previousProfile;
  final PlayerCareerProfile nextProfile;

  void validate() {
    previousProfile.validate(player);
    nextProfile.validate(player);
    if (nextProfile.age != previousProfile.age + 1 ||
        nextProfile.potential != previousProfile.potential ||
        nextProfile.trajectory != previousProfile.trajectory) {
      throw const FormatException(
        'AgedPlayerSnapshot must increment age by 1 with frozen potential/trajectory',
      );
    }
  }
}

/// Classification record for one Year N [PlayerContract] and its schedule.
final class PlannedContractDecision {
  PlannedContractDecision({
    required this.contract,
    required this.schedule,
    required this.classification,
    List<int> remainingGuaranteedSalaries = const [],
  }) : remainingGuaranteedSalaries = List.unmodifiable(
         remainingGuaranteedSalaries,
       );

  final PlayerContract contract;
  final ContractFinancials schedule;
  final ContractClassification classification;
  final List<int> remainingGuaranteedSalaries;
}

/// Pending guaranteed obligation extracted from a retired player's unexpired contract.
///
/// Consumed by C2-B to construct persistent `GuaranteedLiability` records.
final class PendingGuaranteedLiability {
  PendingGuaranteedLiability({
    required this.contractId,
    required this.playerId,
    required this.teamId,
    required this.originalContract,
    required this.originalSchedule,
    required Map<int, int> futureYearSalaries,
  }) : futureYearSalaries = Map.unmodifiable({
         for (final y in futureYearSalaries.keys.toList()..sort())
           y: futureYearSalaries[y]!,
       }) {
    if (this.futureYearSalaries.isEmpty) {
      throw const FormatException(
        'PendingGuaranteedLiability requires at least one future year salary',
      );
    }
  }

  final String contractId;
  final PlayerId playerId;
  final TeamId teamId;
  final PlayerContract originalContract;
  final ContractFinancials originalSchedule;
  final Map<int, int> futureYearSalaries;

  int get totalRemainingGuarantee =>
      futureYearSalaries.values.fold(0, (sum, v) => sum + v);
}

/// One continuing contracted player on a proposed Year N+1 team roster.
final class PlannedRosterEntry {
  const PlannedRosterEntry({
    required this.player,
    required this.nextProfile,
    required this.category,
    required this.contract,
    required this.schedule,
  });

  final Player player;
  final PlayerCareerProfile nextProfile;
  final RosterCategory category;
  final PlayerContract contract;
  final ContractFinancials schedule;
}

/// Non-blocking roster shortage report for a franchise entering Year N+1 offseason.
final class TeamRosterShortage {
  const TeamRosterShortage({
    required this.teamId,
    required this.continuingStandardCount,
    required this.continuingTwoWayCount,
    required this.missingStandardForRegularSeason,
  });

  final TeamId teamId;
  final int continuingStandardCount;
  final int continuingTwoWayCount;
  final int missingStandardForRegularSeason;

  bool get hasShortage => missingStandardForRegularSeason > 0;
}

/// Proposed Year N+1 continuing roster for one franchise.
final class PlannedTeamRoster {
  PlannedTeamRoster({
    required this.teamId,
    required List<PlannedRosterEntry> entries,
    required this.shortage,
  }) : entries = List.unmodifiable(
         List<PlannedRosterEntry>.from(entries)
           ..sort((a, b) => a.player.id.value.compareTo(b.player.id.value)),
       );

  final TeamId teamId;
  final List<PlannedRosterEntry> entries;
  final TeamRosterShortage shortage;
}

/// Pure, immutable, validated plan for Year N -> Year N+1 continuity (M009-T05C-C2-A).
///
/// Produces zero side effects and does not mutate or persist any `GmCareer`.
final class SeasonRolloverPlan {
  SeasonRolloverPlan({
    required this.careerId,
    required this.completedYear,
    required this.targetYear,
    required List<RetiredPlayerRecord> retirements,
    required List<PlannedContractDecision> continuingContracts,
    required List<PlannedContractDecision> expiredContracts,
    required List<PlannedContractDecision> retiredContracts,
    required List<PendingGuaranteedLiability> pendingGuaranteedLiabilities,
    required Map<String, PlannedTeamRoster> proposedRosters,
    required List<TeamRosterShortage> rosterShortages,
    required List<AgedPlayerSnapshot> eligibleExpiringFreeAgents,
    required List<AgedPlayerSnapshot> carriedForwardFreeAgents,
    required Map<String, DraftRights> proposedDraftRightsCarryover,
    Map<String, CarriedUnsignedProspect> proposedCarriedUnsignedProspects =
        const {},
  }) : retirements = List.unmodifiable(
         List<RetiredPlayerRecord>.from(retirements)
           ..sort((a, b) => a.playerId.value.compareTo(b.playerId.value)),
       ),
       continuingContracts = List.unmodifiable(
         List<PlannedContractDecision>.from(continuingContracts)
           ..sort((a, b) => a.contract.id.compareTo(b.contract.id)),
       ),
       expiredContracts = List.unmodifiable(
         List<PlannedContractDecision>.from(expiredContracts)
           ..sort((a, b) => a.contract.id.compareTo(b.contract.id)),
       ),
       retiredContracts = List.unmodifiable(
         List<PlannedContractDecision>.from(retiredContracts)
           ..sort((a, b) => a.contract.id.compareTo(b.contract.id)),
       ),
       pendingGuaranteedLiabilities = List.unmodifiable(
         List<PendingGuaranteedLiability>.from(pendingGuaranteedLiabilities)
           ..sort((a, b) => a.contractId.compareTo(b.contractId)),
       ),
       proposedRosters = Map.unmodifiable({
         for (final k in proposedRosters.keys.toList()..sort())
           k: proposedRosters[k]!,
       }),
       rosterShortages = List.unmodifiable(
         List<TeamRosterShortage>.from(rosterShortages)
           ..sort((a, b) => a.teamId.value.compareTo(b.teamId.value)),
       ),
       eligibleExpiringFreeAgents = List.unmodifiable(
         List<AgedPlayerSnapshot>.from(eligibleExpiringFreeAgents)
           ..sort((a, b) => a.player.id.value.compareTo(b.player.id.value)),
       ),
       carriedForwardFreeAgents = List.unmodifiable(
         List<AgedPlayerSnapshot>.from(carriedForwardFreeAgents)
           ..sort((a, b) => a.player.id.value.compareTo(b.player.id.value)),
       ),
       proposedDraftRightsCarryover = Map.unmodifiable({
         for (final k in proposedDraftRightsCarryover.keys.toList()..sort())
           k: proposedDraftRightsCarryover[k]!,
       }),
       proposedCarriedUnsignedProspects = Map.unmodifiable({
         for (final k in proposedCarriedUnsignedProspects.keys.toList()..sort())
           k: proposedCarriedUnsignedProspects[k]!,
       }) {
    validate();
  }

  final String careerId;
  final int completedYear;
  final int targetYear;
  final List<RetiredPlayerRecord> retirements;
  final List<PlannedContractDecision> continuingContracts;
  final List<PlannedContractDecision> expiredContracts;
  final List<PlannedContractDecision> retiredContracts;
  final List<PendingGuaranteedLiability> pendingGuaranteedLiabilities;
  final Map<String, PlannedTeamRoster> proposedRosters;
  final List<TeamRosterShortage> rosterShortages;
  final List<AgedPlayerSnapshot> eligibleExpiringFreeAgents;
  final List<AgedPlayerSnapshot> carriedForwardFreeAgents;
  final Map<String, DraftRights> proposedDraftRightsCarryover;
  final Map<String, CarriedUnsignedProspect> proposedCarriedUnsignedProspects;

  int get totalContinuingPlayers => proposedRosters.values.fold(
    0,
    (sum, teamRoster) => sum + teamRoster.entries.length,
  );

  int get totalRegularSeasonShortage => rosterShortages.fold(
    0,
    (sum, s) => sum + s.missingStandardForRegularSeason,
  );

  void validate() {
    if (careerId.trim().isEmpty ||
        completedYear < 1 ||
        targetYear != completedYear + 1) {
      throw const FormatException('Invalid SeasonRolloverPlan year metadata');
    }
    if (proposedRosters.length != 30) {
      throw FormatException(
        'SeasonRolloverPlan requires 30 proposed rosters, got '
        '${proposedRosters.length}',
      );
    }

    final seenContractIds = <String>{};
    for (final c in [
      ...continuingContracts,
      ...expiredContracts,
      ...retiredContracts,
    ]) {
      if (!seenContractIds.add(c.contract.id)) {
        throw FormatException(
          'Duplicate contract classification for ${c.contract.id}',
        );
      }
    }

    final retiredIds = <String>{};
    for (final r in retirements) {
      r.validate();
      if (r.retiredAfterYear != completedYear) {
        throw FormatException(
          'RetiredPlayerRecord ${r.playerId.value} year '
          '${r.retiredAfterYear} != $completedYear',
        );
      }
      if (!retiredIds.add(r.playerId.value)) {
        throw FormatException(
          'Duplicate retirement in plan: ${r.playerId.value}',
        );
      }
    }

    final activeRosterPlayerIds = <String>{};
    for (final teamRoster in proposedRosters.values) {
      var standardCount = 0;
      var twoWayCount = 0;
      for (final entry in teamRoster.entries) {
        final pid = entry.player.id.value;
        if (!activeRosterPlayerIds.add(pid)) {
          throw FormatException('Duplicate player ownership in plan: $pid');
        }
        if (retiredIds.contains(pid)) {
          throw FormatException(
            'Retired player $pid cannot appear on proposed roster',
          );
        }
        if (entry.nextProfile.age > PlayerCareerProfile.maxAge) {
          throw FormatException('Proposed roster player $pid exceeds maxAge');
        }
        if (entry.contract.teamId != teamRoster.teamId ||
            entry.contract.category != entry.category ||
            !entry.contract.isActiveIn(targetYear)) {
          throw FormatException('Proposed roster entry $pid contract mismatch');
        }
        if (entry.category == RosterCategory.standard) {
          standardCount++;
        } else if (entry.category == RosterCategory.twoWay) {
          twoWayCount++;
        } else {
          throw FormatException('Illegal continuing roster category for $pid');
        }
      }
      RosterRules.validateStructure(
        standardCount: standardCount,
        twoWayCount: twoWayCount,
        trainingCampCount: 0,
        phase: CareerPhase.openingOffseason,
      ).throwIfInvalid();
    }

    final freeAgentIds = <String>{};
    for (final fa in [
      ...eligibleExpiringFreeAgents,
      ...carriedForwardFreeAgents,
    ]) {
      fa.validate();
      final pid = fa.player.id.value;
      if (!freeAgentIds.add(pid)) {
        throw FormatException('Duplicate free-agent identity in plan: $pid');
      }
      if (activeRosterPlayerIds.contains(pid) || retiredIds.contains(pid)) {
        throw FormatException(
          'Free-agent $pid collides with active roster or retirement',
        );
      }
    }

    for (final entry in proposedDraftRightsCarryover.entries) {
      entry.value.validate();
      final pid = entry.key;
      if (pid != entry.value.prospectId.value) {
        throw const FormatException(
          'Proposed draft rights key does not match prospectId',
        );
      }
      if (activeRosterPlayerIds.contains(pid) ||
          freeAgentIds.contains(pid) ||
          retiredIds.contains(pid)) {
        throw FormatException(
          'Proposed draft rights $pid collides with roster, FA, or retirement',
        );
      }
      final snapshot = proposedCarriedUnsignedProspects[pid];
      if (snapshot == null) {
        throw FormatException(
          'Missing CarriedUnsignedProspect snapshot for proposed draft rights '
          '$pid',
        );
      }
      snapshot.validate();
      if (snapshot.playerId != entry.value.prospectId ||
          snapshot.draftSeasonYear != entry.value.seasonYear ||
          snapshot.overallPick != entry.value.overallPick) {
        throw FormatException(
          'CarriedUnsignedProspect $pid does not match proposed draft rights '
          'provenance',
        );
      }
    }
    for (final entry in proposedCarriedUnsignedProspects.entries) {
      entry.value.validate();
      if (entry.key != entry.value.playerId.value) {
        throw const FormatException(
          'Proposed carried unsigned prospect key does not match playerId',
        );
      }
      if (!proposedDraftRightsCarryover.containsKey(entry.key)) {
        throw FormatException(
          'Proposed carried unsigned prospect ${entry.key} has no matching '
          'draft rights',
        );
      }
    }
  }
}
