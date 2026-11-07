import 'dart:convert';

import 'package:basketball_manager/features/game/game_runner.dart';
import 'package:basketball_manager/features/game/game_seed.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

import 'game_fixtures.dart';

const _config = GenerationConfig(seed: 20261028);

/// Independent control path: builds the same input the worker builds and runs
/// it on the calling isolate.
GameResult _simulateOnCallingIsolate(GameRequest request) {
  final league = request.league;
  final homeTeam = league.teams.singleWhere(
    (team) => team.id.value == request.homeTeamId.value,
  );
  final awayTeam = league.teams.singleWhere(
    (team) => team.id.value == request.awayTeamId.value,
  );
  final input = GameInput.create(
    gameId:
        '${request.homeTeamId.value}-${request.awayTeamId.value}-${request.seed}',
    league: league,
    homeTeamId: request.homeTeamId,
    awayTeamId: request.awayTeamId,
    homeLineup: request.homeLineup ?? CourtLineup.defaultFor(homeTeam),
    awayLineup: request.awayLineup ?? CourtLineup.defaultFor(awayTeam),
    seed: request.seed,
    rules: GameRules.standard,
    rotationPlan: request.rotationPlan,
  );
  return GameSimulator().simulate(input);
}

String _ledgerJson(GameResult result) => jsonEncode(result.ledger.toJson());

String _ledgerDigest(GameResult result) =>
    sha256.convert(utf8.encode(_ledgerJson(result))).toString();

List<Object?> _playerFields(PlayerBoxScore p) => [
  p.teamId,
  p.points,
  p.fgm,
  p.fga,
  p.twoPm,
  p.twoPa,
  p.threePm,
  p.threePa,
  p.ftm,
  p.fta,
  p.assists,
  p.oreb,
  p.dreb,
  p.rebounds,
  p.turnovers,
  p.steals,
  p.blocks,
  p.personalFouls,
  p.secondsPlayed,
];

List<Object?> _teamFields(TeamBoxScore t) => [
  t.teamId,
  t.points,
  t.fgm,
  t.fga,
  t.twoPm,
  t.twoPa,
  t.threePm,
  t.threePa,
  t.ftm,
  t.fta,
  t.assists,
  t.oreb,
  t.dreb,
  t.rebounds,
  t.turnovers,
  t.steals,
  t.blocks,
  t.personalFouls,
];

void _expectSameBoxScore(GameBoxScore worker, GameBoxScore direct) {
  expect(worker.players.keys.toSet(), direct.players.keys.toSet());
  for (final id in direct.players.keys) {
    expect(
      _playerFields(worker.players[id]!),
      _playerFields(direct.players[id]!),
      reason: 'player box score $id',
    );
  }
  expect(worker.teams.keys.toSet(), direct.teams.keys.toSet());
  for (final id in direct.teams.keys) {
    expect(
      _teamFields(worker.teams[id]!),
      _teamFields(direct.teams[id]!),
      reason: 'team box score $id',
    );
  }
  expect(worker.periodPoints.keys.toSet(), direct.periodPoints.keys.toSet());
  for (final id in direct.periodPoints.keys) {
    expect(
      worker.periodPoints[id],
      direct.periodPoints[id],
      reason: 'period points $id',
    );
  }
}

/// Asserts each team total equals the sum of its player rows.
void _expectTotalsMatchPlayerRows(GameBoxScore box) {
  for (final teamId in box.teams.keys) {
    final rows = box.players.values.where((p) => p.teamId == teamId).toList();
    final totals = box.teams[teamId]!;
    int sum(int Function(PlayerBoxScore) field) =>
        rows.fold(0, (acc, row) => acc + field(row));

    expect(totals.points, sum((p) => p.points), reason: 'points $teamId');
    expect(totals.fgm, sum((p) => p.fgm), reason: 'fgm $teamId');
    expect(totals.fga, sum((p) => p.fga), reason: 'fga $teamId');
    expect(totals.twoPm, sum((p) => p.twoPm), reason: 'twoPm $teamId');
    expect(totals.twoPa, sum((p) => p.twoPa), reason: 'twoPa $teamId');
    expect(totals.threePm, sum((p) => p.threePm), reason: 'threePm $teamId');
    expect(totals.threePa, sum((p) => p.threePa), reason: 'threePa $teamId');
    expect(totals.ftm, sum((p) => p.ftm), reason: 'ftm $teamId');
    expect(totals.fta, sum((p) => p.fta), reason: 'fta $teamId');
    expect(totals.assists, sum((p) => p.assists), reason: 'assists $teamId');
    expect(totals.oreb, sum((p) => p.oreb), reason: 'oreb $teamId');
    expect(totals.dreb, sum((p) => p.dreb), reason: 'dreb $teamId');
    expect(totals.rebounds, sum((p) => p.rebounds), reason: 'rebounds $teamId');
    expect(
      totals.turnovers,
      sum((p) => p.turnovers),
      reason: 'turnovers $teamId',
    );
    expect(totals.steals, sum((p) => p.steals), reason: 'steals $teamId');
    expect(totals.blocks, sum((p) => p.blocks), reason: 'blocks $teamId');
    expect(
      totals.personalFouls,
      sum((p) => p.personalFouls),
      reason: 'personalFouls $teamId',
    );
  }
}

