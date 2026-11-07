import '../generation/deterministic_random.dart';
import '../models/ids.dart';
import '../models/player.dart';
import '../models/team.dart';
import 'action_intent.dart';
import 'event_accounting.dart';
import 'game_event.dart';
import 'game_fingerprint.dart';
import 'game_input.dart';
import 'game_reducer.dart';
import 'game_result.dart';
import 'court_lineup.dart';
import 'game_rules.dart';
import 'game_validation.dart';
import 'phase_trace.dart';
import 'game_versions.dart';
import 'probability_model.dart';
import 'rotation_plan.dart';
import 'rotation_policy.dart';
import 'rotation_window_history.dart';

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
/// Passive observation of one foul-out replacement selection.
///
/// [draws] is the number of underlying PRNG draws consumed while choosing the
/// replacement (`0` for the deterministic ranking path). The observer cannot
/// draw randomness, mutate state or change the ledger.
final class ReplacementDrawTrace {
  const ReplacementDrawTrace({
    required this.teamId,
    required this.playerOutId,
    required this.playerInId,
    required this.draws,
  });

  final String teamId;
  final String playerOutId;

  /// `null` when no eligible bench player exists.
  final String? playerInId;
  final int draws;
}

final class RotationDrawTrace {
  const RotationDrawTrace({required this.teamId, required this.draws});

  final String teamId;

  /// PRNG draws consumed by the tactical decision; always zero by contract.
  final int draws;
}

final class GameSimulator {
  GameSimulator({
    BasketballProbabilityModel? probabilityModel,
    this.onPhaseTrace,
    this.onReplacementDraw,
    this.onRotationDraw,
  }) : _injectedModel = probabilityModel;

  final BasketballProbabilityModel? _injectedModel;

  /// Optional passive A1 phase observer (default disabled). It cannot draw
  /// randomness, mutate state or change the ledger.
  final void Function(PhaseTraceRecord record)? onPhaseTrace;

  /// Optional passive replacement-selection observer (default disabled). It
  /// runs after the ranking decision and only reads the PRNG draw counter.
  final void Function(ReplacementDrawTrace trace)? onReplacementDraw;

  /// Optional passive tactical-decision observer (default disabled). It only
  /// reads the PRNG draw counter; the policy is deterministic.
  final void Function(RotationDrawTrace trace)? onRotationDraw;

  /// Simulates and validates one game. Throws [GameValidationException] on any
  /// illegal state, incompatible injected model or bound; never returns a
  /// partial result.
  GameResult simulate(GameInput input) {
    final injected = _injectedModel;
    if (injected == null) {
      return _GameRun(
        input,
        BasketballProbabilityModel(
          rules: input.rules,
          players: [
            for (final team in input.league.teams)
              for (final player in team.players) player,
          ],
        ),
        onPhaseTrace,
        onReplacementDraw,
        onRotationDraw,
      ).run();
    }
    _requireCompatibleA1(injected.rules, input.rules);
    _requireCanonicalRoster(injected, input);
    return _GameRun(
      input,
      injected,
      onPhaseTrace,
      onReplacementDraw,
      onRotationDraw,
    ).run();
  }

  /// Rejects an injected model whose roster disagrees with the input league.
  ///
  /// An injected model built without players falls back to the immutable input
  /// lineups, which [GameInput] has already canonicalised against this league.
  static void _requireCanonicalRoster(
    BasketballProbabilityModel model,
    GameInput input,
  ) {
    final modelPlayers = model.rosterPlayers;
    if (modelPlayers.isEmpty) return;
    final issues = <GameValidationIssue>[];
    for (final team in [input.homeTeam, input.awayTeam]) {
      for (final player in team.players) {
        final candidate = modelPlayers[player.id.value];
        if (candidate == null ||
            candidate.position != player.position ||
            !_sameAttributes(candidate, player)) {
          issues.add(
            GameValidationIssue(
              code: GameValidationCode.invalidRules,
              path: 'probabilityModel.players',
              message:
                  'injected model player ${player.id.value} does not match the '
                  'input league roster',
            ),
          );
        }
      }
    }
    if (issues.isNotEmpty) throw GameValidationException(issues);
  }

