import '../generation/deterministic_random.dart';
import '../models/ids.dart';
import '../models/player.dart';
import 'action_intent.dart';
import 'event_accounting.dart';
import 'game_event.dart';
import 'game_fingerprint.dart';
import 'game_input.dart';
import 'game_reducer.dart';
import 'game_result.dart';
import 'game_rules.dart';
import 'game_validation.dart';
import 'phase_trace.dart';
import 'game_versions.dart';
import 'probability_model.dart';

/// Deterministic headless M002 game orchestrator (T009).
///
/// Produces a complete regulation/overtime ledger from the T008 probability
/// model, then validates it with `GameEventReducer` and derives every official
/// statistic with `EventAccounting`. The returned [GameResult] contains no
/// independent scoreboard: scores are read from the validated box score.
///
/// ## Determinism
///
/// One game-local `DeterministicRandom` is seeded from
/// `GameInput.normalizedSeed`. The opening possession consumes no draw. Draw
/// order follows the T008 contract:
///
/// - normal live phase: A1 type, A1 duration, then the action draws;
/// - final tick (`gameClock == 1`): no A1 or category draws, action draws only;
/// - shot-clock expiry or period expiry before the planned action: the action
///   is never selected, so no outcome draws are consumed;
/// - a phase that reaches the horn exactly (`D == gameClock`) selects its
///   action: a shot resolves, a qualifying shooting or bonus-awarding foul
///   resolves with its free throws, a non-bonus non-shooting foul is recorded
///   and the period ends, while a live turnover or offensive foul is discarded
///   because the event contract forbids live turnovers at the horn;
/// - rebound and free-throw draws follow their own public entry points.
///
/// ## Clock precedence (A1, OD-02)
///
/// Let `Rg` be the remaining game clock and `Rs` the shot clock at phase start,
/// `D` the planned duration:
///
/// - `Rg == 1`: deliberate final-tick attempt; consumes one second and releases
///   at game clock 0.
/// - `D <= Rg && D <= Rs`: the phase completes at `Rg - D`; a release at
///   `Rg - D == 0` or `Rs - D == 0` is legal.
/// - `D > Rs && Rs < Rg`: shot-clock violation at `Rg - Rs`; the planned action
///   is never selected.
/// - `D > Rg` with `Rg <= Rs`: the period expires at 0 without a terminal
///   action, turnover or rebound.
///
/// Planned durations are never clamped to the clock.
///
/// ## A1 configuration ownership
///
/// `GameInput.rules` is authoritative for A1 sampling. Without an injected
/// model, each [simulate] call creates a `BasketballProbabilityModel` from
/// `input.rules`, so one simulator can run sequential games with different
/// valid rule configurations. An injected model is never replaced or mutated;
/// its A1 configuration must agree with `input.rules` or the simulation is
/// rejected before any PRNG draw with
/// `GameValidationCode.invalidRules`.
final class GameSimulator {
  GameSimulator({
    BasketballProbabilityModel? probabilityModel,
    this.onPhaseTrace,
  }) : _injectedModel = probabilityModel;

  final BasketballProbabilityModel? _injectedModel;

  /// Optional passive A1 phase observer (default disabled). It cannot draw
  /// randomness, mutate state or change the ledger.
  final void Function(PhaseTraceRecord record)? onPhaseTrace;

  /// Simulates and validates one game. Throws [GameValidationException] on any
  /// illegal state, incompatible injected model or bound; never returns a
  /// partial result.
  GameResult simulate(GameInput input) {
    final injected = _injectedModel;
    if (injected == null) {
      return _GameRun(
        input,
        BasketballProbabilityModel(rules: input.rules),
        onPhaseTrace,
      ).run();
    }
    _requireCompatibleA1(injected.rules, input.rules);
    return _GameRun(input, injected, onPhaseTrace).run();
  }

