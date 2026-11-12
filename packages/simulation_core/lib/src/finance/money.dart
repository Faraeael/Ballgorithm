import '../validation/validation_result.dart';
import 'financial_rules.dart';

/// Integer-only Credit Unit helpers shared by every financial record.
abstract final class Money {
  static bool isValidBalance(int value) =>
      value >= FinancialRules.minimumBalance &&
      value <= FinancialRules.maximumBalance;

  static ValidationIssue? issueForBalance(int value, String path) {
    if (isValidBalance(value)) return null;
    return ValidationIssue(
      code: ValidationCode.moneyInvalid,
      path: path,
      message:
          'money must be an integer in '
          '${FinancialRules.minimumBalance}..${FinancialRules.maximumBalance}, '
          'got $value',
    );
  }

  static void requireBalance(int value, String path) {
    final issue = issueForBalance(value, path);
    if (issue != null) throw DomainValidationException([issue]);
  }

  /// Adds two stored balances, rejecting results outside the money bounds.
  static int add(int left, int right, String path) {
    final sum = left + right;
    requireBalance(sum, path);
    return sum;
  }

  static bool isNonNegative(int value) => value >= 0;
}
