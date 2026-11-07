import '../models/player.dart';
import 'action_intent.dart';
import 'basis_point_weights.dart';

/// M006 shot-preference policy: willingness to shoot from each zone.
///
/// Preference is inferred from existing attributes. It is not a persisted
/// tendency and not shot accuracy: [BasketballProbabilityModel.shotMakeBasisPoints]
/// free throws, fouls, assists and blocks have their own coefficients and are
/// not read or written here. The functions are pure, consume no randomness and
/// mutate nothing.
///
/// The inside and midrange terms are the v6 formulas, unchanged. Only the
/// three-point term uses the approved piecewise ability curve.
abstract final class DerivedShotPreference {
  /// Ability slope below a rating of 50: willingness falls fast.
  static const int belowAverageSlope = 70;

  /// Ability slope at or above a rating of 50: willingness rises slowly.
  static const int aboveAverageSlope = 30;

  /// Shared three-point base weight before ability and bonuses.
  static const int baseThreeWeight = 3600;

  /// Every raw zone weight is floored here before normalisation.
  static const int minimumZoneWeight = 200;

  static const int _pivot = 50;

  // --- Slot and phase bonuses, indexed PG..C and PhaseKind.values. --------

  static const List<int> _slotInsideBonus = [-400, -250, 0, 600, 900];
  static const List<int> _slotMidrangeBonus = [100, 200, 150, 0, -300];
  static const List<int> _slotThreeBonus = [250, 350, 200, -400, -900];
  static const List<int> _phaseInsideBonus = [700, 0, -300];
  static const List<int> _phaseMidrangeBonus = [-300, 0, 100];
  static const List<int> _phaseThreeBonus = [-400, 0, 200];

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
  }) => _bounded(
    baseThreeWeight +
        threePointAbility(shooter.attributes.threePoint) +
        _slotThreeBonus[slotIndex] +
        _phaseThreeBonus[phase.index],
  );

  /// Raw `[inside, midrange, three]` weights before normalisation.
  static List<int> rawZoneWeights({
    required Player shooter,
    required int slotIndex,
    required PhaseKind phase,
  }) {
    final a = shooter.attributes;
    return <int>[
      _bounded(
        2400 +
            (a.insideScoring - 50) * 22 +
            (a.athleticism - 50) * 10 +
            _slotInsideBonus[slotIndex] +
            _phaseInsideBonus[phase.index],
      ),
      _bounded(
        2500 +
            (a.midrange - 50) * 26 +
            _slotMidrangeBonus[slotIndex] +
            _phaseMidrangeBonus[phase.index],
      ),
      threePointWeight(shooter: shooter, slotIndex: slotIndex, phase: phase),
    ];
  }

  /// Normalized zone weights `[inside, midrange, three]` summing to 10000.
  static List<int> zoneWeights({
    required Player shooter,
    required int slotIndex,
    required PhaseKind phase,
  }) => normalizeBasisPointWeights(
    rawZoneWeights(shooter: shooter, slotIndex: slotIndex, phase: phase),
  );

  static int _bounded(int weight) =>
      weight < minimumZoneWeight ? minimumZoneWeight : weight;
}
