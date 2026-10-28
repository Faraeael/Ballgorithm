import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _generator = LeagueGenerator();
const _config = GenerationConfig(seed: 20261028);

/// Structural snapshot without league/team ids, so seeds are compared on
/// generated content rather than on ids derived from the seed.
String _contentSignature(League league) => jsonEncode([
  for (final team in league.teams)
    [
      for (final player in team.players)
        {
          'position': player.position.shortName,
          'attributes': player.attributes.toJson(),
        },
    ],
]);

void main() {
  group('determinism', () {
    test('same seed and config yield identical snapshots', () {
      final first = _generator.generate(_config);
      final second = _generator.generate(_config);

      expect(jsonEncode(second.toJson()), jsonEncode(first.toJson()));
    });

    test('same seed preserves team and roster ordering', () {
      final first = _generator.generate(_config);
      final second = _generator.generate(_config);

      expect(
        second.teams.map((team) => team.id.value).toList(),
        first.teams.map((team) => team.id.value).toList(),
      );
      for (var t = 0; t < first.teams.length; t++) {
        expect(
          second.teams[t].players.map((player) => player.id.value).toList(),
          first.teams[t].players.map((player) => player.id.value).toList(),
        );
      }
    });

    test('different seeds yield distinct generated content', () {
      final signatures = {
        for (var seed = 1; seed <= 10; seed++)
          _contentSignature(_generator.generate(GenerationConfig(seed: seed))),
      };

      expect(signatures, hasLength(10));
    });

    test('same seed yields identical snapshot after JSON round trip', () {
      final league = _generator.generate(_config);
      final decoded = League.fromJson(
        jsonDecode(jsonEncode(league.toJson())) as Map<String, Object?>,
      );

      expect(jsonEncode(decoded.toJson()), jsonEncode(league.toJson()));
    });
  });

  group('league shape', () {
    late final League league = _generator.generate(_config);

    test('creates 8 teams with 96 distinct players', () {
      expect(league.teams, hasLength(8));

      final playerIds = [
        for (final team in league.teams)
          for (final player in team.players) player.id.value,
      ];
      expect(playerIds, hasLength(96));
      expect(playerIds.toSet(), hasLength(96));
    });

    test('assigns exactly 12 players per team', () {
      for (final team in league.teams) {
        expect(team.players, hasLength(12), reason: team.id.value);
        expect(team.roster.size, 12);
      }
    });

    test('every player id belongs to exactly one team', () {
      final counts = <String, int>{};
      for (final team in league.teams) {
        for (final player in team.players) {
          counts.update(
            player.id.value,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
      }

      expect(counts.keys, hasLength(96));
      expect(counts.values.every((count) => count == 1), isTrue);
    });

    test('each team covers all five positions', () {
      for (final team in league.teams) {
        expect(
          team.players.map((player) => player.position).toSet(),
          containsAll(Position.values),
          reason: team.id.value,
        );
      }
    });

    test('player names are unique within the league', () {
      final names = {
        for (final team in league.teams)
          for (final player in team.players) player.fullName,
      };

      expect(names, hasLength(96));
    });

    test('all attributes are integers within 0..100', () {
      for (final team in league.teams) {
        for (final player in team.players) {
          for (final entry in player.attributes.asMap.entries) {
            expect(
              entry.value,
              isA<int>().having((v) => v >= 0 && v <= 100, '0..100', isTrue),
              reason: '${player.id.value}.${entry.key}',
            );
          }
        }
      }
    });

    test('league passes aggregate validation', () {
      expect(LeagueValidator.validate(league).issues, isEmpty);
    });
  });

  group('config handling', () {
    test('honours team count and players per team', () {
      const config = GenerationConfig(seed: 4, teamCount: 3, playersPerTeam: 7);
      final league = _generator.generate(config);

      expect(league.teams, hasLength(3));
      for (final team in league.teams) {
        expect(team.players, hasLength(7));
        expect(
          team.players.map((player) => player.position).toSet(),
          containsAll(Position.values),
        );
      }
      expect(LeagueValidator.validate(league).isValid, isTrue);
    });

    test('records generation inputs in the snapshot', () {
      final json = _generator.generate(_config).toJson();
      final generation = json['generation'] as Map<String, Object?>;

      expect(generation['seed'], _config.seed);
      expect(generation['engineVersion'], coreEngineVersion);
      expect(generation['prng'], prngImplementationId);
      expect(json['schemaVersion'], snapshotSchemaVersion);
    });
  });
}
