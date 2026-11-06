import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

typedef PolicyFixture = ({
  Team team,
  CourtLineup lineup,
  Map<PlayerId, int> targets,
  Map<PlayerId, int> actuals,
});

PolicyFixture fixture({
  List<Position> benchPositions = const [
    Position.sg,
    Position.sf,
    Position.pf,
    Position.c,
  ],
  int targetSeconds = 720,
}) {
  final attributes = const LeagueGenerator()
      .generate(const GenerationConfig(seed: 20261028))
      .teams
      .first
      .players
      .first
      .attributes;
  Player make(String id, Position position) => Player(
    id: PlayerId(id),
    firstName: 'Player',
    lastName: id,
    position: position,
    attributes: attributes,
  );
  final players = [
    for (final (index, position) in const [
      Position.pg,
      Position.sg,
      Position.sf,
      Position.pf,
      Position.c,
    ].indexed)
      make('p$index', position),
    for (var index = 0; index < benchPositions.length; index++)
      make('p${5 + index}', benchPositions[index]),
  ];
  final team = Team(
    id: TeamId('rotation-policy'),
    name: 'Rotation Policy',
    abbreviation: 'POL',
    roster: Roster(players),
  );
  return (
    team: team,
    lineup: CourtLineup.defaultFor(team),
    targets: {for (final player in players) player.id: targetSeconds},
    actuals: {for (final player in players) player.id: targetSeconds},
  );
}

RotationPolicyInput inputFor(
  PolicyFixture data, {
  Map<PlayerId, int>? targets,
  Map<PlayerId, int>? actuals,
  CourtLineup? lineup,
  int elapsedSeconds = 720,
  int horizonSeconds = 720,
  int activePeriodSeconds = 720,
  int gameSecondsElapsed = 1000,
  Set<PlayerId> disqualified = const {},
  bool mandatoryReplacementPending = false,
  bool swappedThisWindow = false,
  RotationSwapProposal? previousSwap,
  int? previousSwapGameSeconds,
}) => RotationPolicyInput(
  team: data.team,
  activeLineup: lineup ?? data.lineup,
  targetSeconds: targets ?? data.targets,
  actualSeconds: actuals ?? data.actuals,
  elapsedSeconds: elapsedSeconds,
  horizonSeconds: horizonSeconds,
  activePeriodSeconds: activePeriodSeconds,
  gameSecondsElapsed: gameSecondsElapsed,
  disqualified: disqualified,
  mandatoryReplacementPending: mandatoryReplacementPending,
  swappedThisWindow: swappedThisWindow,
  previousSwap: previousSwap,
  previousSwapGameSeconds: previousSwapGameSeconds,
);

Map<PlayerId, int> actualsWith(
  PolicyFixture data, {
  Map<String, int> overrides = const {},
}) => {
  for (final player in data.team.players)
    player.id: overrides[player.id.value] ?? data.actuals[player.id]!,
};

PlayerId idOf(PolicyFixture data, String id) => PlayerId(id);

