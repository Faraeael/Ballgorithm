import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _generator = LeagueGenerator();
const _config = GenerationConfig(seed: 99);

League _league() => _generator.generate(_config);

League _leagueWithTeams(List<Team> teams, {GenerationConfig? config}) =>
    League.create(
      id: const LeagueId('league-test'),
      name: 'Test League',
      config: config ?? _config,
      teams: teams,
    );

Map<String, Object?> _json(League league) =>
    jsonDecode(jsonEncode(league.toJson())) as Map<String, Object?>;

Matcher _throwsCode(ValidationCode code) => throwsA(
  isA<DomainValidationException>().having(
    (e) => e.codes,
    'codes',
    contains(code),
  ),
);

void main() {
  group('generation config validation', () {
    test('rejects team counts outside the supported range', () {
      for (final teamCount in [0, 9]) {
        final result = GenerationConfig(
          seed: 1,
          teamCount: teamCount,
        ).validate();

        expect(
          result.codes,
          contains(ValidationCode.teamCountOutOfRange),
          reason: 'teamCount=$teamCount',
        );
      }
      expect(
        () =>
            _generator.generate(const GenerationConfig(seed: 1, teamCount: 0)),
        _throwsCode(ValidationCode.teamCountOutOfRange),
      );
    });

    test('rejects rosters too small to cover every position', () {
      final result = const GenerationConfig(
        seed: 1,
        playersPerTeam: 4,
      ).validate();

      expect(result.codes, contains(ValidationCode.playersPerTeamOutOfRange));
      expect(
        () => _generator.generate(
          const GenerationConfig(seed: 1, playersPerTeam: 4),
        ),
        _throwsCode(ValidationCode.playersPerTeamOutOfRange),
      );
    });

    test('rejects empty and mismatched engine versions', () {
      expect(
        const GenerationConfig(seed: 1, engineVersion: ' ').validate().codes,
        contains(ValidationCode.engineVersionEmpty),
      );
      expect(
        () => _generator.generate(
          const GenerationConfig(seed: 1, engineVersion: '9.9.9'),
        ),
        _throwsCode(ValidationCode.engineVersionMismatch),
      );
    });

    test('accepts the default configuration', () {
      expect(const GenerationConfig().validate().isValid, isTrue);
    });

    test('enforces unique-name capacity derived from the corpus', () {
      final perTeam = namePairCapacity ~/ 8;
      expect(perTeam * 8, lessThanOrEqualTo(namePairCapacity));

      final lastSupported = _generator.generate(
        GenerationConfig(seed: 2, playersPerTeam: perTeam),
      );
      expect(lastSupported.teams, hasLength(8));
      expect(lastSupported.teams.first.players, hasLength(perTeam));
      expect(
        lastSupported.teams
            .expand((team) => team.players)
            .map((player) => player.fullName)
            .toSet(),
        hasLength(namePairCapacity),
      );

      expect(
        () => _generator.generate(
          GenerationConfig(seed: 2, playersPerTeam: perTeam + 1),
        ),
        _throwsCode(ValidationCode.nameCapacityExceeded),
      );
    });
  });

  group('league validation', () {
    test('rejects a team count that disagrees with the config', () {
      final teams = _league().teams.take(7).toList();

      expect(
        () => _leagueWithTeams(teams),
        _throwsCode(ValidationCode.teamCountMismatch),
      );
    });

    test('rejects a roster with the wrong size', () {
      final league = _league();
      final shortRoster = Roster(league.teams.first.players.take(11).toList());
      final teams = [
        Team(
          id: league.teams.first.id,
          name: league.teams.first.name,
          abbreviation: league.teams.first.abbreviation,
          roster: shortRoster,
        ),
        ...league.teams.skip(1),
      ];

      expect(
        () => _leagueWithTeams(teams),
        _throwsCode(ValidationCode.rosterSizeMismatch),
      );
    });

    test('rejects duplicate team ids', () {
      final league = _league();
      final teams = [
        league.teams.first,
        Team(
          id: league.teams.first.id,
          name: 'Copycats',
          abbreviation: 'CPY',
          roster: league.teams[1].roster,
        ),
        ...league.teams.skip(2),
      ];

      expect(
        () => _leagueWithTeams(teams),
        _throwsCode(ValidationCode.duplicateTeamId),
      );
    });

    test('rejects a player appearing on two teams', () {
      final league = _league();
      final duplicated = league.teams.first.players.first;
      final secondPlayers = [...league.teams[1].players.take(11), duplicated];
      final teams = [
        league.teams.first,
        Team(
          id: league.teams[1].id,
          name: league.teams[1].name,
          abbreviation: league.teams[1].abbreviation,
          roster: Roster(secondPlayers),
        ),
        ...league.teams.skip(2),
      ];

      expect(
        () => _leagueWithTeams(teams),
        _throwsCode(ValidationCode.duplicatePlayerAcrossTeams),
      );
    });

    test('rejects a roster without position coverage', () {
      final league = _league();
      final template = league.teams.first.players.first;
      final allPointGuards = [
        for (var i = 0; i < 12; i++)
          Player(
            id: PlayerId('guard-$i'),
            firstName: 'Guard',
            lastName: '$i',
            position: Position.pg,
            attributes: template.attributes,
          ),
      ];
      final teams = [
        Team(
          id: league.teams.first.id,
          name: league.teams.first.name,
          abbreviation: league.teams.first.abbreviation,
          roster: Roster(allPointGuards),
        ),
        ...league.teams.skip(1),
      ];

      expect(
        () => _leagueWithTeams(teams),
        _throwsCode(ValidationCode.positionCoverageMissing),
      );
    });

    test('rejects duplicate player ids inside one roster', () {
      final player = _league().teams.first.players.first;

      expect(
        () => Roster([player, player]),
        _throwsCode(ValidationCode.duplicatePlayerId),
      );
    });

    test('rejects an empty league id', () {
      expect(
        () => League.create(
          id: const LeagueId(' '),
          name: 'Test League',
          config: _config,
          teams: _league().teams,
        ),
        _throwsCode(ValidationCode.leagueIdEmpty),
      );
    });
  });

  group('snapshot decoding', () {
    test('round trips a generated league', () {
      final league = _league();
      final decoded = League.fromJson(
        jsonDecode(jsonEncode(league.toJson())) as Map<String, Object?>,
      );

      expect(decoded.toJson(), league.toJson());
      expect(LeagueValidator.validate(decoded).isValid, isTrue);
    });

    test('rejects an unsupported schema version', () {
      final json = _json(_league())..['schemaVersion'] = 999;

      expect(
        () => League.fromJson(json),
        _throwsCode(ValidationCode.unsupportedSchemaVersion),
      );
    });

    test('rejects an out-of-range attribute', () {
      final json = _json(_league());
      final player =
          ((json['teams']! as List<Object?>).first
                  as Map<String, Object?>)['roster']!
              as Map<String, Object?>;
      final players = player['players']! as List<Object?>;
      final firstPlayer = players.first as Map<String, Object?>;
      final attributes = firstPlayer['attributes']! as Map<String, Object?>;
      attributes['threePoint'] = 150;

      expect(
        () => League.fromJson(json),
        _throwsCode(ValidationCode.attributeOutOfRange),
      );
    });

    test('rejects a missing attribute and an unknown position', () {
      final json = _json(_league());
      final team =
          (json['teams']! as List<Object?>).first as Map<String, Object?>;
      final players =
          (team['roster']! as Map<String, Object?>)['players']!
              as List<Object?>;
      final player = players.first as Map<String, Object?>;
      (player['attributes']! as Map<String, Object?>).remove('stamina');

      expect(
        () => League.fromJson(json),
        _throwsCode(ValidationCode.attributeMissing),
      );

      final second = _json(_league());
      final secondTeam =
          (second['teams']! as List<Object?>).first as Map<String, Object?>;
      final secondPlayers =
          (secondTeam['roster']! as Map<String, Object?>)['players']!
              as List<Object?>;
      (secondPlayers.first as Map<String, Object?>)['position'] = 'QB';

      expect(
        () => League.fromJson(second),
        _throwsCode(ValidationCode.unknownPosition),
      );
    });

    test('rejects malformed player records', () {
      final json = _json(_league());
      final team =
          (json['teams']! as List<Object?>).first as Map<String, Object?>;
      final players =
          (team['roster']! as Map<String, Object?>)['players']!
              as List<Object?>;
      players[0] = 'not a player';

      expect(
        () => League.fromJson(json),
        _throwsCode(ValidationCode.malformedJson),
      );
    });

    test('rejects duplicate players decoded from two teams', () {
      final json = _json(_league());
      final teams = json['teams']! as List<Object?>;
      final firstTeam = teams.first as Map<String, Object?>;
      final secondTeam = teams[1] as Map<String, Object?>;
      final firstPlayers =
          (firstTeam['roster']! as Map<String, Object?>)['players']!
              as List<Object?>;
      final secondPlayers =
          (secondTeam['roster']! as Map<String, Object?>)['players']!
              as List<Object?>;
      secondPlayers[secondPlayers.length - 1] = firstPlayers.first;

      expect(
        () => League.fromJson(json),
        _throwsCode(ValidationCode.duplicatePlayerAcrossTeams),
      );
    });

    test('rejects null, numeric and boolean team fields', () {
      for (final field in ['id', 'name', 'abbreviation']) {
        for (final bad in <Object?>[null, 12345, 1.5, true]) {
          final json = _json(_league());
          final teams = json['teams']! as List<Object?>;
          (teams.first as Map<String, Object?>)[field] = bad;

          expect(
            () => League.fromJson(json),
            _throwsCode(ValidationCode.malformedJson),
            reason: '$field=$bad',
          );
        }
      }
    });

    test('rejects invalid configuration decoded from a snapshot', () {
      final zeroTeams = _json(_league());
      zeroTeams['teams'] = <Object?>[];
      (zeroTeams['generation']! as Map<String, Object?>)['teamCount'] = 0;
      expect(
        () => League.fromJson(zeroTeams),
        _throwsCode(ValidationCode.teamCountOutOfRange),
      );

      final tinyRoster = _json(_league());
      (tinyRoster['generation']! as Map<String, Object?>)['playersPerTeam'] = 4;
      expect(
        () => League.fromJson(tinyRoster),
        _throwsCode(ValidationCode.playersPerTeamOutOfRange),
      );
    });

    test('rejects snapshots from an unsupported engine version', () {
      final json = _json(_league());
      (json['generation']! as Map<String, Object?>)['engineVersion'] = '9.9.9';

      expect(
        () => League.fromJson(json),
        _throwsCode(ValidationCode.engineVersionMismatch),
      );
    });
  });

  group('player attributes', () {
    test('accepts boundary values 0 and 100', () {
      final attributes = PlayerAttributes(
        insideScoring: 0,
        midrange: 100,
        threePoint: 0,
        freeThrow: 100,
        passing: 0,
        ballHandling: 100,
        perimeterDefense: 0,
        interiorDefense: 100,
        rebounding: 0,
        athleticism: 100,
        stamina: 0,
        basketballIQ: 100,
      );

      expect(attributes.asMap.values, containsAll([0, 100]));
    });

    test('rejects values outside 0..100', () {
      for (final invalid in [-1, 101]) {
        expect(
          () => PlayerAttributes(
            insideScoring: invalid,
            midrange: 50,
            threePoint: 50,
            freeThrow: 50,
            passing: 50,
            ballHandling: 50,
            perimeterDefense: 50,
            interiorDefense: 50,
            rebounding: 50,
            athleticism: 50,
            stamina: 50,
            basketballIQ: 50,
          ),
          _throwsCode(ValidationCode.attributeOutOfRange),
          reason: 'value $invalid',
        );
      }
    });

    test('rejects non-integer JSON attributes', () {
      final json = _json(_league());
      final team =
          (json['teams']! as List<Object?>).first as Map<String, Object?>;
      final players =
          (team['roster']! as Map<String, Object?>)['players']!
              as List<Object?>;
      final player = players.first as Map<String, Object?>;
      (player['attributes']! as Map<String, Object?>)['passing'] = 50.5;

      expect(
        () => League.fromJson(json),
        _throwsCode(ValidationCode.malformedJson),
      );
    });
  });
}
