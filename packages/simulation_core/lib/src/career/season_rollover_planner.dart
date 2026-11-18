import '../models/carried_unsigned_prospect.dart';
import '../models/draft_rights.dart';
import '../models/draft_selection.dart';
import '../models/ids.dart';
import '../models/player_career_profile.dart';
import '../models/roster_category.dart';
import '../models/roster_rules.dart';
import 'career_phase.dart';
import 'gm_career.dart';
import 'retired_player_record.dart';
import 'season_archive.dart';
import 'season_rollover_plan.dart';

/// Pure deterministic planner for Year N -> Year N+1 continuity (M009-T05C-C2-A).
///
/// Produces an immutable [SeasonRolloverPlan] without mutating [GmCareer],
/// advancing `currentYear`, settling finances, or persisting any state.
final class SeasonRolloverPlanner {
  const SeasonRolloverPlanner();

  /// Validates eligibility of [career] and computes its deterministic [SeasonRolloverPlan].
  SeasonRolloverPlan plan(GmCareer career) {
    career.validate();
    final completedYear = career.currentYear;
    final targetYear = completedYear + 1;

    if (career.phase != CareerPhase.playoffs) {
      throw StateError(
        'Cannot plan rollover outside CareerPhase.playoffs (got ${career.phase.name})',
      );
    }
    if (career.seasonHistory.any((r) => r.seasonYear == completedYear)) {
      throw StateError(
        'Season $completedYear has already been archived in seasonHistory',
      );
    }
    if (career.seasonSettlements.any((s) => s.seasonYear == completedYear)) {
      throw StateError(
        'Season $completedYear has already been settled in seasonSettlements',
      );
    }
    // Enforces complete 1,230-game regular season, Play-In, and championship.
    SeasonArchive.fromCareer(career);

    final retirements = <RetiredPlayerRecord>[];
    final retiredPlayerIds = <String>{};
    final continuingContracts = <PlannedContractDecision>[];
    final expiredContracts = <PlannedContractDecision>[];
    final retiredContracts = <PlannedContractDecision>[];
    final pendingLiabilities = <PendingGuaranteedLiability>[];
    final proposedRosters = <String, PlannedTeamRoster>{};
    final rosterShortages = <TeamRosterShortage>[];
    final eligibleExpiringFreeAgents = <AgedPlayerSnapshot>[];
    final carriedForwardFreeAgents = <AgedPlayerSnapshot>[];

    final teamsSorted = career.league.teams.toList()
      ..sort((a, b) => a.id.value.compareTo(b.id.value));
    final validTeamIds = {for (final t in teamsSorted) t.id.value};

    for (final team in teamsSorted) {
      final continuingEntries = <PlannedRosterEntry>[];
      var standardCount = 0;
      var twoWayCount = 0;

      final playersSorted = team.players.toList()
        ..sort((a, b) => a.id.value.compareTo(b.id.value));

      for (final player in playersSorted) {
        final profile = career.careerProfiles.forPlayer(player.id);
        final contract = career.finances.contractForPlayer(player.id);
        if (profile == null || contract == null) {
          throw StateError(
            'Missing profile or active contract for rostered player ${player.id.value}',
          );
        }
        final schedule = career.finances.scheduleFor(contract.id);
        if (schedule == null) {
          throw StateError(
            'Missing financial schedule for contract ${contract.id}',
          );
        }
        final category = team.roster.categoryOf(player.id);
        if (contract.teamId != team.id || contract.category != category) {
          throw StateError(
            'Contract/roster mismatch for player ${player.id.value}',
          );
        }

        if (profile.age >= PlayerCareerProfile.maxAge) {
          retiredPlayerIds.add(player.id.value);
          retirements.add(
            RetiredPlayerRecord(
              playerId: player.id,
              fullName: player.fullName,
              position: player.position,
              finalAge: profile.age,
              retiredAfterYear: completedYear,
              lastTeamId: team.id,
              finalOverall: player.attributes.overallRating,
            ),
          );

          final endYearExclusive = contract.startYear + contract.durationYears;
          if (targetYear < endYearExclusive) {
            final futureSalaries = <int, int>{};
            final salaryList = <int>[];
            for (var y = targetYear; y < endYearExclusive; y++) {
              final amt = schedule.salaryForYear(y)!;
              futureSalaries[y] = amt;
              salaryList.add(amt);
            }
            retiredContracts.add(
              PlannedContractDecision(
                contract: contract,
                schedule: schedule,
                classification: ContractClassification.retiredWithGuarantees,
                remainingGuaranteedSalaries: salaryList,
              ),
            );
            pendingLiabilities.add(
              PendingGuaranteedLiability(
                contractId: contract.id,
                playerId: player.id,
                teamId: team.id,
                originalContract: contract,
                originalSchedule: schedule,
                futureYearSalaries: futureSalaries,
              ),
            );
          } else {
            expiredContracts.add(
              PlannedContractDecision(
                contract: contract,
                schedule: schedule,
                classification: ContractClassification.expired,
              ),
            );
          }
          continue;
        }

        final nextProfile = PlayerCareerProfile(
          playerId: profile.playerId,
          age: profile.age + 1,
          potential: profile.potential,
          trajectory: profile.trajectory,
        );

        if (contract.isActiveIn(targetYear)) {
          continuingContracts.add(
            PlannedContractDecision(
              contract: contract,
              schedule: schedule,
              classification: ContractClassification.continuing,
            ),
          );
          continuingEntries.add(
            PlannedRosterEntry(
              player: player,
              nextProfile: nextProfile,
              category: category,
              contract: contract,
              schedule: schedule,
            ),
          );
          if (category == RosterCategory.standard) {
            standardCount++;
          } else if (category == RosterCategory.twoWay) {
            twoWayCount++;
          }
        } else {
          expiredContracts.add(
            PlannedContractDecision(
              contract: contract,
              schedule: schedule,
              classification: ContractClassification.expired,
            ),
          );
          eligibleExpiringFreeAgents.add(
            AgedPlayerSnapshot(
              player: player,
              previousProfile: profile,
              nextProfile: nextProfile,
            ),
          );
        }
      }

      final missingStandard =
          standardCount < RosterRules.minRegularSeasonStandard
          ? RosterRules.minRegularSeasonStandard - standardCount
          : 0;
      final shortage = TeamRosterShortage(
        teamId: team.id,
        continuingStandardCount: standardCount,
        continuingTwoWayCount: twoWayCount,
        missingStandardForRegularSeason: missingStandard,
      );
      if (shortage.hasShortage) {
        rosterShortages.add(shortage);
      }
      proposedRosters[team.id.value] = PlannedTeamRoster(
        teamId: team.id,
        entries: continuingEntries,
        shortage: shortage,
      );
    }

    final faSorted = career.freeAgentPool.entries.toList()
      ..sort((a, b) => a.id.value.compareTo(b.id.value));
    for (final entry in faSorted) {
      if (entry.profile.age >= PlayerCareerProfile.maxAge) {
        retiredPlayerIds.add(entry.id.value);
        retirements.add(
          RetiredPlayerRecord(
            playerId: entry.id,
            fullName: entry.player.fullName,
            position: entry.player.position,
            finalAge: entry.profile.age,
            retiredAfterYear: completedYear,
            lastTeamId: null,
            finalOverall: entry.player.attributes.overallRating,
          ),
        );
      } else {
        final nextProfile = PlayerCareerProfile(
          playerId: entry.profile.playerId,
          age: entry.profile.age + 1,
          potential: entry.profile.potential,
          trajectory: entry.profile.trajectory,
        );
        carriedForwardFreeAgents.add(
          AgedPlayerSnapshot(
            player: entry.player,
            previousProfile: entry.profile,
            nextProfile: nextProfile,
          ),
        );
      }
    }

    final proposedDraftRightsCarryover = <String, DraftRights>{};
    final proposedCarriedUnsignedProspects =
        <String, CarriedUnsignedProspect>{};

    DraftSelection? selectionFor(PlayerId prospectId) {
      for (final s in career.draftExecutionState.selections) {
        if (s.prospectId == prospectId) return s;
      }
      return null;
    }

    void recordCarryover(
      DraftRights rights,
      CarriedUnsignedProspect agedSnapshot,
    ) {
      final pid = rights.prospectId.value;
      if (proposedDraftRightsCarryover.containsKey(pid) ||
          proposedCarriedUnsignedProspects.containsKey(pid)) {
        throw StateError('Duplicate draft rights detected for prospect $pid');
      }
      proposedDraftRightsCarryover[pid] = rights;
      proposedCarriedUnsignedProspects[pid] = agedSnapshot;
    }

    for (final pid in career.careerDraftRights.keys.toList()..sort()) {
      final rights = career.careerDraftRights[pid]!;
      if (!validTeamIds.contains(rights.owningTeamId.value)) {
        throw StateError(
          'Draft rights $pid reference unknown team ${rights.owningTeamId.value}',
        );
      }
      if (career.rookieSigningLedger.isSigned(rights.prospectId) ||
          retiredPlayerIds.contains(pid)) {
        continue;
      }
      final carried = career.carriedUnsignedProspects[pid];
      if (carried == null) {
        throw StateError(
          'Missing CarriedUnsignedProspect snapshot for carried draft rights '
          '$pid',
        );
      }
      if (carried.age >= PlayerCareerProfile.maxAge) {
        retiredPlayerIds.add(pid);
        retirements.add(
          RetiredPlayerRecord(
            playerId: carried.playerId,
            fullName: carried.fullName,
            position: carried.position,
            finalAge: carried.age,
            retiredAfterYear: completedYear,
            lastTeamId: null,
            finalOverall: carried.attributes.overallRating,
          ),
        );
        continue;
      }
      recordCarryover(rights, carried.withAge(carried.age + 1));
    }

    for (final pid
        in career.draftExecutionState.draftRights.keys.toList()..sort()) {
      final rights = career.draftExecutionState.draftRights[pid]!;
      if (!validTeamIds.contains(rights.owningTeamId.value)) {
        throw StateError(
          'Draft rights $pid reference unknown team ${rights.owningTeamId.value}',
        );
      }
      if (career.rookieSigningLedger.isSigned(rights.prospectId) ||
          retiredPlayerIds.contains(pid)) {
        continue;
      }
      final prospect = career.draftClass.byId(rights.prospectId);
      if (prospect == null) {
        throw StateError(
          'Draft rights $pid missing matching prospect in draftClass',
        );
      }
      final selection = selectionFor(rights.prospectId);
      if (selection == null ||
          selection.selectingTeamId != rights.owningTeamId ||
          selection.overallPick != rights.overallPick ||
          selection.seasonYear != rights.seasonYear) {
        throw StateError(
          'Draft rights $pid lack matching selection provenance',
        );
      }
      if (prospect.age >= PlayerCareerProfile.maxAge) {
        retiredPlayerIds.add(pid);
        retirements.add(
          RetiredPlayerRecord(
            playerId: prospect.id,
            fullName: prospect.fullName,
            position: prospect.position,
            finalAge: prospect.age,
            retiredAfterYear: completedYear,
            lastTeamId: null,
            finalOverall: prospect.attributes.overallRating,
          ),
        );
        continue;
      }
      recordCarryover(
        rights,
        CarriedUnsignedProspect.fromRookieProspect(
          prospect: prospect,
          rights: rights,
          age: prospect.age + 1,
        ),
      );
    }

    return SeasonRolloverPlan(
      careerId: career.id,
      completedYear: completedYear,
      targetYear: targetYear,
      retirements: retirements,
      continuingContracts: continuingContracts,
      expiredContracts: expiredContracts,
      retiredContracts: retiredContracts,
      pendingGuaranteedLiabilities: pendingLiabilities,
      proposedRosters: proposedRosters,
      rosterShortages: rosterShortages,
      eligibleExpiringFreeAgents: eligibleExpiringFreeAgents,
      carriedForwardFreeAgents: carriedForwardFreeAgents,
      proposedDraftRightsCarryover: proposedDraftRightsCarryover,
      proposedCarriedUnsignedProspects: proposedCarriedUnsignedProspects,
    );
  }
}
