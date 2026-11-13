import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import '../support/financial_fixtures.dart';

const _seed = 20261028;
const _service = FreeAgentAcquisitionService();

CareerSetupResult _setup({
  FranchiseSituation situation = FranchiseSituation.playIn,
  String team = 'team-1',
}) => const CareerSetupService().generate(
  CareerSetupRequest(
    selectedTeamId: TeamId(team),
    selectedSituation: situation,
    seed: _seed,
  ),
);

GmCareer _career({
  FranchiseSituation situation = FranchiseSituation.playIn,
  String team = 'team-1',
}) => GmCareer.fromSetupResult(
  _setup(situation: situation, team: team),
  id: 't08d-acquisition',
);

GmCareer _acquireStandard(
  GmCareer career, {
  int salary = 1000,
  int duration = 2,
}) {
  final player = career.freeAgentPool.entries.first.id;
  return _service.acquire(
    career: career,
    teamId: career.userFranchiseId,
    freeAgentId: player,
    category: RosterCategory.standard,
    durationYears: duration,
    agreedFirstYearSalary: salary,
  );
}

Matcher _codesContain(ValidationCode code) => throwsA(
  isA<DomainValidationException>().having(
    (error) => error.codes,
    'codes',
    contains(code),
  ),
);

String _contractsExcluding(CareerFinances finances, PlayerId playerId) =>
    jsonEncode({
      'contracts': [
        for (final contract in finances.contracts.values)
          if (contract.playerId != playerId) contract.toJson(),
      ],
      'schedules': [
        for (final schedule in finances.schedules.values)
          if (schedule.playerId != playerId) schedule.toJson(),
      ],
    });

