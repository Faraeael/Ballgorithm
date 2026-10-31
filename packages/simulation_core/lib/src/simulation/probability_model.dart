import 'dart:math' show max;

import '../generation/deterministic_random.dart';
import '../models/ids.dart';
import '../models/player.dart';
import 'action_intent.dart';
import 'active_lineup.dart';
import 'game_rules.dart';

/// Provisional, uncalibrated ratings-based basketball decision model (T008).
///
/// Pure integer basis points (`0..10000`) and the game-local
/// [DeterministicRandom]. No floats, no clocks, no possession state: the model
/// answers "what does this offence attempt, and who does what", while T009/T010
/// translate decisions into ledger events and resolve clock precedence.
///
/// ## Determinism contract
///
/// Callers pass one seeded `DeterministicRandom`; every public draw method
/// consumes a fixed, documented number of draws:
///
/// `drawPhaseDuration` (A1, two draws):
/// 1. `typeDraw = nextInt(10000)` → transition `0..1499`, early `1500..4499`,
///    half-court `4500..9999` from [GameRules.phaseWeights].
/// 2. `offsetDraw = nextInt(upper - lower + 1)` → `duration = lower + offsetDraw`
///    from [GameRules.phaseDurations]; never clamped to a clock.
///
/// `selectAction` (normal live phase):
/// 1. category `nextInt(10000)`: turnover, offensive foul, non-shooting foul,
///    else field-goal attempt;
/// 2. actor `nextInt(10000)` over the documented weights (ballhandler weights
///    for turnover/fouls, shot-usage weights for a field goal);
/// 3. turnover: steal share `nextInt(10000)`, then (steal only) defender
///    `nextInt(10000)`;
///    field goal: zone `nextInt(10000)` then make `nextInt(10000)`;
/// 4. field goal only: foul draw `nextInt(10000)` (and-one check when made,
///    shooting-foul check when missed); then assist draw `nextInt(10000)` and
///    (assisted only) passer `nextInt(10000)` when made, or block draw
///    `nextInt(10000)` and (blocked only) blocker `nextInt(10000)` when missed
///    without a foul.
///
/// `selectFinalTickAction` consumes no A1 draws and no category draw: its first
/// draw is the actor draw, then zone, make, foul, assist/block as above.
///
/// `resolveRebound`: rebound team `nextInt(10000)`, then rebounder
/// `nextInt(10000)` over the winning side's weights.
///
/// `resolveFreeThrows`: one `nextInt(10000)` per awarded attempt.
///
/// ## Provisional coefficient summary (uncalibrated)
///
/// All values are basis points and explicitly clamped. Sharp arithmetic
/// modifiers use `rating - 50` deltas. Directional expectations, not realism,
/// are the contract; formal calibration is T014/T015.
///
/// - **Shot usage** (`shotUsageWeights`): position base PG 260, SG 240, SF 220,
///   PF 190, C 170; + `max(0, bestShotRating - 50) * 3`;
///   + `(ballHandling - 50) * 2`; + `(basketballIQ - 50)`; floor 60.
/// - **Zone choice** (`shotZoneWeights`): inside 2400 + `(insideScoring-50)*22`
///   + `(athleticism-50)*10` + position bonus; midrange 2500 +
///   `(midrange-50)*26` + position bonus; three 3600 + `(threePoint-50)*24` +
///   position bonus; phase modifiers. Position bonuses (PG→C): inside
///   `-400,-250,0,600,900`, midrange `100,200,150,0,-300`, three
///   `250,350,200,-400,-900`.
/// - **Make** (`shotMakeBasisPoints`): base 5300 inside, 4000 midrange, 3300
///   three; + `(zoneRating-50)*40`; + `(basketballIQ-50)*8`;
///   + `(teamAvgPassing-50)*4` assist quality; + `(athleticism-50)*6` inside
///   only; - `(defenderInteriorOrPerimeterDefense-50)*30`; clamp 700..9000.
/// - **Turnover** (`turnoverBasisPoints`): 1050 - `(teamAvgBallHandling-50)*7`
///   - `(teamAvgPassing-50)*3` - `(teamAvgIQ-50)*3`
///   + `(opponentAvgPerimeterDefense-50)*5` + `(opponentAvgAthleticism-50)*2`
///   + phase bonus (transition 250, early 100, half-court 0); clamp 150..2500.
/// - **Steal weighting**: `perimeterDefense*3 + athleticism*2` + position
///   bonus PG 200, SG 160, SF 120, PF 80, C 40 (guard-leaning, documented in
///   `specs/002-possession-simulation/probability-model.md`).
/// - **Steal share** (`stealShareBasisPoints`): 4800 +
///   `(opponentAvgPerimeterDefense-50)*14` + `(opponentAvgAthleticism-50)*6`
///   - `(ballhandlerBallHandling-50)*6` - `(ballhandlerPassing-50)*3`;
///   clamp 1500..8500.
/// - **Offensive foul**: 420 - `(teamAvgIQ-50)*3` + `(opponentAvgIQ-50)*2`
///   + `(teamAvgAthleticism-50)*2`; clamp 100..1000.
/// - **Non-shooting defensive foul**: 1000 + `(50 - opponentAvgIQ)*5`
///   + `(teamAvgAthleticism-50)*4` + `(teamAvgIQ-50)*2`; clamp 300..2200.
/// - **Shooting foul on a miss**: 800 + `(athleticism-50)*4`
///   + `(IQ-50)*2` + `(insideScoring-50)*2` + `(50 - defenderIQ)*3`;
///   clamp 200..2400.
/// - **And-one**: 160 + `(athleticism-50)*3` + `(insideScoring-50)*3`
///   - `(defenderInteriorDefense-50)*2`; clamp 30..800.
/// - **Assist**: 5400 + `(teamAvgPassing-50)*12` + `(teamAvgIQ-50)*8`;
///   clamp 1500..9000. Passer weights: `passing*3 + IQ*2` + position bonus
///   PG 300, SG 150, SF 100, PF 60, C 40 (teammates only).
/// - **Block**: 520 inside/midrange, 220 three; +
///   `(defenderInteriorDefense-50)*8` + `(defenderAthleticism-50)*5`
///   - `(shooterInsideScoring-50)*4` - `(shooterIQ-50)*2`; clamp 50..2200.
///   Blocker weights: `interiorDefense*3 + athleticism*2` + position bonus
///   PG 20, SG 40, SF 120, PF 260, C 380.
/// - **Offensive-rebound share**: 2700 + `(offReboundStrength -
///   defReboundStrength)*12` + zone bonus (inside 100, midrange 0, three 150),
///   where strength = `avgRebounding*2 + avgAthleticism`; clamp 800..4500.
///   Rebounder weights: `rebounding*3 + athleticism` + position bonus
///   PG 0, SG 40, SF 100, PF 220, C 300.
/// - **Free throw**: 6000 + `(freeThrow-50)*65`; clamp 1500..9800.
///
/// `midrange` affects both zone selection and conversion. `stamina` is never
/// read (M003). A defense's assigned defender is the same canonical lineup
/// index (PG defends PG … C defends C).
final class BasketballProbabilityModel {
  BasketballProbabilityModel({GameRules? rules})
    : rules = rules ?? GameRules.standard;

