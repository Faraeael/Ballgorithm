import 'draft_rights.dart';
import 'ids.dart';
import 'player.dart';
import 'player_attributes.dart';
import 'player_career_profile.dart';
import 'position.dart';
import 'rookie_prospect.dart';

/// Immutable career-level snapshot of an unsigned drafted prospect carried
/// across seasons (M009-T05C-C2-C1).
///
/// Authoritative team ownership lives in `GmCareer.careerDraftRights`; this
/// record links to `DraftRights` by [playerId], [draftSeasonYear], and
/// [overallPick] without duplicating conflicting franchise ownership.
final class CarriedUnsignedProspect {
  const CarriedUnsignedProspect({
    required this.playerId,
    required this.firstName,
    required this.lastName,
    required this.position,
    required this.attributes,
    required this.age,
    required this.potential,
    required this.trajectory,
    required this.draftSeasonYear,
    required this.overallPick,
    required this.projectedRank,
    required this.estimatedPotentialGrade,
    required this.estimatedPotentialRange,
  });

  factory CarriedUnsignedProspect.fromRookieProspect({
    required RookieProspect prospect,
    required DraftRights rights,
    required int age,
  }) {
    prospect.validate();
    rights.validate();
    if (prospect.id != rights.prospectId) {
      throw ArgumentError(
        'Prospect ${prospect.id.value} does not match DraftRights '
        '${rights.prospectId.value}',
      );
    }
    return CarriedUnsignedProspect(
      playerId: prospect.id,
      firstName: prospect.firstName,
      lastName: prospect.lastName,
      position: prospect.position,
      attributes: prospect.attributes,
      age: age,
      potential: prospect.potential,
      trajectory: prospect.trajectory,
      draftSeasonYear: rights.seasonYear,
      overallPick: rights.overallPick,
      projectedRank: prospect.projectedRank,
      estimatedPotentialGrade: prospect.estimatedPotentialGrade,
      estimatedPotentialRange: prospect.estimatedPotentialRange,
    )..validate();
  }

  factory CarriedUnsignedProspect.fromJson(Map<String, dynamic> json) {
    final playerId = json['playerId'];
    final firstName = json['firstName'];
    final lastName = json['lastName'];
    final position = json['position'];
    final attributes = json['attributes'];
    final age = json['age'];
    final potential = json['potential'];
    final trajectory = json['trajectory'];
    final draftSeasonYear = json['draftSeasonYear'];
    final overallPick = json['overallPick'];
    final projectedRank = json['projectedRank'];
    final estimatedGrade = json['estimatedPotentialGrade'];
    final estimatedRange = json['estimatedPotentialRange'];

    if (playerId is! String ||
        firstName is! String ||
        lastName is! String ||
        position is! String ||
        attributes is! Map<String, dynamic> ||
        age is! int ||
        potential is! int ||
        trajectory is! String ||
        draftSeasonYear is! int ||
        overallPick is! int ||
        projectedRank is! int ||
        estimatedGrade is! String ||
        estimatedRange is! String) {
      throw const FormatException('Malformed CarriedUnsignedProspect JSON');
    }

    return CarriedUnsignedProspect(
      playerId: PlayerId(playerId),
      firstName: firstName,
      lastName: lastName,
      position: Position.parse(position),
      attributes: PlayerAttributes.fromJson(attributes),
      age: age,
      potential: potential,
      trajectory: DevelopmentTrajectory.fromJson(trajectory),
      draftSeasonYear: draftSeasonYear,
      overallPick: overallPick,
      projectedRank: projectedRank,
      estimatedPotentialGrade: estimatedGrade,
      estimatedPotentialRange: estimatedRange,
    )..validate();
  }

  final PlayerId playerId;
  final String firstName;
  final String lastName;
  final Position position;
  final PlayerAttributes attributes;
  final int age;
  final int potential;
  final DevelopmentTrajectory trajectory;
  final int draftSeasonYear;
  final int overallPick;
  final int projectedRank;
  final String estimatedPotentialGrade;
  final String estimatedPotentialRange;

  String get fullName => '$firstName $lastName'.trim();

  int get overallRating => attributes.overallRating;

  CarriedUnsignedProspect withAge(int nextAge) => CarriedUnsignedProspect(
    playerId: playerId,
    firstName: firstName,
    lastName: lastName,
    position: position,
    attributes: attributes,
    age: nextAge,
    potential: potential,
    trajectory: trajectory,
    draftSeasonYear: draftSeasonYear,
    overallPick: overallPick,
    projectedRank: projectedRank,
    estimatedPotentialGrade: estimatedPotentialGrade,
    estimatedPotentialRange: estimatedPotentialRange,
  )..validate();

  Player toPlayer() => Player(
    id: playerId,
    firstName: firstName,
    lastName: lastName,
    position: position,
    attributes: attributes,
  );

  PlayerCareerProfile toProfile() {
    final player = toPlayer();
    return PlayerCareerProfile(
      playerId: playerId,
      age: age,
      potential: potential,
      trajectory: trajectory,
    )..validate(player);
  }

  void validate() {
    if (playerId.value.trim().isEmpty ||
        firstName.trim().isEmpty ||
        lastName.trim().isEmpty) {
      throw const FormatException(
        'CarriedUnsignedProspect requires non-empty id and name',
      );
    }
    if (age < PlayerCareerProfile.minAge || age > PlayerCareerProfile.maxAge) {
      throw FormatException(
        'CarriedUnsignedProspect ${playerId.value} age $age must be between '
        '${PlayerCareerProfile.minAge} and ${PlayerCareerProfile.maxAge}',
      );
    }
    if (potential < overallRating || potential > 100) {
      throw FormatException(
        'CarriedUnsignedProspect ${playerId.value} potential $potential must be '
        'between overall ($overallRating) and 100',
      );
    }
    if (draftSeasonYear < 1 || overallPick < 1 || overallPick > 60) {
      throw const FormatException(
        'CarriedUnsignedProspect has invalid draft provenance',
      );
    }
    if (projectedRank < 1 ||
        projectedRank > 90 ||
        estimatedPotentialGrade.trim().isEmpty ||
        estimatedPotentialRange.trim().isEmpty) {
      throw const FormatException(
        'CarriedUnsignedProspect has invalid scouting metadata',
      );
    }
    toProfile();
  }

  Map<String, dynamic> toJson() => {
    'playerId': playerId.value,
    'firstName': firstName,
    'lastName': lastName,
    'position': position.shortName,
    'attributes': attributes.toJson(),
    'age': age,
    'potential': potential,
    'trajectory': trajectory.jsonValue,
    'draftSeasonYear': draftSeasonYear,
    'overallPick': overallPick,
    'projectedRank': projectedRank,
    'estimatedPotentialGrade': estimatedPotentialGrade,
    'estimatedPotentialRange': estimatedPotentialRange,
  };
}
