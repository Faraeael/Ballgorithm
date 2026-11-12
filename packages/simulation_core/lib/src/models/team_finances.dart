import '../finance/financial_rules.dart';
import '../finance/money.dart';
import '../validation/validation_result.dart';
import 'ids.dart';

/// Persisted franchise money: budget, cash, revenue baseline and season.
final class TeamFinances {
  TeamFinances({
    required this.teamId,
    required this.operatingBudget,
    required this.cash,
    required this.revenueBaseline,
    required this.season,
    this.capGrandfathered = false,
    this.grandfatheredPayroll = 0,
  }) {
    requireValid();
  }

  factory TeamFinances.fromJson(Map<String, dynamic> json) {
    final teamId = json['teamId'];
    final operatingBudget = json['operatingBudget'];
    final cash = json['cash'];
    final revenueBaseline = json['revenueBaseline'];
    final season = json['season'];
    final capGrandfathered = json['capGrandfathered'];
    final grandfatheredPayroll = json['grandfatheredPayroll'];
    if (teamId is! String ||
        operatingBudget is! int ||
        cash is! int ||
        revenueBaseline is! int ||
        season is! int ||
        (capGrandfathered != null && capGrandfathered is! bool) ||
        (grandfatheredPayroll != null && grandfatheredPayroll is! int)) {
      throw const FormatException('Malformed TeamFinances JSON');
    }
    return TeamFinances(
      teamId: TeamId(teamId),
      operatingBudget: operatingBudget,
      cash: cash,
      revenueBaseline: revenueBaseline,
      season: season,
      capGrandfathered: capGrandfathered == true,
      grandfatheredPayroll: grandfatheredPayroll as int? ?? 0,
    )..requireValid();
  }

  final TeamId teamId;
  final int operatingBudget;
  final int cash;
  final int revenueBaseline;
  final int season;

  /// True only for a migrated franchise whose payroll exceeded the cap.
  final bool capGrandfathered;

  /// Payroll committed when grandfathering began. Stored payroll may not rise
  /// above this baseline plus the bounded relief overage.
  final int grandfatheredPayroll;

  List<ValidationIssue> validationIssues() {
    final issues = <ValidationIssue>[];
    if (teamId.value.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.financialTeamInvalid,
          path: 'finances.teamId',
          message: 'team finances require a team id',
        ),
      );
    }
    final budgetIssue = Money.issueForBalance(
      operatingBudget,
      'finances.operatingBudget',
    );
    if (budgetIssue != null) issues.add(budgetIssue);
    final cashIssue = Money.issueForBalance(cash, 'finances.cash');
    if (cashIssue != null) issues.add(cashIssue);
    final revenueIssue = Money.issueForBalance(
      revenueBaseline,
      'finances.revenueBaseline',
    );
    if (revenueIssue != null) issues.add(revenueIssue);
    if (season < 1) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.financialTeamInvalid,
          path: 'finances.season',
          message: 'finances season must be >= 1, got $season',
        ),
      );
    }
    if (operatingBudget > FinancialRules.maximumBalance) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.moneyInvalid,
          path: 'finances.operatingBudget',
          message: 'operating budget exceeds the money bound',
        ),
      );
    }
    if (grandfatheredPayroll < 0 ||
        grandfatheredPayroll > FinancialRules.maximumBalance) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.moneyInvalid,
          path: 'finances.grandfatheredPayroll',
          message:
              'grandfathered payroll must be within the money bound, '
              'got $grandfatheredPayroll',
        ),
      );
    }
    if (capGrandfathered && grandfatheredPayroll <= FinancialRules.salaryCap) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.financialTeamInvalid,
          path: 'finances.grandfatheredPayroll',
          message:
              'a grandfathered franchise requires the over-cap payroll '
              'baseline, got $grandfatheredPayroll',
        ),
      );
    }
    return issues;
  }

  void requireValid() {
    ValidationResult(validationIssues()).throwIfInvalid();
  }

  Map<String, Object?> toJson() => {
    'teamId': teamId.value,
    'operatingBudget': operatingBudget,
    'cash': cash,
    'revenueBaseline': revenueBaseline,
    'season': season,
    'capGrandfathered': capGrandfathered,
    'grandfatheredPayroll': grandfatheredPayroll,
  };
}
