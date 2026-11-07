import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

PlayerAttributes _attributes({
  int inside = 50,
  int mid = 50,
  int three = 50,
  int ath = 50,
  int ft = 70,
  int handling = 50,
  int passing = 50,
  int iq = 50,
  int perim = 50,
  int interior = 50,
  int reb = 50,
}) => PlayerAttributes(
  insideScoring: inside,
  midrange: mid,
  threePoint: three,
  freeThrow: ft,
  passing: passing,
  ballHandling: handling,
  perimeterDefense: perim,
  interiorDefense: interior,
  rebounding: reb,
  athleticism: ath,
  stamina: 70,
  basketballIQ: iq,
);

Player _player(
  String id,
  Position position, {
  int inside = 50,
  int mid = 50,
  int three = 50,
  int ath = 50,
  int ft = 70,
  int handling = 50,
  int passing = 50,
  int iq = 50,
  int perim = 50,
  int interior = 50,
  int reb = 50,
}) => Player(
  id: PlayerId(id),
  firstName: 'Player',
  lastName: id,
  position: position,
  attributes: _attributes(
    inside: inside,
    mid: mid,
    three: three,
    ath: ath,
    ft: ft,
    handling: handling,
    passing: passing,
    iq: iq,
    perim: perim,
    interior: interior,
    reb: reb,
  ),
);

/// One frozen audit archetype: nominal position, attributes and occupied slot.
final class _Archetype {
  const _Archetype(
    this.name,
    this.position,
    this.slotIndex,
    this.inside,
    this.mid,
    this.three,
    this.athleticism,
  );

  final String name;
  final Position position;
  final int slotIndex;
  final int inside;
  final int mid;
  final int three;
  final int athleticism;

  Player get player => _player(
    name,
    position,
    inside: inside,
    mid: mid,
    three: three,
    ath: athleticism,
  );
}

const _weakPg = _Archetype('weak pg', Position.pg, 0, 40, 45, 30, 55);
const _weakSg = _Archetype('weak sg', Position.sg, 1, 45, 50, 35, 60);
const _nonShootingC = _Archetype(
  'non-shooting c',
  Position.c,
  4,
  80,
  35,
  20,
  65,
);
const _highThreeC = _Archetype('high-three c', Position.c, 4, 75, 55, 80, 60);
const _highThreeF = _Archetype('high-three f', Position.pf, 3, 70, 65, 78, 65);
const _medianSf = _Archetype('median sf', Position.sf, 2, 50, 50, 50, 50);

/// v6 reference zone vectors, half-court, pinned from the frozen field audit.
const _v6HalfCourt = <String, List<int>>{
  'weak pg': [1994, 3350, 4656],
  'weak sg': [2182, 3321, 4497],
  'non-shooting c': [4822, 2417, 2761],
  'high-three c': [3762, 2505, 3733],
  'high-three f': [3178, 2888, 3934],
  'median sf': [2372, 3107, 4521],
};

/// Proposed v7 zone vectors, half-court, from the piecewise three-point curve.
const _v7HalfCourt = <String, List<int>>{
  'weak pg': [2266, 3807, 3927],
  'weak sg': [2377, 3617, 4006],
  'non-shooting c': [5843, 2929, 1228],
  'high-three c': [3694, 2459, 3847],
  'high-three f': [3127, 2842, 4031],
  'median sf': [2372, 3107, 4521],
};

const _archetypes = [
  _weakPg,
  _weakSg,
  _nonShootingC,
  _highThreeC,
  _highThreeF,
  _medianSf,
];

int _sum(List<int> values) => values.fold<int>(0, (a, b) => a + b);