/// Asserts each team's playing time equals five players x every period played.
void _expectConservation(GameResult result) {
  final box = result.boxScore;
  final total = [
    for (var period = 1; period <= result.periodsPlayed; period++)
      result.input.rules.periodLength(period),
  ].fold<int>(0, (sum, seconds) => sum + seconds);
  for (final teamId in box.teams.keys) {
    final teamSeconds = box.players.values
        .where((player) => player.teamId == teamId)
        .fold<int>(0, (sum, player) => sum + player.secondsPlayed);
    expect(teamSeconds, 5 * total, reason: 'playing-time conservation $teamId');
  }
}

CourtLineup _nonDefaultLineup(Team team) {
  final base = CourtLineup.defaultFor(team);
  final reserve = team.players.firstWhere(
    (player) => !base.containsPlayer(player.id),
  );
  return CourtLineup.create(
    team: team,
    slotOrderedPlayers: [
      reserve,
      for (final slot in base.slots.skip(1)) slot.player!,
    ],
  );
}

List<Object?> _substitutionIdentity(GameResult result) => [
  for (final event in result.events.whereType<Substitution>())
    [
      event.sequence,
      event.period,
      event.gameClock,
      event.teamId,
      event.playerOutId,
      event.playerInId,
      event.reason.name,
    ],
];

