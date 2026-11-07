import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';

Team subsetTeam(Team source, int size) => Team(
  id: source.id,
  name: source.name,
  abbreviation: source.abbreviation,
  roster: Roster(source.players.take(size).toList()),
);

CourtLineup firstFive(CourtLineup base, Team team) => CourtLineup.create(
  team: team,
  slotOrderedPlayers: team.players.take(5).toList(),
);

TeamRotationPlan planFromValues(
  Team team,
  RotationPreset preset,
  List<int> values,
) => TeamRotationPlan.create(
  team: team,
  preset: preset,
  targets: [
    for (var index = 0; index < team.players.length; index++)
      RotationTarget(playerId: team.players[index].id, seconds: values[index]),
  ],
);

TeamRotationPlan planFromMap(
  Team team,
  RotationPreset preset,
  Map<PlayerId, int> targetSeconds,
) => TeamRotationPlan.create(
  team: team,
  preset: preset,
  targets: [
    for (final entry in targetSeconds.entries)
      RotationTarget(playerId: entry.key, seconds: entry.value),
  ],
);

RotationPlan planFor(
  GameInput input,
  RotationPreset homePreset,
  RotationPreset awayPreset,
) {
  TeamRotationPlan expand(
    Team team,
    CourtLineup lineup,
    RotationPreset preset,
  ) {
    final expanded = RotationPlan.expandPreset(
      preset: preset,
      team: team,
      lineup: lineup,
      rules: input.rules,
    );
    return planFromMap(team, preset, expanded);
  }

  return RotationPlan(
    home: expand(input.homeTeam, input.homeLineup, homePreset),
    away: expand(input.awayTeam, input.awayLineup, awayPreset),
  );
}

GameInput rebuildWithPlan(GameInput base, RotationPlan? plan) =>
    GameInput.create(
      gameId: base.gameId,
      league: base.league,
      homeTeamId: base.homeTeamId,
      awayTeamId: base.awayTeamId,
      homeLineup: base.homeLineup,
      awayLineup: base.awayLineup,
      seed: base.seed,
      rules: base.rules,
      rotationPlan: plan,
    );

