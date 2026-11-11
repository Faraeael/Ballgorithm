import 'ids.dart';

/// A single draft pick entitlement in a rookie draft.
final class DraftPick {
  const DraftPick({
    required this.round,
    required this.pickInRound,
    required this.overallPick,
    required this.originalOwnerTeamId,
    required this.currentOwnerTeamId,
  });

  factory DraftPick.fromJson(Map<String, dynamic> json) {
    final round = json['round'] as int?;
    final pickInRound = json['pickInRound'] as int?;
    final overallPick = json['overallPick'] as int?;
    final originalOwner = json['originalOwnerTeamId'] as String?;
    final currentOwner = json['currentOwnerTeamId'] as String?;

    if (round == null ||
        pickInRound == null ||
        overallPick == null ||
        originalOwner == null ||
        currentOwner == null) {
      throw const FormatException('Malformed DraftPick JSON');
    }

    return DraftPick(
      round: round,
      pickInRound: pickInRound,
      overallPick: overallPick,
      originalOwnerTeamId: TeamId(originalOwner),
      currentOwnerTeamId: TeamId(currentOwner),
    );
  }

  final int round;
  final int pickInRound;
  final int overallPick;
  final TeamId originalOwnerTeamId;
  final TeamId currentOwnerTeamId;

  Map<String, dynamic> toJson() => {
    'round': round,
    'pickInRound': pickInRound,
    'overallPick': overallPick,
    'originalOwnerTeamId': originalOwnerTeamId.value,
    'currentOwnerTeamId': currentOwnerTeamId.value,
  };
}
