import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import '../support/financial_fixtures.dart';

const _seed = 20261028;

CareerSetupResult _setup({
  FranchiseSituation situation = FranchiseSituation.tanking,
  String team = 'team-1',
}) => const CareerSetupService().generate(
  CareerSetupRequest(
    selectedTeamId: TeamId(team),
    selectedSituation: situation,
    seed: _seed,
  ),
);

GmCareer _career({FranchiseSituation situation = FranchiseSituation.tanking}) =>
    GmCareer.fromSetupResult(_setup(situation: situation), id: 't08c-test');

CareerFinances _withRecords(
  CareerFinances source, {
  List<PlayerContract>? contracts,
  List<ContractFinancials>? schedules,
  List<TeamFinances>? teamFinances,
  List<StaffCommitment>? staff,
  List<FacilityState>? facilities,
}) => CareerFinances(
  contracts: contracts ?? source.contracts.values.toList(),
  schedules: schedules ?? source.schedules.values.toList(),
  teamFinances: teamFinances ?? source.teamFinances.values.toList(),
  staffCommitments: staff ?? source.staffCommitments.values.toList(),
  facilities: facilities ?? source.facilities.values.toList(),
);

Matcher _codesContain(ValidationCode code) => throwsA(
  isA<DomainValidationException>().having(
    (error) => error.codes,
    'codes',
    contains(code),
  ),
);

