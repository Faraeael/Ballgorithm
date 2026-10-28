/// Machine-readable failure reasons. Never parse [ValidationIssue.message].
enum ValidationCode {
  teamCountOutOfRange,
  playersPerTeamOutOfRange,
  nameCapacityExceeded,
  engineVersionEmpty,
  engineVersionMismatch,
  teamCountMismatch,
  rosterSizeMismatch,
  leagueIdEmpty,
  leagueNameEmpty,
  teamIdEmpty,
  teamNameEmpty,
  teamAbbreviationInvalid,
  duplicateTeamId,
  duplicatePlayerId,
  duplicatePlayerAcrossTeams,
  playerIdEmpty,
  playerNameEmpty,
  positionCoverageMissing,
  attributeOutOfRange,
  attributeMissing,
  unknownPosition,
  malformedJson,
  unsupportedSchemaVersion,
}

final class ValidationIssue {
  const ValidationIssue({
    required this.code,
    required this.path,
    required this.message,
  });

  final ValidationCode code;

  /// Location of the problem, e.g. `teams[2].roster.players[5].attributes`.
  final String path;
  final String message;

  @override
  String toString() => '${code.name} at $path: $message';
}

final class ValidationResult {
  const ValidationResult(this.issues);

  static const ValidationResult valid = ValidationResult(<ValidationIssue>[]);

  final List<ValidationIssue> issues;

  bool get isValid => issues.isEmpty;

  List<ValidationCode> get codes => [for (final issue in issues) issue.code];

  void throwIfInvalid() {
    if (issues.isNotEmpty) {
      throw DomainValidationException(issues);
    }
  }
}

/// Thrown when a domain invariant is violated.
final class DomainValidationException implements Exception {
  DomainValidationException(this.issues)
    : assert(issues.isNotEmpty, 'exception requires at least one issue');

  final List<ValidationIssue> issues;

  List<ValidationCode> get codes => [for (final issue in issues) issue.code];

  @override
  String toString() => 'DomainValidationException: ${issues.join('; ')}';
}
