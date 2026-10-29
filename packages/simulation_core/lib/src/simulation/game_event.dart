import 'game_validation.dart';
import 'game_versions.dart';

enum PossessionEndReason {
  madeFieldGoal('madeFieldGoal'),
  turnover('turnover'),
  defensiveRebound('defensiveRebound'),
  madeFinalFreeThrow('madeFinalFreeThrow'),
  periodEnd('periodEnd');

  const PossessionEndReason(this.wire);
  final String wire;

  static PossessionEndReason parse(String raw, String path) {
    for (final value in values) {
      if (value.wire == raw) return value;
    }
    throw _malformed(path, 'unknown possession end reason "$raw"');
  }
}

enum FoulKind {
  shooting('shooting'),
  nonShooting('nonShooting'),
  offensive('offensive');

  const FoulKind(this.wire);
  final String wire;

  static FoulKind parse(String raw, String path) {
    for (final value in values) {
      if (value.wire == raw) return value;
    }
    throw _malformed(path, 'unknown foul kind "$raw"');
  }
}

enum TurnoverReason {
  steal('steal'),
  shotClock('shotClock'),
  offensiveFoul('offensiveFoul'),

  /// Offensive giveaway with no credited defensive steal: simplified bad
  /// pass, travel, lost ball or out-of-bounds. Amendment 001.
  nonSteal('nonSteal');

  const TurnoverReason(this.wire);
  final String wire;

  static TurnoverReason parse(String raw, String path) {
    for (final value in values) {
      if (value.wire == raw) return value;
    }
    throw _malformed(path, 'unknown turnover reason "$raw"');
  }
}

enum DeadBallReason {
  periodEnd('periodEnd');

  const DeadBallReason(this.wire);
  final String wire;

  static DeadBallReason parse(String raw, String path) {
    for (final value in values) {
      if (value.wire == raw) return value;
    }
    throw _malformed(path, 'unknown dead-ball reason "$raw"');
  }
}

/// Immutable typed event. Sequence IDs start at 1 and increase strictly.
sealed class GameEvent {
  const GameEvent({
    required this.sequence,
    required this.period,
    required this.gameClock,
    required this.shotClock,
  });

  final int sequence;
  final int period;
  final int gameClock;
  final int? shotClock;

  String get type;

  Map<String, Object?> toJson();

  Map<String, Object?> _baseJson() => {
    'sequence': sequence,
    'type': type,
    'period': period,
    'gameClock': gameClock,
    'shotClock': shotClock,
  };

