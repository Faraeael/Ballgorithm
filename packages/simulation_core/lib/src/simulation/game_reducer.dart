import '../models/ids.dart';
import 'box_score.dart';
import 'event_accounting.dart';
import 'game_event.dart';
import 'game_fingerprint.dart';
import 'game_input.dart';
import 'game_state.dart';
import 'game_validation.dart';

/// Opaque proof that a ledger successfully passed [GameEventReducer.validate].
final class ValidatedGameLedger {
  ValidatedGameLedger._(this.input, List<GameEvent> events, this.state)
    : events = List.unmodifiable(events);

  final GameInput input;
  final List<GameEvent> events;
  final GameState state;
}

/// Pure replay validator for a typed M002 ledger.
abstract final class GameEventReducer {
  static ValidatedGameLedger validate(GameInput input, GameEventLedger ledger) {
    if (ledger.gameId != input.gameId) {
      _fail(
        GameValidationCode.emptyGameId,
        'gameId',
        'ledger gameId does not match input',
      );
    }
    if (ledger.inputFingerprint != GameFingerprint.of(input)) {
      _fail(
        GameValidationCode.invalidFingerprint,
        'inputFingerprint',
        'ledger fingerprint does not match the input',
      );
    }
    if (ledger.events.isEmpty) {
      _fail(
        GameValidationCode.eventBeforeGameStarted,
        'events',
        'ledger is empty',
      );
    }
    final state = _Replay(input, ledger.events).run();
    return ValidatedGameLedger._(input, ledger.events, state);
  }

  static GameState replay(GameInput input, GameEventLedger ledger) =>
      validate(input, ledger).state;

  static GameState replayEvents(GameInput input, List<GameEvent> events) =>
      _Replay(input, events).run();
}

Never _fail(GameValidationCode code, String path, String message) {
  throw GameValidationException([
    GameValidationIssue(code: code, path: path, message: message),
  ]);
}

final class _Miss {
  const _Miss({
    required this.sequence,
    required this.teamId,
    required this.isFreeThrow,
  });

  final int sequence;
  final String teamId;
  final bool isFreeThrow;
}

final class _FreeThrowGroup {
  _FreeThrowGroup({
    required this.teamId,
    required this.shooterId,
    required this.total,
    required this.gameClock,
    required this.shotClock,
  });

  final String teamId;
  final String shooterId;
  final int total;
  final int gameClock;
  final int? shotClock;
  String? groupId;
}

final class _Replay {
  _Replay(this.input, this.events);

  final GameInput input;
  final List<GameEvent> events;

  GameState _state = GameState.initial;
  int _lastSequence = 0;
  int _lastClock = 0;
  int _zeroTimeEvents = 0;
  bool _periodEnded = false;

  bool _pendingMadeFg = false;
  bool _pendingAndOne = false;
  String? _andOneShooterId;
  _Miss? _pendingMiss;
  bool _pendingDefensiveRebound = false;
  bool _pendingTurnover = false;
  bool _pendingMadeFinalFt = false;
  bool _pendingDeadBall = false;
  bool _pendingOffensiveFoul = false;
  String? _offensiveFoulPlayerId;
  _FreeThrowGroup? _freeThrows;
  int? _pendingShotClockCeiling;
  final Set<int> _resolvedMisses = <int>{};
  final List<GameEvent> _processed = <GameEvent>[];
  final Map<String, int> _teamFouls = <String, int>{};
  int _periodPossessions = 0;
  String? _expectedNextOffenseTeamId;
  String? _periodStartingTeamId;

  GameState run() {
    if (events.length > input.rules.maxEvents) {
      _fail(
        GameValidationCode.eventLimitExceeded,
        'events',
        '${events.length} events exceeds ${input.rules.maxEvents}',
      );
    }
    for (final event in events) {
      _apply(event);
    }
    return _state;
  }

