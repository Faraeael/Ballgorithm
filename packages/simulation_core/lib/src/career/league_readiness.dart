import '../models/ai_rookie_signing.dart';
import '../models/franchise_situation.dart';
import '../models/ids.dart';
import '../models/roster_rules.dart';
import 'gm_career.dart';

/// Read-only regular-season readiness for one franchise during the offseason.
final class TeamReadiness {
  const TeamReadiness({
    required this.teamId,
    required this.name,
    required this.abbreviation,
    required this.situation,
    required this.standardCount,
    required this.twoWayCount,
    required this.trainingCampCount,
    required this.totalCount,
    required this.isReady,
    required this.standardShortage,
    required this.unsignedDraftedRights,
    required this.signedDraftedRookies,
    required this.readinessIssues,
    required this.isHuman,
  });

  final TeamId teamId;
  final String name;
  final String abbreviation;
  final FranchiseSituation situation;
  final int standardCount;
  final int twoWayCount;
  final int trainingCampCount;
  final int totalCount;
  final bool isReady;
  final int standardShortage;
  final int unsignedDraftedRights;
  final int signedDraftedRookies;
  final List<String> readinessIssues;
  final bool isHuman;

  /// Number of additional standard players required for regular-season readiness.
  int get standardPlayersNeeded => standardShortage;
}

/// League-wide offseason readiness and AI signing progress derived from a career.
final class LeagueReadinessReport {
  const LeagueReadinessReport({
    required this.teams,
    required this.userTeamId,
    required this.totalAiRights,
    required this.evaluatedAiDecisions,
    required this.aiStandardSignings,
    required this.aiTwoWaySignings,
    required this.aiDeferredRights,
    required this.aiParticipatingFranchises,
  });

  factory LeagueReadinessReport.fromCareer(GmCareer career) {
    final rights = career.draftExecutionState.draftRights.values;
    final ledger = career.rookieSigningLedger;
    final decisions = career.aiRookieSigning.decisions.values
        .where((decision) => decision.teamId != career.userFranchiseId)
        .toList();

    final teams = <TeamReadiness>[];
    for (final team in career.league.teams) {
      final readiness = team.roster.validateRegularSeasonReadiness();
      teams.add(
        TeamReadiness(
          teamId: team.id,
          name: team.name,
          abbreviation: team.abbreviation,
          situation: team.situation ?? FranchiseSituation.playIn,
          standardCount: team.roster.standardCount,
          twoWayCount: team.roster.twoWayCount,
          trainingCampCount: team.roster.trainingCampCount,
          totalCount: team.roster.totalContractedCount,
          isReady: readiness.isValid,
          standardShortage:
              (RosterRules.minRegularSeasonStandard - team.roster.standardCount)
                  .clamp(0, RosterRules.minRegularSeasonStandard),
          unsignedDraftedRights: rights
              .where(
                (right) =>
                    right.owningTeamId == team.id &&
                    !ledger.isSigned(right.prospectId),
              )
              .length,
          signedDraftedRookies: ledger.contracts.values
              .where((contract) => contract.teamId == team.id)
              .length,
          readinessIssues: readiness.issues,
          isHuman: team.id == career.userFranchiseId,
        ),
      );
    }

    final aiRights = rights
        .where((right) => right.owningTeamId != career.userFranchiseId)
        .toList();
    final evaluated = aiRights
        .where((right) => career.aiRookieSigning.hasDecision(right.prospectId))
        .length;
    return LeagueReadinessReport(
      teams: List.unmodifiable(teams),
      userTeamId: career.userFranchiseId,
      totalAiRights: aiRights.length,
      evaluatedAiDecisions: evaluated,
      aiStandardSignings: decisions
          .where((d) => d.decision == AiSigningDecisionType.signedStandard)
          .length,
      aiTwoWaySignings: decisions
          .where((d) => d.decision == AiSigningDecisionType.signedTwoWay)
          .length,
      aiDeferredRights: decisions
          .where((d) => d.decision == AiSigningDecisionType.deferred)
          .length,
      aiParticipatingFranchises: {
        for (final right in aiRights) right.owningTeamId.value,
      }.length,
    );
  }

  final List<TeamReadiness> teams;
  final TeamId userTeamId;
  final int totalAiRights;
  final int evaluatedAiDecisions;
  final int aiStandardSignings;
  final int aiTwoWaySignings;
  final int aiDeferredRights;
  final int aiParticipatingFranchises;

  int get pendingAiDecisions => totalAiRights - evaluatedAiDecisions;

  bool get aiSigningComplete => pendingAiDecisions == 0;

  int get readyCount => teams.where((team) => team.isReady).length;

  int get notReadyCount => teams.length - readyCount;

  int get totalStandardShortage =>
      teams.fold(0, (sum, team) => sum + team.standardShortage);

  int get aiReadyCount =>
      teams.where((team) => !team.isHuman && team.isReady).length;

  int get aiNotReadyCount =>
      teams.where((team) => !team.isHuman && !team.isReady).length;

  int get aiBelowMinimumCount => teams
      .where(
        (team) =>
            !team.isHuman &&
            team.standardCount < RosterRules.minRegularSeasonStandard,
      )
      .length;

  int get humanStandardShortage => userTeam.standardShortage;

  TeamReadiness get userTeam =>
      teams.firstWhere((team) => team.teamId == userTeamId);
}
