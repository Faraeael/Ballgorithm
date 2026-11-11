import '../career/career_phase.dart';
import '../validation/validation_result.dart';
import 'ids.dart';
import 'player.dart';
import 'position.dart';
import 'roster_category.dart';
import 'roster_rules.dart';

/// An ordered group of contracted players with category designations.
///
/// Rejects duplicate player IDs outright; size, category capacity, and position
/// coverage are governed by [RosterRules] and phase-aware validation.
final class Roster {
  Roster(List<Player> players, {Map<String, RosterCategory>? categories})
    : players = List.unmodifiable(players),
      categories = Map.unmodifiable(
        categories ??
            {for (final p in players) p.id.value: RosterCategory.standard},
      ) {
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

    for (final key in this.categories.keys) {
      if (!seen.contains(key)) {
        throw DomainValidationException([
          ValidationIssue(
            code: ValidationCode.attributeMissing,
            path: 'roster.categories',
            message: 'category assigned to player not on roster: $key',
          ),
        ]);
      }
    }
  }

  final List<Player> players;
  final Map<String, RosterCategory> categories;

  int get size => players.length;
  int get totalContractedCount => players.length;

  RosterCategory categoryOf(PlayerId id) =>
      categories[id.value] ?? RosterCategory.standard;

  List<Player> get standardPlayers => players
      .where((p) => categoryOf(p.id) == RosterCategory.standard)
      .toList();

  List<Player> get twoWayPlayers =>
      players.where((p) => categoryOf(p.id) == RosterCategory.twoWay).toList();

  List<Player> get trainingCampPlayers => players
      .where((p) => categoryOf(p.id) == RosterCategory.trainingCamp)
      .toList();

  int get standardCount => standardPlayers.length;
  int get twoWayCount => twoWayPlayers.length;
  int get trainingCampCount => trainingCampPlayers.length;

  bool covers(Position position) =>
      players.any((player) => player.position == position);

  RosterValidationResult validateStructure({required CareerPhase phase}) =>
      RosterRules.validateStructure(
        standardCount: standardCount,
        twoWayCount: twoWayCount,
        trainingCampCount: trainingCampCount,
        phase: phase,
      );

  RosterValidationResult validateRegularSeasonReadiness() =>
      RosterRules.validateRegularSeasonReadiness(
        standardCount: standardCount,
        twoWayCount: twoWayCount,
        trainingCampCount: trainingCampCount,
      );

  /// Returns a new [Roster] with [player] added and assigned to [category].
  Roster withPlayer(
    Player player, {
    RosterCategory category = RosterCategory.standard,
  }) {
    if (players.any((p) => p.id == player.id)) {
      throw DomainValidationException([
        ValidationIssue(
          code: ValidationCode.duplicatePlayerId,
          path: 'roster.players',
          message: 'player ${player.id.value} is already on this roster',
        ),
      ]);
    }
    final nextPlayers = [...players, player];
    final nextCategories = Map<String, RosterCategory>.from(categories)
      ..[player.id.value] = category;
    return Roster(nextPlayers, categories: nextCategories);
  }

  /// Returns a new [Roster] with [playerId] removed.
  Roster withoutPlayer(PlayerId playerId) {
    if (!players.any((p) => p.id == playerId)) {
      return this;
    }
    final nextPlayers = players.where((p) => p.id != playerId).toList();
    final nextCategories = Map<String, RosterCategory>.from(categories)
      ..remove(playerId.value);
    return Roster(nextPlayers, categories: nextCategories);
  }

  /// Returns a new [Roster] with [playerId]'s category changed to [newCategory].
  Roster withCategory(PlayerId playerId, RosterCategory newCategory) {
    if (!players.any((p) => p.id == playerId)) {
      throw DomainValidationException([
        ValidationIssue(
          code: ValidationCode.attributeMissing,
          path: 'roster.categories',
          message: 'player ${playerId.value} is not on this roster',
        ),
      ]);
    }
    final nextCategories = Map<String, RosterCategory>.from(categories)
      ..[playerId.value] = newCategory;
    return Roster(players, categories: nextCategories);
  }
}