  void _apply(GameEvent event) {
    if (_state.ended) {
      _fail(
        GameValidationCode.eventAfterGameEnded,
        'event ${event.sequence}',
        'no event may follow GameEnded',
      );
    }
    if (event.sequence != _lastSequence + 1) {
      _fail(
        GameValidationCode.invalidEventSequence,
        'event ${event.sequence}',
        'expected sequence ${_lastSequence + 1}',
      );
    }
    if (event.period < 1) {
      _fail(
        GameValidationCode.periodOutOfRange,
        'event ${event.sequence}.period',
        'period ${event.period} outside supported range',
      );
    }
    if (event.period > input.rules.periods + input.rules.maxOvertimes) {
      _fail(
        GameValidationCode.overtimeLimitExceeded,
        'event ${event.sequence}.period',
        'period ${event.period} exceeds the overtime limit',
      );
    }
    final periodLength = input.rules.periodLength(event.period);
    if (event.gameClock < 0 || event.gameClock > periodLength) {
      _fail(
        GameValidationCode.invalidGameClock,
        'event ${event.sequence}.gameClock',
        'gameClock ${event.gameClock} outside 0..$periodLength',
      );
    }
    if (event.shotClock != null &&
        (event.shotClock! < 0 ||
            event.shotClock! > input.rules.shotClockSeconds)) {
      _fail(
        GameValidationCode.invalidShotClock,
        'event ${event.sequence}.shotClock',
        'shotClock ${event.shotClock} outside 0..${input.rules.shotClockSeconds}',
      );
    }
    if (_pendingShotClockCeiling != null) {
      if (event is! PeriodEnded && event is! GameEnded) {
        final sc = event.shotClock;
        if (sc == null || sc > _pendingShotClockCeiling!) {
          _fail(
            GameValidationCode.illegalShotClockIncrease,
            'event ${event.sequence}.shotClock',
            'shot clock must be reset to at most $_pendingShotClockCeiling',
          );
        }
        _pendingShotClockCeiling = null;
      }
    }
    if (_state.started && event.period == _state.period) {
      if (event.gameClock > _state.gameClock) {
        _fail(
          GameValidationCode.gameClockIncreased,
          'event ${event.sequence}.gameClock',
          'game clock cannot increase within a period',
        );
      }
    }
    _updateZeroTimeGuard(event);
    _lastSequence = event.sequence;
    _state = _state.copyWith(eventCount: event.sequence);
    _processed.add(event);

    if (_state.started &&
        event is! GameStarted &&
        event is! PeriodStarted &&
        event.period != _state.period) {
      _fail(
        GameValidationCode.periodNotStarted,
        'event ${event.sequence}.period',
        'event period ${event.period} does not match active period ${_state.period}',
      );
    }

    if (event is GameStarted) {
      _gameStarted(event);
    } else if (!_state.started) {
      _fail(
        GameValidationCode.eventBeforeGameStarted,
        'event ${event.sequence}',
        'GameStarted must be the first event',
      );
    } else if (event is PeriodStarted) {
      _periodStarted(event);
    } else if (event is PeriodEnded) {
      _periodEndedEvent(event);
    } else if (event is GameEnded) {
      _gameEnded(event);
    } else if (event is PossessionStarted) {
      _possessionStarted(event);
    } else if (event is PossessionEnded) {
      _possessionEnded(event);
    } else if (event is FieldGoalAttempt) {
      _fieldGoal(event);
    } else if (event is PersonalFoul) {
      _personalFoul(event);
    } else if (event is FreeThrowAttempt) {
      _freeThrow(event);
    } else if (event is Rebound) {
      _rebound(event);
    } else if (event is DeadBallMiss) {
      _deadBall(event);
    } else if (event is Turnover) {
      _turnoverEvent(event);
    } else {
      _fail(
        GameValidationCode.unsupportedEventType,
        'event ${event.sequence}',
        'unsupported event',
      );
    }
    if (event is! PeriodStarted) {
      _state = _state.copyWith(gameClock: event.gameClock);
      if (_state.hasOpenPossession) {
        final nextShotClock = _pendingShotClockCeiling ?? event.shotClock;
        if (nextShotClock != null) {
          _state = _state.copyWith(shotClock: nextShotClock);
        }
      }
    }
    if (_state.eventCount > input.rules.maxEvents) {
      _fail(
        GameValidationCode.eventLimitExceeded,
        'events',
        'event count exceeds ${input.rules.maxEvents}',
      );
    }
  }

  void _updateZeroTimeGuard(GameEvent event) {
    if (_state.started &&
        event.period == _state.period &&
        event.gameClock == _lastClock) {
      _zeroTimeEvents++;
      if (_zeroTimeEvents > input.rules.maxZeroTimeEvents) {
        _fail(
          GameValidationCode.zeroTimeEventLimitExceeded,
          'event ${event.sequence}',
          'more than ${input.rules.maxZeroTimeEvents} events at the same clock',
        );
      }
    } else {
      _zeroTimeEvents = 1;
      _lastClock = event.gameClock;
    }
  }

  void _gameStarted(GameStarted event) {
    if (_state.started) {
      _fail(
        GameValidationCode.duplicateGameStarted,
        'event ${event.sequence}',
        'GameStarted already occurred',
      );
    }
    if (event.period != 1 || event.gameClock != input.rules.periodSeconds) {
      _fail(
        GameValidationCode.invalidGameClock,
        'event ${event.sequence}',
        'GameStarted must open period 1 at ${input.rules.periodSeconds}',
      );
    }
    if (event.homeTeamId != input.homeTeamId.value ||
        event.awayTeamId != input.awayTeamId.value ||
        event.startingTeamId != input.startingTeamId.value) {
      _fail(
        GameValidationCode.wrongTeam,
        'event ${event.sequence}',
        'GameStarted teams do not match the input',
      );
    }
    _state = _state.copyWith(
      started: true,
      period: 0,
      gameClock: event.gameClock,
    );
  }

