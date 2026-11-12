import '../models/contract_financials.dart';
import '../models/facility_state.dart';
import '../models/ids.dart';
import '../models/league.dart';
import '../models/player.dart';
import '../models/player_career_profile.dart';
import '../models/player_contract.dart';
import '../models/rookie_contract.dart';
import '../models/rookie_signing_ledger.dart';
import '../models/roster_category.dart';
import '../models/staff_commitment.dart';
import '../models/team_finances.dart';
import '../validation/validation_result.dart';
import 'financial_rules.dart';

/// The authoritative financial aggregate of one career.
///
/// One active [PlayerContract] per rostered player, one [ContractFinancials]
/// schedule per contract, one [TeamFinances] per franchise, plus explicit staff
/// and facility commitments. No other class may own salary money.
final class CareerFinances {
  CareerFinances._({
    required Map<String, PlayerContract> contracts,
    required Map<String, ContractFinancials> schedules,
    required Map<String, TeamFinances> teamFinances,
    required Map<String, StaffCommitment> staffCommitments,
    required Map<String, FacilityState> facilityByKey,
  }) : contracts = Map.unmodifiable(contracts),
       schedules = Map.unmodifiable(schedules),
       teamFinances = Map.unmodifiable(teamFinances),
       staffCommitments = Map.unmodifiable(staffCommitments),
       facilities = Map.unmodifiable(facilityByKey);

