import '../models/ids.dart';
import '../models/player.dart';
import '../models/position.dart';
import '../models/team.dart';
import 'active_lineup.dart';

/// One canonical court slot and the player who currently occupies it.
///
/// Internal to `simulation_core` during M004 T02: it is deliberately absent
/// from the package barrel. Public exposure happens only in the atomic v5
/// transition.
final class CourtSlot {
  const CourtSlot({required this.slot, required this.player});

  final Position slot;
  final Player player;
}

/// Five canonical court slots, PG..C, each holding a unique roster player.
///
/// T02 invariant: every reachable lineup keeps each player in their primary
/// position, so slot-based calculations are numerically identical to the
/// previous position-based ones.
final class CourtLineup {
  CourtLineup._(List<CourtSlot> slots)
    : slots = List<CourtSlot>.unmodifiable(slots);

  /// Builds an internally valid lineup from a team roster.
  ///
  /// Rejects a wrong slot count, non-canonical order, a player outside the
  /// roster, a duplicate player, or a player whose primary position differs
  /// from the slot. T03 relaxes the last rule.
  factory CourtLineup.create(Team team, List<Player> slotOrderedPlayers) {
    if (slotOrderedPlayers.length != Position.values.length) {
      throw ArgumentError.value(
        slotOrderedPlayers.length,
        'slotOrderedPlayers',
        'a court lineup requires exactly ${Position.values.length} players',
      );
    }
    final rosterIds = <String>{
      for (final player in team.players) player.id.value,
    };
    final seen = <String>{};
    final slots = <CourtSlot>[];
    for (var index = 0; index < slotOrderedPlayers.length; index++) {
      final player = slotOrderedPlayers[index];
      final slot = Position.values[index];
      if (!rosterIds.contains(player.id.value)) {
        throw ArgumentError.value(
          player.id.value,
          'slotOrderedPlayers[$index]',
          'player is not on team ${team.id.value}',
        );
      }
      if (!seen.add(player.id.value)) {
        throw ArgumentError.value(
          player.id.value,
          'slotOrderedPlayers[$index]',
          'duplicate player',
        );
      }
      if (player.position != slot) {
        throw ArgumentError.value(
          player.position.shortName,
          'slotOrderedPlayers[$index]',
          'T02 requires ${slot.shortName} in this slot',
        );
      }
      slots.add(CourtSlot(slot: slot, player: player));
    }
    return CourtLineup._(slots);
  }

  /// Converts the validated fixed five into canonical slots.
  ///
  /// Ownership and uniqueness were already enforced by `ActiveLineup` and
  /// `GameInput`; only canonical order is re-checked here.
  factory CourtLineup.fromActiveLineup(ActiveLineup lineup) {
    if (lineup.players.length != Position.values.length) {
      throw ArgumentError.value(
        lineup.players.length,
        'lineup',
        'a court lineup requires exactly ${Position.values.length} players',
      );
    }
    final slots = <CourtSlot>[];
    for (var index = 0; index < lineup.players.length; index++) {
      final player = lineup.players[index];
      final slot = Position.values[index];
      if (player.position != slot) {
        throw ArgumentError.value(
          player.position.shortName,
          'lineup[$index]',
          'T02 requires ${slot.shortName} in this slot',
        );
      }
      slots.add(CourtSlot(slot: slot, player: player));
    }
    return CourtLineup._(slots);
  }

  final List<CourtSlot> slots;

  List<Player> get players => [for (final slot in slots) slot.player];

  Player playerAt(Position slot) => slots[Position.values.indexOf(slot)].player;

  Player playerAtSlotIndex(int index) => slots[index].player;

  Position slotAt(int index) => slots[index].slot;

  CourtSlot slotOfPlayer(PlayerId playerId) {
    for (final slot in slots) {
      if (slot.player.id.value == playerId.value) {
        return slot;
      }
    }
    throw ArgumentError.value(
      playerId.value,
      'playerId',
      'player is not on the court',
    );
  }

  int slotIndexForPlayer(PlayerId playerId) =>
      slots.indexOf(slotOfPlayer(playerId));

  bool containsPlayer(PlayerId playerId) {
    for (final slot in slots) {
      if (slot.player.id.value == playerId.value) return true;
    }
    return false;
  }
}
