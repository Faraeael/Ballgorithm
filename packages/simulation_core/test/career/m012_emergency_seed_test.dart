import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import '../support/career_season_fixtures.dart';

void main() {
  for (final seed in [161137785, 271828182]) {
    test(
      'seed $seed completes emergency recovery and enters season',
      () {
        var career = preFreeAgencyOffseason(seed: seed);
        const market = FreeAgentMarketService();
        const clearance = OffseasonClearanceService();
        const hardship = HardshipSettlementService();
        for (var round = 0; round < 2; round++) {
          career = market.prepareResolution(market.startRound(career));
          while (career.freeAgentMarket.isResolvable) {
            career = market.resolveNext(career);
          }
        }
        career = clearance.prepare(clearance.start(career));
        while (career.offseasonClearance.isResolvable) {
          career = clearance.resolveNext(career);
        }
        career = hardship.prepare(career, humanParticipationConfirmed: true);
        while (career.hardshipSettlement.isResolvable) {
          career = hardship.resolveNext(career);
        }
        const service = EmergencyRosterService();
        final plan = service.preview(career);
        final truncated = const EmergencyRosterService(
          maxSearchStates: 1,
        ).preview(career);
        expect(truncated.status, EmergencyPlanStatus.inconclusive);
        expect(truncated.offers, isEmpty);
        expect(
          service.preview(career).offers.map((offer) => offer.offerId),
          plan.offers.map((offer) => offer.offerId),
        );
        expect(plan.offers, isNotEmpty);
        final next = service.execute(career, plan, humanApproved: true);
        final expectedTeam = seed == 161137785 ? 'team-19' : 'team-4';
        final expectedSalary = seed == 161137785 ? 1130 : 1170;
        final offer = next.emergencySettlement!.offers.single;
        final evidence = next.emergencySettlement!.teams.single;
        expect(offer.teamId.value, expectedTeam);
        expect(offer.salary, expectedSalary);
        expect(offer.relief, expectedSalary);
        expect(
          evidence.payrollBefore,
          lessThanOrEqualTo(evidence.startingLimit),
        );
        expect(
          evidence.payrollBefore + offer.salary,
          lessThanOrEqualTo(evidence.startingLimit + offer.relief),
        );
        expect(evidence.standardBefore, 13);
        expect(
          next.freeAgentPool.acquisitions.entries[offer.transactionId]!.origin,
          AcquisitionOrigin.emergency,
        );
        print(
          'EMERGENCY_SEED seed=$seed team=$expectedTeam '
          'player=${offer.playerId.value} salary=${offer.salary} '
          'relief=${offer.relief} payrollBefore=${evidence.payrollBefore} '
          'ordinary=${evidence.ordinaryRelief} '
          'hardship=${evidence.hardshipRelief} '
          'grandfathered=${evidence.grandfathered} '
          'limit=${evidence.startingLimit} cashBefore=${evidence.cashBefore}',
        );
        final raw =
            jsonDecode(GmCareerCodec.encode(next)) as Map<String, dynamic>;
        final receipt = raw['emergencySettlement'] as Map<String, dynamic>;
        receipt['unexpected'] = true;
        expect(
          () => GmCareerCodec.decode(jsonEncode(raw)),
          throwsFormatException,
        );
        receipt.remove('unexpected');
        final teams = receipt['teams'] as List<dynamic>;
        (teams.first as Map<String, dynamic>)['payrollBefore'] = 0;
        expect(
          () => GmCareerCodec.decode(jsonEncode(raw)),
          throwsFormatException,
        );
        career = GmCareerCodec.decode(GmCareerCodec.encode(next));
        expect(const OffseasonReadinessGate().evaluate(career).readyCount, 30);
        career = clearance.markCleared(career);
        career = const RegularSeasonEntryService().start(career);
        career = const RegularSeasonScheduleService().generate(career);
        final schedule = career.regularSeasonState!.schedule!;
        expect(schedule.rounds, hasLength(82));
        expect(
          schedule.rounds.fold<int>(0, (sum, r) => sum + r.fixtures.length),
          1230,
        );
        if (seed == 271828182) {
          final completed = completeSeason(career);
          final rolled = const SeasonRolloverService()
              .prepareArchiveAndRollover(current: completed)
              .rolloverResult
              .nextCareer;
          final reloaded = GmCareerCodec.decode(GmCareerCodec.encode(rolled));
          expect(reloaded.emergencySettlement, isNull);
          final expired = reloaded.finances.contractForPlayer(
            plan.offers.single.playerId,
          );
          expect(
            expired == null ||
                expired.id !=
                    PlayerContract.idFor(plan.offers.single.playerId, 1),
            isTrue,
          );
          final revived =
              jsonDecode(GmCareerCodec.encode(reloaded))
                  as Map<String, dynamic>;
          revived['emergencySettlement'] =
              (revived['marketHistory'] as List).single['emergencySettlement'];
          expect(
            () => GmCareerCodec.decode(jsonEncode(revived)),
            throwsFormatException,
          );
          final forgedHistory =
              jsonDecode(GmCareerCodec.encode(reloaded))
                  as Map<String, dynamic>;
          (((forgedHistory['marketHistory'] as List).single
                          as Map<String, dynamic>)['emergencySettlement']
                      as Map<String, dynamic>)['teams']
                  .single['ordinaryRelief'] =
              evidence.ordinaryRelief + 100;
          expect(
            () => GmCareerCodec.decode(jsonEncode(forgedHistory)),
            throwsFormatException,
          );
          expect(
            reloaded
                .marketHistory
                .single
                .emergencySettlement!
                .offers
                .single
                .playerId,
            plan.offers.single.playerId,
          );
          final corrupted =
              jsonDecode(GmCareerCodec.encode(reloaded))
                  as Map<String, dynamic>;
          final history = corrupted['marketHistory'] as List<dynamic>;
          (history.single as Map<String, dynamic>)['emergencySettlement'] =
              null;
          expect(
            () => GmCareerCodec.decode(jsonEncode(corrupted)),
            throwsFormatException,
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