  /// Rejects an injected model whose A1 configuration differs from the input.
  ///
  /// Only rules fields actually consumed by the probability model, or tied to
  /// its sampling contract, are compared; unrelated rules such as period length
  /// may differ.
  static void _requireCompatibleA1(GameRules modelRules, GameRules inputRules) {
    final issues = <GameValidationIssue>[];
    if (modelRules.actionDurationModelVersion !=
        inputRules.actionDurationModelVersion) {
      issues.add(
        GameValidationIssue(
          code: GameValidationCode.invalidRules,
          path: 'rules.actionDurationModelVersion',
          message:
              'injected model uses duration model version '
              '${modelRules.actionDurationModelVersion}, input uses '
              '${inputRules.actionDurationModelVersion}',
        ),
      );
    }
    if (!_sameInts(modelRules.phaseWeights, inputRules.phaseWeights)) {
      issues.add(
        GameValidationIssue(
          code: GameValidationCode.invalidRules,
          path: 'rules.phaseWeights',
          message:
              'injected model phase weights '
              '${modelRules.phaseWeights.join(',')} do not match input '
              '${inputRules.phaseWeights.join(',')}',
        ),
      );
    }
    if (!_sameBrackets(modelRules.phaseDurations, inputRules.phaseDurations)) {
      issues.add(
        GameValidationIssue(
          code: GameValidationCode.invalidRules,
          path: 'rules.phaseDurations',
          message:
              'injected model phase durations '
              '${_formatBrackets(modelRules.phaseDurations)} do not match '
              'input ${_formatBrackets(inputRules.phaseDurations)}',
        ),
      );
    }
    if (issues.isNotEmpty) throw GameValidationException(issues);
  }

  static bool _sameInts(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  static bool _sameBrackets(List<List<int>> left, List<List<int>> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (!_sameInts(left[i], right[i])) return false;
    }
    return true;
  }

  static String _formatBrackets(List<List<int>> brackets) =>
      brackets.map((bracket) => '[${bracket.join(',')}]').join(',');
}

final class _GameRun {
  _GameRun(this.input, this._model, [this._trace])
    : rules = input.rules,
      rng = DeterministicRandom(input.normalizedSeed),
      fingerprint = GameFingerprint.of(input) {
    _teamFouls[input.homeTeamId.value] = 0;
    _teamFouls[input.awayTeamId.value] = 0;
  }

  final GameInput input;
  final BasketballProbabilityModel _model;
  final void Function(PhaseTraceRecord record)? _trace;
  final GameRules rules;

  int _traceSequence = 0;

  void _tracePhase(
    PhaseKind kind,
    int plannedSeconds,
    int gameClockBefore,
    int shotClockBefore,
    PhaseResolution resolution,
  ) {
    final observer = _trace;
    if (observer == null) return;
    observer(
      PhaseTraceRecord(
        sequence: ++_traceSequence,
        period: _period,
        kind: kind.name,
        plannedSeconds: plannedSeconds,
        gameClockBefore: gameClockBefore,
        shotClockBefore: shotClockBefore,
        resolution: resolution,
      ),
    );
  }

  final DeterministicRandom rng;
  final String fingerprint;

  final List<GameEvent> events = <GameEvent>[];
  final Map<String, int> _teamFouls = <String, int>{};

  late final TeamOnCourt _homeOnCourt = TeamOnCourt(
    teamId: input.homeTeamId,
    lineup: input.homeLineup,
  );
  late final TeamOnCourt _awayOnCourt = TeamOnCourt(
    teamId: input.awayTeamId,
    lineup: input.awayLineup,
  );

  int _sequence = 0;
  int _period = 1;
  int _clock = 0;
  int? _shotClock;
  String? _possessionId;
  bool _possessionOpen = false;
  late TeamId _offense = input.startingTeamId;
  int _possessionCounter = 0;
  int _freeThrowGroupCounter = 0;
  int _lastClock = 0;
  int _zeroTimeEvents = 0;

