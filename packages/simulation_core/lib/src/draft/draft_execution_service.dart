import '../career/gm_career.dart';
import '../models/draft_execution_state.dart';
import '../models/draft_rights.dart';
import '../models/draft_selection.dart';
import '../models/franchise_situation.dart';
import '../models/ids.dart';
import 'ai_draft_strategy.dart';

/// Executes immutable draft commands with public-scouting-only AI decisions.
final class DraftExecutionService {
  const DraftExecutionService({this.strategy = const AiDraftStrategy()});

  final AiDraftStrategy strategy;

  /// Starts the draft without executing a pick. Repeated starts are rejected.
  GmCareer startDraft(GmCareer career) {
    if (!career.draftExecutionState.isNotStarted) {
      throw StateError('Cannot start: draft has already started');
    }
    return career.copyWith(
      draftExecutionState: DraftExecutionState(
        status: DraftExecutionStatus.inProgress,
        selections: const [],
        draftRights: const {},
      ),
    );
  }

  /// Commits exactly one human-owned pick, without advancing subsequent picks.
  /// Illegal commands throw [StateError] or [ArgumentError] without mutation.
  GmCareer makeHumanSelection({
    required GmCareer career,
    required PlayerId prospectId,
  }) {
    _requireInProgress(career);
    final pick = career.draftExecutionState.currentPick(career.draftOrder)!;
    if (pick.currentOwnerTeamId != career.userFranchiseId) {
      throw StateError(
        'Cannot select: current pick belongs to an AI franchise',
      );
    }
    if (career.draftClass.byId(prospectId) == null) {
      throw ArgumentError(
        'Prospect ${prospectId.value} not found in active draft class',
      );
    }
    if (career.draftExecutionState.isProspectSelected(prospectId)) {
      throw StateError(
        'Prospect ${prospectId.value} has already been selected',
      );
    }
    return _commitSelection(career, prospectId);
  }

  /// Commits exactly one AI-owned pick; human-owned picks are never automated.
  GmCareer executeAiSelection(GmCareer career) {
    _requireInProgress(career);
    final pick = career.draftExecutionState.currentPick(career.draftOrder)!;
    if (pick.currentOwnerTeamId == career.userFranchiseId) {
      throw StateError('Cannot automate a human-owned draft pick');
    }
    final team = career.league.teams.firstWhere(
      (team) => team.id == pick.currentOwnerTeamId,
      orElse: () => throw StateError('Selecting franchise not found in league'),
    );
    final selected = strategy.selectBestProspect(
      availableProspects: career.draftExecutionState
          .availableProspects(career.draftClass)
          .map((prospect) => prospect.toPublicView())
          .toList(),
      team: team,
      situation: team.situation ?? FranchiseSituation.playIn,
      overallPick: pick.overallPick,
      seed: career.generationSeed,
    );
    return _commitSelection(career, selected.id);
  }

  /// Advances consecutive AI picks, stopping before a human pick or completion.
  GmCareer advanceUntilHumanOrComplete(GmCareer career) {
    if (career.draftExecutionState.isNotStarted) {
      throw StateError('Cannot advance: draft has not started');
    }
    var current = career;
    while (current.draftExecutionState.isInProgress &&
        !current.draftExecutionState.isHumanTurn(
          order: current.draftOrder,
          userTeamId: current.userFranchiseId,
        )) {
      current = executeAiSelection(current);
    }
    return current;
  }

  void _requireInProgress(GmCareer career) {
    if (!career.draftExecutionState.isInProgress) {
      throw StateError('Cannot select: draft is not in progress');
    }
  }

  GmCareer _commitSelection(GmCareer career, PlayerId prospectId) {
    final pick = career.draftExecutionState.currentPick(career.draftOrder)!;
    final state = career.draftExecutionState.withSelection(
      selection: DraftSelection(
        seasonYear: career.currentYear,
        round: pick.round,
        pickInRound: pick.pickInRound,
        overallPick: pick.overallPick,
        originalOwnerTeamId: pick.originalOwnerTeamId,
        selectingTeamId: pick.currentOwnerTeamId,
        prospectId: prospectId,
      ),
      rights: DraftRights(
        prospectId: prospectId,
        owningTeamId: pick.currentOwnerTeamId,
        overallPick: pick.overallPick,
        seasonYear: career.currentYear,
      ),
    );
    return career.copyWith(draftExecutionState: state);
  }
}