  static bool _sameAttributes(Player left, Player right) {
    final a = left.attributes.asMap;
    final b = right.attributes.asMap;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return a.length == b.length;
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
    if (!_sameBrackets(
      modelRules.orebPhaseDurations,
      inputRules.orebPhaseDurations,
    )) {
      issues.add(
        GameValidationIssue(
          code: GameValidationCode.invalidRules,
          path: 'rules.orebPhaseDurations',
          message:
              'injected model oreb phase durations '
              '${_formatBrackets(modelRules.orebPhaseDurations)} do not match '
              'input ${_formatBrackets(inputRules.orebPhaseDurations)}',
        ),
      );
    }
    if (!_sameBrackets(
      modelRules.retainedFoulPhaseDurations,
      inputRules.retainedFoulPhaseDurations,
    )) {
      issues.add(
        GameValidationIssue(
          code: GameValidationCode.invalidRules,
          path: 'rules.retainedFoulPhaseDurations',
          message:
              'injected model retained foul phase durations '
              '${_formatBrackets(modelRules.retainedFoulPhaseDurations)} do not '
              'match input '
              '${_formatBrackets(inputRules.retainedFoulPhaseDurations)}',
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
  _GameRun(
    this.input,
    this._model, [
    this._trace,
    this._replacementDraw,
    this._rotationDraw,
  ]) : rules = input.rules,
       rng = DeterministicRandom(input.normalizedSeed),
       fingerprint = GameFingerprint.of(input) {
    _teamFouls[input.homeTeamId.value] = 0;
    _teamFouls[input.awayTeamId.value] = 0;
  }

  final GameInput input;
  final BasketballProbabilityModel _model;
  final void Function(PhaseTraceRecord record)? _trace;
  final void Function(ReplacementDrawTrace trace)? _replacementDraw;
  final void Function(RotationDrawTrace trace)? _rotationDraw;
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
        context: _context.wire,
      ),
    );
  }

  final DeterministicRandom rng;
  final String fingerprint;

  final List<GameEvent> events = <GameEvent>[];
  final Map<String, int> _teamFouls = <String, int>{};

  late final Map<String, Player> _playersById = {
    for (final team in input.league.teams)
      for (final player in team.players) player.id.value: player,
  };

  late TeamOnCourt _homeOnCourt = TeamOnCourt(
    teamId: input.homeTeamId,
    lineup: input.homeLineup,
  );
  late TeamOnCourt _awayOnCourt = TeamOnCourt(
    teamId: input.awayTeamId,
    lineup: input.awayLineup,
  );

  final Map<String, int> _playerFouls = <String, int>{};
  final Set<String> _pendingPeriodReplacements = <String>{};

  late final RotationPlan? _rotation = input.rotationPlan;
  final Map<String, int> _regulationActual = <String, int>{};
  final Map<String, int> _overtimeActual = <String, int>{};
  final Map<String, int> _overtimeTargets = <String, int>{};
  final Set<String> _overtimeTacticalTeams = <String>{};
  final RotationWindowHistory _windowHistory = RotationWindowHistory();
  final Set<String> _mandatoryTeams = <String>{};
  int? _overtimeAllocationPeriod;
  int _completedGameSeconds = 0;
  int _lastAccrualGameSeconds = 0;

  int _sequence = 0;
  int _period = 1;
  int _clock = 0;
  int? _shotClock;
  PossessionContext _context = PossessionContext.fresh;
  String? _possessionId;
  bool _possessionOpen = false;
  late TeamId _offense = input.startingTeamId;
  int _possessionCounter = 0;
  int _freeThrowGroupCounter = 0;
  int _lastClock = 0;
  int _zeroTimeEvents = 0;

  bool get _rotationEnabled => _rotation != null;

  int get _cumulativeGameSeconds =>
      _completedGameSeconds + (rules.periodLength(_period) - _clock);

  /// Accrues elapsed game seconds to every active player in the active phase
  /// bucket. Called at window boundaries and at the period horn.
  void _accruePlaytime() {
    if (!_rotationEnabled) return;
    final now = _cumulativeGameSeconds;
    final delta = now - _lastAccrualGameSeconds;
    if (delta <= 0) return;
    final bucket = _period > rules.periods
        ? _overtimeActual
        : _regulationActual;
    for (final teamId in [input.homeTeamId.value, input.awayTeamId.value]) {
      for (final slot in _onCourt(TeamId(teamId)).lineup.slots) {
        final playerId = slot.playerId.value;
        bucket[playerId] = (bucket[playerId] ?? 0) + delta;
      }
    }
    _lastAccrualGameSeconds = now;
  }

  /// Opens a substitution window for rotation purposes: commits the previous
  /// window's tactical swap (or null), clears the sliding history, and accrues
  /// playtime to the current clock.
  void _beginWindow() {
    if (!_rotationEnabled) return;
    _accruePlaytime();
    _windowHistory.beginWindow([
      input.homeTeamId.value,
      input.awayTeamId.value,
    ]);
    _mandatoryTeams.clear();
  }

  void _ensureOvertimeTargets() {
    if (!_rotationEnabled || _period <= rules.periods) return;
    if (_overtimeAllocationPeriod == _period) return;
    final plan = _rotation!;
    for (final teamId in [input.homeTeamId.value, input.awayTeamId.value]) {
      final team = _teamById(teamId);
      final teamPlan = teamId == input.homeTeamId.value ? plan.home : plan.away;
      final allocation = RotationPolicy.allocateOvertime(
        team: team,
        activeLineup: _onCourt(TeamId(teamId)).lineup,
        regulationTargets: teamPlan.targetSeconds,
        disqualified: {
          for (final player in team.players)
            if (_disqualified(player.id.value)) player.id,
        },
        overtimeSeconds: rules.overtimeSeconds,
        regulationCap: RotationPlan.regulationCap(rules),
      );
      for (final entry in allocation.targetSeconds.entries) {
        _overtimeTargets[entry.key.value] = entry.value;
      }
      if (allocation.tacticalEnabled) _overtimeTacticalTeams.add(teamId);
    }
    _overtimeAllocationPeriod = _period;
  }

  void _runTacticalHooks() {
    if (!_rotationEnabled || _clock <= 0) return;
    _ensureOvertimeTargets();
    for (final teamId in [input.homeTeamId.value, input.awayTeamId.value]) {
      if (_mandatoryTeams.contains(teamId)) continue;
      if (_pendingPeriodReplacements.contains(teamId)) continue;
      if (_period > rules.periods && !_overtimeTacticalTeams.contains(teamId)) {
        continue;
      }
      _proposeTactical(teamId);
    }
  }

  void _proposeTactical(String teamId) {
    final drawsBefore = _rotationDraw == null ? 0 : rng.drawCount;
    final plan = _rotation!;
    final teamPlan = teamId == input.homeTeamId.value ? plan.home : plan.away;
    final team = _teamById(teamId);
    final lineup = _onCourt(TeamId(teamId)).lineup;
    final overtime = _period > rules.periods;
    final targets = overtime
        ? <PlayerId, int>{
            for (final player in team.players)
              player.id: _overtimeTargets[player.id.value] ?? 0,
          }
        : teamPlan.targetSeconds;
    final actual = overtime ? _overtimeActual : _regulationActual;
    final elapsedSeconds = overtime
        ? rules.overtimeSeconds - _clock
        : _cumulativeGameSeconds;
    final horizonSeconds = overtime
        ? rules.overtimeSeconds
        : RotationPlan.regulationCap(rules);
    final proposal = RotationPolicy.propose(
      RotationPolicyInput(
        team: team,
        activeLineup: lineup,
        targetSeconds: targets,
        actualSeconds: {
          for (final player in team.players)
            player.id: actual[player.id.value] ?? 0,
        },
        elapsedSeconds: elapsedSeconds,
        horizonSeconds: horizonSeconds,
        activePeriodSeconds: overtime
            ? rules.overtimeSeconds
            : rules.periodSeconds,
        gameSecondsElapsed: _cumulativeGameSeconds,
        disqualified: {
          for (final player in team.players)
            if (_disqualified(player.id.value)) player.id,
        },
        mandatoryReplacementPending: _pendingPeriodReplacements.contains(
          teamId,
        ),
        swappedThisWindow: _windowHistory.swappedThisWindow(teamId),
        previousWindowSwap: _windowHistory.previousWindowSwap(teamId),
        lastTacticalSwapGameSeconds: _windowHistory.lastTacticalSwapSeconds(
          teamId,
        ),
      ),
    );
    _rotationDraw?.call(
      RotationDrawTrace(teamId: teamId, draws: rng.drawCount - drawsBefore),
    );
    if (proposal == null) return;
    _emit(
      Substitution(
        sequence: _nextSequence(),
        period: _period,
        gameClock: _clock,
        shotClock: _shotClock,
        teamId: teamId,
        playerOutId: proposal.playerOutId.value,
        playerInId: proposal.playerInId.value,
        reason: SubstitutionReason.tactical,
      ),
    );
    _applySubstitution(
      teamId: teamId,
      playerOutId: proposal.playerOutId.value,
      playerInId: proposal.playerInId.value,
    );
    _windowHistory.recordSwap(teamId, proposal, _cumulativeGameSeconds);
  }

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
      _accruePlaytime();
      _emit(
        PeriodEnded(
          sequence: _nextSequence(),
          period: _period,
          gameClock: 0,
          shotClock: null,
        ),
      );
      _completedGameSeconds += rules.periodLength(_period);

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
    if (_rotationEnabled && _period > rules.periods) {
      _overtimeActual.clear();
      _overtimeTargets.clear();
      _overtimeTacticalTeams.clear();
      _overtimeAllocationPeriod = null;
    }
    _emit(
      PeriodStarted(
        sequence: _nextSequence(),
        period: _period,
        gameClock: _clock,
        shotClock: null,
        startingTeamId: _offense.value,
      ),
    );
    if (_rotationEnabled) _beginWindow();
    // W5: satisfy any deferred or outstanding disqualification before the
    // first possession of the period.
    for (final teamId in [input.homeTeamId.value, input.awayTeamId.value]) {
      final lineup = _onCourt(TeamId(teamId)).lineup;
      for (final slot in lineup.slots) {
        if (_disqualified(slot.playerId.value)) {
          _emitFoulOutReplacement(
            teamId: teamId,
            playerId: slot.playerId.value,
            clock: _clock,
            shotClock: null,
          );
        }
      }
    }
    _pendingPeriodReplacements.clear();
    _runTacticalHooks();
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
    _context = PossessionContext.fresh;
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
    _context = PossessionContext.fresh;
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
      final phase = _model.drawPhaseDuration(rng, _context);
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
        final handler = _player(
          _onCourt(_offense),
          _onCourt(_offense).lineup.slots.first.playerId.value,
        );
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
        final handler = _player(
          _onCourt(_offense),
          _onCourt(_offense).lineup.slots.first.playerId.value,
        );
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
      _recordFoul(action.foulingDefenderId!.value);
      if (_rotationEnabled &&
          clock > 0 &&
          _disqualified(action.foulingDefenderId!.value)) {
        _beginWindow();
      }
      _emitFoulOutReplacement(
        teamId: defense.value,
        playerId: action.foulingDefenderId!.value,
        clock: clock,
        shotClock: shotClock,
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
        _recordFoul(action.foulingDefenderId!.value);
        if (_rotationEnabled &&
            clock > 0 &&
            _disqualified(action.foulingDefenderId!.value)) {
          _beginWindow();
        }
        _emitFoulOutReplacement(
          teamId: defense.value,
          playerId: action.foulingDefenderId!.value,
          clock: clock,
          shotClock: shotClock,
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
      _context = PossessionContext.oreb;
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
    _recordFoul(action.playerId.value);
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
    if (_rotationEnabled && _clock > 0) _beginWindow();
    _emitFoulOutReplacement(
      teamId: _offense.value,
      playerId: action.playerId.value,
      clock: _clock,
      shotClock: null,
    );
    if (_rotationEnabled && _clock > 0) _runTacticalHooks();
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
    _recordFoul(action.committingPlayerId.value);
    if (bonus) {
      if (_rotationEnabled &&
          _clock > 0 &&
          _disqualified(action.committingPlayerId.value)) {
        _beginWindow();
      }
      _emitFoulOutReplacement(
        teamId: defense.value,
        playerId: action.committingPlayerId.value,
        clock: _clock,
        shotClock: _shotClock,
      );
      _resolveFreeThrows(shooterId: action.drawnByPlayerId.value, attempts: 2);
      return;
    }
    if (_rotationEnabled && _clock > 0) _beginWindow();
    final floor = rules.nonBonusFoulResetFloorSeconds;
    final current = _shotClock!;
    _shotClock = current > floor ? current : floor;
    _context = PossessionContext.retainedFoul;
    if (_shotClock! > rules.shotClockSeconds) {
      _shotClock = rules.shotClockSeconds;
    }
    _emitFoulOutReplacement(
      teamId: defense.value,
      playerId: action.committingPlayerId.value,
      clock: _clock,
      shotClock: _shotClock,
    );
    if (_rotationEnabled && _clock > 0) _runTacticalHooks();
  }

  Team _teamById(String teamId) =>
      input.league.teams.firstWhere((team) => team.id.value == teamId);

  int _recordFoul(String playerId) =>
      _playerFouls[playerId] = (_playerFouls[playerId] ?? 0) + 1;

  bool _disqualified(String playerId) =>
      (_playerFouls[playerId] ?? 0) >= rules.foulOutLimit;

  List<Player> _eligibleBench(String teamId, CourtLineup lineup) => [
    for (final player in _teamById(teamId).players)
      if (!lineup.containsPlayer(player.id) && !_disqualified(player.id.value))
        player,
  ];

  /// Deterministic replacement: same slot position first, then roster order.
  Player? _replacementFor(String teamId, PlayerId outId) {
    final observer = _replacementDraw;
    final drawsBefore = observer == null ? 0 : rng.drawCount;
    final lineup = _onCourt(TeamId(teamId)).lineup;
    final candidates = _eligibleBench(teamId, lineup);
    Player? selected;
    if (candidates.isNotEmpty) {
      final slot = lineup.slotOf(outId);
      selected = candidates.firstWhere(
        (player) => player.position == slot,
        orElse: () => candidates.first,
      );
    }
    if (observer != null) {
      observer(
        ReplacementDrawTrace(
          teamId: teamId,
          playerOutId: outId.value,
          playerInId: selected?.id.value,
          draws: rng.drawCount - drawsBefore,
        ),
      );
    }
    return selected;
  }

  void _applySubstitution({
    required String teamId,
    required String playerOutId,
    required String playerInId,
  }) {
    final side = _onCourt(TeamId(teamId));
    final players = [
      for (final slot in side.lineup.slots)
        slot.playerId.value == playerOutId
            ? _playersById[playerInId]!
            : _playersById[slot.playerId.value]!,
    ];
    final lineup = CourtLineup.create(
      team: _teamById(teamId),
      slotOrderedPlayers: players,
    );
    if (teamId == input.homeTeamId.value) {
      _homeOnCourt = TeamOnCourt(teamId: input.homeTeamId, lineup: lineup);
    } else {
      _awayOnCourt = TeamOnCourt(teamId: input.awayTeamId, lineup: lineup);
    }
  }

  /// Emits a mandatory foul-out substitution at the current window.
  ///
  /// Returns true when an event was emitted. At clock zero the requirement is
  /// deferred to the next period's W5.
  bool _emitFoulOutReplacement({
    required String teamId,
    required String playerId,
    required int clock,
    required int? shotClock,
  }) {
    if (!_disqualified(playerId)) return false;
    if (_replacementFor(teamId, PlayerId(playerId)) == null) return false;
    if (clock == 0) {
      _pendingPeriodReplacements.add(teamId);
      return false;
    }
    final replacement = _replacementFor(teamId, PlayerId(playerId))!;
    _emit(
      Substitution(
        sequence: _nextSequence(),
        period: _period,
        gameClock: clock,
        shotClock: shotClock,
        teamId: teamId,
        playerOutId: playerId,
        playerInId: replacement.id.value,
        reason: SubstitutionReason.foulOut,
      ),
    );
    _applySubstitution(
      teamId: teamId,
      playerOutId: playerId,
      playerInId: replacement.id.value,
    );
    _mandatoryTeams.add(teamId);
    return true;
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
      if (_rotationEnabled && _clock > 0) {
        _beginWindow();
        _runTacticalHooks();
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
      _context = PossessionContext.oreb;
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
    final player = _playersById[playerId];
    if (player == null) {
      throw StateError(
        'player $playerId is not active for ${side.teamId.value}',
      );
    }
    return player;
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