void main() {
  group('T08D free-agent acquisition', () {
    test('initial pool and identity snapshot are persistent', () {
      final career = _career();
      expect(career.freeAgentPool.length, 90);
      expect(career.freeAgentPool.initialPlayerIds.length, 90);
      expect(career.freeAgentPool.acquisitions.isEmpty, isTrue);
      expect(
        career.freeAgentPool.initialPlayerIds.map((id) => id.value).toSet(),
        career.freeAgentPool.playerIds,
      );
    });

    test('valid standard acquisition moves one player atomically', () {
      final career = _career();
      final playerId = career.freeAgentPool.entries.first.id;
      final entry = career.freeAgentPool.byId(playerId)!;
      final before = _contractsExcluding(career.finances, playerId);
      final beforeReadiness = LeagueReadinessReport.fromCareer(career).teams
          .firstWhere((team) => team.teamId == career.userFranchiseId)
          .standardShortage;

      final acquired = _service.acquire(
        career: career,
        teamId: career.userFranchiseId,
        freeAgentId: playerId,
        category: RosterCategory.standard,
        durationYears: 2,
        agreedFirstYearSalary: 1000,
      );

      expect(acquired.freeAgentPool.length, 89);
      expect(acquired.freeAgentPool.contains(playerId), isFalse);
      expect(acquired.freeAgentPool.initialPlayerIds.length, 90);
      expect(acquired.freeAgentPool.acquisitions.length, 1);
      final record = acquired.freeAgentPool.acquisitions.forPlayer(playerId)!;
      expect(record.teamId, acquired.userFranchiseId);
      expect(record.origin, AcquisitionOrigin.initialPool);
      expect(record.seasonYear, 1);

      final rosterPlayer = acquired.userTeam.players.firstWhere(
        (player) => player.id == playerId,
      );
      expect(rosterPlayer.firstName, entry.player.firstName);
      expect(rosterPlayer.position, entry.player.position);
      expect(rosterPlayer.attributes.asMap, entry.player.attributes.asMap);
      final profile = acquired.careerProfiles.forPlayer(playerId)!;
      expect(profile.age, entry.profile.age);
      expect(profile.potential, entry.profile.potential);
      expect(profile.trajectory, entry.profile.trajectory);

      final contract = acquired.finances.contractForPlayer(playerId)!;
      expect(contract.source, ContractSource.freeAgent);
      expect(contract.category, RosterCategory.standard);
      expect(contract.durationYears, 2);
      final schedule = acquired.finances.scheduleFor(contract.id)!;
      expect(schedule.annualSalaries, [1000, 1050]);
      expect(_contractsExcluding(acquired.finances, playerId), before);

      final afterReadiness = LeagueReadinessReport.fromCareer(acquired).teams
          .firstWhere((team) => team.teamId == acquired.userFranchiseId)
          .standardShortage;
      expect(afterReadiness, beforeReadiness - 1);
    });

    test('valid two-way acquisition uses 250 and does not reduce shortage', () {
      final career = _career();
      final playerId = career.freeAgentPool.entries.last.id;
      final before = LeagueReadinessReport.fromCareer(
        career,
      ).teams.firstWhere((team) => team.teamId == career.userFranchiseId);
      final acquired = _service.acquire(
        career: career,
        teamId: career.userFranchiseId,
        freeAgentId: playerId,
        category: RosterCategory.twoWay,
        durationYears: 2,
        agreedFirstYearSalary: 250,
      );
      final after = LeagueReadinessReport.fromCareer(
        acquired,
      ).teams.firstWhere((team) => team.teamId == acquired.userFranchiseId);
      expect(acquired.freeAgentPool.length, 89);
      expect(after.standardShortage, before.standardShortage);
      expect(after.twoWayCount, before.twoWayCount + 1);
      final contract = acquired.finances.contractForPlayer(playerId)!;
      expect(contract.category, RosterCategory.twoWay);
      expect(acquired.finances.scheduleFor(contract.id)!.annualSalaries, [
        250,
        250,
      ]);
      expect(
        acquired.finances.cashPayrollFor(acquired.userFranchiseId, 1),
        acquired.finances.capPayrollFor(acquired.userFranchiseId, 1) + 250,
      );
    });
    test('clearance origin cannot be forged before authorization', () {
      final career = _career();
      expect(
        () => _service.acquire(
          career: career,
          teamId: career.userFranchiseId,
          freeAgentId: career.freeAgentPool.entries.first.id,
          category: RosterCategory.standard,
          durationYears: 1,
          agreedFirstYearSalary: FinancialRules.minimumSalary,
          origin: AcquisitionOrigin.clearance,
        ),
        _codesContain(ValidationCode.freeAgentAcquisitionInvalid),
      );
    });

    test('sequential acquisitions shrink the pool below 90', () {
      var career = _career();
      final ids = [
        career.freeAgentPool.entries[0].id,
        career.freeAgentPool.entries[1].id,
      ];
      career = _service.acquire(
        career: career,
        teamId: career.userFranchiseId,
        freeAgentId: ids[0],
        category: RosterCategory.standard,
        durationYears: 1,
        agreedFirstYearSalary: 400,
      );
      career = _service.acquire(
        career: career,
        teamId: career.userFranchiseId,
        freeAgentId: ids[1],
        category: RosterCategory.standard,
        durationYears: 1,
        agreedFirstYearSalary: 400,
      );
      expect(career.freeAgentPool.length, 88);
      expect(career.freeAgentPool.acquisitions.length, 2);
      expect(career.freeAgentPool.initialPlayerIds.length, 90);
      expect(career.userTeam.roster.standardCount, 14);
    });

    test('duplicate, missing, unknown-team and phase errors are rejected', () {
      final career = _career();
      final playerId = career.freeAgentPool.entries.first.id;
      final acquired = _service.acquire(
        career: career,
        teamId: career.userFranchiseId,
        freeAgentId: playerId,
        category: RosterCategory.standard,
        durationYears: 1,
        agreedFirstYearSalary: 400,
      );
      expect(
        () => _service.acquire(
          career: acquired,
          teamId: acquired.userFranchiseId,
          freeAgentId: playerId,
          category: RosterCategory.standard,
          durationYears: 1,
          agreedFirstYearSalary: 400,
        ),
        _codesContain(ValidationCode.freeAgentInvalid),
      );
      expect(
        () => _service.acquire(
          career: career,
          teamId: career.userFranchiseId,
          freeAgentId: const PlayerId('missing-free-agent'),
          category: RosterCategory.standard,
          durationYears: 1,
          agreedFirstYearSalary: 400,
        ),
        _codesContain(ValidationCode.freeAgentInvalid),
      );
      expect(
        () => _service.acquire(
          career: career,
          teamId: const TeamId('team-99'),
          freeAgentId: playerId,
          category: RosterCategory.standard,
          durationYears: 1,
          agreedFirstYearSalary: 400,
        ),
        _codesContain(ValidationCode.freeAgentInvalid),
      );
    });

    test('duration and salary rules are enforced', () {
      final career = _career();
      final playerId = career.freeAgentPool.entries.first.id;
      for (final duration in [0, 5]) {
        expect(
          () => _service.acquire(
            career: career,
            teamId: career.userFranchiseId,
            freeAgentId: playerId,
            category: RosterCategory.standard,
            durationYears: duration,
            agreedFirstYearSalary: 1000,
          ),
          _codesContain(ValidationCode.contractInvalid),
        );
      }
      expect(
        () => _service.acquire(
          career: career,
          teamId: career.userFranchiseId,
          freeAgentId: playerId,
          category: RosterCategory.twoWay,
          durationYears: 3,
          agreedFirstYearSalary: 250,
        ),
        _codesContain(ValidationCode.contractInvalid),
      );
      for (final salary in [399, 8001]) {
        expect(
          () => _service.acquire(
            career: career,
            teamId: career.userFranchiseId,
            freeAgentId: playerId,
            category: RosterCategory.standard,
            durationYears: 1,
            agreedFirstYearSalary: salary,
          ),
          _codesContain(ValidationCode.salaryOutOfBounds),
        );
      }
      expect(
        () => _service.acquire(
          career: career,
          teamId: career.userFranchiseId,
          freeAgentId: playerId,
          category: RosterCategory.twoWay,
          durationYears: 1,
          agreedFirstYearSalary: 251,
        ),
        _codesContain(ValidationCode.salaryOutOfBounds),
      );
      expect(
        () => _service.acquire(
          career: career,
          teamId: career.userFranchiseId,
          freeAgentId: playerId,
          category: RosterCategory.standard,
          durationYears: 2,
          agreedFirstYearSalary: 8000,
        ),
        _codesContain(ValidationCode.salaryOutOfBounds),
      );
    });

    test('roster capacity is enforced for standard, two-way and total', () {
      final base = _career();
      final fullStandard = _addPlayers(
        base,
        standard: 3,
        twoWay: 0,
        trainingCamp: 0,
      );
      expect(fullStandard.userTeam.roster.standardCount, 15);
      expect(
        () => _service.acquire(
          career: fullStandard,
          teamId: fullStandard.userFranchiseId,
          freeAgentId: fullStandard.freeAgentPool.entries.first.id,
          category: RosterCategory.standard,
          durationYears: 1,
          agreedFirstYearSalary: 400,
        ),
        _codesContain(ValidationCode.rosterCapacityExceeded),
      );
      final fullTwoWay = _addPlayers(
        base,
        standard: 0,
        twoWay: 3,
        trainingCamp: 0,
      );
      expect(
        () => _service.acquire(
          career: fullTwoWay,
          teamId: fullTwoWay.userFranchiseId,
          freeAgentId: fullTwoWay.freeAgentPool.entries.first.id,
          category: RosterCategory.twoWay,
          durationYears: 1,
          agreedFirstYearSalary: 250,
        ),
        _codesContain(ValidationCode.rosterCapacityExceeded),
      );
      final fullTotal = _addPlayers(
        base,
        standard: 3,
        twoWay: 3,
        trainingCamp: 3,
      );
      expect(fullTotal.userTeam.roster.totalContractedCount, 21);
      expect(
        () => _service.acquire(
          career: fullTotal,
          teamId: fullTotal.userFranchiseId,
          freeAgentId: fullTotal.freeAgentPool.entries.first.id,
          category: RosterCategory.twoWay,
          durationYears: 1,
          agreedFirstYearSalary: 250,
        ),
        _codesContain(ValidationCode.rosterCapacityExceeded),
      );
    });

    test('cap and cash violations are rejected', () {
      final nearCap = _career(
        situation: FranchiseSituation.contender,
        team: 'team-19',
      );
      final capPayroll = nearCap.finances.capPayrollFor(
        nearCap.userFranchiseId,
        1,
      );
      expect(capPayroll + 2000, greaterThan(FinancialRules.salaryCap));
      expect(
        () => _service.acquire(
          career: nearCap,
          teamId: nearCap.userFranchiseId,
          freeAgentId: nearCap.freeAgentPool.entries.first.id,
          category: RosterCategory.standard,
          durationYears: 1,
          agreedFirstYearSalary: 2000,
        ),
        _codesContain(ValidationCode.capBreach),
      );

      final lowCash = _withRevenueAtBreakEven(_career());
      expect(
        () => _service.acquire(
          career: lowCash,
          teamId: lowCash.userFranchiseId,
          freeAgentId: lowCash.freeAgentPool.entries.first.id,
          category: RosterCategory.standard,
          durationYears: 1,
          agreedFirstYearSalary: 400,
        ),
        _codesContain(ValidationCode.cashInsufficient),
      );
    });

    test('grandfathered over-cap franchise cannot acquire', () {
      final career = _overCapCareer();
      expect(
        career.finances.capPayrollFor(career.userFranchiseId, 1),
        greaterThan(FinancialRules.salaryCap),
      );
      expect(
        () => _service.acquire(
          career: career,
          teamId: career.userFranchiseId,
          freeAgentId: career.freeAgentPool.entries.first.id,
          category: RosterCategory.standard,
          durationYears: 1,
          agreedFirstYearSalary: 400,
        ),
        _codesContain(ValidationCode.capBreach),
      );
      expect(career.freeAgentPool.acquisitions.length, 0);
    });

    test('acquisitions may reduce a position below 12', () {
      var career = _career();
      final guards = career.freeAgentPool.entries
          .where((entry) => entry.player.position == Position.pg)
          .take(8)
          .map((entry) => entry.id)
          .toList();
      for (var i = 0; i < guards.length; i++) {
        career = _service.acquire(
          career: career,
          teamId: career.league.teams[i + 1].id,
          freeAgentId: guards[i],
          category: RosterCategory.standard,
          durationYears: 1,
          agreedFirstYearSalary: 400,
        );
      }
      expect(career.freeAgentPool.length, 82);
      expect(
        career.freeAgentPool.entries
            .where((entry) => entry.player.position == Position.pg)
            .length,
        10,
      );
      expect(career.freeAgentPool.acquisitions.length, 8);
      career.validate();
    });

    test('failed acquisition leaves the original career unchanged', () {
      final career = _career();
      final before = GmCareerCodec.encode(career);
      expect(
        () => _service.acquire(
          career: career,
          teamId: career.userFranchiseId,
          freeAgentId: career.freeAgentPool.entries.first.id,
          category: RosterCategory.standard,
          durationYears: 1,
          agreedFirstYearSalary: 8001,
        ),
        _codesContain(ValidationCode.salaryOutOfBounds),
      );
      expect(GmCareerCodec.encode(career), before);
    });

    test('ledger, pool and roster mismatches are rejected', () {
      final career = _acquireStandard(_career());
      final playerId =
          career.freeAgentPool.acquisitions.entries.values.single.playerId;
      final rosterPlayer = career.league.teams
          .expand((team) => team.players)
          .firstWhere((player) => player.id == playerId);
      expect(
        () => FreeAgentPool(
          entries: [
            ...career.freeAgentPool.entries,
            FreeAgentEntry(
              player: rosterPlayer,
              profile: career.careerProfiles.forPlayer(playerId)!,
            ),
          ],
          initialPlayerIds: career.freeAgentPool.initialPlayerIds,
          acquisitions: career.freeAgentPool.acquisitions,
        ),
        throwsFormatException,
      );
      expect(
        () => FreeAgentPool(
          entries: career.freeAgentPool.entries,
          initialPlayerIds: career.freeAgentPool.initialPlayerIds,
          acquisitions: FreeAgentAcquisitionLedger.empty(),
        ),
        throwsFormatException,
      );
      final base = _career();
      final orphanId = base.freeAgentPool.entries.first.id;
      final orphanRecord = FreeAgentAcquisition(
        transactionId: FreeAgentAcquisition.idFor(orphanId, 1),
        playerId: orphanId,
        teamId: base.userFranchiseId,
        contractId: PlayerContract.idFor(orphanId, 1),
        seasonYear: 1,
        category: RosterCategory.standard,
      );
      final ledgerWithoutRoster = FreeAgentPool(
        entries: [
          for (final entry in base.freeAgentPool.entries)
            if (entry.id != orphanId) entry,
        ],
        initialPlayerIds: base.freeAgentPool.initialPlayerIds,
        acquisitions: FreeAgentAcquisitionLedger(entries: [orphanRecord]),
      );
      expect(
        () => base.copyWith(freeAgentPool: ledgerWithoutRoster),
        throwsFormatException,
      );
    });

    test('save/load preserves acquisitions and pool state', () {
      final acquired = _acquireStandard(_career());
      final encoded = GmCareerCodec.encode(acquired);
      final decoded = GmCareerCodec.decode(encoded);
      expect(GmCareerCodec.encode(decoded), encoded);
      expect(
        jsonEncode(decoded.freeAgentPool.toJson()),
        jsonEncode(acquired.freeAgentPool.toJson()),
      );
      expect(
        decoded.finances.contracts.length,
        acquired.finances.contracts.length,
      );
    });

    test('v1-v8 saves migrate with an identity snapshot and empty ledger', () {
      final career = _career();
      final base =
          jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
      for (var version = 1; version <= 8; version++) {
        final older = Map<String, dynamic>.from(base)
          ..['schemaVersion'] = version;
        final pool = older['freeAgentPool'];
        if (pool is Map<String, dynamic>) {
          pool
            ..remove('initialPlayerIds')
            ..remove('acquisitions');
        }
        if (version < 8) older.remove('finances');
        final migrated = GmCareerCodec.decode(jsonEncode(older));
        expect(migrated.schemaVersion, 14, reason: 'from v$version');
        expect(migrated.freeAgentPool.length, 90);
        expect(migrated.freeAgentPool.initialPlayerIds.length, 90);
        expect(migrated.freeAgentPool.acquisitions.isEmpty, isTrue);
      }
    });

    test('native v9 requires identity snapshot and ledger', () {
      final base =
          jsonDecode(GmCareerCodec.encode(_career())) as Map<String, dynamic>;
      final missingIds = Map<String, dynamic>.from(base);
      ((missingIds['freeAgentPool'] as Map<String, dynamic>)).remove(
        'initialPlayerIds',
      );
      expect(
        () => GmCareerCodec.decode(jsonEncode(missingIds)),
        throwsFormatException,
      );
      final missingLedger = Map<String, dynamic>.from(base);
      ((missingLedger['freeAgentPool'] as Map<String, dynamic>)).remove(
        'acquisitions',
      );
      expect(
        () => GmCareerCodec.decode(jsonEncode(missingLedger)),
        throwsFormatException,
      );
    });

    test('deterministic evidence across all four situations', () {
      for (final situation in FranchiseSituation.values) {
        final career = _career(situation: situation);
        expect(career.freeAgentPool.length, 90, reason: situation.name);
        final before = LeagueReadinessReport.fromCareer(
          career,
        ).teams.firstWhere((team) => team.teamId == career.userFranchiseId);
        final acquired = _service.acquire(
          career: career,
          teamId: career.userFranchiseId,
          freeAgentId: career.freeAgentPool.entries.first.id,
          category: RosterCategory.standard,
          durationYears: 1,
          agreedFirstYearSalary: 400,
        );
        final after = LeagueReadinessReport.fromCareer(
          acquired,
        ).teams.firstWhere((team) => team.teamId == acquired.userFranchiseId);
        expect(acquired.freeAgentPool.length, 89);
        expect(acquired.freeAgentPool.acquisitions.length, 1);
        expect(after.standardCount, before.standardCount + 1);
        expect(after.standardShortage, before.standardShortage - 1);
      }
    });
  });
}

