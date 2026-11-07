import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';

const leagueSeed = 20261028;

GameInput plannedInput({
  RotationPreset homePreset = RotationPreset.balanced,
  RotationPreset awayPreset = RotationPreset.balanced,
  int seed = 42,
  GameRules? rules,
  League? league,
}) {
  final effectiveRules = rules ?? GameRules.standard;
  final resolvedLeague =
      league ??
      const LeagueGenerator().generate(
        const GenerationConfig(seed: leagueSeed),
      );
  final home = resolvedLeague.teams.first;
  final away = resolvedLeague.teams[1];
  final homeLineup = CourtLineup.defaultFor(home);
  final awayLineup = CourtLineup.defaultFor(away);

  TeamRotationPlan expand(
    Team team,
    CourtLineup lineup,
    RotationPreset preset,
  ) {
    final targets = RotationPlan.expandPreset(
      preset: preset,
      team: team,
      lineup: lineup,
      rules: effectiveRules,
    );
    return TeamRotationPlan.create(
      team: team,
      preset: preset,
      targets: [
        for (final player in team.players)
          RotationTarget(playerId: player.id, seconds: targets[player.id]!),
      ],
    );
  }

  return GameInput.create(
    gameId: 'rotation-smoke',
    league: resolvedLeague,
    homeTeamId: home.id,
    awayTeamId: away.id,
    homeLineup: homeLineup,
    awayLineup: awayLineup,
    seed: seed,
    rules: effectiveRules,
    rotationPlan: RotationPlan(
      home: expand(home, homeLineup, homePreset),
      away: expand(away, awayLineup, awayPreset),
    ),
  );
}

List<Substitution> tactical(GameResult result) => [
  for (final event in result.events.whereType<Substitution>())
    if (event.reason == SubstitutionReason.tactical) event,
];

String? windowFor(List<GameEvent> events, int substitutionIndex) {
  for (var index = substitutionIndex - 1; index >= 0; index--) {
    final event = events[index];
    if (event is Substitution) continue;
    if (event is PeriodStarted) return 'W5';
    if (event is PossessionEnded) {
      if (event.reason == PossessionEndReason.madeFinalFreeThrow) return 'W2';
      if (event.reason == PossessionEndReason.turnover) return 'W4';
      return 'other:${event.reason.name}';
    }
    if (event is PersonalFoul) {
      return event.kind == FoulKind.nonShooting && event.freeThrowsAwarded == 0
          ? 'W1'
          : 'W0';
    }
    return 'other:${event.runtimeType}';
  }
  return null;
}

/// Maximal runs of adjacent substitution events: one legal window each.
List<List<Substitution>> substitutionRuns(List<GameEvent> events) {
  final runs = <List<Substitution>>[];
  var current = <Substitution>[];
  void flush() {
    if (current.isNotEmpty) runs.add(current);
    current = <Substitution>[];
  }

  for (final event in events) {
    if (event is Substitution) {
      current.add(event);
    } else {
      flush();
    }
  }
  flush();
  return runs;
}

int cumulativeSeconds(GameRules rules, GameEvent event) {
  var total = 0;
  for (var period = 1; period < event.period; period++) {
    total += rules.periodLength(period);
  }
  return total + rules.periodLength(event.period) - event.gameClock;
}

typedef OvertimeFixture = ({
  Team team,
  CourtLineup lineup,
  Map<PlayerId, int> targets,
});

OvertimeFixture overtimeFixture({
  List<Position> benchPositions = const [
    Position.sg,
    Position.sf,
    Position.pf,
    Position.c,
  ],
  int regulationTarget = 2880,
}) {
  final attributes = const LeagueGenerator()
      .generate(const GenerationConfig(seed: leagueSeed))
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
      make('o$index', position),
    for (var index = 0; index < benchPositions.length; index++)
      make('o${5 + index}', benchPositions[index]),
  ];
  final team = Team(
    id: TeamId('overtime-policy'),
    name: 'Overtime Policy',
    abbreviation: 'OTP',
    roster: Roster(players),
  );
  return (
    team: team,
    lineup: CourtLineup.defaultFor(team),
    targets: {for (final player in players) player.id: regulationTarget},
  );
}

