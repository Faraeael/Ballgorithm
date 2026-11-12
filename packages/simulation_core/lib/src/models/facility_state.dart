import '../finance/financial_rules.dart';
import '../finance/money.dart';
import '../validation/validation_result.dart';
import 'ids.dart';

/// Explicit facility inventory and its recurring maintenance cost.
///
/// T08C models money only; facility gameplay effects are not implemented.
final class FacilityState {
  FacilityState({
    required this.teamId,
    required this.kind,
    required this.level,
    required this.maintenancePerYear,
  }) {
    requireValid();
  }

  factory FacilityState.fromJson(Map<String, dynamic> json) {
    final teamId = json['teamId'];
    final kind = json['facility'];
    final level = json['level'];
    final maintenancePerYear = json['maintenancePerYear'];
    if (teamId is! String ||
        kind is! String ||
        level is! int ||
        maintenancePerYear is! int) {
      throw const FormatException('Malformed FacilityState JSON');
    }
    return FacilityState(
      teamId: TeamId(teamId),
      kind: FacilityKind.fromJson(kind),
      level: level,
      maintenancePerYear: maintenancePerYear,
    )..requireValid();
  }

  final TeamId teamId;
  final FacilityKind kind;
  final int level;
  final int maintenancePerYear;

  List<ValidationIssue> validationIssues() {
    final issues = <ValidationIssue>[];
    if (teamId.value.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.facilityInvalid,
          path: 'facility.teamId',
          message: 'facility requires a team id',
        ),
      );
    }
    if (level < FinancialRules.minFacilityLevel ||
        level > FinancialRules.maxFacilityLevel) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.facilityInvalid,
          path: 'facility.level',
          message:
              'facility level must be '
              '${FinancialRules.minFacilityLevel}..'
              '${FinancialRules.maxFacilityLevel}, got $level',
        ),
      );
    }
    final expectedMaintenance = FinancialRules.facilityMaintenance(kind, level);
    if (maintenancePerYear != expectedMaintenance) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.facilityInvalid,
          path: 'facility.maintenancePerYear',
          message:
              'facility maintenance must be $expectedMaintenance for '
              '${kind.jsonValue} level $level, got $maintenancePerYear',
        ),
      );
    }
    final costIssue = Money.issueForBalance(
      maintenancePerYear,
      'facility.maintenancePerYear',
    );
    if (costIssue != null) issues.add(costIssue);
    return issues;
  }

  void requireValid() {
    ValidationResult(validationIssues()).throwIfInvalid();
  }

  Map<String, Object?> toJson() => {
    'teamId': teamId.value,
    'facility': kind.jsonValue,
    'level': level,
    'maintenancePerYear': maintenancePerYear,
  };
}
