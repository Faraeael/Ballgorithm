import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _seed = 20261028;
const _market = FreeAgentMarketService();
const _clearance = OffseasonClearanceService();
const _gate = OffseasonReadinessGate();
const _value = FreeAgentMarketValueService();

GmCareer _base() => GmCareer.fromSetupResult(
  const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: _seed,
    ),
  ),
  id: 't08h-readiness',
);

GmCareer _draft(GmCareer career) {
  const draft = DraftExecutionService();
  var current = draft.startDraft(career);
  while (!current.draftExecutionState.isCompleted) {
    current =
        current.draftExecutionState.isHumanTurn(
          order: current.draftOrder,
          userTeamId: current.userFranchiseId,
        )
        ? draft.makeHumanSelection(
            career: current,
            prospectId: current.draftExecutionState
                .availableProspects(current.draftClass)
                .first
                .id,
          )
        : draft.executeAiSelection(current);
  }
  return current;
}

GmCareer _aiRookies(GmCareer career) {
  const service = RookieAiSigningService();
  var current = service.initialize(career);
  while (service.pendingRights(current).isNotEmpty) {
    current = service.applyNextDecision(current);
  }
  return current;
}

GmCareer _marketRounds(GmCareer career) {
  var current = _market.startRound(career);
  current = _market.prepareResolution(current);
  while (current.freeAgentMarket.isResolvable) {
    current = _market.resolveNext(current);
  }
  current = _market.startRound(current);
  current = _market.prepareResolution(current);
  while (current.freeAgentMarket.isResolvable) {
    current = _market.resolveNext(current);
  }
  return current;
}

GmCareer _offseason() => _marketRounds(_aiRookies(_draft(_base())));

void main() {
  group('T08H offseason readiness', () {
    test('fresh career is in progress, not ready', () {
      final result = _gate.evaluate(_base());
      expect(result.status, OffseasonReadinessStatus.offseasonInProgress);
      expect(result.reasons, contains('Rookie draft is not complete'));
    });

    test('market-complete career reports precise shortage status', () {
      final career = _offseason();
      final result = _gate.evaluate(career);
      expect(
        result.status,
        anyOf(
          OffseasonReadinessStatus.clearanceRequired,
          OffseasonReadinessStatus.financialExceptionRequired,
        ),
      );
      expect(result.belowMinimumCount, greaterThan(0));
      expect(result.totalShortage, greaterThan(0));
      expect(result.teams, isNotEmpty);
    });

    test('clearance start grants exact bounded exceptions', () {
      final career = _clearance.start(_offseason());
      expect(
        career.offseasonClearance.status,
        OffseasonClearanceStatus.collectingHumanOffers,
      );
      for (final exception in career.offseasonClearance.capExceptions) {
        expect(exception.amount, inInclusiveRange(1, 800));
        expect(exception.missingPlayers, inInclusiveRange(1, 2));
        expect(
          exception.amount,
          lessThanOrEqualTo(400 * exception.missingPlayers),
        );
        final team = career.finances.financesFor(exception.teamId);
        expect(team.capException, exception.amount);
        final roster = career.league.teams.firstWhere(
          (candidate) => candidate.id == exception.teamId,
        );
        expect(roster.roster.standardCount, inInclusiveRange(12, 13));
      }
    });

    test('human clearance offer can fill a missing standard spot', () {
      var career = _clearance.start(_offseason());
      final human = career.userTeam;
      final need =
          RosterRules.minRegularSeasonStandard - human.roster.standardCount;
      if (need <= 0) return;
      final entry = career.freeAgentPool.entries.first;
      final salary = _value.estimate(entry.toPublicView()).acceptableMaximum;
      career = _clearance.stageHumanOffer(
        career: career,
        teamId: career.userFranchiseId,
        playerId: entry.id,
        durationYears: 1,
        firstYearSalary: salary,
      );
      career = _clearance.prepare(career);
      while (career.offseasonClearance.isResolvable) {
        career = _clearance.resolveNext(career);
      }
      expect(career.offseasonClearance.isComplete, isTrue);
      expect(
        career.userTeam.roster.standardCount,
        greaterThanOrEqualTo(human.roster.standardCount),
      );
    });

    test('mark cleared is blocked while any team is short', () {
      var career = _clearance.start(_offseason());
      career = _clearance.prepare(career);
      while (career.offseasonClearance.isResolvable) {
        career = _clearance.resolveNext(career);
      }
      final result = _gate.evaluate(career);
      if (result.status == OffseasonReadinessStatus.readyForConfirmation) {
        return;
      }
      expect(
        () => _clearance.markCleared(career),
        throwsA(isA<DomainValidationException>()),
      );
    });

    test('v12 migrates to v13 with empty clearance; v13 is strict', () {
      final base =
          jsonDecode(GmCareerCodec.encode(_base())) as Map<String, dynamic>;
      final v12 = Map<String, dynamic>.from(base)
        ..['schemaVersion'] = 12
        ..remove('offseasonClearance');
      final migrated = GmCareerCodec.decode(jsonEncode(v12));
      expect(migrated.schemaVersion, 13);
      expect(
        migrated.offseasonClearance.status,
        OffseasonClearanceStatus.notStarted,
      );
      final missing = Map<String, dynamic>.from(base)
        ..remove('offseasonClearance');
      expect(
        () => GmCareerCodec.decode(jsonEncode(missing)),
        throwsFormatException,
      );
    });
  });
}
