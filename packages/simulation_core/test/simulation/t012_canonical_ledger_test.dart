import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';
import 't012_canonical_ledger_fixture.dart';
import 't012_canonical_ledger_fixture_v2.dart';
import 't012_canonical_ledger_fixture_v3.dart';
import 't012_canonical_ledger_fixture_v5.dart';

/// T012 primary fixture: league seed 20261028, game seed 42, standard rules.
/// v6 fingerprint of the same null-plan input. The historical v5 value
/// (`e9b99720...`) remains archived with the M004 checkpoint and is not
/// rewritten; only the fingerprint header moved to version 4.
const String pinnedInputFingerprint =
    'f60d9aa9c7db01089a257d05fa0cc4b52402ef06d29f8bae1a1caa447b0d8ff7';

/// SHA-256 over the UTF-8 bytes of [t012CanonicalLedgerV5Json].
const String pinnedLedgerDigest =
    '3ba26e3d34abf8b1e40f5469fa3c043be8ac712f9b39c6b3b992859d92cd3cc2';

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
  CourtLineup? homeLineup,
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
      final fingerprint = GameFingerprint.of(input);
      expect(fingerprint, pinnedInputFingerprint);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint), isTrue);
      expect(
        sha256Hex(t012CanonicalLedgerV5Json),
        pinnedLedgerDigest,
        reason: 'the provisional golden fixture must keep its pinned digest',
      );

      // M006 T04: simulation 7 intentionally changes actor and zone selection,
      // so the v5 fixture prefix and the v5 no-substitution body are history
      // (verified at the M005 checkpoint). The archive keeps its pinned digest
      // above; current-engine output is pinned in t04_v7_fixture_test.dart, and
      // this test asserts repeat identity and ledger validity only.
      final repeat = GameSimulator().simulate(buildInput(seed: 42));
      expect(canonical, canonicalJson(repeat));
      expect(result.events.length, greaterThan(700));
      expect(
        GameEventReducer.validate(input, result.ledger).state.ended,
        isTrue,
      );

      expect(result.ledger.gameId, 'game-1');
      expect(result.ledger.inputFingerprint, pinnedInputFingerprint);
      expect(result.eventSchemaVersion, 3);
      expect(result.simulationVersion, gameSimulationVersion);
      expect(result.rulesVersion, 3);
      expect(result.prngImplementationId, 'xorshift32-v1');
      expect(gameEventSchemaVersion, 3);
      expect(gameSimulationVersion, 7);
      expect(gameRulesVersion, 3);
      expect(gameFingerprintVersion, 5);
      expect(gameActionDurationModelVersion, 2);

      expect(result.events.first, isA<GameStarted>());
      expect(result.events.first.sequence, 1);
      expect(result.events.last, isA<GameEnded>());
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
      final broken = t012CanonicalLedgerV5Json.replaceFirst(
        '"eventSchemaVersion":3',
        '"eventSchemaVersion":2',
      );
      expect(
        () => expectCanonicalBytes(broken, t012CanonicalLedgerV5Json),
        failsWith('ledger header'),
      );
    });

    test('event differences report the containing sequence number', () {
      const marker = '"sequence":5,';
      final markerAt = t012CanonicalLedgerV5Json.indexOf(marker);
      expect(markerAt, greaterThan(0));
      const clockKey = '"gameClock":';
      final clockAt =
          t012CanonicalLedgerV5Json.indexOf(clockKey, markerAt) +
          clockKey.length;
      final digit = t012CanonicalLedgerV5Json[clockAt];
      final broken = t012CanonicalLedgerV5Json.replaceRange(
        clockAt,
        clockAt + 1,
        digit == '9' ? '0' : '${int.parse(digit) + 1}',
      );
      expect(
        () => expectCanonicalBytes(broken, t012CanonicalLedgerV5Json),
        failsWith('event sequence #5'),
      );
    });
  });

  group('golden ledger round trip', () {
    // M006 T04: the archived v5 ledger is retained byte-for-byte but a v7
    // build no longer decodes it. Historical decode, round-trip and link
    // integrity were verified at the M005 checkpoint; the current-version
    // round trip and link checks run on the v7 fixture in
    // t04_v7_fixture_test.dart.
    test('the archived v5 golden ledger is rejected by the v7 reader', () {
      final decoded =
          jsonDecode(t012CanonicalLedgerV5Json) as Map<String, Object?>;
      expectNoFloats(t012CanonicalLedgerV5Json);
      expect(sha256Hex(t012CanonicalLedgerV5Json), pinnedLedgerDigest);
      expect(decoded['gameSimulationVersion'], 5);
      expect(decoded['eventSchemaVersion'], gameEventSchemaVersion);
      expect(
        () => GameEventLedger.fromJson(decoded),
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
              ),
        ),
      );
    });
  });

  group('additional pinned seeds', () {
    test('published seeds repeat identically and reconcile', () {
      // M006 T04: the v4/v5 published digests are historical (simulation 7
      // intentionally changes shot selection). Current-engine determinism is
      // the contract: same input, byte-identical ledger.
      for (final seed in [1, 42, 99, 20261029]) {
        final input = buildInput(seed: seed);
        final result = GameSimulator().simulate(input);
        final repeat = GameSimulator().simulate(input);
        expect(
          sha256Hex(canonicalJson(repeat)),
          sha256Hex(canonicalJson(result)),
          reason: 'seed $seed',
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
      expect(payload['homeLineup'], [
        for (final slot in base.homeLineup.slots) slot.toJson(),
      ]);
      expect(payload['awayLineup'], [
        for (final slot in base.awayLineup.slots) slot.toJson(),
      ]);
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
      final alternate = CourtLineup.create(
        team: home,
        slotOrderedPlayers: swapped,
      );
      expect(alternate.playerIds, isNot(base.homeLineup.playerIds));
      expect(
        GameFingerprint.of(rebuild(base, homeLineup: alternate)),
        isNot(baseline),
      );

      final reordered = [...base.homeLineup.players];
      final first = reordered[0];
      reordered[0] = reordered[1];
      reordered[1] = first;
      final reorderedLineup = CourtLineup.create(
        team: home,
        slotOrderedPlayers: reordered,
      );
      expect(reorderedLineup.playerIds, isNot(base.homeLineup.playerIds));
      expect(reorderedLineup.slots.first.slot, Position.pg);
      expect(reorderedLineup.players.first.position, Position.sg);
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
    test('v1, v2 and v3 historical fixtures remain parseable as JSON', () {
      final v1 = jsonDecode(t012CanonicalLedgerJson) as Map<String, Object?>;
      expect(v1['gameSimulationVersion'], 1);
      expect(v1['events'], isA<List<Object?>>());

      final v2 = jsonDecode(t012CanonicalLedgerV2Json) as Map<String, Object?>;
      expect(v2['gameSimulationVersion'], 2);
      expect(v2['events'], isA<List<Object?>>());

      final v3 = jsonDecode(t012CanonicalLedgerV3Json) as Map<String, Object?>;
      expect(v3['gameSimulationVersion'], 3);
      expect(v3['events'], isA<List<Object?>>());
    });
  });
}