/// Fixed five used for the ability/preference separation proofs.
List<Player> _separationRoster() => [
  _player(
    'pg',
    Position.pg,
    inside: 62,
    mid: 64,
    three: 70,
    ath: 66,
    handling: 78,
    passing: 74,
    iq: 72,
    perim: 58,
    interior: 40,
    reb: 42,
    ft: 82,
  ),
  _player(
    'sg',
    Position.sg,
    inside: 58,
    mid: 66,
    three: 72,
    ath: 70,
    handling: 70,
    passing: 66,
    iq: 68,
    perim: 66,
    interior: 44,
    reb: 46,
    ft: 78,
  ),
  _player(
    'sf',
    Position.sf,
    inside: 64,
    mid: 62,
    three: 66,
    ath: 68,
    handling: 62,
    passing: 64,
    iq: 66,
    perim: 62,
    interior: 56,
    reb: 60,
    ft: 74,
  ),
  _player(
    'pf',
    Position.pf,
    inside: 72,
    mid: 56,
    three: 52,
    ath: 66,
    handling: 54,
    passing: 58,
    iq: 62,
    perim: 54,
    interior: 70,
    reb: 74,
    ft: 68,
  ),
  _player(
    'c',
    Position.c,
    inside: 78,
    mid: 48,
    three: 30,
    ath: 62,
    handling: 46,
    passing: 52,
    iq: 60,
    perim: 46,
    interior: 78,
    reb: 82,
    ft: 60,
  ),
];

CourtLineup _separationLineup() {
  final roster = _separationRoster();
  final team = Team(
    id: const TeamId('m006-t03'),
    name: 'M006 T03',
    abbreviation: 'TEE',
    roster: Roster(roster),
  );
  return CourtLineup.create(team: team, slotOrderedPlayers: roster);
}