  void _periodStarted(PeriodStarted event) {
    if (event.period != _state.period + 1) {
      _fail(
        GameValidationCode.periodOutOfRange,
        'event ${event.sequence}.period',
        'expected period ${_state.period + 1}, got ${event.period}',
      );
    }
    if (!(_periodEnded || event.period == 1)) {
      _fail(
        GameValidationCode.periodAlreadyStarted,
        'event ${event.sequence}',
        'previous period has not ended',
      );
    }
    if (_state.hasOpenPossession ||
        _pendingMiss != null ||
        _freeThrows != null) {
      _fail(
        GameValidationCode.periodAlreadyStarted,
        'event ${event.sequence}',
        'period cannot start with unresolved possession or free throws',
      );
    }
    if (event.gameClock != input.rules.periodLength(event.period) ||
        event.shotClock != null) {
      _fail(
        GameValidationCode.invalidGameClock,
        'event ${event.sequence}',
        'period start must have period length and no shot clock',
      );
    }
    final expectedStarter = _starterFor(event.period);
    if (event.startingTeamId != expectedStarter.value) {
      _fail(
        GameValidationCode.wrongTeam,
        'event ${event.sequence}.startingTeamId',
        'period ${event.period} must be started by ${expectedStarter.value}',
      );
    }
    if (event.period > input.rules.periods) {
      final score = _boxScore();
      if (score.teams[input.homeTeamId.value]!.points !=
          score.teams[input.awayTeamId.value]!.points) {
        _fail(
          GameValidationCode.overtimeNotTied,
          'event ${event.sequence}.period',
          'overtime requires a tied score after the preceding period',
        );
      }
    }
    _periodEnded = false;
    _periodStartingTeamId = event.startingTeamId;
    _periodPossessions = 0;
    _expectedNextOffenseTeamId = null;
    _teamFouls[input.homeTeamId.value] = 0;
    _teamFouls[input.awayTeamId.value] = 0;
    _clearPending();
    _state = _state.copyWith(
      period: event.period,
      gameClock: event.gameClock,
      clearShotClock: true,
      clearPossession: true,
    );
  }

  void _periodEndedEvent(PeriodEnded event) {
    if (_periodEnded) {
      _fail(
        GameValidationCode.periodAlreadyEnded,
        'event ${event.sequence}',
        'period has already ended',
      );
    }
    if (event.period != _state.period) {
      _fail(
        GameValidationCode.periodOutOfRange,
        'event ${event.sequence}.period',
        'period does not match',
      );
    }
    if (_state.hasOpenPossession) {
      _fail(
        GameValidationCode.periodEndInvalid,
        'event ${event.sequence}',
        'possession must end before PeriodEnded',
      );
    }
    if (_freeThrows != null || _pendingMiss != null) {
      _fail(
        GameValidationCode.periodEndInvalid,
        'event ${event.sequence}',
        'free throws or misses must resolve before PeriodEnded',
      );
    }
    if (event.gameClock != 0) {
      _fail(
        GameValidationCode.periodEndInvalid,
        'event ${event.sequence}.gameClock',
        'period can only end at game clock 0',
      );
    }
    _periodEnded = true;
    _expectedNextOffenseTeamId = null;
    _clearPending();
    _state = _state.copyWith(clearPossession: true, clearShotClock: true);
  }

  void _gameEnded(GameEnded event) {
    if (!_periodEnded || _state.hasOpenPossession) {
      _fail(
        GameValidationCode.gameEndInvalid,
        'event ${event.sequence}',
        'GameEnded requires a closed final period',
      );
    }
    if (event.finalPeriod != _state.period ||
        _state.period < input.rules.periods) {
      _fail(
        GameValidationCode.gameEndInvalid,
        'event ${event.sequence}.finalPeriod',
        'GameEnded before the final period or wrong period',
      );
    }
    final score = _boxScore();
    if (score.teams[input.homeTeamId.value]!.points ==
        score.teams[input.awayTeamId.value]!.points) {
      _fail(
        GameValidationCode.gameEndInvalid,
        'event ${event.sequence}',
        'GameEnded cannot end in a tie',
      );
    }
    _state = _state.copyWith(ended: true);
  }

