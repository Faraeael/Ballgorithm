import 'ids.dart';
import 'roster_category.dart';

/// Persistent rookie contract terms for one drafted prospect.
///
/// Category may be [RosterCategory.standard] or [RosterCategory.twoWay]. Salary,
/// cap, options and guarantees are deliberately absent: franchise finances are
/// not implemented, so no zero-cost obligation is implied.
final class RookieContract {
  const RookieContract({
    required this.id,
    required this.playerId,
    required this.teamId,
    required this.category,
    required this.startYear,
    required this.durationYears,
    required this.draftSeasonYear,
    required this.overallPick,
  });

  factory RookieContract.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final playerId = json['playerId'];
    final teamId = json['teamId'];
    final category = json['category'];
    final startYear = json['startYear'];
    final durationYears = json['durationYears'];
    final draftSeasonYear = json['draftSeasonYear'];
    final overallPick = json['overallPick'];

    if (id is! String ||
        playerId is! String ||
        teamId is! String ||
        category is! String ||
        startYear is! int ||
        durationYears is! int ||
        draftSeasonYear is! int ||
        overallPick is! int) {
      throw const FormatException('Malformed RookieContract JSON');
    }

    return RookieContract(
      id: id,
      playerId: PlayerId(playerId),
      teamId: TeamId(teamId),
      category: RosterCategory.fromJson(category),
      startYear: startYear,
      durationYears: durationYears,
      draftSeasonYear: draftSeasonYear,
      overallPick: overallPick,
    )..validate();
  }

  /// Deterministic contract identity for one signed prospect.
  static String idFor(PlayerId playerId) => 'rookie-contract-${playerId.value}';

  static const int minDurationYears = 1;
  static const int maxStandardDurationYears = 4;
  static const int maxTwoWayDurationYears = 2;

  final String id;
  final PlayerId playerId;
  final TeamId teamId;
  final RosterCategory category;
  final int startYear;
  final int durationYears;
  final int draftSeasonYear;
  final int overallPick;

  /// Inclusive final career year covered by this contract.
  int get endYear => startYear + durationYears - 1;

  static bool isSupportedCategory(RosterCategory category) =>
      category == RosterCategory.standard || category == RosterCategory.twoWay;

  static int maxDurationFor(RosterCategory category) => switch (category) {
    RosterCategory.standard => maxStandardDurationYears,
    RosterCategory.twoWay => maxTwoWayDurationYears,
    RosterCategory.trainingCamp => 0,
  };

  void validate() {
    if (id.trim().isEmpty || id != idFor(playerId)) {
      throw const FormatException('Invalid rookie contract identity');
    }
    if (playerId.value.trim().isEmpty || teamId.value.trim().isEmpty) {
      throw const FormatException('Rookie contract requires player and team');
    }
    if (!isSupportedCategory(category)) {
      throw FormatException(
        'Unsupported rookie contract category: ${category.jsonValue}',
      );
    }
    if (startYear < 1 || draftSeasonYear < 1 || startYear < draftSeasonYear) {
      throw const FormatException('Invalid rookie contract start year');
    }
    if (overallPick < 1 || overallPick > 60) {
      throw const FormatException('Invalid rookie contract draft pick');
    }
    if (durationYears < minDurationYears ||
        durationYears > maxDurationFor(category)) {
      throw FormatException(
        'Invalid rookie contract duration $durationYears for ${category.jsonValue}',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'playerId': playerId.value,
    'teamId': teamId.value,
    'category': category.jsonValue,
    'startYear': startYear,
    'durationYears': durationYears,
    'draftSeasonYear': draftSeasonYear,
    'overallPick': overallPick,
  };
}
