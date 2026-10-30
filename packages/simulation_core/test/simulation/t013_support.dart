import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import 'support.dart';

/// T013 property corpus: every seed from 1 to 200 inclusive.
final List<int> t013Seeds = List<int>.generate(200, (index) => index + 1);

GameInput standardInput(int seed, {GameRules? rules}) =>
    buildInput(seed: seed, rules: rules);

/// Independent accounting audit of a completed game (AC06, AC07).
///
/// Uses `EventAccounting` output as the authoritative box score and checks
/// every published equation against it and against the ledger.
void auditAccounting(GameInput input, GameResult result) {
  final box = result.boxScore;
  final lineupIds = <String>{
    ...input.homeLineup.playerIds,
    ...input.awayLineup.playerIds,
  };

  expect(
    box.players.keys.toSet().difference(lineupIds),
    isEmpty,
    reason: 'only active players may be credited',
  );
  expect(box.players.keys.toSet(), lineupIds);

  for (final teamId in [input.homeTeamId, input.awayTeamId]) {
    final team = box.teams[teamId.value]!;
    expect(team.teamId, teamId.value);
    expect(team.fgm, team.twoPm + team.threePm);
    expect(team.fga, team.twoPa + team.threePa);
    expect(team.twoPm, inInclusiveRange(0, team.twoPa));
    expect(team.threePm, inInclusiveRange(0, team.threePa));
    expect(team.ftm, inInclusiveRange(0, team.fta));
    expect(team.points, 2 * team.twoPm + 3 * team.threePm + team.ftm);
    expect(team.rebounds, team.oreb + team.dreb);
    for (final value in [
      team.points,
      team.fgm,
      team.fga,
      team.twoPm,
      team.twoPa,
      team.threePm,
      team.threePa,
      team.ftm,
      team.fta,
      team.assists,
      team.oreb,
      team.dreb,
      team.rebounds,
      team.turnovers,
      team.steals,
      team.blocks,
      team.personalFouls,
    ]) {
      expect(value, greaterThanOrEqualTo(0));
    }

    var players = const _Totals();
    for (final player in input.lineupFor(teamId).players) {
      final stats = box.players[player.id.value]!;
      expect(stats.playerId, player.id.value);
      expect(stats.teamId, teamId.value);
      expect(stats.fgm, stats.twoPm + stats.threePm);
      expect(stats.fga, stats.twoPa + stats.threePa);
      expect(stats.twoPm, inInclusiveRange(0, stats.twoPa));
      expect(stats.threePm, inInclusiveRange(0, stats.threePa));
      expect(stats.ftm, inInclusiveRange(0, stats.fta));
      expect(stats.points, 2 * stats.twoPm + 3 * stats.threePm + stats.ftm);
      expect(stats.rebounds, stats.oreb + stats.dreb);
      players = players.plus(stats);
    }
    expect(players.fgm, team.fgm);
    expect(players.fga, team.fga);
    expect(players.twoPm, team.twoPm);
    expect(players.twoPa, team.twoPa);
    expect(players.threePm, team.threePm);
    expect(players.threePa, team.threePa);
    expect(players.ftm, team.ftm);
    expect(players.fta, team.fta);
    expect(players.points, team.points);
    expect(
      players.assists,
      team.assists,
      reason: 'assists are player-credited',
    );
    expect(players.oreb, team.oreb);
    expect(players.dreb, team.dreb);
    expect(players.rebounds, team.rebounds);
    expect(players.turnovers, team.turnovers);
    expect(players.steals, team.steals);
    expect(players.blocks, team.blocks);
    expect(players.personalFouls, team.personalFouls);

    final periodPoints = box.periodPoints[teamId.value]!;
    expect(
      periodPoints.values.fold(0, (a, b) => a + b),
      team.points,
      reason: 'period points must reconcile with the team total',
    );
    expect(
      periodPoints.keys,
      everyElement(inInclusiveRange(1, result.periodsPlayed)),
    );
  }

  expect(result.homeScore, box.teams[input.homeTeamId.value]!.points);
  expect(result.awayScore, box.teams[input.awayTeamId.value]!.points);
  expect(result.homeScore, isNot(result.awayScore));
}