  static GameEvent fromJson(
    Map<String, Object?> json, {
    String path = 'event',
  }) {
    final type = _str(json, 'type', path);
    final sequence = _int(json, 'sequence', path);
    final period = _int(json, 'period', path);
    final gameClock = _int(json, 'gameClock', path);
    final shotClock = _optInt(json, 'shotClock', path);
    switch (type) {
      case 'GameStarted':
        return GameStarted(
          sequence: sequence,
          period: period,
          gameClock: gameClock,
          shotClock: shotClock,
          homeTeamId: _str(json, 'homeTeamId', path),
          awayTeamId: _str(json, 'awayTeamId', path),
          startingTeamId: _str(json, 'startingTeamId', path),
        );
      case 'GameEnded':
        return GameEnded(
          sequence: sequence,
          period: period,
          gameClock: gameClock,
          shotClock: shotClock,
          finalPeriod: _int(json, 'finalPeriod', path),
        );
      case 'PeriodStarted':
        return PeriodStarted(
          sequence: sequence,
          period: period,
          gameClock: gameClock,
          shotClock: shotClock,
          startingTeamId: _str(json, 'startingTeamId', path),
        );
      case 'PeriodEnded':
        return PeriodEnded(
          sequence: sequence,
          period: period,
          gameClock: gameClock,
          shotClock: shotClock,
        );
      case 'PossessionStarted':
        return PossessionStarted(
          sequence: sequence,
          period: period,
          gameClock: gameClock,
          shotClock: shotClock,
          possessionId: _str(json, 'possessionId', path),
          offenseTeamId: _str(json, 'offenseTeamId', path),
        );
      case 'PossessionEnded':
        return PossessionEnded(
          sequence: sequence,
          period: period,
          gameClock: gameClock,
          shotClock: shotClock,
          possessionId: _str(json, 'possessionId', path),
          offenseTeamId: _str(json, 'offenseTeamId', path),
          reason: PossessionEndReason.parse(_str(json, 'reason', path), path),
        );
      case 'FieldGoalAttempt':
        return FieldGoalAttempt(
          sequence: sequence,
          period: period,
          gameClock: gameClock,
          shotClock: shotClock,
          teamId: _str(json, 'teamId', path),
          shooterId: _str(json, 'shooterId', path),
          shotValue: _int(json, 'shotValue', path),
          made: _bool(json, 'made', path),
          assistedById: _optStr(json, 'assistedById', path),
          blockedById: _optStr(json, 'blockedById', path),
          andOne: _bool(json, 'andOne', path),
        );
      case 'PersonalFoul':
        return PersonalFoul(
          sequence: sequence,
          period: period,
          gameClock: gameClock,
          shotClock: shotClock,
          committingTeamId: _str(json, 'committingTeamId', path),
          committingPlayerId: _str(json, 'committingPlayerId', path),
          drawnByPlayerId: _optStr(json, 'drawnByPlayerId', path),
          kind: FoulKind.parse(_str(json, 'kind', path), path),
          freeThrowsAwarded: _int(json, 'freeThrowsAwarded', path),
          bonus: _bool(json, 'bonus', path),
        );
      case 'FreeThrowAttempt':
        return FreeThrowAttempt(
          sequence: sequence,
          period: period,
          gameClock: gameClock,
          shotClock: shotClock,
          teamId: _str(json, 'teamId', path),
          shooterId: _str(json, 'shooterId', path),
          groupId: _str(json, 'groupId', path),
          attemptIndex: _int(json, 'attemptIndex', path),
          attemptsInGroup: _int(json, 'attemptsInGroup', path),
          made: _bool(json, 'made', path),
          lastOfGroup: _bool(json, 'lastOfGroup', path),
        );
      case 'Rebound':
        return Rebound(
          sequence: sequence,
          period: period,
          gameClock: gameClock,
          shotClock: shotClock,
          teamId: _str(json, 'teamId', path),
          playerId: _str(json, 'playerId', path),
          offensive: _bool(json, 'offensive', path),
          missedEventSequence: _int(json, 'missedEventSequence', path),
        );
      case 'DeadBallMiss':
        return DeadBallMiss(
          sequence: sequence,
          period: period,
          gameClock: gameClock,
          shotClock: shotClock,
          teamId: _str(json, 'teamId', path),
          missedEventSequence: _int(json, 'missedEventSequence', path),
          reason: DeadBallReason.parse(_str(json, 'reason', path), path),
        );
      case 'Turnover':
        return Turnover(
          sequence: sequence,
          period: period,
          gameClock: gameClock,
          shotClock: shotClock,
          teamId: _str(json, 'teamId', path),
          playerId: _str(json, 'playerId', path),
          reason: TurnoverReason.parse(_str(json, 'reason', path), path),
          stolenById: _optStr(json, 'stolenById', path),
        );
      default:
        throw GameValidationException([
          GameValidationIssue(
            code: GameValidationCode.unsupportedEventType,
            path: path,
            message: 'unsupported event type "$type"',
          ),
        ]);
    }
  }
}

final class GameStarted extends GameEvent {
  const GameStarted({
    required super.sequence,
    required super.period,
    required super.gameClock,
    required super.shotClock,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.startingTeamId,
  });

  final String homeTeamId;
  final String awayTeamId;
  final String startingTeamId;

  @override
  String get type => 'GameStarted';

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson(),
    'homeTeamId': homeTeamId,
    'awayTeamId': awayTeamId,
    'startingTeamId': startingTeamId,
  };
}

final class GameEnded extends GameEvent {
  const GameEnded({
    required super.sequence,
    required super.period,
    required super.gameClock,
    required super.shotClock,
    required this.finalPeriod,
  });

  final int finalPeriod;

  @override
  String get type => 'GameEnded';

  @override
  Map<String, Object?> toJson() => {..._baseJson(), 'finalPeriod': finalPeriod};
}

final class PeriodStarted extends GameEvent {
  const PeriodStarted({
    required super.sequence,
    required super.period,
    required super.gameClock,
    required super.shotClock,
    required this.startingTeamId,
  });

  final String startingTeamId;

  @override
  String get type => 'PeriodStarted';

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson(),
    'startingTeamId': startingTeamId,
  };
}

final class PeriodEnded extends GameEvent {
  const PeriodEnded({
    required super.sequence,
    required super.period,
    required super.gameClock,
    required super.shotClock,
  });

  @override
  String get type => 'PeriodEnded';

  @override
  Map<String, Object?> toJson() => _baseJson();
}