  void _possessionStarted(PossessionStarted event) {
    if (_state.hasOpenPossession) {
      _fail(
        GameValidationCode.possessionAlreadyOpen,
        'event ${event.sequence}',
        'possession ${_state.possessionId} is still open',
      );
    }
    if (event.shotClock != input.rules.shotClockSeconds) {
      _fail(
        GameValidationCode.illegalShotClockIncrease,
        'event ${event.sequence}.shotClock',
        'new possession must start at ${input.rules.shotClockSeconds}',
      );
    }
    if (event.gameClock <= 0) {
      _fail(
        GameValidationCode.possessionAlreadyOpen,
        'event ${event.sequence}',
        'no new possession after the horn',
      );
    }
    if (event.possessionId.trim().isEmpty) {
      _fail(
        GameValidationCode.emptyPossessionId,
        'event ${event.sequence}',
        'possessionId must be non-empty',
      );
    }
    final team = _teamId(event.offenseTeamId);
    if (team == null) {
      _fail(
        GameValidationCode.playerNotActive,
        'event ${event.sequence}',
        'unknown offense team ${event.offenseTeamId}',
      );
    }
    if (_periodPossessions == 0 &&
        event.offenseTeamId != _periodStartingTeamId) {
      _fail(
        GameValidationCode.wrongTeam,
        'event ${event.sequence}',
        'period must open with the team that won the opening possession',
      );
    }
    if (_expectedNextOffenseTeamId != null &&
        event.offenseTeamId != _expectedNextOffenseTeamId) {
      _fail(
        GameValidationCode.wrongTeam,
        'event ${event.sequence}.offenseTeamId',
        'next possession must belong to $_expectedNextOffenseTeamId',
      );
    }
    _expectedNextOffenseTeamId = null;
    _periodPossessions++;
    _clearPending();
    _freeThrows = null;
    _state = _state.copyWith(
      possessionId: event.possessionId,
      offenseTeamId: event.offenseTeamId,
      shotClock: event.shotClock,
    );
  }

  void _possessionEnded(PossessionEnded event) {
    _requirePossession(event);
    if (event.possessionId != _state.possessionId ||
        event.offenseTeamId != _state.offenseTeamId) {
      _fail(
        GameValidationCode.possessionEndReasonInvalid,
        'event ${event.sequence}',
        'possession end does not match the open possession',
      );
    }
    final reason = event.reason;
    if (reason != PossessionEndReason.periodEnd) {
      _requireSameTimestamp(event, GameValidationCode.deadBallClockAdvanced);
      _requireSameShotClock(event);
    }
    final valid = switch (reason) {
      PossessionEndReason.madeFieldGoal => _pendingMadeFg,
      PossessionEndReason.turnover => _pendingTurnover,
      PossessionEndReason.defensiveRebound => _pendingDefensiveRebound,
      PossessionEndReason.madeFinalFreeThrow => _pendingMadeFinalFt,
      PossessionEndReason.periodEnd =>
        event.gameClock == 0 &&
            _pendingMiss == null &&
            !_pendingMadeFg &&
            !_pendingAndOne &&
            !_pendingTurnover &&
            !_pendingDefensiveRebound &&
            !_pendingMadeFinalFt &&
            !_pendingOffensiveFoul &&
            _freeThrows == null,
    };
    if (!valid) {
      _fail(
        GameValidationCode.possessionEndReasonInvalid,
        'event ${event.sequence}.reason',
        'reason ${reason.wire} does not match the preceding outcome',
      );
    }
    switch (reason) {
      case PossessionEndReason.madeFieldGoal:
      case PossessionEndReason.turnover:
      case PossessionEndReason.defensiveRebound:
      case PossessionEndReason.madeFinalFreeThrow:
        _expectedNextOffenseTeamId = input
            .opponentOf(_teamId(event.offenseTeamId)!)
            .value;
      case PossessionEndReason.periodEnd:
        _expectedNextOffenseTeamId = null;
    }
    _clearPending();
    _state = _state.copyWith(clearPossession: true, clearShotClock: true);
  }

  void _fieldGoal(FieldGoalAttempt event) {
    _requirePossession(event);
    _checkLiveAction(event);
    if (event.teamId != _state.offenseTeamId) {
      _fail(
        GameValidationCode.wrongTeam,
        'event ${event.sequence}.teamId',
        'field goal must belong to the offense',
      );
    }
    _requireActive(event.teamId, event.shooterId, event.sequence);
    if (event.shotValue != 2 && event.shotValue != 3) {
      _fail(
        GameValidationCode.andOneInvalid,
        'event ${event.sequence}.shotValue',
        'shotValue must be 2 or 3',
      );
    }
    _requireNoPendingOutcome(event);
    if (event.andOne && !event.made) {
      _fail(
        GameValidationCode.andOneInvalid,
        'event ${event.sequence}.andOne',
        'and-one requires a made field goal',
      );
    }
    if (event.made) {
      if (event.blockedById != null) {
        _fail(
          GameValidationCode.blockInvalid,
          'event ${event.sequence}.blockedById',
          'a made shot cannot be blocked',
        );
      }
      if (event.assistedById != null) {
        if (event.assistedById == event.shooterId) {
          _fail(
            GameValidationCode.assistInvalid,
            'event ${event.sequence}.assistedById',
            'shooter cannot assist their own shot',
          );
        }
        _requireActive(event.teamId, event.assistedById!, event.sequence);
      }
      if (event.andOne) {
        _pendingAndOne = true;
        _andOneShooterId = event.shooterId;
      } else {
        _pendingMadeFg = true;
      }
    } else {
      if (event.assistedById != null) {
        _fail(
          GameValidationCode.assistInvalid,
          'event ${event.sequence}.assistedById',
          'assist requires a made field goal',
        );
      }
      if (event.blockedById != null) {
        final opponent = input.opponentOf(_teamId(event.teamId)!);
        _requireActive(opponent.value, event.blockedById!, event.sequence);
      }
      _pendingMiss = _Miss(
        sequence: event.sequence,
        teamId: event.teamId,
        isFreeThrow: false,
      );
    }
    _noShotClockIncrease(event);
  }