/// Independent causality audit of the accepted ledger (AC05, AC07, AC07c).
void auditCausality(GameInput input, GameResult result) {
  final events = result.events;
  final bySequence = {for (final event in events) event.sequence: event};
  final lineupOf = {
    input.homeTeamId.value: input.homeLineup.playerIds.toSet(),
    input.awayTeamId.value: input.awayLineup.playerIds.toSet(),
  };

  final missSequences = <int>{};
  final resolvedMisses = <int>{};

  for (var i = 0; i < events.length; i++) {
    final event = events[i];
    expect(event.sequence, i + 1);
    if (i > 0) {
      expect(event.period, greaterThanOrEqualTo(events[i - 1].period));
    }
    if (event is FieldGoalAttempt) {
      expect(lineupOf[event.teamId], contains(event.shooterId));
      expect(event.shotValue, anyOf(2, 3));
      if (event.made) {
        expect(event.blockedById, isNull);
        if (event.assistedById != null) {
          expect(event.assistedById, isNot(event.shooterId));
          expect(lineupOf[event.teamId], contains(event.assistedById));
        }
        if (event.andOne) {
          final next = events[i + 1];
          expect(next, isA<PersonalFoul>());
          final foul = next as PersonalFoul;
          expect(foul.kind, FoulKind.shooting);
          expect(foul.freeThrowsAwarded, 1);
          expect(foul.bonus, isFalse);
          expect(foul.drawnByPlayerId, event.shooterId);
          expect(foul.gameClock, event.gameClock);
          expect(foul.shotClock, event.shotClock);
        }
      } else {
        expect(event.assistedById, isNull);
        missSequences.add(event.sequence);
        if (event.blockedById != null) {
          final opponent = input.opponentOf(TeamId(event.teamId)).value;
          expect(lineupOf[opponent], contains(event.blockedById));
        }
      }
    } else if (event is FreeThrowAttempt) {
      expect(lineupOf[event.teamId], contains(event.shooterId));
      expect(event.attemptIndex, inInclusiveRange(1, event.attemptsInGroup));
      expect(event.lastOfGroup, event.attemptIndex == event.attemptsInGroup);
      if (!event.made && event.lastOfGroup && event.gameClock > 0) {
        missSequences.add(event.sequence);
      }
    } else if (event is Rebound) {
      expect(event.missedEventSequence, lessThan(event.sequence));
      final missed = bySequence[event.missedEventSequence];
      expect(missed, isNotNull, reason: 'rebound without a miss');
      expect(missSequences, contains(event.missedEventSequence));
      expect(
        resolvedMisses.add(event.missedEventSequence),
        isTrue,
        reason: 'each miss resolves exactly once',
      );
      expect(lineupOf[event.teamId], contains(event.playerId));
      expect(event.gameClock, greaterThanOrEqualTo(0));
      if (event.offensive) {
        expect(event.shotClock, input.rules.offensiveReboundResetSeconds);
        if (missed is FieldGoalAttempt) expect(event.teamId, missed.teamId);
        if (missed is FreeThrowAttempt) expect(event.teamId, missed.teamId);
      } else {
        expect(event.shotClock, input.rules.shotClockSeconds);
        if (missed is FieldGoalAttempt) {
          expect(event.teamId, isNot(missed.teamId));
        }
      }
    } else if (event is DeadBallMiss) {
      expect(event.gameClock, 0);
      expect(resolvedMisses.add(event.missedEventSequence), isTrue);
    } else if (event is Turnover) {
      expect(lineupOf[event.teamId], contains(event.playerId));
      switch (event.reason) {
        case TurnoverReason.steal:
          expect(event.stolenById, isNotNull);
          final opponent = input.opponentOf(TeamId(event.teamId)).value;
          expect(lineupOf[opponent], contains(event.stolenById));
        case TurnoverReason.nonSteal:
          expect(event.stolenById, isNull);
        case TurnoverReason.shotClock:
          expect(event.shotClock, 0);
          expect(event.gameClock, greaterThan(0));
          expect(
            event.playerId,
            playerAt(input, TeamId(event.teamId), Position.pg),
          );
        case TurnoverReason.offensiveFoul:
          expect(event.stolenById, isNull);
          final foul = bySequence[event.sequence - 1];
          expect(foul, isA<PersonalFoul>());
          final foulEvent = foul! as PersonalFoul;
          expect(foulEvent.kind, FoulKind.offensive);
          expect(foulEvent.committingPlayerId, event.playerId);
          expect(foulEvent.gameClock, event.gameClock);
      }
    } else if (event is PersonalFoul) {
      expect(
        lineupOf[event.committingTeamId],
        contains(event.committingPlayerId),
      );
      if (event.drawnByPlayerId != null) {
        final opponent = input.opponentOf(TeamId(event.committingTeamId)).value;
        expect(lineupOf[opponent], contains(event.drawnByPlayerId));
      }
      expect(event.freeThrowsAwarded, inInclusiveRange(0, 3));
    } else if (event is PossessionStarted) {
      expect(event.shotClock, input.rules.shotClockSeconds);
      expect(event.gameClock, greaterThanOrEqualTo(0));
    }
  }

  expect(
    missSequences.difference(resolvedMisses),
    isEmpty,
    reason: 'every live miss must resolve',
  );

  // Every credited steal matches exactly one steal turnover and vice versa.
  final stealTurnovers = events
      .whereType<Turnover>()
      .where((turnover) => turnover.reason == TurnoverReason.steal)
      .length;
  final creditedSteals = result.boxScore.teams.values.fold(
    0,
    (total, team) => total + team.steals,
  );
  expect(creditedSteals, stealTurnovers);

  final blocks = events
      .whereType<FieldGoalAttempt>()
      .where((shot) => shot.blockedById != null)
      .length;
  final creditedBlocks = result.boxScore.teams.values.fold(
    0,
    (total, team) => total + team.blocks,
  );
  expect(creditedBlocks, blocks);
  for (final shot in events.whereType<FieldGoalAttempt>()) {
    if (shot.blockedById != null) expect(shot.made, isFalse);
  }
}