  final GameRules rules;

  static const int _maxBasisPoints = 10000;

  // --- Positional baselines, indexed PG, SG, SF, PF, C. -------------------

  static const List<int> _usagePositionBase = [260, 240, 220, 190, 170];
  static const List<int> _handlePositionBase = [420, 320, 280, 220, 180];
  static const List<int> _insidePositionBonus = [-400, -250, 0, 600, 900];
  static const List<int> _midrangePositionBonus = [100, 200, 150, 0, -300];
  static const List<int> _threePositionBonus = [250, 350, 200, -400, -900];
  static const List<int> _assistPositionBonus = [300, 150, 100, 60, 40];
  static const List<int> _blockPositionBonus = [20, 40, 120, 260, 380];
  static const List<int> _stealPositionBonus = [200, 160, 120, 80, 40];
  static const List<int> _reboundPositionBonus = [0, 40, 100, 220, 300];

  /// Phase modifiers indexed [PhaseKind.values].
  static const List<int> _insidePhaseBonus = [700, 0, -300];
  static const List<int> _midrangePhaseBonus = [-300, 0, 100];
  static const List<int> _threePhaseBonus = [-400, 0, 200];
  static const List<int> _turnoverPhaseBonus = [250, 100, 0];
  static const List<int> _reboundZoneBonus = [100, 0, 150];

  // --- Amendment 002 (simulation v2): exposure/security contract ----------

  /// Position role bases for turnover exposure (PG..C).
  static const List<int> _exposurePositionBase = [420, 320, 280, 220, 180];
  static const int _exposurePassingWeight = 2;
  static const int _exposureIqWeight = 1;