void main() {
  group('thresholds', () {
    test('regulation and overtime values match the frozen policy', () {
      expect(RotationPolicy.thresholds(720), (h: 90, cooldown: 120));
      expect(RotationPolicy.thresholds(300), (h: 37, cooldown: 50));
    });

    test('very short periods floor both thresholds at one', () {
      expect(RotationPolicy.thresholds(8), (h: 1, cooldown: 1));
      expect(RotationPolicy.thresholds(6), (h: 1, cooldown: 1));
      expect(RotationPolicy.thresholds(1), (h: 1, cooldown: 1));
      expect(RotationPolicy.thresholds(0), (h: 1, cooldown: 1));
    });
  });

  group('selection', () {
    test('no qualifying deficit returns no swap', () {
      final data = fixture();
      expect(RotationPolicy.propose(inputFor(data)), isNull);
    });

    test('selects the most over-target active player', () {
      final data = fixture();
      final proposal = RotationPolicy.propose(
        inputFor(
          data,
          actuals: actualsWith(
            data,
            overrides: {'p0': 900, 'p1': 950, 'p5': 0},
          ),
        ),
      );
      expect(proposal, isNotNull);
      expect(proposal!.playerOutId, idOf(data, 'p1'));
      expect(proposal.playerOutDeficit, -230);
      expect(proposal.playerInDeficit, 720);
    });

    test('outgoing ties break on lower canonical roster index', () {
      final data = fixture();
      final proposal = RotationPolicy.propose(
        inputFor(
          data,
          actuals: actualsWith(
            data,
            overrides: {'p0': 900, 'p1': 900, 'p5': 0},
          ),
        ),
      );
      expect(proposal!.playerOutId, idOf(data, 'p0'));
    });

    test('incoming prefers the vacated slot position', () {
      final data = fixture(
        benchPositions: const [
          Position.sg,
          Position.sf,
          Position.pf,
          Position.c,
          Position.pg,
        ],
      );
      final proposal = RotationPolicy.propose(
        inputFor(
          data,
          actuals: actualsWith(data, overrides: {'p0': 900, 'p5': 0, 'p9': 0}),
        ),
      );
      expect(proposal, isNotNull);
      expect(proposal!.vacatedSlot, Position.pg);
      expect(proposal.playerInId, idOf(data, 'p9'));
    });

    test('incoming ties break on roster index within the slot match', () {
      final data = fixture(
        benchPositions: const [
          Position.sg,
          Position.pg,
          Position.pg,
          Position.c,
        ],
      );
      final proposal = RotationPolicy.propose(
        inputFor(
          data,
          actuals: actualsWith(data, overrides: {'p0': 900, 'p6': 0, 'p7': 0}),
        ),
      );
      expect(proposal!.playerInId, idOf(data, 'p6'));
    });

    test('incoming picks the largest bench deficit', () {
      final data = fixture();
      final proposal = RotationPolicy.propose(
        inputFor(
          data,
          actuals: actualsWith(
            data,
            overrides: {'p0': 900, 'p5': 0, 'p6': 600},
          ),
        ),
      );
      expect(proposal!.playerInId, idOf(data, 'p5'));
      expect(proposal.playerInDeficit, 720);
    });

    test('required deficit boundary is inclusive', () {
      final data = fixture();
      final atBoundary = RotationPolicy.propose(
        inputFor(
          data,
          actuals: actualsWith(data, overrides: {'p0': 810, 'p5': 630}),
        ),
      );
      expect(atBoundary, isNotNull);
      expect(atBoundary!.playerOutDeficit, -90);
      expect(atBoundary.playerInDeficit, 90);

      final below = RotationPolicy.propose(
        inputFor(
          data,
          actuals: actualsWith(data, overrides: {'p0': 809, 'p5': 631}),
        ),
      );
      expect(below, isNull);
    });

    test('expected values use the supplied phase-local horizon', () {
      final data = fixture();
      final proposal = RotationPolicy.propose(
        inputFor(
          data,
          elapsedSeconds: 360,
          horizonSeconds: 720,
          actuals: actualsWith(
            data,
            overrides: {
              'p0': 500,
              'p1': 360,
              'p2': 360,
              'p3': 360,
              'p4': 360,
              'p5': 0,
            },
          ),
        ),
      );
      expect(proposal, isNotNull);
      expect(proposal!.playerOutDeficit, -140);
      expect(proposal.playerInDeficit, 360);
    });

    test('overtime thresholds use the overtime period length', () {
      final data = fixture();
      final qualifying = RotationPolicy.propose(
        inputFor(
          data,
          activePeriodSeconds: 300,
          actuals: actualsWith(data, overrides: {'p0': 757, 'p5': 683}),
        ),
      );
      expect(qualifying, isNotNull);
      expect(qualifying!.playerOutDeficit, -37);
      expect(qualifying.playerInDeficit, 37);

      final short = RotationPolicy.propose(
        inputFor(
          data,
          activePeriodSeconds: 300,
          actuals: actualsWith(data, overrides: {'p0': 756, 'p5': 684}),
        ),
      );
      expect(short, isNull);
    });
  });

  group('suppression and eligibility', () {
    test('cooldown blocks a swap and expires on the boundary', () {
      final data = fixture();
      final actuals = actualsWith(data, overrides: {'p0': 900, 'p5': 0});
      expect(
        RotationPolicy.propose(
          inputFor(
            data,
            actuals: actuals,
            gameSecondsElapsed: 1119,
            previousSwapGameSeconds: 1000,
          ),
        ),
        isNull,
      );
      expect(
        RotationPolicy.propose(
          inputFor(
            data,
            actuals: actuals,
            gameSecondsElapsed: 1120,
            previousSwapGameSeconds: 1000,
          ),
        ),
        isNotNull,
      );
    });

    test('cooldown spans regulation period boundaries', () {
      final data = fixture();
      final actuals = actualsWith(data, overrides: {'p0': 900, 'p5': 0});
      expect(
        RotationPolicy.propose(
          inputFor(
            data,
            actuals: actuals,
            gameSecondsElapsed: 2910,
            previousSwapGameSeconds: 2800,
          ),
        ),
        isNull,
      );
      expect(
        RotationPolicy.propose(
          inputFor(
            data,
            actuals: actuals,
            gameSecondsElapsed: 2920,
            previousSwapGameSeconds: 2800,
          ),
        ),
        isNotNull,
      );
    });

    test('an exact reverse of the previous swap is suppressed', () {
      final data = fixture();
      final benchLineup = CourtLineup.create(
        team: data.team,
        slotOrderedPlayers: [
          data.team.players[5],
          data.team.players[1],
          data.team.players[2],
          data.team.players[3],
          data.team.players[4],
        ],
      );
      final previous = RotationSwapProposal(
        playerOutId: idOf(data, 'p0'),
        playerInId: idOf(data, 'p5'),
        vacatedSlot: Position.pg,
        playerOutDeficit: -180,
        playerInDeficit: 720,
      );
      final proposal = RotationPolicy.propose(
        inputFor(
          data,
          lineup: benchLineup,
          actuals: {
            for (final player in data.team.players)
              player.id: player.id.value == 'p5' ? 900 : 0,
          },
          previousSwap: previous,
          previousSwapGameSeconds: 500,
          gameSecondsElapsed: 1000,
        ),
      );
      expect(proposal, isNull);
    });

    test('mandatory replacement or an existing window swap suppresses', () {
      final data = fixture();
      final actuals = actualsWith(data, overrides: {'p0': 900, 'p5': 0});
      expect(
        RotationPolicy.propose(
          inputFor(data, actuals: actuals, mandatoryReplacementPending: true),
        ),
        isNull,
      );
      expect(
        RotationPolicy.propose(
          inputFor(data, actuals: actuals, swappedThisWindow: true),
        ),
        isNull,
      );
    });

    test('disqualified players are never selected', () {
      final data = fixture();
      final outgoing = RotationPolicy.propose(
        inputFor(
          data,
          actuals: actualsWith(
            data,
            overrides: {'p0': 1000, 'p1': 900, 'p5': 0},
          ),
          disqualified: {idOf(data, 'p0')},
        ),
      );
      expect(outgoing!.playerOutId, idOf(data, 'p1'));

      final incoming = RotationPolicy.propose(
        inputFor(
          data,
          actuals: actualsWith(
            data,
            overrides: {'p0': 900, 'p5': 0, 'p6': 500},
          ),
          disqualified: {idOf(data, 'p5')},
        ),
      );
      expect(incoming!.playerInId, idOf(data, 'p6'));
      expect(incoming.playerInDeficit, 220);
    });

    test('zero-target bench players are excluded', () {
      final data = fixture();
      final targets = {...data.targets};
      for (final player in data.team.players.skip(5)) {
        targets[player.id] = 0;
      }
      final proposal = RotationPolicy.propose(
        inputFor(
          data,
          targets: targets,
          actuals: actualsWith(data, overrides: {'p0': 900}),
        ),
      );
      expect(proposal, isNull);
    });

    test('no eligible bench returns no swap', () {
      final data = fixture();
      final disqualified = {
        for (final player in data.team.players.skip(5)) player.id,
      };
      expect(
        RotationPolicy.propose(
          inputFor(
            data,
            actuals: actualsWith(data, overrides: {'p0': 900}),
            disqualified: disqualified,
          ),
        ),
        isNull,
      );
    });
  });

  group('determinism', () {
    test('repeated calls are identical and consume no PRNG draws', () {
      final data = fixture();
      final rng = DeterministicRandom(1);
      final drawsBefore = rng.drawCount;
      final input = inputFor(
        data,
        actuals: actualsWith(data, overrides: {'p0': 900, 'p5': 0}),
      );
      final first = RotationPolicy.propose(input);
      final second = RotationPolicy.propose(input);
      expect(rng.drawCount, drawsBefore);
      expect(first!.playerOutId, second!.playerOutId);
      expect(first.playerInId, second.playerInId);
      expect(first.playerOutDeficit, second.playerOutDeficit);
      expect(first.playerInDeficit, second.playerInDeficit);
    });
  });
}