final class _Totals {
  const _Totals({
    this.fgm = 0,
    this.fga = 0,
    this.twoPm = 0,
    this.twoPa = 0,
    this.threePm = 0,
    this.threePa = 0,
    this.ftm = 0,
    this.fta = 0,
    this.points = 0,
    this.assists = 0,
    this.oreb = 0,
    this.dreb = 0,
    this.rebounds = 0,
    this.turnovers = 0,
    this.steals = 0,
    this.blocks = 0,
    this.personalFouls = 0,
  });

  final int fgm;
  final int fga;
  final int twoPm;
  final int twoPa;
  final int threePm;
  final int threePa;
  final int ftm;
  final int fta;
  final int points;
  final int assists;
  final int oreb;
  final int dreb;
  final int rebounds;
  final int turnovers;
  final int steals;
  final int blocks;
  final int personalFouls;

  _Totals plus(PlayerBoxScore s) => _Totals(
    fgm: fgm + s.fgm,
    fga: fga + s.fga,
    twoPm: twoPm + s.twoPm,
    twoPa: twoPa + s.twoPa,
    threePm: threePm + s.threePm,
    threePa: threePa + s.threePa,
    ftm: ftm + s.ftm,
    fta: fta + s.fta,
    points: points + s.points,
    assists: assists + s.assists,
    oreb: oreb + s.oreb,
    dreb: dreb + s.dreb,
    rebounds: rebounds + s.rebounds,
    turnovers: turnovers + s.turnovers,
    steals: steals + s.steals,
    blocks: blocks + s.blocks,
    personalFouls: personalFouls + s.personalFouls,
  );
}
