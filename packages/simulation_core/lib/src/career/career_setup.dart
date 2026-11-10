import '../generation/league_generator.dart';
import '../models/franchise_situation.dart';
import '../models/generation_config.dart';
import '../models/ids.dart';
import '../models/league.dart';
import '../models/player_career_profile.dart';
import '../models/team.dart';

/// Request parameters to initialize a new GM career league.
final class CareerSetupRequest {
  const CareerSetupRequest({
    required this.selectedTeamId,
    required this.selectedSituation,
    this.seed = 20261028,
  });

  final TeamId selectedTeamId;
  final FranchiseSituation selectedSituation;
  final int seed;
}

/// The generated outcome of a career league setup.
final class CareerSetupResult {
  const CareerSetupResult({
    required this.league,
    required this.careerProfiles,
    required this.selectedTeam,
    required this.userOpeningDraftPick,
  });

  final League league;
  final LeagueCareerProfiles careerProfiles;
  final Team selectedTeam;
  final int userOpeningDraftPick;

  FranchiseSituation get selectedSituation => selectedTeam.situation!;
}

/// Coordinates situation-driven 30-team league generation and career profile
/// creation for GM Career mode.
final class CareerSetupService {
  const CareerSetupService({this.generator = const LeagueGenerator()});

  final LeagueGenerator generator;

  CareerSetupResult generate(CareerSetupRequest request) {
    final config = GenerationConfig(seed: request.seed, teamCount: 30);
    final league = generator.generate(
      config,
      userTeamId: request.selectedTeamId,
      userSituation: request.selectedSituation,
    );

    final selectedTeam = league.teams.firstWhere(
      (t) => t.id == request.selectedTeamId,
      orElse: () =>
          throw StateError('Selected team not found in generated league'),
    );

    final profiles = LeagueCareerProfiles.generate(
      league: league,
      seed: request.seed,
    );

    return CareerSetupResult(
      league: league,
      careerProfiles: profiles,
      selectedTeam: selectedTeam,
      userOpeningDraftPick: request.selectedSituation.userOpeningDraftPick,
    );
  }
}
