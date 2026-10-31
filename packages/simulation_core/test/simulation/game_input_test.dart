import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('GameInput validation', () {
    test('builds a valid input with canonical default lineups', () {
      final input = buildInput();
      expect(input.homeLineup.players, hasLength(5));
      expect(input.awayLineup.players, hasLength(5));
      expect(input.homeLineup.players.map((p) => p.position), Position.values);
      expect(input.homeTeamId, isNot(input.awayTeamId));
      expect(input.homeStarts, isTrue); // seed 42 is even.
    });

    test('normalizes seed zero to the documented fallback and starts away', () {
      final input = buildInput(seed: 0);
      expect(input.normalizedSeed, 0x9E3779B9);
      expect(input.homeStarts, isFalse);
      expect(input.startingTeamId, input.awayTeamId);
    });

    test('rejects the same team on both sides', () {
      final input = buildInput();
      expect(
        () => GameInput.create(
          gameId: 'x',
          league: input.league,
          homeTeamId: input.homeTeamId,
          awayTeamId: input.homeTeamId,
          homeLineup: input.homeLineup,
          awayLineup: input.homeLineup,
          seed: 1,
          rules: GameRules.standard,
        ),
        throwsA(
          isA<GameValidationException>().having(
            (e) => e.codes,
            'codes',
            contains(GameValidationCode.teamsNotDistinct),
          ),
        ),
      );
    });

    test('rejects foreign lineup players and cross-lineup duplicates', () {
      final input = buildInput();
      expect(
        () => GameInput.create(
          gameId: 'x',
          league: input.league,
          homeTeamId: input.homeTeamId,
          awayTeamId: input.awayTeamId,
          homeLineup: input.awayLineup,
          awayLineup: input.awayLineup,
          seed: 1,
          rules: GameRules.standard,
        ),
        throwsA(
          isA<GameValidationException>().having(
            (e) => e.codes,
            'codes',
            contains(GameValidationCode.foreignLineupPlayer),
          ),
        ),
      );
      expect(
        () => GameInput.create(
          gameId: 'x',
          league: input.league,
          homeTeamId: input.homeTeamId,
          awayTeamId: input.awayTeamId,
          homeLineup: input.homeLineup,
          awayLineup: input.homeLineup,
          seed: 1,
          rules: GameRules.standard,
        ),
        throwsA(
          isA<GameValidationException>().having(
            (e) => e.codes,
            'codes',
            contains(GameValidationCode.duplicatePlayerAcrossLineups),
          ),
        ),
      );
    });

    test('rejects invalid and unsupported rules', () {
      final input = buildInput();
      expect(
        () => GameInput.create(
          gameId: 'x',
          league: input.league,
          homeTeamId: input.homeTeamId,
          awayTeamId: input.awayTeamId,
          homeLineup: input.homeLineup,
          awayLineup: input.awayLineup,
          seed: 1,
          rules: GameRules(maxEvents: 0),
        ),
        throwsA(
          isA<GameValidationException>().having(
            (e) => e.codes,
            'codes',
            contains(GameValidationCode.invalidRules),
          ),
        ),
      );
      expect(
        () => GameRules(rulesVersion: 99).validate(),
        throwsA(
          isA<GameValidationException>().having(
            (e) => e.codes,
            'codes',
            contains(GameValidationCode.unsupportedRulesVersion),
          ),
        ),
      );
    });
  });

  group('ActiveLineup', () {
    test('rejects wrong order, duplicates and wrong size', () {
      final input = buildInput();
      final players = input.homeLineup.players;
      expect(
        () => ActiveLineup.create([players[1], players[0], ...players.skip(2)]),
        throwsA(
          isA<GameValidationException>().having(
            (e) => e.codes,
            'codes',
            contains(GameValidationCode.invalidLineupPositions),
          ),
        ),
      );
      expect(
        () => ActiveLineup.create([players[0], players[0], ...players.skip(2)]),
        throwsA(
          isA<GameValidationException>().having(
            (e) => e.codes,
            'codes',
            contains(GameValidationCode.duplicateLineupPlayer),
          ),
        ),
      );
      expect(
        () => ActiveLineup.create(players.take(4).toList()),
        throwsA(
          isA<GameValidationException>().having(
            (e) => e.codes,
            'codes',
            contains(GameValidationCode.invalidLineupSize),
          ),
        ),
      );
    });

    test('default selection requires every position', () {
      final input = buildInput();
      final team = input.homeTeam;
      final withoutCenter = team.players
          .where((player) => player.position != Position.c)
          .toList();
      final incomplete = Team(
        id: team.id,
        name: team.name,
        abbreviation: team.abbreviation,
        roster: Roster(withoutCenter),
      );
      expect(
        () => ActiveLineup.defaultFor(incomplete),
        throwsA(
          isA<GameValidationException>().having(
            (e) => e.codes,
            'codes',
            contains(GameValidationCode.invalidLineupPositions),
          ),
        ),
      );
    });
  });

  group('fingerprint', () {
    test('is stable for the same input and changes with seed or lineup', () {
      final input = buildInput();
      final same = buildInput();
      expect(GameFingerprint.of(input), GameFingerprint.of(same));
      expect(GameFingerprint.of(input), matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        GameFingerprint.of(input),
        'ad0fb1a7b33f284c06c904c58ca38c67a1f062b42ca3e4632ffdcf611604ef92',
      );

      final otherSeed = buildInput(seed: 43);
      expect(GameFingerprint.of(otherSeed), isNot(GameFingerprint.of(input)));

      final replacement = input.homeLineup.players.toList();
      final alternate = input.homeTeam.players.firstWhere(
        (player) =>
            player.position == Position.pg && player.id != replacement[0].id,
      );
      replacement[0] = alternate;
      final changedLineup = GameInput.create(
        gameId: input.gameId,
        league: input.league,
        homeTeamId: input.homeTeamId,
        awayTeamId: input.awayTeamId,
        homeLineup: ActiveLineup.create(replacement),
        awayLineup: input.awayLineup,
        seed: input.seed,
        rules: input.rules,
      );
      expect(
        GameFingerprint.of(changedLineup),
        isNot(GameFingerprint.of(input)),
      );
    });

    test('aliasing raw seeds share normalization but not fingerprint', () {
      final first = buildInput(seed: 7);
      final alias = buildInput(seed: 7 + 0x100000000);
      expect(alias.normalizedSeed, first.normalizedSeed);
      expect(GameFingerprint.of(alias), isNot(GameFingerprint.of(first)));
    });

    test('canonical payload contains no floating-point values', () {
      final encoded = GameFingerprint.canonicalJson(
        buildInput(),
      ).replaceAll(RegExp(r'"[^"]*"'), '""');
      expect(encoded, isNot(matches(RegExp(r'\d\.\d'))));
    });
  });
}
