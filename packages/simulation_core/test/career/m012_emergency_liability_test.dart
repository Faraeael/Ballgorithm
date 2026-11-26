import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import '../support/career_season_fixtures.dart';

const _user = TeamId('team-1');

GmCareer _settle(GmCareer c) {
  const market = FreeAgentMarketService();
  const clearance = OffseasonClearanceService();
  const hardship = HardshipSettlementService();
  for (var round = 0; round < 2; round++) {
    c = market.prepareResolution(market.startRound(c));
    while (c.freeAgentMarket.isResolvable) {
      c = market.resolveNext(c);
    }
  }
  c = clearance.prepare(clearance.start(c));
  while (c.offseasonClearance.isResolvable) {
    c = clearance.resolveNext(c);
  }
  c = hardship.prepare(c, humanParticipationConfirmed: true);
  while (c.hardshipSettlement.isResolvable) {
    c = hardship.resolveNext(c);
  }
  return c;
}

/// Year-2 draft in which the human franchise leaves its rookies unsigned.
GmCareer _draftWithoutHumanSignings(GmCareer c) {
  const draft = DraftExecutionService();
  const ai = RookieAiSigningService();
  c = draft.startDraft(c);
  while (!c.draftExecutionState.isCompleted) {
    if (c.draftExecutionState.isHumanTurn(
      order: c.draftOrder,
      userTeamId: c.userFranchiseId,
    )) {
      final pick = c.draftClass.prospects.firstWhere(
        (p) => !c.draftExecutionState.draftRights.containsKey(p.id.value),
      );
      c = draft.makeHumanSelection(career: c, prospectId: pick.id);
    } else {
      c = draft.executeAiSelection(c);
    }
  }
  c = ai.initialize(c);
  while (ai.pendingRights(c).isNotEmpty) {
    c = ai.applyNextDecision(c);
  }
  return c;
}

/// Adds real guaranteed-liability records to the authoritative finances.
GmCareer _withLiabilities(GmCareer c, List<GuaranteedLiability> added) {
  final f = c.finances;
  return c.copyWith(
    finances: CareerFinances(
      contracts: f.contracts.values,
      schedules: f.schedules.values,
      teamFinances: f.teamFinances.values,
      staffCommitments: f.staffCommitments.values,
      facilities: f.facilities.values,
      guaranteedLiabilities: [...f.guaranteedLiabilities.values, ...added],
      debtByTeam: f.debtByTeam,
    ),
  );
}

GuaranteedLiability _liability(
  String key,
  RosterCategory category,
  int salary,
) => GuaranteedLiability(
  id: GuaranteedLiability.idFor('contract-retired-$key-1'),
  originalContractId: 'contract-retired-$key-1',
  playerId: PlayerId('retired-$key'),
  teamId: _user,
  originalCategory: category,
  retirementYear: 1,
  salariesByYear: {2: salary},
);

