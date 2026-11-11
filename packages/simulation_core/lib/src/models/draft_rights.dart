import 'ids.dart';

/// Exclusive acquisition rights for an unsigned drafted prospect.
///
/// Draft rights associate the selected rookie with the franchise that drafted
/// them. They do NOT constitute active roster membership and consume zero
/// roster slots.
final class DraftRights {
  const DraftRights({
    required this.prospectId,
    required this.owningTeamId,
    required this.overallPick,
    required this.seasonYear,
  });

  factory DraftRights.fromJson(Map<String, dynamic> json) {
    final prospectId = json['prospectId'];
    final owningTeam = json['owningTeamId'];
    final overallPick = json['overallPick'];
    final year = json['seasonYear'];

    if (prospectId is! String ||
        owningTeam is! String ||
        overallPick is! int ||
        year is! int) {
      throw const FormatException('Malformed DraftRights JSON');
    }

    return DraftRights(
      prospectId: PlayerId(prospectId),
      owningTeamId: TeamId(owningTeam),
      overallPick: overallPick,
      seasonYear: year,
    )..validate();
  }

  final PlayerId prospectId;
  final TeamId owningTeamId;
  final int overallPick;
  final int seasonYear;

  void validate() {
    if (seasonYear < 1 ||
        overallPick < 1 ||
        overallPick > 60 ||
        prospectId.value.trim().isEmpty ||
        owningTeamId.value.trim().isEmpty) {
      throw const FormatException('Invalid draft rights');
    }
  }

  Map<String, dynamic> toJson() => {
    'prospectId': prospectId.value,
    'owningTeamId': owningTeamId.value,
    'overallPick': overallPick,
    'seasonYear': seasonYear,
  };
}
