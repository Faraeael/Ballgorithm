import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

GmCareer _buildYear2CareerForClearance({
  required bool triggerCapException,
  int seed = 20261125,
}) {
  final setup = const CareerSetupService().generate(
    CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: seed,
    ),
  );
  var y1 = GmCareer.fromSetupResult(setup, id: 'career-c2c2a-$seed');
  const draftService = DraftExecutionService();
  const signingService = RookieSigningService();
  const aiSigningService = RookieAiSigningService();

  y1 = draftService.startDraft(y1);
  while (!y1.draftExecutionState.isCompleted) {
    if (y1.draftExecutionState.isHumanTurn(
      order: y1.draftOrder,
      userTeamId: y1.userFranchiseId,
    )) {
      final pick = y1.draftClass.prospects.firstWhere(
        (p) => !y1.draftExecutionState.draftRights.containsKey(p.id.value),
      );
      y1 = draftService.makeHumanSelection(career: y1, prospectId: pick.id);
    } else {
      y1 = draftService.executeAiSelection(y1);
    }
  }
  y1 = aiSigningService.initialize(y1);
  while (aiSigningService.pendingRights(y1).isNotEmpty) {
    y1 = aiSigningService.applyNextDecision(y1);
  }
  for (final r in y1.unsignedDraftRights) {
    if (r.owningTeamId == y1.userFranchiseId) {
      y1 = signingService.signDraftedRookie(
        career: y1,
        teamId: y1.userFranchiseId,
        prospectId: r.prospectId,
        category: RosterCategory.standard,
        durationYears: 2,
      );
    }
  }

  final targetTeam = y1.league.teams.firstWhere(
    (t) => t.id != y1.userFranchiseId,
  );
  final debtTeam = y1.league.teams.last;

  final y2League = y1.league;
  final bootstrapped = FinancialMigration.bootstrapFromCareerState(
    league: y2League,
    careerProfiles: y1.careerProfiles,
    rookieSigningLedger: RookieSigningLedger.empty(),
    currentYear: 2,
  );

  final contracts = bootstrapped.contracts;
  final schedules = Map<String, ContractFinancials>.from(
    bootstrapped.schedules,
  );
  if (triggerCapException) {
    // Pick a non-debt team with 12 standard legacy players and set its
    // legacy salaries to valid bootstrap tiers totaling 40,800 CU (200 CU room
    // for 2 missing standard players -> deterministic 600 CU CapException).
    final capExceptionTeam = y2League.teams.firstWhere(
      (t) =>
          t.id != debtTeam.id &&
          t.id != targetTeam.id &&
          t.roster.standardCount == 12 &&
          schedules.values
              .where(
                (s) =>
                    s.teamId == t.id &&
                    contracts[s.contractId]?.category ==
                        RosterCategory.standard,
              )
              .every(
                (s) => contracts[s.contractId]?.source == ContractSource.legacy,
              ),
    );
    final stdSchedules = schedules.values
        .where(
          (s) =>
              s.teamId == capExceptionTeam.id &&
              contracts[s.contractId]?.category == RosterCategory.standard,
        )
        .toList();
    const bootstrap40800 = [
      4100,
      4100,
      4100,
      4100,
      4100,
      4100,
      3300,
      3300,
      3300,
      3300,
      2600,
      400,
    ];
    for (var i = 0; i < stdSchedules.length; i++) {
      final orig = stdSchedules[i];
      schedules[orig.contractId] = ContractFinancials(
        contractId: orig.contractId,
        playerId: orig.playerId,
        teamId: orig.teamId,
        annualSalaries: FinancialRules.standardSchedule(
          bootstrap40800[i],
          orig.durationYears,
        ),
        guaranteedYears: orig.guaranteedYears,
        source: orig.source,
        signedYear: orig.signedYear,
      );
    }
  }

  final liability = GuaranteedLiability(
    id: GuaranteedLiability.idFor('retired-y1-contract'),
    originalContractId: 'retired-y1-contract',
    playerId: const PlayerId('retired-y1-player'),
    teamId: targetTeam.id,
    originalCategory: RosterCategory.standard,
    retirementYear: 1,
    salariesByYear: const {2: 500, 3: 550},
  );

  final teamFinances = <TeamFinances>[];
  for (final tf in bootstrapped.teamFinances.values) {
    final grandfathered = !triggerCapException;
    final rawPayroll = bootstrapped.capPayrollFor(tf.teamId, 2);
    final gfPayroll = grandfathered
        ? (rawPayroll > FinancialRules.salaryCap
              ? rawPayroll
              : FinancialRules.salaryCap + 100)
        : 0;
    if (tf.teamId == debtTeam.id) {
      teamFinances.add(
        TeamFinances(
          teamId: tf.teamId,
          operatingBudget: tf.operatingBudget,
          cash: 0,
          revenueBaseline: tf.revenueBaseline,
          season: tf.season,
          capGrandfathered: grandfathered,
          grandfatheredPayroll: gfPayroll,
          capException: 0,
        ),
      );
    } else if (tf.teamId == targetTeam.id) {
      teamFinances.add(
        TeamFinances(
          teamId: tf.teamId,
          operatingBudget: FinancialRules.maximumBalance,
          cash: 200000,
          revenueBaseline: 100000,
          season: tf.season,
          capGrandfathered: grandfathered,
          grandfatheredPayroll: gfPayroll,
          capException: 0,
        ),
      );
    } else if (grandfathered) {
      teamFinances.add(
        TeamFinances(
          teamId: tf.teamId,
          operatingBudget: tf.operatingBudget,
          cash: tf.cash,
          revenueBaseline: tf.revenueBaseline,
          season: tf.season,
          capGrandfathered: true,
          grandfatheredPayroll: gfPayroll,
          capException: 0,
        ),
      );
    } else {
      teamFinances.add(tf);
    }
  }

  final y2Finances = CareerFinances(
    contracts: contracts.values,
    schedules: schedules.values,
    teamFinances: teamFinances,
    staffCommitments: bootstrapped.staffCommitments.values,
    facilities: bootstrapped.facilities.values,
    guaranteedLiabilities: [liability],
    debtByTeam: {debtTeam.id.value: 750},
  );

  var y2 = y1.copyWith(
    currentYear: 2,
    phase: CareerPhase.openingOffseason,
    league: y2League,
    draftClass: const DraftGenerator().generateDraftClass(
      league: y2League,
      seed: y1.generationSeed + 2,
      seasonYear: 2,
    ),
    draftExecutionState: DraftExecutionState.initial(),
    rookieSigningLedger: RookieSigningLedger.empty(),
    aiRookieSigning: AiRookieSigningState.empty(),
    freeAgentPool: FreeAgentPool(
      seasonYear: 2,
      entries: y1.freeAgentPool.entries,
    ),
    freeAgentOffers: FreeAgentOfferLedger.empty(),
    freeAgentMarket: FreeAgentMarketState.initial(seasonYear: 2),
    offseasonClearance: OffseasonClearanceState.initial(seasonYear: 2),
    hardshipSettlement: HardshipSettlement.initial(seasonYear: 2),
    finances: y2Finances,
    retiredPlayers: [
      RetiredPlayerRecord(
        playerId: const PlayerId('retired-y1-player'),
        fullName: 'Retired Veteran',
        position: Position.c,
        finalAge: 38,
        retiredAfterYear: 1,
        finalOverall: 75,
      ),
    ],
    seasonSettlements: [
      SeasonSettlementRecord(
        seasonYear: 1,
        settledTeamIds: [for (final t in y2League.teams) t.id]
          ..sort((a, b) => a.value.compareTo(b.value)),
        totalRevenue: 1000000,
        totalExpenses: 900000,
      ),
    ],
  );
  const marketService = FreeAgentMarketService();
  for (var round = 0; round < 2; round++) {
    y2 = marketService.startRound(y2);
    y2 = marketService.prepareResolution(y2);
    while (y2.freeAgentMarket.isResolvable) {
      y2 = marketService.resolveNext(y2);
    }
  }
  return y2;
}

