import 'package:basketball_manager/features/game/game_runner.dart';
import 'package:basketball_manager/features/game/game_seed.dart';
import 'package:simulation_core/simulation_core.dart';

/// Shared deterministic fixtures for T024/T025 widget tests.
const GenerationConfig testConfig = GenerationConfig(seed: 20261028);
const int testHomeIndex = 3;
const int testAwayIndex = 5;

League generateTestLeague() => const LeagueGenerator().generate(testConfig);

GameRequest testRequest(
  League league, {
  int homeIndex = testHomeIndex,
  int awayIndex = testAwayIndex,
  int rematchIndex = 0,
}) => GameRequest(
  league: league,
  homeTeamId: league.teams[homeIndex].id,
  awayTeamId: league.teams[awayIndex].id,
  seed: deriveGameSeed(
    leagueSeed: league.config.seed,
    homeIndex: homeIndex,
    awayIndex: awayIndex,
    rematchIndex: rematchIndex,
  ),
);

/// The same input the worker builds, simulated on the calling isolate.
GameResult simulateRequest(GameRequest request) {
  final league = request.league;
  final homeTeam = league.teams.singleWhere(
    (team) => team.id.value == request.homeTeamId.value,
  );
  final awayTeam = league.teams.singleWhere(
    (team) => team.id.value == request.awayTeamId.value,
  );
  return GameSimulator().simulate(
    GameInput.create(
      gameId:
          '${request.homeTeamId.value}-${request.awayTeamId.value}-'
          '${request.seed}',
      league: league,
      homeTeamId: request.homeTeamId,
      awayTeamId: request.awayTeamId,
      homeLineup: CourtLineup.defaultFor(homeTeam),
      awayLineup: CourtLineup.defaultFor(awayTeam),
      seed: request.seed,
      rules: GameRules.standard,
    ),
  );
}

/// First deterministic overtime fixture found in the bounded rematch cycle.
(GameRequest, GameResult) findOvertimeFixture(League league) {
  for (var home = 0; home < league.teams.length; home++) {
    for (var away = 0; away < league.teams.length; away++) {
      if (home == away) continue;
      for (var rematch = 0; rematch < 48; rematch++) {
        final request = testRequest(
          league,
          homeIndex: home,
          awayIndex: away,
          rematchIndex: rematch,
        );
        final result = simulateRequest(request);
        if (result.overtimes > 0) return (request, result);
      }
    }
  }
  throw StateError('no overtime fixture found in the bounded search');
}

/// Copy of [league] with one player renamed, through the canonical JSON round
/// trip so no model is mutated.
League leagueWithLongPlayerName(
  League league, {
  required int teamIndex,
  required int playerIndex,
  required String firstName,
  required String lastName,
}) {
  final json = league.toJson();
  final teams = json['teams']! as List<Object?>;
  final team = teams[teamIndex]! as Map<String, Object?>;
  final roster = team['roster']! as Map<String, Object?>;
  final players = roster['players']! as List<Object?>;
  final player = players[playerIndex]! as Map<String, Object?>;
  player['firstName'] = firstName;
  player['lastName'] = lastName;
  return League.fromJson(json);
}
