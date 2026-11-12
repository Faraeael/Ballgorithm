import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _seed = 20261028;

CareerSetupResult _setup() => const CareerSetupService().generate(
  const CareerSetupRequest(
    selectedTeamId: TeamId('team-1'),
    selectedSituation: FranchiseSituation.playIn,
    seed: _seed,
  ),
);

GmCareer _career() =>
    GmCareer.fromSetupResult(_setup(), id: 't08c-p1-contracts');

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

League _leagueWithTeam(GmCareer career, Team updated) => League.create(
  id: career.league.id,
  name: career.league.name,
  config: career.league.config,
  teams: [
    for (final candidate in career.league.teams)
      candidate.id == updated.id ? updated : candidate,
  ],
  enforceRosterSize: false,
);

LeagueCareerProfiles _profilesWith(
  GmCareer career,
  Map<String, PlayerCareerProfile> additions,
) => LeagueCareerProfiles(
  leagueSeed: career.careerProfiles.leagueSeed,
  profiles: {...career.careerProfiles.profiles, ...additions},
);

Player _replacementPlayer(Player source, {required int rating}) => Player(
  id: source.id,
  firstName: source.firstName,
  lastName: source.lastName,
  position: source.position,
  attributes: PlayerAttributes(
    insideScoring: rating,
    midrange: rating,
    threePoint: rating,
    freeThrow: rating,
    passing: rating,
    ballHandling: rating,
    perimeterDefense: rating,
    interiorDefense: rating,
    rebounding: rating,
    athleticism: rating,
    stamina: rating,
    basketballIQ: rating,
  ),
);

String _contractSnapshot(CareerFinances finances) => jsonEncode({
  'contracts': [
    for (final contract in finances.contracts.values) contract.toJson(),
  ],
  'schedules': [
    for (final schedule in finances.schedules.values) schedule.toJson(),
  ],
});

