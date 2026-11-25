import '../models/ids.dart';
import '../models/league.dart';
import '../models/player.dart';
import '../models/roster.dart';
import '../models/roster_category.dart';
import '../models/team.dart';
import '../simulation/court_lineup.dart';
import '../simulation/game_input.dart';
import '../simulation/game_result.dart';
import '../simulation/game_rules.dart';
import '../simulation/game_simulator.dart';
import '../simulation/rotation_plan.dart';
import 'career_rotation_service.dart';
import 'gm_career.dart';
import 'regular_season_schedule.dart';

/// Builds deterministic game inputs without changing authoritative rosters.
final class RegularSeasonGameAdapter {
  const RegularSeasonGameAdapter();

  /// Standard-roster copy of [source] used for every career game input.
  /// Two-way players and unsigned rights never enter simulation.
  static Team standardTeamFor(Team source) {
    final players = <Player>[
      for (final player in source.roster.players)
        if (source.roster.categoryOf(player.id) == RosterCategory.standard)
          player,
    ];
    if (players.length < 5) {
      throw FormatException(
        'Team ${source.id.value} has fewer than five standard players',
      );
    }
    return source.copyWith(roster: Roster(players));
  }

  League simulationLeagueFor(GmCareer career) {
    final teams = <Team>[
      for (final source in career.league.teams) standardTeamFor(source),
    ];
    return League.create(
      id: career.league.id,
      name: career.league.name,
      config: career.league.config,
      teams: teams,
      enforceRosterSize: false,
    );
  }

  GameInput createInput(
    GmCareer career,
    RegularSeasonFixture fixture, {
    League? simulationLeague,
  }) => createGameInput(
    career,
    gameId: fixture.id,
    homeTeamId: fixture.homeTeamId,
    awayTeamId: fixture.awayTeamId,
    seed: fixture.gameSeed,
    simulationLeague: simulationLeague,
  );

  GameInput createGameInput(
    GmCareer career, {
    required String gameId,
    required TeamId homeTeamId,
    required TeamId awayTeamId,
    required int seed,
    League? simulationLeague,
  }) {
    final league = simulationLeague ?? simulationLeagueFor(career);
    final teams = league.teams;
    final home = teams.firstWhere((team) => team.id == homeTeamId);
    final away = teams.firstWhere((team) => team.id == awayTeamId);
    final rules = GameRules.standard;
    final homeSide = _sideFor(career, home, rules);
    final awaySide = _sideFor(career, away, rules);
    final homeLineup = homeSide.lineup;
    final awayLineup = awaySide.lineup;
    final plan = RotationPlan(home: homeSide.plan, away: awaySide.plan);
    return GameInput.create(
      gameId: gameId,
      league: league,
      homeTeamId: homeTeamId,
      awayTeamId: awayTeamId,
      homeLineup: homeLineup,
      awayLineup: awayLineup,
      seed: seed,
      rules: rules,
      rotationPlan: plan,
    );
  }

  /// One authoritative decision path for every side of every career game
  /// (regular season, batch, Play-In, playoffs): see
  /// [CareerRotationService.decisionFor]. With coaching disabled this is the
  /// M010 behaviour exactly. An unresolvable manual plan throws: it never
  /// falls back to AUTO.
  static ({CourtLineup lineup, TeamRotationPlan plan}) _sideFor(
    GmCareer career,
    Team team,
    GameRules rules,
  ) {
    final decision = CareerRotationService.decisionFor(
      career,
      team,
      rules: rules,
    );
    return (lineup: decision.lineup, plan: decision.plan);
  }

  GameResult simulate(GmCareer career, RegularSeasonFixture fixture) =>
      GameSimulator().simulate(createInput(career, fixture));
}
