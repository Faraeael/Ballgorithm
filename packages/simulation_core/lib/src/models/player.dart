import '../validation/validation_result.dart';
import 'ids.dart';
import 'player_attributes.dart';
import 'position.dart';

final class Player {
  Player({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.position,
    required this.attributes,
  });

  factory Player.fromJson(Map<String, Object?> json, {String path = 'player'}) {
    final id = json['id'];
    final firstName = json['firstName'];
    final lastName = json['lastName'];
    final position = json['position'];
    final attributes = json['attributes'];
    if (id is! String ||
        firstName is! String ||
        lastName is! String ||
        position is! String ||
        attributes is! Map<String, Object?>) {
      throw DomainValidationException([
        ValidationIssue(
          code: ValidationCode.malformedJson,
          path: path,
          message:
              'player requires string id, names, position and attribute map',
        ),
      ]);
    }
    return Player(
      id: PlayerId(id),
      firstName: firstName,
      lastName: lastName,
      position: Position.parse(position, path: '$path.position'),
      attributes: PlayerAttributes.fromJson(attributes),
    );
  }

  final PlayerId id;
  final String firstName;
  final String lastName;
  final Position position;
  final PlayerAttributes attributes;

  String get fullName => '$firstName $lastName'.trim();

  Map<String, Object?> toJson() => {
    'id': id.value,
    'firstName': firstName,
    'lastName': lastName,
    'position': position.shortName,
    'attributes': attributes.toJson(),
  };
}
