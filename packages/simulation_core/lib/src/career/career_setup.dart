import '../generation/draft_generator.dart';
import '../generation/league_generator.dart';
import '../generation/name_corpus.dart';
import '../models/draft_order.dart';
import '../models/franchise_situation.dart';
import '../models/generation_config.dart';
import '../models/ids.dart';
import '../models/league.dart';
import '../models/player_career_profile.dart';
import '../models/rookie_draft_class.dart';
import '../models/team.dart';

/// Request parameters to initialize a new GM career league.
final class CareerSetupRequest {
  const CareerSetupRequest({
    required this.selectedTeamId,
    required this.selectedSituation,
    required this.seed,
  });

  final TeamId selectedTeamId;
  final FranchiseSituation selectedSituation;
  final int seed;

  void validate() {
    if (selectedTeamId.value.trim().isEmpty) {
      throw ArgumentError.value(
        selectedTeamId.value,
        'selectedTeamId',
        'Selected franchise ID must not be empty',
      );
    }
    if (seed <= 0) {
      throw ArgumentError.value(
        seed,
        'seed',
        'Career seed must be a positive integer',
      );
    }
  }
}

/// The generated outcome of a career league setup.
final class CareerSetupResult {
  const CareerSetupResult({
    required this.league,
    required this.careerProfiles,
    required this.selectedTeam,
    required this.userOpeningDraftPick,
    required this.seed,
    this.draftOrder,
    this.draftClass,
  });

  final League league;
  final LeagueCareerProfiles careerProfiles;
  final Team selectedTeam;
  final int userOpeningDraftPick;
  final int seed;
  final DraftOrder? draftOrder;
  final RookieDraftClass? draftClass;

  FranchiseSituation get selectedSituation => selectedTeam.situation!;
}

/// Coordinates situation-driven 30-team league generation and career profile
/// creation for GM Career mode.
final class CareerSetupService {
  const CareerSetupService({this.generator = const LeagueGenerator()});

  final LeagueGenerator generator;

  CareerSetupResult generate(CareerSetupRequest request) {
    request.validate();

    if (!teamCatalog.any((t) => t.id == request.selectedTeamId.value)) {
      throw ArgumentError.value(
        request.selectedTeamId.value,
        'selectedTeamId',
        'Unknown franchise ID: ${request.selectedTeamId.value}',
      );
    }

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
    const draftGen = DraftGenerator();
    final draftOrder = draftGen.generateDraftOrder(
      league: league,
      seed: request.seed,
      userTeamId: request.selectedTeamId,
      userSituation: request.selectedSituation,
    );
    final draftClass = draftGen.generateDraftClass(
      league: league,
      seed: request.seed,
      seasonYear: 1,
    );

    return CareerSetupResult(
      league: league,
      careerProfiles: profiles,
      selectedTeam: selectedTeam,
      userOpeningDraftPick: request.selectedSituation.userOpeningDraftPick,
      seed: request.seed,
      draftOrder: draftOrder,
      draftClass: draftClass,
    );
  }
}
