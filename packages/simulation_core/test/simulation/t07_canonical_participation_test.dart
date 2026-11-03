import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';
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
/// build at c7f1d7a with the same normalized input. Divergence may only start
/// at the first `Substitution`.
const String pinnedV4PrefixDigest =
    '0fa93f89ea7125c5270e2e14324b122dec78deec3e512c0c6ddbf6a3a08d3b9b';

const List<int> pinnedSubstitutionSequences = [393, 511, 611, 805];

/// Exact seconds derived from ledger intervals. Entering at clock `c` yields
/// `c` seconds in that period plus every later full period.
const Map<String, int> pinnedSeconds = {
  'player-1-1': 2880,
  'player-1-10': 0,
  'player-1-11': 0,
  'player-1-12': 83,
  'player-1-2': 2797,
  'player-1-3': 1790,
  'player-1-4': 2132,
  'player-1-5': 748,
  'player-1-6': 1090,
  'player-1-7': 0,
  'player-1-8': 2880,
  'player-1-9': 0,
  'player-2-1': 2880,
  'player-2-10': 0,
  'player-2-11': 0,
  'player-2-12': 0,
  'player-2-2': 2880,
  'player-2-3': 0,
  'player-2-4': 1434,
  'player-2-5': 2880,
  'player-2-6': 0,
  'player-2-7': 0,
  'player-2-8': 1446,
  'player-2-9': 2880,
};

Map<String, Object?> fixtureJson() =>
    jsonDecode(t07CanonicalParticipationLedgerJson) as Map<String, Object?>;

Map<String, Object?> copyOfFixture() =>
    jsonDecode(jsonEncode(fixtureJson())) as Map<String, Object?>;

List<Object?> fixtureEvents(Map<String, Object?> json) =>
    json['events']! as List<Object?>;

String sha256Hex(String value) => sha256.convert(utf8.encode(value)).toString();

String eventsJson(List<GameEvent> events) =>
    jsonEncode([for (final event in events) event.toJson()]);

Matcher throwsCode(GameValidationCode code) => throwsA(
  isA<GameValidationException>().having(
    (error) => error.codes,
    'codes',
    contains(code),
  ),
);

