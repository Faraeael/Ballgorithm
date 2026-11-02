import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _config = GenerationConfig(seed: 20261028);

void main() {
  late League league;
  late Team team;
  late CourtLineup defaultLineup;

  setUpAll(() {
    league = const LeagueGenerator().generate(_config);
    team = league.teams.first;
    defaultLineup = CourtLineup.defaultFor(team);
  });

  group('CourtLineup.defaultFor', () {
    test('maps the five players to canonical PG..C slots', () {
      expect(defaultLineup.slots, hasLength(5));
      expect([
        for (final slot in defaultLineup.slots) slot.slot,
      ], Position.values);
      for (var index = 0; index < 5; index++) {
        expect(
          defaultLineup.playerIdAtSlotIndex(index).value,
          defaultLineup.players[index].id.value,
        );
        expect(
          defaultLineup.slotIndexForPlayer(defaultLineup.players[index].id),
          index,
        );
        expect(
          defaultLineup.slotOf(defaultLineup.players[index].id),
          Position.values[index],
        );
        expect(
          defaultLineup.containsPlayer(defaultLineup.players[index].id),
          isTrue,
        );
      }
    });
  });

  group('CourtLineup.create', () {
    test('accepts a roster five whose slot positions are canonical', () {
      final court = CourtLineup.create(
        team: team,
        slotOrderedPlayers: defaultLineup.players,
      );
      expect(court.playerIds, defaultLineup.playerIds);
      expect(court.slots.map((slot) => slot.slot), Position.values);
    });

    test('accepts a player whose primary position differs from the slot', () {
      final players = [...defaultLineup.players];
      final swapped = [players[1], players[0], ...players.sublist(2)];
      final court = CourtLineup.create(team: team, slotOrderedPlayers: swapped);
      expect(court.playerIds.first, players[1].id.value);
      expect(court.slotOf(players[1].id), Position.pg);
      expect(court.players.first.position, Position.sg);
    });

    test('rejects a wrong slot count', () {
      expect(
        () => CourtLineup.create(
          team: team,
          slotOrderedPlayers: defaultLineup.players.take(4).toList(),
        ),
        throwsA(isA<GameValidationException>()),
      );
    });

    test('rejects a duplicate player', () {
      final players = [...defaultLineup.players];
      players[4] = players[0];
      expect(
        () => CourtLineup.create(team: team, slotOrderedPlayers: players),
        throwsA(isA<GameValidationException>()),
      );
    });

    test('rejects a player outside the roster', () {
      final outsider = league.teams[1].players.first;
      final players = [...defaultLineup.players]..[0] = outsider;
      expect(
        () => CourtLineup.create(team: team, slotOrderedPlayers: players),
        throwsA(isA<GameValidationException>()),
      );
    });

    test('reports an unknown player as not on court', () {
      final outsider = league.teams[1].players.first;
      expect(() => defaultLineup.slotOf(outsider.id), throwsArgumentError);
      expect(defaultLineup.containsPlayer(outsider.id), isFalse);
    });
  });

  test('stores canonical roster players, not caller-supplied objects', () {
    final original = defaultLineup.players.first;
    final altered = Player(
      id: original.id,
      firstName: original.firstName,
      lastName: original.lastName,
      position: original.position,
      attributes: PlayerAttributes.fromJson({
        ...original.attributes.toJson(),
        'insideScoring': 99,
        'threePoint': 99,
      }),
    );
    final players = [...defaultLineup.players]..[0] = altered;
    final court = CourtLineup.create(team: team, slotOrderedPlayers: players);
    final canonical = team.players.firstWhere(
      (player) => player.id.value == original.id.value,
    );
    expect(identical(court.players.first, canonical), isTrue);
    expect(
      court.players.first.attributes.insideScoring,
      canonical.attributes.insideScoring,
    );
  });

  test('serializes identity as ordered slot/player-id pairs', () {
    final slots = defaultLineup.toJson();
    expect(slots, hasLength(5));
    for (var index = 0; index < 5; index++) {
      final entry = slots[index];
      expect(entry['slot'], Position.values[index].shortName);
      expect(entry['playerId'], defaultLineup.playerIds[index]);
      expect(entry.keys, unorderedEquals(['slot', 'playerId']));
    }
  });
}
