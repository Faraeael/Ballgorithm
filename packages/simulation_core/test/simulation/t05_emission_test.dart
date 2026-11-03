import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';

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

    // Behavioural determinism is retained alongside the draw-count evidence.
    final second = GameSimulator().simulate(input);
    expect(
      jsonEncode(second.ledger.toJson()),
      jsonEncode(result.ledger.toJson()),
    );
  });
}
