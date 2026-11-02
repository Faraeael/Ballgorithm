import '../models/ids.dart';
import '../models/player.dart';
import '../models/position.dart';
import '../models/team.dart';
import 'game_validation.dart';

/// One canonical court slot and the player occupying it.
///
/// Frozen M004 contract: identity is the slot plus the player id. A player's
/// primary position may differ from the occupied slot.
final class CourtSlot {
  const CourtSlot({required this.slot, required this.playerId, this.player});

  final Position slot;
  final PlayerId playerId;

  /// Non-serialized convenience reference. Identity and serialization are
  /// slot + player id; this field never appears in JSON or fingerprints.
  final Player? player;

  Map<String, Object?> toJson() => {
    'slot': slot.shortName,
    'playerId': playerId.value,
  };
}

/// Five canonical PG..C court slots, each holding a unique roster player.
final class CourtLineup {
  CourtLineup._(List<CourtSlot> slots)
    : slots = List<CourtSlot>.unmodifiable(slots);

  /// Builds a lineup from slot-ordered roster players.
  ///
  /// The slot at index `i` is `Position.values[i]`; the player's own primary
  /// position is not constrained and may differ.
  /// Builds a lineup and validates roster ownership, size, uniqueness and
  /// canonical slot assignment.
  factory CourtLineup.create({
    required Team team,
    required List<Player> slotOrderedPlayers,
  }) {
    final issues = <GameValidationIssue>[];
    if (slotOrderedPlayers.length != Position.values.length) {
      issues.add(
        GameValidationIssue(
          code: GameValidationCode.invalidLineupSize,
          path: 'lineup.players',
          message:
              'lineup requires exactly ${Position.values.length} players, '
              'got ${slotOrderedPlayers.length}',
        ),
      );
    }
    final rosterIds = <String>{
      for (final player in team.players) player.id.value,
    };
    final seen = <String>{};
    for (var index = 0; index < slotOrderedPlayers.length; index++) {
      final player = slotOrderedPlayers[index];
      if (!rosterIds.contains(player.id.value) && issues.isEmpty) {
        issues.add(
          GameValidationIssue(
            code: GameValidationCode.foreignLineupPlayer,
            path: 'lineup.players[$index]',
            message: 'player ${player.id.value} is not on ${team.id.value}',
          ),
        );
      }
      if (!seen.add(player.id.value)) {
        issues.add(
          GameValidationIssue(
            code: GameValidationCode.duplicateLineupPlayer,
            path: 'lineup.players[$index]',
            message: 'duplicate player ${player.id.value}',
          ),
        );
      }
    }
    if (issues.isNotEmpty) throw GameValidationException(issues);

    // Store the roster's own Player instances. A caller cannot smuggle altered
    // ratings under a valid roster id: the canonical fingerprint covers ids and
    // league data, so behaviour must come from the roster object too.
    final rosterById = {
      for (final player in team.players) player.id.value: player,
    };
    return CourtLineup._([
      for (var index = 0; index < slotOrderedPlayers.length; index++)
        CourtSlot(
          slot: Position.values[index],
          playerId: slotOrderedPlayers[index].id,
          player: rosterById[slotOrderedPlayers[index].id.value],
        ),
    ]);
  }

  /// First eligible player per position in stable roster order.
  factory CourtLineup.defaultFor(Team team) {
    final selected = <Player>[];
    for (final position in Position.values) {
      Player? found;
      for (final player in team.players) {
        if (player.position == position) {
          found = player;
          break;
        }
      }
      if (found == null) {
        throw GameValidationException([
          GameValidationIssue(
            code: GameValidationCode.invalidLineupPositions,
            path: 'lineup.players',
            message: 'team ${team.id.value} has no ${position.shortName}',
          ),
        ]);
      }
      selected.add(found);
    }
    return CourtLineup.create(team: team, slotOrderedPlayers: selected);
  }

  final List<CourtSlot> slots;

  List<String> get playerIds => [for (final slot in slots) slot.playerId.value];

  /// Slot-ordered players. Throws if a slot was built without a player
  /// reference (for example from a future deserializer).
  List<Player> get players => [for (final slot in slots) _requirePlayer(slot)];

  Player _requirePlayer(CourtSlot slot) {
    final player = slot.player;
    if (player == null) {
      throw ArgumentError.value(
        slot.playerId.value,
        'slots',
        'slot has no resolved player',
      );
    }
    return player;
  }

  Player playerAt(Position slot) =>
      _requirePlayer(slots[Position.values.indexOf(slot)]);

  Player playerAtSlotIndex(int index) => _requirePlayer(slots[index]);

  PlayerId playerIdAt(Position slot) =>
      slots[Position.values.indexOf(slot)].playerId;

  PlayerId playerIdAtSlotIndex(int index) => slots[index].playerId;

  Position slotAt(int index) => slots[index].slot;

  Position slotOf(PlayerId playerId) {
    for (final slot in slots) {
      if (slot.playerId.value == playerId.value) return slot.slot;
    }
    throw ArgumentError.value(
      playerId.value,
      'playerId',
      'player is not on the court',
    );
  }

  int slotIndexForPlayer(PlayerId playerId) {
    for (var index = 0; index < slots.length; index++) {
      if (slots[index].playerId.value == playerId.value) return index;
    }
    throw ArgumentError.value(
      playerId.value,
      'playerId',
      'player is not on the court',
    );
  }

  CourtSlot slotOfPlayerSlot(PlayerId playerId) {
    for (final slot in slots) {
      if (slot.playerId.value == playerId.value) return slot;
    }
    throw ArgumentError.value(
      playerId.value,
      'playerId',
      'player is not on the court',
    );
  }

  bool containsPlayer(PlayerId playerId) {
    for (final slot in slots) {
      if (slot.playerId.value == playerId.value) return true;
    }
    return false;
  }

  /// Ordered slot/player-id pairs, as required by the frozen contract.
  List<Map<String, Object?>> toJson() => [
    for (final slot in slots) slot.toJson(),
  ];
}