void main() {
  final model = BasketballProbabilityModel();

  group('v6 production zone weights are unchanged', () {
    for (final archetype in _archetypes) {
      test('${archetype.name} half-court', () {
        expect(
          model.shotZoneWeights(
            shooter: archetype.player,
            phase: PhaseKind.halfCourt,
          ),
          _v6HalfCourt[archetype.name],
        );
      });
    }

    test('production weights equal the normalised v6 raw formula', () {
      for (final archetype in _archetypes) {
        for (final phase in PhaseKind.values) {
          expect(
            model.shotZoneWeights(shooter: archetype.player, phase: phase),
            BasketballProbabilityModel.normalizeBasisPointWeights(
              BasketballProbabilityModel.rawShotZoneWeights(
                shooter: archetype.player,
                slotIndex: archetype.slotIndex,
                phase: phase,
              ),
            ),
            reason: '${archetype.name} $phase',
          );
        }
      }
    });

    test('v6 keeps the linear three-point coefficient of 24', () {
      final shooter = _player('sf70', Position.sf, three: 70);
      expect(
        BasketballProbabilityModel.rawShotZoneWeights(
          shooter: shooter,
          slotIndex: 2,
          phase: PhaseKind.halfCourt,
        )[2],
        3600 + 24 * 20 + 200 + 200,
      );
    });
  });

  group('derived preference half-court vectors', () {
    for (final archetype in _archetypes) {
      test('${archetype.name} normalised to 10000', () {
        final weights = DerivedShotPreference.zoneWeights(
          shooter: archetype.player,
          slotIndex: archetype.slotIndex,
          phase: PhaseKind.halfCourt,
        );
        expect(weights, _v7HalfCourt[archetype.name]);
        expect(_sum(weights), 10000);
      });
    }

    test('accepted thresholds for weak shooters and the median shooter', () {
      List<int> v7(_Archetype archetype) => _v7HalfCourt[archetype.name]!;
      expect(v7(_weakPg)[2], lessThanOrEqualTo(4000));
      expect(v7(_weakSg)[2], lessThanOrEqualTo(4100));
      expect(v7(_nonShootingC)[2], lessThanOrEqualTo(1500));
      expect(v7(_medianSf)[2], _v6HalfCourt[_medianSf.name]![2]);
    });

    test('stretch bigs keep a high three share; no position ban', () {
      expect(_v7HalfCourt[_highThreeC.name]![2], greaterThanOrEqualTo(3600));
      expect(_v7HalfCourt[_highThreeF.name]![2], greaterThanOrEqualTo(3900));
      // A rating of 0 is floored, never banned: a positive three weight remains.
      final zeroThree = _player('zero', Position.c, three: 0);
      for (final phase in PhaseKind.values) {
        expect(
          DerivedShotPreference.threePointWeight(
            shooter: zeroThree,
            slotIndex: 4,
            phase: phase,
          ),
          200,
        );
      }
      expect(
        DerivedShotPreference.zoneWeights(
          shooter: zeroThree,
          slotIndex: 4,
          phase: PhaseKind.halfCourt,
        )[2],
        greaterThan(0),
      );
    });
  });

  group('piecewise ability curve', () {
    test('steep below 50, shallow at or above 50', () {
      expect(DerivedShotPreference.threePointAbility(0), -3500);
      expect(DerivedShotPreference.threePointAbility(1), -3430);
      expect(DerivedShotPreference.threePointAbility(25), -1750);
      expect(DerivedShotPreference.threePointAbility(49), -70);
      expect(DerivedShotPreference.threePointAbility(50), 0);
      expect(DerivedShotPreference.threePointAbility(51), 30);
      expect(DerivedShotPreference.threePointAbility(75), 750);
      expect(DerivedShotPreference.threePointAbility(100), 1500);
    });

    test('boundaries use the documented branch', () {
      expect(DerivedShotPreference.threePointAbility(49), 70 * (49 - 50));
      expect(DerivedShotPreference.threePointAbility(50), 30 * (50 - 50));
      expect(DerivedShotPreference.threePointAbility(51), 30 * (51 - 50));
    });
  });

  group('raw three weights and the 200 floor', () {
    test('maximum valid rating', () {
      expect(
        DerivedShotPreference.threePointWeight(
          shooter: _player('maxC', Position.c, three: 100),
          slotIndex: 4,
          phase: PhaseKind.halfCourt,
        ),
        4400,
      );
      expect(
        DerivedShotPreference.threePointWeight(
          shooter: _player('maxPg', Position.pg, three: 100),
          slotIndex: 0,
          phase: PhaseKind.halfCourt,
        ),
        5550,
      );
    });

    test('floor is applied before normalisation, not clamped later', () {
      final zeroC = _player('zero', Position.c, three: 0);
      // Unterminated value would be 3600 - 3500 - 900 + 200 = -600.
      expect(
        DerivedShotPreference.zoneWeights(
          shooter: zeroC,
          slotIndex: 4,
          phase: PhaseKind.halfCourt,
        ),
        [5454, 4181, 365],
      );
    });

    test('inside and midrange raw terms are the v6 terms verbatim', () {
      for (final archetype in _archetypes) {
        for (final phase in PhaseKind.values) {
          final v6 = BasketballProbabilityModel.rawShotZoneWeights(
            shooter: archetype.player,
            slotIndex: archetype.slotIndex,
            phase: phase,
          );
          final derived = DerivedShotPreference.rawZoneWeights(
            shooter: archetype.player,
            slotIndex: archetype.slotIndex,
            phase: phase,
          );
          expect(derived.sublist(0, 2), v6.sublist(0, 2));
        }
      }
    });
  });

  group('phase handling', () {
    test('weak PG: transition, early, half-court', () {
      List<int> zone(PhaseKind phase) => DerivedShotPreference.zoneWeights(
        shooter: _weakPg.player,
        slotIndex: _weakPg.slotIndex,
        phase: phase,
      );
      expect(zone(PhaseKind.transition), [3748, 3214, 3038]);
      expect(zone(PhaseKind.earlyOffense), [2711, 3659, 3630]);
      expect(zone(PhaseKind.halfCourt), [2266, 3807, 3927]);
    });

    test('non-shooting C: transition, early, half-court', () {
      List<int> zone(PhaseKind phase) => DerivedShotPreference.zoneWeights(
        shooter: _nonShootingC.player,
        slotIndex: _nonShootingC.slotIndex,
        phase: phase,
      );
      expect(zone(PhaseKind.transition), [7377, 2315, 308]);
      expect(zone(PhaseKind.earlyOffense), [6303, 2776, 921]);
      expect(zone(PhaseKind.halfCourt), [5843, 2929, 1228]);
    });

    test('high-three C: transition, early, half-court', () {
      List<int> zone(PhaseKind phase) => DerivedShotPreference.zoneWeights(
        shooter: _highThreeC.player,
        slotIndex: _highThreeC.slotIndex,
        phase: phase,
      );
      expect(zone(PhaseKind.transition), [4706, 2054, 3240]);
      expect(zone(PhaseKind.earlyOffense), [3997, 2358, 3645]);
      expect(zone(PhaseKind.halfCourt), [3694, 2459, 3847]);
    });

    test('phase bonuses still move the three weight', () {
      final shooter = _medianSf.player;
      int raw(PhaseKind phase) => DerivedShotPreference.rawZoneWeights(
        shooter: shooter,
        slotIndex: 2,
        phase: phase,
      )[2];
      expect(raw(PhaseKind.transition), 3400);
      expect(raw(PhaseKind.earlyOffense), 3800);
      expect(raw(PhaseKind.halfCourt), 4000);
    });
  });

  group('occupied slot versus nominal position', () {
    final shooter = _player('combo', Position.pg, three: 70);
    final lineup = CourtLineup.create(
      team: Team(
        id: const TeamId('m006-t03-slot'),
        name: 'M006 T03 slot',
        abbreviation: 'SLT',
        roster: Roster(_separationRoster()),
      ),
      slotOrderedPlayers: _separationRoster(),
    );

    test('the occupied slot selects the bonus', () {
      final atPointGuard = DerivedShotPreference.threePointWeight(
        shooter: shooter,
        slotIndex: 0,
        phase: PhaseKind.halfCourt,
      );
      final atPowerForward = DerivedShotPreference.threePointWeight(
        shooter: shooter,
        slotIndex: 3,
        phase: PhaseKind.halfCourt,
      );
      expect(atPointGuard, 4650);
      expect(atPowerForward, 4000);
      expect(atPointGuard - atPowerForward, 650);
    });

    test('nominal position weights ignore the occupied slot', () {
      expect(
        model.shotZoneWeights(shooter: shooter, phase: PhaseKind.halfCourt),
        [1903, 3023, 5074],
      );
      expect(
        DerivedShotPreference.zoneWeights(
          shooter: shooter,
          slotIndex: 3,
          phase: PhaseKind.halfCourt,
        ),
        isNot(
          model.shotZoneWeights(shooter: shooter, phase: PhaseKind.halfCourt),
        ),
      );
    });

    test('slot changes zone preference but never make probability', () {
      final defender = lineup.playerAtSlotIndex(1);
      final makeBefore = model.shotMakeBasisPoints(
        shooter: lineup.playerAtSlotIndex(0),
        defender: defender,
        zone: ShotZone.three,
        offense: lineup,
      );
      DerivedShotPreference.zoneWeights(
        shooter: shooter,
        slotIndex: 3,
        phase: PhaseKind.halfCourt,
      );
      expect(
        model.shotMakeBasisPoints(
          shooter: lineup.playerAtSlotIndex(0),
          defender: defender,
          zone: ShotZone.three,
          offense: lineup,
        ),
        makeBefore,
      );
    });
  });

  group('ability / preference separation', () {
    final lineup = _separationLineup();
    final shooter = lineup.playerAtSlotIndex(0);
    final defender = lineup.playerAtSlotIndex(1);

    test('conversion and non-shot coefficients are the v6 references', () {
      expect(
        model.shotMakeBasisPoints(
          shooter: shooter,
          defender: defender,
          zone: ShotZone.three,
          offense: lineup,
        ),
        3844,
      );
      expect(
        model.shotMakeBasisPoints(
          shooter: shooter,
          defender: defender,
          zone: ShotZone.midrange,
          offense: lineup,
        ),
        4304,
      );
      expect(
        model.shotMakeBasisPoints(
          shooter: shooter,
          defender: defender,
          zone: ShotZone.inside,
          offense: lineup,
        ),
        6280,
      );
      expect(model.freeThrowMakeBasisPoints(shooter), 8080);
      expect(model.assistBasisPoints(lineup), 5664);
      expect(
        model.blockBasisPoints(
          shooter: shooter,
          defender: defender,
          zone: ShotZone.three,
        ),
        180,
      );
      expect(
        model.andOneBasisPoints(shooter: shooter, defender: defender),
        256,
      );
      expect(
        model.shootingFoulBasisPoints(shooter: shooter, defender: defender),
        878,
      );
    });

    test('preference calls leave every coefficient identical', () {
      final makeBefore = model.shotMakeBasisPoints(
        shooter: shooter,
        defender: defender,
        zone: ShotZone.three,
        offense: lineup,
      );
      DerivedShotPreference.zoneWeights(
        shooter: shooter,
        slotIndex: 0,
        phase: PhaseKind.halfCourt,
      );
      DerivedShotPreference.rawZoneWeights(
        shooter: shooter,
        slotIndex: 3,
        phase: PhaseKind.transition,
      );
      expect(
        model.shotMakeBasisPoints(
          shooter: shooter,
          defender: defender,
          zone: ShotZone.three,
          offense: lineup,
        ),
        makeBefore,
      );
      expect(model.freeThrowMakeBasisPoints(shooter), 8080);
      expect(model.assistBasisPoints(lineup), 5664);
      expect(
        model.andOneBasisPoints(shooter: shooter, defender: defender),
        256,
      );
    });

    test('a preference change moves zone selection, not accuracy', () {
      final cold = _player('cold', Position.sf, three: 25);
      final hot = _player('hot', Position.sf, three: 95);
      expect(
        DerivedShotPreference.zoneWeights(
          shooter: cold,
          slotIndex: 2,
          phase: PhaseKind.halfCourt,
        )[2],
        lessThan(
          DerivedShotPreference.zoneWeights(
            shooter: hot,
            slotIndex: 2,
            phase: PhaseKind.halfCourt,
          )[2],
        ),
      );
      // Accuracy differs only because the rating differs; the policy itself has
      // no path into shotMakeBasisPoints, proven by the coefficient pins above.
    });
  });

  group('determinism', () {
    test('no draws are consumed and repeated calls agree', () {
      final rng = DeterministicRandom(20261107);
      final drawsBefore = rng.drawCount;
      final shooter = _weakSg.player;

      final first = DerivedShotPreference.zoneWeights(
        shooter: shooter,
        slotIndex: _weakSg.slotIndex,
        phase: PhaseKind.halfCourt,
      );
      final second = DerivedShotPreference.zoneWeights(
        shooter: shooter,
        slotIndex: _weakSg.slotIndex,
        phase: PhaseKind.halfCourt,
      );
      DerivedShotPreference.threePointAbility(37);
      DerivedShotPreference.threePointWeight(
        shooter: shooter,
        slotIndex: 0,
        phase: PhaseKind.transition,
      );

      expect(second, first);
      expect(rng.drawCount, drawsBefore);
    });

    test(
      'normalized weights equal the model normalisation of the raw vector',
      () {
        for (final archetype in _archetypes) {
          for (final phase in PhaseKind.values) {
            expect(
              DerivedShotPreference.zoneWeights(
                shooter: archetype.player,
                slotIndex: archetype.slotIndex,
                phase: phase,
              ),
              BasketballProbabilityModel.normalizeBasisPointWeights(
                DerivedShotPreference.rawZoneWeights(
                  shooter: archetype.player,
                  slotIndex: archetype.slotIndex,
                  phase: phase,
                ),
              ),
            );
          }
        }
      },
    );
  });
}