  void _personalFoul(PersonalFoul event) {
    _checkLiveAction(event);
    if (event.freeThrowsAwarded < 0 || event.freeThrowsAwarded > 3) {
      _fail(
        GameValidationCode.freeThrowsInvalid,
        'event ${event.sequence}',
        'freeThrowsAwarded must be 0..3',
      );
    }
    final committingTeam = _teamId(event.committingTeamId);
    if (committingTeam == null) {
      _fail(
        GameValidationCode.wrongTeam,
        'event ${event.sequence}.committingTeamId',
        'unknown committing team',
      );
    }
    _requireActive(
      event.committingTeamId,
      event.committingPlayerId,
      event.sequence,
    );

    if (_pendingAndOne) {
      if (event.kind != FoulKind.shooting ||
          event.committingTeamId !=
              input.opponentOf(_teamId(_state.offenseTeamId!)!).value ||
          event.drawnByPlayerId != _andOneShooterId ||
          event.freeThrowsAwarded != 1 ||
          event.bonus) {
        _fail(
          GameValidationCode.andOneInvalid,
          'event ${event.sequence}',
          'and-one requires a defensive shooting foul worth one FT',
        );
      }
      _requireSameTimestamp(event, GameValidationCode.andOneInvalid);
      _requireSameShotClock(event);
      _incrementTeamFoul(event.committingTeamId);
      _pendingAndOne = false;
      _startFreeThrows(
        teamId: _state.offenseTeamId!,
        shooterId: _andOneShooterId!,
        total: 1,
        event: event,
      );
      return;
    }

    _requirePossession(event);
    if (_pendingMadeFg ||
        _pendingMiss != null ||
        _pendingDefensiveRebound ||
        _pendingTurnover ||
        _pendingMadeFinalFt ||
        _pendingDeadBall ||
        _pendingOffensiveFoul ||
        _freeThrows != null) {
      _fail(
        GameValidationCode.possessionAlreadyOpen,
        'event ${event.sequence}',
        'foul cannot follow an unresolved outcome',
      );
    }
    if (event.committingTeamId == _state.offenseTeamId) {
      if (event.kind != FoulKind.offensive ||
          event.freeThrowsAwarded != 0 ||
          event.bonus ||
          event.drawnByPlayerId != null) {
        _fail(
          GameValidationCode.foulKindInvalid,
          'event ${event.sequence}',
          'team foul must be a normal offensive foul worth no FTs',
        );
      }
      _pendingOffensiveFoul = true;
      _offensiveFoulPlayerId = event.committingPlayerId;
      return;
    }

    if (event.committingTeamId !=
        input.opponentOf(_teamId(_state.offenseTeamId!)!).value) {
      _fail(
        GameValidationCode.wrongTeam,
        'event ${event.sequence}.committingTeamId',
        'defensive foul must be committed by the opponent',
      );
    }
    final drawnBy = event.drawnByPlayerId;
    if (drawnBy == null) {
      _fail(
        GameValidationCode.freeThrowsInvalid,
        'event ${event.sequence}',
        'defensive foul requires a drawn-by player',
      );
    }
    _requireActive(_state.offenseTeamId!, drawnBy, event.sequence);
    _incrementTeamFoul(event.committingTeamId);
    if (event.kind == FoulKind.shooting) {
      if (event.freeThrowsAwarded != 2 && event.freeThrowsAwarded != 3) {
        _fail(
          GameValidationCode.freeThrowsInvalid,
          'event ${event.sequence}',
          'shooting foul awards 2 or 3 FTs',
        );
      }
      if (event.bonus) {
        _fail(
          GameValidationCode.freeThrowsInvalid,
          'event ${event.sequence}.bonus',
          'shooting fouls are not bonus awards',
        );
      }
      _startFreeThrows(
        teamId: _state.offenseTeamId!,
        shooterId: drawnBy,
        total: event.freeThrowsAwarded,
        event: event,
      );
    } else if (event.kind == FoulKind.nonShooting) {
      final threshold = input.rules.bonusThreshold(_state.period);
      final bonus = _teamFouls[event.committingTeamId]! >= threshold;
      if (event.bonus != bonus ||
          (bonus
              ? event.freeThrowsAwarded != 2
              : event.freeThrowsAwarded != 0)) {
        _fail(
          GameValidationCode.freeThrowsInvalid,
          'event ${event.sequence}',
          'non-shooting foul bonus/FTs do not match the team-foul count',
        );
      }
      if (bonus) {
        _startFreeThrows(
          teamId: _state.offenseTeamId!,
          shooterId: drawnBy,
          total: 2,
          event: event,
        );
      } else {
        _pendingShotClockCeiling = _resetCeiling(event.shotClock);
        _state = _state.copyWith(shotClock: _pendingShotClockCeiling);
      }
    } else {
      _fail(
        GameValidationCode.foulKindInvalid,
        'event ${event.sequence}',
        'offensive foul must be committed by the offense',
      );
    }
    _noShotClockIncrease(event);
  }

