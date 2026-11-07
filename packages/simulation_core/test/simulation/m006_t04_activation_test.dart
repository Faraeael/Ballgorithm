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
    handling: handling,
    passing: passing,
    iq: iq,
    perim: perim,
    interior: interior,
    reb: reb,
  ),
);

/// Weak point guard: low ratings everywhere, low creation score.
final _weakPg = _player(
  'weak-pg',
  Position.pg,
  inside: 40,
  mid: 45,
  three: 30,
  ath: 55,
  handling: 42,
  passing: 45,
  iq: 44,
);

/// Elite creator wing: high creation score and high shooting.
final _creatorWing = _player(
  'creator-wing',
  Position.sf,
  inside: 70,
  mid: 65,
  three: 78,
  ath: 65,
  handling: 82,
  passing: 80,
  iq: 78,
);

/// Neutral-ranked elite scorer: high shooting, average creation.
final _eliteScorer = _player(
  'elite-scorer',
  Position.pf,
  inside: 72,
  mid: 68,
  three: 76,
  ath: 68,
  handling: 48,
  passing: 46,
  iq: 52,
);

final _roleFiller = _player(
  'filler',
  Position.sg,
  inside: 50,
  mid: 50,
  three: 50,
  ath: 50,
  handling: 50,
  passing: 50,
  iq: 50,
);

final _stretchCenter = _player(
  'stretch-center',
  Position.c,
  inside: 75,
  mid: 55,
  three: 80,
  ath: 60,
  handling: 55,
  passing: 60,
  iq: 62,
);

final _nonShootingCenter = _player(
  'non-shooting-center',
  Position.c,
  inside: 80,
  mid: 35,
  three: 20,
  ath: 65,
  handling: 44,
  passing: 48,
  iq: 55,
);

final _medianShooter = _player('median', Position.sf);

CourtLineup _lineupOf(List<Player> ordered) {
  final team = Team(
    id: const TeamId('m006-t04'),
    name: 'M006 T04',
    abbreviation: 'TEE',
    roster: Roster(ordered),
  );
  return CourtLineup.create(team: team, slotOrderedPlayers: ordered);
}

int _sum(List<int> values) => values.fold<int>(0, (a, b) => a + b);