  GameResult run() {
    _emit(
      GameStarted(
        sequence: _nextSequence(),
        period: 1,
        gameClock: rules.periodSeconds,
        shotClock: null,
        homeTeamId: input.homeTeamId.value,
        awayTeamId: input.awayTeamId.value,
        startingTeamId: input.startingTeamId.value,
      ),
    );

    _period = 1;
    while (true) {
      _startPeriod();
      _playPeriod();
      _emit(
        PeriodEnded(
          sequence: _nextSequence(),
          period: _period,
          gameClock: 0,
          shotClock: null,
        ),
      );

      final homePoints = _pointsFor(input.homeTeamId);
      final awayPoints = _pointsFor(input.awayTeamId);
      final tied = homePoints == awayPoints;
      if (!tied && _period >= rules.periods) {
        _emit(
          GameEnded(
            sequence: _nextSequence(),
            period: _period,
            gameClock: 0,
            shotClock: null,
            finalPeriod: _period,
          ),
        );
        break;
      }
      if (tied && _period >= rules.periods + rules.maxOvertimes) {
        _fail(
          GameValidationCode.overtimeLimitExceeded,
          'period',
          'tied after $_period periods exceeds maxOvertimes '
              '${rules.maxOvertimes}',
        );
      }
      _period++;
    }

    final ledger = GameEventLedger(
      gameId: input.gameId,
      inputFingerprint: fingerprint,
      events: events,
    );
    final validated = GameEventReducer.validate(input, ledger);
    final box = EventAccounting.aggregate(validated);
    final homeScore = box.teams[input.homeTeamId.value]!.points;
    final awayScore = box.teams[input.awayTeamId.value]!.points;
    return GameResult(
      input: input,
      inputFingerprint: fingerprint,
      ledger: ledger,
      state: validated.state,
      boxScore: box,
      homeScore: homeScore,
      awayScore: awayScore,
      periodsPlayed: _period,
      possessions: events.whereType<PossessionStarted>().length,
      simulationVersion: gameSimulationVersion,
      rulesVersion: gameRulesVersion,
      eventSchemaVersion: gameEventSchemaVersion,
      prngImplementationId: 'xorshift32-v1',
    );
  }

  // --- Period and possession skeleton -------------------------------------

  void _startPeriod() {
    _clock = rules.periodLength(_period);
    _shotClock = null;
    _possessionOpen = false;
    _possessionId = null;
    _offense = _starterFor(_period);
    _teamFouls[input.homeTeamId.value] = 0;
    _teamFouls[input.awayTeamId.value] = 0;
    _emit(
      PeriodStarted(
        sequence: _nextSequence(),
        period: _period,
        gameClock: _clock,
        shotClock: null,
        startingTeamId: _offense.value,
      ),
    );
  }

  void _playPeriod() {
    while (_clock > 0) {
      _startPossession();
      final expired = _playPossession();
      if (expired) {
        _endPossession(PossessionEndReason.periodEnd);
        break;
      }
      if (_clock > 0) {
        _offense = _opponentOf(_offense);
      }
    }
  }

  void _startPossession() {
    _possessionCounter++;
    _possessionId = 'p$_possessionCounter';
    _possessionOpen = true;
    _shotClock = rules.shotClockSeconds;
    _emit(
      PossessionStarted(
        sequence: _nextSequence(),
        period: _period,
        gameClock: _clock,
        shotClock: _shotClock,
        possessionId: _possessionId!,
        offenseTeamId: _offense.value,
      ),
    );
  }

  void _endPossession(PossessionEndReason reason) {
    _emit(
      PossessionEnded(
        sequence: _nextSequence(),
        period: _period,
        gameClock: _clock,
        shotClock: _shotClock,
        possessionId: _possessionId!,
        offenseTeamId: _offense.value,
        reason: reason,
      ),
    );
    _possessionOpen = false;
    _possessionId = null;
    _shotClock = null;
  }

