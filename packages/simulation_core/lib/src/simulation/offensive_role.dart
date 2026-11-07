import '../models/ids.dart';
import '../models/player.dart';
import 'court_lineup.dart';

/// How much a player shapes offensive opportunity in the M006 design.
///
/// This is a weight-shaping classification, not a simulated possession-level
/// ballhandler: it does not decide who turns the ball over or commits an
/// offensive foul, and it is never persisted on `Player` or in a snapshot.
enum OffensiveRole { primary, secondary, neutral }

/// Immutable result of ranking one active five by creation score.
///
/// [ranking] lists all five players from primary to neutral in the same order
/// the ranking used: descending creation score, then canonical court-slot
/// order for ties. [scoreFor] and [roleOf] answer per player.
final class OffensiveRoleAssignment {
  OffensiveRoleAssignment._({
    required List<PlayerId> ranking,
    required Map<PlayerId, int> scores,
    required Map<PlayerId, OffensiveRole> roles,
  }) : ranking = List<PlayerId>.unmodifiable(ranking),
       _scores = Map<PlayerId, int>.unmodifiable(scores),
       _roles = Map<PlayerId, OffensiveRole>.unmodifiable(roles);

  /// Primary first, secondary second, neutral ranks after them.
  final List<PlayerId> ranking;

  final Map<PlayerId, int> _scores;
  final Map<PlayerId, OffensiveRole> _roles;

  PlayerId get primary => ranking[0];

  PlayerId get secondary => ranking[1];

  int scoreFor(PlayerId playerId) => _scores[playerId] ?? 0;

  OffensiveRole roleOf(PlayerId playerId) =>
      _roles[playerId] ?? OffensiveRole.neutral;
}

/// Pure, deterministic creation ranking for the M006 v1 role signal.
///
/// `creationScore = 3 × ballHandling + passing + basketballIQ`
///
/// The score deliberately contains **no position bonus**: position still
/// influences usage and shot zones through the existing v6 weights, but the
/// role ranking must reflect creation ability only. Ties break on canonical
/// court-slot order (PG, SG, SF, PF, C). The function consumes no randomness,
/// holds no state and is not called from any production path while M006-T01
/// remains dormant.
abstract final class OffensiveRoleRanking {
  static int creationScore(Player player) {
    final attributes = player.attributes;
    return 3 * attributes.ballHandling +
        attributes.passing +
        attributes.basketballIQ;
  }

  static OffensiveRoleAssignment derive(CourtLineup lineup) {
    final entries = <({PlayerId playerId, int score, int slotIndex})>[];
    for (var slotIndex = 0; slotIndex < lineup.slots.length; slotIndex++) {
      final player = lineup.playerAtSlotIndex(slotIndex);
      entries.add((
        playerId: player.id,
        score: creationScore(player),
        slotIndex: slotIndex,
      ));
    }
    entries.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.slotIndex.compareTo(b.slotIndex);
    });

    final ranking = [for (final entry in entries) entry.playerId];
    final scores = {for (final entry in entries) entry.playerId: entry.score};
    final roles = {
      for (var index = 0; index < ranking.length; index++)
        ranking[index]: switch (index) {
          0 => OffensiveRole.primary,
          1 => OffensiveRole.secondary,
          _ => OffensiveRole.neutral,
        },
    };
    return OffensiveRoleAssignment._(
      ranking: ranking,
      scores: scores,
      roles: roles,
    );
  }
}