void main() {
  group('M009-T05C-C2-C2A: Offseason Financial Ledger Preservation', () {
    test(
      '1-15: OffseasonClearanceService.start/prepare preserves debtByTeam and guaranteedLiabilities when CapException is assigned',
      () {
        final y2Career = _buildYear2CareerForClearance(
          triggerCapException: true,
        );
        final beforeJson = GmCareerCodec.encode(y2Career);

        const clearance = OffseasonClearanceService();
        final started = clearance.start(y2Career);
        expect(started.offseasonClearance.capExceptions, isNotEmpty);

        final prepared = clearance.prepare(started);

        // 14. Input career unchanged
        expect(GmCareerCodec.encode(y2Career), equals(beforeJson));

        // 1. Debt balances preserved exactly
        expect(
          prepared.finances.debtByTeam,
          equals(y2Career.finances.debtByTeam),
        );

        // 2 & 3. Guaranteed liabilities, identities, and schedules unchanged
        expect(
          prepared.finances.guaranteedLiabilities.length,
          equals(y2Career.finances.guaranteedLiabilities.length),
        );
        for (final entry in y2Career.finances.guaranteedLiabilities.entries) {
          final actual = prepared.finances.guaranteedLiabilities[entry.key]!;
          expect(actual.id, entry.value.id);
          expect(actual.originalContractId, entry.value.originalContractId);
          expect(actual.salariesByYear, equals(entry.value.salariesByYear));
        }

        // 4, 5, 6, 7, 9. Contracts, schedules, staff, facilities unchanged & no duplicates
        expect(
          prepared.finances.contracts.length,
          equals(y2Career.finances.contracts.length),
        );
        expect(
          prepared.finances.schedules.length,
          equals(y2Career.finances.schedules.length),
        );
        expect(
          prepared.finances.staffCommitments.length,
          equals(y2Career.finances.staffCommitments.length),
        );
        expect(
          prepared.finances.facilities.length,
          equals(y2Career.finances.facilities.length),
        );

        // 8. Only authorized cap-exception state changed
        final exceptionTeamIds = {
          for (final e in prepared.offseasonClearance.capExceptions)
            e.teamId.value,
        };
        for (final tid in y2Career.finances.teamFinances.keys) {
          final beforeTf = y2Career.finances.teamFinances[tid]!;
          final afterTf = prepared.finances.teamFinances[tid]!;
          expect(afterTf.cash, beforeTf.cash);
          expect(afterTf.operatingBudget, beforeTf.operatingBudget);
          if (exceptionTeamIds.contains(tid)) {
            expect(afterTf.capException, greaterThan(0));
          } else {
            expect(afterTf.capException, beforeTf.capException);
          }
          // 10. Non-negative balances
          expect(afterTf.cash, greaterThanOrEqualTo(0));
        }

        // 11 & 12. Valid career & codec round-trip preserves both ledgers
        prepared.validate();
        final decoded = GmCareerCodec.decode(GmCareerCodec.encode(prepared));
        expect(
          decoded.finances.debtByTeam,
          equals(prepared.finances.debtByTeam),
        );
        expect(
          decoded.finances.guaranteedLiabilities.keys,
          equals(prepared.finances.guaranteedLiabilities.keys),
        );

        // 13. Repeated reads never consume or settle a liability
        final readTeam = decoded.league.teams.firstWhere(
          (t) => t.id != decoded.userFranchiseId,
        );
        final cap1 = decoded.finances.capPayrollFor(readTeam.id, 2);
        final cap2 = decoded.finances.capPayrollFor(readTeam.id, 2);
        expect(cap1, equals(cap2));
        expect(decoded.finances.guaranteedLiabilities, hasLength(1));
      },
    );

    test(
      'No CapException path also preserves debtByTeam and guaranteedLiabilities',
      () {
        final y2Career = _buildYear2CareerForClearance(
          triggerCapException: false,
        );
        const clearance = OffseasonClearanceService();
        final started = clearance.start(y2Career);
        expect(started.offseasonClearance.capExceptions, isEmpty);
        expect(
          started.finances.debtByTeam,
          equals(y2Career.finances.debtByTeam),
        );
        expect(
          started.finances.guaranteedLiabilities.keys,
          equals(y2Career.finances.guaranteedLiabilities.keys),
        );
      },
    );
  });
}
