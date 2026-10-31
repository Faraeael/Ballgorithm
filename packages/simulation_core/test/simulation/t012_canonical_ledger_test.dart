import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';
import 't012_canonical_ledger_fixture.dart';
import 't012_canonical_ledger_fixture_v2.dart';
import 't012_canonical_ledger_fixture_v3.dart';

/// T012 primary fixture: league seed 20261028, game seed 42, standard rules.
const String pinnedInputFingerprint =
    'ad0fb1a7b33f284c06c904c58ca38c67a1f062b42ca3e4632ffdcf611604ef92';

/// SHA-256 over the UTF-8 bytes of [t012CanonicalLedgerV3Json].
const String pinnedLedgerDigest =
    '2baefd7d605ec65225c470f938fb45218db50d78a0d9ae75548e2e6646c276ac';

/// Published ledger digests for the same fixture configuration under simulation v3.
const Map<int, String> pinnedSeedDigests = {
  1: '074d2116645b899b427101e8aecf5b9cd0c693bad4839160bc19c0b69130ba76',
  99: 'e895fb231ee74ca9abe4321cc8867aae6ab1010baa7e58b3b8817524f3e1e2e8',
  20261029: '501c2e0e5e91c8490e8956a1b79f2141842bff9790b2e4bf44aa46b9e6ef80a5',
};

/// Raw-seed alias offset mandated by the normalized-seed contract.
const int seedAliasOffset = 4294967296;

String canonicalJson(GameResult result) => jsonEncode(result.ledger.toJson());

String sha256Hex(String value) => sha256.convert(utf8.encode(value)).toString();

String eventsJson(List<GameEvent> events) =>
    jsonEncode([for (final event in events) event.toJson()]);

/// Byte-exact comparison with a first-difference diagnostic.
void expectCanonicalBytes(String actual, String expected) {
  if (actual == expected) return;
  final limit = math.min(actual.length, expected.length);
  var offset = 0;
  while (offset < limit &&
      actual.codeUnitAt(offset) == expected.codeUnitAt(offset)) {
    offset++;
  }
  String window(String value) {
    final start = math.max(0, offset - 40);
    final end = math.min(value.length, offset + 40);
    return value.substring(start, end);
  }

  final sequencePattern = RegExp(r'"sequence":(\d+)');
  final prefix = actual.substring(0, math.min(offset, actual.length));
  final preceding = sequencePattern.allMatches(prefix);
  final location = preceding.isEmpty
      ? 'ledger header'
      : 'at or after event sequence #${preceding.last.group(1)}';
  fail(
    'canonical ledger differs at character offset $offset '
    '($location, '
    'expected length ${expected.length}, actual ${actual.length})\n'
    'expected: ${window(expected)}\n'
    'actual:   ${window(actual)}\n'
    'expected digest: $pinnedLedgerDigest\n'
    'actual digest:   ${sha256Hex(actual)}',
  );
}

GameInput rebuild(
  GameInput base, {
  League? league,
  ActiveLineup? homeLineup,
  int? seed,
  GameRules? rules,
}) => GameInput.create(
  gameId: base.gameId,
  league: league ?? base.league,
  homeTeamId: base.homeTeamId,
  awayTeamId: base.awayTeamId,
  homeLineup: homeLineup ?? base.homeLineup,
  awayLineup: base.awayLineup,
  seed: seed ?? base.seed,
  rules: rules ?? base.rules,
);

Map<String, Object?> leagueJson(GameInput input) => input.league.toJson();

/// Mutates one unrelated team's roster inside a league JSON snapshot.
void bumpTeamThreeStamina(Map<String, Object?> json) {
  final teams = json['teams']! as List<Object?>;
  final team = teams[2]! as Map<String, Object?>;
  final roster = team['roster']! as Map<String, Object?>;
  final players = roster['players']! as List<Object?>;
  final player = players.first! as Map<String, Object?>;
  final attributes = player['attributes']! as Map<String, Object?>;
  attributes['stamina'] = (attributes['stamina']! as int) + 1;
}

