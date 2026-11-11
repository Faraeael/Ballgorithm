import 'ids.dart';
import 'player_attributes.dart';
import 'position.dart';
import 'rookie_prospect.dart';

/// Restricted public scouting view of a rookie prospect.
///
/// Contains ONLY public, observable information: attributes, overall rating,
/// consensus projected ranking, estimated potential grade, and estimated ceiling range.
///
/// Deliberately and strictly omits hidden true potential ceiling and developmental
/// trajectory curves to ensure AI evaluation fairness.
final class PublicProspectScoutingView {
  const PublicProspectScoutingView({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.position,
    required this.age,
    required this.attributes,
    required this.overallRating,
    required this.projectedRank,
    required this.estimatedPotentialGrade,
    required this.estimatedPotentialRange,
  });

  factory PublicProspectScoutingView.fromProspect(RookieProspect prospect) {
    return PublicProspectScoutingView(
      id: prospect.id,
      firstName: prospect.firstName,
      lastName: prospect.lastName,
      position: prospect.position,
      age: prospect.age,
      attributes: prospect.attributes,
      overallRating: prospect.overallRating,
      projectedRank: prospect.projectedRank,
      estimatedPotentialGrade: prospect.estimatedPotentialGrade,
      estimatedPotentialRange: prospect.estimatedPotentialRange,
    );
  }

  final PlayerId id;
  final String firstName;
  final String lastName;
  final Position position;
  final int age;
  final PlayerAttributes attributes;
  final int overallRating;
  final int projectedRank;
  final String estimatedPotentialGrade;
  final String estimatedPotentialRange;

  String get fullName => '$firstName $lastName'.trim();
}