void main() {
  final base = buildInput();
  final home = base.homeTeam;
  final away = base.awayTeam;

  group('rotation plan contract', () {
    test('serializes canonically home-then-away in roster order', () {
      final plan = planFor(
        base,
        RotationPreset.balanced,
        RotationPreset.balanced,
      );
      final json =
          jsonDecode(jsonEncode(plan.toJson())) as Map<String, Object?>;
      expect(json.keys.toList(), ['home', 'away']);

      for (final entry in {'home': home, 'away': away}.entries) {
        final teamJson = json[entry.key]! as Map<String, Object?>;
        expect(teamJson.keys.toList(), ['preset', 'targets']);
        expect(teamJson['preset'], 'balanced');
        final targets = (teamJson['targets']! as List<Object?>)
            .cast<Map<String, Object?>>();
        expect(targets, hasLength(entry.value.players.length));
        expect(
          [for (final target in targets) target['playerId']],
          [for (final player in entry.value.players) player.id.value],
        );
      }
    });

    test('is independent of target insertion order', () {
      final expanded = RotationPlan.expandPreset(
        preset: RotationPreset.balanced,
        team: home,
        lineup: base.homeLineup,
        rules: base.rules,
      );
      final forward = planFromMap(home, RotationPreset.balanced, expanded);
      final reversed = planFromMap(
        home,
        RotationPreset.balanced,
        Map.fromEntries(expanded.entries.toList().reversed),
      );
      expect(reversed.toJson(), forward.toJson());
      expect(jsonEncode(reversed.toJson()), jsonEncode(forward.toJson()));
    });

    test(
      'rejects foreign, duplicate and negative targets with typed codes',
      () {
        final foreignId = away.players.first.id;
        expect(
          () => TeamRotationPlan.create(
            team: home,
            preset: RotationPreset.custom,
            targets: [RotationTarget(playerId: foreignId, seconds: 1)],
          ),
          throwsA(
            isA<GameValidationException>().having(
              (error) => error.codes,
              'codes',
              contains(GameValidationCode.foreignRotationPlayer),
            ),
          ),
        );
        final duplicate = home.players.first.id;
        expect(
          () => TeamRotationPlan.create(
            team: home,
            preset: RotationPreset.custom,
            targets: [
              RotationTarget(playerId: duplicate, seconds: 1),
              RotationTarget(playerId: duplicate, seconds: 2),
            ],
          ),
          throwsA(
            isA<GameValidationException>().having(
              (error) => error.codes,
              'codes',
              contains(GameValidationCode.duplicateRotationPlayer),
            ),
          ),
        );
        expect(
          () => TeamRotationPlan.create(
            team: home,
            preset: RotationPreset.custom,
            targets: [RotationTarget(playerId: duplicate, seconds: -1)],
          ),
          throwsA(
            isA<GameValidationException>().having(
              (error) => error.codes,
              'codes',
              contains(GameValidationCode.invalidRotationSeconds),
            ),
          ),
        );
      },
    );

    test('null plan is the explicit legacy mode', () {
      expect(base.rotationPlan, isNull);
      final payload = GameFingerprint.canonicalPayload(base);
      expect(payload.containsKey('rotationPlan'), isFalse);
    });

    test('re-bases a plan onto the league roster order', () {
      final shuffled = Team(
        id: home.id,
        name: home.name,
        abbreviation: home.abbreviation,
        roster: Roster(home.players.reversed.toList()),
      );
      final values = RotationPlan.expandPreset(
        preset: RotationPreset.balanced,
        team: home,
        lineup: base.homeLineup,
        rules: base.rules,
      );
      final plan = TeamRotationPlan.create(
        team: shuffled,
        preset: RotationPreset.balanced,
        targets: [
          for (final player in shuffled.players)
            RotationTarget(playerId: player.id, seconds: values[player.id]!),
        ],
      );
      final input = rebuildWithPlan(
        base,
        RotationPlan(
          home: plan,
          away: planFor(
            base,
            RotationPreset.balanced,
            RotationPreset.balanced,
          ).away,
        ),
      );
      final targets =
          (input.rotationPlan!.home.toJson()['targets']! as List<Object?>)
              .cast<Map<String, Object?>>();
      expect(
        [for (final target in targets) target['playerId']],
        [for (final player in home.players) player.id.value],
      );
    });
  });

  group('preset allocation', () {
    const standardVectors = {
      (RotationPreset.balanced, 5): [2880, 2880, 2880, 2880, 2880],
      (RotationPreset.balanced, 6): [2542, 2541, 2541, 2541, 2541, 1694],
      (RotationPreset.balanced, 7): [2274, 2274, 2274, 2274, 2274, 1515, 1515],
      (RotationPreset.balanced, 8): [
        2058,
        2058,
        2057,
        2057,
        2057,
        1371,
        1371,
        1371,
      ],
      (RotationPreset.balanced, 9): [
        1879,
        1879,
        1878,
        1878,
        1878,
        1252,
        1252,
        1252,
        1252,
      ],
      (RotationPreset.balanced, 12): [
        1879,
        1879,
        1878,
        1878,
        1878,
        1252,
        1252,
        1252,
        1252,
        0,
        0,
        0,
      ],
      (RotationPreset.starterHeavy, 5): [2880, 2880, 2880, 2880, 2880],
      (RotationPreset.starterHeavy, 6): [2667, 2667, 2667, 2667, 2666, 1066],
      (RotationPreset.starterHeavy, 7): [
        2483,
        2483,
        2483,
        2483,
        2482,
        993,
        993,
      ],
      (RotationPreset.starterHeavy, 8): [
        2323,
        2323,
        2323,
        2322,
        2322,
        929,
        929,
        929,
      ],
      (RotationPreset.starterHeavy, 9): [
        2323,
        2323,
        2323,
        2322,
        2322,
        929,
        929,
        929,
        0,
      ],
      (RotationPreset.starterHeavy, 12): [
        2323,
        2323,
        2323,
        2322,
        2322,
        929,
        929,
        929,
        0,
        0,
        0,
        0,
      ],
    };

    for (final entry in standardVectors.entries) {
      test(
        '${entry.key.$1.jsonValue} n=${entry.key.$2} matches the frozen vector',
        () {
          final team = subsetTeam(home, entry.key.$2);
          final lineup = firstFive(base.homeLineup, team);
          final expanded = RotationPlan.expandPreset(
            preset: entry.key.$1,
            team: team,
            lineup: lineup,
            rules: GameRules.standard,
          );
          expect([
            for (final player in team.players) expanded[player.id],
          ], entry.value);
          expect(expanded.values.fold(0, (a, b) => a + b), 14400);
          expect(expanded.values.every((seconds) => seconds <= 2880), isTrue);
        },
      );
    }

    for (final preset in [
      RotationPreset.balanced,
      RotationPreset.starterHeavy,
    ]) {
      for (var size = 5; size <= 12; size++) {
        test('${preset.jsonValue} n=$size conserves the team total', () {
          final team = subsetTeam(home, size);
          final lineup = firstFive(base.homeLineup, team);
          final expanded = RotationPlan.expandPreset(
            preset: preset,
            team: team,
            lineup: lineup,
            rules: GameRules.standard,
          );
          expect(expanded, hasLength(size));
          expect(expanded.values.fold(0, (a, b) => a + b), 14400);
          expect(expanded.values.every((seconds) => seconds <= 2880), isTrue);
          for (final starter in lineup.players) {
            expect(expanded[starter.id], greaterThan(0));
          }
        });
      }
    }

    test('short periods allocate exact integer seconds', () {
      final rules = GameRules(periodSeconds: 100);
      final team = subsetTeam(home, 6);
      final lineup = firstFive(base.homeLineup, team);
      final balanced = RotationPlan.expandPreset(
        preset: RotationPreset.balanced,
        team: team,
        lineup: lineup,
        rules: rules,
      );
      final starterHeavy = RotationPlan.expandPreset(
        preset: RotationPreset.starterHeavy,
        team: team,
        lineup: lineup,
        rules: rules,
      );
      expect(
        [for (final player in team.players) balanced[player.id]],
        [353, 353, 353, 353, 353, 235],
      );
      expect(
        [for (final player in team.players) starterHeavy[player.id]],
        [371, 371, 370, 370, 370, 148],
      );
      expect(balanced.values.fold(0, (a, b) => a + b), 2000);
      expect(starterHeavy.values.fold(0, (a, b) => a + b), 2000);
    });

    test('remainder goes to starters before roster-order reserves', () {
      final team = subsetTeam(home, 8);
      final starters = team.players.skip(3).toList();
      final lineup = CourtLineup.create(
        team: team,
        slotOrderedPlayers: starters,
      );
      final expanded = RotationPlan.expandPreset(
        preset: RotationPreset.balanced,
        team: team,
        lineup: lineup,
        rules: GameRules.standard,
      );
      expect(
        [for (final player in team.players) expanded[player.id]],
        [1371, 1371, 1371, 2058, 2058, 2057, 2057, 2057],
      );
    });

    test('five-player rosters receive the full cap and small rosters fail', () {
      final exact = subsetTeam(home, 5);
      final lineup = firstFive(base.homeLineup, exact);
      final expanded = RotationPlan.expandPreset(
        preset: RotationPreset.balanced,
        team: exact,
        lineup: lineup,
        rules: GameRules.standard,
      );
      expect(expanded.values, everyElement(2880));
      expect(expanded.values.fold(0, (a, b) => a + b), 14400);

      final small = subsetTeam(home, 4);
      expect(
        () => RotationPlan.expandPreset(
          preset: RotationPreset.balanced,
          team: small,
          lineup: lineup,
          rules: GameRules.standard,
        ),
        throwsA(
          isA<GameValidationException>().having(
            (error) => error.codes,
            'codes',
            contains(GameValidationCode.invalidRosterSizeForRotation),
          ),
        ),
      );
    });
  });

  group('GameInput plan validation', () {
    test('accepts balanced and custom plans for both teams', () {
      final balanced = rebuildWithPlan(
        base,
        planFor(base, RotationPreset.balanced, RotationPreset.balanced),
      );
      expect(balanced.rotationPlan, isNotNull);

      final customTargets = <PlayerId, int>{
        for (final player in home.players) player.id: 0,
      };
      for (final player in base.homeLineup.players) {
        customTargets[player.id] = 2880;
      }
      final custom = TeamRotationPlan.create(
        team: home,
        preset: RotationPreset.custom,
        targets: [
          for (final entry in customTargets.entries)
            RotationTarget(playerId: entry.key, seconds: entry.value),
        ],
      );
      final input = rebuildWithPlan(
        base,
        RotationPlan(
          home: custom,
          away: planFor(
            base,
            RotationPreset.balanced,
            RotationPreset.balanced,
          ).away,
        ),
      );
      expect(input.rotationPlan!.home.preset, RotationPreset.custom);
    });

    test('five-player leagues validate both team plans', () {
      final league = const LeagueGenerator().generate(
        const GenerationConfig(seed: 7, teamCount: 2, playersPerTeam: 5),
      );
      final fiveHome = league.teams.first;
      final fiveAway = league.teams[1];
      const cap = 2880;
      TeamRotationPlan full(Team team) => TeamRotationPlan.create(
        team: team,
        preset: RotationPreset.balanced,
        targets: [
          for (final player in team.players)
            RotationTarget(playerId: player.id, seconds: cap),
        ],
      );
      final input = GameInput.create(
        gameId: 'five-a-side',
        league: league,
        homeTeamId: fiveHome.id,
        awayTeamId: fiveAway.id,
        homeLineup: CourtLineup.defaultFor(fiveHome),
        awayLineup: CourtLineup.defaultFor(fiveAway),
        seed: 42,
        rules: GameRules.standard,
        rotationPlan: RotationPlan(home: full(fiveHome), away: full(fiveAway)),
      );
      expect(input.rotationPlan!.home.targetSeconds.values, everyElement(cap));
      expect(input.rotationPlan!.away.targetSeconds.values, everyElement(cap));
    });

    test('rejects missing, over-cap, wrong-total and zero-starter plans', () {
      final valid = planFor(
        base,
        RotationPreset.balanced,
        RotationPreset.balanced,
      );

      final missing = TeamRotationPlan.create(
        team: home,
        preset: RotationPreset.balanced,
        targets: [
          for (final player in home.players.skip(1))
            RotationTarget(
              playerId: player.id,
              seconds: valid.home.secondsFor(player.id),
            ),
        ],
      );
      expect(
        () => rebuildWithPlan(
          base,
          RotationPlan(home: missing, away: valid.away),
        ),
        throwsA(
          isA<GameValidationException>().having(
            (error) => error.codes,
            'codes',
            contains(GameValidationCode.missingRotationPlayer),
          ),
        ),
      );

      final overCapValues = [
        for (final player in home.players) valid.home.secondsFor(player.id),
      ];
      overCapValues[0] = 2881;
      overCapValues[5] = overCapValues[5] - 1;
      final overCap = planFromValues(
        home,
        RotationPreset.custom,
        overCapValues,
      );
      expect(
        () => rebuildWithPlan(
          base,
          RotationPlan(home: overCap, away: valid.away),
        ),
        throwsA(
          isA<GameValidationException>().having(
            (error) => error.codes,
            'codes',
            contains(GameValidationCode.invalidRotationSeconds),
          ),
        ),
      );

      final wrongTotalValues = [
        for (final player in home.players) valid.home.secondsFor(player.id),
      ];
      wrongTotalValues[5] = wrongTotalValues[5] + 1;
      final wrongTotal = planFromValues(
        home,
        RotationPreset.custom,
        wrongTotalValues,
      );
      expect(
        () => rebuildWithPlan(
          base,
          RotationPlan(home: wrongTotal, away: valid.away),
        ),
        throwsA(
          isA<GameValidationException>().having(
            (error) => error.codes,
            'codes',
            contains(GameValidationCode.invalidRotationTotal),
          ),
        ),
      );

      final zeroStarterValues = [0, 2880, 2880, 2880, 2880];
      while (zeroStarterValues.length < home.players.length) {
        zeroStarterValues.add(0);
      }
      zeroStarterValues[5] = 2880;
      final zeroStarter = planFromValues(
        home,
        RotationPreset.custom,
        zeroStarterValues,
      );
      expect(
        () => rebuildWithPlan(
          base,
          RotationPlan(home: zeroStarter, away: valid.away),
        ),
        throwsA(
          isA<GameValidationException>().having(
            (error) => error.codes,
            'codes',
            contains(GameValidationCode.starterTargetNotPositive),
          ),
        ),
      );
    });

    test('rejects a preset whose explicit targets disagree', () {
      final valid = planFor(
        base,
        RotationPreset.balanced,
        RotationPreset.balanced,
      );
      final values = [
        for (final player in home.players) valid.home.secondsFor(player.id),
      ];
      values[5] = values[5] + 1;
      values[6] = values[6] - 1;
      final mismatched = planFromValues(home, RotationPreset.balanced, values);
      expect(
        () => rebuildWithPlan(
          base,
          RotationPlan(home: mismatched, away: valid.away),
        ),
        throwsA(
          isA<GameValidationException>().having(
            (error) => error.codes,
            'codes',
            contains(GameValidationCode.rotationPresetMismatch),
          ),
        ),
      );
    });
  });

  group('fingerprints and versions', () {
    test('equivalent plans share one fingerprint; different plans differ', () {
      final first = rebuildWithPlan(
        base,
        planFor(base, RotationPreset.balanced, RotationPreset.balanced),
      );
      final second = rebuildWithPlan(
        base,
        planFor(base, RotationPreset.balanced, RotationPreset.balanced),
      );
      expect(GameFingerprint.of(first), GameFingerprint.of(second));

      final changed = rebuildWithPlan(
        base,
        planFor(base, RotationPreset.balanced, RotationPreset.starterHeavy),
      );
      expect(GameFingerprint.of(changed), isNot(GameFingerprint.of(first)));
      expect(GameFingerprint.of(first), isNot(GameFingerprint.of(base)));
    });

    test('the canonical payload carries lineups and the plan', () {
      final planned = rebuildWithPlan(
        base,
        planFor(base, RotationPreset.balanced, RotationPreset.balanced),
      );
      final payload = GameFingerprint.canonicalPayload(planned);
      expect(payload['homeLineup'], base.homeLineup.toJson());
      expect(payload['awayLineup'], base.awayLineup.toJson());
      expect(payload.containsKey('rotationPlan'), isTrue);
      expect(payload['rotationPlan'], planned.rotationPlan!.toJson());
    });

    test('version identifiers follow the frozen M005 boundary', () {
      expect(gameSimulationVersion, 6);
      expect(gameFingerprintVersion, 4);
      expect(gameRulesVersion, 3);
      expect(gameEventSchemaVersion, 3);
      expect(gameActionDurationModelVersion, 2);
      expect(coreEngineVersion, '1.0.0');
      expect(snapshotSchemaVersion, 1);
      expect(prngImplementationId, 'xorshift32-v1');
    });

    test('null plan preserves the legacy path without tactical swaps', () {
      for (final seed in [7, 15, 42]) {
        final legacy = GameSimulator().simulate(buildInput(seed: seed));
        expect(
          legacy.events.whereType<Substitution>().where(
            (event) => event.reason == SubstitutionReason.tactical,
          ),
          isEmpty,
          reason: 'seed $seed',
        );
      }
    });
  });
}
