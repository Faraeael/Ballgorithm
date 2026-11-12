import '../validation/validation_result.dart';
import 'ids.dart';
import 'player_contract.dart';

/// The only source of salary money for one [PlayerContract].
///
/// `annualSalaries` has exactly one integer Credit Unit entry per contract
/// year. The schedule is immutable once created.
final class ContractFinancials {
  ContractFinancials({
    required this.contractId,
    required this.playerId,
    required this.teamId,
    required List<int> annualSalaries,
    required this.guaranteedYears,
    required this.source,
    required this.signedYear,
  }) : annualSalaries = List.unmodifiable(annualSalaries) {
    requireValid();
  }

  factory ContractFinancials.fromJson(Map<String, dynamic> json) {
    final contractId = json['contractId'];
    final playerId = json['playerId'];
    final teamId = json['teamId'];
    final rawSalaries = json['annualSalaries'];
    final guaranteedYears = json['guaranteedYears'];
    final source = json['source'];
    final signedYear = json['signedYear'];
    if (contractId is! String ||
        playerId is! String ||
        teamId is! String ||
        rawSalaries is! List ||
        guaranteedYears is! int ||
        source is! String ||
        signedYear is! int) {
      throw const FormatException('Malformed ContractFinancials JSON');
    }
    final salaries = <int>[];
    for (final rawSalary in rawSalaries) {
      if (rawSalary is! int) {
        throw const FormatException('Malformed contract salary entry');
      }
      salaries.add(rawSalary);
    }
    return ContractFinancials(
      contractId: contractId,
      playerId: PlayerId(playerId),
      teamId: TeamId(teamId),
      annualSalaries: salaries,
      guaranteedYears: guaranteedYears,
      source: ContractSource.fromJson(source),
      signedYear: signedYear,
    )..requireValid();
  }

  final String contractId;
  final PlayerId playerId;
  final TeamId teamId;
  final List<int> annualSalaries;
  final int guaranteedYears;
  final ContractSource source;
  final int signedYear;

  int get durationYears => annualSalaries.length;

  /// Salary due in [year], or null when the schedule does not cover it.
  int? salaryForYear(int year) {
    final index = year - signedYear;
    if (index < 0 || index >= annualSalaries.length) return null;
    return annualSalaries[index];
  }

  List<ValidationIssue> validationIssues() {
    final issues = <ValidationIssue>[];
    if (contractId.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.scheduleInvalid,
          path: 'financials.contractId',
          message: 'schedule contract id must not be empty',
        ),
      );
    }
    if (playerId.value.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.scheduleInvalid,
          path: 'financials.playerId',
          message: 'schedule player id must not be empty',
        ),
      );
    }
    if (teamId.value.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.scheduleInvalid,
          path: 'financials.teamId',
          message: 'schedule team id must not be empty',
        ),
      );
    }
    if (signedYear < 1) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.scheduleInvalid,
          path: 'financials.signedYear',
          message: 'schedule signedYear must be >= 1, got $signedYear',
        ),
      );
    }
    if (annualSalaries.isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.scheduleInvalid,
          path: 'financials.annualSalaries',
          message: 'schedule must contain at least one salary year',
        ),
      );
    }
    if (guaranteedYears < 1 || guaranteedYears > annualSalaries.length) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.scheduleInvalid,
          path: 'financials.guaranteedYears',
          message:
              'guaranteedYears must be in 1..${annualSalaries.length}, '
              'got $guaranteedYears',
        ),
      );
    }
    for (var i = 0; i < annualSalaries.length; i++) {
      final salary = annualSalaries[i];
      if (salary < 0) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.scheduleInvalid,
            path: 'financials.annualSalaries[$i]',
            message: 'salary must be non-negative, got $salary',
          ),
        );
      }
    }
    return issues;
  }

  void requireValid() {
    ValidationResult(validationIssues()).throwIfInvalid();
  }

  Map<String, Object?> toJson() => {
    'contractId': contractId,
    'playerId': playerId.value,
    'teamId': teamId.value,
    'annualSalaries': annualSalaries,
    'guaranteedYears': guaranteedYears,
    'source': source.jsonValue,
    'signedYear': signedYear,
  };
}
