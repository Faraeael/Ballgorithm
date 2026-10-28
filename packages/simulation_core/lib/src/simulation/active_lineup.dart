import '../models/player.dart';
import '../models/position.dart';
import '../models/team.dart';
import 'game_validation.dart';

/// Five active players in canonical PG, SG, SF, PF, C order.
final class ActiveLineup {
  ActiveLineup._(List<Player> players) : players = List.unmodifiable(players);

  factory ActiveLineup.create(List<Player> players) {
    final issues = <GameValidationIssue>[];
    if (players.length != Position.values.length) {
      issues.add(
        GameValidationIssue(
          code: GameValidationCode.invalidLineupSize,
          path: 'lineup.players',
          message:
              'lineup requires exactly ${Position.values.length} players, '
              'got ${players.length}',
        ),
      );
    } else {
      final seen = <String>{};
      for (var i = 0; i < players.length; i++) {
        final player = players[i];
        if (!seen.add(player.id.value)) {
          issues.add(
            GameValidationIssue(
              code: GameValidationCode.duplicateLineupPlayer,
              path: 'lineup.players[$i]',
              message: 'duplicate player ${player.id.value}',
            ),
          );
        }
        if (player.position != Position.values[i]) {
          issues.add(
            GameValidationIssue(
              code: GameValidationCode.invalidLineupPositions,
              path: 'lineup.players[$i]',
              message:
                  'expected ${Position.values[i].shortName} at index $i, '
                  'got ${player.position.shortName}',
            ),
          );
        }
      }
    }
    if (issues.isNotEmpty) throw GameValidationException(issues);
    return ActiveLineup._(players);
  }

  /// First eligible player per position in stable roster order.
  factory ActiveLineup.defaultFor(Team team) {
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
    return ActiveLineup._(selected);
  }

  final List<Player> players;

  List<String> get playerIds => [for (final player in players) player.id.value];

  bool containsPlayer(String playerId) =>
      players.any((player) => player.id.value == playerId);

  Player? playerById(String playerId) {
    for (final player in players) {
      if (player.id.value == playerId) return player;
    }
    return null;
  }

  Map<String, Object?> toJson() => {'playerIds': playerIds};
}