  factory CareerFinances({
    required Iterable<PlayerContract> contracts,
    required Iterable<ContractFinancials> schedules,
    required Iterable<TeamFinances> teamFinances,
    required Iterable<StaffCommitment> staffCommitments,
    required Iterable<FacilityState> facilities,
  }) {
    final issues = <ValidationIssue>[];
    final contractsById = <String, PlayerContract>{};
    for (final contract in contracts) {
      if (contractsById.containsKey(contract.id)) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.contractDuplicate,
            path: 'finances.contracts',
            message: 'duplicate contract id ${contract.id}',
          ),
        );
      }
      contractsById[contract.id] = contract;
    }
    final schedulesById = <String, ContractFinancials>{};
    for (final schedule in schedules) {
      if (schedulesById.containsKey(schedule.contractId)) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.financialDuplicate,
            path: 'finances.schedules',
            message: 'duplicate schedule for contract ${schedule.contractId}',
          ),
        );
      }
      schedulesById[schedule.contractId] = schedule;
    }
    final teamsById = <String, TeamFinances>{};
    for (final finances in teamFinances) {
      if (teamsById.containsKey(finances.teamId.value)) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.financialTeamInvalid,
            path: 'finances.teamFinances',
            message: 'duplicate finances for team ${finances.teamId.value}',
          ),
        );
      }
      teamsById[finances.teamId.value] = finances;
    }
    final staffById = <String, StaffCommitment>{};
    for (final staff in staffCommitments) {
      if (staffById.containsKey(staff.id)) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.financialDuplicate,
            path: 'finances.staffCommitments',
            message: 'duplicate staff commitment ${staff.id}',
          ),
        );
      }
      staffById[staff.id] = staff;
    }
    final facilityByKey = <String, FacilityState>{};
    for (final facility in facilities) {
      final key = facilityKey(facility.teamId, facility.kind);
      if (facilityByKey.containsKey(key)) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.financialDuplicate,
            path: 'finances.facilities',
            message:
                'duplicate ${facility.kind.jsonValue} facility for team '
                '${facility.teamId.value}',
          ),
        );
      }
      facilityByKey[key] = facility;
    }
    ValidationResult(issues).throwIfInvalid();
    return CareerFinances._(
      contracts: contractsById,
      schedules: schedulesById,
      teamFinances: teamsById,
      staffCommitments: staffById,
      facilityByKey: facilityByKey,
    );
  }

  factory CareerFinances.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is! int ||
        schemaVersion < 1 ||
        schemaVersion > FinancialRules.financialSchemaVersion) {
      throw FormatException(
        'Unsupported financial schema version: $schemaVersion '
        '(supported: 1..${FinancialRules.financialSchemaVersion})',
      );
    }
    List<dynamic> requireList(String key) {
      final raw = json[key];
      if (raw is! List) {
        throw FormatException('Missing or invalid $key in finances');
      }
      return raw;
    }

    T parse<T>(
      Object? raw,
      T Function(Map<String, dynamic>) parser,
      String key,
    ) {
      if (raw is! Map<String, dynamic>) {
        throw FormatException('Malformed $key entry in finances');
      }
      return parser(raw);
    }

    return CareerFinances(
      contracts: [
        for (final raw in requireList('contracts'))
          parse(raw, PlayerContract.fromJson, 'contracts'),
      ],
      schedules: [
        for (final raw in requireList('schedules'))
          parse(raw, ContractFinancials.fromJson, 'schedules'),
      ],
      teamFinances: [
        for (final raw in requireList('teamFinances'))
          parse(raw, TeamFinances.fromJson, 'teamFinances'),
      ],
      staffCommitments: [
        for (final raw in requireList('staffCommitments'))
          parse(raw, StaffCommitment.fromJson, 'staffCommitments'),
      ],
      facilities: [
        for (final raw in requireList('facilities'))
          parse(raw, FacilityState.fromJson, 'facilities'),
      ],
    );
  }

  final Map<String, PlayerContract> contracts;
  final Map<String, ContractFinancials> schedules;
  final Map<String, TeamFinances> teamFinances;
  final Map<String, StaffCommitment> staffCommitments;

  /// Keyed by `facilityKey(teamId, kind)`.
  final Map<String, FacilityState> facilities;

  static String facilityKey(TeamId teamId, FacilityKind kind) =>
      '${teamId.value}:${kind.jsonValue}';

  TeamFinances financesFor(TeamId teamId) =>
      teamFinances[teamId.value] ??
      (throw StateError('Missing finances for team ${teamId.value}'));

  PlayerContract? contractForPlayer(PlayerId playerId) {
    for (final contract in contracts.values) {
      if (contract.playerId == playerId) return contract;
    }
    return null;
  }

  ContractFinancials? scheduleFor(String contractId) => schedules[contractId];

  Iterable<ContractFinancials> schedulesForTeam(TeamId teamId) =>
      schedules.values.where((schedule) => schedule.teamId == teamId);

  int capPayrollFor(TeamId teamId, int year) => schedulesForTeam(teamId)
      .where((schedule) {
        final contract = contracts[schedule.contractId];
        return contract != null && contract.category == RosterCategory.standard;
      })
      .fold<int>(
        0,
        (sum, schedule) => sum + (schedule.salaryForYear(year) ?? 0),
      );

  int twoWayPayrollFor(TeamId teamId, int year) => schedulesForTeam(teamId)
      .where((schedule) {
        final contract = contracts[schedule.contractId];
        return contract != null && contract.category == RosterCategory.twoWay;
      })
      .fold<int>(
        0,
        (sum, schedule) => sum + (schedule.salaryForYear(year) ?? 0),
      );

  int cashPayrollFor(TeamId teamId, int year) =>
      capPayrollFor(teamId, year) + twoWayPayrollFor(teamId, year);

  int operatingCommitmentsFor(TeamId teamId) {
    var total = 0;
    for (final staff in staffCommitments.values) {
      if (staff.teamId == teamId) total += staff.annualCost;
    }
    for (final facility in facilities.values) {
      if (facility.teamId == teamId) total += facility.maintenancePerYear;
    }
    return total;
  }

  int projectedEndOfSeasonCash(TeamId teamId, int year) {
    final finances = financesFor(teamId);
    return finances.cash +
        finances.revenueBaseline -
        cashPayrollFor(teamId, year) -
        operatingCommitmentsFor(teamId);
  }

  /// Cross-record validation against the career state that owns this money.
  void validate({
    required League league,
    required LeagueCareerProfiles careerProfiles,
    required RookieSigningLedger rookieSigningLedger,
    required int currentYear,
  }) {
    final issues = <ValidationIssue>[];
    final teamsById = {for (final team in league.teams) team.id.value: team};

    void checkRecord(Iterable<ValidationIssue> recordIssues) =>
        issues.addAll(recordIssues);

    for (final contract in contracts.values) {
      checkRecord(contract.validationIssues());
    }
    for (final schedule in schedules.values) {
      checkRecord(schedule.validationIssues());
      if (!contracts.containsKey(schedule.contractId)) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.scheduleMissing,
            path: 'finances.schedules',
            message: 'schedule ${schedule.contractId} has no matching contract',
          ),
        );
      }
    }
    for (final finances in teamFinances.values) {
      checkRecord(finances.validationIssues());
    }
    for (final staff in staffCommitments.values) {
      checkRecord(staff.validationIssues());
      if (!staff.isActiveIn(currentYear)) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.staffInvalid,
            path: 'finances.staffCommitments',
            message:
                'staff commitment ${staff.id} is not active in year '
                '$currentYear',
          ),
        );
      }
    }
    for (final facility in facilities.values) {
      checkRecord(facility.validationIssues());
    }

    for (final team in league.teams) {
      if (!teamFinances.containsKey(team.id.value)) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.financialTeamInvalid,
            path: 'finances.teamFinances',
            message: 'missing finances for team ${team.id.value}',
          ),
        );
      }
    }
    for (final teamId in teamFinances.keys) {
      if (!teamsById.containsKey(teamId)) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.financialTeamInvalid,
            path: 'finances.teamFinances',
            message: 'finances reference unknown team $teamId',
          ),
        );
      }
    }
    for (final staff in staffCommitments.values) {
      if (!teamsById.containsKey(staff.teamId.value)) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.staffInvalid,
            path: 'finances.staffCommitments',
            message:
                'staff commitment references unknown team '
                '${staff.teamId.value}',
          ),
        );
      }
    }
    for (final facility in facilities.values) {
      if (!teamsById.containsKey(facility.teamId.value)) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.facilityInvalid,
            path: 'finances.facilities',
            message:
                'facility references unknown team '
                '${facility.teamId.value}',
          ),
        );
      }
    }

    // Roster ownership: exactly one active contract per player.
    final contractByPlayer = <String, List<PlayerContract>>{};
    for (final contract in contracts.values) {
      (contractByPlayer[contract.playerId.value] ??= []).add(contract);
    }
    final rosterCategoryByPlayer = <String, RosterCategory>{};
    final rosterTeamByPlayer = <String, TeamId>{};
    for (final team in league.teams) {
      for (final player in team.players) {
        rosterCategoryByPlayer[player.id.value] = team.roster.categoryOf(
          player.id,
        );
        rosterTeamByPlayer[player.id.value] = team.id;
      }
    }
    for (final playerId in rosterCategoryByPlayer.keys) {
      final candidates = (contractByPlayer[playerId] ?? const [])
          .where((contract) => contract.isActiveIn(currentYear))
          .toList();
      if (candidates.length != 1) {
        issues.add(
          ValidationIssue(
            code: candidates.isEmpty
                ? ValidationCode.contractMissing
                : ValidationCode.contractDuplicate,
            path: 'finances.contracts',
            message:
                'player $playerId must have exactly one active contract '
                'in year $currentYear, found ${candidates.length}',
          ),
        );
      }
    }
    for (final entry in contractByPlayer.entries) {
      final hasActiveContract = entry.value.any(
        (contract) => contract.isActiveIn(currentYear),
      );
      if (hasActiveContract && !rosterCategoryByPlayer.containsKey(entry.key)) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.financialOwnershipMismatch,
            path: 'finances.contracts',
            message:
                'active contract for player ${entry.key} outside any roster',
          ),
        );
      }
    }

    final ledgerByPlayer = {
      for (final contract in rookieSigningLedger.contracts.values)
        contract.playerId.value: contract,
    };
    final ledgerByRookieId = {
      for (final contract in rookieSigningLedger.contracts.values)
        contract.id: contract,
    };
    final linkedRookieContracts = <String>{};

    for (final contract in contracts.values) {
      final playerId = contract.playerId.value;
      final rosterTeam = rosterTeamByPlayer[playerId];
      final rosterCategory = rosterCategoryByPlayer[playerId];
      final player = _playerById(league, contract.playerId);
      final profile = careerProfiles.forPlayer(contract.playerId);
      final schedule = schedules[contract.id];
      if (schedule == null) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.scheduleMissing,
            path: 'finances.schedules',
            message: 'contract ${contract.id} has no financial schedule',
          ),
        );
        continue;
      }
      if (rosterTeam == null || rosterCategory == null) {
        continue;
      }
      if (contract.teamId != rosterTeam) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.financialOwnershipMismatch,
            path: 'finances.contracts',
            message:
                'contract ${contract.id} team ${contract.teamId.value} does '
                'not match roster team ${rosterTeam.value}',
          ),
        );
      }
      if (contract.category != rosterCategory) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.financialOwnershipMismatch,
            path: 'finances.contracts',
            message:
                'contract ${contract.id} category ${contract.category.jsonValue} '
                'does not match roster category ${rosterCategory.jsonValue}',
          ),
        );
      }
      if (!contract.isActiveIn(currentYear)) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.contractInvalid,
            path: 'finances.contracts',
            message:
                'contract ${contract.id} is not active in year $currentYear',
          ),
        );
      }
      if (schedule.playerId != contract.playerId ||
          schedule.teamId != contract.teamId ||
          schedule.source != contract.source) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.financialOwnershipMismatch,
            path: 'finances.schedules',
            message:
                'schedule ${schedule.contractId} metadata does not match '
                'its contract',
          ),
        );
      }
      if (schedule.durationYears != contract.durationYears ||
          schedule.signedYear != contract.startYear) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.scheduleInvalid,
            path: 'finances.schedules',
            message:
                'schedule ${schedule.contractId} length/start year does not '
                'match contract duration/start year',
          ),
        );
      }
      if (schedule.guaranteedYears != schedule.durationYears) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.scheduleInvalid,
            path: 'finances.schedules',
            message: 'v1 requires full guarantees for ${schedule.contractId}',
          ),
        );
      }
      _validateSalaries(
        issues: issues,
        contract: contract,
        schedule: schedule,
        player: player,
        profile: profile,
        rookieContract: ledgerByPlayer[playerId],
      );
      if (contract.source == ContractSource.rookie) {
        final rookieId = contract.rookieContractId;
        final rookie = rookieId == null ? null : ledgerByRookieId[rookieId];
        if (rookie == null) {
          issues.add(
            ValidationIssue(
              code: ValidationCode.rookieLinkMismatch,
              path: 'finances.contracts',
              message:
                  'rookie contract ${contract.id} has no matching historical '
                  'RookieContract',
            ),
          );
        } else {
          linkedRookieContracts.add(rookie.id);
          if (rookie.playerId != contract.playerId ||
              rookie.teamId != contract.teamId ||
              rookie.category != contract.category ||
              rookie.startYear != contract.startYear ||
              rookie.durationYears != contract.durationYears) {
            issues.add(
              ValidationIssue(
                code: ValidationCode.rookieLinkMismatch,
                path: 'finances.contracts',
                message:
                    'rookie contract ${contract.id} does not preserve '
                    'RookieContract ${rookie.id}',
              ),
            );
          }
        }
      }
    }

    for (final rookie in rookieSigningLedger.contracts.values) {
      if (!linkedRookieContracts.contains(rookie.id)) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.rookieLinkMismatch,
            path: 'finances.contracts',
            message:
                'signed RookieContract ${rookie.id} has no linked '
                'PlayerContract',
          ),
        );
      }
    }

    for (final team in league.teams) {
      final finances = teamFinances[team.id.value];
      if (finances == null) continue;
      if (finances.season != currentYear) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.financialTeamInvalid,
            path: 'finances.teamFinances',
            message:
                'team ${team.id.value} finances season ${finances.season} '
                'does not match career year $currentYear',
          ),
        );
      }
      final capPayroll = capPayrollFor(team.id, currentYear);
      if (capPayroll > FinancialRules.salaryCap) {
        if (!finances.capGrandfathered) {
          issues.add(
            ValidationIssue(
              code: ValidationCode.capBreach,
              path: 'finances.teamFinances',
              message:
                  'team ${team.id.value} cap payroll $capPayroll exceeds '
                  '${FinancialRules.salaryCap}',
            ),
          );
        } else if (capPayroll >
            finances.grandfatheredPayroll +
                FinancialRules.maximumReliefOverage) {
          issues.add(
            ValidationIssue(
              code: ValidationCode.capBreach,
              path: 'finances.teamFinances',
              message:
                  'team ${team.id.value} grandfathered payroll $capPayroll '
                  'exceeds baseline ${finances.grandfatheredPayroll} plus '
                  '${FinancialRules.maximumReliefOverage}',
            ),
          );
        }
      }
      final twoWayPayroll = twoWayPayrollFor(team.id, currentYear);
      final cashPayroll = capPayroll + twoWayPayroll;
      final operating = operatingCommitmentsFor(team.id);
      if (operating > finances.operatingBudget) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.budgetBreach,
            path: 'finances.teamFinances',
            message:
                'team ${team.id.value} operating commitments $operating '
                'exceed budget ${finances.operatingBudget}',
          ),
        );
      }
      final projected =
          finances.cash + finances.revenueBaseline - cashPayroll - operating;
      if (projected < 0) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.cashInsufficient,
            path: 'finances.teamFinances',
            message:
                'team ${team.id.value} projected year-$currentYear cash '
                '$projected is negative',
          ),
        );
      }
    }

    ValidationResult(issues).throwIfInvalid();
  }

  void _validateSalaries({
    required List<ValidationIssue> issues,
    required PlayerContract contract,
    required ContractFinancials schedule,
    required Player? player,
    required PlayerCareerProfile? profile,
    required RookieContract? rookieContract,
  }) {
    final salaries = schedule.annualSalaries;
    if (contract.source == ContractSource.legacy && profile != null) {
      final expectedDuration = FinancialRules.legacyDurationForAge(profile.age);
      if (contract.durationYears != expectedDuration) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.contractInvalid,
            path: 'finances.contracts',
            message:
                'legacy contract ${contract.id} duration '
                '${contract.durationYears} must be $expectedDuration for '
                'age ${profile.age}',
          ),
        );
      }
    }
    if (contract.category == RosterCategory.twoWay) {
      for (var i = 0; i < salaries.length; i++) {
        if (salaries[i] != FinancialRules.twoWaySalary) {
          issues.add(
            ValidationIssue(
              code: ValidationCode.scheduleInvalid,
              path: 'finances.schedules',
              message:
                  'two-way salary ${salaries[i]} in ${schedule.contractId} '
                  'must be ${FinancialRules.twoWaySalary}',
            ),
          );
        }
      }
    } else {
      for (var i = 0; i < salaries.length; i++) {
        if (salaries[i] < FinancialRules.minimumSalary ||
            salaries[i] > FinancialRules.maximumSalary) {
          issues.add(
            ValidationIssue(
              code: ValidationCode.salaryOutOfBounds,
              path: 'finances.schedules',
              message:
                  'salary ${salaries[i]} in ${schedule.contractId} is outside '
                  '${FinancialRules.minimumSalary}..'
                  '${FinancialRules.maximumSalary}',
            ),
          );
        }
      }
    }

    final expected = switch (contract.source) {
      ContractSource.legacy => _expectedLegacy(
        contract: contract,
        player: player,
        profile: profile,
      ),
      ContractSource.rookie => _expectedRookie(
        contract: contract,
        rookieContract: rookieContract,
      ),
      _ => null,
    };
    if (expected != null) {
      if (expected.length != salaries.length) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.scheduleInvalid,
            path: 'finances.schedules',
            message:
                'schedule ${schedule.contractId} must contain '
                '${expected.length} years',
          ),
        );
      } else {
        for (var i = 0; i < expected.length; i++) {
          if (expected[i] != salaries[i]) {
            issues.add(
              ValidationIssue(
                code: ValidationCode.scheduleInvalid,
                path: 'finances.schedules',
                message:
                    'salary year ${i + 1} in ${schedule.contractId} must be '
                    '${expected[i]}, got ${salaries[i]}',
              ),
            );
          }
        }
      }
    } else if (contract.category == RosterCategory.standard &&
        contract.source != ContractSource.legacy &&
        contract.source != ContractSource.rookie) {
      for (var i = 1; i < salaries.length; i++) {
        final expectedRaise = FinancialRules.raiseStandardSalary(
          salaries[i - 1],
        );
        if (salaries[i] != expectedRaise) {
          issues.add(
            ValidationIssue(
              code: ValidationCode.scheduleInvalid,
              path: 'finances.schedules',
              message:
                  'salary year ${i + 1} in ${schedule.contractId} must apply '
                  'the 5% raise ($expectedRaise)',
            ),
          );
        }
      }
    }
  }

  List<int>? _expectedLegacy({
    required PlayerContract contract,
    required Player? player,
    required PlayerCareerProfile? profile,
  }) {
    if (player == null || profile == null) return null;
    final duration = FinancialRules.legacyDurationForAge(profile.age);
    if (contract.durationYears != duration) return null;
    if (contract.category == RosterCategory.twoWay) {
      return FinancialRules.twoWaySchedule(duration);
    }
    return FinancialRules.standardSchedule(
      FinancialRules.legacySalaryForOverall(player.attributes.overallRating),
      duration,
    );
  }

  List<int>? _expectedRookie({
    required PlayerContract contract,
    required RookieContract? rookieContract,
  }) {
    if (rookieContract == null) return null;
    return contract.category == RosterCategory.twoWay
        ? FinancialRules.twoWaySchedule(contract.durationYears)
        : FinancialRules.standardSchedule(
            FinancialRules.rookieSalaryForPick(rookieContract.overallPick),
            contract.durationYears,
          );
  }

  static Player? _playerById(League league, PlayerId playerId) {
    for (final team in league.teams) {
      for (final player in team.players) {
        if (player.id == playerId) return player;
      }
    }
    return null;
  }

  /// Deterministic canonical JSON: every list is sorted by its stable key.
  Map<String, Object?> toJson() {
    final contractList = contracts.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final scheduleList = schedules.values.toList()
      ..sort((a, b) => a.contractId.compareTo(b.contractId));
    final teamList = teamFinances.values.toList()
      ..sort((a, b) => a.teamId.value.compareTo(b.teamId.value));
    final staffList = staffCommitments.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final facilityList = facilities.values.toList()
      ..sort((a, b) {
        final byTeam = a.teamId.value.compareTo(b.teamId.value);
        return byTeam != 0 ? byTeam : a.kind.index.compareTo(b.kind.index);
      });
    return {
      'schemaVersion': FinancialRules.financialSchemaVersion,
      'teamFinances': [for (final entry in teamList) entry.toJson()],
      'contracts': [for (final entry in contractList) entry.toJson()],
      'schedules': [for (final entry in scheduleList) entry.toJson()],
      'staffCommitments': [for (final entry in staffList) entry.toJson()],
      'facilities': [for (final entry in facilityList) entry.toJson()],
    };
  }
}