  /// Runs phases until the possession ends. Returns true when the period
  /// expired while the possession was still open.
  bool _playPossession() {
    while (true) {
      if (_clock == 0) return false;
      final shotClock = _shotClock!;

      if (_clock == 1) {
        if (shotClock == 0) {
          _clock = 0;
          return true;
        }
        final action = _model.selectFinalTickAction(
          offense: _onCourt(_offense),
          defense: _onCourt(_opponentOf(_offense)),
          rng: rng,
        );
        _clock = 0;
        _shotClock = shotClock - 1;
        _applyAction(action);
        return _possessionOpen;
      }

      final clockBefore = _clock;
      final shotClockBefore = shotClock;
      final phase = _model.drawPhaseDuration(rng);
      final duration = phase.seconds;

      if (duration <= _clock && duration <= shotClock) {
        final action = _model.selectAction(
          offense: _onCourt(_offense),
          defense: _onCourt(_opponentOf(_offense)),
          phase: phase.kind,
          rng: rng,
        );
        _clock -= duration;
        _shotClock = shotClock - duration;

        if (action is ShotAttemptAction) {
          _tracePhase(
            phase.kind,
            duration,
            clockBefore,
            shotClockBefore,
            PhaseResolution.legalShot,
          );
          _applyAction(action);
          if (!_possessionOpen) return false;
          if (_clock == 0) return true;
          continue;
        }

        if (action is NonShootingFoulAction) {
          if (_clock == 0) {
            // A1: a qualifying foul that is the terminal action of a phase
            // initiated before expiry resolves at zero; bonus free throws
            // complete before PeriodEnded. A non-bonus foul keeps the
            // possession open only until the caller ends the period.
            _tracePhase(
              phase.kind,
              duration,
              clockBefore,
              shotClockBefore,
              PhaseResolution.legalFoul,
            );
            _applyAction(action);
            return _possessionOpen;
          }
          if (_shotClock == 0 && !_wouldBeBonusFoul()) {
            // No released attempt and no qualifying award: fall through to
            // the shot-clock violation.
          } else {
            _tracePhase(
              phase.kind,
              duration,
              clockBefore,
              shotClockBefore,
              PhaseResolution.legalFoul,
            );
            _applyAction(action);
            if (!_possessionOpen) return false;
            if (_clock == 0) return true;
            continue;
          }
        } else if (_clock == 0) {
          // A live turnover or offensive foul at the horn has no legal event;
          // the action is discarded and the period expires.
          _tracePhase(
            phase.kind,
            duration,
            clockBefore,
            shotClockBefore,
            PhaseResolution.actionDiscardedAtHorn,
          );
          return true;
        } else if (_shotClock! > 0) {
          // Live turnover or offensive foul with time remaining.
          _tracePhase(
            phase.kind,
            duration,
            clockBefore,
            shotClockBefore,
            PhaseResolution.legalTurnover,
          );
          _applyAction(action);
          return false;
        }

        // Shot-clock expiry with no released attempt or qualifying award.
        _tracePhase(
          phase.kind,
          duration,
          clockBefore,
          shotClockBefore,
          PhaseResolution.shotClockExpiryNoAttempt,
        );
        final handler = _onCourt(_offense).lineup.players.first;
        _emit(
          Turnover(
            sequence: _nextSequence(),
            period: _period,
            gameClock: _clock,
            shotClock: 0,
            teamId: _offense.value,
            playerId: handler.id.value,
            reason: TurnoverReason.shotClock,
          ),
        );
        _endPossession(PossessionEndReason.turnover);
        return false;
      }

      if (duration > shotClock && shotClock < _clock) {
        _tracePhase(
          phase.kind,
          duration,
          clockBefore,
          shotClockBefore,
          PhaseResolution.shotClockOvershoot,
        );
        _clock -= shotClock;
        _shotClock = 0;
        final handler = _onCourt(_offense).lineup.players.first;
        _emit(
          Turnover(
            sequence: _nextSequence(),
            period: _period,
            gameClock: _clock,
            shotClock: 0,
            teamId: _offense.value,
            playerId: handler.id.value,
            reason: TurnoverReason.shotClock,
          ),
        );
        _endPossession(PossessionEndReason.turnover);
        return false;
      }

      // Game clock expires first (D > Rg, Rg <= Rs): no terminal action.
      _tracePhase(
        phase.kind,
        duration,
        clockBefore,
        shotClockBefore,
        clockBefore == shotClockBefore
            ? PhaseResolution.simultaneousExpiry
            : PhaseResolution.gameClockFirst,
      );
      _clock = 0;
      return true;
    }
  }

