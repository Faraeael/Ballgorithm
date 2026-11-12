import '../finance/financial_rules.dart';
import '../finance/money.dart';
import '../validation/validation_result.dart';
import 'ids.dart';

/// One explicit recurring staff commitment.
final class StaffCommitment {
  StaffCommitment({
    required this.id,
    required this.teamId,
    required this.category,
    required this.tier,
    required this.annualCost,
    required this.startYear,
    required this.durationYears,
  }) {
    requireValid();
  }

  factory StaffCommitment.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final teamId = json['teamId'];
    final category = json['category'];
    final tier = json['tier'];
    final annualCost = json['annualCost'];
    final startYear = json['startYear'];
    final durationYears = json['durationYears'];
    if (id is! String ||
        teamId is! String ||
        category is! String ||
        tier is! String ||
        annualCost is! int ||
        startYear is! int ||
        durationYears is! int) {
      throw const FormatException('Malformed StaffCommitment JSON');
    }
    return StaffCommitment(
      id: id,
      teamId: TeamId(teamId),
      category: StaffCategory.fromJson(category),
      tier: StaffTier.fromJson(tier),
      annualCost: annualCost,
      startYear: startYear,
      durationYears: durationYears,
    )..requireValid();
  }

  static String idFor(TeamId teamId, StaffCategory category, int index) =>
      'staff-${teamId.value}-${category.jsonValue}-$index';

  static const int maxDurationYears = 5;

  final String id;
  final TeamId teamId;
  final StaffCategory category;
  final StaffTier tier;
  final int annualCost;
  final int startYear;
  final int durationYears;

  bool isActiveIn(int year) =>
      year >= startYear && year < startYear + durationYears;

  List<ValidationIssue> validationIssues() {
    final issues = <ValidationIssue>[];
    if (id.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.staffInvalid,
          path: 'staff.id',
          message: 'staff commitment requires an id',
        ),
      );
    }
    if (teamId.value.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.staffInvalid,
          path: 'staff.teamId',
          message: 'staff commitment requires a team id',
        ),
      );
    }
    final costIssue = Money.issueForBalance(annualCost, 'staff.annualCost');
    if (costIssue != null) issues.add(costIssue);
    if (startYear < 1) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.staffInvalid,
          path: 'staff.startYear',
          message: 'staff startYear must be >= 1, got $startYear',
        ),
      );
    }
    if (durationYears < 1 || durationYears > maxDurationYears) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.staffInvalid,
          path: 'staff.durationYears',
          message:
              'staff duration must be 1..$maxDurationYears, '
              'got $durationYears',
        ),
      );
    }
    return issues;
  }

  void requireValid() {
    ValidationResult(validationIssues()).throwIfInvalid();
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'teamId': teamId.value,
    'category': category.jsonValue,
    'tier': tier.jsonValue,
    'annualCost': annualCost,
    'startYear': startYear,
    'durationYears': durationYears,
  };
}
