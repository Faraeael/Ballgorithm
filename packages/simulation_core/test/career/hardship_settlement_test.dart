import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _seed = 1604126146;
const _situation = FranchiseSituation.tanking;
const _draft = DraftExecutionService();
const _rookies = RookieAiSigningService();
const _market = FreeAgentMarketService();
const _clearance = OffseasonClearanceService();
const _hardship = HardshipSettlementService();
const _gate = OffseasonReadinessGate();

GmCareer _careerBeforeHardship({
  TeamId selectedTeamId = const TeamId('team-1'),
}) {
  var career = GmCareer.fromSetupResult(
    const CareerSetupService().generate(
      CareerSetupRequest(
        selectedTeamId: selectedTeamId,
        selectedSituation: _situation,
        seed: _seed,
      ),
    ),
    id: 't08h-p2-hardship-test',
  );
  career = _draft.startDraft(career);
  while (!career.draftExecutionState.isCompleted) {
    career =
        career.draftExecutionState.isHumanTurn(
          order: career.draftOrder,
          userTeamId: career.userFranchiseId,
        )
        ? _draft.makeHumanSelection(
            career: career,
            prospectId: career.draftExecutionState
                .availableProspects(career.draftClass)
                .first
                .id,
          )
        : _draft.executeAiSelection(career);
  }
  career = _rookies.initialize(career);
  while (_rookies.pendingRights(career).isNotEmpty) {
    career = _rookies.applyNextDecision(career);
  }
  for (var round = 0; round < 2; round++) {
    career = _market.startRound(career);
    career = _market.prepareResolution(career);
    while (career.freeAgentMarket.isResolvable) {
      career = _market.resolveNext(career);
    }
  }
  career = _clearance.start(career);
  career = _clearance.prepare(career);
  while (career.offseasonClearance.isResolvable) {
    career = _clearance.resolveNext(career);
  }
  return career;
}

GmCareer _resolveAll(GmCareer career) {
  var current = career;
  while (current.hardshipSettlement.isResolvable) {
    current = _hardship.resolveNext(current);
  }
  return current;
}

