import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

PlayerAttributes attributes({
  int handling = 50,
  int passing = 50,
  int iq = 50,
  int inside = 50,
  int mid = 50,
  int three = 50,
  int ath = 50,
}) => PlayerAttributes(
  insideScoring: inside,
  midrange: mid,
  threePoint: three,
  freeThrow: 70,
  passing: passing,
  ballHandling: handling,
  perimeterDefense: 50,
  interiorDefense: 50,
  rebounding: 50,
  athleticism: ath,
  stamina: 70,
  basketballIQ: iq,
);

Player player(
  String id,
  Position position, {
  int handling = 50,
  int passing = 50,
  int iq = 50,
  int inside = 50,
  int mid = 50,
  int three = 50,
  int ath = 50,
}) => Player(
  id: PlayerId(id),
  firstName: 'Player',
  lastName: id,
  position: position,
  attributes: attributes(
    handling: handling,
    passing: passing,
    iq: iq,
    inside: inside,
    mid: mid,
    three: three,
    ath: ath,
  ),
);

Team teamOf(List<Player> players) => Team(
  id: const TeamId('m006-opportunity'),
  name: 'M006 Opportunity',
  abbreviation: 'OPP',
  roster: Roster(players),
);

CourtLineup lineupOf(Team team, List<Player> ordered) =>
    CourtLineup.create(team: team, slotOrderedPlayers: ordered);

List<Player> five({
  int pgHandling = 60,
  int pgPassing = 60,
  int pgIq = 60,
  int sgHandling = 55,
  int sgPassing = 55,
  int sgIq = 55,
  int sfHandling = 50,
  int sfPassing = 50,
  int sfIq = 50,
  int pfHandling = 45,
  int pfPassing = 45,
  int pfIq = 45,
  int cHandling = 40,
  int cPassing = 40,
  int cIq = 40,
}) => [
  player('pg', Position.pg, handling: pgHandling, passing: pgPassing, iq: pgIq),
  player('sg', Position.sg, handling: sgHandling, passing: sgPassing, iq: sgIq),
  player('sf', Position.sf, handling: sfHandling, passing: sfPassing, iq: sfIq),
  player('pf', Position.pf, handling: pfHandling, passing: pfPassing, iq: pfIq),
  player('c', Position.c, handling: cHandling, passing: cPassing, iq: cIq),
];