  // --- Action translation -------------------------------------------------

  void _applyAction(OffensiveAction action) {
    switch (action) {
      case ShotAttemptAction shot:
        _resolveShot(shot);
      case TurnoverAction turnover:
        _resolveTurnover(turnover);
      case OffensiveFoulAction foul:
        _resolveOffensiveFoul(foul);
      case NonShootingFoulAction foul:
        _resolveNonShootingFoul(foul);
    }
  }

  void _resolveShot(ShotAttemptAction action) {
    final offense = _offense;
    final defense = _opponentOf(offense);
    final clock = _clock;
    final shotClock = _shotClock!;

    // Missed shooting foul: no counted field-goal attempt.
    if (!action.made && action.freeThrowsAwarded > 0) {
      _countTeamFoul(defense);
      _emit(
        PersonalFoul(
          sequence: _nextSequence(),
          period: _period,
          gameClock: clock,
          shotClock: shotClock,
          committingTeamId: defense.value,
          committingPlayerId: action.foulingDefenderId!.value,
          drawnByPlayerId: action.shooterId.value,
          kind: FoulKind.shooting,
          freeThrowsAwarded: action.freeThrowsAwarded,
          bonus: false,
        ),
      );
      _resolveFreeThrows(
        shooterId: action.shooterId.value,
        attempts: action.freeThrowsAwarded,
      );
      return;
    }

    final attemptSequence = _nextSequence();
    _emit(
      FieldGoalAttempt(
        sequence: attemptSequence,
        period: _period,
        gameClock: clock,
        shotClock: shotClock,
        teamId: offense.value,
        shooterId: action.shooterId.value,
        shotValue: action.shotValue,
        made: action.made,
        andOne: action.andOne,
        assistedById: action.assistedById?.value,
        blockedById: action.blockedById?.value,
      ),
    );

    if (action.made) {
      if (action.andOne) {
        _countTeamFoul(defense);
        _emit(
          PersonalFoul(
            sequence: _nextSequence(),
            period: _period,
            gameClock: clock,
            shotClock: shotClock,
            committingTeamId: defense.value,
            committingPlayerId: action.foulingDefenderId!.value,
            drawnByPlayerId: action.shooterId.value,
            kind: FoulKind.shooting,
            freeThrowsAwarded: 1,
            bonus: false,
          ),
        );
        _resolveFreeThrows(shooterId: action.shooterId.value, attempts: 1);
      } else {
        _endPossession(PossessionEndReason.madeFieldGoal);
      }
      return;
    }

    if (clock == 0) {
      _emit(
        DeadBallMiss(
          sequence: _nextSequence(),
          period: _period,
          gameClock: 0,
          shotClock: shotClock,
          teamId: offense.value,
          missedEventSequence: attemptSequence,
          reason: DeadBallReason.periodEnd,
        ),
      );
      _endPossession(PossessionEndReason.periodEnd);
      return;
    }

    final rebound = _model.resolveRebound(
      offense: _onCourt(offense),
      defense: _onCourt(defense),
      zone: action.zone,
      rng: rng,
    );
    if (rebound.offensive) {
      _shotClock = rules.offensiveReboundResetSeconds;
      _emit(
        Rebound(
          sequence: _nextSequence(),
          period: _period,
          gameClock: clock,
          shotClock: _shotClock,
          teamId: offense.value,
          playerId: rebound.playerId.value,
          offensive: true,
          missedEventSequence: attemptSequence,
        ),
      );
      return;
    }
    _shotClock = rules.shotClockSeconds;
    _emit(
      Rebound(
        sequence: _nextSequence(),
        period: _period,
        gameClock: clock,
        shotClock: _shotClock,
        teamId: defense.value,
        playerId: rebound.playerId.value,
        offensive: false,
        missedEventSequence: attemptSequence,
      ),
    );
    _endPossession(PossessionEndReason.defensiveRebound);
  }

