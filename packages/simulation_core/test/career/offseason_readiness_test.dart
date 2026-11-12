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
    test(
      'readiness counts approved relief without claiming player acceptance',
      () {
        final career = _clearance.start(_offseason());
        final exception = career.offseasonClearance.capExceptions.firstWhere(
          (item) => item.amount > 0,
        );
        final need = _gate
            .evaluate(career)
            .teams
            .singleWhere((item) => item.teamId == exception.teamId);

        expect(need.capRoom, lessThan(FinancialRules.minimumSalary));
        expect(need.authorizedCapRelief, exception.amount);
        expect(need.financiallyLegalMinimumOffers, greaterThan(0));
        expect(need.willingMinimumOffers, 0);
        expect(need.playerRejectedMinimumOffers, greaterThan(0));
      },
    );
    test('financial illegality does not become player refusal', () {
      final marketCareer = _offseason();
      final authorized = _clearance.start(marketCareer);
      final exception = authorized.offseasonClearance.capExceptions.first;
      final entry = authorized.freeAgentPool.entries.first;
      const evaluator = FreeAgentOfferEvaluator();
      final illegal = evaluator.evaluate(
        career: marketCareer,
        teamId: exception.teamId,
        freeAgentId: entry.id,
        category: RosterCategory.standard,
        durationYears: 1,
        agreedFirstYearSalary: FinancialRules.minimumSalary,
        clearanceOffer: true,
      );
      final willingness = evaluator.evaluateWillingness(
        career: marketCareer,
        teamId: exception.teamId,
        freeAgentId: entry.id,
        category: RosterCategory.standard,
        durationYears: 1,
        salary: FinancialRules.minimumSalary,
      );

      expect(illegal.status, FreeAgentOfferStatus.financiallyIllegal);
      expect(illegal.reasonCode, 'capBreach');
      expect(willingness.accepts, isFalse);
      expect(willingness.reasonCode, isNot('capBreach'));
    });

    test('forged exception amount fails career validation', () {
      final career = _clearance.start(_offseason());
      final original = career.offseasonClearance.capExceptions.first;
      final forged = CapException(
        teamId: original.teamId,
        amount: original.amount == 1 ? 2 : original.amount - 1,
        missingPlayers: original.missingPlayers,
        reason: original.reason,
      );
      final altered = career.offseasonClearance.copyWith(
        capExceptions: [forged],
      );

      expect(
        () => career.copyWith(offseasonClearance: altered),
        throwsFormatException,
      );
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

    test(
      'clearance resume after persisted step does not replay acquisitions',
      () {
        var sealed = _clearance.start(_offseason());
        final entry = sealed.freeAgentPool.entries.first;
        sealed = _clearance.stageHumanOffer(
          career: sealed,
          teamId: sealed.userFranchiseId,
          playerId: entry.id,
          durationYears: 1,
          firstYearSalary: _value
              .estimate(entry.toPublicView())
              .acceptableMaximum,
        );
        sealed = _clearance.prepare(sealed);

        var uninterrupted = sealed;
        while (uninterrupted.offseasonClearance.isResolvable) {
          uninterrupted = _clearance.resolveNext(uninterrupted);
        }

        var resumed = GmCareerCodec.decode(
          GmCareerCodec.encode(_clearance.resolveNext(sealed)),
        );
        while (resumed.offseasonClearance.isResolvable) {
          resumed = _clearance.resolveNext(resumed);
        }

        expect(
          GmCareerCodec.encode(resumed),
          GmCareerCodec.encode(uninterrupted),
        );
        final acquisitions = resumed.freeAgentPool.acquisitions.entries.values;
        expect(
          acquisitions.map((item) => item.playerId).toSet().length,
          acquisitions.length,
        );
        expect(
          resumed.offseasonClearance.outcomes
              .map((item) => item.playerId)
              .toSet()
              .length,
          resumed.offseasonClearance.outcomes.length,
        );
      },
    );

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