void main() {
  group('T08C-P1 contract immutability', () {
    test('unrelated team update preserves contracts and schedules', () {
      final career = _career();
      final before = _contractSnapshot(career.finances);
      final team = career.userTeam.copyWith(name: 'Renamed Franchise');
      final updated = career.copyWith(league: _leagueWithTeam(career, team));
      expect(_contractSnapshot(updated.finances), before);
      expect(updated.userTeam.name, 'Renamed Franchise');
    });

    test('unrelated roster reorder preserves contracts and schedules', () {
      final career = _career();
      final before = _contractSnapshot(career.finances);
      final team = career.league.teams.firstWhere(
        (candidate) => candidate.id == const TeamId('team-2'),
      );
      final reordered = [
        team.players[1],
        team.players[0],
        ...team.players.skip(2),
      ];
      final updated = career.copyWith(
        league: _leagueWithTeam(
          career,
          team.copyWith(
            roster: Roster(reordered, categories: team.roster.categories),
          ),
        ),
      );
      expect(_contractSnapshot(updated.finances), before);
      expect(
        updated.league.teams
            .firstWhere((candidate) => candidate.id == team.id)
            .players
            .first
            .id,
        team.players[1].id,
      );
    });

    test('OVR change does not change salary or invalidate the contract', () {
      final career = _career();
      final team = career.userTeam;
      final player = team.players.first;
      final contract = career.finances.contractForPlayer(player.id)!;
      final schedule = career.finances.scheduleFor(contract.id)!;
      final before = jsonEncode(schedule.toJson());
      final updated = career.copyWith(
        league: _leagueWithTeam(
          career,
          team.copyWith(
            roster: team.roster
                .withoutPlayer(player.id)
                .withPlayer(_replacementPlayer(player, rating: 99)),
          ),
        ),
        careerProfiles: _profilesWith(career, {
          player.id.value: PlayerCareerProfile(
            playerId: player.id,
            age: career.careerProfiles.forPlayer(player.id)!.age,
            potential: 99,
            trajectory: DevelopmentTrajectory.steady,
          ),
        }),
      );
      expect(
        jsonEncode(updated.finances.scheduleFor(contract.id)!.toJson()),
        before,
      );
      expect(
        updated.finances.contractForPlayer(player.id)!.source,
        ContractSource.legacy,
      );
    });

    test('age change does not rewrite duration', () {
      final career = _career();
      final player = career.userTeam.players.first;
      final contract = career.finances.contractForPlayer(player.id)!;
      final updated = career.copyWith(
        careerProfiles: _profilesWith(career, {
          player.id.value: PlayerCareerProfile(
            playerId: player.id,
            age: 38,
            potential: 99,
            trajectory: DevelopmentTrajectory.steady,
          ),
        }),
      );
      final after = updated.finances.contractForPlayer(player.id)!;
      expect(after.durationYears, contract.durationYears);
      expect(after.startYear, contract.startYear);
      expect(after.source, contract.source);
      updated.validate();
    });

    test('fabricated roster addition without a contract is rejected', () {
      final career = _career();
      final team = career.userTeam;
      final added = Player(
        id: const PlayerId('fabricated-player'),
        firstName: 'Fabricated',
        lastName: 'Player',
        position: Position.pg,
        attributes: _replacementPlayer(
          team.players.first,
          rating: 50,
        ).attributes,
      );
      final updatedTeam = team.copyWith(roster: team.roster.withPlayer(added));
      expect(
        () => career.copyWith(
          league: _leagueWithTeam(career, updatedTeam),
          careerProfiles: _profilesWith(career, {
            added.id.value: PlayerCareerProfile(
              playerId: added.id,
              age: 23,
              potential: 60,
              trajectory: DevelopmentTrajectory.steady,
            ),
          }),
        ),
        throwsA(
          isA<DomainValidationException>().having(
            (error) => error.codes,
            'codes',
            contains(ValidationCode.contractMissing),
          ),
        ),
      );
    });

    test('duplicate employment is rejected by the transaction boundary', () {
      final career = _career();
      final player = career.userTeam.players.first;
      final contract = career.finances.contractForPlayer(player.id)!;
      expect(
        () => FinancialTransactions.addContract(
          finances: career.finances,
          contract: PlayerContract(
            id: 'duplicate-contract',
            playerId: player.id,
            teamId: career.userFranchiseId,
            category: contract.category,
            startYear: contract.startYear,
            durationYears: 1,
            source: ContractSource.freeAgent,
          ),
          annualSalaries: const [400],
        ),
        throwsA(
          isA<DomainValidationException>().having(
            (error) => error.codes,
            'codes',
            contains(ValidationCode.contractDuplicate),
          ),
        ),
      );
      expect(
        () => FinancialTransactions.addContract(
          finances: career.finances,
          contract: FinancialTransactions.futureFreeAgentContract(
            playerId: const PlayerId('new-player'),
            teamId: career.userFranchiseId,
            category: RosterCategory.standard,
            startYear: 1,
            durationYears: 2,
          ),
          annualSalaries: const [400],
        ),
        throwsA(
          isA<DomainValidationException>().having(
            (error) => error.codes,
            'codes',
            contains(ValidationCode.scheduleInvalid),
          ),
        ),
      );
    });

    test('future free-agent contract keeps its source across copies', () {
      final career = _career();
      final team = career.userTeam;
      final player = Player(
        id: const PlayerId('future-free-agent'),
        firstName: 'Future',
        lastName: 'Signing',
        position: Position.sf,
        attributes: _replacementPlayer(
          team.players.first,
          rating: 60,
        ).attributes,
      );
      final updatedTeam = team.copyWith(roster: team.roster.withPlayer(player));
      final league = _leagueWithTeam(career, updatedTeam);
      final profiles = _profilesWith(career, {
        player.id.value: PlayerCareerProfile(
          playerId: player.id,
          age: 27,
          potential: 70,
          trajectory: DevelopmentTrajectory.steady,
        ),
      });
      final finances = FinancialTransactions.addContract(
        finances: career.finances,
        contract: FinancialTransactions.futureFreeAgentContract(
          playerId: player.id,
          teamId: team.id,
          category: RosterCategory.standard,
          startYear: career.currentYear,
          durationYears: 2,
        ),
        annualSalaries: const [2700, 2835],
      );
      final signed = career.copyWith(
        league: league,
        careerProfiles: profiles,
        finances: finances,
      );
      final after = signed.copyWith(
        freeAgentPool: const FreeAgentGenerator().generate(seed: 424242),
      );
      final retained = after.finances.contractForPlayer(player.id)!;
      expect(retained.source, ContractSource.freeAgent);
      expect(after.finances.scheduleFor(retained.id)!.annualSalaries, const [
        2700,
        2835,
      ]);
    });

    test('unauthorized salary rewrite is rejected', () {
      final career = _career();
      final contract = career.finances.contracts.values.first;
      final schedule = career.finances.scheduleFor(contract.id)!;
      final broken = ContractFinancials(
        contractId: schedule.contractId,
        playerId: schedule.playerId,
        teamId: schedule.teamId,
        annualSalaries: [
          for (var i = 0; i < schedule.annualSalaries.length; i++) 4321,
        ],
        guaranteedYears: schedule.guaranteedYears,
        source: schedule.source,
        signedYear: schedule.signedYear,
      );
      expect(
        () => career.copyWith(
          finances: CareerFinances(
            contracts: career.finances.contracts.values,
            schedules: [
              for (final record in career.finances.schedules.values)
                record.contractId == contract.id ? broken : record,
            ],
            teamFinances: career.finances.teamFinances.values,
            staffCommitments: career.finances.staffCommitments.values,
            facilities: career.finances.facilities.values,
          ),
        ),
        throwsA(
          isA<DomainValidationException>().having(
            (error) => error.codes,
            'codes',
            contains(ValidationCode.scheduleInvalid),
          ),
        ),
      );
    });

    test('human rookie signing keeps every earlier contract', () {
      var career = _completedDraft(_career());
      final before = _contractSnapshot(career.finances);
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
      expect(career.finances.contracts.length, 361);
      final after = jsonEncode({
        'contracts': [
          for (final contract in career.finances.contracts.values)
            if (contract.playerId != rights.prospectId) contract.toJson(),
        ],
        'schedules': [
          for (final schedule in career.finances.schedules.values)
            if (schedule.playerId != rights.prospectId) schedule.toJson(),
        ],
      });
      expect(after, before);
    });

    test('sequential rookie signings preserve earlier schedules', () {
      var career = _completedDraft(_career());
      final rights = career.draftExecutionState.draftRights.values
          .where((right) => right.owningTeamId == career.userFranchiseId)
          .toList();
      career = const RookieSigningService().signDraftedRookie(
        career: career,
        teamId: career.userFranchiseId,
        prospectId: rights[0].prospectId,
        category: RosterCategory.standard,
        durationYears: 4,
      );
      final first = career.finances.contractForPlayer(rights[0].prospectId)!;
      final firstSchedule = jsonEncode(
        career.finances.scheduleFor(first.id)!.toJson(),
      );
      career = const RookieSigningService().signDraftedRookie(
        career: career,
        teamId: career.userFranchiseId,
        prospectId: rights[1].prospectId,
        category: RosterCategory.standard,
        durationYears: 3,
      );
      expect(
        jsonEncode(career.finances.scheduleFor(first.id)!.toJson()),
        firstSchedule,
      );
      expect(
        career.finances.contractForPlayer(rights[1].prospectId)!.source,
        ContractSource.rookie,
      );
    });

    test(
      'AI signing uses the same transaction and keeps existing contracts',
      () {
        final career = _completedDraft(_career());
        final before = _contractSnapshot(career.finances);
        const service = RookieAiSigningService();
        var current = service.initialize(career);
        final pendingBefore = service.pendingRights(current).length;
        current = service.applyNextDecision(current);
        expect(service.pendingRights(current).length, pendingBefore - 1);
        final signedIds = {
          for (final contract in current.rookieSigningLedger.contracts.values)
            contract.playerId.value,
        };
        final after = jsonEncode({
          'contracts': [
            for (final contract in current.finances.contracts.values)
              if (!signedIds.contains(contract.playerId.value))
                contract.toJson(),
          ],
          'schedules': [
            for (final schedule in current.finances.schedules.values)
              if (!signedIds.contains(schedule.playerId.value))
                schedule.toJson(),
          ],
        });
        expect(after, before);
      },
    );

    test('save/load preserves contracts byte-for-byte', () {
      final career = _career();
      final encoded = GmCareerCodec.encode(career);
      final decoded = GmCareerCodec.decode(encoded);
      expect(GmCareerCodec.encode(decoded), encoded);
      expect(
        jsonEncode(decoded.finances.toJson()),
        jsonEncode(career.finances.toJson()),
      );
    });

    test('financial rules and staff/facility baselines are unchanged', () {
      final career = _career();
      expect(FinancialRules.salaryCap, 41000);
      expect(FinancialRules.minimumSalary, 400);
      expect(FinancialRules.maximumSalary, 8000);
      expect(FinancialRules.twoWaySalary, 250);
      for (final team in career.league.teams) {
        expect(
          career.finances.staffCommitments.values
              .where((record) => record.teamId == team.id)
              .fold<int>(0, (sum, record) => sum + record.annualCost),
          9500,
        );
        expect(
          career.finances.facilities.values
              .where((record) => record.teamId == team.id)
              .fold<int>(0, (sum, record) => sum + record.maintenancePerYear),
          2800,
        );
      }
      final teamId = career.userFranchiseId;
      expect(
        career.finances.cashPayrollFor(teamId, 1),
        career.finances.capPayrollFor(teamId, 1) +
            career.finances.twoWayPayrollFor(teamId, 1),
      );
      expect(
        jsonEncode(career.copyWith().freeAgentPool.toJson()),
        jsonEncode(career.freeAgentPool.toJson()),
      );
    });
  });
}
