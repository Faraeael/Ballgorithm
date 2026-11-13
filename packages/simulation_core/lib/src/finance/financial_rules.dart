import '../models/franchise_situation.dart';
import '../models/roster_category.dart';

/// Approved T08C financial constants and deterministic calculations.
///
/// All amounts are integer Credit Units (CU). No floating point is used and no
/// value depends on RNG, clock or locale.
abstract final class FinancialRules {
  static const int salaryCap = 41000;
  static const int minimumSalary = 400;
  static const int maximumSalary = 8000;
  static const int twoWaySalary = 250;

  /// 5% annual raise, in basis points.
  static const int annualRaiseBasisPoints = 500;

  static const int maximumTwoWayPlayers = 3;
  static const int minimumStandardRoster = 14;

  static const int maximumReliefDeals = 2;
  static const int maximumReliefOverage = 800;

  /// Combined ordinary and hardship cap overage ceiling for T08H-P2.
  static const int maximumCombinedHardshipOverage = 1000;

  /// Overage the minimum-roster exception may permit, or null when the
  /// franchise is not eligible. T08C records this rule only; it executes no
  /// relief transaction.
  static int? minimumRosterReliefOverage({
    required int standardCount,
    required int capRoom,
  }) {
    final missing = minimumStandardRoster - standardCount;
    if (missing <= 0 || missing > maximumReliefDeals) return null;
    final cost = missing * minimumSalary;
    final overage = cost - capRoom;
    if (overage <= 0) return 0;
    return overage > maximumReliefOverage ? maximumReliefOverage : overage;
  }

  /// Version of the financial section inside career schema v8.
  static const int financialSchemaVersion = 1;

  static const int minimumBalance = 0;
  static const int maximumBalance = 1000000;

  static const int minFacilityLevel = 1;
  static const int maxFacilityLevel = 5;

  static const int initialStaffCost = 9500;
  static const int initialFacilityMaintenance = 2800;

  /// Legacy bootstrap values. Membership is checked to detect unauthorized
  /// rewrites; it is never recalculated from a player's current overall.
  static const Set<int> legacyBootstrapSalaries = {
    400,
    550,
    800,
    1100,
    1500,
    2000,
    2600,
    3300,
    4100,
    5000,
    6000,
  };

  static int legacySalaryForOverall(int overall) {
    if (overall < 42) return 400;
    if (overall <= 45) return 550;
    if (overall <= 49) return 800;
    if (overall <= 53) return 1100;
    if (overall <= 57) return 1500;
    if (overall <= 61) return 2000;
    if (overall <= 65) return 2600;
    if (overall <= 69) return 3300;
    if (overall <= 73) return 4100;
    if (overall <= 77) return 5000;
    return 6000;
  }

  /// Legacy migration duration: two years at age 29 or younger, one at 30+.
  static int legacyDurationForAge(int age) => age >= 30 ? 1 : 2;

  /// Rookie scale by overall draft pick, before category adjustment.
  static int rookieSalaryForPick(int overallPick) {
    if (overallPick <= 5) return 1800;
    if (overallPick <= 10) return 1500;
    if (overallPick <= 20) return 1200;
    if (overallPick <= 30) return 1000;
    return 700;
  }

  static int rookieSalary({
    required int overallPick,
    required RosterCategory category,
  }) => category == RosterCategory.twoWay
      ? twoWaySalary
      : rookieSalaryForPick(overallPick);

  /// New-contract duration limit by roster category. Existing signed
  /// agreements are validated by their stored terms, not this rule.
  static int maxDurationForCategory(RosterCategory category) =>
      category == RosterCategory.twoWay ? 2 : 4;

  static int raiseStandardSalary(int salary) =>
      (salary * (10000 + annualRaiseBasisPoints)) ~/ 10000;

  /// Deterministic standard schedule: 5% raise per year, rounded down.
  static List<int> standardSchedule(int yearOne, int durationYears) {
    final schedule = <int>[yearOne];
    var salary = yearOne;
    for (var year = 1; year < durationYears; year++) {
      salary = raiseStandardSalary(salary);
      schedule.add(salary);
    }
    return schedule;
  }

  static List<int> twoWaySchedule(int durationYears) =>
      List<int>.filled(durationYears, twoWaySalary);

  static FranchiseFinancialPlan planFor(FranchiseSituation situation) =>
      switch (situation) {
        FranchiseSituation.tanking => const FranchiseFinancialPlan(
          operatingBudget: 18000,
          cash: 10000,
          revenueBaseline: 42000,
        ),
        FranchiseSituation.playIn => const FranchiseFinancialPlan(
          operatingBudget: 21000,
          cash: 13000,
          revenueBaseline: 47000,
        ),
        FranchiseSituation.playoff => const FranchiseFinancialPlan(
          operatingBudget: 24000,
          cash: 16000,
          revenueBaseline: 52000,
        ),
        FranchiseSituation.contender => const FranchiseFinancialPlan(
          operatingBudget: 27000,
          cash: 19000,
          revenueBaseline: 57000,
        ),
      };

  /// Annual maintenance for one facility level. Facility effects are not
  /// implemented in T08C.
  static int facilityMaintenance(FacilityKind kind, int level) =>
      switch (kind) {
        FacilityKind.training => 600 * level,
        FacilityKind.medical => 500 * level,
        FacilityKind.scouting => 300 * level,
        FacilityKind.arena => 800 * level,
      };
}

/// Deterministic starting money for one franchise situation.
final class FranchiseFinancialPlan {
  const FranchiseFinancialPlan({
    required this.operatingBudget,
    required this.cash,
    required this.revenueBaseline,
  });

  final int operatingBudget;
  final int cash;
  final int revenueBaseline;
}

/// Recurring staff categories. Effects are out of T08C scope.
enum StaffCategory {
  headCoach('headCoach'),
  assistant('assistant'),
  playerDevelopment('playerDevelopment'),
  scout('scout'),
  medical('medical');

  const StaffCategory(this.jsonValue);

  final String jsonValue;

  static StaffCategory fromJson(String value) => values.firstWhere(
    (category) => category.jsonValue == value || category.name == value,
    orElse: () => throw ArgumentError.value(
      value,
      'staffCategory',
      'Unknown staff category: $value',
    ),
  );
}

enum StaffTier {
  basic('basic'),
  standard('standard'),
  premium('premium');

  const StaffTier(this.jsonValue);

  final String jsonValue;

  static StaffTier fromJson(String value) => values.firstWhere(
    (tier) => tier.jsonValue == value || tier.name == value,
    orElse: () => throw ArgumentError.value(
      value,
      'staffTier',
      'Unknown staff tier: $value',
    ),
  );
}

enum FacilityKind {
  training('training'),
  medical('medical'),
  scouting('scouting'),
  arena('arena');

  const FacilityKind(this.jsonValue);

  final String jsonValue;

  static FacilityKind fromJson(String value) => values.firstWhere(
    (kind) => kind.jsonValue == value || kind.name == value,
    orElse: () => throw ArgumentError.value(
      value,
      'facility',
      'Unknown facility: $value',
    ),
  );
}