  void _resolveTurnover(TurnoverAction action) {
    _emit(
      Turnover(
        sequence: _nextSequence(),
        period: _period,
        gameClock: _clock,
        shotClock: _shotClock,
        teamId: _offense.value,
        playerId: action.playerId.value,
        reason: action.kind == TurnoverKind.steal
            ? TurnoverReason.steal
            : TurnoverReason.nonSteal,
        stolenById: action.stolenById?.value,
      ),
    );
    _endPossession(PossessionEndReason.turnover);
  }

  void _resolveOffensiveFoul(OffensiveFoulAction action) {
    _emit(
      PersonalFoul(
        sequence: _nextSequence(),
        period: _period,
        gameClock: _clock,
        shotClock: _shotClock,
        committingTeamId: _offense.value,
        committingPlayerId: action.playerId.value,
        kind: FoulKind.offensive,
        freeThrowsAwarded: 0,
        bonus: false,
      ),
    );
    _emit(
      Turnover(
        sequence: _nextSequence(),
        period: _period,
        gameClock: _clock,
        shotClock: _shotClock,
        teamId: _offense.value,
        playerId: action.playerId.value,
        reason: TurnoverReason.offensiveFoul,
      ),
    );
    _endPossession(PossessionEndReason.turnover);
  }

  void _resolveNonShootingFoul(NonShootingFoulAction action) {
    final defense = _opponentOf(_offense);
    final count = _countTeamFoul(defense);
    final bonus = count >= rules.bonusThreshold(_period);
    _emit(
      PersonalFoul(
        sequence: _nextSequence(),
        period: _period,
        gameClock: _clock,
        shotClock: _shotClock,
        committingTeamId: defense.value,
        committingPlayerId: action.committingPlayerId.value,
        drawnByPlayerId: action.drawnByPlayerId.value,
        kind: FoulKind.nonShooting,
        freeThrowsAwarded: bonus ? 2 : 0,
        bonus: bonus,
      ),
    );
    if (bonus) {
      _resolveFreeThrows(shooterId: action.drawnByPlayerId.value, attempts: 2);
      return;
    }
    final floor = rules.nonBonusFoulResetFloorSeconds;
    final current = _shotClock!;
    _shotClock = current > floor ? current : floor;
    if (_shotClock! > rules.shotClockSeconds) {
      _shotClock = rules.shotClockSeconds;
    }
  }