final class PossessionStarted extends GameEvent {
  const PossessionStarted({
    required super.sequence,
    required super.period,
    required super.gameClock,
    required super.shotClock,
    required this.possessionId,
    required this.offenseTeamId,
  });

  final String possessionId;
  final String offenseTeamId;

  @override
  String get type => 'PossessionStarted';

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson(),
    'possessionId': possessionId,
    'offenseTeamId': offenseTeamId,
  };
}

final class PossessionEnded extends GameEvent {
  const PossessionEnded({
    required super.sequence,
    required super.period,
    required super.gameClock,
    required super.shotClock,
    required this.possessionId,
    required this.offenseTeamId,
    required this.reason,
  });

  final String possessionId;
  final String offenseTeamId;
  final PossessionEndReason reason;

  @override
  String get type => 'PossessionEnded';

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson(),
    'possessionId': possessionId,
    'offenseTeamId': offenseTeamId,
    'reason': reason.wire,
  };
}

final class FieldGoalAttempt extends GameEvent {
  const FieldGoalAttempt({
    required super.sequence,
    required super.period,
    required super.gameClock,
    required super.shotClock,
    required this.teamId,
    required this.shooterId,
    required this.shotValue,
    required this.made,
    required this.andOne,
    this.assistedById,
    this.blockedById,
  });

  final String teamId;
  final String shooterId;
  final int shotValue;
  final bool made;
  final bool andOne;
  final String? assistedById;
  final String? blockedById;

  @override
  String get type => 'FieldGoalAttempt';

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson(),
    'teamId': teamId,
    'shooterId': shooterId,
    'shotValue': shotValue,
    'made': made,
    'assistedById': assistedById,
    'blockedById': blockedById,
    'andOne': andOne,
  };
}

final class PersonalFoul extends GameEvent {
  const PersonalFoul({
    required super.sequence,
    required super.period,
    required super.gameClock,
    required super.shotClock,
    required this.committingTeamId,
    required this.committingPlayerId,
    required this.kind,
    required this.freeThrowsAwarded,
    required this.bonus,
    this.drawnByPlayerId,
  });

  final String committingTeamId;
  final String committingPlayerId;
  final String? drawnByPlayerId;
  final FoulKind kind;
  final int freeThrowsAwarded;
  final bool bonus;

  @override
  String get type => 'PersonalFoul';

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson(),
    'committingTeamId': committingTeamId,
    'committingPlayerId': committingPlayerId,
    'drawnByPlayerId': drawnByPlayerId,
    'kind': kind.wire,
    'freeThrowsAwarded': freeThrowsAwarded,
    'bonus': bonus,
  };
}

final class FreeThrowAttempt extends GameEvent {
  const FreeThrowAttempt({
    required super.sequence,
    required super.period,
    required super.gameClock,
    required super.shotClock,
    required this.teamId,
    required this.shooterId,
    required this.groupId,
    required this.attemptIndex,
    required this.attemptsInGroup,
    required this.made,
    required this.lastOfGroup,
  });

  final String teamId;
  final String shooterId;
  final String groupId;
  final int attemptIndex;
  final int attemptsInGroup;
  final bool made;
  final bool lastOfGroup;

  @override
  String get type => 'FreeThrowAttempt';

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson(),
    'teamId': teamId,
    'shooterId': shooterId,
    'groupId': groupId,
    'attemptIndex': attemptIndex,
    'attemptsInGroup': attemptsInGroup,
    'made': made,
    'lastOfGroup': lastOfGroup,
  };
}

final class Rebound extends GameEvent {
  const Rebound({
    required super.sequence,
    required super.period,
    required super.gameClock,
    required super.shotClock,
    required this.teamId,
    required this.playerId,
    required this.offensive,
    required this.missedEventSequence,
  });

  final String teamId;
  final String playerId;
  final bool offensive;
  final int missedEventSequence;

  @override
  String get type => 'Rebound';

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson(),
    'teamId': teamId,
    'playerId': playerId,
    'offensive': offensive,
    'missedEventSequence': missedEventSequence,
  };
}

final class DeadBallMiss extends GameEvent {
  const DeadBallMiss({
    required super.sequence,
    required super.period,
    required super.gameClock,
    required super.shotClock,
    required this.teamId,
    required this.missedEventSequence,
    required this.reason,
  });

  final String teamId;
  final int missedEventSequence;
  final DeadBallReason reason;

  @override
  String get type => 'DeadBallMiss';

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson(),
    'teamId': teamId,
    'missedEventSequence': missedEventSequence,
    'reason': reason.wire,
  };
}

