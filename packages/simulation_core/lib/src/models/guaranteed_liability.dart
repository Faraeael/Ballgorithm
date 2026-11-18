import '../finance/financial_rules.dart';
import '../validation/validation_result.dart';
import 'ids.dart';
import 'roster_category.dart';

/// Durable guaranteed salary obligation retained after a contracted player retires.
///
/// Preserves originating contract identity and exact future-year salary
/// obligations without keeping a retired player on an active roster.
final class GuaranteedLiability {
  GuaranteedLiability({
    required this.id,
    required this.originalContractId,
    required this.playerId,
    required this.teamId,
    required this.originalCategory,
    required this.retirementYear,
    required Map<int, int> salariesByYear,
  }) : salariesByYear = Map.unmodifiable({
         for (final year in salariesByYear.keys.toList()..sort())
           year: salariesByYear[year]!,
       }) {
    requireValid();
  }

  factory GuaranteedLiability.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final originalContractId = json['originalContractId'];
    final playerId = json['playerId'];
    final teamId = json['teamId'];
    final originalCategory = json['originalCategory'];
    final retirementYear = json['retirementYear'];
    final rawSalaries = json['salariesByYear'];
    if (id is! String ||
        originalContractId is! String ||
        playerId is! String ||
        teamId is! String ||
        originalCategory is! String ||
        retirementYear is! int ||
        rawSalaries is! Map<String, dynamic>) {
      throw const FormatException('Malformed GuaranteedLiability JSON');
    }
    final salariesByYear = <int, int>{};
    for (final entry in rawSalaries.entries) {
      final year = int.tryParse(entry.key);
      if (year == null || entry.value is! int) {
        throw const FormatException(
          'Malformed salariesByYear entry in GuaranteedLiability',
        );
      }
      salariesByYear[year] = entry.value as int;
    }
    return GuaranteedLiability(
      id: id,
      originalContractId: originalContractId,
      playerId: PlayerId(playerId),
      teamId: TeamId(teamId),
      originalCategory: RosterCategory.fromJson(originalCategory),
      retirementYear: retirementYear,
      salariesByYear: salariesByYear,
    );
  }

  static String idFor(String originalContractId) =>
      'liability-$originalContractId';

  final String id;
  final String originalContractId;
  final PlayerId playerId;
  final TeamId teamId;
  final RosterCategory originalCategory;
  final int retirementYear;
  final Map<int, int> salariesByYear;

  int salaryForYear(int year) => salariesByYear[year] ?? 0;

  bool hasObligationIn(int year) => (salariesByYear[year] ?? 0) > 0;

  int get totalObligation =>
      salariesByYear.values.fold<int>(0, (sum, v) => sum + v);

  List<ValidationIssue> validationIssues() {
    final issues = <ValidationIssue>[];
    if (id.trim().isEmpty || originalContractId.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.contractInvalid,
          path: 'finances.guaranteedLiabilities',
          message: 'guaranteed liability requires non-empty id and contractId',
        ),
      );
    }
    if (playerId.value.trim().isEmpty || teamId.value.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.financialOwnershipMismatch,
          path: 'finances.guaranteedLiabilities',
          message: 'guaranteed liability requires playerId and teamId',
        ),
      );
    }
    if (originalCategory == RosterCategory.trainingCamp) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.contractInvalid,
          path: 'finances.guaranteedLiabilities',
          message: 'trainingCamp category cannot carry guaranteed liability',
        ),
      );
    }
    if (retirementYear < 1) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.contractInvalid,
          path: 'finances.guaranteedLiabilities',
          message: 'retirementYear must be >= 1, got $retirementYear',
        ),
      );
    }
    if (salariesByYear.isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.scheduleInvalid,
          path: 'finances.guaranteedLiabilities',
          message: 'guaranteed liability requires at least one future salary',
        ),
      );
    }
    for (final entry in salariesByYear.entries) {
      if (entry.key <= retirementYear) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.scheduleInvalid,
            path: 'finances.guaranteedLiabilities',
            message:
                'guaranteed liability year ${entry.key} must be > '
                'retirementYear $retirementYear',
          ),
        );
      }
      if (entry.value < 1 || entry.value > FinancialRules.maximumSalary) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.salaryOutOfBounds,
            path: 'finances.guaranteedLiabilities',
            message:
                'guaranteed liability salary ${entry.value} out of bounds '
                '1..${FinancialRules.maximumSalary}',
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
    'id': id,
    'originalContractId': originalContractId,
    'playerId': playerId.value,
    'teamId': teamId.value,
    'originalCategory': originalCategory.jsonValue,
    'retirementYear': retirementYear,
    'salariesByYear': {
      for (final entry in salariesByYear.entries) '${entry.key}': entry.value,
    },
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GuaranteedLiability) return false;
    if (id != other.id ||
        originalContractId != other.originalContractId ||
        playerId != other.playerId ||
        teamId != other.teamId ||
        originalCategory != other.originalCategory ||
        retirementYear != other.retirementYear ||
        salariesByYear.length != other.salariesByYear.length) {
      return false;
    }
    for (final entry in salariesByYear.entries) {
      if (other.salariesByYear[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    originalContractId,
    playerId,
    teamId,
    originalCategory,
    retirementYear,
    Object.hashAll(
      salariesByYear.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}
