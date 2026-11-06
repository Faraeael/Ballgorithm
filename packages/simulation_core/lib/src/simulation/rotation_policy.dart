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
    this.previousSwap,
    this.previousSwapGameSeconds,
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
  final RotationSwapProposal? previousSwap;
  final int? previousSwapGameSeconds;
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

  /// Returns at most one tactical swap, or `null` when no swap qualifies.
  static RotationSwapProposal? propose(RotationPolicyInput input) {
    if (input.mandatoryReplacementPending || input.swappedThisWindow) {
      return null;
    }
    if (input.horizonSeconds <= 0) return null;

    final limits = thresholds(input.activePeriodSeconds);
    final previousAt = input.previousSwapGameSeconds;
    if (previousAt != null &&
        input.gameSecondsElapsed - previousAt < limits.cooldown) {
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

    final previous = input.previousSwap;
    if (previous != null &&
        previous.playerInId == outgoing.id &&
        previous.playerOutId == incoming.id) {
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
