import '../models/ids.dart';
import 'court_lineup.dart';
import 'game_validation.dart';
import 'offensive_role.dart';
import 'probability_model.dart';

/// Dormant M006-T02 opportunity policy.
///
/// Applies the approved role multipliers to the raw v6 shooter-usage weights
/// and normalises the result to 10000 basis points. The function is pure: it
/// consumes no randomness, mutates nothing and is not called from any production
/// path while T02 remains dormant.
///
/// It deliberately does not model possession-level ball handling; the role
/// assignment is a weight-shaping classification only.
abstract final class OffensiveOpportunity {
  static const int primaryBasisPoints = 13500;
  static const int secondaryBasisPoints = 11500;
  static const int neutralBasisPoints = 10000;

  static int multiplierFor(OffensiveRole role) => switch (role) {
    OffensiveRole.primary => primaryBasisPoints,
    OffensiveRole.secondary => secondaryBasisPoints,
    OffensiveRole.neutral => neutralBasisPoints,
  };

  /// The dormant policy entry point.
  ///
  /// Starts from the model's raw v6 usage weights (canonical court-slot order),
  /// applies `raw × multiplier` with exact integer arithmetic, and runs the
  /// model's own proportional normalisation once, returning weights that sum to
  /// exactly 10000 in canonical court-slot order.
  static List<int> adjustedUsageWeights({
    required CourtLineup activeLineup,
    required OffensiveRoleAssignment roles,
  }) {
    final raw = BasketballProbabilityModel().rawShotUsageWeights(activeLineup);
    return applyRoleMultipliers(
      rawUsageWeights: raw,
      activeLineup: activeLineup,
      roles: roles,
    );
  }

  /// Applies the multipliers to an explicit raw v6 usage vector.
  ///
  /// Public and pure so the multiplier step is independently testable without
  /// recomputing attributes; callers must pass the raw, unnormalised vector.
  static List<int> applyRoleMultipliers({
    required List<int> rawUsageWeights,
    required CourtLineup activeLineup,
    required OffensiveRoleAssignment roles,
  }) {
    _requireAligned(activeLineup, roles);
    if (rawUsageWeights.length != activeLineup.slots.length) {
      throw GameValidationException([
        GameValidationIssue(
          code: GameValidationCode.roleAssignmentMismatch,
          path: 'rawUsageWeights',
          message:
              'expected ${activeLineup.slots.length} raw usage weights, '
              'got ${rawUsageWeights.length}',
        ),
      ]);
    }
    final weighted = <int>[
      for (var index = 0; index < rawUsageWeights.length; index++)
        rawUsageWeights[index] *
            multiplierFor(
              roles.roleOf(PlayerId(activeLineup.slots[index].playerId.value)),
            ),
    ];
    return BasketballProbabilityModel.normalizeBasisPointWeights(weighted);
  }

  /// Rejects a role assignment that does not describe exactly the active five.
  ///
  /// T01's `roleOf` falls back to neutral for unknown ids; this guard prevents
  /// that fallback from silently masking a mismatched lineup/role input in the
  /// opportunity policy.
  static void _requireAligned(
    CourtLineup activeLineup,
    OffensiveRoleAssignment roles,
  ) {
    final lineupIds = [for (final slot in activeLineup.slots) slot.playerId];
    final ranking = roles.ranking;
    String? message;
    if (ranking.length != lineupIds.length) {
      message =
          'role ranking has ${ranking.length} players, '
          'lineup has ${lineupIds.length}';
    } else {
      final listed = <String>{};
      for (final playerId in ranking) {
        if (!listed.add(playerId.value)) {
          message = 'role ranking repeats player ${playerId.value}';
          break;
        }
      }
      if (message == null) {
        final lineupSet = {for (final playerId in lineupIds) playerId.value};
        final rankingSet = {for (final playerId in ranking) playerId.value};
        if (rankingSet.length != lineupSet.length ||
            !rankingSet.containsAll(lineupSet)) {
          message = 'role ranking does not match the active five';
        }
      }
    }
    if (message != null) {
      throw GameValidationException([
        GameValidationIssue(
          code: GameValidationCode.roleAssignmentMismatch,
          path: 'roles.ranking',
          message: message,
        ),
      ]);
    }
  }
}
