import 'ids.dart';
import 'roster_category.dart';

/// Explicit roster membership designation for one contracted player.
final class RosterMembership {
  const RosterMembership({required this.playerId, required this.category});

  factory RosterMembership.fromJson(Map<String, dynamic> json) {
    final rawPlayerId = json['playerId'] as String?;
    final rawCategory = json['category'] as String?;
    if (rawPlayerId == null || rawCategory == null) {
      throw const FormatException('Malformed RosterMembership JSON');
    }
    return RosterMembership(
      playerId: PlayerId(rawPlayerId),
      category: RosterCategory.fromJson(rawCategory),
    );
  }

  final PlayerId playerId;
  final RosterCategory category;

  Map<String, dynamic> toJson() => {
    'playerId': playerId.value,
    'category': category.jsonValue,
  };
}
