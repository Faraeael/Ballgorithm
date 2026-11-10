import '../models/ids.dart';
import '../models/league.dart';
import '../models/team.dart';
import '../simulation/game_result.dart';
import 'franchise_strategy.dart';
import 'season_fixture.dart';
import 'season_player_totals.dart';
import 'season_round.dart';
import 'season_schedule.dart';
import 'season_standing.dart';

final class SeasonState {
  SeasonState({
    this.schemaVersion = 1,
    required this.id,
    required this.leagueSeed,
    required this.league,
    required this.userFranchiseId,
    required this.userStrategy,
    required this.schedule,
    required this.currentRoundNumber,
    required this.standings,
    required Map<String, SeasonPlayerTotals> playerStats,
  }) : playerStats = Map.unmodifiable(playerStats);

  final int schemaVersion;
  final String id;
  final int leagueSeed;
  final League league;
  final TeamId userFranchiseId;
  final FranchiseStrategy userStrategy;
  final SeasonSchedule schedule;
  final int currentRoundNumber;
  final LeagueStandings standings;
  final Map<String, SeasonPlayerTotals> playerStats;

  bool get isSeasonCompleted => currentRoundNumber > 14;

  SeasonRound? get currentRound =>
      isSeasonCompleted ? null : schedule.roundAt(currentRoundNumber);

  SeasonFixture? get nextUserFixture {
    final round = currentRound;
    if (round == null) return null;
    for (final f in round.fixtures) {
      if (f.homeTeamId == userFranchiseId || f.awayTeamId == userFranchiseId) {
        return f;
      }
    }
    return null;
  }

  SeasonStanding get champion => standings.ranked.first;

  SeasonStanding get userStanding => standings.table[userFranchiseId.value]!;

  Team get userTeam => league.teams.firstWhere(
    (t) => t.id == userFranchiseId,
    orElse: () => throw StateError('User franchise not found in league teams'),
  );

  static SeasonState initialize({
    required League league,
    required TeamId userFranchiseId,
    FranchiseStrategy? strategy,
  }) {
    final userTeam = league.teams.firstWhere(
      (t) => t.id == userFranchiseId,
      orElse: () => throw ArgumentError.value(
        userFranchiseId.value,
        'userFranchiseId',
        'User franchise must be one of the league teams',
      ),
    );

    final schedule = SeasonSchedule.generate(league: league);
    final standings = LeagueStandings.initial(league);
    final effectiveStrategy =
        strategy ?? FranchiseStrategy.defaultFor(userTeam);

    final stats = <String, SeasonPlayerTotals>{};
    for (final t in league.teams) {
      for (final p in t.players) {
        stats[p.id.value] = SeasonPlayerTotals.initial(
          playerId: p.id.value,
          teamId: t.id.value,
        );
      }
    }

    return SeasonState(
      id: 'season-${league.config.seed}-${userFranchiseId.value}',
      leagueSeed: league.config.seed,
      league: league,
      userFranchiseId: userFranchiseId,
      userStrategy: effectiveStrategy,
      schedule: schedule,
      currentRoundNumber: 1,
      standings: standings,
      playerStats: stats,
    );
  }

  SeasonState updateStrategy(FranchiseStrategy newStrategy) {
    if (newStrategy.teamId != userFranchiseId) {
      throw ArgumentError.value(
        newStrategy.teamId.value,
        'newStrategy.teamId',
        'Strategy must be for the user franchise ${userFranchiseId.value}',
      );
    }
    return SeasonState(
      schemaVersion: schemaVersion,
      id: id,
      leagueSeed: leagueSeed,
      league: league,
      userFranchiseId: userFranchiseId,
      userStrategy: newStrategy,
      schedule: schedule,
      currentRoundNumber: currentRoundNumber,
      standings: standings,
      playerStats: playerStats,
    );
  }

  /// Transactionally commits a completed round.
  ///
  /// Updates all 4 fixture summaries, standings, streak counts, and cumulative
  /// player statistics in a single atomic state transition, then advances the
  /// round pointer.
  SeasonState commitRound({
    required int roundNumber,
    required List<GameResult> results,
  }) {
    if (isSeasonCompleted) {
      throw StateError('Cannot commit round: season is already completed');
    }
    if (roundNumber != currentRoundNumber) {
      throw StateError(
        'Cannot commit round $roundNumber: current active round is $currentRoundNumber',
      );
    }
    if (results.length != 4) {
      throw ArgumentError.value(
        results.length,
        'results.length',
        'Expected exactly 4 game results for round $roundNumber',
      );
    }

    final targetRound = schedule.roundAt(roundNumber);
    final updatedFixtures = <SeasonFixture>[];
    var updatedStandings = standings;
    final updatedPlayerStats = Map<String, SeasonPlayerTotals>.from(
      playerStats,
    );

    for (final fixture in targetRound.fixtures) {
      final matchingResult = results.firstWhere(
        (r) =>
            r.homeTeamId == fixture.homeTeamId &&
            r.awayTeamId == fixture.awayTeamId,
        orElse: () => throw StateError(
          'Missing result for fixture ${fixture.id} (${fixture.homeTeamId.value} vs ${fixture.awayTeamId.value})',
        ),
      );

      final summary = SeasonGameSummary.fromResult(matchingResult);
      updatedFixtures.add(fixture.copyWithSummary(summary));

      updatedStandings = updatedStandings.applyGame(
        homeId: fixture.homeTeamId,
        awayId: fixture.awayTeamId,
        homeScore: matchingResult.homeScore,
        awayScore: matchingResult.awayScore,
      );

      for (final lineEntry in summary.playerLines.entries) {
        final playerId = lineEntry.key;
        final currentTotals =
            updatedPlayerStats[playerId] ??
            SeasonPlayerTotals.initial(
              playerId: playerId,
              teamId: lineEntry.value.teamId,
            );
        updatedPlayerStats[playerId] = currentTotals.applyGame(lineEntry.value);
      }
    }

    final updatedRound = SeasonRound(
      roundNumber: roundNumber,
      fixtures: updatedFixtures,
    );
    final updatedSchedule = schedule.copyWithUpdatedRound(updatedRound);

    return SeasonState(
      schemaVersion: schemaVersion,
      id: id,
      leagueSeed: leagueSeed,
      league: league,
      userFranchiseId: userFranchiseId,
      userStrategy: userStrategy,
      schedule: updatedSchedule,
      currentRoundNumber: currentRoundNumber + 1,
      standings: updatedStandings,
      playerStats: updatedPlayerStats,
    );
  }
}
