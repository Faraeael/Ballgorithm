import '../models/draft_selection.dart';
import '../models/ids.dart';
import '../models/league.dart';
import '../models/player.dart';
import '../models/player_career_profile.dart';
import '../models/rookie_contract.dart';
import '../models/roster_category.dart';
import '../models/team.dart';
import 'gm_career.dart';

/// Atomic, pure-domain signing of one drafted prospect into a franchise roster.
///
/// The same command serves any franchise; AI signing policy is a later milestone.
final class RookieSigningService {
  const RookieSigningService();

  /// Returns a new validated [GmCareer] with exactly one rookie signing applied.
  ///
  /// Throws [StateError] or [ArgumentError] before producing state when the
  /// command is illegal. Draft history, rights and all other players are
  /// preserved unchanged.
  GmCareer signDraftedRookie({
    required GmCareer career,
    required TeamId teamId,
    required PlayerId prospectId,
    required RosterCategory category,
    required int durationYears,
  }) {
    final draft = career.draftExecutionState;
    if (!draft.isCompleted) {
      throw StateError('Cannot sign: rookie draft is not completed');
    }
    final prospect = career.draftClass.byId(prospectId);
    if (prospect == null) {
      throw ArgumentError(
        'Prospect ${prospectId.value} not found in draft class',
      );
    }
    final rights = draft.draftRights[prospectId.value];
    final selection = _selectionFor(draft.selections, prospectId);
    if (rights == null || selection == null) {
      throw StateError(
        'Cannot sign: prospect ${prospectId.value} was not drafted',
      );
    }
    if (rights.owningTeamId != teamId) {
      throw StateError(
        'Cannot sign: draft rights for ${prospectId.value} belong to '
        '${rights.owningTeamId.value}',
      );
    }
    final team = _teamById(career, teamId);
    if (team == null) {
      throw StateError('Signing franchise ${teamId.value} not found');
    }
    if (career.rookieSigningLedger.isSigned(prospectId)) {
      throw StateError(
        'Prospect ${prospectId.value} has already signed a rookie contract',
      );
    }
    for (final candidate in career.league.teams) {
      if (candidate.players.any((player) => player.id == prospectId)) {
        throw StateError(
          'Prospect ${prospectId.value} is already on a contracted roster',
        );
      }
    }
    if (!RookieContract.isSupportedCategory(category)) {
      throw ArgumentError.value(
        category.jsonValue,
        'category',
        'Unsupported rookie contract category',
      );
    }
    final maxDuration = RookieContract.maxDurationFor(category);
    if (durationYears < RookieContract.minDurationYears ||
        durationYears > maxDuration) {
      throw ArgumentError.value(
        durationYears,
        'durationYears',
        'Rookie contract duration must be between '
            '${RookieContract.minDurationYears} and $maxDuration years for '
            '${category.jsonValue}',
      );
    }
    if (career.careerProfiles.forPlayer(prospectId) != null) {
      throw StateError(
        'Prospect ${prospectId.value} already has a career profile',
      );
    }

    final player = Player(
      id: prospect.id,
      firstName: prospect.firstName,
      lastName: prospect.lastName,
      position: prospect.position,
      attributes: prospect.attributes,
    );
    final profile = PlayerCareerProfile(
      playerId: prospect.id,
      age: prospect.age,
      potential: prospect.potential,
      trajectory: prospect.trajectory,
    )..validate(player);
    final roster = team.roster.withPlayer(player, category: category);
    final capacity = roster.validateStructure(phase: career.phase);
    if (!capacity.isValid) {
      throw StateError(
        'Cannot sign ${prospectId.value}: ${capacity.issues.join('; ')}',
      );
    }

    final contract = RookieContract(
      id: RookieContract.idFor(prospectId),
      playerId: prospectId,
      teamId: teamId,
      category: category,
      startYear: career.currentYear,
      durationYears: durationYears,
      draftSeasonYear: selection.seasonYear,
      overallPick: selection.overallPick,
    );
    final updatedTeam = team.copyWith(roster: roster);
    final updatedLeague = League.create(
      id: career.league.id,
      name: career.league.name,
      config: career.league.config,
      teams: [
        for (final candidate in career.league.teams)
          candidate.id == teamId ? updatedTeam : candidate,
      ],
      enforceRosterSize: false,
    );
    final updatedProfiles = LeagueCareerProfiles(
      schemaVersion: career.careerProfiles.schemaVersion,
      leagueSeed: career.careerProfiles.leagueSeed,
      profiles: {...career.careerProfiles.profiles, prospectId.value: profile},
    );
    return career.copyWith(
      league: updatedLeague,
      careerProfiles: updatedProfiles,
      rookieSigningLedger: career.rookieSigningLedger.withContract(contract),
    );
  }

  static DraftSelection? _selectionFor(
    List<DraftSelection> selections,
    PlayerId prospectId,
  ) {
    for (final selection in selections) {
      if (selection.prospectId == prospectId) return selection;
    }
    return null;
  }

  static Team? _teamById(GmCareer career, TeamId teamId) {
    for (final team in career.league.teams) {
      if (team.id == teamId) return team;
    }
    return null;
  }
}
