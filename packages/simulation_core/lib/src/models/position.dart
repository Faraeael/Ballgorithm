import '../validation/validation_result.dart';

enum Position {
  pg('PG', 'Point Guard'),
  sg('SG', 'Shooting Guard'),
  sf('SF', 'Small Forward'),
  pf('PF', 'Power Forward'),
  c('C', 'Center');

  const Position(this.shortName, this.fullName);

  final String shortName;
  final String fullName;

  static Position parse(String raw, {String path = 'position'}) {
    for (final position in values) {
      if (position.shortName == raw) {
        return position;
      }
    }
    throw DomainValidationException([
      ValidationIssue(
        code: ValidationCode.unknownPosition,
        path: path,
        message: 'unknown position "$raw"',
      ),
    ]);
  }
}
