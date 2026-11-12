import '../models/contract_financials.dart';
import '../models/ids.dart';
import '../models/player_contract.dart';
import '../models/rookie_contract.dart';
import '../models/roster_category.dart';
import '../validation/validation_result.dart';
import 'career_finances.dart';
import 'financial_rules.dart';

/// The only authorized runtime mutation boundary for financial records.
///
/// T08C uses it for rookie signing. T08D acquisition must add a `freeAgent`
/// contract through [addContract] with an explicit agreed first-year salary;
/// it must never regenerate legacy terms.
abstract final class FinancialTransactions {
  /// Adds one employment contract and its schedule, preserving every existing
  /// record. Rejects a second overlapping contract for the same player.
  static CareerFinances addContract({
    required CareerFinances finances,
    required PlayerContract contract,
    required List<int> annualSalaries,
  }) {
    if (annualSalaries.length != contract.durationYears) {
      throw DomainValidationException([
        ValidationIssue(
          code: ValidationCode.scheduleInvalid,
          path: 'finances.schedules',
          message:
              'contract ${contract.id} requires ${contract.durationYears} '
              'salary years, got ${annualSalaries.length}',
        ),
      ]);
    }
    for (final existing in finances.contracts.values) {
      if (existing.playerId != contract.playerId) continue;
      if (_overlaps(existing, contract)) {
        throw DomainValidationException([
          ValidationIssue(
            code: ValidationCode.contractDuplicate,
            path: 'finances.contracts',
            message:
                'player ${contract.playerId.value} already has an overlapping '
                'contract ${existing.id}',
          ),
        ]);
      }
    }
    return CareerFinances(
      contracts: [...finances.contracts.values, contract],
      schedules: [
        ...finances.schedules.values,
        ContractFinancials(
          contractId: contract.id,
          playerId: contract.playerId,
          teamId: contract.teamId,
          annualSalaries: annualSalaries,
          guaranteedYears: contract.durationYears,
          source: contract.source,
          signedYear: contract.startYear,
        ),
      ],
      teamFinances: finances.teamFinances.values,
      staffCommitments: finances.staffCommitments.values,
      facilities: finances.facilities.values,
    );
  }

  /// Creates the linked employment record for a historical rookie signing.
  static CareerFinances signRookie({
    required CareerFinances finances,
    required RookieContract rookieContract,
  }) {
    if (!RookieContract.isSupportedCategory(rookieContract.category)) {
      throw ArgumentError.value(
        rookieContract.category.jsonValue,
        'category',
        'Unsupported rookie contract category',
      );
    }
    final contract = PlayerContract(
      id: PlayerContract.idFor(
        rookieContract.playerId,
        rookieContract.startYear,
      ),
      playerId: rookieContract.playerId,
      teamId: rookieContract.teamId,
      category: rookieContract.category,
      startYear: rookieContract.startYear,
      durationYears: rookieContract.durationYears,
      source: ContractSource.rookie,
      rookieContractId: rookieContract.id,
    );
    final salaries = rookieContract.category == RosterCategory.twoWay
        ? FinancialRules.twoWaySchedule(rookieContract.durationYears)
        : FinancialRules.standardSchedule(
            FinancialRules.rookieSalaryForPick(rookieContract.overallPick),
            rookieContract.durationYears,
          );
    return addContract(
      finances: finances,
      contract: contract,
      annualSalaries: salaries,
    );
  }

  static bool _overlaps(PlayerContract left, PlayerContract right) =>
      left.startYear < right.startYear + right.durationYears &&
      right.startYear < left.startYear + left.durationYears;

  /// Convenience for a future free-agent contract. Not called in T08C.
  static PlayerContract futureFreeAgentContract({
    required PlayerId playerId,
    required TeamId teamId,
    required RosterCategory category,
    required int startYear,
    required int durationYears,
  }) => PlayerContract(
    id: PlayerContract.idFor(playerId, startYear),
    playerId: playerId,
    teamId: teamId,
    category: category,
    startYear: startYear,
    durationYears: durationYears,
    source: ContractSource.freeAgent,
  );
}
