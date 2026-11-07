import '../models/ids.dart';
import '../models/player.dart';
import '../models/position.dart';
import '../models/team.dart';
import 'court_lineup.dart';

/// A deterministic tactical swap proposed by [RotationPolicy].
///
/// The policy never emits an event; the simulator decides whether and when to
/// turn a proposal into a `Substitution(reason: tactical)`.
final class RotationSwapProposal {
  const RotationSwapProposal({
    required this.playerOutId,
    required this.playerInId,
    required this.vacatedSlot,
    required this.playerOutDeficit,
    required this.playerInDeficit,
  });

  final PlayerId playerOutId;
  final PlayerId playerInId;
  final Position vacatedSlot;
  final int playerOutDeficit;
  final int playerInDeficit;
}

/// Validated state for one policy evaluation.
///
/// Seconds are integer player-seconds. [elapsedSeconds] and [horizonSeconds]
/// are phase-local (regulation or one overtime period); [gameSecondsElapsed]
/// is cumulative game time used only for the cooldown. Callers supply
/// validated state: every active and eligible bench player should have a
/// target, and the active lineup must belong to [team].
final class RotationPolicyInput {
  const RotationPolicyInput({
    required this.team,
    required this.activeLineup,
    required this.targetSeconds,
    required this.actualSeconds,
    required this.elapsedSeconds,
    required this.horizonSeconds,
    required this.activePeriodSeconds,
    required this.gameSecondsElapsed,
    this.disqualified = const {},
    this.mandatoryReplacementPending = false,
    this.swappedThisWindow = false,
    this.previousWindowSwap,
    this.lastTacticalSwapGameSeconds,
  });

  final Team team;
  final CourtLineup activeLineup;
  final Map<PlayerId, int> targetSeconds;
  final Map<PlayerId, int> actualSeconds;
  final int elapsedSeconds;
  final int horizonSeconds;

  /// Length of the active period: `periodSeconds` in regulation,
  /// `overtimeSeconds` in overtime.
  final int activePeriodSeconds;

  /// Cumulative game seconds since tip-off, used for the cooldown only.
  final int gameSecondsElapsed;
  final Set<PlayerId> disqualified;
  final bool mandatoryReplacementPending;
  final bool swappedThisWindow;

  /// The immediately previous substitution window's tactical swap, or `null`
  /// when that window had no tactical swap. Used only for exact-reverse
  /// suppression, independently of [lastTacticalSwapGameSeconds]. A caller
  /// must clear it after a swap-free window.
  final RotationSwapProposal? previousWindowSwap;

  /// Cumulative game seconds of the team's most recent tactical swap, used
  /// only for the cooldown. It is independent of [previousWindowSwap].
  final int? lastTacticalSwapGameSeconds;
}

/// Per-period overtime playing-time targets for one team.
final class OvertimeRotationTargets {
  const OvertimeRotationTargets({
    required this.targetSeconds,
    required this.tacticalEnabled,
  });

  final Map<PlayerId, int> targetSeconds;

  /// False when fewer than five players are eligible; depleted continuation
  /// disables tactical swapping for this period.
  final bool tacticalEnabled;
}

/// Pure deterministic playing-time policy. Consumes no randomness and holds no
/// mutable state.
abstract final class RotationPolicy {
  /// Phase-aware threshold pair for a period of [activePeriodSeconds].
  static ({int h, int cooldown}) thresholds(int activePeriodSeconds) {
    final length = activePeriodSeconds < 1 ? 1 : activePeriodSeconds;
    return (h: _atLeastOne(length ~/ 8), cooldown: _atLeastOne(length ~/ 6));
  }

  static int _atLeastOne(int value) => value < 1 ? 1 : value;

  /// Allocates one overtime period's targets from the regulation plan.
  ///
  /// Eligible players are ordered active court slots first, then eligible
  /// bench in canonical roster order. Base targets are
  /// `floor(regulationTarget × L ÷ C)`, capped at `L`, with a round-robin
  /// remainder. When every eligible regulation target is zero, an equal split
  /// is used instead. Leftovers in a depleted period are forced onto
  /// disqualified continuers.
  static OvertimeRotationTargets allocateOvertime({
    required Team team,
    required CourtLineup activeLineup,
    required Map<PlayerId, int> regulationTargets,
    required Set<PlayerId> disqualified,
    required int overtimeSeconds,
    required int regulationCap,
  }) {
    final length = _atLeastOne(overtimeSeconds);
    final total = 5 * length;
    final cap = _atLeastOne(regulationCap);
    final targets = <PlayerId, int>{
      for (final player in team.players) player.id: 0,
    };

    final activeIds = [for (final id in activeLineup.playerIds) PlayerId(id)];
    final activeSet = activeIds.toSet();
    final eligible = <PlayerId>[];
    for (final playerId in activeIds) {
      if (!disqualified.contains(playerId)) eligible.add(playerId);
    }
    for (final player in team.players) {
      if (activeSet.contains(player.id)) continue;
      if (disqualified.contains(player.id)) continue;
      if ((regulationTargets[player.id] ?? 0) <= 0) continue;
      eligible.add(player.id);
    }
    final continuers = [
      for (final playerId in activeIds)
        if (disqualified.contains(playerId)) playerId,
    ];

    void distributeRoundRobin(List<PlayerId> order, int remaining) {
      var index = 0;
      final limit = order.length * (length + 1);
      while (remaining > 0 && order.isNotEmpty && index < limit) {
        final playerId = order[index % order.length];
        if (targets[playerId]! < length) {
          targets[playerId] = targets[playerId]! + 1;
          remaining--;
        }
        index++;
      }
    }

    if (eligible.isEmpty) {
      distributeRoundRobin(continuers, total);
      return OvertimeRotationTargets(
        targetSeconds: Map<PlayerId, int>.unmodifiable(targets),
        tacticalEnabled: false,
      );
    }

    final allZero = eligible.every(
      (playerId) => (regulationTargets[playerId] ?? 0) == 0,
    );
    for (final playerId in eligible) {
      final base = allZero
          ? total ~/ eligible.length
          : (regulationTargets[playerId] ?? 0) * length ~/ cap;
      targets[playerId] = base > length ? length : base;
    }

    var remaining =
        total - targets.values.fold<int>(0, (sum, value) => sum + value);
    distributeRoundRobin(eligible, remaining);
    remaining =
        total - targets.values.fold<int>(0, (sum, value) => sum + value);
    if (remaining > 0) {
      distributeRoundRobin(continuers, remaining);
      remaining =
          total - targets.values.fold<int>(0, (sum, value) => sum + value);
    }

    return OvertimeRotationTargets(
      targetSeconds: Map<PlayerId, int>.unmodifiable(targets),
      tacticalEnabled: eligible.length >= 5 && remaining == 0,
    );
  }

