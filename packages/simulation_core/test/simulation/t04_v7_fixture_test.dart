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
import 't04_v7_canonical_fixture.dart';
import 't07_canonical_participation_fixture.dart';

/// SHA-256 over the UTF-8 bytes of [t04CanonicalLedgerV7Json].
const String pinnedV7Digest =
    '3e2eab7c01d7ece322dc5c7954fe08f71bc2baeb66be910981b09dac2e8a39ce';

/// v7 fingerprint of the planned fixture input.
const String pinnedV7Fingerprint =
    'd1b4b98d8b1042f2aebac4271825d20a43f53d12abb3213c4c0341f36fb66538';

/// v7 fingerprint of the same league, lineups, seed and rules with a null plan.
const String pinnedNoPlanV7Fingerprint =
    'f60d9aa9c7db01089a257d05fa0cc4b52402ef06d29f8bae1a1caa447b0d8ff7';

/// SHA-256 over the v7 null-plan canonical ledger.
const String pinnedNoPlanV7Digest =
    'db38c685f10e2b19980c52f68b323ae35e2932e2620cf36116b4e8340590f3ee';

const int pinnedV7EventCount = 823;
const int pinnedV7SubstitutionCount = 25;
const int pinnedV7TacticalSubstitutionCount = 24;
const int pinnedV7HomeScore = 108;
const int pinnedV7AwayScore = 89;
const int pinnedV7PeriodsPlayed = 4;

/// Historical v5 evidence, unchanged by T04.
const String pinnedV5Digest =
    '9b4244fbacd2f615a76724ce3e9885f04160e2fd9463ce13871bbde8685b4b8a';
const String pinnedV5Fingerprint =
    'e9b99720fa77ecd362e05029ebdba80ded67828f662f8b5f09e1edf8581ed3ed';
const int v7FirstSubstitutionIndex = 81;

/// Exactly derived from the pinned ledger: substitution intervals plus the
/// four 720-second periods. Every roster player has a row.
const Map<String, int> pinnedV7Seconds = {
  'player-1-1': 1942,
  'player-1-2': 1745,
  'player-1-3': 1977,
  'player-1-4': 1920,
  'player-1-5': 1291,
  'player-1-6': 1143,
  'player-1-7': 1439,
  'player-1-8': 1697,
  'player-1-9': 1246,
  'player-1-10': 0,
  'player-1-11': 0,
  'player-1-12': 0,
  'player-2-1': 1942,
  'player-2-2': 1745,
  'player-2-3': 1231,
  'player-2-4': 1977,
  'player-2-5': 1920,
  'player-2-6': 1081,
  'player-2-7': 1405,
  'player-2-8': 1143,
  'player-2-9': 1956,
  'player-2-10': 0,
  'player-2-11': 0,
  'player-2-12': 0,
};

/// Pinned result: home 108, away 89, periods 1-4.
const Map<int, int> pinnedV7HomePeriodScores = {1: 34, 2: 23, 3: 27, 4: 24};
const Map<int, int> pinnedV7AwayPeriodScores = {1: 18, 2: 24, 3: 20, 4: 27};

String sha256Hex(String value) => sha256.convert(utf8.encode(value)).toString();

