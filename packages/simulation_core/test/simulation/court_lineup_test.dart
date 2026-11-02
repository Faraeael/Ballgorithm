import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/simulation/court_lineup.dart';
import 'package:test/test.dart';

const _config = GenerationConfig(seed: 20261028);

void main() {
  late League league;
  late Team team;
  late ActiveLineup active;

  setUpAll(() {
    league = const LeagueGenerator().generate(_config);
    team = league.teams.first;
    active = ActiveLineup.defaultFor(team);
  });

  group('CourtLineup.fromActiveLineup', () {
    test('maps the five players to canonical PG..C slots', () {
      final court = CourtLineup.fromActiveLineup(active);
      expect(court.slots, hasLength(5));
      expect([for (final slot in court.slots) slot.slot], Position.values);
      expect(court.players, active.players);
      for (var index = 0; index < 5; index++) {
        expect(court.playerAtSlotIndex(index), active.players[index]);
        expect(court.slotIndexForPlayer(active.players[index].id), index);
        expect(
          court.slotOfPlayer(active.players[index].id).slot,
          Position.values[index],
        );
        expect(court.containsPlayer(active.players[index].id), isTrue);
      }
    });
  });

  group('CourtLineup.create', () {
    test('accepts a canonical roster five', () {
      final court = CourtLineup.create(team, active.players);
      expect(court.players, active.players);
    });

    test('rejects a wrong slot count', () {
      expect(
        () => CourtLineup.create(team, active.players.take(4).toList()),
        throwsArgumentError,
      );
    });

    test('rejects a duplicate player', () {
      final players = [...active.players];
      players[4] = players[0];
      expect(() => CourtLineup.create(team, players), throwsArgumentError);
    });

    test('rejects a player outside the roster', () {
      final outsider = league.teams[1].players.first;
      final players = [...active.players]..[0] = outsider;
      expect(() => CourtLineup.create(team, players), throwsArgumentError);
    });

    test('rejects a mismatched slot position in T02', () {
      final players = [...active.players];
      players[0] = active.players[1];
      players[1] = active.players[0];
      expect(() => CourtLineup.create(team, players), throwsArgumentError);
    });

    test('reports an unknown player as not on court', () {
      final court = CourtLineup.create(team, active.players);
      expect(
        () => court.slotOfPlayer(league.teams[1].players.first.id),
        throwsArgumentError,
      );
      expect(court.containsPlayer(league.teams[1].players.first.id), isFalse);
    });
  });
}