void main() {
  final input = buildInput(seed: 42);

  group('canonical participation fixture', () {
    test('committed fixture keeps its pinned bytes, digest and header', () {
      expect(
        sha256Hex(t07CanonicalParticipationLedgerJson),
        pinnedDigest,
        reason: 'the committed fixture bytes are the pinned evidence',
      );
      final json = fixtureJson();
      expect(jsonEncode(json), t07CanonicalParticipationLedgerJson);
      expect(
        utf8.encode(jsonEncode(json)),
        utf8.encode(t07CanonicalParticipationLedgerJson),
      );
      expect(json['eventSchemaVersion'], gameEventSchemaVersion);
      expect(json['gameSimulationVersion'], gameSimulationVersion);
      expect(json['gameRulesVersion'], gameRulesVersion);
      expect(json['prngImplementationId'], 'xorshift32-v1');
      expect(json['inputFingerprint'], pinnedFingerprint);
      expect(json['gameId'], 'game-1');
      expect(gameEventSchemaVersion, 3);
      expect(gameSimulationVersion, 5);
      expect(gameRulesVersion, 3);
      expect(gameFingerprintVersion, 3);
      expect(gameActionDurationModelVersion, 2);
    });

    test('replay validates, completes and reconciles minutes', () {
      final ledger = GameEventLedger.fromJson(fixtureJson());
      final validated = GameEventReducer.validate(input, ledger);
      final box = EventAccounting.aggregate(validated);

      expect(validated.state.ended, isTrue);
      expect(ledger.inputFingerprint, pinnedFingerprint);
      expect(GameFingerprint.of(input), pinnedFingerprint);
      expect(validated.events, hasLength(pinnedEventCount));
      expect(validated.events.first, isA<GameStarted>());
      expect(validated.events.last, isA<GameEnded>());
      expect(validated.events.last.sequence, pinnedEventCount);
      for (var i = 0; i < validated.events.length; i++) {
        expect(validated.events[i].sequence, i + 1);
      }

      final substitutions = validated.events.whereType<Substitution>().toList();
      expect(substitutions, hasLength(pinnedSubstitutionCount));
      expect([
        for (final sub in substitutions) sub.sequence,
      ], pinnedSubstitutionSequences);
      expect(substitutions.first.sequence, pinnedFirstSubstitutionSequence);
      expect(
        substitutions.every((sub) => sub.reason == SubstitutionReason.foulOut),
        isTrue,
      );
      expect(substitutions.first.teamId, 'team-2');
      expect(substitutions.first.playerOutId, 'player-2-4');
      expect(substitutions.first.playerInId, 'player-2-8');

      expect(box.teams[input.homeTeamId.value]!.points, pinnedHomeScore);
      expect(box.teams[input.awayTeamId.value]!.points, pinnedAwayScore);
      expect(validated.state.period, pinnedPeriodsPlayed);
      expect(box.players, hasLength(24));
      for (final teamId in [input.homeTeamId, input.awayTeamId]) {
        final roster = input.league.teams
            .firstWhere((team) => team.id == teamId)
            .players;
        for (final player in roster) {
          expect(box.players[player.id.value], isNotNull);
        }
      }
      for (final entry in pinnedSeconds.entries) {
        expect(
          box.players[entry.key]!.secondsPlayed,
          entry.value,
          reason: 'secondsPlayed for ${entry.key}',
        );
      }
      for (final teamId in [input.homeTeamId.value, input.awayTeamId.value]) {
        final teamSeconds = box.players.values
            .where((player) => player.teamId == teamId)
            .fold<int>(0, (sum, player) => sum + player.secondsPlayed);
        expect(teamSeconds, 5 * 4 * 720);
        final periods = box.periodPoints[teamId]!;
        expect(periods.keys, unorderedEquals([1, 2, 3, 4]));
        expect(
          periods.values.fold<int>(0, (a, b) => a + b),
          box.teams[teamId]!.points,
        );
      }
    });

    test('replay derives minutes from the recorded substitution clocks', () {
      final box = account(
        input,
        GameEventLedger.fromJson(fixtureJson()).events,
      );
      // Entered period 2 at 0:06 and stayed: 6 + 720 + 720.
      expect(box.players['player-2-8']!.secondsPlayed, 6 + 720 + 720);
      // Left at the same clock: 720 + (720 - 6).
      expect(box.players['player-2-4']!.secondsPlayed, 720 + 720 - 6);
      // Left period 3 at 6:10: 720 + 720 + (720 - 370).
      expect(box.players['player-1-3']!.secondsPlayed, 720 + 720 + 350);
      // Entered at 6:10 period 3: 370 + 720.
      expect(box.players['player-1-6']!.secondsPlayed, 370 + 720);
      // Entered period 3 at 0:28: 28 + 720.
      expect(box.players['player-1-5']!.secondsPlayed, 28 + 720);
      // Entered period 4 at 1:23: 83.
      expect(box.players['player-1-12']!.secondsPlayed, 83);
    });

    test('20 repeated simulations reproduce the committed fixture', () {
      final fixture = t07CanonicalParticipationLedgerJson;
      final replayedBox = account(
        input,
        GameEventLedger.fromJson(fixtureJson()).events,
      );
      for (var run = 0; run < 20; run++) {
        final result = GameSimulator().simulate(input);
        final canonical = jsonEncode(result.ledger.toJson());
        expect(canonical, fixture, reason: 'canonical bytes, run $run');
        expect(sha256Hex(canonical), pinnedDigest, reason: 'digest, run $run');
        expect(result.inputFingerprint, pinnedFingerprint);
        expect(result.events, hasLength(pinnedEventCount));
        expect(
          result.events.whereType<Substitution>().length,
          pinnedSubstitutionCount,
        );
        expect(result.homeScore, pinnedHomeScore);
        expect(result.awayScore, pinnedAwayScore);
        expect(result.periodsPlayed, pinnedPeriodsPlayed);
        expect(
          result.homePeriodScores,
          replayedBox.periodPoints[input.homeTeamId.value],
        );
        expect(
          result.awayPeriodScores,
          replayedBox.periodPoints[input.awayTeamId.value],
        );
        for (final entry in pinnedSeconds.entries) {
          expect(
            result.boxScore.players[entry.key]!.secondsPlayed,
            entry.value,
            reason: 'secondsPlayed ${entry.key}, run $run',
          );
        }
        for (final id in result.boxScore.players.keys) {
          final fresh = result.boxScore.players[id]!;
          final replay = replayedBox.players[id]!;
          expect(
            [
              fresh.points,
              fresh.fgm,
              fresh.fga,
              fresh.rebounds,
              fresh.assists,
              fresh.turnovers,
              fresh.steals,
              fresh.blocks,
              fresh.personalFouls,
              fresh.secondsPlayed,
            ],
            [
              replay.points,
              replay.fgm,
              replay.fga,
              replay.rebounds,
              replay.assists,
              replay.turnovers,
              replay.steals,
              replay.blocks,
              replay.personalFouls,
              replay.secondsPlayed,
            ],
            reason: 'player statistics $id, run $run',
          );
        }
        for (final teamId in result.boxScore.teams.keys) {
          expect(
            result.boxScore.teams[teamId]!.points,
            replayedBox.teams[teamId]!.points,
            reason: 'team points $teamId, run $run',
          );
        }
      }
    });

    test('seed-42 prefix matches the historical v4 event array', () {
      final events = GameEventLedger.fromJson(fixtureJson()).events;
      final prefix = events.take(pinnedFirstSubstitutionSequence - 1).toList();
      expect(prefix, hasLength(392));
      expect(events[392], isA<Substitution>());
      expect(sha256Hex(eventsJson(prefix)), pinnedV4PrefixDigest);
    });
  });

  group('canonical mutation rejection', () {
    GameValidationCode? rejectedCode(Map<String, Object?> json) {
      final ledger = GameEventLedger.fromJson(json);
      try {
        GameEventReducer.validate(input, ledger);
      } on GameValidationException catch (error) {
        return error.codes.first;
      }
      return null;
    }

    test('changed substitution player identity is rejected', () {
      final json = copyOfFixture();
      final events = fixtureEvents(json);
      // player-2-5 is already on court when the substitution occurs.
      (events[392]! as Map<String, Object?>)['playerInId'] = 'player-2-5';
      expect(rejectedCode(json), GameValidationCode.duplicateLineupPlayer);
    });

    test('illegal incoming player is rejected', () {
      final json = copyOfFixture();
      final events = fixtureEvents(json);
      (events[392]! as Map<String, Object?>)['playerInId'] = 'player-1-12';
      expect(rejectedCode(json), GameValidationCode.foreignLineupPlayer);
    });

    test('changed substitution clock is rejected', () {
      final json = copyOfFixture();
      final events = fixtureEvents(json);
      final sub = events[392]! as Map<String, Object?>;
      sub['gameClock'] = (sub['gameClock']! as int) - 1;
      expect(rejectedCode(json), GameValidationCode.deadBallClockAdvanced);
    });

    test('changed substitution period is rejected', () {
      final json = copyOfFixture();
      final events = fixtureEvents(json);
      final sub = events[392]! as Map<String, Object?>;
      sub['period'] = (sub['period']! as int) + 1;
      expect(rejectedCode(json), GameValidationCode.periodNotStarted);
    });

    test('illegal substitution reason is rejected', () {
      final json = copyOfFixture();
      final events = fixtureEvents(json);
      (events[392]! as Map<String, Object?>)['reason'] = 'tactical';
      expect(rejectedCode(json), GameValidationCode.playerNotActive);
    });

    test('broken event sequence is rejected', () {
      final json = copyOfFixture();
      final events = fixtureEvents(json);
      (events[392]! as Map<String, Object?>)['sequence'] = 392;
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
}