GmCareer _completedDraft(GmCareer career) {
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

void main() {
  group('T08C financial foundation', () {
    test('every initial player has one contract and one schedule', () {
      final career = _career();
      expect(career.schemaVersion, 13);
      expect(career.finances.contracts.length, 360);
      expect(career.finances.schedules.length, 360);
      expect(career.finances.teamFinances.length, 30);
      for (final team in career.league.teams) {
        for (final player in team.players) {
          final contract = career.finances.contractForPlayer(player.id);
          expect(contract, isNotNull, reason: player.id.value);
          expect(contract!.source, ContractSource.legacy);
          expect(
            contract.teamId,
            team.id,
            reason: 'ownership must match the roster',
          );
          final schedule = career.finances.scheduleFor(contract.id);
          expect(schedule, isNotNull);
          expect(schedule!.annualSalaries.length, contract.durationYears);
        }
      }
    });

    test('legacy salaries and durations follow the approved table', () {
      final career = _career();
      for (final team in career.league.teams) {
        for (final player in team.players) {
          final contract = career.finances.contractForPlayer(player.id)!;
          final profile = career.careerProfiles.forPlayer(player.id)!;
          final schedule = career.finances.scheduleFor(contract.id)!;
          expect(
            contract.durationYears,
            FinancialRules.legacyDurationForAge(profile.age),
          );
          expect(
            schedule.annualSalaries.first,
            FinancialRules.legacySalaryForOverall(
              player.attributes.overallRating,
            ),
          );
        }
      }
    });

    test('starting finances, staff and facilities are explicit', () {
      final career = _career();
      for (final team in career.league.teams) {
        final finances = career.finances.financesFor(team.id);
        final plan = FinancialRules.planFor(team.situation!);
        expect(finances.operatingBudget, plan.operatingBudget);
        expect(finances.cash, plan.cash);
        expect(finances.revenueBaseline, plan.revenueBaseline);
        expect(finances.capGrandfathered, isFalse);
        final staff = career.finances.staffCommitments.values.where(
          (record) => record.teamId == team.id,
        );
        final facilities = career.finances.facilities.values.where(
          (record) => record.teamId == team.id,
        );
        expect(
          staff.fold<int>(0, (sum, record) => sum + record.annualCost),
          FinancialRules.initialStaffCost,
        );
        expect(
          facilities.fold<int>(
            0,
            (sum, record) => sum + record.maintenancePerYear,
          ),
          FinancialRules.initialFacilityMaintenance,
        );
        expect(
          career.finances.operatingCommitmentsFor(team.id),
          FinancialRules.initialStaffCost +
              FinancialRules.initialFacilityMaintenance,
        );
      }
    });

    test('two-way salary stays out of cap but inside cash payroll', () {
      final base = _career();
      final team = base.userTeam;
      final twoWayPlayer = team.players.first;
      final moved = withBootstrappedTeam(
        base,
        team.copyWith(
          roster: team.roster.withCategory(
            twoWayPlayer.id,
            RosterCategory.twoWay,
          ),
        ),
      );
      final contract = moved.finances.contractForPlayer(twoWayPlayer.id)!;
      expect(contract.category, RosterCategory.twoWay);
      final schedule = moved.finances.scheduleFor(contract.id)!;
      expect(schedule.annualSalaries, everyElement(250));
      expect(moved.finances.twoWayPayrollFor(team.id, 1), 250);
      expect(
        moved.finances.cashPayrollFor(team.id, 1),
        moved.finances.capPayrollFor(team.id, 1) + 250,
      );
      final cashPayroll = moved.finances.cashPayrollFor(team.id, 1);
      expect(cashPayroll, greaterThan(250));
      moved.validate();
    });

    test('money arithmetic rejects balances outside the bound', () {
      expect(Money.add(400, 250, 'test'), 650);
      expect(
        () => Money.add(999999, 10, 'test'),
        _codesContain(ValidationCode.moneyInvalid),
      );
      expect(
        () => Money.requireBalance(-1, 'test'),
        _codesContain(ValidationCode.moneyInvalid),
      );
      expect(Money.isNonNegative(0), isTrue);
    });

    test('minimum-roster relief distinguishes 200 from the 800 bound', () {
      expect(
        FinancialRules.minimumRosterReliefOverage(
          standardCount: 12,
          capRoom: 600,
        ),
        200,
      );
      expect(
        FinancialRules.minimumRosterReliefOverage(
          standardCount: 12,
          capRoom: 0,
        ),
        800,
      );
      expect(
        FinancialRules.minimumRosterReliefOverage(
          standardCount: 12,
          capRoom: 800,
        ),
        0,
      );
      expect(
        FinancialRules.minimumRosterReliefOverage(
          standardCount: 11,
          capRoom: 0,
        ),
        isNull,
      );
      expect(
        FinancialRules.minimumRosterReliefOverage(
          standardCount: 14,
          capRoom: 0,
        ),
        isNull,
      );
    });

    test(
      'rookie signing preserves the historical contract and links money',
      () {
        var career = _completedDraft(_career());
        final rights = career.draftExecutionState.draftRights.values.firstWhere(
          (right) => right.owningTeamId == career.userFranchiseId,
        );
        final signed = const RookieSigningService().signDraftedRookie(
          career: career,
          teamId: career.userFranchiseId,
          prospectId: rights.prospectId,
          category: RosterCategory.standard,
          durationYears: 4,
        );
        final rookie = signed.rookieSigningLedger.forPlayer(rights.prospectId)!;
        final contract = signed.finances.contractForPlayer(rights.prospectId)!;
        expect(contract.source, ContractSource.rookie);
        expect(contract.rookieContractId, rookie.id);
        expect(contract.durationYears, rookie.durationYears);
        expect(contract.category, rookie.category);
        final schedule = signed.finances.scheduleFor(contract.id)!;
        expect(
          schedule.annualSalaries.first,
          FinancialRules.rookieSalaryForPick(rookie.overallPick),
        );
        final encoded = GmCareerCodec.encode(signed);
        final decoded = GmCareerCodec.decode(encoded);
        expect(
          jsonEncode(
            decoded.rookieSigningLedger.forPlayer(rookie.playerId)!.toJson(),
          ),
          jsonEncode(rookie.toJson()),
        );
        expect(
          jsonEncode(
            decoded.finances.contractForPlayer(rights.prospectId)!.toJson(),
          ),
          jsonEncode(contract.toJson()),
        );
      },
    );

    test('v8 round-trip is canonical and keeps free-agent bytes', () {
      final career = _career();
      final first = GmCareerCodec.encode(career);
      final decoded = GmCareerCodec.decode(first);
      expect(GmCareerCodec.encode(decoded), first);
      expect(
        jsonEncode(decoded.freeAgentPool.toJson()),
        jsonEncode(career.freeAgentPool.toJson()),
      );
      expect(
        jsonEncode(decoded.finances.toJson()),
        jsonEncode(career.finances.toJson()),
      );
    });

    test('v1-v7 saves migrate with deterministic financial records', () {
      final career = _career();
      final encoded = GmCareerCodec.decode(GmCareerCodec.encode(career));
      final base =
          jsonDecode(GmCareerCodec.encode(encoded)) as Map<String, dynamic>;
      for (var version = 1; version <= 7; version++) {
        final older = Map<String, dynamic>.from(base)
          ..['schemaVersion'] = version
          ..remove('finances');
        final migrated = GmCareerCodec.decode(jsonEncode(older));
        expect(migrated.schemaVersion, 13, reason: 'from v$version');
        expect(migrated.finances.contracts.length, 360);
        expect(migrated.finances.schedules.length, 360);
        migrated.validate();
        final reencoded =
            jsonDecode(GmCareerCodec.encode(migrated)) as Map<String, dynamic>;
        expect(reencoded['schemaVersion'], 13);
        expect(reencoded['finances'], isNotNull);
      }
    });

    test('v8 saves without financial records are rejected', () {
      final encoded =
          jsonDecode(GmCareerCodec.encode(_career())) as Map<String, dynamic>
            ..remove('finances');
      expect(
        () => GmCareerCodec.decode(jsonEncode(encoded)),
        throwsA(isA<FormatException>()),
      );
    });

    test('duplicate financial records are rejected', () {
      final career = _career();
      final contracts = career.finances.contracts.values.toList();
      expect(
        () => _withRecords(
          career.finances,
          contracts: [...contracts, contracts.first],
        ),
        _codesContain(ValidationCode.contractDuplicate),
      );
      final teams = career.finances.teamFinances.values.toList();
      expect(
        () => _withRecords(
          career.finances,
          teamFinances: [...teams, teams.first],
        ),
        _codesContain(ValidationCode.financialTeamInvalid),
      );
      final staff = career.finances.staffCommitments.values.toList();
      expect(
        () => _withRecords(career.finances, staff: [...staff, staff.first]),
        _codesContain(ValidationCode.financialDuplicate),
      );
    });

    test(
      'orphan schedules, missing contracts and wrong ownership are rejected',
      () {
        final career = _career();
        final schedules = career.finances.schedules.values.toList();
        final orphan = ContractFinancials(
          contractId: 'contract-missing-1',
          playerId: const PlayerId('player-missing'),
          teamId: const TeamId('team-1'),
          annualSalaries: const [400],
          guaranteedYears: 1,
          source: ContractSource.legacy,
          signedYear: 1,
        );
        expect(
          () => career.copyWith(
            finances: _withRecords(
              career.finances,
              schedules: [...schedules, orphan],
            ),
          ),
          _codesContain(ValidationCode.scheduleMissing),
        );

        final contracts = career.finances.contracts.values.toList();
        expect(
          () => career.copyWith(
            finances: _withRecords(
              career.finances,
              contracts: contracts.sublist(1),
            ),
          ),
          _codesContain(ValidationCode.contractMissing),
        );

        final first = contracts.first;
        final wrongTeamContract = PlayerContract(
          id: first.id,
          playerId: first.playerId,
          teamId: const TeamId('team-2'),
          category: first.category,
          startYear: first.startYear,
          durationYears: first.durationYears,
          source: first.source,
        );
        final firstSchedule = career.finances.scheduleFor(first.id)!;
        final wrongTeamSchedule = ContractFinancials(
          contractId: first.id,
          playerId: first.playerId,
          teamId: const TeamId('team-2'),
          annualSalaries: firstSchedule.annualSalaries,
          guaranteedYears: firstSchedule.guaranteedYears,
          source: firstSchedule.source,
          signedYear: firstSchedule.signedYear,
        );
        expect(
          () => career.copyWith(
            finances: _withRecords(
              career.finances,
              contracts: [wrongTeamContract, ...contracts.skip(1)],
              schedules: [wrongTeamSchedule, ...schedules.skip(1)],
            ),
          ),
          _codesContain(ValidationCode.financialOwnershipMismatch),
        );
      },
    );

    test('invalid salaries, budgets and cash projections are rejected', () {
      final career = _career();
      final schedules = career.finances.schedules.values.toList();
      final first = schedules.first;
      final inflated = ContractFinancials(
        contractId: first.contractId,
        playerId: first.playerId,
        teamId: first.teamId,
        annualSalaries: [
          for (var i = 0; i < first.annualSalaries.length; i++) 99999,
        ],
        guaranteedYears: first.guaranteedYears,
        source: first.source,
        signedYear: first.signedYear,
      );
      expect(
        () => career.copyWith(
          finances: _withRecords(
            career.finances,
            schedules: [inflated, ...schedules.skip(1)],
          ),
        ),
        _codesContain(ValidationCode.salaryOutOfBounds),
      );

      final teams = career.finances.teamFinances.values.toList();
      final userTeam = career.finances.financesFor(career.userFranchiseId);
      final noBudget = TeamFinances(
        teamId: userTeam.teamId,
        operatingBudget: 0,
        cash: userTeam.cash,
        revenueBaseline: userTeam.revenueBaseline,
        season: userTeam.season,
      );
      expect(
        () => career.copyWith(
          finances: _withRecords(
            career.finances,
            teamFinances: [
              for (final record in teams)
                record.teamId == userTeam.teamId ? noBudget : record,
            ],
          ),
        ),
        _codesContain(ValidationCode.budgetBreach),
      );

      final noRevenue = TeamFinances(
        teamId: userTeam.teamId,
        operatingBudget: userTeam.operatingBudget,
        cash: userTeam.cash,
        revenueBaseline: 0,
        season: userTeam.season,
      );
      expect(
        () => career.copyWith(
          finances: _withRecords(
            career.finances,
            teamFinances: [
              for (final record in teams)
                record.teamId == userTeam.teamId ? noRevenue : record,
            ],
          ),
        ),
        _codesContain(ValidationCode.cashInsufficient),
      );

      expect(
        () => TeamFinances(
          teamId: userTeam.teamId,
          operatingBudget: userTeam.operatingBudget,
          cash: -1,
          revenueBaseline: userTeam.revenueBaseline,
          season: userTeam.season,
        ),
        _codesContain(ValidationCode.moneyInvalid),
      );
    });

    test('over-cap payroll requires an explicit grandfather flag', () {
      final career = _career();
      final teamId = career.userFranchiseId;
      final team = career.league.teams.firstWhere(
        (candidate) => candidate.id == teamId,
      );
      final contracts = <PlayerContract>[];
      final schedules = <ContractFinancials>[];
      for (final existing in career.finances.contracts.values) {
        final isUserPlayer = team.players.any(
          (player) => player.id == existing.playerId,
        );
        if (!isUserPlayer) {
          contracts.add(existing);
          schedules.add(career.finances.scheduleFor(existing.id)!);
          continue;
        }
        final contract = PlayerContract(
          id: PlayerContract.idFor(existing.playerId, 1),
          playerId: existing.playerId,
          teamId: teamId,
          category: existing.category,
          startYear: 1,
          durationYears: 1,
          source: ContractSource.freeAgent,
        );
        contracts.add(contract);
        schedules.add(
          ContractFinancials(
            contractId: contract.id,
            playerId: contract.playerId,
            teamId: contract.teamId,
            annualSalaries: const [8000],
            guaranteedYears: 1,
            source: ContractSource.freeAgent,
            signedYear: 1,
          ),
        );
      }
      final finances = career.finances.financesFor(teamId);
      final teams = [
        for (final record in career.finances.teamFinances.values)
          record.teamId == teamId
              ? TeamFinances(
                  teamId: teamId,
                  operatingBudget: finances.operatingBudget,
                  cash: finances.cash,
                  revenueBaseline: 1000000,
                  season: 1,
                  capGrandfathered: true,
                  grandfatheredPayroll: 96000,
                )
              : record,
      ];
      final grandfathered = career.copyWith(
        finances: _withRecords(
          career.finances,
          contracts: contracts,
          schedules: schedules,
          teamFinances: teams,
        ),
      );
      expect(
        grandfathered.finances.capPayrollFor(teamId, 1),
        greaterThan(FinancialRules.salaryCap),
      );

      final notGrandfathered = [
        for (final record in teams)
          record.teamId == teamId
              ? TeamFinances(
                  teamId: teamId,
                  operatingBudget: record.operatingBudget,
                  cash: record.cash,
                  revenueBaseline: record.revenueBaseline,
                  season: record.season,
                )
              : record,
      ];
      expect(
        () => career.copyWith(
          finances: _withRecords(
            career.finances,
            contracts: contracts,
            schedules: schedules,
            teamFinances: notGrandfathered,
          ),
        ),
        _codesContain(ValidationCode.capBreach),
      );
    });

    test('rookie link, staff and facility corruption are rejected', () {
      var career = _completedDraft(_career());
      final rights = career.draftExecutionState.draftRights.values.firstWhere(
        (right) => right.owningTeamId == career.userFranchiseId,
      );
      career = const RookieSigningService().signDraftedRookie(
        career: career,
        teamId: career.userFranchiseId,
        prospectId: rights.prospectId,
        category: RosterCategory.standard,
        durationYears: 4,
      );
      final contract = career.finances.contractForPlayer(rights.prospectId)!;
      final brokenLink = PlayerContract(
        id: contract.id,
        playerId: contract.playerId,
        teamId: contract.teamId,
        category: contract.category,
        startYear: contract.startYear,
        durationYears: contract.durationYears,
        source: contract.source,
        rookieContractId: 'rookie-contract-missing',
      );
      expect(
        () => career.copyWith(
          finances: _withRecords(
            career.finances,
            contracts: [
              for (final record in career.finances.contracts.values)
                record.id == contract.id ? brokenLink : record,
            ],
          ),
        ),
        _codesContain(ValidationCode.rookieLinkMismatch),
      );

      expect(
        () => StaffCommitment(
          id: 'staff-invalid',
          teamId: career.userFranchiseId,
          category: StaffCategory.scout,
          tier: StaffTier.basic,
          annualCost: -1,
          startYear: 1,
          durationYears: 1,
        ),
        _codesContain(ValidationCode.moneyInvalid),
      );

      expect(
        () => FacilityState(
          teamId: career.userFranchiseId,
          kind: FacilityKind.training,
          level: 9,
          maintenancePerYear: 5400,
        ),
        _codesContain(ValidationCode.facilityInvalid),
      );
    });
  });
}
