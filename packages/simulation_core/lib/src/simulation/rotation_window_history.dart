import 'rotation_policy.dart';

/// Per-team substitution-window history for the tactical rotation policy.
///
/// The immediately previous window's swap is kept separately from the last
/// tactical swap timestamp: an empty window clears the former but never the
/// latter, so cooldown is unaffected by intervening swap-free windows.
final class RotationWindowHistory {
  final Map<String, RotationSwapProposal?> _previous =
      <String, RotationSwapProposal?>{};
  final Map<String, RotationSwapProposal?> _current =
      <String, RotationSwapProposal?>{};
  final Map<String, int> _lastSwapSeconds = <String, int>{};

  /// Commits the window that just closed and starts a new one for each team.
  void beginWindow(Iterable<String> teamIds) {
    for (final teamId in teamIds) {
      _previous[teamId] = _current[teamId];
      _current[teamId] = null;
    }
  }

  RotationSwapProposal? previousWindowSwap(String teamId) => _previous[teamId];

  bool swappedThisWindow(String teamId) => _current[teamId] != null;

  int? lastTacticalSwapSeconds(String teamId) => _lastSwapSeconds[teamId];

  void recordSwap(String teamId, RotationSwapProposal proposal, int seconds) {
    _current[teamId] = proposal;
    _lastSwapSeconds[teamId] = seconds;
  }
}
