import '../validation/validation_result.dart';

/// A player's true ability. Ratings are explicit integers in `0..100`.
///
/// Scouting observation of these values belongs to a later milestone and is
/// deliberately absent here.
final class PlayerAttributes {
  PlayerAttributes({
    required this.insideScoring,
    required this.midrange,
    required this.threePoint,
    required this.freeThrow,
    required this.passing,
    required this.ballHandling,
    required this.perimeterDefense,
    required this.interiorDefense,
    required this.rebounding,
    required this.athleticism,
    required this.stamina,
    required this.basketballIQ,
  }) {
    final issues = <ValidationIssue>[];
    for (final entry in asMap.entries) {
      final value = entry.value;
      if (value < minRating || value > maxRating) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.attributeOutOfRange,
            path: 'attributes.${entry.key}',
            message: '${entry.key} must be $minRating..$maxRating, got $value',
          ),
        );
      }
    }
    ValidationResult(issues).throwIfInvalid();
  }

  factory PlayerAttributes.fromJson(Map<String, Object?> json) {
    final issues = <ValidationIssue>[];
    final values = <String, int>{};
    for (final name in attributeNames) {
      final raw = json[name];
      if (raw == null) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.attributeMissing,
            path: 'attributes.$name',
            message: 'missing attribute $name',
          ),
        );
        continue;
      }
      if (raw is! int) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.malformedJson,
            path: 'attributes.$name',
            message: 'attribute $name must be an integer, got $raw',
          ),
        );
        continue;
      }
      values[name] = raw;
    }
    ValidationResult(issues).throwIfInvalid();
    return PlayerAttributes(
      insideScoring: values['insideScoring']!,
      midrange: values['midrange']!,
      threePoint: values['threePoint']!,
      freeThrow: values['freeThrow']!,
      passing: values['passing']!,
      ballHandling: values['ballHandling']!,
      perimeterDefense: values['perimeterDefense']!,
      interiorDefense: values['interiorDefense']!,
      rebounding: values['rebounding']!,
      athleticism: values['athleticism']!,
      stamina: values['stamina']!,
      basketballIQ: values['basketballIQ']!,
    );
  }

  static const int minRating = 0;
  static const int maxRating = 100;

  static const List<String> attributeNames = [
    'insideScoring',
    'midrange',
    'threePoint',
    'freeThrow',
    'passing',
    'ballHandling',
    'perimeterDefense',
    'interiorDefense',
    'rebounding',
    'athleticism',
    'stamina',
    'basketballIQ',
  ];

  final int insideScoring;
  final int midrange;
  final int threePoint;
  final int freeThrow;
  final int passing;
  final int ballHandling;
  final int perimeterDefense;
  final int interiorDefense;
  final int rebounding;
  final int athleticism;
  final int stamina;
  final int basketballIQ;

  /// Stable attribute order; also the JSON key order and the UI row order.
  Map<String, int> get asMap => {
    'insideScoring': insideScoring,
    'midrange': midrange,
    'threePoint': threePoint,
    'freeThrow': freeThrow,
    'passing': passing,
    'ballHandling': ballHandling,
    'perimeterDefense': perimeterDefense,
    'interiorDefense': interiorDefense,
    'rebounding': rebounding,
    'athleticism': athleticism,
    'stamina': stamina,
    'basketballIQ': basketballIQ,
  };

  Map<String, Object?> toJson() => asMap;
}