void main() {
  test('multiplier constants are exact basis points', () {
    expect(OffensiveOpportunity.primaryBasisPoints, 13500);
    expect(OffensiveOpportunity.secondaryBasisPoints, 11500);
    expect(OffensiveOpportunity.neutralBasisPoints, 10000);
    expect(OffensiveOpportunity.multiplierFor(OffensiveRole.primary), 13500);
    expect(OffensiveOpportunity.multiplierFor(OffensiveRole.secondary), 11500);
    expect(OffensiveOpportunity.multiplierFor(OffensiveRole.neutral), 10000);
  });

  test('equal raw weights produce the exact multiplier vector', () {
    final players = five();
    final team = teamOf(players);
    final lineup = lineupOf(team, players);
    final roles = OffensiveRoleRanking.derive(lineup);
    expect(roles.roleOf(const PlayerId('pg')), OffensiveRole.primary);
    expect(roles.roleOf(const PlayerId('sg')), OffensiveRole.secondary);

    final result = OffensiveOpportunity.applyRoleMultipliers(
      rawUsageWeights: const [100, 100, 100, 100, 100],
      activeLineup: lineup,
      roles: roles,
    );
    // 1.35/1.15/1.00/1.00/1.00 of 100 each, normalised once to 10000.
    expect(result, [2454, 2090, 1818, 1818, 1820]);
    expect(result.fold<int>(0, (a, b) => a + b), 10000);
  });

  test('adjusted usage returns canonical slot order and sums to 10000', () {
    final players = five();
    final team = teamOf(players);
    final lineup = lineupOf(team, players);
    final roles = OffensiveRoleRanking.derive(lineup);
    final result = OffensiveOpportunity.adjustedUsageWeights(
      activeLineup: lineup,
      roles: roles,
    );
    expect(result, hasLength(5));
    expect(result.fold<int>(0, (a, b) => a + b), 10000);
    final raw = BasketballProbabilityModel().rawShotUsageWeights(lineup);
    expect(
      result,
      OffensiveOpportunity.applyRoleMultipliers(
        rawUsageWeights: raw,
        activeLineup: lineup,
        roles: roles,
      ),
    );
  });

  test('a primary creator outside the first slot is lifted in place', () {
    final players = five(
      pgHandling: 40,
      pgPassing: 40,
      pgIq: 40,
      sfHandling: 80,
      sfPassing: 80,
      sfIq: 80,
    );
    final team = teamOf(players);
    final lineup = lineupOf(team, players);
    final roles = OffensiveRoleRanking.derive(lineup);
    expect(roles.primary, const PlayerId('sf'));
    final result = OffensiveOpportunity.applyRoleMultipliers(
      rawUsageWeights: const [100, 100, 100, 100, 100],
      activeLineup: lineup,
      roles: roles,
    );
    expect(result[2], 2454); // SF slot 2, primary
    expect(result[0], 1818); // PG slot 0, neutral
    expect(result.fold<int>(0, (a, b) => a + b), 10000);
  });

  test('results are independent of roster insertion order', () {
    final players = five();
    final shuffled = [
      players[3],
      players[0],
      players[4],
      players[2],
      players[1],
    ];
    final first = OffensiveOpportunity.adjustedUsageWeights(
      activeLineup: lineupOf(teamOf(players), players),
      roles: OffensiveRoleRanking.derive(lineupOf(teamOf(players), players)),
    );
    final second = OffensiveOpportunity.adjustedUsageWeights(
      activeLineup: lineupOf(teamOf(shuffled), players),
      roles: OffensiveRoleRanking.derive(lineupOf(teamOf(shuffled), players)),
    );
    expect(second, first);
  });

  test('inputs and role assignments are not mutated', () {
    final players = five();
    final team = teamOf(players);
    final lineup = lineupOf(team, players);
    final roles = OffensiveRoleRanking.derive(lineup);
    final rankingBefore = List<PlayerId>.of(roles.ranking);
    final raw = [90, 80, 70, 60, 50];
    final rawBefore = List<int>.of(raw);

    OffensiveOpportunity.applyRoleMultipliers(
      rawUsageWeights: raw,
      activeLineup: lineup,
      roles: roles,
    );

    expect(raw, rawBefore);
    expect(roles.ranking, rankingBefore);
    expect(lineup.playerIds, team.players.take(5).map((p) => p.id.value));
  });

  test('no random draws are consumed', () {
    final players = five();
    final team = teamOf(players);
    final lineup = lineupOf(team, players);
    final roles = OffensiveRoleRanking.derive(lineup);
    final rng = DeterministicRandom(20261028);
    final before = rng.drawCount;
    OffensiveOpportunity.adjustedUsageWeights(
      activeLineup: lineup,
      roles: roles,
    );
    expect(rng.drawCount, before);
  });

  test('a neutral elite shooter is never given a suppressive multiplier', () {
    final players = [
      player('creator', Position.pg, handling: 90, passing: 90, iq: 90),
      player('sg', Position.sg, handling: 55, passing: 55, iq: 55),
      player(
        'scorer',
        Position.sf,
        handling: 50,
        passing: 50,
        iq: 60,
        three: 95,
        mid: 85,
        inside: 70,
      ),
      player('pf', Position.pf, handling: 45, passing: 45, iq: 45),
      player('c', Position.c, handling: 40, passing: 40, iq: 40),
    ];
    final team = teamOf(players);
    final lineup = lineupOf(team, players);
    final roles = OffensiveRoleRanking.derive(lineup);
    expect(roles.primary, const PlayerId('creator'));
    final role = roles.roleOf(const PlayerId('scorer'));
    expect(role, isNot(OffensiveRole.primary));
    expect(
      OffensiveOpportunity.multiplierFor(role),
      greaterThanOrEqualTo(10000),
    );
  });

  test('a mismatched role assignment fails explicitly', () {
    final players = five();
    final replacement = player(
      'other',
      Position.pg,
      handling: 60,
      passing: 60,
      iq: 60,
    );
    final team = teamOf([...players, replacement]);
    final lineupA = lineupOf(team, players);
    final rolesA = OffensiveRoleRanking.derive(lineupA);
    final lineupB = lineupOf(team, [replacement, ...players.skip(1)]);

    expect(
      () => OffensiveOpportunity.adjustedUsageWeights(
        activeLineup: lineupB,
        roles: rolesA,
      ),
      throwsA(
        isA<GameValidationException>().having(
          (e) => e.codes,
          'codes',
          contains(GameValidationCode.roleAssignmentMismatch),
        ),
      ),
    );
  });

  test('raw vector length must match the active five', () {
    final players = five();
    final team = teamOf(players);
    final lineup = lineupOf(team, players);
    final roles = OffensiveRoleRanking.derive(lineup);
    expect(
      () => OffensiveOpportunity.applyRoleMultipliers(
        rawUsageWeights: const [100, 100, 100],
        activeLineup: lineup,
        roles: roles,
      ),
      throwsA(
        isA<GameValidationException>().having(
          (e) => e.codes,
          'codes',
          contains(GameValidationCode.roleAssignmentMismatch),
        ),
      ),
    );
  });

  test('substitution recalculates opportunity for the new five', () {
    final creator = player(
      'creator',
      Position.pg,
      handling: 90,
      passing: 90,
      iq: 90,
    );
    final bench = player(
      'bench',
      Position.pg,
      handling: 40,
      passing: 40,
      iq: 40,
    );
    final others = [
      player('sg', Position.sg, handling: 50, passing: 50, iq: 50),
      player('sf', Position.sf, handling: 50, passing: 50, iq: 50),
      player('pf', Position.pf, handling: 50, passing: 50, iq: 50),
      player('c', Position.c, handling: 50, passing: 50, iq: 50),
    ];
    final team = teamOf([creator, ...others, bench]);
    final beforeLineup = lineupOf(team, [creator, ...others]);
    final afterLineup = lineupOf(team, [bench, ...others]);
    final before = OffensiveOpportunity.adjustedUsageWeights(
      activeLineup: beforeLineup,
      roles: OffensiveRoleRanking.derive(beforeLineup),
    );
    final after = OffensiveOpportunity.adjustedUsageWeights(
      activeLineup: afterLineup,
      roles: OffensiveRoleRanking.derive(afterLineup),
    );
    expect(after.fold<int>(0, (a, b) => a + b), 10000);
    // SG (slot 1) becomes primary after the creator leaves; its share rises.
    expect(after[1], greaterThan(before[1]));
  });

  test('opportunity weights never alter zone make probability', () {
    final model = BasketballProbabilityModel();
    final players = five();
    final team = teamOf(players);
    final lineup = lineupOf(team, players);
    final shooter = lineup.playerAtSlotIndex(0);
    final defender = lineup.playerAtSlotIndex(1);
    final before = model.shotMakeBasisPoints(
      shooter: shooter,
      defender: defender,
      zone: ShotZone.three,
      offense: lineup,
    );
    OffensiveOpportunity.adjustedUsageWeights(
      activeLineup: lineup,
      roles: OffensiveRoleRanking.derive(lineup),
    );
    final after = model.shotMakeBasisPoints(
      shooter: shooter,
      defender: defender,
      zone: ShotZone.three,
      offense: lineup,
    );
    expect(after, before);
  });

  test('production v6 usage weights equal the normalised raw vector', () {
    final model = BasketballProbabilityModel();
    final players = five();
    final team = teamOf(players);
    final lineup = lineupOf(team, players);
    expect(
      model.shotUsageWeights(lineup),
      BasketballProbabilityModel.normalizeBasisPointWeights(
        model.rawShotUsageWeights(lineup),
      ),
    );
    expect(model.shotUsageWeights(lineup).fold<int>(0, (a, b) => a + b), 10000);
  });
}