void main() {
  late GmCareer yearTwo;

  setUpAll(() {
    var c = _settle(preFreeAgencyOffseason(seed: 271828182));
    final plan = const EmergencyRosterService().preview(c);
    c = const EmergencyRosterService().execute(c, plan, humanApproved: true);
    c = completeSeason(
      scheduledSeason(const OffseasonClearanceService().markCleared(c)),
    );
    yearTwo = const SeasonRolloverService()
        .prepareArchiveAndRollover(current: c)
        .rolloverResult
        .nextCareer;
    expect(yearTwo.currentYear, 2);
  });

  test(
    'guaranteed liabilities count once and authorize only emergency salary',
    () {
      final standard = _liability('cap', RosterCategory.standard, 450);
      final twoWay = _liability('cash', RosterCategory.twoWay, 250);
      var c = _withLiabilities(yearTwo, [standard, twoWay]);
      expect(c.finances.guaranteedLiabilityCapFor(_user, 2), 450);
      expect(c.finances.guaranteedLiabilityCashFor(_user, 2), 700);
      c = _settle(_draftWithoutHumanSignings(c));

      const service = EmergencyRosterService();
      final plan = service.preview(c);
      final userOffers = plan.offers.where((o) => o.teamId == _user).toList();
      final projection = plan.teams.firstWhere((t) => t.teamId == _user);
      print(
        'LIABILITY_FIXTURE status=${plan.status} '
        'standardBefore=${projection.standardBefore} '
        'payrollBefore=${projection.payrollBefore} '
        'cashBefore=${projection.cashBefore} '
        'offers=${userOffers.map((o) => '${o.playerId.value}:${o.salary}:${o.relief}').toList()}',
      );
      expect(userOffers, isNotEmpty);

      // Payroll and cash include each liability exactly once.
      expect(
        projection.payrollBefore,
        c.finances.activeStandardPayrollFor(_user, 2) + 450,
      );
      expect(projection.payrollBefore, c.finances.capPayrollFor(_user, 2));
      expect(
        projection.cashBefore,
        c.finances.projectedEndOfSeasonCash(_user, 2) -
            c.finances.debtFor(_user),
      );

      // Emergency signings stop at the mandatory roster: no expansion.
      expect(
        userOffers.length,
        (14 - projection.standardBefore).clamp(0, 15) +
            projection.missingPositionsBefore.length,
      );

      final settled = service.execute(c, plan, humanApproved: true);
      final receipt = settled.emergencySettlement!.teams.firstWhere(
        (t) => t.teamId == _user,
      );
      final salary = userOffers.fold<int>(0, (s, o) => s + o.salary);
      final relief = userOffers.fold<int>(0, (s, o) => s + o.relief);
      expect(receipt.payrollBefore, projection.payrollBefore);
      expect(
        settled.finances.capPayrollFor(_user, 2),
        receipt.payrollBefore + salary,
      );
      // Relief never exceeds the emergency salaries themselves, so it cannot
      // cover the pre-existing liability.
      expect(relief, lessThanOrEqualTo(salary));
      expect(
        settled.finances.capPayrollFor(_user, 2),
        lessThanOrEqualTo(receipt.startingLimit + relief),
      );
      final team = settled.league.teams.firstWhere((t) => t.id == _user);
      expect(team.roster.standardCount, 14);
      expect(Position.values.every(team.roster.covers), isTrue);

      // Save/reload is exact; extra relief that would pay for the liability
      // is rejected.
      final encoded = GmCareerCodec.encode(settled);
      expect(GmCareerCodec.encode(GmCareerCodec.decode(encoded)), encoded);
      final raw = jsonDecode(encoded) as Map<String, dynamic>;
      final offers =
          (raw['emergencySettlement'] as Map<String, dynamic>)['offers']
              as List;
      final userOffer =
          offers.firstWhere((o) => (o as Map)['teamId'] == _user.value)
              as Map<String, dynamic>;
      userOffer['relief'] = (userOffer['relief'] as int) + 450;
      expect(
        () => GmCareerCodec.decode(jsonEncode(raw)),
        throwsFormatException,
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'cash-only liabilities that exhaust cash block emergency signing',
    () {
      // Each record is within the 8,000 CU salary bound; together they leave
      // less cash than one minimum emergency salary.
      var c = _withLiabilities(yearTwo, [
        for (var i = 0; i < 8; i++)
          _liability('cash$i', RosterCategory.twoWay, 8000),
      ]);
      expect(c.finances.guaranteedLiabilityCapFor(_user, 2), 0);
      c = _settle(_draftWithoutHumanSignings(c));
      final cash =
          c.finances.projectedEndOfSeasonCash(_user, 2) -
          c.finances.debtFor(_user);
      expect(cash, lessThan(FinancialRules.minimumSalary));
      final plan = const EmergencyRosterService().preview(c);
      print('LIABILITY_CASH status=${plan.status} cash=$cash');
      expect(plan.offers.where((o) => o.teamId == _user), isEmpty);
      expect(plan.status, EmergencyPlanStatus.noSolution);
      expect(
        () => const EmergencyRosterService().execute(
          c,
          plan,
          humanApproved: true,
        ),
        throwsStateError,
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