List<Object?> playerLine(PlayerBoxScore stats) => [
  stats.playerId,
  stats.teamId,
  stats.points,
  stats.fgm,
  stats.fga,
  stats.twoPm,
  stats.twoPa,
  stats.threePm,
  stats.threePa,
  stats.ftm,
  stats.fta,
  stats.assists,
  stats.oreb,
  stats.dreb,
  stats.rebounds,
  stats.turnovers,
  stats.steals,
  stats.blocks,
  stats.personalFouls,
];

List<Object?> teamLine(TeamBoxScore stats) => [
  stats.teamId,
  stats.points,
  stats.fgm,
  stats.fga,
  stats.twoPm,
  stats.twoPa,
  stats.threePm,
  stats.threePa,
  stats.ftm,
  stats.fta,
  stats.assists,
  stats.oreb,
  stats.dreb,
  stats.rebounds,
  stats.turnovers,
  stats.steals,
  stats.blocks,
  stats.personalFouls,
];

/// Platform-independent, ordered projection of a box score.
String canonicalBoxScore(GameBoxScore box) {
  final playerIds = box.players.keys.toList()..sort();
  final teamIds = box.teams.keys.toList()..sort();
  final periodKeys = box.periodPoints.keys.toList()..sort();
  return jsonEncode({
    'players': [for (final id in playerIds) playerLine(box.players[id]!)],
    'teams': [for (final id in teamIds) teamLine(box.teams[id]!)],
    'periods': [
      for (final id in periodKeys)
        [
          id,
          [
            for (final period in box.periodPoints[id]!.keys.toList()..sort())
              [period, box.periodPoints[id]![period]],
          ],
        ],
    ],
  });
}

/// Rejects any floating-point number token in canonical JSON.
///
/// A value-level check cannot work on the JS runtime, where every decoded
/// number is a `double`; the canonical byte stream is checked instead.
void expectNoFloats(String canonical) {
  final floatToken = RegExp(r'[\[:,]-?\d+\.\d+|[\[:,]-?\d+[eE][+-]?\d+');
  final match = floatToken.firstMatch(canonical);
  expect(
    match,
    isNull,
    reason: 'canonical JSON must not contain ${match?.group(0)}',
  );
}