void main() {
  test('a planned game emits reducer-valid tactical substitutions', () {
    final result = GameSimulator().simulate(plannedInput());
    final swaps = tactical(result);
    expect(swaps, isNotEmpty);
    expect(swaps.every((event) => event.gameClock > 0), isTrue);
    expect(
      swaps.map((event) => event.teamId).toSet(),
      containsAll([
        result.input.homeTeamId.value,
        result.input.awayTeamId.value,
      ]),
    );
  });

  test('tactical hooks fire only at W1/W2/W4/W5 and never at W0', () {
    final windows = <String>{};
    for (final seed in [7, 15, 42]) {
      final result = GameSimulator().simulate(plannedInput(seed: seed));
      for (var index = 0; index < result.events.length; index++) {
        final event = result.events[index];
        if (event is! Substitution ||
            event.reason != SubstitutionReason.tactical) {
          continue;
        }
        final window = windowFor(result.events, index);
        expect(window, isNotNull);
        expect(window, isNot('W0'));
        expect(window, isNot(startsWith('other')));
        windows.add(window!);
      }
    }
    expect(windows, containsAll(['W1', 'W2', 'W4', 'W5']));
  });

  test('a foul-out replacement precedes same-team tactical swaps', () {
    final result = GameSimulator().simulate(plannedInput());
    final events = result.events;
    for (var index = 0; index < events.length; index++) {
      final event = events[index];
      if (event is! Substitution ||
          event.reason != SubstitutionReason.tactical) {
        continue;
      }
      for (var next = index + 1; next < events.length; next++) {
        final later = events[next];
        if (later is! Substitution) break;
        if (later.teamId != event.teamId) continue;
        expect(
          later.reason,
          SubstitutionReason.tactical,
          reason: 'mandatory replacement must come first for the team',
        );
      }
    }
  });

  test('rotation changes player minutes and conserves team seconds', () {
    final planned = GameSimulator().simulate(plannedInput());
    final legacy = GameSimulator().simulate(buildInput(seed: 42));
    expect(tactical(legacy), isEmpty);

    var changed = false;
    for (final teamId in [
      planned.input.homeTeamId.value,
      planned.input.awayTeamId.value,
    ]) {
      final teamPlayers = planned.input.league.teams
          .firstWhere((team) => team.id.value == teamId)
          .players;
      var total = 0;
      for (final player in teamPlayers) {
        final plannedSeconds =
            planned.boxScore.players[player.id.value]!.secondsPlayed;
        total += plannedSeconds;
        final legacySeconds =
            legacy.boxScore.players[player.id.value]!.secondsPlayed;
        if (plannedSeconds != legacySeconds) changed = true;
      }
      var expected = 0;
      for (var period = 1; period <= planned.periodsPlayed; period++) {
        expected += 5 * planned.input.rules.periodLength(period);
      }
      expect(total, expected);
    }
    expect(changed, isTrue);
  });

  test('tactical swaps change the active five, not just statistics', () {
    final result = GameSimulator().simulate(plannedInput());
    final active = <String, Set<String>>{
      result.input.homeTeamId.value: {...result.input.homeLineup.playerIds},
      result.input.awayTeamId.value: {...result.input.awayLineup.playerIds},
    };
    final starters = {
      ...result.input.homeLineup.playerIds,
      ...result.input.awayLineup.playerIds,
    };
    final entrants = <String>{};
    var tacticalCount = 0;
    for (final event in result.events.whereType<Substitution>()) {
      final five = active[event.teamId]!;
      expect(five, contains(event.playerOutId));
      expect(five, isNot(contains(event.playerInId)));
      five
        ..remove(event.playerOutId)
        ..add(event.playerInId);
      expect(five, hasLength(5));
      if (event.reason == SubstitutionReason.tactical) {
        tacticalCount++;
        entrants.add(event.playerInId);
      }
    }
    expect(tacticalCount, greaterThan(0));
    expect(entrants.difference(starters), isNotEmpty);
  });

  test('overtime planned games validate and conserve minutes', () {
    final rules = GameRules(
      periodSeconds: 1,
      overtimeSeconds: 60,
      shotClockSeconds: 1,
      offensiveReboundResetSeconds: 1,
      nonBonusFoulResetFloorSeconds: 1,
    );
    GameResult? overtime;
    for (var seed = 1; seed <= 20 && overtime == null; seed++) {
      final result = GameSimulator().simulate(
        plannedInput(seed: seed, rules: rules),
      );
      if (result.overtimes > 0) overtime = result;
    }
    expect(overtime, isNotNull);
    final result = overtime!;
    expect(result.periodsPlayed, greaterThan(4));
    final overtimePeriods = {
      for (final event in result.events.whereType<PeriodStarted>())
        if (event.period > 4) event.period,
    };
    expect(overtimePeriods, isNotEmpty);
    for (final teamId in [
      result.input.homeTeamId.value,
      result.input.awayTeamId.value,
    ]) {
      var total = 0;
      for (final player
          in result.input.league.teams
              .firstWhere((team) => team.id.value == teamId)
              .players) {
        total += result.boxScore.players[player.id.value]!.secondsPlayed;
      }
      var expected = 0;
      for (var period = 1; period <= result.periodsPlayed; period++) {
        expected += 5 * result.input.rules.periodLength(period);
      }
      expect(total, expected);
    }
    for (final substitution in result.events.whereType<Substitution>().where(
      (event) => event.reason == SubstitutionReason.tactical,
    )) {
      expect(substitution.gameClock, greaterThan(0));
    }
  });

  test('different plans produce different participation on one seed', () {
    final balanced = GameSimulator().simulate(plannedInput());
    final starterHeavy = GameSimulator().simulate(
      plannedInput(
        homePreset: RotationPreset.starterHeavy,
        awayPreset: RotationPreset.starterHeavy,
      ),
    );
    final differences = [
      for (final player in balanced.input.homeTeam.players)
        if (balanced.boxScore.players[player.id.value]!.secondsPlayed !=
            starterHeavy.boxScore.players[player.id.value]!.secondsPlayed)
          player.id.value,
    ];
    expect(differences, isNotEmpty);
  });

  test('identical planned inputs reproduce identical ledgers', () {
    final first = GameSimulator().simulate(plannedInput());
    final second = GameSimulator().simulate(plannedInput());
    expect(first.inputFingerprint, second.inputFingerprint);
    expect(
      first.events.map((event) => event.toJson()).toList(),
      second.events.map((event) => event.toJson()).toList(),
    );
    expect(tactical(first), isNotEmpty);
  });

  test('tactical decisions consume zero PRNG draws', () {
    final traces = <RotationDrawTrace>[];
    final result = GameSimulator(
      onRotationDraw: traces.add,
    ).simulate(plannedInput());
    expect(tactical(result), isNotEmpty);
    expect(traces, isNotEmpty);
    expect(traces.every((trace) => trace.draws == 0), isTrue);
  });

  test('a foul-out window suppresses a rotation that was otherwise due', () {
    var collisions = 0;
    for (final seed in [1, 7, 15, 42, 99, 2026]) {
      final result = GameSimulator().simulate(plannedInput(seed: seed));
      final input = result.input;
      final plan = input.rotationPlan!;
      final rules = input.rules;
      final threshold = rules.periodSeconds ~/ 8;
      final horizon = RotationPlan.regulationCap(rules);

      final seconds = <String, int>{};
      final active = <String, List<String>>{
        input.homeTeamId.value: input.homeLineup.playerIds.toList(),
        input.awayTeamId.value: input.awayLineup.playerIds.toList(),
      };
      final fouls = <String, int>{};
      var last = 0;

      for (var index = 0; index < result.events.length; index++) {
        final event = result.events[index];
        final now = cumulativeSeconds(rules, event);
        final delta = now - last;
        if (delta > 0) {
          for (final five in active.values) {
            for (final playerId in five) {
              seconds[playerId] = (seconds[playerId] ?? 0) + delta;
            }
          }
        }
        last = now;

        if (event is PersonalFoul) {
          fouls[event.committingPlayerId] =
              (fouls[event.committingPlayerId] ?? 0) + 1;
          continue;
        }
        if (event is! Substitution) continue;

        if (event.reason == SubstitutionReason.foulOut &&
            event.period <= rules.periods) {
          final teamId = event.teamId;
          final teamPlan = teamId == input.homeTeamId.value
              ? plan.home
              : plan.away;
          final team = input.league.teams.firstWhere(
            (candidate) => candidate.id.value == teamId,
          );
          final five = active[teamId]!;
          final disqualified = {
            for (final player in team.players)
              if ((fouls[player.id.value] ?? 0) >= rules.foulOutLimit)
                player.id.value,
          };
          int deficit(String playerId) =>
              (teamPlan.targetSeconds[PlayerId(playerId)] ?? 0) *
                  now ~/
                  horizon -
              (seconds[playerId] ?? 0);
          final healthyActive = [
            for (final playerId in five)
              if (!disqualified.contains(playerId)) playerId,
          ];
          final bench = [
            for (final player in team.players)
              if (!five.contains(player.id.value) &&
                  !disqualified.contains(player.id.value) &&
                  (teamPlan.targetSeconds[player.id] ?? 0) > 0)
                player.id.value,
          ];
          final due =
              healthyActive.any((id) => deficit(id) <= -threshold) &&
              bench.any((id) => deficit(id) >= threshold);
          if (due) {
            collisions++;
            for (var next = index + 1; next < result.events.length; next++) {
              final later = result.events[next];
              if (later is! Substitution) break;
              if (later.teamId != teamId) continue;
              expect(
                later.reason,
                SubstitutionReason.foulOut,
                reason: 'a due rotation must not pre-empt the foul-out',
              );
            }
          }
        }

        final five = active[event.teamId]!;
        expect(five, contains(event.playerOutId));
        five[five.indexOf(event.playerOutId)] = event.playerInId;
      }

      for (final player in result.boxScore.players.values) {
        expect(
          seconds[player.playerId] ?? 0,
          player.secondsPlayed,
          reason: 'ledger oracle must match the box score',
        );
      }
    }
    expect(collisions, greaterThan(0));
  });

  test('tactical swaps respect the regulation cooldown', () {
    final cooldown = GameRules.standard.periodSeconds ~/ 6;
    var pairs = 0;
    for (final seed in [7, 15, 42]) {
      final result = GameSimulator().simulate(plannedInput(seed: seed));
      for (final teamId in [
        result.input.homeTeamId.value,
        result.input.awayTeamId.value,
      ]) {
        final swaps = [
          for (final sub in result.events.whereType<Substitution>())
            if (sub.teamId == teamId &&
                sub.reason == SubstitutionReason.tactical &&
                sub.period <= result.input.rules.periods)
              sub,
        ];
        for (var index = 1; index < swaps.length; index++) {
          expect(
            cumulativeSeconds(result.input.rules, swaps[index]) -
                cumulativeSeconds(result.input.rules, swaps[index - 1]),
            greaterThanOrEqualTo(cooldown),
          );
          pairs++;
        }
      }
    }
    expect(pairs, greaterThan(0));
  });

  test('the reducer rejects tactical substitutions at illegal moments', () {
    final result = GameSimulator().simulate(plannedInput());
    final target = tactical(result).first;
    List<GameEvent> mutated({int? gameClock, int? shotClock}) => [
      for (final event in result.events)
        if (event.sequence == target.sequence)
          Substitution(
            sequence: target.sequence,
            period: target.period,
            gameClock: gameClock ?? target.gameClock,
            shotClock: shotClock ?? target.shotClock,
            teamId: target.teamId,
            playerOutId: target.playerOutId,
            playerInId: target.playerInId,
            reason: target.reason,
          )
        else
          event,
    ];

    expect(
      () => GameEventReducer.validate(
        result.input,
        buildLedger(result.input, mutated()),
      ),
      returnsNormally,
    );
    expect(
      () => GameEventReducer.validate(
        result.input,
        buildLedger(result.input, mutated(gameClock: 0)),
      ),
      throwsA(isA<GameValidationException>()),
    );
    expect(
      () => GameEventReducer.validate(
        result.input,
        buildLedger(
          result.input,
          mutated(shotClock: (target.shotClock ?? 0) + 1),
        ),
      ),
      throwsA(isA<GameValidationException>()),
    );
  });

  test('a five-player roster cannot rotate and still conserves seconds', () {
    final league = const LeagueGenerator().generate(
      const GenerationConfig(seed: leagueSeed, playersPerTeam: 5),
    );
    GameResult? depleted;
    for (var seed = 1; seed <= 40 && depleted == null; seed++) {
      final result = GameSimulator().simulate(
        plannedInput(seed: seed, league: league),
      );
      if (result.boxScore.players.values.any(
        (line) => line.personalFouls >= result.input.rules.foulOutLimit,
      )) {
        depleted = result;
      }
    }
    expect(depleted, isNotNull);
    final result = depleted!;
    expect(tactical(result), isEmpty);
    for (final teamId in [
      result.input.homeTeamId.value,
      result.input.awayTeamId.value,
    ]) {
      var total = 0;
      for (final player
          in result.input.league.teams
              .firstWhere((team) => team.id.value == teamId)
              .players) {
        final line = result.boxScore.players[player.id.value]!;
        total += line.secondsPlayed;
        if (line.personalFouls >= result.input.rules.foulOutLimit) {
          expect(line.secondsPlayed, greaterThan(0));
        }
      }
      var expected = 0;
      for (var period = 1; period <= result.periodsPlayed; period++) {
        expected += 5 * result.input.rules.periodLength(period);
      }
      expect(total, expected);
    }
  });

  test('overtime windows keep the same hook and mandatory rules', () {
    final rules = GameRules(
      periodSeconds: 12,
      overtimeSeconds: 120,
      shotClockSeconds: 24,
      offensiveReboundResetSeconds: 14,
      nonBonusFoulResetFloorSeconds: 14,
    );
    GameResult? found;
    for (var seed = 1; seed <= 300 && found == null; seed++) {
      final result = GameSimulator().simulate(
        plannedInput(seed: seed, rules: rules),
      );
      if (result.overtimes == 0) continue;
      if (result.events.any(
        (event) =>
            event is Substitution &&
            event.reason == SubstitutionReason.tactical &&
            event.period > rules.periods,
      )) {
        found = result;
      }
    }
    expect(found, isNotNull, reason: 'overtime rotation must be reachable');
    final result = found!;

    for (var index = 0; index < result.events.length; index++) {
      final event = result.events[index];
      if (event is! Substitution ||
          event.reason != SubstitutionReason.tactical ||
          event.period <= rules.periods) {
        continue;
      }
      final window = windowFor(result.events, index);
      expect(window, isNot('W0'));
      expect(window, isNot(startsWith('other')));
      expect(event.gameClock, greaterThan(0));
    }

    for (final run in substitutionRuns(result.events)) {
      final fouledOut = {
        for (final sub in run)
          if (sub.reason == SubstitutionReason.foulOut) sub.teamId,
      };
      final rotated = {
        for (final sub in run)
          if (sub.reason == SubstitutionReason.tactical) sub.teamId,
      };
      expect(rotated.intersection(fouledOut), isEmpty);
    }

    for (final teamId in [
      result.input.homeTeamId.value,
      result.input.awayTeamId.value,
    ]) {
      var total = 0;
      for (final player
          in result.input.league.teams
              .firstWhere((team) => team.id.value == teamId)
              .players) {
        total += result.boxScore.players[player.id.value]!.secondsPlayed;
      }
      var expected = 0;
      for (var period = 1; period <= result.periodsPlayed; period++) {
        expected += 5 * result.input.rules.periodLength(period);
      }
      expect(total, expected);
    }

    final replay = GameSimulator().simulate(
      plannedInput(seed: found.input.seed, rules: rules),
    );
    expect(
      [
        for (final event in replay.events.whereType<Substitution>())
          if (event.period > rules.periods) event.toJson(),
      ],
      [
        for (final event in result.events.whereType<Substitution>())
          if (event.period > rules.periods) event.toJson(),
      ],
    );
  });

  test('an overtime foul-out precedes tactics and reshapes the next period', () {
    final rules = GameRules.standard;
    final input = plannedInput(
      seed: 5438,
      homePreset: RotationPreset.starterHeavy,
      awayPreset: RotationPreset.starterHeavy,
    );
    final result = GameSimulator().simulate(input);
    expect(result.overtimes, greaterThanOrEqualTo(2));
    final events = result.events;

    final fouls = <String, int>{};
    var foulOutIndex = -1;
    for (var index = 0; index < events.length; index++) {
      final event = events[index];
      if (event is PersonalFoul) {
        fouls[event.committingPlayerId] =
            (fouls[event.committingPlayerId] ?? 0) + 1;
        continue;
      }
      if (event is Substitution &&
          event.period > rules.periods &&
          event.reason == SubstitutionReason.foulOut) {
        foulOutIndex = index;
        break;
      }
    }
    expect(foulOutIndex, greaterThan(0), reason: 'overtime foul-out required');
    final foulOut = events[foulOutIndex] as Substitution;
    final foulPeriod = foulOut.period;
    expect(foulPeriod, greaterThan(rules.periods));
    expect(foulPeriod, lessThan(result.periodsPlayed));
    expect(foulOut.gameClock, greaterThan(0));
    expect(fouls[foulOut.playerOutId], rules.foulOutLimit);

    final trigger = events[foulOutIndex - 1];
    expect(trigger, isA<PersonalFoul>());
    final foul = trigger as PersonalFoul;
    expect(foul.committingPlayerId, foulOut.playerOutId);
    expect(foul.period, foulPeriod);
    expect(foul.gameClock, foulOut.gameClock);
    expect(
      foul.kind,
      FoulKind.nonShooting,
      reason: 'W1 is a tactical window, so precedence is observable there',
    );
    expect(foul.freeThrowsAwarded, 0);
    expect(foul.bonus, isFalse);
    expect(
      events[foulOutIndex + 1],
      isNot(isA<Substitution>()),
      reason: 'the mandatory replacement closes its window before any swap',
    );

    final later = [
      for (var index = foulOutIndex + 1; index < events.length; index++)
        if (events[index] is Substitution) events[index] as Substitution,
    ];
    for (final sub in later) {
      expect(sub.playerInId, isNot(foulOut.playerOutId));
    }
    final samePeriodTactical = [
      for (final sub in later)
        if (sub.period == foulPeriod &&
            sub.teamId == foulOut.teamId &&
            sub.reason == SubstitutionReason.tactical)
          sub,
    ];
    expect(
      samePeriodTactical,
      isNotEmpty,
      reason: 'the fixed period allocation keeps driving later windows',
    );
    for (final sub in samePeriodTactical) {
      expect(sub.playerOutId, isNot(foulOut.playerOutId));
    }

    // Ledger oracle: per-period seconds, foul counts and the lineup at the end
    // of the foul-out period.
    final seconds = <int, Map<String, int>>{};
    final active = <String, List<String>>{
      input.homeTeamId.value: input.homeLineup.playerIds.toList(),
      input.awayTeamId.value: input.awayLineup.playerIds.toList(),
    };
    final endOfFoulPeriod = <String, List<String>>{};
    var last = 0;
    var snapshotTaken = false;
    for (final event in events) {
      if (event.period > foulPeriod && !snapshotTaken) {
        snapshotTaken = true;
        endOfFoulPeriod.addAll({
          for (final entry in active.entries) entry.key: List.of(entry.value),
        });
      }
      final now = cumulativeSeconds(rules, event);
      final delta = now - last;
      if (delta > 0) {
        final bucket = seconds.putIfAbsent(event.period, () => <String, int>{});
        for (final five in active.values) {
          for (final playerId in five) {
            bucket[playerId] = (bucket[playerId] ?? 0) + delta;
          }
        }
      }
      last = now;
      if (event is Substitution) {
        final five = active[event.teamId]!;
        final slot = five.indexOf(event.playerOutId);
        expect(slot, greaterThanOrEqualTo(0));
        five[slot] = event.playerInId;
      }
    }
    expect(endOfFoulPeriod, isNotEmpty);

    final foulCountsAtFoulPeriodEnd = <String, int>{};
    for (final event in events) {
      if (event.period > foulPeriod) break;
      if (event is PersonalFoul) {
        foulCountsAtFoulPeriodEnd[event.committingPlayerId] =
            (foulCountsAtFoulPeriodEnd[event.committingPlayerId] ?? 0) + 1;
      }
    }

    for (final entry in seconds.entries) {
      if (entry.key > foulPeriod) {
        expect(entry.value[foulOut.playerOutId] ?? 0, 0);
      }
    }
    for (final player in result.boxScore.players.values) {
      final total = seconds.values.fold<int>(
        0,
        (sum, bucket) => sum + (bucket[player.playerId] ?? 0),
      );
      expect(total, player.secondsPlayed);
    }
    for (final teamId in [input.homeTeamId.value, input.awayTeamId.value]) {
      var total = 0;
      for (final player
          in input.league.teams
              .firstWhere((team) => team.id.value == teamId)
              .players) {
        total += result.boxScore.players[player.id.value]!.secondsPlayed;
      }
      var expected = 0;
      for (var period = 1; period <= result.periodsPlayed; period++) {
        expected += 5 * rules.periodLength(period);
      }
      expect(total, expected);
    }

    final team = input.league.teams.firstWhere(
      (candidate) => candidate.id.value == foulOut.teamId,
    );
    final teamPlan = foulOut.teamId == input.homeTeamId.value
        ? input.rotationPlan!.home
        : input.rotationPlan!.away;
    final allocation = RotationPolicy.allocateOvertime(
      team: team,
      activeLineup: CourtLineup.create(
        team: team,
        slotOrderedPlayers: [
          for (final playerId in endOfFoulPeriod[foulOut.teamId]!)
            team.players.firstWhere((player) => player.id.value == playerId),
        ],
      ),
      regulationTargets: teamPlan.targetSeconds,
      disqualified: {
        for (final player in team.players)
          if ((foulCountsAtFoulPeriodEnd[player.id.value] ?? 0) >=
              rules.foulOutLimit)
            player.id,
      },
      overtimeSeconds: rules.overtimeSeconds,
      regulationCap: RotationPlan.regulationCap(rules),
    );
    expect(
      allocation.targetSeconds[PlayerId(foulOut.playerOutId)],
      0,
      reason: 'the next period must exclude the disqualified player',
    );
    expect(
      allocation.targetSeconds.values.fold<int>(0, (sum, value) => sum + value),
      5 * rules.overtimeSeconds,
    );

    final replay = GameSimulator().simulate(
      plannedInput(
        seed: 5438,
        homePreset: RotationPreset.starterHeavy,
        awayPreset: RotationPreset.starterHeavy,
      ),
    );
    expect(
      [for (final event in replay.events) event.toJson()],
      [for (final event in events) event.toJson()],
    );
  });

  group('window history', () {
    const team = 'team-1';
    const other = 'team-2';
    final swap = RotationSwapProposal(
      playerOutId: const PlayerId('a'),
      playerInId: const PlayerId('b'),
      vacatedSlot: Position.pg,
      playerOutDeficit: -100,
      playerInDeficit: 100,
    );

    test('an empty window clears the previous pair but not the timestamp', () {
      final history = RotationWindowHistory();
      history.beginWindow([team, other]);
      history.recordSwap(team, swap, 300);
      history.beginWindow([team, other]);
      expect(history.previousWindowSwap(team), same(swap));
      expect(history.swappedThisWindow(team), isFalse);
      expect(history.lastTacticalSwapSeconds(team), 300);

      history.beginWindow([team, other]);
      expect(history.previousWindowSwap(team), isNull);
      expect(history.lastTacticalSwapSeconds(team), 300);
      expect(history.previousWindowSwap(other), isNull);
      expect(history.lastTacticalSwapSeconds(other), isNull);
    });

    test('teams keep independent histories', () {
      final history = RotationWindowHistory();
      history.beginWindow([team, other]);
      history.recordSwap(other, swap, 500);
      history.beginWindow([team, other]);
      expect(history.previousWindowSwap(other), same(swap));
      expect(history.previousWindowSwap(team), isNull);
      expect(history.lastTacticalSwapSeconds(other), 500);
      expect(history.lastTacticalSwapSeconds(team), isNull);
    });

    test('a reverse swap waits for an empty window, not for the clock', () {
      const teamId = 'reverse';
      final fixture = overtimeFixture(benchPositions: const [Position.pg]);
      final players = fixture.team.players;
      final bench = players[5];
      final targets = {for (final player in players) player.id: 2880};
      final startLineup = CourtLineup.create(
        team: fixture.team,
        slotOrderedPlayers: players.take(5).toList(),
      );
      final swappedLineup = CourtLineup.create(
        team: fixture.team,
        slotOrderedPlayers: [
          for (final slot in startLineup.slots)
            slot.playerId == players[0].id ? bench : slot.player!,
        ],
      );

      final history = RotationWindowHistory();
      RotationSwapProposal? decide({
        required CourtLineup lineup,
        required Map<PlayerId, int> actual,
        required int elapsed,
      }) => RotationPolicy.propose(
        RotationPolicyInput(
          team: fixture.team,
          activeLineup: lineup,
          targetSeconds: targets,
          actualSeconds: actual,
          elapsedSeconds: elapsed,
          horizonSeconds: 2880,
          activePeriodSeconds: 720,
          gameSecondsElapsed: elapsed,
          previousWindowSwap: history.previousWindowSwap(teamId),
          lastTacticalSwapGameSeconds: history.lastTacticalSwapSeconds(teamId),
        ),
      );

      history.beginWindow([teamId]);
      final first = decide(
        lineup: startLineup,
        actual: {
          players[0].id: 700,
          players[1].id: 600,
          players[2].id: 600,
          players[3].id: 600,
          players[4].id: 600,
          bench.id: 0,
        },
        elapsed: 600,
      );
      expect(first, isNotNull);
      expect(first!.playerOutId, players[0].id);
      expect(first.playerInId, bench.id);
      history.recordSwap(teamId, first, 600);

      Map<PlayerId, int> reversedActual() => {
        players[0].id: 600,
        players[1].id: 800,
        players[2].id: 800,
        players[3].id: 800,
        players[4].id: 800,
        bench.id: 900,
      };

      history.beginWindow([teamId]);
      expect(history.swappedThisWindow(teamId), isFalse);
      expect(history.previousWindowSwap(teamId), same(first));
      expect(
        decide(lineup: swappedLineup, actual: reversedActual(), elapsed: 800),
        isNull,
        reason: 'cooldown has expired, so only the reverse rule can block it',
      );

      history.beginWindow([teamId]);
      expect(history.previousWindowSwap(teamId), isNull);
      expect(history.lastTacticalSwapSeconds(teamId), 600);
      final reverse = decide(
        lineup: swappedLineup,
        actual: reversedActual(),
        elapsed: 800,
      );
      expect(reverse, isNotNull);
      expect(reverse!.playerOutId, bench.id);
      expect(reverse.playerInId, players[0].id);
    });
  });

  group('overtime allocation', () {
    test('balanced nine-player plan matches the frozen first period', () {
      final fixture = overtimeFixture();
      final targets = {
        for (final player in fixture.team.players)
          player.id: [
            1879,
            1879,
            1878,
            1878,
            1878,
            1252,
            1252,
            1252,
            1252,
          ][fixture.team.players.indexOf(player)],
      };
      final allocation = RotationPolicy.allocateOvertime(
        team: fixture.team,
        activeLineup: fixture.lineup,
        regulationTargets: targets,
        disqualified: const {},
        overtimeSeconds: 300,
        regulationCap: 2880,
      );
      expect(
        [
          for (final player in fixture.team.players)
            allocation.targetSeconds[player.id],
        ],
        [196, 196, 196, 196, 196, 130, 130, 130, 130],
      );
      expect(allocation.tacticalEnabled, isTrue);
    });

    test('a disqualified reserve changes the next period allocation', () {
      final fixture = overtimeFixture();
      final targets = {
        for (final player in fixture.team.players)
          player.id: [
            1879,
            1879,
            1878,
            1878,
            1878,
            1252,
            1252,
            1252,
            1252,
          ][fixture.team.players.indexOf(player)],
      };
      final disqualified = {fixture.team.players[5].id};
      final allocation = RotationPolicy.allocateOvertime(
        team: fixture.team,
        activeLineup: fixture.lineup,
        regulationTargets: targets,
        disqualified: disqualified,
        overtimeSeconds: 300,
        regulationCap: 2880,
      );
      expect(
        [
          for (final player in fixture.team.players)
            allocation.targetSeconds[player.id],
        ],
        [212, 212, 212, 212, 212, 0, 147, 147, 146],
      );
    });

    test('all-zero regulation targets fall back to an equal split', () {
      final fixture = overtimeFixture(regulationTarget: 0);
      final allocation = RotationPolicy.allocateOvertime(
        team: fixture.team,
        activeLineup: fixture.lineup,
        regulationTargets: fixture.targets,
        disqualified: const {},
        overtimeSeconds: 300,
        regulationCap: 2880,
      );
      expect(
        [
          for (final player in fixture.team.players)
            allocation.targetSeconds[player.id],
        ],
        [300, 300, 300, 300, 300, 0, 0, 0, 0],
      );
      expect(allocation.tacticalEnabled, isTrue);
    });

    test('depleted periods disable tactics and force continuer seconds', () {
      final fixture = overtimeFixture(
        benchPositions: const [Position.sg, Position.sf],
        regulationTarget: 0,
      );
      final disqualified = {
        fixture.team.players[3].id,
        fixture.team.players[4].id,
      };
      final targets = <PlayerId, int>{
        for (final player in fixture.team.players) player.id: 0,
      };
      for (final index in [0, 1, 2, 3, 4]) {
        targets[fixture.team.players[index].id] = 2880;
      }
      final allocation = RotationPolicy.allocateOvertime(
        team: fixture.team,
        activeLineup: fixture.lineup,
        regulationTargets: targets,
        disqualified: disqualified,
        overtimeSeconds: 300,
        regulationCap: 2880,
      );
      expect(allocation.tacticalEnabled, isFalse);
      var total = 0;
      for (final player in fixture.team.players) {
        total += allocation.targetSeconds[player.id]!;
      }
      expect(total, 1500);
      expect(allocation.targetSeconds[fixture.team.players[3].id], 300);
      expect(allocation.targetSeconds[fixture.team.players[4].id], 300);
    });
  });
}