GmCareer _addPlayers(
  GmCareer career, {
  required int standard,
  required int twoWay,
  required int trainingCamp,
}) {
  final team = career.userTeam;
  var roster = team.roster;
  final added = <Player>[];
  void add(int count, String prefix, RosterCategory category) {
    for (var i = 0; i < count; i++) {
      final player = Player(
        id: PlayerId('$prefix-${team.id.value}-$i'),
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

  add(standard, 'std', RosterCategory.standard);
  add(twoWay, 'tw', RosterCategory.twoWay);
  add(trainingCamp, 'tc', RosterCategory.trainingCamp);
  return withBootstrappedTeam(
    career,
    team.copyWith(roster: roster),
    careerProfiles: LeagueCareerProfiles(
      leagueSeed: career.careerProfiles.leagueSeed,
      profiles: {
        ...career.careerProfiles.profiles,
        for (final player in added)
          player.id.value: PlayerCareerProfile(
            playerId: player.id,
            age: 23,
            potential: 60,
            trajectory: DevelopmentTrajectory.steady,
          ),
      },
    ),
  );
}

GmCareer _overCapCareer() {
  final career = _career();
  final teamId = career.userFranchiseId;
  final team = career.userTeam;
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
  final finances = career.finances;
  final record = finances.financesFor(teamId);
  final updated = CareerFinances(
    contracts: contracts,
    schedules: schedules,
    teamFinances: [
      for (final candidate in finances.teamFinances.values)
        candidate.teamId == teamId
            ? TeamFinances(
                teamId: teamId,
                operatingBudget: record.operatingBudget,
                cash: record.cash,
                revenueBaseline: 1000000,
                season: 1,
                capGrandfathered: true,
                grandfatheredPayroll: 96000,
              )
            : candidate,
    ],
    staffCommitments: finances.staffCommitments.values,
    facilities: finances.facilities.values,
  );
  return career.copyWith(finances: updated);
}

GmCareer _withRevenueAtBreakEven(GmCareer career) {
  final teamId = career.userFranchiseId;
  final finances = career.finances;
  final revenue =
      finances.cashPayrollFor(teamId, career.currentYear) +
      finances.operatingCommitmentsFor(teamId) +
      100;
  final updated = CareerFinances(
    contracts: finances.contracts.values,
    schedules: finances.schedules.values,
    teamFinances: [
      for (final record in finances.teamFinances.values)
        record.teamId == teamId
            ? TeamFinances(
                teamId: teamId,
                operatingBudget: record.operatingBudget,
                cash: 0,
                revenueBaseline: revenue,
                season: record.season,
                capGrandfathered: record.capGrandfathered,
                grandfatheredPayroll: record.grandfatheredPayroll,
              )
            : record,
    ],
    staffCommitments: finances.staffCommitments.values,
    facilities: finances.facilities.values,
  );
  return career.copyWith(finances: updated);
}