  /// Returns at most one tactical swap, or `null` when no swap qualifies.
  static RotationSwapProposal? propose(RotationPolicyInput input) {
    if (input.mandatoryReplacementPending || input.swappedThisWindow) {
      return null;
    }
    if (input.horizonSeconds <= 0) return null;

    final limits = thresholds(input.activePeriodSeconds);
    final lastSwapAt = input.lastTacticalSwapGameSeconds;
    if (lastSwapAt != null &&
        input.gameSecondsElapsed - lastSwapAt < limits.cooldown) {
      return null;
    }

    final rosterIndex = <PlayerId, int>{
      for (var index = 0; index < input.team.players.length; index++)
        input.team.players[index].id: index,
    };
    final playerById = <PlayerId, Player>{
      for (final player in input.team.players) player.id: player,
    };
    final activeIds = <PlayerId>{
      for (final id in input.activeLineup.playerIds) PlayerId(id),
    };

    int expected(PlayerId playerId) =>
        (input.targetSeconds[playerId] ?? 0) *
        input.elapsedSeconds ~/
        input.horizonSeconds;
    int deficit(PlayerId playerId) =>
        expected(playerId) - (input.actualSeconds[playerId] ?? 0);

    int compareRoster(Player a, Player b) {
      final indexA = rosterIndex[a.id] ?? 0;
      final indexB = rosterIndex[b.id] ?? 0;
      if (indexA != indexB) return indexA.compareTo(indexB);
      return a.id.value.compareTo(b.id.value);
    }

    final active = <Player>[];
    for (final id in activeIds) {
      final player = playerById[id];
      if (player == null || input.disqualified.contains(id)) continue;
      active.add(player);
    }
    if (active.isEmpty) return null;

    var minimumDeficit = deficit(active.first.id);
    for (final player in active.skip(1)) {
      final value = deficit(player.id);
      if (value < minimumDeficit) minimumDeficit = value;
    }
    if (minimumDeficit > -limits.h) return null;

    final outgoingCandidates = [
      for (final player in active)
        if (deficit(player.id) == minimumDeficit) player,
    ]..sort(compareRoster);
    final outgoing = outgoingCandidates.first;

    final eligibleBench = <Player>[];
    for (final player in input.team.players) {
      if (activeIds.contains(player.id)) continue;
      if (input.disqualified.contains(player.id)) continue;
      if ((input.targetSeconds[player.id] ?? 0) <= 0) continue;
      if (deficit(player.id) < limits.h) continue;
      eligibleBench.add(player);
    }
    if (eligibleBench.isEmpty) return null;

    var maximumDeficit = deficit(eligibleBench.first.id);
    for (final player in eligibleBench.skip(1)) {
      final value = deficit(player.id);
      if (value > maximumDeficit) maximumDeficit = value;
    }
    final tied = [
      for (final player in eligibleBench)
        if (deficit(player.id) == maximumDeficit) player,
    ];
    final vacatedSlot = input.activeLineup.slotOfPlayerSlot(outgoing.id).slot;
    final sameSlot = [
      for (final player in tied)
        if (player.position == vacatedSlot) player,
    ];
    final incomingPool = sameSlot.isEmpty ? tied : sameSlot;
    incomingPool.sort(compareRoster);
    final incoming = incomingPool.first;

    final previousWindow = input.previousWindowSwap;
    if (previousWindow != null &&
        previousWindow.playerInId == outgoing.id &&
        previousWindow.playerOutId == incoming.id) {
      return null;
    }

    return RotationSwapProposal(
      playerOutId: outgoing.id,
      playerInId: incoming.id,
      vacatedSlot: vacatedSlot,
      playerOutDeficit: deficit(outgoing.id),
      playerInDeficit: deficit(incoming.id),
    );
  }
}