  void _freeThrow(FreeThrowAttempt event) {
    final group = _freeThrows;
    if (group == null) {
      _fail(
        GameValidationCode.freeThrowSequenceInvalid,
        'event ${event.sequence}',
        'free throw without an awarded sequence',
      );
    }
    if (event.groupId.trim().isEmpty) {
      _fail(
        GameValidationCode.freeThrowSequenceInvalid,
        'event ${event.sequence}.groupId',
        'free-throw groupId must be non-empty',
      );
    }
    if (group.groupId == null) {
      group.groupId = event.groupId;
    } else if (group.groupId != event.groupId) {
      _fail(
        GameValidationCode.freeThrowSequenceInvalid,
        'event ${event.sequence}.groupId',
        'free-throw groupId changed within the awarded group',
      );
    }
    if (event.teamId != group.teamId ||
        event.shooterId != group.shooterId ||
        event.attemptsInGroup != group.total ||
        event.attemptIndex != _nextFreeThrowIndex()) {
      _fail(
        GameValidationCode.freeThrowSequenceInvalid,
        'event ${event.sequence}',
        'free throw does not match the open group',
      );
    }
    if (event.gameClock != group.gameClock ||
        event.shotClock != group.shotClock) {
      _fail(
        GameValidationCode.freeThrowSequenceInvalid,
        'event ${event.sequence}',
        'free throws must not advance the clock',
      );
    }
    if (event.lastOfGroup != (event.attemptIndex == group.total)) {
      _fail(
        GameValidationCode.freeThrowSequenceInvalid,
        'event ${event.sequence}.lastOfGroup',
        'lastOfGroup does not match the group size',
      );
    }
    if (event.attemptIndex == group.total) {
      _freeThrows = null;
      if (event.made) {
        _pendingMadeFinalFt = true;
      } else {
        _pendingMiss = _Miss(
          sequence: event.sequence,
          teamId: event.teamId,
          isFreeThrow: true,
        );
      }
    } else {
      _freeThrowIndex = event.attemptIndex + 1;
    }
    _noShotClockIncrease(event);
  }

  int _freeThrowIndex = 1;

  int _nextFreeThrowIndex() => _freeThrowIndex;

  void _startFreeThrows({
    required String teamId,
    required String shooterId,
    required int total,
    required PersonalFoul event,
  }) {
    if (total == 0) {
      _fail(
        GameValidationCode.freeThrowsInvalid,
        'event ${event.sequence}',
        'free throw group must not be empty',
      );
    }
    _freeThrows = _FreeThrowGroup(
      teamId: teamId,
      shooterId: shooterId,
      total: total,
      gameClock: event.gameClock,
      shotClock: event.shotClock,
    );
    _freeThrowIndex = 1;
  }

  void _rebound(Rebound event) {
    if (_resolvedMisses.contains(event.missedEventSequence)) {
      _fail(
        GameValidationCode.reboundDuplicate,
        'event ${event.sequence}',
        'miss already resolved',
      );
    }
    final miss = _pendingMiss;
    if (miss == null || miss.sequence != event.missedEventSequence) {
      _fail(
        GameValidationCode.reboundInvalid,
        'event ${event.sequence}',
        'rebound must link to the pending miss',
      );
    }
    if (event.gameClock == 0) {
      _fail(
        GameValidationCode.reboundInvalid,
        'event ${event.sequence}',
        'zero-clock misses are DeadBallMiss, not rebounds',
      );
    }
    _requireSameTimestamp(event, GameValidationCode.deadBallClockAdvanced);
    _requireActive(event.teamId, event.playerId, event.sequence);
    if (event.offensive) {
      if (event.teamId != miss.teamId) {
        _fail(
          GameValidationCode.reboundWrongTeam,
          'event ${event.sequence}',
          'offensive rebound must be by the shooting team',
        );
      }
      if (event.shotClock != input.rules.offensiveReboundResetSeconds) {
        _fail(
          GameValidationCode.illegalShotClockIncrease,
          'event ${event.sequence}.shotClock',
          'offensive rebound resets to ${input.rules.offensiveReboundResetSeconds}',
        );
      }
      _pendingMiss = null;
      _resolvedMisses.add(event.missedEventSequence);
      _state = _state.copyWith(shotClock: event.shotClock);
    } else {
      if (event.teamId == miss.teamId) {
        _fail(
          GameValidationCode.reboundWrongTeam,
          'event ${event.sequence}',
          'defensive rebound must be by the opponent',
        );
      }
      if (event.shotClock != input.rules.shotClockSeconds) {
        _fail(
          GameValidationCode.illegalShotClockIncrease,
          'event ${event.sequence}.shotClock',
          'defensive rebound resets to ${input.rules.shotClockSeconds}',
        );
      }
      _pendingMiss = null;
      _resolvedMisses.add(event.missedEventSequence);
      _pendingDefensiveRebound = true;
      _state = _state.copyWith(shotClock: event.shotClock);
    }
    _noShotClockIncrease(event, allowReset: true);
  }

