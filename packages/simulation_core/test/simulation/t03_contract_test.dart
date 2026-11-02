import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';
import 't012_canonical_ledger_fixture_v4.dart';
import 't012_canonical_ledger_fixture_v5.dart';

void main() {
  group('Substitution event contract', () {
    final event = Substitution(
      sequence: 7,
      period: 2,
      gameClock: 431,
      shotClock: 12,
      teamId: 'team-1',
      playerOutId: 'player-1-2',
      playerInId: 'player-1-9',
      reason: SubstitutionReason.foulOut,
    );

    test('round-trips canonical JSON', () {
      final json = event.toJson();
      expect(json['type'], 'Substitution');
      expect(json['reason'], 'foulOut');
      final decoded = GameEvent.fromJson(json);
      expect(decoded, isA<Substitution>());
      final copy = decoded as Substitution;
      expect(copy.teamId, event.teamId);
      expect(copy.playerOutId, event.playerOutId);
      expect(copy.playerInId, event.playerInId);
      expect(copy.reason, SubstitutionReason.foulOut);
      expect(copy.toJson(), json);
    });

    test('accepts the tactical reason', () {
      final tactical = SubstitutionReason.parse('tactical', 'reason');
      expect(tactical, SubstitutionReason.tactical);
    });

    test('rejects an unknown reason with a typed error', () {
      final json = event.toJson()..['reason'] = 'injury';
      expect(
        () => GameEvent.fromJson(json),
        throwsA(
          isA<GameValidationException>().having(
            (e) => e.codes,
            'codes',
            contains(GameValidationCode.unsupportedEventType),
          ),
        ),
      );
    });

    test('rejects a missing player id', () {
      final json = event.toJson()..remove('playerInId');
      expect(
        () => GameEvent.fromJson(json),
        throwsA(isA<GameValidationException>()),
      );
    });

    test('reducer rejects a Substitution with no open window', () {
      final input = buildInput();
      final ledger = GameEventLedger(
        gameId: input.gameId,
        inputFingerprint: GameFingerprint.of(input),
        events: [
          GameStarted(
            sequence: 1,
            period: 1,
            gameClock: input.rules.periodSeconds,
            shotClock: null,
            homeTeamId: input.homeTeamId.value,
            awayTeamId: input.awayTeamId.value,
            startingTeamId: input.startingTeamId.value,
          ),
          PeriodStarted(
            sequence: 2,
            period: 1,
            gameClock: input.rules.periodSeconds,
            shotClock: null,
            startingTeamId: input.startingTeamId.value,
          ),
          PossessionStarted(
            sequence: 3,
            period: 1,
            gameClock: input.rules.periodSeconds,
            shotClock: input.rules.shotClockSeconds,
            possessionId: 'p1',
            offenseTeamId: input.startingTeamId.value,
          ),
          Substitution(
            sequence: 4,
            period: 1,
            gameClock: input.rules.periodSeconds,
            shotClock: input.rules.shotClockSeconds,
            teamId: input.homeTeamId.value,
            playerOutId: event.playerOutId,
            playerInId: event.playerInId,
            reason: SubstitutionReason.foulOut,
          ),
        ],
      );
      expect(
        () => GameEventReducer.validate(input, ledger),
        throwsA(
          isA<GameValidationException>().having(
            (e) => e.toString(),
            'message',
            contains('no substitution window is open'),
          ),
        ),
      );
    });
  });

  group('v5 versions and rules', () {
    test('version identifiers are the frozen T03 values', () {
      expect(gameSimulationVersion, 5);
      expect(gameRulesVersion, 3);
      expect(gameEventSchemaVersion, 3);
      expect(gameFingerprintVersion, 3);
      expect(gameActionDurationModelVersion, 2);
      expect(GameRules.standard.foulOutLimit, 6);
      expect(GameRules.standard.substitutionPolicyVersion, 1);
    });

    test('rules serialize and validate the new fields', () {
      final json = GameRules.standard.toJson();
      expect(json['foulOutLimit'], 6);
      expect(json['substitutionPolicyVersion'], 1);
      GameRules(foulOutLimit: 6).validate();
      for (final value in [0, 5, 7]) {
        expect(
          () => GameRules(foulOutLimit: value).validate(),
          throwsA(isA<GameValidationException>()),
          reason: 'foulOutLimit $value must be rejected',
        );
      }
      expect(
        () => GameRules(substitutionPolicyVersion: 2).validate(),
        throwsA(isA<GameValidationException>()),
      );
    });

    test('a v4 ledger header is rejected by the v5 reader', () {
      final input = buildInput();
      final json = GameEventLedger(
        gameId: input.gameId,
        inputFingerprint: GameFingerprint.of(input),
        events: const [],
      ).toJson();
      json['eventSchemaVersion'] = 2;
      expect(
        () => GameEventLedger.fromJson(json),
        throwsA(
          isA<GameValidationException>().having(
            (e) => e.codes,
            'codes',
            contains(GameValidationCode.unsupportedEventSchemaVersion),
          ),
        ),
      );
    });
  });

  test('fingerprint uses ordered slot/player-id pairs', () {
    final input = buildInput();
    final payload = GameFingerprint.canonicalPayload(input);
    for (final key in ['homeLineup', 'awayLineup']) {
      final pairs = payload[key]! as List<Object?>;
      expect(pairs, hasLength(5));
      for (var i = 0; i < 5; i++) {
        final pair = pairs[i]! as Map<String, Object?>;
        expect(pair.keys.toSet(), {'slot', 'playerId'});
        expect(pair['slot'], Position.values[i].shortName);
      }
    }
  });

  test('v5 event array matches the pinned v4 baseline exactly', () {
    Map<String, Object?> headerOf(String json) =>
        jsonDecode(json) as Map<String, Object?>;
    final v4 = headerOf(t012CanonicalLedgerV4Json);
    final v5 = headerOf(t012CanonicalLedgerV5Json);
    expect(v5['events'], v4['events']);
    expect(v5['gameId'], v4['gameId']);
    expect(v5['eventSchemaVersion'], isNot(v4['eventSchemaVersion']));
    expect(v5['inputFingerprint'], isNot(v4['inputFingerprint']));
  });

  test('altered lineup objects cannot change behaviour for the same ids', () {
    final base = buildInput(seed: 11);
    final home = base.homeTeam;
    final alteredPlayers = [
      for (final player in base.homeLineup.players)
        player.id.value == home.players.first.id.value
            ? Player(
                id: player.id,
                firstName: player.firstName,
                lastName: player.lastName,
                position: player.position,
                attributes: PlayerAttributes.fromJson({
                  ...player.attributes.toJson(),
                  'threePoint': 100,
                  'insideScoring': 100,
                }),
              )
            : player,
    ];
    final alteredLineup = CourtLineup.create(
      team: home,
      slotOrderedPlayers: alteredPlayers,
    );
    final alteredInput = GameInput.create(
      gameId: base.gameId,
      league: base.league,
      homeTeamId: base.homeTeamId,
      awayTeamId: base.awayTeamId,
      homeLineup: alteredLineup,
      awayLineup: base.awayLineup,
      seed: base.seed,
      rules: base.rules,
    );
    expect(
      GameFingerprint.of(alteredInput),
      GameFingerprint.of(base),
      reason: 'ids and league are identical, so the fingerprint must match',
    );
    final first = GameSimulator().simulate(alteredInput);
    final second = GameSimulator().simulate(base);
    expect(
      jsonEncode(first.ledger.toJson()),
      jsonEncode(second.ledger.toJson()),
      reason:
          'behaviour must come from the canonical roster, not the supplied '
          'objects',
    );
  });

  test('a foreign Team with same ids cannot inject altered ratings', () {
    final base = buildInput(seed: 13);
    final home = base.homeTeam;
    final alteredPlayers = [
      for (final player in home.players)
        player.id.value == base.homeLineup.playerIds.first
            ? Player(
                id: player.id,
                firstName: player.firstName,
                lastName: player.lastName,
                position: player.position,
                attributes: PlayerAttributes.fromJson({
                  ...player.attributes.toJson(),
                  'threePoint': 100,
                }),
              )
            : player,
    ];
    final fakeTeam = Team(
      id: home.id,
      name: home.name,
      abbreviation: home.abbreviation,
      roster: Roster(alteredPlayers),
    );
    final foreignLineup = CourtLineup.create(
      team: fakeTeam,
      slotOrderedPlayers: [
        for (final playerId in base.homeLineup.playerIds)
          alteredPlayers.firstWhere((player) => player.id.value == playerId),
      ],
    );
    final rebuilt = GameInput.create(
      gameId: base.gameId,
      league: base.league,
      homeTeamId: base.homeTeamId,
      awayTeamId: base.awayTeamId,
      homeLineup: foreignLineup,
      awayLineup: base.awayLineup,
      seed: base.seed,
      rules: base.rules,
    );
    expect(GameFingerprint.of(rebuilt), GameFingerprint.of(base));
    final canonical = base.homeTeam.players.firstWhere(
      (player) => player.id.value == base.homeLineup.playerIds.first,
    );
    expect(identical(rebuilt.homeLineup.players.first, canonical), isTrue);
    expect(
      jsonEncode(GameSimulator().simulate(rebuilt).ledger.toJson()),
      jsonEncode(GameSimulator().simulate(base).ledger.toJson()),
    );
  });

  test('injected models must agree with the input league roster', () {
    final input = buildInput(seed: 17);
    final altered = [
      for (final player in input.homeTeam.players)
        Player(
          id: player.id,
          firstName: player.firstName,
          lastName: player.lastName,
          position: player.position,
          attributes: PlayerAttributes.fromJson({
            ...player.attributes.toJson(),
            'insideScoring': 100,
          }),
        ),
    ];
    final injected = BasketballProbabilityModel(
      rules: input.rules,
      players: altered,
    );
    expect(
      () => GameSimulator(probabilityModel: injected).simulate(input),
      throwsA(
        isA<GameValidationException>().having(
          (e) => e.codes,
          'codes',
          contains(GameValidationCode.invalidRules),
        ),
      ),
    );

    final canonical = BasketballProbabilityModel(
      rules: input.rules,
      players: [
        for (final team in input.league.teams)
          for (final player in team.players) player,
      ],
    );
    expect(
      GameSimulator(probabilityModel: canonical).simulate(input).homeScore,
      GameSimulator().simulate(input).homeScore,
    );
    expect(
      GameSimulator(
        probabilityModel: BasketballProbabilityModel(),
      ).simulate(input).homeScore,
      GameSimulator().simulate(input).homeScore,
    );
  });

  test('the model roster view rejects every external mutation', () {
    final input = buildInput(seed: 19);
    final model = BasketballProbabilityModel(
      rules: input.rules,
      players: [
        for (final team in input.league.teams)
          for (final player in team.players) player,
      ],
    );
    final playerId = input.homeLineup.playerIds.first;
    final view = model.rosterPlayers;
    final canonical = view[playerId]!;
    final altered = Player(
      id: canonical.id,
      firstName: canonical.firstName,
      lastName: canonical.lastName,
      position: canonical.position,
      attributes: PlayerAttributes.fromJson({
        ...canonical.attributes.toJson(),
        'threePoint': 100,
      }),
    );

    expect(() => view['injected'] = altered, throwsUnsupportedError);
    expect(() => view[playerId] = altered, throwsUnsupportedError);
    expect(() => view.remove(playerId), throwsUnsupportedError);
    expect(view.clear, throwsUnsupportedError);
    expect(view, hasLength(input.league.teams.length * 12));
    expect(identical(view[playerId], canonical), isTrue);

    var attempted = 0;
    final result = GameSimulator(
      probabilityModel: model,
      onPhaseTrace: (_) {
        if (attempted > 0) return;
        attempted = 4;
        for (final action in <void Function()>[
          () => model.rosterPlayers['injected'] = altered,
          () => model.rosterPlayers[playerId] = altered,
          () => model.rosterPlayers.remove(playerId),
          () => model.rosterPlayers.clear(),
        ]) {
          expect(action, throwsUnsupportedError);
        }
      },
    ).simulate(input);
    expect(attempted, 4);
    expect(identical(model.rosterPlayers[playerId], canonical), isTrue);

    final control = GameSimulator().simulate(input);
    expect(result.inputFingerprint, control.inputFingerprint);
    expect(
      jsonEncode(result.ledger.toJson()),
      jsonEncode(control.ledger.toJson()),
    );
  });

  test('simulator emits only foul-out substitutions and they validate', () {
    final result = GameSimulator().simulate(buildInput(seed: 42));
    final substitutions = result.events.whereType<Substitution>().toList();
    expect(substitutions, isNotEmpty);
    expect(
      substitutions.every(
        (event) => event.reason == SubstitutionReason.foulOut,
      ),
      isTrue,
      reason: 'the T05 simulator never emits tactical substitutions',
    );
    expect(result.simulationVersion, 5);
    expect(result.eventSchemaVersion, 3);
  });

  test('a no-disqualification game contains no substitutions', () {
    final input = buildInput(seed: 15);
    final result = GameSimulator().simulate(input);
    expect(result.events.whereType<Substitution>(), isEmpty);
    expect(result.ledger.events.length, greaterThan(0));
    GameEventReducer.validate(input, result.ledger);
  });
}