void main() {
  group('canonical golden ledger', () {
    test('seed 42 reproduces the committed golden bytes and digest', () {
      final input = buildInput(seed: 42);
      final result = GameSimulator().simulate(input);
      final canonical = canonicalJson(result);

      expectCanonicalBytes(canonical, t012CanonicalLedgerV3Json);
      expect(
        utf8.encode(canonical),
        utf8.encode(t012CanonicalLedgerV3Json),
        reason: 'canonical UTF-8 byte stream must match the golden fixture',
      );

      final fingerprint = GameFingerprint.of(input);
      expect(fingerprint, pinnedInputFingerprint);
      expect(sha256Hex(canonical), pinnedLedgerDigest);
      expect(
        sha256Hex(t012CanonicalLedgerV3Json),
        pinnedLedgerDigest,
        reason: 'the golden fixture itself must hash to the pinned digest',
      );
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint), isTrue);

      expect(result.events.length, 805);
      expect(result.homeScore, 88);
      expect(result.awayScore, 100);
      expect(result.awayScore, greaterThan(result.homeScore));
      expect(result.periodsPlayed, 4);
      expect(result.homePeriodScores.values.fold(0, (a, b) => a + b), 88);
      expect(result.awayPeriodScores.values.fold(0, (a, b) => a + b), 100);

      expect(result.ledger.gameId, 'game-1');
      expect(result.ledger.inputFingerprint, pinnedInputFingerprint);
      expect(result.eventSchemaVersion, 2);
      expect(result.simulationVersion, 3);
      expect(result.rulesVersion, 2);
      expect(result.prngImplementationId, 'xorshift32-v1');
      expect(gameEventSchemaVersion, 2);
      expect(gameSimulationVersion, 3);
      expect(gameRulesVersion, 2);
      expect(gameFingerprintVersion, 2);
      expect(gameActionDurationModelVersion, 2);

      expect(result.events.first, isA<GameStarted>());
      expect(result.events.first.sequence, 1);
      expect(result.events.last, isA<GameEnded>());
      expect(result.events.last.sequence, 805);
      expect(
        result.events.whereType<GameStarted>().single.startingTeamId,
        input.startingTeamId.value,
      );
      expect(
        result.events.whereType<GameEnded>().single.finalPeriod,
        result.periodsPlayed,
      );
    });
  });

  group('golden mismatch diagnostics', () {
    Matcher failsWith(String fragment) => throwsA(
      isA<TestFailure>().having(
        (e) => e.message,
        'message',
        contains(fragment),
      ),
    );

    test('header differences are reported as header, not event 1', () {
      final broken = t012CanonicalLedgerV3Json.replaceFirst(
        '"eventSchemaVersion":2',
        '"eventSchemaVersion":3',
      );
      expect(
        () => expectCanonicalBytes(broken, t012CanonicalLedgerV3Json),
        failsWith('ledger header'),
      );
    });

    test('event differences report the containing sequence number', () {
      const marker = '"sequence":5,';
      final markerAt = t012CanonicalLedgerV3Json.indexOf(marker);
      expect(markerAt, greaterThan(0));
      const clockKey = '"gameClock":';
      final clockAt =
          t012CanonicalLedgerV3Json.indexOf(clockKey, markerAt) +
          clockKey.length;
      final digit = t012CanonicalLedgerV3Json[clockAt];
      final broken = t012CanonicalLedgerV3Json.replaceRange(
        clockAt,
        clockAt + 1,
        digit == '9' ? '0' : '${int.parse(digit) + 1}',
      );
      expect(
        () => expectCanonicalBytes(broken, t012CanonicalLedgerV3Json),
        failsWith('event sequence #5'),
      );
    });
  });

  group('golden ledger round trip', () {
    final input = buildInput(seed: 42);
    final result = GameSimulator().simulate(input);

    test('decode, re-encode and validate the committed golden ledger', () {
      final decoded =
          jsonDecode(t012CanonicalLedgerV3Json) as Map<String, Object?>;
      expectNoFloats(t012CanonicalLedgerV3Json);

      final ledger = GameEventLedger.fromJson(decoded);
      final reencoded = jsonEncode(ledger.toJson());
      expectCanonicalBytes(reencoded, t012CanonicalLedgerV3Json);
      expect(utf8.encode(reencoded), utf8.encode(t012CanonicalLedgerV3Json));
      expect(sha256Hex(reencoded), pinnedLedgerDigest);

      final validated = GameEventReducer.validate(input, ledger);
      expect(validated.state.ended, isTrue);
      expect(validated.state.started, isTrue);
      expect(validated.state.hasOpenPossession, isFalse);
      expect(validated.state.eventCount, ledger.events.length);
      expect(validated.state.period, result.periodsPlayed);
      expect(validated.events.first, isA<GameStarted>());
      expect(validated.events.last, isA<GameEnded>());

      expect(
        canonicalBoxScore(EventAccounting.aggregate(validated)),
        canonicalBoxScore(result.boxScore),
      );
    });

    test(
      'decoded ledger preserves free-throw, foul, rebound and turnover links',
      () {
        final ledger = GameEventLedger.fromJson(
          jsonDecode(t012CanonicalLedgerV3Json) as Map<String, Object?>,
        );
        final events = ledger.events;
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
            group.map((a) => a.attemptIndex),
            List.generate(size, (i) => i + 1),
          );
          expect(group.last.lastOfGroup, isTrue);
          expect(group.take(size - 1).every((a) => !a.lastOfGroup), isTrue);
          expect(group.map((a) => a.teamId).toSet(), hasLength(1));
          expect(group.map((a) => a.shooterId).toSet(), hasLength(1));
        }

        final andOnes = events.whereType<FieldGoalAttempt>().where(
          (e) => e.andOne,
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

        final nonSteal = events
            .whereType<Turnover>()
            .where((turnover) => turnover.reason == TurnoverReason.nonSteal)
            .toList();
        expect(nonSteal, isNotEmpty);
        for (final turnover in nonSteal) {
          expect(turnover.stolenById, isNull);
          expect(
            (turnover.toJson()['reason']),
            'nonSteal',
            reason: 'Amendment 001 wire reason must survive decoding',
          );
        }

        final steals = events.whereType<Turnover>().where(
          (turnover) => turnover.reason == TurnoverReason.steal,
        );
        for (final turnover in steals) {
          expect(turnover.stolenById, isNotNull);
        }

        final possessionStarts = events.whereType<PossessionStarted>().toList();
        expect(possessionStarts, isNotEmpty);
        String? open;
        for (final event in events) {
          if (event is PossessionStarted) {
            expect(
              open,
              isNull,
              reason: 'nested possession at ${event.sequence}',
            );
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
      },
    );
  });

  group('additional pinned seeds', () {
    test('published seed digests reproduce on this platform', () {
      for (final entry in pinnedSeedDigests.entries) {
        final input = buildInput(seed: entry.key);
        final result = GameSimulator().simulate(input);
        expect(
          sha256Hex(canonicalJson(result)),
          entry.value,
          reason: 'seed ${entry.key}',
        );
        final validated = GameEventReducer.validate(input, result.ledger);
        expect(validated.state.ended, isTrue);
        expect(result.homeScore, isNot(result.awayScore));
        expect(result.periodsPlayed, greaterThanOrEqualTo(4));
        expect(result.events.first, isA<GameStarted>());
        expect(result.events.last, isA<GameEnded>());
        expect(result.events.length, greaterThan(700));
        expect(
          EventAccounting.aggregate(
            validated,
          ).teams[input.homeTeamId.value]!.points,
          result.homeScore,
        );
        expect(
          EventAccounting.aggregate(
            validated,
          ).teams[input.awayTeamId.value]!.points,
          result.awayScore,
        );
      }
    });
  });

  group('input fingerprint identity', () {
    final base = buildInput(seed: 42);
    final baseline = GameFingerprint.of(base);
    final payload = GameFingerprint.canonicalPayload(base);

    test('canonical payload is versioned, ordered and fingerprint-stable', () {
      expect(baseline, pinnedInputFingerprint);
      expect(GameFingerprint.of(buildInput(seed: 42)), baseline);
      expect(
        GameFingerprint.canonicalJson(base),
        GameFingerprint.canonicalJson(base),
      );
      expect(GameFingerprint.canonicalJson(base), jsonEncode(payload));
      expect(payload.keys.toList(), [
        'fingerprintVersion',
        'league',
        'homeTeamId',
        'awayTeamId',
        'homeLineup',
        'awayLineup',
        'gameSeed',
        'normalizedSeed',
        'rules',
        'versions',
      ]);
      expect(payload['fingerprintVersion'], gameFingerprintVersion);
      expect(payload['homeLineup'], base.homeLineup.playerIds);
      expect(payload['awayLineup'], base.awayLineup.playerIds);
      expect(payload['gameSeed'], 42);
      expect(payload['normalizedSeed'], 42);
      final versions = payload['versions']! as Map<String, Object?>;
      expect(versions, {
        'simulation': gameSimulationVersion,
        'rules': gameRulesVersion,
        'eventSchema': gameEventSchemaVersion,
        'prng': 'xorshift32-v1',
        'coreEngine': coreEngineVersion,
        'leagueSchema': snapshotSchemaVersion,
      });
      expect(coreEngineVersion, '1.0.0');
      expect(snapshotSchemaVersion, 1);
    });

    test('unrelated roster changes alter the fingerprint', () {
      final json = leagueJson(base);
      bumpTeamThreeStamina(json);
      final mutated = League.fromJson(json);
      expect(
        GameFingerprint.of(rebuild(base, league: mutated)),
        isNot(baseline),
        reason: 'unrelated roster changes must alter the fingerprint by design',
      );
    });

    test('lineup membership and order are fingerprinted', () {
      final home = base.homeTeam;
      final pointGuards = home.players
          .where((player) => player.position == Position.pg)
          .toList();
      expect(pointGuards.length, greaterThan(1));
      final swapped = [...base.homeLineup.players];
      swapped[Position.pg.index] = pointGuards[1];
      final alternate = ActiveLineup.create(swapped);
      expect(alternate.playerIds, isNot(base.homeLineup.playerIds));
      expect(
        GameFingerprint.of(rebuild(base, homeLineup: alternate)),
        isNot(baseline),
      );

      final reordered = [...base.homeLineup.players];
      final first = reordered[0];
      reordered[0] = reordered[1];
      reordered[1] = first;
      expect(
        () => ActiveLineup.create(reordered),
        throwsA(isA<GameValidationException>()),
        reason: 'canonical PG,SG,SF,PF,C order is enforced, not reordered',
      );
    });

    test('raw seed, A1 configuration and rules values are fingerprinted', () {
      expect(GameFingerprint.of(rebuild(base, seed: 43)), isNot(baseline));
      expect(
        GameFingerprint.of(
          rebuild(
            base,
            rules: GameRules(phaseWeights: const [5000, 2500, 2500]),
          ),
        ),
        isNot(baseline),
      );
      expect(
        GameFingerprint.of(
          rebuild(
            base,
            rules: GameRules(
              phaseDurations: const [
                [3, 7],
                [5, 11],
                [10, 22],
              ],
            ),
          ),
        ),
        isNot(baseline),
      );
      expect(
        GameFingerprint.of(
          rebuild(base, rules: GameRules(bonusRegulationFouls: 4)),
        ),
        isNot(baseline),
      );
      expect(
        GameFingerprint.of(rebuild(base, rules: GameRules(maxOvertimes: 2))),
        isNot(baseline),
      );
    });

    test('rule variants that simulate still differ only by their inputs', () {
      final variant = rebuild(base, rules: GameRules(bonusRegulationFouls: 4));
      final variantResult = GameSimulator().simulate(variant);
      expect(
        variantResult.ledger.inputFingerprint,
        GameFingerprint.of(variant),
      );
      expect(
        GameEventReducer.validate(variant, variantResult.ledger).state.ended,
        isTrue,
      );
      expect(
        variantResult.ledger.inputFingerprint,
        isNot(pinnedInputFingerprint),
      );
    });
  });

  group('raw seed alias', () {
    test('s and s + 2^32 share events but not the fingerprint', () {
      final canonical = buildInput(seed: 42);
      final aliased = buildInput(seed: 42 + seedAliasOffset);
      expect(canonical.seed, 42);
      expect(aliased.seed, 42 + seedAliasOffset);
      expect(aliased.normalizedSeed, 42);
      expect(aliased.normalizedSeed, canonical.normalizedSeed);

      final canonicalFingerprint = GameFingerprint.of(canonical);
      final aliasedFingerprint = GameFingerprint.of(aliased);
      expect(canonicalFingerprint, isNot(aliasedFingerprint));

      final first = GameSimulator().simulate(canonical);
      final second = GameSimulator().simulate(aliased);
      expect(eventsJson(second.events), eventsJson(first.events));
      expect(second.homeScore, first.homeScore);
      expect(second.awayScore, first.awayScore);
      expect(second.periodsPlayed, first.periodsPlayed);

      final firstLedger = canonicalJson(first);
      final secondLedger = canonicalJson(second);
      expect(firstLedger, isNot(secondLedger));
      expect(
        firstLedger.replaceFirst(canonicalFingerprint, '<fingerprint>'),
        secondLedger.replaceFirst(aliasedFingerprint, '<fingerprint>'),
        reason: 'the ledger header differs only by the input fingerprint',
      );
      expect(second.ledger.inputFingerprint, aliasedFingerprint);
    });
  });

  group('historical golden fixture archives', () {
    test('v1 and v2 historical fixtures remain parseable as JSON', () {
      final v1 = jsonDecode(t012CanonicalLedgerJson) as Map<String, Object?>;
      expect(v1['gameSimulationVersion'], 1);
      expect(v1['events'], isA<List<Object?>>());

      final v2 = jsonDecode(t012CanonicalLedgerV2Json) as Map<String, Object?>;
      expect(v2['gameSimulationVersion'], 2);
      expect(v2['events'], isA<List<Object?>>());
    });
  });
}