  /// Base individual live-turnover hazard and per-point security slopes.
  static const int _turnoverBaseBasisPoints = 1093;
  static const int _hazardBallHandlingSlope = -10;
  static const int _hazardPassingSlope = -4;
  static const int _hazardIqSlope = -4;
  static const int _hazardPerimeterDefenseSlope = 7;
  static const int _hazardAthleticismSlope = 3;
  static const int _hazardMinBasisPoints = 150;
  static const int _hazardMaxBasisPoints = 2500;

  // --- A1 duration --------------------------------------------------------

  /// Draws the owner-approved A1 phase type and planned duration.
  ///
  /// Exactly two draws: `nextInt(10000)` then `nextInt(bracketSize)`. The
  /// result is a plan only; the orchestrator compares it with the clocks and
  /// never clamps it (OD-02).
  PhaseDuration drawPhaseDuration(
    DeterministicRandom rng, [
    PossessionContext context = PossessionContext.fresh,
  ]) {
    final weights = rules.phaseWeights;
    final brackets = switch (context) {
      PossessionContext.fresh => rules.phaseDurations,
      PossessionContext.oreb => rules.orebPhaseDurations,
      PossessionContext.retainedFoul => rules.retainedFoulPhaseDurations,
    };
    if (weights.length != 3 ||
        brackets.length != 3 ||
        weights.reduce((a, b) => a + b) != _maxBasisPoints) {
      throw StateError('GameRules phase weights/brackets must be validated');
    }
    final typeDraw = rng.nextInt(_maxBasisPoints);
    var index = 0;
    var cumulative = 0;
    for (var i = 0; i < weights.length; i++) {
      cumulative += weights[i];
      if (typeDraw < cumulative) {
        index = i;
        break;
      }
    }
    final bracket = brackets[index];
    final count = bracket[1] - bracket[0] + 1;
    final offset = rng.nextInt(count);
    return PhaseDuration(
      kind: PhaseKind.values[index],
      seconds: bracket[0] + offset,
    );
  }

  // --- Action selection ---------------------------------------------------

  /// Selects the terminal decision for a normal live offensive phase.
  ///
  /// The caller must already own the phase's A1 draws; this method consumes no
  /// duration draws.
  OffensiveAction selectAction({
    required TeamOnCourt offense,
    required TeamOnCourt defense,
    required PhaseKind phase,
    required DeterministicRandom rng,
  }) {
    final turnover = turnoverBasisPoints(
      offense: offense,
      defense: defense,
      phase: phase,
    );
    final offensiveFoul = offensiveFoulBasisPoints(
      offense: offense,
      defense: defense,
    );
    final nonShootingFoul = nonShootingFoulBasisPoints(
      offense: offense,
      defense: defense,
    );
    final categoryDraw = rng.nextInt(_maxBasisPoints);
    if (categoryDraw < turnover) {
      return _selectTurnover(
        offense,
        defense,
        rng,
        _actorWeights(
          exposureWeights(offense.lineup),
          playerTurnoverHazards(
            offense: offense,
            defense: defense,
            phase: phase,
          ),
        ),
      );
    }
    if (categoryDraw < turnover + offensiveFoul) {
      final offender = _pickWeighted(rng, offense.lineup, _ballHandlerScore);
      final index = _lineupIndex(offense.lineup, offender.id)!;
      return OffensiveFoulAction(
        offenseTeamId: offense.teamId,
        playerId: offender.id,
        victimId: defense.lineup.players[index].id,
      );
    }
    if (categoryDraw < turnover + offensiveFoul + nonShootingFoul) {
      final drawnBy = _pickWeighted(rng, offense.lineup, _ballHandlerScore);
      final index = _lineupIndex(offense.lineup, drawnBy.id)!;
      return NonShootingFoulAction(
        offenseTeamId: offense.teamId,
        committingPlayerId: defense.lineup.players[index].id,
        drawnByPlayerId: drawnBy.id,
      );
    }
    return _selectShot(offense, defense, phase, rng);
  }

  /// Final-tick deliberate attempt (OD-02): no A1 and no category draws.
  ///
  /// The caller has already established that one second remains and resolves
  /// the attempt at game clock zero.
  ShotAttemptAction selectFinalTickAction({
    required TeamOnCourt offense,
    required TeamOnCourt defense,
    required DeterministicRandom rng,
  }) {
    return _selectShot(offense, defense, PhaseKind.halfCourt, rng);
  }

