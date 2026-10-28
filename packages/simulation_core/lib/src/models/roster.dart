import '../validation/validation_result.dart';
import 'player.dart';
import 'position.dart';

/// An ordered group of players. Rejects duplicate player IDs outright; size
/// and position coverage are league-level rules checked by LeagueValidator.
final class Roster {
  Roster(List<Player> players) : players = List.unmodifiable(players) {
    final seen = <String>{};
    for (final player in this.players) {
      if (!seen.add(player.id.value)) {
        throw DomainValidationException([
          ValidationIssue(
            code: ValidationCode.duplicatePlayerId,
            path: 'roster.players',
            message: 'duplicate player id ${player.id.value}',
          ),
        ]);
      }
    }
  }

  final List<Player> players;

  int get size => players.length;

  bool covers(Position position) =>
      players.any((player) => player.position == position);
}