  void _deadBall(DeadBallMiss event) {
    _requireSameTimestamp(event, GameValidationCode.deadBallClockAdvanced);
    _requireSameShotClock(event);
    if (_resolvedMisses.contains(event.missedEventSequence)) {
      _fail(
        GameValidationCode.reboundDuplicate,
        'event ${event.sequence}',
        'miss already resolved',
      );
    }
    final miss = _pendingMiss;
    if (miss == null ||
        miss.sequence != event.missedEventSequence ||
        event.gameClock != 0 ||
        event.teamId != miss.teamId) {
      _fail(
        GameValidationCode.deadBallInvalid,
        'event ${event.sequence}',
        'DeadBallMiss must close a zero-clock miss by the shooting team',
      );
    }
    _resolvedMisses.add(event.missedEventSequence);
    _pendingMiss = null;
    _pendingDeadBall = true;
    _noShotClockIncrease(event);
  }

  void _turnoverEvent(Turnover event) {
    _requirePossession(event);
    _checkLiveAction(event);
    if (_pendingMadeFg ||
        _pendingAndOne ||
        _pendingMiss != null ||
        _pendingDefensiveRebound ||
        _pendingTurnover ||
        _pendingMadeFinalFt ||
        _pendingDeadBall ||
        _freeThrows != null) {
      _fail(
        GameValidationCode.possessionAlreadyOpen,
        'event ${event.sequence}',
        'turnover cannot follow an unresolved outcome',
      );
    }
    if (event.teamId != _state.offenseTeamId) {
      _fail(
        GameValidationCode.wrongTeam,
        'event ${event.sequence}.teamId',
        'turnover must belong to the offense',
      );
    }
    _requireActive(event.teamId, event.playerId, event.sequence);
    switch (event.reason) {
      case TurnoverReason.steal:
        if (_pendingOffensiveFoul) {
          _fail(
            GameValidationCode.turnoverInvalid,
            'event ${event.sequence}',
            'steal cannot follow an offensive foul',
          );
        }
        final stolenBy = event.stolenById;
        if (stolenBy == null) {
          _fail(
            GameValidationCode.stealInvalid,
            'event ${event.sequence}.stolenById',
            'steal requires an opponent',
          );
        }
        _requireActive(
          input.opponentOf(_teamId(event.teamId)!).value,
          stolenBy,
          event.sequence,
        );
      case TurnoverReason.shotClock:
        if (event.gameClock == 0) {
          _fail(
            GameValidationCode.periodHornPrecedence,
            'event ${event.sequence}.gameClock',
            'period horn takes precedence over a simultaneous shot-clock expiry',
          );
        }
        if (_pendingOffensiveFoul ||
            event.stolenById != null ||
            event.shotClock != 0) {
          _fail(
            GameValidationCode.turnoverInvalid,
            'event ${event.sequence}',
            'shot-clock violation requires no steal and shot clock 0',
          );
        }
      case TurnoverReason.offensiveFoul:
        _requireSameTimestamp(event, GameValidationCode.turnoverInvalid);
        _requireSameShotClock(event);
        if (!_pendingOffensiveFoul ||
            event.playerId != _offensiveFoulPlayerId ||
            event.stolenById != null) {
          _fail(
            GameValidationCode.turnoverInvalid,
            'event ${event.sequence}',
            'offensive-foul turnover must follow that offensive foul',
          );
        }
        _pendingOffensiveFoul = false;
        _offensiveFoulPlayerId = null;
      case TurnoverReason.nonSteal:
        if (event.gameClock == 0) {
          _fail(
            GameValidationCode.periodHornPrecedence,
            'event ${event.sequence}.gameClock',
            'period horn takes precedence over a non-steal turnover',
          );
        }
        if (event.shotClock == 0) {
          _fail(
            GameValidationCode.turnoverInvalid,
            'event ${event.sequence}.shotClock',
            'zero shot clock must use the shotClock reason',
          );
        }
        if (event.stolenById != null || _pendingOffensiveFoul) {
          _fail(
            GameValidationCode.turnoverInvalid,
            'event ${event.sequence}',
            'non-steal turnover requires no steal and no pending offensive foul',
          );
        }
    }
    _pendingTurnover = true;
    _noShotClockIncrease(event);
  }

  void _requirePossession(GameEvent event) {
    if (!_state.hasOpenPossession) {
      _fail(
        GameValidationCode.noOpenPossession,
        'event ${event.sequence}',
        'event requires a live possession',
      );
    }
    if (event.shotClock == null) {
      _fail(
        GameValidationCode.invalidShotClock,
        'event ${event.sequence}.shotClock',
        'live events require a shot clock',
      );
    }
  }

