import '../models/ids.dart';
import 'basis_point_weights.dart';
import 'court_lineup.dart';
import 'game_validation.dart';
import 'offensive_role.dart';

/// M006 opportunity policy: role multipliers on the raw shooter-usage weights.
///
/// Applies the approved role multipliers to the raw v6 usage weights and
/// normalises the result to 10000 basis points in canonical court-slot order.
/// The function is pure: it consumes no randomness, mutates nothing and holds no
/// state. It deliberately does not model possession-level ball handling; the
/// role assignment is a weight-shaping classification only.
abstract final class OffensiveOpportunity {
  static const int primaryBasisPoints = 13500;
  static const int secondaryBasisPoints = 11500;
  static const int neutralBasisPoints = 10000;

  static int multiplierFor(OffensiveRole role) => switch (role) {
    OffensiveRole.primary => primaryBasisPoints,
    OffensiveRole.secondary => secondaryBasisPoints,
    OffensiveRole.neutral => neutralBasisPoints,
  };

  /// Applies `raw × multiplier` with exact integer arithmetic and normalises
  /// once, returning weights that sum to exactly 10000 in canonical court-slot
  /// order.
  ///
  /// [rawUsageWeights] must be the unnormalised vector for the same five as
  /// [activeLineup]; multipliers are never applied to an already-normalised
  /// vector.
  static List<int> adjustedUsageWeights({
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
    return normalizeBasisPointWeights(weighted);
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
        final onCourt = {for (final id in lineupIds) id.value};
        for (final playerId in ranking) {
          if (!onCourt.contains(playerId.value)) {
            message =
                'role ranking includes ${playerId.value}, '
                'who is not on court';
            break;
          }
        }
      }
    }
    if (message != null) {
      throw GameValidationException([
        GameValidationIssue(
          code: GameValidationCode.roleAssignmentMismatch,
          path: 'roles',
          message: message,
        ),
      ]);
    }
  }
}