void main() {
  late League league;
  late GameRequest request;
  late GameResult direct;

  setUpAll(() {
    league = const LeagueGenerator().generate(_config);
    final home = league.teams[3];
    final away = league.teams[5];
    request = GameRequest(
      league: league,
      homeTeamId: home.id,
      awayTeamId: away.id,
      seed: deriveGameSeed(
        leagueSeed: league.config.seed,
        homeIndex: 3,
        awayIndex: 5,
        rematchIndex: 0,
      ),
    );
    direct = _simulateOnCallingIsolate(request);
  });

  setUp(() => debugWorkerRuns = 0);

  test('worker runs off the calling isolate and returns GameResult', () async {
    final result = await runGame(request);
    expect(result, isA<GameResult>());
    expect(
      debugWorkerRuns,
      0,
      reason:
          'the counter must not change on the calling isolate: a change means '
          'the callback ran inline (web) rather than in a worker',
    );
  });

  test('worker and calling-isolate results are identical', () async {
    final worker = await runGame(request);

    expect(worker.inputFingerprint, direct.inputFingerprint);
    expect(worker.homeScore, direct.homeScore);
    expect(worker.awayScore, direct.awayScore);
    expect(worker.periodsPlayed, direct.periodsPlayed);
    expect(worker.possessions, direct.possessions);
    expect(worker.ledger.events.length, direct.ledger.events.length);
    expect(worker.events.first.sequence, direct.events.first.sequence);
    expect(worker.events.last.sequence, direct.events.last.sequence);
    expect(worker.winnerTeamId.value, direct.winnerTeamId.value);

    expect(_ledgerJson(worker), _ledgerJson(direct));
    expect(_ledgerDigest(worker), _ledgerDigest(direct));

    final workerSubs = _substitutionIdentity(worker);
    expect(
      workerSubs,
      isNotEmpty,
      reason: 'the fixture request must contain foul-out substitutions',
    );
    expect(workerSubs, _substitutionIdentity(direct));

    _expectSameBoxScore(worker.boxScore, direct.boxScore);
    _expectTotalsMatchPlayerRows(worker.boxScore);
    _expectTotalsMatchPlayerRows(direct.boxScore);
    _expectConservation(worker);
    _expectConservation(direct);
  });

  test('repeated worker runs reproduce identical results', () async {
    final first = await runGame(request);
    final second = await runGame(request);

    expect(second.inputFingerprint, first.inputFingerprint);
    expect(_ledgerDigest(second), _ledgerDigest(first));
    expect(second.homeScore, first.homeScore);
    expect(second.awayScore, first.awayScore);
  });

  test('seed normalization matches the core contract', () {
    final team = league.teams.first;
    GameInput inputWith(int seed) => GameInput.create(
      gameId: 'normalization-$seed',
      league: league,
      homeTeamId: team.id,
      awayTeamId: league.teams[1].id,
      homeLineup: CourtLineup.defaultFor(team),
      awayLineup: CourtLineup.defaultFor(league.teams[1]),
      seed: seed,
      rules: GameRules.standard,
    );

    expect(inputWith(0).normalizedSeed, 0x9E3779B9);
    expect(inputWith(7).normalizedSeed, 7);
    expect(
      deriveGameSeed(
        leagueSeed: league.config.seed,
        homeIndex: 3,
        awayIndex: 5,
        rematchIndex: 0,
      ),
      isNot(0x9E3779B9),
    );
  });

  test('teamsNotDistinct from inside the worker is a typed failure', () async {
    final bad = GameRequest(
      league: league,
      homeTeamId: league.teams.first.id,
      awayTeamId: league.teams.first.id,
      seed: 1234567,
    );
    await expectLater(
      runGame(bad),
      throwsA(
        isA<GameValidationException>()
            .having(
              (error) => error.codes,
              'codes',
              contains(GameValidationCode.teamsNotDistinct),
            )
            .having((error) => error.issues, 'issues', isNotEmpty),
      ),
    );
  });

  test(
    'planned request transports lineups and plan through the worker',
    () async {
      final home = league.teams[3];
      final away = league.teams[5];
      final homeLineup = _nonDefaultLineup(home);
      final awayLineup = CourtLineup.defaultFor(away);
      final plan = managedPlan(
        league: league,
        homeIndex: 3,
        awayIndex: 5,
        manageHome: true,
        managedLineup: homeLineup,
      );
      final planned = GameRequest(
        league: league,
        homeTeamId: home.id,
        awayTeamId: away.id,
        seed: request.seed,
        homeLineup: homeLineup,
        awayLineup: awayLineup,
        rotationPlan: plan,
      );

      final worker = await runGame(planned);
      final direct = _simulateOnCallingIsolate(planned);

      expect(worker.input.lineupFor(home.id).playerIds, homeLineup.playerIds);
      expect(
        worker.input.lineupFor(home.id).playerIds,
        isNot(CourtLineup.defaultFor(home).playerIds),
      );
      expect(worker.input.lineupFor(away.id).playerIds, awayLineup.playerIds);
      expect(worker.input.rotationPlan, isNotNull);
      expect(
        worker.input.rotationPlan!.home.targetSeconds,
        plan.home.targetSeconds,
      );
      expect(
        worker.input.rotationPlan!.away.targetSeconds,
        plan.away.targetSeconds,
      );
      expect(
        worker.events.whereType<Substitution>().where(
          (sub) => sub.reason == SubstitutionReason.tactical,
        ),
        isNotEmpty,
        reason: 'an ignored plan would emit no tactical substitution',
      );
      expect(worker.inputFingerprint, direct.inputFingerprint);
      expect(_ledgerDigest(worker), _ledgerDigest(direct));
      expect(_substitutionIdentity(worker), _substitutionIdentity(direct));
      _expectSameBoxScore(worker.boxScore, direct.boxScore);
    },
  );

  test('plan without explicit lineups uses the default five', () async {
    final home = league.teams[3];
    final away = league.teams[5];
    final homeLineup = CourtLineup.defaultFor(home);
    final basePlan = managedPlan(
      league: league,
      homeIndex: 3,
      awayIndex: 5,
      manageHome: true,
      managedLineup: homeLineup,
    );
    final edited = <String, int>{
      for (final entry in basePlan.home.targetSeconds.entries)
        entry.key.value: entry.value,
    };
    edited[homeLineup.playerIds.first] =
        edited[homeLineup.playerIds.first]! - 30;
    edited[homeLineup.playerIds.last] = edited[homeLineup.playerIds.last]! + 30;
    final plan = managedPlan(
      league: league,
      homeIndex: 3,
      awayIndex: 5,
      manageHome: true,
      managedLineup: homeLineup,
      preset: RotationPreset.custom,
      customTargets: edited,
    );
    final planned = GameRequest(
      league: league,
      homeTeamId: home.id,
      awayTeamId: away.id,
      seed: request.seed,
      rotationPlan: plan,
    );
    final worker = await runGame(planned);
    expect(worker.input.lineupFor(home.id).playerIds, homeLineup.playerIds);
    expect(worker.input.rotationPlan, isNotNull);
    expect(
      worker.events.whereType<Substitution>().where(
        (sub) => sub.reason == SubstitutionReason.tactical,
      ),
      isNotEmpty,
    );
  });

  test(
    'null-plan request keeps the legacy path without tactical swaps',
    () async {
      final worker = await runGame(request);
      expect(worker.input.rotationPlan, isNull);
      expect(
        worker.events.whereType<Substitution>().where(
          (sub) => sub.reason == SubstitutionReason.tactical,
        ),
        isEmpty,
      );
    },
  );

  test('worker overhead is recorded, not asserted', () async {
    final directWatch = Stopwatch()..start();
    _simulateOnCallingIsolate(request);
    directWatch.stop();

    final workerWatch = Stopwatch()..start();
    await runGame(request);
    workerWatch.stop();

    debugPrint(
      'T021 timing: calling isolate ${directWatch.elapsedMicroseconds} us, '
      'worker ${workerWatch.elapsedMicroseconds} us '
      '(informational; desktop VM only)',
    );
    debugPrint(
      'T021 identity: seed ${request.seed}, fingerprint '
      '${direct.inputFingerprint}, score ${direct.awayScore}-'
      '${direct.homeScore}, periods ${direct.periodsPlayed}, '
      'events ${direct.ledger.events.length}',
    );
  });
}
