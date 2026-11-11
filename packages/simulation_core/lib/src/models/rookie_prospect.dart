import 'ids.dart';
import 'player_attributes.dart';
import 'player_career_profile.dart';
import 'position.dart';

/// An individual rookie prospect eligible for the rookie draft.
final class RookieProspect {
  const RookieProspect({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.position,
    required this.age,
    required this.attributes,
    required this.potential,
    required this.trajectory,
    required this.projectedRank,
    required this.estimatedPotentialGrade,
    required this.estimatedPotentialRange,
  });

  factory RookieProspect.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] as String?;
    final firstName = json['firstName'] as String?;
    final lastName = json['lastName'] as String?;
    final rawPosition = json['position'] as String?;
    final age = json['age'] as int?;
    final rawAttributes = json['attributes'] as Map<String, dynamic>?;
    final potential = json['potential'] as int?;
    final rawTrajectory = json['trajectory'] as String?;
    final projectedRank = json['projectedRank'] as int?;
    final estimatedGrade = json['estimatedPotentialGrade'] as String?;
    final estimatedRange = json['estimatedPotentialRange'] as String?;

    if (rawId == null ||
        firstName == null ||
        lastName == null ||
        rawPosition == null ||
        age == null ||
        rawAttributes == null ||
        potential == null ||
        rawTrajectory == null ||
        projectedRank == null ||
        estimatedGrade == null ||
        estimatedRange == null) {
      throw const FormatException('Malformed RookieProspect JSON');
    }

    return RookieProspect(
      id: PlayerId(rawId),
      firstName: firstName,
      lastName: lastName,
      position: Position.parse(rawPosition),
      age: age,
      attributes: PlayerAttributes.fromJson(rawAttributes),
      potential: potential,
      trajectory: DevelopmentTrajectory.fromJson(rawTrajectory),
      projectedRank: projectedRank,
      estimatedPotentialGrade: estimatedGrade,
      estimatedPotentialRange: estimatedRange,
    );
  }

  final PlayerId id;
  final String firstName;
  final String lastName;
  final Position position;
  final int age;
  final PlayerAttributes attributes;
  final int potential;
  final DevelopmentTrajectory trajectory;
  final int projectedRank;
  final String estimatedPotentialGrade;
  final String estimatedPotentialRange;

  String get fullName => '$firstName $lastName'.trim();

  int get overallRating => attributes.overallRating;

  void validate() {
    if (age < 19 || age > 22) {
      throw FormatException('Prospect age $age must be between 19 and 22');
    }
    if (potential < overallRating || potential > 100) {
      throw FormatException(
        'Prospect potential $potential must be between overall ($overallRating) and 100',
      );
    }
    if (projectedRank < 1 || projectedRank > 90) {
      throw FormatException(
        'Prospect projectedRank $projectedRank must be between 1 and 90',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id.value,
    'firstName': firstName,
    'lastName': lastName,
    'position': position.shortName,
    'age': age,
    'attributes': attributes.toJson(),
    'potential': potential,
    'trajectory': trajectory.jsonValue,
    'projectedRank': projectedRank,
    'estimatedPotentialGrade': estimatedPotentialGrade,
    'estimatedPotentialRange': estimatedPotentialRange,
  };
}
