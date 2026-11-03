import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Independent ranking oracle: reconstructs the active five, foul counts and
/// eligible bench from the event stream, then applies the frozen selection
/// contract. The chosen entrant is included in the candidate list.
({String expected, List<Player> eligible, List<Player> sameSlot}) _oracle(
  GameInput input,
  List<GameEvent> events,
  Substitution target,
) {
  final roster = {
    for (final team in input.league.teams)
      team.id.value: [for (final player in team.players) player],
  };
  final active = {
    for (final team in input.league.teams)
      team.id.value: [...input.lineupFor(team.id).playerIds],
  };
  final fouls = <String, int>{};
  for (final event in events) {
    if (event is PersonalFoul) {
      fouls[event.committingPlayerId] =
          (fouls[event.committingPlayerId] ?? 0) + 1;
    } else if (event is Substitution) {
      if (identical(event, target)) {
        final ids = active[event.teamId]!;
        final index = ids.indexOf(event.playerOutId);
        final slot = input.lineupFor(TeamId(event.teamId)).slotAt(index);
        final eligible = [
          for (final player in roster[event.teamId]!)
            if (!ids.contains(player.id.value) &&
                (fouls[player.id.value] ?? 0) < input.rules.foulOutLimit)
              player,
        ];
        final sameSlot = [
          for (final player in eligible)
            if (player.position == slot) player,
        ];
        final expected = sameSlot.isNotEmpty ? sameSlot.first : eligible.first;
        return (
          expected: expected.id.value,
          eligible: eligible,
          sameSlot: sameSlot,
        );
      }
      final ids = active[event.teamId]!;
      final index = ids.indexOf(event.playerOutId);
      if (index != -1) ids[index] = event.playerInId;
    }
  }
  throw StateError('target substitution is not in the event stream');
}

