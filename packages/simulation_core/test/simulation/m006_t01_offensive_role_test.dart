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
  id: const TeamId('m006-role'),
  name: 'M006 Role',
  abbreviation: 'ROL',
  roster: Roster(players),
);

CourtLineup lineupOf(Team team, List<Player> slotOrdered) =>
    CourtLineup.create(team: team, slotOrderedPlayers: slotOrdered);

const positions = [
  Position.pg,
  Position.sg,
  Position.sf,
  Position.pf,
  Position.c,
];

void main() {
  test('creation score is 3*ballHandling + passing + basketballIQ', () {
    final p = player('a', Position.pg, handling: 72, passing: 68, iq: 62);
    expect(OffensiveRoleRanking.creationScore(p), 3 * 72 + 68 + 62);
    expect(OffensiveRoleRanking.creationScore(p), 346);
  });

  test('primary, secondary and neutral ranks come from descending score', () {
    final players = [
      player('pg', Position.pg, handling: 60, passing: 60, iq: 60), // 300
      player('sg', Position.sg, handling: 55, passing: 55, iq: 55), // 275
      player('sf', Position.sf, handling: 50, passing: 50, iq: 50), // 250
      player('pf', Position.pf, handling: 45, passing: 45, iq: 45), // 225
      player('c', Position.c, handling: 40, passing: 40, iq: 40), // 200
    ];
    final team = teamOf(players);
    final assignment = OffensiveRoleRanking.derive(lineupOf(team, players));

    expect(assignment.ranking, [
      const PlayerId('pg'),
      const PlayerId('sg'),
      const PlayerId('sf'),
      const PlayerId('pf'),
      const PlayerId('c'),
    ]);
    expect(assignment.primary, const PlayerId('pg'));
    expect(assignment.secondary, const PlayerId('sg'));
    expect(assignment.roleOf(const PlayerId('pg')), OffensiveRole.primary);
    expect(assignment.roleOf(const PlayerId('sg')), OffensiveRole.secondary);
    for (final id in ['sf', 'pf', 'c']) {
      expect(assignment.roleOf(PlayerId(id)), OffensiveRole.neutral);
    }
    expect(assignment.scoreFor(const PlayerId('pg')), 300);
  });

  test('ties break on canonical court-slot order', () {
    final players = [
      player('pg', Position.pg, handling: 60, passing: 60, iq: 60), // 300
      player('sg', Position.sg, handling: 60, passing: 60, iq: 60), // 300
      player('sf', Position.sf, handling: 50, passing: 50, iq: 50),
      player('pf', Position.pf, handling: 45, passing: 45, iq: 45),
      player('c', Position.c, handling: 40, passing: 40, iq: 40),
    ];
    final team = teamOf(players);
    final assignment = OffensiveRoleRanking.derive(lineupOf(team, players));
    expect(assignment.primary, const PlayerId('pg'));
    expect(assignment.secondary, const PlayerId('sg'));
  });

  test('ranking has no position bonus', () {
    // The centre has the strongest creation score but occupies the C slot.
    final players = [
      player('pg', Position.pg, handling: 50, passing: 50, iq: 50),
      player('sg', Position.sg, handling: 50, passing: 50, iq: 50),
      player('sf', Position.sf, handling: 50, passing: 50, iq: 50),
      player('pf', Position.pf, handling: 50, passing: 50, iq: 50),
      player('c', Position.c, handling: 80, passing: 80, iq: 80), // 400
    ];
    final team = teamOf(players);
    final assignment = OffensiveRoleRanking.derive(lineupOf(team, players));
    expect(assignment.primary, const PlayerId('c'));
    expect(assignment.scoreFor(const PlayerId('c')), 400);

    // Same attributes, same player at PG: identical ranking result.
    final swapped = [
      players[4],
      player('sg', Position.sg, handling: 50, passing: 50, iq: 50),
      player('sf', Position.sf, handling: 50, passing: 50, iq: 50),
      player('pf', Position.pf, handling: 50, passing: 50, iq: 50),
      player('pg2', Position.pg, handling: 50, passing: 50, iq: 50),
    ];
    final swappedTeam = teamOf(swapped);
    final swappedAssignment = OffensiveRoleRanking.derive(
      lineupOf(swappedTeam, swapped),
    );
    expect(swappedAssignment.primary, const PlayerId('c'));
  });

  test('repeated calls are deterministic and consume no randomness', () {
    final players = [
      player('pg', Position.pg, handling: 70, passing: 65, iq: 60),
      player('sg', Position.sg, handling: 60, passing: 55, iq: 55),
      player('sf', Position.sf, handling: 55, passing: 50, iq: 50),
      player('pf', Position.pf, handling: 50, passing: 45, iq: 45),
      player('c', Position.c, handling: 45, passing: 40, iq: 40),
    ];
    final team = teamOf(players);
    final lineup = lineupOf(team, players);
    final rng = DeterministicRandom(20261028);
    final drawsBefore = rng.drawCount;

    final first = OffensiveRoleRanking.derive(lineup);
    final second = OffensiveRoleRanking.derive(lineup);

    expect(second.ranking, first.ranking);
    for (final id in first.ranking) {
      expect(second.scoreFor(id), first.scoreFor(id));
      expect(second.roleOf(id), first.roleOf(id));
    }
    expect(rng.drawCount, drawsBefore);
  });

  test('ranking is independent of roster insertion order', () {
    final players = [
      player('pg', Position.pg, handling: 60, passing: 60, iq: 60),
      player('sg', Position.sg, handling: 55, passing: 55, iq: 55),
      player('sf', Position.sf, handling: 50, passing: 50, iq: 50),
      player('pf', Position.pf, handling: 45, passing: 45, iq: 45),
      player('c', Position.c, handling: 40, passing: 40, iq: 40),
    ];
    final shuffled = [
      players[3],
      players[0],
      players[4],
      players[2],
      players[1],
    ];
    final first = OffensiveRoleRanking.derive(
      lineupOf(teamOf(players), players),
    );
    final second = OffensiveRoleRanking.derive(
      lineupOf(teamOf(shuffled), players),
    );
    expect(second.ranking, first.ranking);
  });

  test('ranking results are immutable', () {
    final players = [
      player('pg', Position.pg, handling: 60, passing: 60, iq: 60),
      player('sg', Position.sg, handling: 55, passing: 55, iq: 55),
      player('sf', Position.sf, handling: 50, passing: 50, iq: 50),
      player('pf', Position.pf, handling: 45, passing: 45, iq: 45),
      player('c', Position.c, handling: 40, passing: 40, iq: 40),
    ];
    final assignment = OffensiveRoleRanking.derive(
      lineupOf(teamOf(players), players),
    );
    expect(
      () => assignment.ranking.add(const PlayerId('extra')),
      throwsUnsupportedError,
    );
  });

  test('substitution reclassifies the active five', () {
    final creator = player(
      'creator',
      Position.pg,
      handling: 90,
      passing: 90,
      iq: 90,
    );
    final others = [
      player('sg', Position.sg, handling: 50, passing: 50, iq: 50),
      player('sf', Position.sf, handling: 50, passing: 50, iq: 50),
      player('pf', Position.pf, handling: 50, passing: 50, iq: 50),
      player('c', Position.c, handling: 50, passing: 50, iq: 50),
    ];
    final bench = player(
      'bench',
      Position.pg,
      handling: 40,
      passing: 40,
      iq: 40,
    );
    final team = teamOf([creator, ...others, bench]);

    final before = OffensiveRoleRanking.derive(
      lineupOf(team, [creator, ...others]),
    );
    expect(before.primary, const PlayerId('creator'));

    final after = OffensiveRoleRanking.derive(
      lineupOf(team, [bench, ...others]),
    );
    expect(after.ranking, isNot(contains(const PlayerId('creator'))));
    expect(after.primary, const PlayerId('sg')); // tie on 250, slot order
    expect(after.roleOf(const PlayerId('bench')), OffensiveRole.neutral);
  });

  test('the same player changes role when teammates change', () {
    final star = player(
      'star',
      Position.sg,
      handling: 70,
      passing: 70,
      iq: 70,
    ); // 350
    final weakTeammates = [
      player('pg', Position.pg, handling: 50, passing: 50, iq: 50),
      star,
      player('sf', Position.sf, handling: 50, passing: 50, iq: 50),
      player('pf', Position.pf, handling: 50, passing: 50, iq: 50),
      player('c', Position.c, handling: 50, passing: 50, iq: 50),
    ];
    final strongTeammate = player(
      'creator',
      Position.pg,
      handling: 95,
      passing: 95,
      iq: 95,
    ); // 475
    final strongLineup = [
      strongTeammate,
      star,
      player('sf', Position.sf, handling: 50, passing: 50, iq: 50),
      player('pf', Position.pf, handling: 50, passing: 50, iq: 50),
      player('c', Position.c, handling: 50, passing: 50, iq: 50),
    ];

    final alone = OffensiveRoleRanking.derive(
      lineupOf(teamOf(weakTeammates), weakTeammates),
    );
    final withCreator = OffensiveRoleRanking.derive(
      lineupOf(teamOf(strongLineup), strongLineup),
    );

    expect(alone.roleOf(const PlayerId('star')), OffensiveRole.primary);
    expect(withCreator.roleOf(const PlayerId('star')), OffensiveRole.secondary);
  });

  test('production usage and zone weights ignore the role helper', () {
    final model = BasketballProbabilityModel();
    final players = [
      player('pg', Position.pg, handling: 72, passing: 68, iq: 62, three: 45),
      player('sg', Position.sg, handling: 60, passing: 55, iq: 55, three: 60),
      player('sf', Position.sf, handling: 50, passing: 50, iq: 50),
      player('pf', Position.pf, handling: 55, passing: 60, iq: 62, three: 78),
      player('c', Position.c, handling: 35, passing: 40, iq: 50, three: 20),
    ];
    final team = teamOf(players);
    final lineup = lineupOf(team, players);

    final usageBefore = model.shotUsageWeights(lineup);
    final zoneBefore = model.shotZoneWeights(
      shooter: players.first,
      phase: PhaseKind.halfCourt,
    );

    OffensiveRoleRanking.derive(lineup);

    expect(model.shotUsageWeights(lineup), usageBefore);
    expect(
      model.shotZoneWeights(shooter: players.first, phase: PhaseKind.halfCourt),
      zoneBefore,
    );
    expect(model.shotUsageWeights(lineup).fold<int>(0, (a, b) => a + b), 10000);
  });

  test(
    'an elite scorer stays eligible for high usage without a creator rank',
    () {
      final scorer = player(
        'scorer',
        Position.sf,
        handling: 50,
        passing: 50,
        iq: 60,
        three: 95,
        mid: 85,
        inside: 70,
      );
      final creator = player(
        'creator',
        Position.pg,
        handling: 80,
        passing: 80,
        iq: 80,
      );
      final players = [
        creator,
        player('sg', Position.sg, handling: 50, passing: 50, iq: 50),
        scorer,
        player('pf', Position.pf, handling: 50, passing: 50, iq: 50),
        player('c', Position.c, handling: 50, passing: 50, iq: 50),
      ];
      final team = teamOf(players);
      final lineup = lineupOf(team, players);
      final assignment = OffensiveRoleRanking.derive(lineup);
      expect(assignment.primary, const PlayerId('creator'));
      // Second only on creation score, never primary; role does not suppress
      // his shooting usage.
      expect(assignment.primary, isNot(const PlayerId('scorer')));
      expect(
        assignment.roleOf(const PlayerId('scorer')),
        anyOf(OffensiveRole.secondary, OffensiveRole.neutral),
      );

      // v6 usage is not role-adjusted: the scorer can still carry high usage.
      final weights = BasketballProbabilityModel().shotUsageWeights(lineup);
      final scorerIndex = lineup.slotIndexForPlayer(const PlayerId('scorer'));
      final creatorIndex = lineup.slotIndexForPlayer(const PlayerId('creator'));
      expect(weights[scorerIndex], greaterThan(weights[creatorIndex]));
    },
  );
}
