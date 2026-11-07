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
  CourtLineup? homeLineup,
  CourtLineup? awayLineup,
  RotationPlan? rotationPlan,
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
  homeLineup: homeLineup,
  awayLineup: awayLineup,
  rotationPlan: rotationPlan,
);

/// A valid lineup that is not `CourtLineup.defaultFor`: the first reserve
/// occupies the first court slot.
CourtLineup nonDefaultLineup(Team team) {
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

/// The same plan the setup screen builds for one managed team and its
/// deterministic opponent.
RotationPlan managedPlan({
  required League league,
  required int homeIndex,
  required int awayIndex,
  required bool manageHome,
  required CourtLineup managedLineup,
  RotationPreset preset = RotationPreset.balanced,
  Map<String, int>? customTargets,
}) {
  final home = league.teams[homeIndex];
  final away = league.teams[awayIndex];
  TeamRotationPlan planFor(
    Team team,
    CourtLineup lineup,
    RotationPreset teamPreset,
    Map<String, int>? custom,
  ) {
    final targets = teamPreset == RotationPreset.custom
        ? <PlayerId, int>{
            for (final player in team.players)
              player.id: custom?[player.id.value] ?? 0,
          }
        : RotationPlan.expandPreset(
            preset: teamPreset,
            team: team,
            lineup: lineup,
            rules: GameRules.standard,
          );
    return TeamRotationPlan.create(
      team: team,
      preset: teamPreset,
      targets: [
        for (final player in team.players)
          RotationTarget(playerId: player.id, seconds: targets[player.id] ?? 0),
      ],
    );
  }

  final managed = manageHome ? home : away;
  final managedTeamPlan = planFor(
    managed,
    managedLineup,
    preset,
    customTargets,
  );
  final opponent = manageHome ? away : home;
  final opponentPlan = planFor(
    opponent,
    CourtLineup.defaultFor(opponent),
    RotationPreset.balanced,
    null,
  );
  return RotationPlan(
    home: manageHome ? managedTeamPlan : opponentPlan,
    away: manageHome ? opponentPlan : managedTeamPlan,
  );
}

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
      homeLineup: request.homeLineup ?? CourtLineup.defaultFor(homeTeam),
      awayLineup: request.awayLineup ?? CourtLineup.defaultFor(awayTeam),
      seed: request.seed,
      rules: GameRules.standard,
      rotationPlan: request.rotationPlan,
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