  void _resolveFreeThrows({required String shooterId, required int attempts}) {
    final offense = _offense;
    final defense = _opponentOf(offense);
    final clock = _clock;
    final shotClock = _shotClock!;
    final group = _model.resolveFreeThrows(
      offense: _onCourt(offense),
      shooter: _player(_onCourt(offense), shooterId),
      attempts: attempts,
      rng: rng,
    );
    final groupId = '${_possessionId!}-ft${++_freeThrowGroupCounter}';
    var lastSequence = 0;
    for (var index = 0; index < attempts; index++) {
      lastSequence = _nextSequence();
      _emit(
        FreeThrowAttempt(
          sequence: lastSequence,
          period: _period,
          gameClock: clock,
          shotClock: shotClock,
          teamId: offense.value,
          shooterId: shooterId,
          groupId: groupId,
          attemptIndex: index + 1,
          attemptsInGroup: attempts,
          made: group.madeByAttempt[index],
          lastOfGroup: index == attempts - 1,
        ),
      );
    }

    if (group.madeByAttempt.last) {
      _endPossession(PossessionEndReason.madeFinalFreeThrow);
      return;
    }
    if (clock == 0) {
      _emit(
        DeadBallMiss(
          sequence: _nextSequence(),
          period: _period,
          gameClock: 0,
          shotClock: shotClock,
          teamId: offense.value,
          missedEventSequence: lastSequence,
          reason: DeadBallReason.periodEnd,
        ),
      );
      _endPossession(PossessionEndReason.periodEnd);
      return;
    }

    final rebound = _model.resolveRebound(
      offense: _onCourt(offense),
      defense: _onCourt(defense),
      rng: rng,
    );
    if (rebound.offensive) {
      _shotClock = rules.offensiveReboundResetSeconds;
      _emit(
        Rebound(
          sequence: _nextSequence(),
          period: _period,
          gameClock: clock,
          shotClock: _shotClock,
          teamId: offense.value,
          playerId: rebound.playerId.value,
          offensive: true,
          missedEventSequence: lastSequence,
        ),
      );
      return;
    }
    _shotClock = rules.shotClockSeconds;
    _emit(
      Rebound(
        sequence: _nextSequence(),
        period: _period,
        gameClock: clock,
        shotClock: _shotClock,
        teamId: defense.value,
        playerId: rebound.playerId.value,
        offensive: false,
        missedEventSequence: lastSequence,
      ),
    );
    _endPossession(PossessionEndReason.defensiveRebound);
  }

  // --- Helpers ------------------------------------------------------------

  TeamOnCourt _onCourt(TeamId team) =>
      team == input.homeTeamId ? _homeOnCourt : _awayOnCourt;

  TeamId _opponentOf(TeamId team) => input.opponentOf(team);

  TeamId _starterFor(int period) => period.isOdd
      ? input.startingTeamId
      : input.opponentOf(input.startingTeamId);

  Player _player(TeamOnCourt side, String playerId) {
    for (final player in side.lineup.players) {
      if (player.id.value == playerId) return player;
    }
    throw StateError('player $playerId is not active for ${side.teamId.value}');
  }

  bool _wouldBeBonusFoul() {
    final defense = _opponentOf(_offense);
    return (_teamFouls[defense.value] ?? 0) + 1 >=
        rules.bonusThreshold(_period);
  }

  int _countTeamFoul(TeamId team) {
    final next = (_teamFouls[team.value] ?? 0) + 1;
    _teamFouls[team.value] = next;
    return next;
  }

  int _pointsFor(TeamId team) {
    var points = 0;
    for (final event in events) {
      if (event is FieldGoalAttempt &&
          event.made &&
          event.teamId == team.value) {
        points += event.shotValue;
      } else if (event is FreeThrowAttempt &&
          event.made &&
          event.teamId == team.value) {
        points += 1;
      }
    }
    return points;
  }

  int _nextSequence() => ++_sequence;

  void _emit(GameEvent event) {
    if (events.length >= rules.maxEvents) {
      _fail(
        GameValidationCode.eventLimitExceeded,
        'events',
        'simulation exceeded ${rules.maxEvents} events',
      );
    }
    if (event.period == _period && event.gameClock == _lastClock) {
      _zeroTimeEvents++;
      if (_zeroTimeEvents > rules.maxZeroTimeEvents) {
        _fail(
          GameValidationCode.zeroTimeEventLimitExceeded,
          'event ${event.sequence}',
          'more than ${rules.maxZeroTimeEvents} events at game clock '
              '${event.gameClock}',
        );
      }
    } else {
      _zeroTimeEvents = 1;
      _lastClock = event.gameClock;
    }
    events.add(event);
  }

  Never _fail(GameValidationCode code, String path, String message) =>
      throw GameValidationException([
        GameValidationIssue(code: code, path: path, message: message),
      ]);
}