void main() {
  late GmCareer beforeHardship;
  late GmCareer prepared;

  setUpAll(() {
    beforeHardship = _careerBeforeHardship();
    prepared = _hardship.prepare(
      beforeHardship,
      humanParticipationConfirmed: false,
    );
  });

  group('T08H-P2 bounded hardship settlement', () {
    test('authority is exact, team-bound, and capped at 1,000 CU', () {
      expect(FinancialRules.salaryCap, 41000);
      expect(prepared.hardshipSettlement.offers, isNotEmpty);
      expect(prepared.hardshipSettlement.humanParticipationConfirmed, isFalse);
      expect(
        prepared.hardshipSettlement.authorizations.any(
          (authority) => authority.teamId == prepared.userFranchiseId,
        ),
        isFalse,
      );
      for (final authority in prepared.hardshipSettlement.authorizations) {
        expect(
          authority.existingOrdinaryRelief + authority.additionalAmount,
          lessThanOrEqualTo(1000),
        );
        expect(authority.maximumCombinedOverage, 1000);
        expect(authority.reason, hardshipAuthorizationReason);
        expect(authority.authorizedOfferIds, isNotEmpty);
        final teamOffers = prepared.hardshipSettlement.offers
            .where((offer) => offer.teamId == authority.teamId)
            .toList();
        final firstYearTotal = teamOffers.fold<int>(
          0,
          (sum, offer) => sum + offer.firstYearSalary,
        );
        final payroll = prepared.finances.capPayrollFor(
          authority.teamId,
          prepared.currentYear,
        );
        final overage = payroll + firstYearTotal - FinancialRules.salaryCap;
        final requiredAdditional = overage > authority.existingOrdinaryRelief
            ? overage - authority.existingOrdinaryRelief
            : 0;
        expect(teamOffers, isNotEmpty);
        expect(authority.additionalAmount, requiredAdditional);
        expect(requiredAdditional, greaterThan(0));
        expect(teamOffers.length, lessThanOrEqualTo(authority.missingPlayers));
      }
      prepared.validate();
    });
    test('human participation confirmation is persisted before resolution', () {
      final declined = _hardship.prepare(
        beforeHardship,
        humanParticipationConfirmed: false,
      );
      expect(declined.hardshipSettlement.humanParticipationConfirmed, isFalse);
      expect(
        declined.hardshipSettlement.offers.any(
          (offer) => offer.teamId == beforeHardship.userFranchiseId,
        ),
        isFalse,
      );
      final approved = _hardship.prepare(
        beforeHardship,
        humanParticipationConfirmed: true,
      );
      expect(approved.hardshipSettlement.humanParticipationConfirmed, isTrue);
    });

    test(
      'offers use player acceptance; active transactions are financially legal',
      () {
        final evaluator = const FreeAgentOfferEvaluator();
        final before = GmCareerCodec.encode(prepared);
        for (final offer in prepared.hardshipSettlement.offers) {
          final willingness = evaluator.evaluateWillingness(
            career: prepared,
            teamId: offer.teamId,
            freeAgentId: offer.playerId,
            category: RosterCategory.standard,
            durationYears: offer.durationYears,
            salary: offer.firstYearSalary,
          );
          expect(willingness.accepts, isTrue);
          expect(offer.firstYearSalary, greaterThanOrEqualTo(400));
          expect(
            offer.salarySchedule.every((salary) => salary <= 8000),
            isTrue,
          );
        }
        expect(GmCareerCodec.encode(prepared), before);

        var current = prepared;
        while (current.hardshipSettlement.isResolvable) {
          final playerId = current
              .hardshipSettlement
              .resolutionOrder[current.hardshipSettlement.nextResolutionIndex];
          for (final offer in current.hardshipSettlement.offersFor(playerId)) {
            final decision = evaluator.evaluate(
              career: current,
              teamId: offer.teamId,
              freeAgentId: offer.playerId,
              category: RosterCategory.standard,
              durationYears: offer.durationYears,
              agreedFirstYearSalary: offer.firstYearSalary,
              hardshipOfferId: offer.offerId,
            );
            final team = current.league.teams.firstWhere(
              (item) => item.id == offer.teamId,
            );
            if (team.roster.standardCount < 14) {
              expect(
                decision.isFinanciallyLegal,
                isTrue,
                reason: decision.reasonCode,
              );
              expect(decision.isAcceptable, isTrue);
            }
          }
          current = _hardship.resolveNext(current);
        }
      },
    );
    test('generic acquisitions cannot spend hardship relief', () {
      final offer = prepared.hardshipSettlement.offers.first;
      final service = const FreeAgentAcquisitionService();
      final before = GmCareerCodec.encode(prepared);
      expect(
        () => service.acquire(
          career: prepared,
          teamId: offer.teamId,
          freeAgentId: offer.playerId,
          category: RosterCategory.standard,
          durationYears: offer.durationYears,
          agreedFirstYearSalary: offer.firstYearSalary,
          origin: AcquisitionOrigin.hardship,
        ),
        throwsA(isA<DomainValidationException>()),
      );
      expect(
        () => service.acquire(
          career: prepared,
          teamId: offer.teamId,
          freeAgentId: offer.playerId,
          category: RosterCategory.standard,
          durationYears: offer.durationYears,
          agreedFirstYearSalary: offer.firstYearSalary,
          origin: AcquisitionOrigin.initialPool,
          hardshipOfferId: offer.offerId,
          hardshipSettlementAfterAcquisition: prepared.hardshipSettlement,
          freeAgentOffersAfterAcquisition: prepared.freeAgentOffers,
        ),
        throwsA(isA<DomainValidationException>()),
      );
      expect(GmCareerCodec.encode(prepared), before);
    });

    test(
      'competitive resolution is deterministic and never duplicates ownership',
      () {
        final first = _resolveAll(prepared);
        final second = _resolveAll(prepared);
        expect(GmCareerCodec.encode(first), GmCareerCodec.encode(second));
        expect(first.phase, CareerPhase.openingOffseason);
        expect(first.currentYear, 1);
        expect(
          first.hardshipSettlement.status,
          HardshipSettlementStatus.complete,
        );
        final acquisitions = first.freeAgentPool.acquisitions.entries.values
            .where((record) => record.origin == AcquisitionOrigin.hardship)
            .toList();
        expect(acquisitions, isNotEmpty);
        expect(
          acquisitions.map((record) => record.playerId).toSet().length,
          acquisitions.length,
        );
        final results = first.hardshipSettlement.outcomes
            .expand((outcome) => outcome.results)
            .toList();
        for (final acquisition in acquisitions) {
          final offer = first.hardshipSettlement.offers.firstWhere(
            (item) =>
                item.teamId == acquisition.teamId &&
                item.playerId == acquisition.playerId,
          );
          final contract = first.finances.contractForPlayer(
            acquisition.playerId,
          )!;
          final schedule = first.finances.schedules[contract.id]!;
          expect(contract.teamId, acquisition.teamId);
          expect(contract.durationYears, offer.durationYears);
          expect(contract.source, ContractSource.freeAgent);
          expect(schedule.annualSalaries, offer.salarySchedule);
          expect(schedule.annualSalaries.first, offer.firstYearSalary);
          expect(
            schedule.annualSalaries.skip(1).fold<int>(0, (a, b) => a + b),
            offer.salarySchedule.skip(1).fold<int>(0, (a, b) => a + b),
          );
        }
        for (final team in first.league.teams) {
          expect(team.roster.standardCount, lessThanOrEqualTo(14));
        }
        expect(
          results.where(
            (result) => result.outcome == FreeAgentMarketOfferOutcome.accepted,
          ),
          hasLength(acquisitions.length),
        );
        for (final authorization in first.hardshipSettlement.authorizations) {
          expect(
            authorization.usedAmount,
            lessThanOrEqualTo(authorization.additionalAmount),
          );
          expect(
            authorization.existingOrdinaryRelief + authorization.usedAmount,
            lessThanOrEqualTo(1000),
          );
        }
        first.validate();
      },
    );

    test(
      'prepared settlement blocks readiness and consumed settlement stays gated',
      () {
        expect(
          _gate.evaluate(prepared).status,
          isNot(OffseasonReadinessStatus.readyForConfirmation),
        );
        final resolved = _resolveAll(prepared);
        final readiness = _gate.evaluate(resolved);
        expect(
          readiness.status,
          isNot(OffseasonReadinessStatus.readyForConfirmation),
        );
        expect(readiness.readyCount, lessThan(30));
        expect(resolved.phase, CareerPhase.openingOffseason);
      },
    );

    test('tampered authority and schema migration boundaries fail safely', () {
      final authority = prepared.hardshipSettlement.authorizations.first;
      expect(
        () => HardshipAuthorization(
          authorizationId: authority.authorizationId,
          teamId: authority.teamId,
          seasonYear: authority.seasonYear,
          additionalAmount: 1001,
          existingOrdinaryRelief: authority.existingOrdinaryRelief,
          maximumCombinedOverage: 1000,
          missingPlayers: authority.missingPlayers,
          authorizedOfferIds: authority.authorizedOfferIds,
          reason: authority.reason,
          status: HardshipAuthorizationStatus.unused,
          usedAmount: 0,
          transactionIds: const [],
        ),
        throwsA(isA<DomainValidationException>()),
      );

      final legacy =
          jsonDecode(GmCareerCodec.encode(beforeHardship))
                as Map<String, dynamic>
            ..['schemaVersion'] = 13
            ..remove('hardshipSettlement');
      final migrated = GmCareerCodec.decode(jsonEncode(legacy));
      expect(migrated.schemaVersion, 14);
      expect(
        migrated.hardshipSettlement.status,
        HardshipSettlementStatus.notStarted,
      );
      expect(
        migrated.freeAgentPool.toJson(),
        beforeHardship.freeAgentPool.toJson(),
      );
      expect(migrated.finances.toJson(), beforeHardship.finances.toJson());
      final nativeV14 =
          jsonDecode(GmCareerCodec.encode(beforeHardship))
                as Map<String, dynamic>
            ..remove('hardshipSettlement');
      expect(
        () => GmCareerCodec.decode(jsonEncode(nativeV14)),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
