import 'ids.dart';

/// Immutable record of a single executed draft selection.
final class DraftSelection {
  const DraftSelection({
    required this.seasonYear,
    required this.round,
    required this.pickInRound,
    required this.overallPick,
    required this.originalOwnerTeamId,
    required this.selectingTeamId,
    required this.prospectId,
  });

  factory DraftSelection.fromJson(Map<String, dynamic> json) {
    final year = json['seasonYear'];
    final round = json['round'];
    final pickInRound = json['pickInRound'];
    final overallPick = json['overallPick'];
    final originalOwner = json['originalOwnerTeamId'];
    final selectingTeam = json['selectingTeamId'];
    final prospectId = json['prospectId'];

    if (year is! int ||
        round is! int ||
        pickInRound is! int ||
        overallPick is! int ||
        originalOwner is! String ||
        selectingTeam is! String ||
        prospectId is! String) {
      throw const FormatException('Malformed DraftSelection JSON');
    }

    return DraftSelection(
      seasonYear: year,
      round: round,
      pickInRound: pickInRound,
      overallPick: overallPick,
      originalOwnerTeamId: TeamId(originalOwner),
      selectingTeamId: TeamId(selectingTeam),
      prospectId: PlayerId(prospectId),
    )..validate();
  }

  final int seasonYear;
  final int round;
  final int pickInRound;
  final int overallPick;
  final TeamId originalOwnerTeamId;
  final TeamId selectingTeamId;
  final PlayerId prospectId;

  void validate() {
    if (seasonYear < 1 ||
        overallPick < 1 ||
        overallPick > 60 ||
        round != (overallPick - 1) ~/ 30 + 1 ||
        pickInRound != (overallPick - 1) % 30 + 1 ||
        originalOwnerTeamId.value.trim().isEmpty ||
        selectingTeamId.value.trim().isEmpty ||
        prospectId.value.trim().isEmpty) {
      throw const FormatException('Invalid draft selection');
    }
  }

  Map<String, dynamic> toJson() => {
    'seasonYear': seasonYear,
    'round': round,
    'pickInRound': pickInRound,
    'overallPick': overallPick,
    'originalOwnerTeamId': originalOwnerTeamId.value,
    'selectingTeamId': selectingTeamId.value,
    'prospectId': prospectId.value,
  };
}
