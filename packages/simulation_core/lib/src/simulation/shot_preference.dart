import '../models/player.dart';
import 'action_intent.dart';
import 'probability_model.dart';

/// Dormant M006-T03 derived shot-preference policy.
///
/// Replaces the linear three-point willingness term with a piecewise ability
/// curve. Inside and midrange weights come from the v6 raw formula unchanged, so
/// this policy reuses those terms instead of restating them.
///
/// Preference is willingness inferred from attributes, not a persisted tendency
/// and not shot accuracy: [BasketballProbabilityModel.shotMakeBasisPoints],
/// free throws, fouls, assists and blocks are untouched. The functions are pure,
/// consume no randomness, mutate nothing and are called from no production path
/// while T03 remains dormant.
abstract final class DerivedShotPreference {
  /// Ability slope below a rating of 50: willingness falls fast.
  static const int belowAverageSlope = 70;

  /// Ability slope at or above a rating of 50: willingness rises slowly.
  static const int aboveAverageSlope = 30;

  static const int _pivot = 50;

  /// The piecewise ability term for a three-point rating in `0..100`.
  ///
  /// Continuous at the pivot: both branches give 0 when `threePoint == 50`.
  static int threePointAbility(int threePoint) => threePoint < _pivot
      ? belowAverageSlope * (threePoint - _pivot)
      : aboveAverageSlope * (threePoint - _pivot);

  /// Raw three-point weight from the shooter's occupied court slot.
  ///
  /// [slotIndex] is the slot the shooter actually occupies (`PG..C` as `0..4`),
  /// not necessarily his nominal [Player.position].
  static int threePointWeight({
    required Player shooter,
    required int slotIndex,
    required PhaseKind phase,
  }) => BasketballProbabilityModel.rawThreePointWeight(
    abilityBasisPoints: threePointAbility(shooter.attributes.threePoint),
    slotIndex: slotIndex,
    phase: phase,
  );

  /// Raw `[inside, midrange, three]` weights before normalisation.
  static List<int> rawZoneWeights({
    required Player shooter,
    required int slotIndex,
    required PhaseKind phase,
  }) {
    final v6 = BasketballProbabilityModel.rawShotZoneWeights(
      shooter: shooter,
      slotIndex: slotIndex,
      phase: phase,
    );
    return <int>[
      v6[0],
      v6[1],
      threePointWeight(shooter: shooter, slotIndex: slotIndex, phase: phase),
    ];
  }

  /// Normalized zone weights `[inside, midrange, three]` summing to 10000.
  static List<int> zoneWeights({
    required Player shooter,
    required int slotIndex,
    required PhaseKind phase,
  }) => BasketballProbabilityModel.normalizeBasisPointWeights(
    rawZoneWeights(shooter: shooter, slotIndex: slotIndex, phase: phase),
  );
}
