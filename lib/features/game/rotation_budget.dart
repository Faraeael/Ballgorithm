import 'dart:math' as math;

/// Accepted M005 custom playing-time budget rules (owner acceptance §3),
/// shared by Game Day setup and the career rotation editor.
///
/// Targets are integer player-seconds keyed by player id. Only the edited
/// player's value ever changes: nothing is redistributed.
abstract final class RotationBudget {
  /// Fine-adjustment step (the M005 `±10s` controls).
  static const int fineStepSeconds = 10;

  static int total(Map<String, int> targets) =>
      targets.values.fold<int>(0, (sum, value) => sum + value);

  /// Highest value [playerId] may take: the per-player [cap] and whatever the
  /// [teamTotal] still allows after the other players are counted.
  static int maximumAllowed(
    Map<String, int> targets,
    String playerId, {
    required int cap,
    required int teamTotal,
  }) {
    final current = targets[playerId] ?? 0;
    final others = total(targets) - current;
    return math.min(cap, teamTotal - others);
  }

  /// Returns the value to store for [playerId], or `null` when the proposal is
  /// rejected or unchanged.
  ///
  /// [clamp] is used by slider drags: a proposal above the allowed maximum
  /// sticks to that maximum so the thumb never runs past the team budget.
  /// Fine adjustments reject out-of-range proposals outright.
  static int? propose(
    Map<String, int> targets,
    String playerId,
    int seconds, {
    required int cap,
    required int teamTotal,
    bool clamp = false,
  }) {
    final current = targets[playerId] ?? 0;
    final allowed = maximumAllowed(
      targets,
      playerId,
      cap: cap,
      teamTotal: teamTotal,
    );
    var proposed = seconds;
    if (clamp) proposed = math.min(proposed, allowed);
    if (proposed < 0 || proposed > allowed) return null;
    if (proposed == current && targets.containsKey(playerId)) return null;
    return proposed;
  }
}