void main() {
  test('substitutions are foul-out only, lawful and positional', () {
    final input = buildInput(seed: 42);
    final result = GameSimulator().simulate(input);
    final substitutions = result.events.whereType<Substitution>().toList();
    expect(substitutions, isNotEmpty);

    final active = <String, List<String>>{
      input.homeTeamId.value: input.homeLineup.playerIds,
      input.awayTeamId.value: input.awayLineup.playerIds,
    };
    final fouls = <String, int>{};
    final roster = <String, List<Player>>{
      input.homeTeamId.value: input.homeTeam.players.toList(),
      input.awayTeamId.value: input.awayTeam.players.toList(),
    };

    for (final event in result.events) {
      if (event is PersonalFoul) {
        fouls[event.committingPlayerId] =
            (fouls[event.committingPlayerId] ?? 0) + 1;
      }
      if (event is! Substitution) continue;
      expect(event.reason, SubstitutionReason.foulOut);
      final ids = active[event.teamId]!;
      final index = ids.indexOf(event.playerOutId);
      expect(index, isNot(-1), reason: 'out player must be active');
      expect(ids, isNot(contains(event.playerInId)));
      expect(
        roster[event.teamId]!.map((player) => player.id.value),
        contains(event.playerInId),
      );
      expect(
        fouls[event.playerOutId] ?? 0,
        greaterThanOrEqualTo(input.rules.foulOutLimit),
      );
      // Deterministic replacement prefers the vacated slot position when any
      // eligible bench player shares it.
      final outPlayer = roster[event.teamId]!.firstWhere(
        (player) => player.id.value == event.playerOutId,
      );
      final eligibleSameSlot = [
        for (final player in roster[event.teamId]!)
          if (!ids.contains(player.id.value) &&
              player.id.value != event.playerInId &&
              (fouls[player.id.value] ?? 0) < input.rules.foulOutLimit &&
              player.position ==
                  input.lineupFor(TeamId(event.teamId)).slotAt(index))
            player.id.value,
      ];
      final incoming = roster[event.teamId]!.firstWhere(
        (player) => player.id.value == event.playerInId,
      );
      if (eligibleSameSlot.isNotEmpty) {
        expect(
          incoming.position,
          input.lineupFor(TeamId(event.teamId)).slotAt(index),
        );
      }
      ids[index] = event.playerInId;
      expect(outPlayer.id.value, event.playerOutId);
    }
  });

  test('a depleted roster continues without substitutions', () {
    final league = const LeagueGenerator().generate(
      const GenerationConfig(seed: 20261028, playersPerTeam: 5),
    );
    final home = league.teams.first;
    final away = league.teams[1];
    final input = GameInput.create(
      gameId: 'depleted',
      league: league,
      homeTeamId: home.id,
      awayTeamId: away.id,
      homeLineup: CourtLineup.defaultFor(home),
      awayLineup: CourtLineup.defaultFor(away),
      seed: 42,
      rules: GameRules.standard,
    );
    final result = GameSimulator().simulate(input);
    expect(result.events.whereType<Substitution>(), isEmpty);
    expect(result.events.whereType<PersonalFoul>(), isNotEmpty);
    expect(result.homeScore, isNot(result.awayScore));
  });

  test('replacement selection consumes zero PRNG draws', () {
    final input = buildInput(seed: 42);
    final traces = <ReplacementDrawTrace>[];
    final result = GameSimulator(onReplacementDraw: traces.add).simulate(input);
    final substitutions = result.events.whereType<Substitution>().toList();
    expect(substitutions, isNotEmpty, reason: 'real replacement required');
    expect(traces, isNotEmpty, reason: 'the observer must see real selections');

    // Every emitted foul-out substitution was chosen by an observed selection.
    final observed = [
      for (final trace in traces)
        if (trace.playerInId != null)
          '${trace.playerOutId}->${trace.playerInId}',
    ];
    for (final substitution in substitutions) {
      expect(
        observed,
        contains('${substitution.playerOutId}->${substitution.playerInId}'),
        reason: 'selection for ${substitution.playerOutId} was observed',
      );
    }

    // The actual ranking path consumed no underlying PRNG draws.
    expect(traces, hasLength(greaterThanOrEqualTo(substitutions.length)));
    for (final trace in traces) {
      expect(
        trace.draws,
        0,
        reason:
            'selection ${trace.playerOutId} -> ${trace.playerInId} drew '
            '${trace.draws} values',
      );
    }

    // Ranking: independent oracle, including same-slot tie-break by roster order.
    var sameSlotTies = 0;
    for (final substitution in substitutions) {
      final oracle = _oracle(input, result.events, substitution);
      expect(
        substitution.playerInId,
        oracle.expected,
        reason: 'ranking for ${substitution.playerOutId}',
      );
      if (oracle.sameSlot.length >= 2) sameSlotTies++;
      expect(
        traces.any(
          (trace) =>
              trace.playerOutId == substitution.playerOutId &&
              trace.playerInId == substitution.playerInId,
        ),
        isTrue,
      );
    }
    expect(
      sameSlotTies,
      greaterThanOrEqualTo(2),
      reason: 'fixture exercises the same-slot first-candidate tie-break',
    );

    // Behavioural determinism is retained alongside the draw-count evidence.
    final second = GameSimulator().simulate(input);
    expect(
      jsonEncode(second.ledger.toJson()),
      jsonEncode(result.ledger.toJson()),
    );
  });

  test('roster-order fallback selects the first eligible candidate', () {
    // Pinned fallback fixture: 7-player rosters, game seed 3. The first
    // disqualification is player-2-3 (SF); neither bench player is an SF.
    final league = const LeagueGenerator().generate(
      const GenerationConfig(seed: 20261028, playersPerTeam: 7),
    );
    final input = GameInput.create(
      gameId: 'ac12-fallback-3',
      league: league,
      homeTeamId: league.teams[0].id,
      awayTeamId: league.teams[1].id,
      homeLineup: CourtLineup.defaultFor(league.teams[0]),
      awayLineup: CourtLineup.defaultFor(league.teams[1]),
      seed: 3,
      rules: GameRules.standard,
    );
    final traces = <ReplacementDrawTrace>[];
    final result = GameSimulator(onReplacementDraw: traces.add).simulate(input);
    final substitutions = result.events.whereType<Substitution>().toList();
    expect(substitutions, isNotEmpty);
    final first = substitutions.first;

    final oracle = _oracle(input, result.events, first);
    expect(oracle.sameSlot, isEmpty, reason: 'no same-position candidate');
    expect(oracle.eligible.length, greaterThanOrEqualTo(2));
    expect(oracle.eligible.first.id.value, first.playerInId);
    expect(
      oracle.eligible.map((player) => player.id.value).toSet(),
      containsAll(<String>{first.playerInId, oracle.eligible[1].id.value}),
    );
    expect(oracle.eligible[1].id.value, isNot(first.playerInId));

    final trace = traces.firstWhere(
      (candidate) =>
          candidate.playerOutId == first.playerOutId &&
          candidate.playerInId == first.playerInId,
    );
    expect(trace.playerInId, oracle.expected);
    expect(trace.draws, 0);
  });
}
