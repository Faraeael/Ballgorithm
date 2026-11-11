import '../generation/draft_generator.dart';
import '../models/draft_order.dart';
import '../models/franchise_situation.dart';
import '../models/ids.dart';
import '../models/league.dart';
import '../models/player_career_profile.dart';
import '../models/rookie_draft_class.dart';
import '../models/team.dart';
import 'career_phase.dart';
import 'career_setup.dart';

/// The authoritative, persistent root state of a GM Career.
final class GmCareer {
  GmCareer({
    required this.id,
    this.schemaVersion = currentSchemaVersion,
    required this.generationSeed,
    required this.userFranchiseId,
    required this.originalSituation,
    this.currentYear = 1,
    this.phase = CareerPhase.openingOffseason,
    required this.league,
    required this.careerProfiles,
    required this.userOpeningDraftPick,
    DraftOrder? draftOrder,
    RookieDraftClass? draftClass,
  }) : draftOrder =
           draftOrder ??
           const DraftGenerator().generateDraftOrder(
             league: league,
             seed: generationSeed,
             userTeamId: userFranchiseId,
             userSituation: originalSituation,
           ),
       draftClass =
           draftClass ??
           const DraftGenerator().generateDraftClass(
             league: league,
             seed: generationSeed,
             seasonYear: currentYear,
           ) {
    validate();
  }

  /// Creates a new persistent [GmCareer] from a verified [CareerSetupResult].
  factory GmCareer.fromSetupResult(CareerSetupResult result, {String? id}) {
    final careerId =
        id ??
        'career-${result.seed}-${result.selectedTeam.id.value}-${DateTime.now().millisecondsSinceEpoch}';
    return GmCareer(
      id: careerId,
      generationSeed: result.seed,
      userFranchiseId: result.selectedTeam.id,
      originalSituation: result.selectedSituation,
      currentYear: 1,
      phase: CareerPhase.openingOffseason,
      league: result.league,
      careerProfiles: result.careerProfiles,
      userOpeningDraftPick: result.userOpeningDraftPick,
      draftOrder: result.draftOrder,
      draftClass: result.draftClass,
    );
  }

  static const int currentSchemaVersion = 2;

  final String id;
  final int schemaVersion;
  final int generationSeed;
  final TeamId userFranchiseId;
  final FranchiseSituation originalSituation;
  final int currentYear;
  final CareerPhase phase;
  final League league;
  final LeagueCareerProfiles careerProfiles;
  final int userOpeningDraftPick;

  final DraftOrder draftOrder;
  final RookieDraftClass draftClass;

  /// Returns the human user's managed [Team].
  Team get userTeam => league.teams.firstWhere(
    (t) => t.id == userFranchiseId,
    orElse: () => throw StateError(
      'User franchise ${userFranchiseId.value} not found in league',
    ),
  );

  /// Validates internal consistency and all domain invariants of the career.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('Career ID cannot be empty');
    }
    if (schemaVersion < 1 || schemaVersion > currentSchemaVersion) {
      throw FormatException(
        'Unsupported career schema version: $schemaVersion (supported: 1..$currentSchemaVersion)',
      );
    }
    if (currentYear < 1) {
      throw FormatException(
        'Invalid career year: $currentYear (expected >= 1)',
      );
    }
    if (league.teams.length != 30) {
      throw FormatException(
        'Invalid league: expected exactly 30 teams, found ${league.teams.length}',
      );
    }

    final teamIds = <String>{};
    final playerIds = <String>{};
    for (final team in league.teams) {
      if (!teamIds.add(team.id.value)) {
        throw FormatException('Duplicate team ID in league: ${team.id.value}');
      }
      if (team.roster.players.length != 12) {
        throw FormatException(
          'Team ${team.id.value} must have exactly 12 players, found ${team.roster.players.length}',
        );
      }
      for (final player in team.players) {
        if (!playerIds.add(player.id.value)) {
          throw FormatException(
            'Duplicate player ID in league: ${player.id.value}',
          );
        }
      }
    }

    if (!teamIds.contains(userFranchiseId.value)) {
      throw FormatException(
        'User franchise ${userFranchiseId.value} not found in league teams',
      );
    }

    for (final pid in playerIds) {
      if (!careerProfiles.profiles.containsKey(pid)) {
        throw FormatException('Missing career profile for player $pid');
      }
    }

    if (userOpeningDraftPick < 1 || userOpeningDraftPick > 30) {
      throw FormatException(
        'Invalid opening draft pick: $userOpeningDraftPick (expected 1..30)',
      );
    }

    if (currentYear == 1 && phase == CareerPhase.openingOffseason) {
      final expectedPick = originalSituation.userOpeningDraftPick;
      if (userOpeningDraftPick != expectedPick) {
        throw FormatException(
          'Opening draft pick mismatch: expected $expectedPick for ${originalSituation.displayName}, got $userOpeningDraftPick',
        );
      }
    }

    draftOrder.validate();
    draftClass.validate();

    final userRound1Pick = draftOrder.pickAt(userOpeningDraftPick);
    if (userRound1Pick.currentOwnerTeamId != userFranchiseId) {
      throw FormatException(
        'User franchise ${userFranchiseId.value} does not own opening draft pick $userOpeningDraftPick in draft order',
      );
    }
  }
}
