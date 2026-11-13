import '../models/league.dart';
import '../models/roster.dart';
import '../models/roster_category.dart';
import '../models/team.dart';
import '../simulation/court_lineup.dart';
import '../simulation/game_input.dart';
import '../simulation/game_result.dart';
import '../simulation/game_rules.dart';
import '../simulation/game_simulator.dart';
import '../simulation/rotation_plan.dart';
import 'gm_career.dart';
import 'regular_season_schedule.dart';

/// Builds deterministic game inputs without changing authoritative rosters.
final class RegularSeasonGameAdapter {
  const RegularSeasonGameAdapter();

  League simulationLeagueFor(GmCareer career) {
    final teams = <Team>[];
    for (final source in career.league.teams) {
      final players = source.roster.players
          .where(
            (player) =>
                source.roster.categoryOf(player.id) == RosterCategory.standard,
          )
          .toList();
      if (players.length < 5) {
        throw FormatException(
          'Team ${source.id.value} has fewer than five standard players',
        );
      }
      teams.add(source.copyWith(roster: Roster(players)));
    }
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
  }) {
    final league = simulationLeague ?? simulationLeagueFor(career);
    final teams = league.teams;
    final home = teams.firstWhere((team) => team.id == fixture.homeTeamId);
    final away = teams.firstWhere((team) => team.id == fixture.awayTeamId);
    final homeLineup = CourtLineup.defaultFor(home);
    final awayLineup = CourtLineup.defaultFor(away);
    final rules = GameRules.standard;
    final plan = RotationPlan(
      home: TeamRotationPlan.create(
        team: home,
        preset: RotationPreset.balanced,
        targets: [
          for (final entry in RotationPlan.expandPreset(
            preset: RotationPreset.balanced,
            team: home,
            lineup: homeLineup,
            rules: rules,
          ).entries)
            RotationTarget(playerId: entry.key, seconds: entry.value),
        ],
      ),
      away: TeamRotationPlan.create(
        team: away,
        preset: RotationPreset.balanced,
        targets: [
          for (final entry in RotationPlan.expandPreset(
            preset: RotationPreset.balanced,
            team: away,
            lineup: awayLineup,
            rules: rules,
          ).entries)
            RotationTarget(playerId: entry.key, seconds: entry.value),
        ],
      ),
    );
    return GameInput.create(
      gameId: fixture.id,
      league: league,
      homeTeamId: fixture.homeTeamId,
      awayTeamId: fixture.awayTeamId,
      homeLineup: homeLineup,
      awayLineup: awayLineup,
      seed: fixture.gameSeed,
      rules: rules,
      rotationPlan: plan,
    );
  }

  GameResult simulate(GmCareer career, RegularSeasonFixture fixture) =>
      GameSimulator().simulate(createInput(career, fixture));
}