Map<String, Object?> fixtureJson() =>
    jsonDecode(t04CanonicalLedgerV7Json) as Map<String, Object?>;

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
GameInput v7FixtureInput() {
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
  final input = v7FixtureInput();

  group('v7 canonical fixture', () {
    test('pinned bytes, digest and header', () {
      expect(sha256Hex(t04CanonicalLedgerV7Json), pinnedV7Digest);
      final json = fixtureJson();
      expect(jsonEncode(json), t04CanonicalLedgerV7Json);
      expectNoFloats(t04CanonicalLedgerV7Json);
      expect(json['eventSchemaVersion'], 3);
      expect(json['gameSimulationVersion'], 7);
      expect(json['gameRulesVersion'], 3);
      expect(json['prngImplementationId'], 'xorshift32-v1');
      expect(json['inputFingerprint'], pinnedV7Fingerprint);
      expect(json['gameId'], 'game-1');
      final events = fixtureEvents(json);
      expect(events, hasLength(pinnedV7EventCount));
    });

    test('the pinned plan reproduces the fixture and repeats exactly', () {
      expect(input.rotationPlan, isNotNull);
      expect(input.lineupFor(input.homeTeamId), input.homeLineup);
      expect(input.lineupFor(input.awayTeamId), input.awayLineup);
      final first = GameSimulator().simulate(input);
      expect(first.inputFingerprint, pinnedV7Fingerprint);
      expect(jsonEncode(first.ledger.toJson()), t04CanonicalLedgerV7Json);
      expect(sha256Hex(jsonEncode(first.ledger.toJson())), pinnedV7Digest);
      expect(first.homeScore, pinnedV7HomeScore);
      expect(first.awayScore, pinnedV7AwayScore);
      expect(first.periodsPlayed, pinnedV7PeriodsPlayed);
      final substitutions = first.events.whereType<Substitution>().toList();
      expect(substitutions, hasLength(pinnedV7SubstitutionCount));
      expect(
        substitutions.where((sub) => sub.reason == SubstitutionReason.tactical),
        hasLength(pinnedV7TacticalSubstitutionCount),
      );
      for (var run = 0; run < 5; run++) {
        final replay = GameSimulator().simulate(v7FixtureInput());
        expect(
          jsonEncode(replay.ledger.toJson()),
          t04CanonicalLedgerV7Json,
          reason: 'repeat $run must be byte identical',
        );
      }
    });

    test('replay validates, completes and reconciles minutes', () {
      final ledger = GameEventLedger.fromJson(fixtureJson());
      final validated = GameEventReducer.validate(input, ledger);
      final box = EventAccounting.aggregate(validated);

      expect(validated.state.ended, isTrue);
      expect(validated.events, hasLength(pinnedV7EventCount));
      for (var index = 0; index < validated.events.length; index++) {
        expect(validated.events[index].sequence, index + 1);
      }
      expect(validated.events.first, isA<GameStarted>());
      expect(validated.events.last, isA<GameEnded>());

      final substitutions = validated.events.whereType<Substitution>().toList();
      expect(substitutions, hasLength(pinnedV7SubstitutionCount));
      expect(
        substitutions.where((sub) => sub.reason == SubstitutionReason.tactical),
        hasLength(pinnedV7TacticalSubstitutionCount),
      );
      expect(
        substitutions.where((sub) => sub.reason == SubstitutionReason.foulOut),
        hasLength(1),
        reason: 'one foul-out substitution joins the tactical windows',
      );
      for (final sub in substitutions) {
        expect(sub.gameClock, greaterThan(0));
      }
      expect(substitutions.first.period, 1);
      expect(substitutions.first.gameClock, 456);
      expect(substitutions.first.teamId, 'team-1');
      expect(substitutions.first.playerOutId, 'player-1-1');
      expect(substitutions.first.playerInId, 'player-1-7');
      expect(
        [for (final sub in substitutions) sub.sequence],
        [
          82,
          83,
          124,
          125,
          167,
          168,
          226,
          227,
          268,
          269,
          306,
          307,
          425,
          426,
          488,
          489,
          520,
          521,
          579,
          580,
          672,
          673,
          734,
          758,
          768,
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
      expect(box.teams[input.homeTeamId.value]!.points, pinnedV7HomeScore);
      expect(box.teams[input.awayTeamId.value]!.points, pinnedV7AwayScore);
      expect(box.players, hasLength(24));
      for (final entry in pinnedV7Seconds.entries) {
        expect(
          box.players[entry.key]!.secondsPlayed,
          entry.value,
          reason: 'secondsPlayed ${entry.key}',
        );
      }
      expect(
        box.periodPoints[input.homeTeamId.value],
        pinnedV7HomePeriodScores,
      );
      expect(
        box.periodPoints[input.awayTeamId.value],
        pinnedV7AwayPeriodScores,
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

  group('v7 canonical mutation rejection', () {
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
      (events[v7FirstSubstitutionIndex]!
              as Map<String, Object?>)['playerInId'] =
          'player-1-2';
      expect(rejectedCode(json), GameValidationCode.duplicateLineupPlayer);
    });

    test('illegal incoming player is rejected', () {
      final json = copyOfFixture();
      final events = fixtureEvents(json);
      (events[v7FirstSubstitutionIndex]!
              as Map<String, Object?>)['playerInId'] =
          'player-2-1';
      expect(rejectedCode(json), GameValidationCode.foreignLineupPlayer);
    });

    test('changed tactical clock is rejected', () {
      final json = copyOfFixture();
      final events = fixtureEvents(json);
      final sub = events[v7FirstSubstitutionIndex]! as Map<String, Object?>;
      sub['gameClock'] = (sub['gameClock']! as int) - 1;
      expect(rejectedCode(json), GameValidationCode.deadBallClockAdvanced);
    });

    test('changed tactical period is rejected', () {
      final json = copyOfFixture();
      final events = fixtureEvents(json);
      final sub = events[v7FirstSubstitutionIndex]! as Map<String, Object?>;
      sub['period'] = (sub['period']! as int) + 1;
      expect(rejectedCode(json), GameValidationCode.periodNotStarted);
    });

    test('illegal substitution reason is rejected', () {
      final json = copyOfFixture();
      final events = fixtureEvents(json);
      (events[v7FirstSubstitutionIndex]! as Map<String, Object?>)['reason'] =
          'foulOut';
      expect(rejectedCode(json), GameValidationCode.playerNotActive);
    });

    test('broken event sequence is rejected', () {
      final json = copyOfFixture();
      final events = fixtureEvents(json);
      (events[v7FirstSubstitutionIndex]! as Map<String, Object?>)['sequence'] =
          v7FirstSubstitutionIndex;
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

  group('no-plan v7 determinism', () {
    test('the v7 null-plan output is deterministic and differs from v6', () {
      // M006 T04: simulation 7 intentionally changes shooter and zone
      // selection, so the v5 event array no longer matches. No v6/v7 ledger or
      // draw-count equality is claimed; only repeat identity is.
      final result = GameSimulator().simulate(buildInput(seed: 42));
      final repeat = GameSimulator().simulate(buildInput(seed: 42));
      final canonical = jsonEncode(result.ledger.toJson());

      expect(jsonEncode(repeat.ledger.toJson()), canonical);
      expect(sha256Hex(canonical), pinnedNoPlanV7Digest);
      expect(result.events, hasLength(805));
      expect(result.homeScore, 104);
      expect(result.awayScore, 106);
      expect(result.periodsPlayed, 4);
      expect(result.inputFingerprint, pinnedNoPlanV7Fingerprint);
      expect(
        result.inputFingerprint,
        isNot(pinnedV5Fingerprint),
        reason: 'the fingerprint payload moved to versions 7 / 5',
      );
      expect(
        GameEventReducer.validate(
          buildInput(seed: 42),
          result.ledger,
        ).state.ended,
        isTrue,
      );

      final substitutions = result.events.whereType<Substitution>().toList();
      expect(substitutions, hasLength(2));
      expect(
        substitutions.every((sub) => sub.reason == SubstitutionReason.foulOut),
        isTrue,
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
    test(
      'the v7 build rejects the v5 and v6 fixtures with the simulation code',
      () {
        for (final json in [
          jsonDecode(t07CanonicalParticipationLedgerJson)
              as Map<String, Object?>,
          jsonDecode(t012CanonicalLedgerV5Json) as Map<String, Object?>,
          jsonDecode(t04CanonicalLedgerV6Json) as Map<String, Object?>,
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
                      contains(
                        GameValidationCode.unsupportedEventSchemaVersion,
                      ),
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
      },
    );

    test('version identifiers follow the frozen M006 boundary', () {
      expect(gameSimulationVersion, 7);
      expect(gameFingerprintVersion, 5);
      expect(gameRulesVersion, 3);
      expect(gameEventSchemaVersion, 3);
      expect(gameActionDurationModelVersion, 2);
      expect(GameRules.standard.foulOutLimit, 6);
      expect(GameRules.standard.substitutionPolicyVersion, 1);
    });

    test('historical v1-v6 fixture bytes remain parseable and pinned', () {
      for (final fixture in [
        t012CanonicalLedgerJson,
        t012CanonicalLedgerV2Json,
        t012CanonicalLedgerV3Json,
        t012CanonicalLedgerV4Json,
        t012CanonicalLedgerV5Json,
        t04CanonicalLedgerV6Json,
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
      expect(
        (jsonDecode(t04CanonicalLedgerV6Json)
            as Map<String, Object?>)['gameSimulationVersion'],
        6,
      );
    });
  });
}