  void _requireNoPendingOutcome(FieldGoalAttempt event) {
    if (_pendingMadeFg ||
        _pendingAndOne ||
        _pendingMiss != null ||
        _pendingDefensiveRebound ||
        _pendingTurnover ||
        _pendingMadeFinalFt ||
        _pendingDeadBall ||
        _pendingOffensiveFoul ||
        _freeThrows != null) {
      _fail(
        GameValidationCode.possessionAlreadyOpen,
        'event ${event.sequence}',
        'previous outcome is unresolved',
      );
    }
  }

  void _requireActive(String teamId, String playerId, int sequence) {
    final team = _teamId(teamId);
    if (team == null) {
      _fail(
        GameValidationCode.wrongTeam,
        'event $sequence.teamId',
        'unknown team $teamId',
      );
    }
    if (!input.isActive(team!, _playerId(playerId))) {
      _fail(
        GameValidationCode.playerNotActive,
        'event $sequence.playerId',
        'player $playerId is not active for $teamId',
      );
    }
  }

  TeamId? _teamId(String value) {
    if (value == input.homeTeamId.value) return input.homeTeamId;
    if (value == input.awayTeamId.value) return input.awayTeamId;
    return null;
  }

  PlayerId _playerId(String value) => PlayerId(value);

  TeamId _starterFor(int period) {
    final first = input.startingTeamId;
    return period.isOdd ? first : input.opponentOf(first);
  }

  int _resetCeiling(int? current) {
    final value = current ?? 0;
    final floor = value > input.rules.nonBonusFoulResetFloorSeconds
        ? value
        : input.rules.nonBonusFoulResetFloorSeconds;
    return floor > input.rules.shotClockSeconds
        ? input.rules.shotClockSeconds
        : floor;
  }

  void _incrementTeamFoul(String teamId) {
    _teamFouls[teamId] = (_teamFouls[teamId] ?? 0) + 1;
  }

  void _noShotClockIncrease(GameEvent event, {bool allowReset = false}) {
    // Reset increases are validated explicitly by the event handlers.
    if (!allowReset) {
      final previous = _state.shotClock;
      if (previous != null &&
          event.shotClock != null &&
          event.shotClock! > previous) {
        _fail(
          GameValidationCode.illegalShotClockIncrease,
          'event ${event.sequence}.shotClock',
          'shot clock may only increase through a legal reset',
        );
      }
    }
  }

  /// A live offensive action must consume game time and shot clock together.
  void _checkLiveAction(GameEvent event) {
    final previousClock = _state.gameClock;
    final previousShotClock = _state.shotClock;
    final shotClock = event.shotClock;
    if (previousShotClock == null || shotClock == null) {
      _fail(
        GameValidationCode.invalidShotClock,
        'event ${event.sequence}.shotClock',
        'live actions require a shot clock',
      );
    }
    final elapsed = previousClock - event.gameClock;
    if (elapsed < 0) {
      _fail(
        GameValidationCode.gameClockIncreased,
        'event ${event.sequence}.gameClock',
        'game clock cannot increase within a period',
      );
    }
    if (elapsed > previousShotClock) {
      _fail(
        GameValidationCode.shotClockElapsedMismatch,
        'event ${event.sequence}.gameClock',
        'live action consumed $elapsed s with only $previousShotClock s on the shot clock',
      );
    }
    final expected = previousShotClock - elapsed;
    if (shotClock != expected) {
      _fail(
        GameValidationCode.shotClockElapsedMismatch,
        'event ${event.sequence}.shotClock',
        'expected shot clock $expected after $elapsed s, got $shotClock',
      );
    }
  }

  void _requireSameTimestamp(GameEvent event, GameValidationCode code) {
    if (event.gameClock != _state.gameClock) {
      _fail(
        code,
        'event ${event.sequence}.gameClock',
        'resolution must occur at the miss/timestamp clock',
      );
    }
  }

  void _requireSameShotClock(GameEvent event) {
    if (event.shotClock != _state.shotClock) {
      _fail(
        GameValidationCode.illegalShotClockIncrease,
        'event ${event.sequence}.shotClock',
        'zero-time resolution must not change the shot clock',
      );
    }
  }

  GameBoxScore _boxScore() => EventAccounting.aggregate(
    ValidatedGameLedger._(input, _processed, _state),
  );

  void _clearPending() {
    _pendingMadeFg = false;
    _pendingAndOne = false;
    _andOneShooterId = null;
    _pendingMiss = null;
    _pendingDefensiveRebound = false;
    _pendingTurnover = false;
    _pendingMadeFinalFt = false;
    _pendingDeadBall = false;
    _pendingOffensiveFoul = false;
    _offensiveFoulPlayerId = null;
    _freeThrows = null;
    _freeThrowIndex = 1;
    _pendingShotClockCeiling = null;
  }
}
