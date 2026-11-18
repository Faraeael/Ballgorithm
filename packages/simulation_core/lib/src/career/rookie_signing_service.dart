import '../finance/financial_transactions.dart';
import '../models/carried_unsigned_prospect.dart';
import '../models/draft_rights.dart';
import '../models/draft_selection.dart';
import '../models/ids.dart';
import '../models/league.dart';
import '../models/player.dart';
import '../models/player_career_profile.dart';
import '../models/rookie_contract.dart';
import '../models/roster_category.dart';
import '../models/team.dart';
import 'career_phase.dart';
import 'gm_career.dart';

/// Atomic, pure-domain signing of one drafted prospect into a franchise roster.
///
/// Supports both current-year drafted prospects (`draftExecutionState`) and
/// multi-season carried unsigned prospects (`careerDraftRights` +
/// `carriedUnsignedProspects`).
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
    final TeamId owningTeamId;
    final int draftSeasonYear;
    final int overallPick;
    final Player player;
    final PlayerCareerProfile profile;
    final Map<String, CarriedUnsignedProspect> nextCarriedProspects;
    final Map<String, DraftRights> nextCareerDraftRights;

    if (career.careerDraftRights.containsKey(prospectId.value)) {
      final rights = career.careerDraftRights[prospectId.value]!;
      final carried = career.carriedUnsignedProspects[prospectId.value];
      if (carried == null) {
        throw StateError(
          'Cannot sign: missing carried prospect snapshot for '
          '${prospectId.value}',
        );
      }
      owningTeamId = rights.owningTeamId;
      draftSeasonYear = carried.draftSeasonYear;
      overallPick = carried.overallPick;
      player = carried.toPlayer();
      profile = carried.toProfile();
      nextCareerDraftRights = Map.of(career.careerDraftRights)
        ..remove(prospectId.value);
      nextCarriedProspects = Map.of(career.carriedUnsignedProspects)
        ..remove(prospectId.value);
    } else {
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
      owningTeamId = rights.owningTeamId;
      draftSeasonYear = selection.seasonYear;
      overallPick = selection.overallPick;
      player = Player(
        id: prospect.id,
        firstName: prospect.firstName,
        lastName: prospect.lastName,
        position: prospect.position,
        attributes: prospect.attributes,
      );
      profile = PlayerCareerProfile(
        playerId: prospect.id,
        age: prospect.age,
        potential: prospect.potential,
        trajectory: prospect.trajectory,
      )..validate(player);
      nextCareerDraftRights = career.careerDraftRights;
      nextCarriedProspects = career.carriedUnsignedProspects;
    }

    if (owningTeamId != teamId) {
      throw StateError(
        'Cannot sign: draft rights for ${prospectId.value} belong to '
        '${owningTeamId.value}',
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
    if (career.retiredPlayers.any((r) => r.playerId == prospectId)) {
      throw StateError(
        'Prospect ${prospectId.value} is retired and cannot be signed',
      );
    }
    if (career.freeAgentPool.playerIds.contains(prospectId.value)) {
      throw StateError(
        'Prospect ${prospectId.value} is already in the free-agent pool',
      );
    }
    for (final candidate in career.league.teams) {
      if (candidate.players.any((p) => p.id == prospectId)) {
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
      draftSeasonYear: draftSeasonYear,
      overallPick: overallPick,
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
      enforcePositionCoverage: career.phase != CareerPhase.openingOffseason,
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
      finances: FinancialTransactions.signRookie(
        finances: career.finances,
        rookieContract: contract,
      ),
      careerDraftRights: nextCareerDraftRights,
      carriedUnsignedProspects: nextCarriedProspects,
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