  OffensiveAction _selectTurnover(
    TeamOnCourt offense,
    TeamOnCourt defense,
    DeterministicRandom rng,
    List<int> actorWeights,
  ) {
    final handler =
        offense.lineup.players[_pickWeightedIndex(rng, actorWeights)];
    final share = stealShareBasisPoints(ballhandler: handler, defense: defense);
    if (rng.nextInt(_maxBasisPoints) < share) {
      final thief = _pickWeighted(rng, defense.lineup, _stealScore);
      return TurnoverAction(
        offenseTeamId: offense.teamId,
        playerId: handler.id,
        kind: TurnoverKind.steal,
        stolenById: thief.id,
      );
    }
    return TurnoverAction(
      offenseTeamId: offense.teamId,
      playerId: handler.id,
      kind: TurnoverKind.nonSteal,
    );
  }

  ShotAttemptAction _selectShot(
    TeamOnCourt offense,
    TeamOnCourt defense,
    PhaseKind phase,
    DeterministicRandom rng,
  ) {
    final shooter = offense
        .lineup
        .players[_pickWeightedIndex(rng, shotUsageWeights(offense.lineup))];
    final index = _lineupIndex(offense.lineup, shooter.id)!;
    final defender = defense.lineup.players[index];

    final zoneWeights = shotZoneWeights(shooter: shooter, phase: phase);
    final zoneDraw = rng.nextInt(_maxBasisPoints);
    var zone = ShotZone.three;
    if (zoneDraw < zoneWeights[0]) {
      zone = ShotZone.inside;
    } else if (zoneDraw < zoneWeights[0] + zoneWeights[1]) {
      zone = ShotZone.midrange;
    }

    final makeBp = shotMakeBasisPoints(
      shooter: shooter,
      defender: defender,
      zone: zone,
      offense: offense.lineup,
    );
    final made = rng.nextInt(_maxBasisPoints) < makeBp;

    if (made) {
      final andOneBp = andOneBasisPoints(shooter: shooter, defender: defender);
      final andOne = rng.nextInt(_maxBasisPoints) < andOneBp;
      PlayerId? assistedById;
      final assistBp = assistBasisPoints(offense.lineup);
      if (rng.nextInt(_maxBasisPoints) < assistBp) {
        final passer = _pickWeighted(
          rng,
          offense.lineup,
          _assistScore,
          exclude: shooter.id,
        );
        assistedById = passer.id;
      }
      return ShotAttemptAction(
        offenseTeamId: offense.teamId,
        shooterId: shooter.id,
        zone: zone,
        made: true,
        andOne: andOne,
        freeThrowsAwarded: andOne ? 1 : 0,
        foulingDefenderId: andOne ? defender.id : null,
        assistedById: assistedById,
      );
    }

    final foulBp = shootingFoulBasisPoints(
      shooter: shooter,
      defender: defender,
    );
    if (rng.nextInt(_maxBasisPoints) < foulBp) {
      return ShotAttemptAction(
        offenseTeamId: offense.teamId,
        shooterId: shooter.id,
        zone: zone,
        made: false,
        andOne: false,
        freeThrowsAwarded: zone.shotValue,
        foulingDefenderId: defender.id,
      );
    }

    final blockBp = blockBasisPoints(
      shooter: shooter,
      defender: defender,
      zone: zone,
    );
    PlayerId? blockedById;
    if (rng.nextInt(_maxBasisPoints) < blockBp) {
      final blocker = _pickWeighted(rng, defense.lineup, _blockScore);
      blockedById = blocker.id;
    }
    return ShotAttemptAction(
      offenseTeamId: offense.teamId,
      shooterId: shooter.id,
      zone: zone,
      made: false,
      andOne: false,
      freeThrowsAwarded: 0,
      blockedById: blockedById,
    );
  }

  // --- Rebound ------------------------------------------------------------

  /// Resolves one live miss into exactly one offensive or defensive rebound.
  ///
  /// [zone] is null for a missed final free throw. Draws: rebound team
  /// `nextInt(10000)`, then rebounder `nextInt(10000)` on the winning side.
  ReboundIntent resolveRebound({
    required TeamOnCourt offense,
    required TeamOnCourt defense,
    required DeterministicRandom rng,
    ShotZone? zone,
  }) {
    final share = offensiveReboundBasisPoints(
      offense: offense,
      defense: defense,
      zone: zone,
    );
    final offensive = rng.nextInt(_maxBasisPoints) < share;
    final side = offensive ? offense : defense;
    final rebounder = _pickWeighted(rng, side.lineup, _reboundScore);
    return ReboundIntent(
      teamId: side.teamId,
      playerId: rebounder.id,
      offensive: offensive,
    );
  }

