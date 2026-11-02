import 'package:flutter/foundation.dart';
import 'package:simulation_core/simulation_core.dart';

/// Everything one game needs, in a form that can cross an isolate boundary.
final class GameRequest {
  const GameRequest({
    required this.league,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.seed,
  });

  final League league;
  final TeamId homeTeamId;
  final TeamId awayTeamId;
  final int seed;
}

/// Incremented inside the worker. It stays zero on the calling isolate, which
/// is how tests prove the callback did not run on the UI isolate. On the web
/// `compute` runs inline, so the counter does increment there.
@visibleForTesting
int debugWorkerRuns = 0;

/// Runs one game through [compute]: a separate isolate on native platforms,
/// inline on the web. Never a second scoreboard — the worker returns the
/// validated `GameResult` produced by the core.
Future<GameResult> runGame(GameRequest request) =>
    compute(_simulateGame, request);

GameResult _simulateGame(GameRequest request) {
  debugWorkerRuns++;
  final homeTeam = _teamIn(request.league, request.homeTeamId, 'homeTeamId');
  final awayTeam = _teamIn(request.league, request.awayTeamId, 'awayTeamId');
  final input = GameInput.create(
    gameId:
        '${request.homeTeamId.value}-${request.awayTeamId.value}-${request.seed}',
    league: request.league,
    homeTeamId: request.homeTeamId,
    awayTeamId: request.awayTeamId,
    homeLineup: ActiveLineup.defaultFor(homeTeam),
    awayLineup: ActiveLineup.defaultFor(awayTeam),
    seed: request.seed,
    rules: GameRules.standard,
  );
  return GameSimulator().simulate(input);
}

/// Typed failure for a team id the league does not contain; the UI cannot build
/// such a request, but the worker must not surface a bare `StateError`.
Team _teamIn(League league, TeamId id, String path) {
  for (final team in league.teams) {
    if (team.id.value == id.value) return team;
  }
  throw GameValidationException([
    GameValidationIssue(
      code: GameValidationCode.teamNotFound,
      path: path,
      message: 'team ${id.value} is not in the league',
    ),
  ]);
}
