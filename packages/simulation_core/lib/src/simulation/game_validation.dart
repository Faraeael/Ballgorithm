/// Machine-readable M002 failure reasons. Never parse [GameValidationIssue.message].
enum GameValidationCode {
  emptyGameId,
  emptyPossessionId,
  teamsNotDistinct,
  teamNotFound,
  invalidLineupSize,
  invalidLineupPositions,
  duplicateLineupPlayer,
  foreignLineupPlayer,
  duplicatePlayerAcrossLineups,
  invalidRules,
  unsupportedRulesVersion,
  unsupportedSimulationVersion,
  unsupportedEventSchemaVersion,
  invalidSeed,
  invalidFingerprint,
  malformedEventJson,
  unsupportedEventType,
  invalidEventSequence,
  eventBeforeGameStarted,
  gameAlreadyStarted,
  duplicateGameStarted,
  eventAfterGameEnded,
  periodOutOfRange,
  periodAlreadyStarted,
  periodNotStarted,
  periodAlreadyEnded,
  invalidGameClock,
  gameClockIncreased,
  invalidShotClock,
  illegalShotClockIncrease,
  shotClockElapsedMismatch,
  deadBallClockAdvanced,
  possessionAlreadyOpen,
  noOpenPossession,
  wrongOffenseTeam,
  playerNotActive,
  wrongTeam,
  assistInvalid,
  blockInvalid,
  andOneInvalid,
  foulKindInvalid,
  freeThrowsInvalid,
  freeThrowSequenceInvalid,
  reboundInvalid,
  reboundDuplicate,
  reboundWrongTeam,
  deadBallInvalid,
  turnoverInvalid,
  stealInvalid,
  possessionEndReasonInvalid,
  periodEndInvalid,
  gameEndInvalid,
  eventLimitExceeded,
  zeroTimeEventLimitExceeded,
  overtimeLimitExceeded,
  overtimeNotTied,
  periodHornPrecedence,
}

final class GameValidationIssue {
  const GameValidationIssue({
    required this.code,
    required this.path,
    required this.message,
  });

  final GameValidationCode code;
  final String path;
  final String message;

  @override
  String toString() => '${code.name} at $path: $message';
}

final class GameValidationException implements Exception {
  GameValidationException(List<GameValidationIssue> issues)
    : issues = List.unmodifiable(issues) {
    if (issues.isEmpty) {
      throw ArgumentError('GameValidationException requires an issue');
    }
  }

  final List<GameValidationIssue> issues;

  List<GameValidationCode> get codes => [for (final i in issues) i.code];

  @override
  String toString() => 'GameValidationException: ${issues.join('; ')}';
}