  // --- Free throws --------------------------------------------------------

  /// Resolves one deterministic free-throw group (1..3 attempts).
  ///
  /// The shooter is resolved from [offense] by ID; the supplied object only
  /// identifies the actor, never supplies its ratings. Throws [ArgumentError]
  /// when the ID is not active in [offense] or the award size is invalid.
  /// The caller decides the bonus rule and event grouping.
  FreeThrowGroupIntent resolveFreeThrows({
    required TeamOnCourt offense,
    required Player shooter,
    required int attempts,
    required DeterministicRandom rng,
  }) {
    if (attempts < 1 || attempts > 3) {
      throw ArgumentError.value(attempts, 'attempts', 'must be 1..3');
    }
    final index = _lineupIndex(offense.lineup, shooter.id);
    if (index == null) {
      throw ArgumentError.value(
        shooter.id.value,
        'shooter',
        'shooter must be active in the offense lineup',
      );
    }
    final activeShooter = offense.lineup.players[index];
    final madeBp = freeThrowMakeBasisPoints(activeShooter);
    final made = <bool>[
      for (var i = 0; i < attempts; i++) rng.nextInt(_maxBasisPoints) < madeBp,
    ];
    return FreeThrowGroupIntent(
      teamId: offense.teamId,
      shooterId: activeShooter.id,
      madeByAttempt: made,
    );
  }

  // --- Public probability functions ---------------------------------------

