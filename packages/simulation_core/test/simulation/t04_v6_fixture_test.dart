import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';
import 't012_canonical_ledger_fixture.dart';
import 't012_canonical_ledger_fixture_v2.dart';
import 't012_canonical_ledger_fixture_v3.dart';
import 't012_canonical_ledger_fixture_v4.dart';
import 't012_canonical_ledger_fixture_v5.dart';
import 't04_v6_canonical_fixture.dart';
import 't07_canonical_participation_fixture.dart';

/// SHA-256 over the UTF-8 bytes of [t04CanonicalLedgerV6Json].
const String pinnedV6Digest =
    '7f0c3d2962f05a66ff54ad42b3a8d53059871ceca31ac1402cbc5c14e024aa12';

/// v6 fingerprint of the planned fixture input.
const String pinnedV6Fingerprint =
    '493b7c4f70cb297de89c4d0dd7e5ccda1a6e3e53c7a9ea4096e5c115ca4d8103';

/// v6 fingerprint of the same league, lineups, seed and rules with a null plan.
const String pinnedNoPlanV6Fingerprint =
    '05e56d1154cbc695a84e248efbbba408c70cdd589da3b5b94c1458e1a636e520';

/// SHA-256 of the v5 no-plan event array, which equals the v5 fixture events.
const String pinnedNoPlanEventDigest =
    'c0332fb98b933b6183e46e1b2ae87eeb2a7078c67ff4aa74df05af6458f7ce02';

const int pinnedV6EventCount = 804;
const int pinnedV6SubstitutionCount = 26;
const int pinnedV6TacticalSubstitutionCount = 26;
const int pinnedV6HomeScore = 95;
const int pinnedV6AwayScore = 93;
const int pinnedV6PeriodsPlayed = 4;

/// Historical v5 evidence, unchanged by T04.
const String pinnedV5Digest =
    '9b4244fbacd2f615a76724ce3e9885f04160e2fd9463ce13871bbde8685b4b8a';
const String pinnedV5Fingerprint =
    'e9b99720fa77ecd362e05029ebdba80ded67828f662f8b5f09e1edf8581ed3ed';
const int pinnedV5EventCount = 837;
const List<int> pinnedV5SubstitutionSequences = [393, 511, 611, 805];

const int v6FirstSubstitutionIndex = 70;

/// Exactly derived from the pinned ledger: substitution intervals plus the
/// four 720-second periods. Every roster player has a row.
const Map<String, int> pinnedV6Seconds = {
  'player-1-1': 1645,
  'player-1-2': 1737,
  'player-1-3': 2074,
  'player-1-4': 1764,
  'player-1-5': 1435,
  'player-1-6': 1270,
  'player-1-7': 1380,
  'player-1-8': 2065,
  'player-1-9': 1030,
  'player-1-10': 0,
  'player-1-11': 0,
  'player-1-12': 0,
  'player-2-1': 1645,
  'player-2-2': 1737,
  'player-2-3': 1435,
  'player-2-4': 2074,
  'player-2-5': 1764,
  'player-2-6': 1030,
  'player-2-7': 1380,
  'player-2-8': 1270,
  'player-2-9': 2065,
  'player-2-10': 0,
  'player-2-11': 0,
  'player-2-12': 0,
};

/// Pinned result: home 95, away 93, periods 1-4.
const Map<int, int> pinnedV6HomePeriodScores = {1: 29, 2: 26, 3: 16, 4: 24};
const Map<int, int> pinnedV6AwayPeriodScores = {1: 17, 2: 25, 3: 27, 4: 24};

String sha256Hex(String value) => sha256.convert(utf8.encode(value)).toString();

String eventsJson(List<GameEvent> events) =>
    jsonEncode([for (final event in events) event.toJson()]);

Map<String, Object?> fixtureJson() =>
    jsonDecode(t04CanonicalLedgerV6Json) as Map<String, Object?>;

Map<String, Object?> copyOfFixture() =>
    jsonDecode(jsonEncode(fixtureJson())) as Map<String, Object?>;

List<Object?> fixtureEvents(Map<String, Object?> json) =>
    json['events']! as List<Object?>;

void expectNoFloats(String canonical) {
  final floatToken = RegExp(r'[\[:,]-?\d+\.\d+|[\[:,]-?\d+[eE][+-]?\d+');
  final match = floatToken.firstMatch(canonical);
  expect(
    match,
    isNull,
    reason: 'canonical JSON must not contain ${match?.group(0)}',
  );
}

