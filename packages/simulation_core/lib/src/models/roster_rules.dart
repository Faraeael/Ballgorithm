import '../career/career_phase.dart';

/// Authority on franchise roster capacity limits and phase-aware compliance rules.
abstract final class RosterRules {
  // Offseason limits
  static const int maxOffseasonStandard = 15;
  static const int maxOffseasonTwoWay = 3;
  static const int maxOffseasonTotal = 21;

  // Regular-season limits & readiness thresholds
  static const int minRegularSeasonStandard = 14;
  static const int maxRegularSeasonStandard = 15;
  static const int maxRegularSeasonTwoWay = 3;
  static const int maxRegularSeasonTotal = 18;
  static const int maxRegularSeasonTrainingCamp = 0;

  // Initial generation baseline
  static const int initialGenerationSize = 12;

  /// Validates structural validity of a roster for a given [CareerPhase].
  ///
  /// Structural validity ensures that no roster category cap or total limit
  /// is exceeded. During [CareerPhase.openingOffseason], standard rosters of
  /// 12 to 15 players are structurally valid.
  static RosterValidationResult validateStructure({
    required int standardCount,
    required int twoWayCount,
    required int trainingCampCount,
    required CareerPhase phase,
  }) {
    final issues = <String>[];
    final total = standardCount + twoWayCount + trainingCampCount;

    if (phase == CareerPhase.openingOffseason) {
      if (standardCount > maxOffseasonStandard) {
        issues.add(
          'Standard player count ($standardCount) exceeds offseason limit ($maxOffseasonStandard)',
        );
      }
      if (twoWayCount > maxOffseasonTwoWay) {
        issues.add(
          'Two-way player count ($twoWayCount) exceeds limit ($maxOffseasonTwoWay)',
        );
      }
      if (total > maxOffseasonTotal) {
        issues.add(
          'Total contracted roster count ($total) exceeds offseason limit ($maxOffseasonTotal)',
        );
      }
    } else {
      if (standardCount > maxRegularSeasonStandard) {
        issues.add(
          'Standard player count ($standardCount) exceeds regular-season limit ($maxRegularSeasonStandard)',
        );
      }
      if (twoWayCount > maxRegularSeasonTwoWay) {
        issues.add(
          'Two-way player count ($twoWayCount) exceeds limit ($maxRegularSeasonTwoWay)',
        );
      }
      if (trainingCampCount > maxRegularSeasonTrainingCamp) {
        issues.add(
          'Training-camp players ($trainingCampCount) are not permitted outside offseason',
        );
      }
      if (total > maxRegularSeasonTotal) {
        issues.add(
          'Total contracted roster count ($total) exceeds regular-season limit ($maxRegularSeasonTotal)',
        );
      }
    }

    return RosterValidationResult(issues: issues);
  }

  /// Validates whether a roster meets all criteria necessary to begin a regular season:
  /// - At least 14 standard players.
  /// - At most 15 standard players.
  /// - At most 3 two-way players.
  /// - Exactly 0 training camp players remaining.
  /// - Total contracted players in 14..18.
  static RosterValidationResult validateRegularSeasonReadiness({
    required int standardCount,
    required int twoWayCount,
    required int trainingCampCount,
  }) {
    final issues = <String>[];
    final total = standardCount + twoWayCount + trainingCampCount;

    if (standardCount < minRegularSeasonStandard) {
      issues.add(
        'Franchise has $standardCount standard players; regular season requires at least $minRegularSeasonStandard',
      );
    }
    if (standardCount > maxRegularSeasonStandard) {
      issues.add(
        'Franchise has $standardCount standard players; regular season allows at most $maxRegularSeasonStandard',
      );
    }
    if (twoWayCount > maxRegularSeasonTwoWay) {
      issues.add(
        'Franchise has $twoWayCount two-way players; exceeds regular-season limit ($maxRegularSeasonTwoWay)',
      );
    }
    if (trainingCampCount > 0) {
      issues.add(
        'Franchise has $trainingCampCount training-camp players; all must be converted or waived before regular season',
      );
    }
    if (total > maxRegularSeasonTotal) {
      issues.add(
        'Total roster ($total) exceeds regular-season limit ($maxRegularSeasonTotal)',
      );
    }

    return RosterValidationResult(issues: issues);
  }
}

/// Typed validation result for roster capacity and compliance checks.
final class RosterValidationResult {
  const RosterValidationResult({this.issues = const []});

  final List<String> issues;

  bool get isValid => issues.isEmpty;

  void throwIfInvalid() {
    if (!isValid) {
      throw FormatException('Roster validation failed:\n${issues.join('\n')}');
    }
  }
}