  /// Clamps [value] into `[min, max]` inside `0..10000`.
  static int clampBasisPoints(int value, {int min = 0, int max = 10000}) {
    if (min < 0 || max > _maxBasisPoints || min > max) {
      throw ArgumentError('invalid basis-point clamp $min..$max');
    }
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  /// Normalized shot-usage weights summing to 10000.
  List<int> shotUsageWeights(ActiveLineup offense) {
    final raw = <int>[
      for (final player in offense.players)
        max(
          60,
          _usagePositionBase[player.position.index] +
              max(
                    0,
                    max(
                          player.attributes.insideScoring,
                          max(
                            player.attributes.midrange,
                            player.attributes.threePoint,
                          ),
                        ) -
                        50,
                  ) *
                  3 +
              (player.attributes.ballHandling - 50) * 2 +
              (player.attributes.basketballIQ - 50),
        ),
    ];
    return _normalize(raw);
  }

  /// Normalized zone weights `[inside, midrange, three]` summing to 10000.
  List<int> shotZoneWeights({
    required Player shooter,
    required PhaseKind phase,
  }) {
    final a = shooter.attributes;
    final position = shooter.position.index;
    final raw = <int>[
      max(
        200,
        2400 +
            (a.insideScoring - 50) * 22 +
            (a.athleticism - 50) * 10 +
            _insidePositionBonus[position] +
            _insidePhaseBonus[phase.index],
      ),
      max(
        200,
        2500 +
            (a.midrange - 50) * 26 +
            _midrangePositionBonus[position] +
            _midrangePhaseBonus[phase.index],
      ),
      max(
        200,
        3600 +
            (a.threePoint - 50) * 24 +
            _threePositionBonus[position] +
            _threePhaseBonus[phase.index],
      ),
    ];
    return _normalize(raw);
  }

  /// Bounded two/three-point conversion probability.
  int shotMakeBasisPoints({
    required Player shooter,
    required Player defender,
    required ShotZone zone,
    required ActiveLineup offense,
  }) {
    final a = shooter.attributes;
    final d = defender.attributes;
    final team = _lineupAverages(offense);
    final base = switch (zone) {
      ShotZone.inside => 5300,
      ShotZone.midrange => 4000,
      ShotZone.three => 3300,
    };
    final zoneRating = switch (zone) {
      ShotZone.inside => a.insideScoring,
      ShotZone.midrange => a.midrange,
      ShotZone.three => a.threePoint,
    };
    final defenseRating = zone == ShotZone.inside
        ? d.interiorDefense
        : d.perimeterDefense;
    final athleticBonus = zone == ShotZone.inside
        ? (a.athleticism - 50) * 6
        : 0;
    return clampBasisPoints(
      base +
          (zoneRating - 50) * 40 +
          (a.basketballIQ - 50) * 8 +
          (team.passing - 50) * 4 +
          athleticBonus -
          (defenseRating - 50) * 30,
      min: 700,
      max: 9000,
    );
  }

  /// Normalized turnover exposure weights (PG..C), summing to 10000.
  ///
  /// Amendment 002: involvement is a role statement. `ballHandling` is
  /// deliberately excluded; passing and basketballIQ express playmaking and
  /// decision responsibility. Positive min-one largest-remainder allocation.
  List<int> exposureWeights(ActiveLineup lineup) {
    final raw = <int>[
      for (final player in lineup.players)
        max(
          1,
          _exposurePositionBase[player.position.index] +
              _exposurePassingWeight * (player.attributes.passing - 50) +
              _exposureIqWeight * (player.attributes.basketballIQ - 50),
        ),
    ];
    return allocatePositiveWeights(raw, _maxBasisPoints);
  }

  /// Individual live-turnover hazards in basis points (PG..C order).
  List<int> playerTurnoverHazards({
    required TeamOnCourt offense,
    required TeamOnCourt defense,
    required PhaseKind phase,
  }) {
    final def = _lineupAverages(defense.lineup);
    final defenseTerm =
        _hazardPerimeterDefenseSlope * (def.perimeterDefense - 50) +
        _hazardAthleticismSlope * (def.athleticism - 50);
    return [
      for (final player in offense.lineup.players)
        clampBasisPoints(
          _turnoverBaseBasisPoints +
              _hazardBallHandlingSlope * (player.attributes.ballHandling - 50) +
              _hazardPassingSlope * (player.attributes.passing - 50) +
              _hazardIqSlope * (player.attributes.basketballIQ - 50) +
              defenseTerm +
              _turnoverPhaseBonus[phase.index],
          min: _hazardMinBasisPoints,
          max: _hazardMaxBasisPoints,
        ),
    ];
  }

  /// Team live-turnover probability for the current phase.
  ///
  /// `H = clamp(floor(sum(E_i * h_i) / 10000), 150, 2500)`. Because every `h_i`
  /// is clamped into the same interval, this category clamp cannot bind.
  int turnoverBasisPoints({
    required TeamOnCourt offense,
    required TeamOnCourt defense,
    required PhaseKind phase,
  }) => _teamTurnoverBasisPoints(
    exposureWeights(offense.lineup),
    playerTurnoverHazards(offense: offense, defense: defense, phase: phase),
  );

  /// Normalized actor weights for a live turnover, summing to 10000.
  List<int> turnoverActorWeights({
    required TeamOnCourt offense,
    required TeamOnCourt defense,
    required PhaseKind phase,
  }) => _actorWeights(
    exposureWeights(offense.lineup),
    playerTurnoverHazards(offense: offense, defense: defense, phase: phase),
  );

  int _teamTurnoverBasisPoints(List<int> exposure, List<int> hazards) {
    var total = 0;
    for (var i = 0; i < exposure.length; i++) {
      total += exposure[i] * hazards[i];
    }
    return clampBasisPoints(
      total ~/ _maxBasisPoints,
      min: _hazardMinBasisPoints,
      max: _hazardMaxBasisPoints,
    );
  }

  static List<int> _actorWeights(List<int> exposure, List<int> hazards) =>
      allocatePositiveWeights([
        for (var i = 0; i < exposure.length; i++) exposure[i] * hazards[i],
      ], _maxBasisPoints);

  /// Share of live turnovers attributed to a steal.
  int stealShareBasisPoints({
    required Player ballhandler,
    required TeamOnCourt defense,
  }) {
    final a = ballhandler.attributes;
    final def = _lineupAverages(defense.lineup);
    return clampBasisPoints(
      4800 +
          (def.perimeterDefense - 50) * 14 +
          (def.athleticism - 50) * 6 -
          (a.ballHandling - 50) * 6 -
          (a.passing - 50) * 3,
      min: 1500,
      max: 8500,
    );
  }

  /// Normal offensive-foul probability.
  int offensiveFoulBasisPoints({
    required TeamOnCourt offense,
    required TeamOnCourt defense,
  }) {
    final off = _lineupAverages(offense.lineup);
    final def = _lineupAverages(defense.lineup);
    return clampBasisPoints(
      420 -
          (off.basketballIQ - 50) * 3 +
          (def.basketballIQ - 50) * 2 +
          (off.athleticism - 50) * 2,
      min: 100,
      max: 1000,
    );
  }

  /// Defensive non-shooting-foul probability. Bonus thresholds are resolved by
  /// the orchestrator, never here.
  int nonShootingFoulBasisPoints({
    required TeamOnCourt offense,
    required TeamOnCourt defense,
  }) {
    final off = _lineupAverages(offense.lineup);
    final def = _lineupAverages(defense.lineup);
    return clampBasisPoints(
      1000 +
          (50 - def.basketballIQ) * 5 +
          (off.athleticism - 50) * 4 +
          (off.basketballIQ - 50) * 2,
      min: 300,
      max: 2200,
    );
  }

  /// Shooting-foul probability on a missed attempt (awards no counted FGA).
  int shootingFoulBasisPoints({
    required Player shooter,
    required Player defender,
  }) {
    final a = shooter.attributes;
    final d = defender.attributes;
    return clampBasisPoints(
      800 +
          (a.athleticism - 50) * 4 +
          (a.basketballIQ - 50) * 2 +
          (a.insideScoring - 50) * 2 +
          (50 - d.basketballIQ) * 3,
      min: 200,
      max: 2400,
    );
  }

  /// And-one probability on a made attempt.
  int andOneBasisPoints({required Player shooter, required Player defender}) {
    final a = shooter.attributes;
    final d = defender.attributes;
    return clampBasisPoints(
      160 +
          (a.athleticism - 50) * 3 +
          (a.insideScoring - 50) * 3 -
          (d.interiorDefense - 50) * 2,
      min: 30,
      max: 800,
    );
  }

  /// Probability that a made field goal is assisted.
  int assistBasisPoints(ActiveLineup offense) {
    final team = _lineupAverages(offense);
    return clampBasisPoints(
      5400 + (team.passing - 50) * 12 + (team.basketballIQ - 50) * 8,
      min: 1500,
      max: 9000,
    );
  }

  /// Block probability on a missed, unfouled attempt.
  int blockBasisPoints({
    required Player shooter,
    required Player defender,
    required ShotZone zone,
  }) {
    final a = shooter.attributes;
    final d = defender.attributes;
    final base = zone == ShotZone.three ? 220 : 520;
    return clampBasisPoints(
      base +
          (d.interiorDefense - 50) * 8 +
          (d.athleticism - 50) * 5 -
          (a.insideScoring - 50) * 4 -
          (a.basketballIQ - 50) * 2,
      min: 50,
      max: 2200,
    );
  }

  /// Offensive-rebound share of one live miss. [zone] is null for a missed
  /// final free throw.
  int offensiveReboundBasisPoints({
    required TeamOnCourt offense,
    required TeamOnCourt defense,
    ShotZone? zone,
  }) {
    final off = _lineupAverages(offense.lineup);
    final def = _lineupAverages(defense.lineup);
    final offStrength = off.rebounding * 2 + off.athleticism;
    final defStrength = def.rebounding * 2 + def.athleticism;
    return clampBasisPoints(
      2700 +
          (offStrength - defStrength) * 12 +
          (zone == null ? 0 : _reboundZoneBonus[zone.index]),
      min: 800,
      max: 4500,
    );
  }

  /// Individual free-throw make probability.
  int freeThrowMakeBasisPoints(Player shooter) => clampBasisPoints(
    6000 + (shooter.attributes.freeThrow - 50) * 65,
    min: 1500,
    max: 9800,
  );

  // --- Weights and helpers ------------------------------------------------

  int _ballHandlerScore(Player player) {
    final a = player.attributes;
    return _handlePositionBase[player.position.index] +
        a.ballHandling * 3 +
        a.passing +
        a.basketballIQ;
  }

  int _stealScore(Player player) {
    final a = player.attributes;
    return _stealPositionBonus[player.position.index] +
        a.perimeterDefense * 3 +
        a.athleticism * 2;
  }

  int _assistScore(Player player) {
    final a = player.attributes;
    return _assistPositionBonus[player.position.index] +
        a.passing * 3 +
        a.basketballIQ * 2;
  }

  int _blockScore(Player player) {
    final a = player.attributes;
    return _blockPositionBonus[player.position.index] +
        a.interiorDefense * 3 +
        a.athleticism * 2;
  }

  int _reboundScore(Player player) {
    final a = player.attributes;
    return _reboundPositionBonus[player.position.index] +
        a.rebounding * 3 +
        a.athleticism;
  }

  static int? _lineupIndex(ActiveLineup lineup, PlayerId playerId) {
    for (var i = 0; i < lineup.players.length; i++) {
      if (lineup.players[i].id == playerId) return i;
    }
    return null;
  }

  /// Draws one player using normalized basis-point weights: exactly one
  /// `nextInt(10000)`.
  Player _pickWeighted(
    DeterministicRandom rng,
    ActiveLineup lineup,
    int Function(Player) weightOf, {
    PlayerId? exclude,
  }) {
    final weights = <int>[
      for (final player in lineup.players)
        player.id == exclude ? 0 : max(1, weightOf(player)),
    ];
    return lineup.players[_pickWeightedIndex(rng, weights)];
  }

  static int _pickWeightedIndex(DeterministicRandom rng, List<int> weights) {
    final normalized = _normalize(weights);
    final draw = rng.nextInt(_maxBasisPoints);
    var running = 0;
    for (var i = 0; i < normalized.length; i++) {
      running += normalized[i];
      if (draw < running) return i;
    }
    return normalized.length - 1;
  }

  /// Integer normalization to exactly 10000; the rounding remainder goes to the
  /// last positive slot so an excluded (zero-weight) player can never be picked.
  static List<int> _normalize(List<int> raw) {
    final total = raw.fold(0, (a, b) => a + b);
    if (total <= 0) {
      throw ArgumentError.value(raw, 'weights', 'need a positive weight');
    }
    var lastPositive = raw.length - 1;
    while (lastPositive > 0 && raw[lastPositive] == 0) {
      lastPositive--;
    }
    final normalized = List<int>.filled(raw.length, 0);
    var assigned = 0;
    for (var i = 0; i < raw.length; i++) {
      if (i == lastPositive) {
        normalized[i] = _maxBasisPoints - assigned;
      } else if (raw[i] > 0) {
        final share = raw[i] * _maxBasisPoints ~/ total;
        normalized[i] = share;
        assigned += share;
      }
    }
    return normalized;
  }

  /// Positive min-one largest-remainder allocation to exactly [budget].
  ///
  /// Used for exposure and turnover-actor weights so a positive raw weight can
  /// never be rounded to zero. Ties are broken by canonical index. Public so the
  /// contract (positivity, exact sum, error window) is directly testable.
  static List<int> allocatePositiveWeights(List<int> raw, int budget) {
    if (raw.isEmpty) {
      throw ArgumentError.value(raw, 'weights', 'need at least one weight');
    }
    if (budget < raw.length) {
      throw ArgumentError.value(budget, 'budget', 'budget below player count');
    }
    var total = 0;
    for (final value in raw) {
      if (value < 1) {
        throw ArgumentError.value(raw, 'weights', 'weights must be positive');
      }
      total += value;
    }
    final remBudget = budget - raw.length;
    final extra = <int>[for (final value in raw) value * remBudget ~/ total];
    var assigned = 0;
    for (final value in extra) {
      assigned += value;
    }
    final leftover = remBudget - assigned;
    final remainders = <int>[
      for (var i = 0; i < raw.length; i++)
        raw[i] * remBudget - extra[i] * total,
    ];
    final order = List<int>.generate(raw.length, (index) => index)
      ..sort((a, b) {
        final byRemainder = remainders[b].compareTo(remainders[a]);
        return byRemainder != 0 ? byRemainder : a.compareTo(b);
      });
    for (var i = 0; i < leftover; i++) {
      extra[order[i]] += 1;
    }
    return [for (final value in extra) value + 1];
  }

  static _LineupAverages _lineupAverages(ActiveLineup lineup) {
    var ballHandling = 0;
    var passing = 0;
    var basketballIQ = 0;
    var perimeterDefense = 0;
    var rebounding = 0;
    var athleticism = 0;
    final players = lineup.players;
    for (final player in players) {
      final a = player.attributes;
      ballHandling += a.ballHandling;
      passing += a.passing;
      basketballIQ += a.basketballIQ;
      perimeterDefense += a.perimeterDefense;
      rebounding += a.rebounding;
      athleticism += a.athleticism;
    }
    final n = players.length;
    return _LineupAverages(
      ballHandling: ballHandling ~/ n,
      passing: passing ~/ n,
      basketballIQ: basketballIQ ~/ n,
      perimeterDefense: perimeterDefense ~/ n,
      rebounding: rebounding ~/ n,
      athleticism: athleticism ~/ n,
    );
  }
}

final class _LineupAverages {
  const _LineupAverages({
    required this.ballHandling,
    required this.passing,
    required this.basketballIQ,
    required this.perimeterDefense,
    required this.rebounding,
    required this.athleticism,
  });

  final int ballHandling;
  final int passing;
  final int basketballIQ;
  final int perimeterDefense;
  final int rebounding;
  final int athleticism;
}