/// The v6 canonical fixture input: league seed 20261028, team-1 vs team-2,
/// default lineups, balanced plans for both teams, game seed 42.
GameInput v6FixtureInput() {
  final base = buildInput(seed: 42);
  RotationPlan plan(RotationPreset preset) => RotationPlan(
    home: _teamPlan(base.homeTeam, base.homeLineup, base.rules, preset),
    away: _teamPlan(base.awayTeam, base.awayLineup, base.rules, preset),
  );
  return GameInput.create(
    gameId: base.gameId,
    league: base.league,
    homeTeamId: base.homeTeamId,
    awayTeamId: base.awayTeamId,
    homeLineup: base.homeLineup,
    awayLineup: base.awayLineup,
    seed: base.seed,
    rules: base.rules,
    rotationPlan: plan(RotationPreset.balanced),
  );
}

TeamRotationPlan _teamPlan(
  Team team,
  CourtLineup lineup,
  GameRules rules,
  RotationPreset preset,
) {
  final targets = RotationPlan.expandPreset(
    preset: preset,
    team: team,
    lineup: lineup,
    rules: rules,
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

/// Independent minutes oracle: walk the ledger with the clock deltas and the
/// substitution events, crediting the five on court.
Map<String, int> ledgerSeconds(GameInput input, List<GameEvent> events) {
  final seconds = <String, int>{};
  final active = <String, List<String>>{
    input.homeTeamId.value: input.homeLineup.playerIds.toList(),
    input.awayTeamId.value: input.awayLineup.playerIds.toList(),
  };
  var last = 0;
  for (final event in events) {
    var now = 0;
    for (var period = 1; period < event.period; period++) {
      now += input.rules.periodLength(period);
    }
    now += input.rules.periodLength(event.period) - event.gameClock;
    final delta = now - last;
    if (delta > 0) {
      for (final five in active.values) {
        for (final playerId in five) {
          seconds[playerId] = (seconds[playerId] ?? 0) + delta;
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
  return seconds;
}

Matcher throwsCode(GameValidationCode code) => throwsA(
  isA<GameValidationException>().having(
    (error) => error.codes,
    'codes',
    contains(code),
  ),
);

void main() {
  final input = v6FixtureInput();

  group('v6 canonical fixture', () {
    test('pinned bytes, digest and header', () {
      expect(sha256Hex(t04CanonicalLedgerV6Json), pinnedV6Digest);
      final json = fixtureJson();
      expect(jsonEncode(json), t04CanonicalLedgerV6Json);
      expectNoFloats(t04CanonicalLedgerV6Json);
      expect(json['eventSchemaVersion'], 3);
      expect(json['gameSimulationVersion'], 6);
      expect(json['gameRulesVersion'], 3);
      expect(json['prngImplementationId'], 'xorshift32-v1');
      expect(json['inputFingerprint'], pinnedV6Fingerprint);
      expect(json['gameId'], 'game-1');
      final events = fixtureEvents(json);
      expect(events, hasLength(pinnedV6EventCount));
    });

    test('the pinned plan reproduces the fixture and repeats exactly', () {
      expect(input.rotationPlan, isNotNull);
      expect(input.lineupFor(input.homeTeamId), input.homeLineup);
      expect(input.lineupFor(input.awayTeamId), input.awayLineup);
      final first = GameSimulator().simulate(input);
      expect(first.inputFingerprint, pinnedV6Fingerprint);
      expect(jsonEncode(first.ledger.toJson()), t04CanonicalLedgerV6Json);
      expect(sha256Hex(jsonEncode(first.ledger.toJson())), pinnedV6Digest);
      expect(first.homeScore, pinnedV6HomeScore);
      expect(first.awayScore, pinnedV6AwayScore);
      expect(first.periodsPlayed, pinnedV6PeriodsPlayed);
      final substitutions = first.events.whereType<Substitution>().toList();
      expect(substitutions, hasLength(pinnedV6SubstitutionCount));
      expect(
        substitutions.where((sub) => sub.reason == SubstitutionReason.tactical),
        hasLength(pinnedV6TacticalSubstitutionCount),
      );
      for (var run = 0; run < 5; run++) {
        final replay = GameSimulator().simulate(v6FixtureInput());
        expect(
          jsonEncode(replay.ledger.toJson()),
          t04CanonicalLedgerV6Json,
          reason: 'repeat $run must be byte identical',
        );
      }
    });

    test('replay validates, completes and reconciles minutes', () {
      final ledger = GameEventLedger.fromJson(fixtureJson());
      final validated = GameEventReducer.validate(input, ledger);
      final box = EventAccounting.aggregate(validated);

      expect(validated.state.ended, isTrue);
      expect(validated.events, hasLength(pinnedV6EventCount));
      for (var index = 0; index < validated.events.length; index++) {
        expect(validated.events[index].sequence, index + 1);
      }
      expect(validated.events.first, isA<GameStarted>());
      expect(validated.events.last, isA<GameEnded>());

      final substitutions = validated.events.whereType<Substitution>().toList();
      expect(substitutions, hasLength(pinnedV6SubstitutionCount));
      expect(
        substitutions.where((sub) => sub.reason == SubstitutionReason.tactical),
        hasLength(pinnedV6TacticalSubstitutionCount),
      );
      for (final sub in substitutions) {
        expect(sub.reason, SubstitutionReason.tactical);
        expect(sub.gameClock, greaterThan(0));
      }
      expect(substitutions.first.period, 1);
      expect(substitutions.first.gameClock, 435);
      expect(substitutions.first.teamId, 'team-1');
      expect(substitutions.first.playerOutId, 'player-1-1');
      expect(substitutions.first.playerInId, 'player-1-7');
      expect(
        [for (final sub in substitutions) sub.sequence],
        [
          71,
          72,
          110,
          111,
          142,
          143,
          200,
          201,
          263,
          264,
          301,
          302,
          375,
          376,
          427,
          428,
          486,
          487,
          611,
          612,
          668,
          669,
          724,
          725,
          774,
          775,
        ],
      );

      final oracle = ledgerSeconds(input, validated.events);
      for (final player in box.players.values) {
        expect(
          oracle[player.playerId] ?? 0,
          player.secondsPlayed,
          reason: 'secondsPlayed ${player.playerId}',
        );
      }
      for (final teamId in [input.homeTeamId.value, input.awayTeamId.value]) {
        final teamSeconds = box.players.values
            .where((player) => player.teamId == teamId)
            .fold<int>(0, (sum, player) => sum + player.secondsPlayed);
        expect(teamSeconds, 5 * 4 * 720);
      }
      expect(box.teams[input.homeTeamId.value]!.points, pinnedV6HomeScore);
      expect(box.teams[input.awayTeamId.value]!.points, pinnedV6AwayScore);
      expect(box.players, hasLength(24));
      for (final entry in pinnedV6Seconds.entries) {
        expect(
          box.players[entry.key]!.secondsPlayed,
          entry.value,
          reason: 'secondsPlayed ${entry.key}',
        );
      }
      expect(
        box.periodPoints[input.homeTeamId.value],
        pinnedV6HomePeriodScores,
      );
      expect(
        box.periodPoints[input.awayTeamId.value],
        pinnedV6AwayPeriodScores,
      );
    });

    test('decoded v6 ledger preserves free-throw, foul, rebound and '
        'turnover links', () {
      final events = GameEventLedger.fromJson(fixtureJson()).events;
      final bySequence = {for (final event in events) event.sequence: event};

      final groups = <String, List<FreeThrowAttempt>>{};
      for (final attempt in events.whereType<FreeThrowAttempt>()) {
        groups.putIfAbsent(attempt.groupId, () => []).add(attempt);
      }
      expect(groups, isNotEmpty);
      for (final group in groups.values) {
        final size = group.first.attemptsInGroup;
        expect(group.length, size);
        expect(
          group.map((attempt) => attempt.attemptIndex),
          List.generate(size, (index) => index + 1),
        );
        expect(group.last.lastOfGroup, isTrue);
        expect(group.take(size - 1).every((a) => !a.lastOfGroup), isTrue);
        expect(group.map((a) => a.teamId).toSet(), hasLength(1));
        expect(group.map((a) => a.shooterId).toSet(), hasLength(1));
      }

      final andOnes = events.whereType<FieldGoalAttempt>().where(
        (attempt) => attempt.andOne,
      );
      for (final shot in andOnes) {
        expect(shot.made, isTrue);
        final following =
            events.firstWhere(
                  (event) =>
                      event.sequence > shot.sequence &&
                      event is FreeThrowAttempt,
                )
                as FreeThrowAttempt;
        expect(following.teamId, shot.teamId);
        expect(following.shooterId, shot.shooterId);
        expect(following.attemptIndex, 1);
      }

      final rebounds = events.whereType<Rebound>().toList();
      expect(rebounds, isNotEmpty);
      for (final rebound in rebounds) {
        final missed = bySequence[rebound.missedEventSequence];
        expect(missed, isNotNull);
        expect(missed!.sequence, lessThan(rebound.sequence));
        if (missed is FieldGoalAttempt) {
          expect(missed.made, isFalse);
          if (rebound.offensive) expect(missed.teamId, rebound.teamId);
        } else if (missed is FreeThrowAttempt) {
          expect(missed.made, isFalse);
          expect(missed.lastOfGroup, isTrue);
        } else {
          fail('unexpected rebound source ${missed.type}');
        }
      }

      for (final turnover in events.whereType<Turnover>()) {
        switch (turnover.reason) {
          case TurnoverReason.steal:
            expect(turnover.stolenById, isNotNull);
          case TurnoverReason.nonSteal:
          case TurnoverReason.offensiveFoul:
          case TurnoverReason.shotClock:
            expect(turnover.stolenById, isNull);
        }
      }

      String? open;
      for (final event in events) {
        if (event is PossessionStarted) {
          expect(open, isNull, reason: 'nested possession ${event.sequence}');
          open = event.possessionId;
        } else if (event is PossessionEnded) {
          expect(event.possessionId, open);
          open = null;
        }
      }
      expect(open, isNull);

      var lastClock = -1;
      var period = 0;
      for (final event in events) {
        if (event is GameStarted || event is PeriodStarted) {
          period = event.period;
          lastClock = event.gameClock;
          continue;
        }
        expect(event.period, period);
        expect(event.gameClock, lessThanOrEqualTo(lastClock));
        lastClock = event.gameClock;
      }
    });
  });

  group('v6 canonical mutation rejection', () {
    GameValidationCode? rejectedCode(Map<String, Object?> json) {
      final ledger = GameEventLedger.fromJson(json);
      try {
        GameEventReducer.validate(input, ledger);
      } on GameValidationException catch (error) {
        return error.codes.first;
      }
      return null;
    }

    test('changed tactical player identity is rejected', () {
      final json = copyOfFixture();
      final events = fixtureEvents(json);
      (events[v6FirstSubstitutionIndex]!
              as Map<String, Object?>)['playerInId'] =
          'player-1-2';
      expect(rejectedCode(json), GameValidationCode.duplicateLineupPlayer);
    });

    test('illegal incoming player is rejected', () {
      final json = copyOfFixture();
      final events = fixtureEvents(json);
      (events[v6FirstSubstitutionIndex]!
              as Map<String, Object?>)['playerInId'] =
          'player-2-1';
      expect(rejectedCode(json), GameValidationCode.foreignLineupPlayer);
    });

    test('changed tactical clock is rejected', () {
      final json = copyOfFixture();
      final events = fixtureEvents(json);
      final sub = events[v6FirstSubstitutionIndex]! as Map<String, Object?>;
      sub['gameClock'] = (sub['gameClock']! as int) - 1;
      expect(rejectedCode(json), GameValidationCode.deadBallClockAdvanced);
    });

    test('changed tactical period is rejected', () {
      final json = copyOfFixture();
      final events = fixtureEvents(json);
      final sub = events[v6FirstSubstitutionIndex]! as Map<String, Object?>;
      sub['period'] = (sub['period']! as int) + 1;
      expect(rejectedCode(json), GameValidationCode.periodNotStarted);
    });

    test('illegal substitution reason is rejected', () {
      final json = copyOfFixture();
      final events = fixtureEvents(json);
      (events[v6FirstSubstitutionIndex]! as Map<String, Object?>)['reason'] =
          'foulOut';
      expect(rejectedCode(json), GameValidationCode.playerNotActive);
    });

    test('broken event sequence is rejected', () {
      final json = copyOfFixture();
      final events = fixtureEvents(json);
      (events[v6FirstSubstitutionIndex]! as Map<String, Object?>)['sequence'] =
          v6FirstSubstitutionIndex;
      expect(rejectedCode(json), GameValidationCode.invalidEventSequence);
    });

    test('mismatched ledger fingerprint is rejected', () {
      final json = copyOfFixture();
      json['inputFingerprint'] = List.filled(64, '0').join();
      expect(rejectedCode(json), GameValidationCode.invalidFingerprint);
    });

    test('unsupported event schema version is rejected', () {
      final json = copyOfFixture();
      json['eventSchemaVersion'] = 2;
      expect(
        () => GameEventLedger.fromJson(json),
        throwsCode(GameValidationCode.unsupportedEventSchemaVersion),
      );
    });
  });

  group('no-plan v5 equivalence', () {
    test('the v6 null-plan event array equals the pinned v5 array', () {
      final v5 =
          jsonDecode(t07CanonicalParticipationLedgerJson)
              as Map<String, Object?>;
      final v5Events = v5['events']! as List<Object?>;
      final result = GameSimulator().simulate(buildInput(seed: 42));

      expect(eventsJson(result.events), jsonEncode(v5Events));
      expect(sha256Hex(eventsJson(result.events)), pinnedNoPlanEventDigest);
      expect(v5Events, hasLength(pinnedV5EventCount));
      expect(result.events, hasLength(pinnedV5EventCount));

      final substitutions = result.events.whereType<Substitution>().toList();
      expect(substitutions, hasLength(4));
      expect([
        for (final sub in substitutions) sub.sequence,
      ], pinnedV5SubstitutionSequences);
      expect(
        substitutions.every((sub) => sub.reason == SubstitutionReason.foulOut),
        isTrue,
      );
      expect(result.homeScore, 103);
      expect(result.awayScore, 99);
      expect(result.periodsPlayed, 4);
      expect(result.inputFingerprint, pinnedNoPlanV6Fingerprint);
      expect(
        result.inputFingerprint,
        isNot(pinnedV5Fingerprint),
        reason: 'the fingerprint header moved to v6; events did not',
      );
    });

    test('null plans consume no rotation decisions', () {
      final traces = <RotationDrawTrace>[];
      final result = GameSimulator(
        onRotationDraw: traces.add,
      ).simulate(buildInput(seed: 42));
      expect(traces, isEmpty);
      expect(
        result.events.whereType<Substitution>().where(
          (sub) => sub.reason == SubstitutionReason.tactical,
        ),
        isEmpty,
      );
    });
  });

  group('version boundary', () {
    test('the v6 build rejects the v5 fixture with the simulation code', () {
      for (final json in [
        jsonDecode(t07CanonicalParticipationLedgerJson) as Map<String, Object?>,
        jsonDecode(t012CanonicalLedgerV5Json) as Map<String, Object?>,
      ]) {
        expect(
          () => GameEventLedger.fromJson(json),
          throwsA(
            isA<GameValidationException>()
                .having(
                  (error) => error.codes,
                  'codes',
                  contains(GameValidationCode.unsupportedSimulationVersion),
                )
                .having(
                  (error) => error.codes,
                  'codes',
                  isNot(
                    contains(GameValidationCode.unsupportedEventSchemaVersion),
                  ),
                )
                .having(
                  (error) => [for (final issue in error.issues) issue.path],
                  'paths',
                  contains('gameSimulationVersion'),
                ),
          ),
        );
      }
    });

    test('version identifiers follow the frozen M005 boundary', () {
      expect(gameSimulationVersion, 6);
      expect(gameFingerprintVersion, 4);
      expect(gameRulesVersion, 3);
      expect(gameEventSchemaVersion, 3);
      expect(gameActionDurationModelVersion, 2);
      expect(GameRules.standard.foulOutLimit, 6);
      expect(GameRules.standard.substitutionPolicyVersion, 1);
    });

    test('historical v1-v5 fixture bytes remain parseable and pinned', () {
      for (final fixture in [
        t012CanonicalLedgerJson,
        t012CanonicalLedgerV2Json,
        t012CanonicalLedgerV3Json,
        t012CanonicalLedgerV4Json,
        t012CanonicalLedgerV5Json,
        t07CanonicalParticipationLedgerJson,
      ]) {
        expect(jsonDecode(fixture), isA<Map<String, Object?>>());
      }
      expect(
        (jsonDecode(t012CanonicalLedgerV5Json)
            as Map<String, Object?>)['gameSimulationVersion'],
        5,
      );
      expect(
        (jsonDecode(t07CanonicalParticipationLedgerJson)
            as Map<String, Object?>)['gameSimulationVersion'],
        5,
      );
      expect(sha256Hex(t07CanonicalParticipationLedgerJson), pinnedV5Digest);
    });
  });
}
