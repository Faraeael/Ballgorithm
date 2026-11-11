import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _seed = 20261028;
const _team = TeamId('team-1');

void main() {
  late GmCareer completed;

  setUpAll(() {
    completed = _completedCareer();
  });

  group('M008-T07D league readiness report', () {
    test('lists all 30 franchises and derives readiness from RosterRules', () {
      final report = LeagueReadinessReport.fromCareer(completed);
      expect(report.teams.length, 30);
      expect(report.readyCount + report.notReadyCount, 30);
      for (final team in report.teams) {
        final source = completed.league.teams.firstWhere(
          (candidate) => candidate.id == team.teamId,
        );
        final readiness = source.roster.validateRegularSeasonReadiness();
        expect(team.isReady, readiness.isValid, reason: team.teamId.value);
        expect(team.readinessIssues, readiness.issues);
        expect(
          team.standardCount,
          source.roster.standardCount,
          reason: team.teamId.value,
        );
        expect(team.twoWayCount, source.roster.twoWayCount);
        expect(team.totalCount, source.roster.totalContractedCount);
      }
    });

    test('computes standard shortages from the 14-player minimum', () {
      final report = LeagueReadinessReport.fromCareer(completed);
      expect(report.totalStandardShortage, 60);
      expect(report.humanStandardShortage, 2);
      expect(report.userTeam.teamId, _team);
      expect(report.userTeam.isHuman, isTrue);
      expect(report.teams.where((team) => team.isHuman).length, 1);
      expect(report.teams.every((team) => team.standardShortage == 2), isTrue);
    });

    test('two-way players never satisfy the standard minimum', () {
      final expanded = _expandTeam(
        completed,
        const TeamId('team-2'),
        standard: 1,
        twoWay: 3,
      );
      final report = LeagueReadinessReport.fromCareer(expanded);
      final team = report.teams.firstWhere(
        (row) => row.teamId == const TeamId('team-2'),
      );
      expect(team.standardCount, 13);
      expect(team.twoWayCount, 3);
      expect(team.isReady, isFalse);
      expect(team.standardShortage, 1);
      expect(team.readinessIssues, isNotEmpty);
    });

    test('AI signing aggregates follow committed decisions', () {
      final partial = _applyDecisions(completed, 7);
      final partialReport = LeagueReadinessReport.fromCareer(partial);
      expect(partialReport.totalAiRights, 58);
      expect(partialReport.evaluatedAiDecisions, 7);
      expect(partialReport.pendingAiDecisions, 51);
      expect(
        partialReport.aiStandardSignings +
            partialReport.aiTwoWaySignings +
            partialReport.aiDeferredRights,
        7,
      );
      expect(partialReport.aiSigningComplete, isFalse);

      final full = _applyDecisions(completed, 58);
      final fullReport = LeagueReadinessReport.fromCareer(full);
      expect(fullReport.evaluatedAiDecisions, 58);
      expect(fullReport.pendingAiDecisions, 0);
      expect(fullReport.aiSigningComplete, isTrue);
      expect(
        fullReport.aiStandardSignings +
            fullReport.aiTwoWaySignings +
            fullReport.aiDeferredRights,
        58,
      );
      expect(fullReport.aiDeferredRights, greaterThan(0));
      expect(fullReport.aiReadyCount + fullReport.aiNotReadyCount, 29);
      expect(fullReport.aiBelowMinimumCount, greaterThan(0));
      expect(fullReport.aiParticipatingFranchises, 29);
    });

    test('signed and unsigned rookie counts match the ledger and rights', () {
      final full = _applyDecisions(completed, 58);
      final report = LeagueReadinessReport.fromCareer(full);
      for (final row in report.teams) {
        final contracts = full.rookieSigningLedger.contracts.values.where(
          (contract) => contract.teamId == row.teamId,
        );
        expect(row.signedDraftedRookies, contracts.length);
        final unsigned = full.draftExecutionState.draftRights.values.where(
          (right) =>
              right.owningTeamId == row.teamId &&
              !full.rookieSigningLedger.isSigned(right.prospectId),
        );
        expect(row.unsignedDraftedRights, unsigned.length);
      }
    });

    test('total shortage equals the sum of per-team shortages', () {
      final full = _applyDecisions(completed, 58);
      final report = LeagueReadinessReport.fromCareer(full);
      final sum = report.teams.fold<int>(
        0,
        (total, team) => total + team.standardShortage,
      );
      expect(report.totalStandardShortage, sum);
    });
  });
}

GmCareer _completedCareer() {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: _team,
      selectedSituation: FranchiseSituation.playIn,
      seed: _seed,
    ),
  );
  var career = GmCareer.fromSetupResult(setup, id: 't07d-readiness');
  const draft = DraftExecutionService();
  career = draft.startDraft(career);
  while (!career.draftExecutionState.isCompleted) {
    career =
        career.draftExecutionState.isHumanTurn(
          order: career.draftOrder,
          userTeamId: career.userFranchiseId,
        )
        ? draft.makeHumanSelection(
            career: career,
            prospectId: career.draftExecutionState
                .availableProspects(career.draftClass)
                .first
                .id,
          )
        : draft.executeAiSelection(career);
  }
  return career;
}

GmCareer _applyDecisions(GmCareer career, int count) {
  const service = RookieAiSigningService();
  var current = service.initialize(career);
  for (var i = 0; i < count; i++) {
    current = service.applyNextDecision(current);
  }
  return current;
}

GmCareer _expandTeam(
  GmCareer career,
  TeamId teamId, {
  int standard = 0,
  int twoWay = 0,
}) {
  final team = career.league.teams.firstWhere(
    (candidate) => candidate.id == teamId,
  );
  var roster = team.roster;
  final added = <Player>[];
  void add(int count, RosterCategory category, String prefix) {
    for (var i = 0; i < count; i++) {
      final player = Player(
        id: PlayerId('$prefix-${teamId.value}-$i'),
        firstName: 'Added',
        lastName: '$prefix$i',
        position: Position.sg,
        attributes: PlayerAttributes(
          insideScoring: 50,
          midrange: 50,
          threePoint: 50,
          freeThrow: 50,
          passing: 50,
          ballHandling: 50,
          perimeterDefense: 50,
          interiorDefense: 50,
          rebounding: 50,
          athleticism: 50,
          stamina: 50,
          basketballIQ: 50,
        ),
      );
      added.add(player);
      roster = roster.withPlayer(player, category: category);
    }
  }

  add(standard, RosterCategory.standard, 'std');
  add(twoWay, RosterCategory.twoWay, 'tw');
  final updated = team.copyWith(roster: roster);
  return career.copyWith(
    league: League.create(
      id: career.league.id,
      name: career.league.name,
      config: career.league.config,
      teams: [
        for (final candidate in career.league.teams)
          candidate.id == teamId ? updated : candidate,
      ],
      enforceRosterSize: false,
    ),
    careerProfiles: LeagueCareerProfiles(
      leagueSeed: career.careerProfiles.leagueSeed,
      profiles: {
        ...career.careerProfiles.profiles,
        for (final player in added)
          player.id.value: PlayerCareerProfile(
            playerId: player.id,
            age: 24,
            potential: 60,
            trajectory: DevelopmentTrajectory.steady,
          ),
      },
    ),
  );
}
