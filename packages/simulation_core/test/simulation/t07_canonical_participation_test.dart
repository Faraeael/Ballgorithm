// Historical M004 T07 canonical participation fixture (ledger kept in
// t07_canonical_participation_fixture.dart, byte-for-byte).
//
// M005 T04 turns the current build into a v6 reader: a v5 ledger is no longer
// decoded, it is rejected with the typed `unsupportedSimulationVersion` code
// (the event schema stays at version 3). Historical replay, round-trip,
// minutes and mutation evidence is executed against the accepted M004
// checkpoint 36bc3597 in an isolated read-only worktree. The current-version
// equivalents are pinned in t04_v6_fixture_test.dart. This file keeps the
// archived bytes and identity verifiable in the current suite.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 't07_canonical_participation_fixture.dart';

/// League seed 20261028, team-1 vs team-2, default lineups, game seed 42.
const String pinnedFingerprint =
    'e9b99720fa77ecd362e05029ebdba80ded67828f662f8b5f09e1edf8581ed3ed';

/// SHA-256 over the UTF-8 bytes of [t07CanonicalParticipationLedgerJson].
const String pinnedDigest =
    '9b4244fbacd2f615a76724ce3e9885f04160e2fd9463ce13871bbde8685b4b8a';

const int pinnedEventCount = 837;
const int pinnedSubstitutionCount = 4;
const int pinnedFirstSubstitutionSequence = 393;
const int pinnedHomeScore = 103;
const int pinnedAwayScore = 99;
const int pinnedPeriodsPlayed = 4;

/// SHA-256 of the first 392 canonical events, captured from the historical v4
/// build at c7f1d7a with the same normalized input.
const String pinnedV4PrefixDigest =
    '0fa93f89ea7125c5270e2e14324b122dec78deec3e512c0c6ddbf6a3a08d3b9b';

const List<int> pinnedSubstitutionSequences = [393, 511, 611, 805];

String sha256Hex(String value) => sha256.convert(utf8.encode(value)).toString();

Map<String, Object?> fixtureJson() =>
    jsonDecode(t07CanonicalParticipationLedgerJson) as Map<String, Object?>;

void main() {
  final json = fixtureJson();
  final events = json['events']! as List<Object?>;

  test('committed fixture keeps its pinned bytes, digest and v5 header', () {
    expect(sha256Hex(t07CanonicalParticipationLedgerJson), pinnedDigest);
    expect(jsonEncode(json), t07CanonicalParticipationLedgerJson);
    expect(
      utf8.encode(jsonEncode(json)),
      utf8.encode(t07CanonicalParticipationLedgerJson),
    );
    expect(json['eventSchemaVersion'], 3);
    expect(json['gameSimulationVersion'], 5);
    expect(json['gameRulesVersion'], 3);
    expect(json['prngImplementationId'], 'xorshift32-v1');
    expect(json['inputFingerprint'], pinnedFingerprint);
    expect(json['gameId'], 'game-1');
    expect(events, hasLength(pinnedEventCount));

    expect(gameSimulationVersion, 7);
    expect(gameFingerprintVersion, 5);
    expect(gameRulesVersion, 3);
    expect(gameEventSchemaVersion, 3);
    expect(gameActionDurationModelVersion, 2);
    expect(json['gameSimulationVersion'], isNot(gameSimulationVersion));
  });

  test(
    'the v6 reader rejects the archived ledger with the simulation code',
    () {
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
    },
  );

  test('archived participation markers stay as recorded', () {
    for (var index = 0; index < events.length; index++) {
      expect((events[index]! as Map<String, Object?>)['sequence'], index + 1);
    }
    final substitutions = [
      for (final event in events)
        if ((event! as Map<String, Object?>)['type'] == 'Substitution')
          event as Map<String, Object?>,
    ];
    expect(substitutions, hasLength(pinnedSubstitutionCount));
    expect([
      for (final sub in substitutions) sub['sequence'],
    ], pinnedSubstitutionSequences);
    expect(substitutions.every((sub) => sub['reason'] == 'foulOut'), isTrue);
    expect(substitutions.first['sequence'], pinnedFirstSubstitutionSequence);
    expect(substitutions.first['teamId'], 'team-2');
    expect(substitutions.first['playerOutId'], 'player-2-4');
    expect(substitutions.first['playerInId'], 'player-2-8');

    int points(String teamId) {
      var total = 0;
      for (final event in events) {
        final map = event! as Map<String, Object?>;
        if (map['teamId'] != teamId || map['made'] != true) continue;
        if (map['type'] == 'FieldGoalAttempt') {
          total += map['shotValue']! as int;
        } else if (map['type'] == 'FreeThrowAttempt') {
          total += 1;
        }
      }
      return total;
    }

    expect(points('team-1'), pinnedHomeScore);
    expect(points('team-2'), pinnedAwayScore);
    final ended = events.last! as Map<String, Object?>;
    expect(ended['type'], 'GameEnded');
    expect(ended['finalPeriod'], pinnedPeriodsPlayed);
  });

  test('the archived v4 prefix keeps its published digest', () {
    final prefix = events.take(pinnedFirstSubstitutionSequence - 1).toList();
    expect(prefix, hasLength(392));
    expect((events[392]! as Map<String, Object?>)['type'], 'Substitution');
    expect(sha256Hex(jsonEncode(prefix)), pinnedV4PrefixDigest);
  });
}