void main() {
  final model = BasketballProbabilityModel();

  group('role-aware shooter selection', () {
    test('the creator wing is primary and its usage weight is lifted', () {
      final lineup = _lineupOf([
        _weakPg,
        _roleFiller,
        _creatorWing,
        _eliteScorer,
        _nonShootingCenter,
      ]);
      final roles = OffensiveRoleRanking.derive(lineup);
      expect(roles.primary, _creatorWing.id);
      // The elite scorer is creation-neutral here: role rank is not shooting.
      expect(roles.roleOf(_eliteScorer.id), OffensiveRole.neutral);

      final raw = model.rawShotUsageWeights(lineup);
      final produced = model.shotUsageWeights(lineup);
      final creatorIndex = lineup.slotIndexForPlayer(_creatorWing.id);
      final weakPgIndex = lineup.slotIndexForPlayer(_weakPg.id);

      expect(_sum(produced), 10000);
      // The multiplier lifts the creator above his raw share.
      expect(
        produced[creatorIndex] / 10000,
        greaterThan(raw[creatorIndex] / _sum(raw)),
      );
      // The weak guard is neutral: his share is diluted, never suppressed.
      final rawTotal = _sum(raw);
      expect(produced[weakPgIndex], greaterThan(0));
      expect(
        produced[weakPgIndex] / 10000,
        lessThanOrEqualTo(raw[weakPgIndex] / rawTotal),
      );
    });

    test('a creator center takes the primary multiplier', () {
      final creatorCenter = _player(
        'creator-center',
        Position.c,
        inside: 72,
        mid: 60,
        three: 55,
        ath: 66,
        handling: 80,
        passing: 78,
        iq: 76,
      );
      final lineup = _lineupOf([
        _weakPg,
        _roleFiller,
        _player('sf', Position.sf),
        _player('pf', Position.pf),
        creatorCenter,
      ]);
      final roles = OffensiveRoleRanking.derive(lineup);
      expect(roles.primary, creatorCenter.id);
      expect(
        roles.roleOf(_weakPg.id),
        anyOf(OffensiveRole.secondary, OffensiveRole.neutral),
      );
      final produced = model.shotUsageWeights(lineup);
      expect(produced[4], greaterThan(produced[0]));
    });

    test('a neutral elite scorer keeps his raw weight, share dilutes', () {
      final lineup = _lineupOf([
        _weakPg,
        _roleFiller,
        _creatorWing,
        _eliteScorer,
        _nonShootingCenter,
      ]);
      final roles = OffensiveRoleRanking.derive(lineup);
      expect(roles.roleOf(_eliteScorer.id), OffensiveRole.neutral);
      final raw = model.rawShotUsageWeights(lineup);
      final produced = model.shotUsageWeights(lineup);
      final scorerIndex = lineup.slotIndexForPlayer(_eliteScorer.id);
      expect(
        raw[scorerIndex],
        greaterThan(raw[lineup.slotIndexForPlayer(_weakPg.id)]),
      );
      expect(produced[scorerIndex], greaterThan(0));
      // No multiplier below 1.0: a neutral scorer is only diluted by others.
      expect(
        OffensiveOpportunity.multiplierFor(roles.roleOf(_eliteScorer.id)),
        greaterThanOrEqualTo(OffensiveOpportunity.neutralBasisPoints),
      );
    });

    test('substitution moves the primary multiplier to the new five', () {
      final benchCreator = _player(
        'bench-creator',
        Position.pg,
        handling: 88,
        passing: 86,
        iq: 84,
      );
      final team = Team(
        id: const TeamId('m006-t04-subs'),
        name: 'M006 T04 subs',
        abbreviation: 'SUB',
        roster: Roster([
          _weakPg,
          _roleFiller,
          _creatorWing,
          _eliteScorer,
          _nonShootingCenter,
          benchCreator,
        ]),
      );
      final before = CourtLineup.create(
        team: team,
        slotOrderedPlayers: [
          _weakPg,
          _roleFiller,
          _creatorWing,
          _eliteScorer,
          _nonShootingCenter,
        ],
      );
      final after = CourtLineup.create(
        team: team,
        slotOrderedPlayers: [
          benchCreator,
          _roleFiller,
          _creatorWing,
          _eliteScorer,
          _nonShootingCenter,
        ],
      );
      expect(OffensiveRoleRanking.derive(before).primary, _creatorWing.id);
      expect(OffensiveRoleRanking.derive(after).primary, benchCreator.id);
      final beforeWeights = model.shotUsageWeights(before);
      final afterWeights = model.shotUsageWeights(after);
      expect(afterWeights[0], greaterThan(beforeWeights[0]));
      expect(afterWeights[0], greaterThan(afterWeights[2]));
      expect(_sum(afterWeights), 10000);
    });
  });

  group('activated zone preference', () {
    test('non-shooting center, stretch center, forward and median shooter', () {
      expect(
        model.shotZoneWeights(
          shooter: _nonShootingCenter,
          phase: PhaseKind.halfCourt,
        ),
        [5843, 2929, 1228],
      );
      expect(
        model.shotZoneWeights(
          shooter: _stretchCenter,
          phase: PhaseKind.halfCourt,
        ),
        [3694, 2459, 3847],
      );
      expect(
        model.shotZoneWeights(
          shooter: _eliteScorer,
          phase: PhaseKind.halfCourt,
        ),
        [3169, 2891, 3940],
      );
      expect(
        model.shotZoneWeights(
          shooter: _medianShooter,
          phase: PhaseKind.halfCourt,
        ),
        [2372, 3107, 4521],
      );
    });
  });

  group('production draw path uses the activated policies', () {
    final offense = TeamOnCourt(
      teamId: const TeamId('m006-t04'),
      lineup: _lineupOf([
        _weakPg,
        _roleFiller,
        _creatorWing,
        _eliteScorer,
        _nonShootingCenter,
      ]),
    );
    final defenseLineup = _lineupOf([
      _player('d-pg', Position.pg),
      _player('d-sg', Position.sg),
      _player('d-sf', Position.sf),
      _player('d-pf', Position.pf),
      _player('d-c', Position.c),
    ]);
    final defense = TeamOnCourt(
      teamId: const TeamId('m006-t04-defense'),
      lineup: defenseLineup,
    );

    test('final-tick shooter and zone follow the activated weights', () {
      const seed = 20261107;
      // Replicate the two draws the final-tick path consumes: actor, then zone.
      final oracle = DeterministicRandom(seed);
      final actorDraw = oracle.nextInt(10000);
      final zoneDraw = oracle.nextInt(10000);

      final action = model.selectFinalTickAction(
        offense: offense,
        defense: defense,
        rng: DeterministicRandom(seed),
      );

      final usage = model.shotUsageWeights(offense.lineup);
      var cumulative = 0;
      var expectedShooter = offense.lineup.slots.last.playerId;
      for (var index = 0; index < usage.length; index++) {
        cumulative += usage[index];
        if (actorDraw < cumulative) {
          expectedShooter = offense.lineup.slots[index].playerId;
          break;
        }
      }
      expect(action.shooterId, expectedShooter);

      final slotIndex = offense.lineup.slotIndexForPlayer(action.shooterId);
      final zones = DerivedShotPreference.zoneWeights(
        shooter: offense.lineup.players[slotIndex],
        slotIndex: slotIndex,
        phase: PhaseKind.halfCourt,
      );
      final expectedZone = zoneDraw < zones[0]
          ? ShotZone.inside
          : zoneDraw < zones[0] + zones[1]
          ? ShotZone.midrange
          : ShotZone.three;
      expect(action.zone, expectedZone);
    });

    test('shot success coefficients are unchanged by the activation', () {
      final shooter = offense.lineup.playerAtSlotIndex(0);
      final defender = defenseLineup.playerAtSlotIndex(0);
      expect(
        model.shotMakeBasisPoints(
          shooter: shooter,
          defender: defender,
          zone: ShotZone.three,
          offense: offense.lineup,
        ),
        isA<int>(),
      );
      // Zone preference moves; conversion still uses the v6 coefficient set.
      final before = model.shotMakeBasisPoints(
        shooter: shooter,
        defender: defender,
        zone: ShotZone.midrange,
        offense: offense.lineup,
      );
      model.shotZoneWeights(shooter: shooter, phase: PhaseKind.transition);
      expect(
        model.shotMakeBasisPoints(
          shooter: shooter,
          defender: defender,
          zone: ShotZone.midrange,
          offense: offense.lineup,
        ),
        before,
      );
    });
  });
}
