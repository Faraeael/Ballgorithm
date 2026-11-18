import '../models/ids.dart';
import '../models/player_career_profile.dart';
import '../models/position.dart';

/// Immutable historical record of a player who retired from the league.
///
/// Policy-neutral archival metadata: does not encode contract buyout or
/// dead-cap rules.
final class RetiredPlayerRecord {
  RetiredPlayerRecord({
    required this.playerId,
    required this.fullName,
    required this.position,
    required this.finalAge,
    required this.retiredAfterYear,
    this.lastTeamId,
    required this.finalOverall,
  }) {
    validate();
  }

  factory RetiredPlayerRecord.fromJson(Map<String, dynamic> json) {
    final playerId = json['playerId'];
    final fullName = json['fullName'];
    final position = json['position'];
    final finalAge = json['finalAge'];
    final retiredAfterYear = json['retiredAfterYear'];
    final lastTeamId = json['lastTeamId'];
    final finalOverall = json['finalOverall'];
    if (playerId is! String ||
        fullName is! String ||
        position is! String ||
        finalAge is! int ||
        retiredAfterYear is! int ||
        (lastTeamId != null && lastTeamId is! String) ||
        finalOverall is! int) {
      throw const FormatException('Malformed RetiredPlayerRecord JSON');
    }
    return RetiredPlayerRecord(
      playerId: PlayerId(playerId),
      fullName: fullName,
      position: Position.parse(position, path: 'retiredPlayer.position'),
      finalAge: finalAge,
      retiredAfterYear: retiredAfterYear,
      lastTeamId: lastTeamId == null ? null : TeamId(lastTeamId as String),
      finalOverall: finalOverall,
    );
  }

  final PlayerId playerId;
  final String fullName;
  final Position position;
  final int finalAge;
  final int retiredAfterYear;
  final TeamId? lastTeamId;
  final int finalOverall;

  void validate() {
    if (playerId.value.trim().isEmpty || fullName.trim().isEmpty) {
      throw const FormatException(
        'RetiredPlayerRecord requires non-empty playerId and fullName',
      );
    }
    if (finalAge < PlayerCareerProfile.minAge ||
        finalAge > PlayerCareerProfile.maxAge) {
      throw FormatException(
        'RetiredPlayerRecord finalAge $finalAge outside '
        '${PlayerCareerProfile.minAge}..${PlayerCareerProfile.maxAge}',
      );
    }
    if (retiredAfterYear < 1) {
      throw FormatException(
        'RetiredPlayerRecord retiredAfterYear must be >= 1, got $retiredAfterYear',
      );
    }
    if (lastTeamId != null && lastTeamId!.value.trim().isEmpty) {
      throw const FormatException(
        'RetiredPlayerRecord lastTeamId must not be blank when provided',
      );
    }
    if (finalOverall < 0 || finalOverall > 100) {
      throw FormatException(
        'RetiredPlayerRecord finalOverall $finalOverall outside 0..100',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'playerId': playerId.value,
    'fullName': fullName,
    'position': position.shortName,
    'finalAge': finalAge,
    'retiredAfterYear': retiredAfterYear,
    'lastTeamId': lastTeamId?.value,
    'finalOverall': finalOverall,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RetiredPlayerRecord &&
          playerId == other.playerId &&
          fullName == other.fullName &&
          position == other.position &&
          finalAge == other.finalAge &&
          retiredAfterYear == other.retiredAfterYear &&
          lastTeamId == other.lastTeamId &&
          finalOverall == other.finalOverall;

  @override
  int get hashCode => Object.hash(
    playerId,
    fullName,
    position,
    finalAge,
    retiredAfterYear,
    lastTeamId,
    finalOverall,
  );
}
