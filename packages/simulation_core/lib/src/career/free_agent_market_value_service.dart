import '../models/free_agent.dart';
import '../finance/financial_rules.dart';

/// Expected public role from observable ability.
enum ExpectedPlayerRole {
  starter('starter', 'Starter'),
  rotation('rotation', 'Rotation'),
  bench('bench', 'Bench'),
  developmental('developmental', 'Developmental');

  const ExpectedPlayerRole(this.jsonValue, this.displayName);

  final String jsonValue;
  final String displayName;
}

/// Public market estimate for one free agent.
final class MarketValuation {
  const MarketValuation({
    required this.estimatedAnnualSalary,
    required this.acceptableMinimum,
    required this.acceptableMaximum,
    required this.preferredDurationYears,
    required this.expectedRole,
    required this.explanation,
  });

  final int estimatedAnnualSalary;
  final int acceptableMinimum;
  final int acceptableMaximum;
  final int preferredDurationYears;
  final ExpectedPlayerRole expectedRole;
  final String explanation;
}

/// Deterministic, public-information-only free-agent valuation.
///
/// Inputs are limited to the public view: OVR, age, position and observable
/// attributes. Hidden potential, trajectory, progression and PRNG state are not
/// accessible by type.
final class FreeAgentMarketValueService {
  const FreeAgentMarketValueService();

  static const int _minimum = FinancialRules.minimumSalary;
  static const int _maximum = FinancialRules.maximumSalary;

  MarketValuation estimate(PublicFreeAgentView player) {
    final preferred = preferredDuration(player);
    final value = annualValue(player, preferred);
    final scheduleCap = maxYearOneForDuration(preferred);
    final minimum = _round((value * 8500) ~/ 10000);
    final maximum = _round((value * 11500) ~/ 10000);
    return MarketValuation(
      estimatedAnnualSalary: value,
      acceptableMinimum: _clamp(minimum),
      acceptableMaximum: _clamp(maximum > scheduleCap ? scheduleCap : maximum),
      preferredDurationYears: preferred,
      expectedRole: expectedRole(player),
      explanation:
          'Public OVR ${player.overallRating}, age ${player.age}, '
          '${player.position.shortName}: ${expectedRole(player).displayName} '
          'market estimate ${value.toString()} CU; preferred '
          '$preferred-year standard contract.',
    );
  }

  ExpectedPlayerRole expectedRole(PublicFreeAgentView player) {
    final overall = player.overallRating;
    if (overall >= 78) return ExpectedPlayerRole.starter;
    if (overall >= 70) return ExpectedPlayerRole.rotation;
    if (overall >= 62) return ExpectedPlayerRole.bench;
    return ExpectedPlayerRole.developmental;
  }

  int preferredDuration(PublicFreeAgentView player) {
    if (player.age <= 23) return 2;
    if (player.age <= 28) return 3;
    if (player.age <= 31) return 2;
    return 1;
  }

  /// Annual value for an explicit duration. The 5% schedule is applied on top
  /// by the contract layer; this is the negotiated year-one value.
  int annualValue(PublicFreeAgentView player, int durationYears) {
    if (durationYears < 1 || durationYears > 4) {
      throw ArgumentError.value(
        durationYears,
        'durationYears',
        'Duration must be 1..4',
      );
    }
    final rating = player.overallRating.clamp(50, 90).toInt();
    final ratingSquared = (rating - 50) * (rating - 50);
    final base = _minimum + ratingSquared * 6;
    final ageBp = switch (player.age) {
      <= 23 => 8500,
      <= 28 => 10500,
      <= 31 => 10000,
      <= 34 => 8500,
      _ => 7000,
    };
    final durationBp = switch (durationYears) {
      1 => 10800,
      2 => 10200,
      3 => 10000,
      _ => 9600,
    };
    var value = (base * ageBp) ~/ 10000;
    value = (value * durationBp) ~/ 10000;
    final scheduleCap = maxYearOneForDuration(durationYears);
    return _clamp(_round(value), max: scheduleCap);
  }

  /// Two-way money is fixed by the rulebook; only eligibility varies.
  int twoWayValue() => FinancialRules.twoWaySalary;

  /// Largest year-one salary whose full 5% schedule stays within the 8,000 CU
  /// individual maximum.
  static int maxYearOneForDuration(int durationYears) {
    if (durationYears < 1 || durationYears > 4) {
      throw ArgumentError.value(
        durationYears,
        'durationYears',
        'Duration must be 1..4',
      );
    }
    var maximum = FinancialRules.maximumSalary;
    for (var year = 1; year < durationYears; year++) {
      maximum = (maximum * 10000) ~/ 10500;
    }
    return maximum;
  }

  static int _round(int value) => ((value + 5) ~/ 10) * 10;

  static int _clamp(int value, {int max = _maximum}) =>
      value < _minimum ? _minimum : (value > max ? max : value);
}