final class Turnover extends GameEvent {
  const Turnover({
    required super.sequence,
    required super.period,
    required super.gameClock,
    required super.shotClock,
    required this.teamId,
    required this.playerId,
    required this.reason,
    this.stolenById,
  });

  final String teamId;
  final String playerId;
  final TurnoverReason reason;
  final String? stolenById;

  @override
  String get type => 'Turnover';

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson(),
    'teamId': teamId,
    'playerId': playerId,
    'reason': reason.wire,
    'stolenById': stolenById,
  };
}

/// Canonical ledger header + ordered events.
final class GameEventLedger {
  GameEventLedger({
    required this.gameId,
    required this.inputFingerprint,
    required List<GameEvent> events,
  }) : events = List.unmodifiable(events);

  final String gameId;
  final String inputFingerprint;
  final List<GameEvent> events;

  Map<String, Object?> toJson() => {
    'eventSchemaVersion': gameEventSchemaVersion,
    'gameSimulationVersion': gameSimulationVersion,
    'gameRulesVersion': gameRulesVersion,
    'prngImplementationId': 'xorshift32-v1',
    'inputFingerprint': inputFingerprint,
    'gameId': gameId,
    'events': [for (final event in events) event.toJson()],
  };

  factory GameEventLedger.fromJson(Map<String, Object?> json) {
    final issues = <GameValidationIssue>[];
    void check(
      bool condition,
      GameValidationCode code,
      String path,
      String message,
    ) {
      if (!condition) {
        issues.add(
          GameValidationIssue(code: code, path: path, message: message),
        );
      }
    }

    check(
      _intOrNull(json, 'eventSchemaVersion') == gameEventSchemaVersion,
      GameValidationCode.unsupportedEventSchemaVersion,
      'eventSchemaVersion',
      'unsupported event schema version',
    );
    check(
      _intOrNull(json, 'gameSimulationVersion') == gameSimulationVersion,
      GameValidationCode.unsupportedSimulationVersion,
      'gameSimulationVersion',
      'unsupported simulation version',
    );
    check(
      _intOrNull(json, 'gameRulesVersion') == gameRulesVersion,
      GameValidationCode.unsupportedRulesVersion,
      'gameRulesVersion',
      'unsupported rules version',
    );
    check(
      json['prngImplementationId'] == 'xorshift32-v1',
      GameValidationCode.unsupportedSimulationVersion,
      'prngImplementationId',
      'unsupported PRNG implementation',
    );
    final fingerprint = json['inputFingerprint'];
    check(
      fingerprint is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint),
      GameValidationCode.invalidFingerprint,
      'inputFingerprint',
      'fingerprint must be 64 lowercase hex characters',
    );
    check(
      json['gameId'] is String && (json['gameId'] as String).trim().isNotEmpty,
      GameValidationCode.emptyGameId,
      'gameId',
      'gameId must be non-empty',
    );
    final rawEvents = json['events'];
    check(
      rawEvents is List<Object?>,
      GameValidationCode.malformedEventJson,
      'events',
      'events must be a list',
    );
    if (issues.isNotEmpty) throw GameValidationException(issues);

    final events = <GameEvent>[];
    final eventList = rawEvents as List<Object?>;
    for (var i = 0; i < eventList.length; i++) {
      final raw = eventList[i];
      if (raw is! Map<String, Object?>) {
        throw GameValidationException([
          const GameValidationIssue(
            code: GameValidationCode.malformedEventJson,
            path: 'events',
            message: 'event must be an object',
          ),
        ]);
      }
      events.add(GameEvent.fromJson(raw, path: 'events[$i]'));
    }
    return GameEventLedger(
      gameId: json['gameId']! as String,
      inputFingerprint: fingerprint! as String,
      events: events,
    );
  }
}

Never _malformed(String path, String message) {
  throw GameValidationException([
    GameValidationIssue(
      code: GameValidationCode.malformedEventJson,
      path: path,
      message: message,
    ),
  ]);
}

String _str(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    _malformed('$path.$key', 'required non-empty string');
  }
  return value;
}

String? _optStr(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    _malformed('$path.$key', 'optional value must be a non-empty string');
  }
  return value;
}

int _int(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int) _malformed('$path.$key', 'required integer');
  return value;
}

int? _optInt(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int) {
    _malformed('$path.$key', 'optional value must be an integer');
  }
  return value;
}

int? _intOrNull(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is int ? value : null;
}

bool _bool(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) _malformed('$path.$key', 'required boolean');
  return value;
}
