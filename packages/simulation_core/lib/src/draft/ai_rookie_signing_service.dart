import '../career/gm_career.dart';
import '../career/rookie_signing_service.dart';
import '../models/ai_rookie_signing.dart';
import '../models/draft_rights.dart';
import '../models/draft_selection.dart';
import '../models/franchise_situation.dart';
import '../models/ids.dart';
import '../models/rookie_contract.dart';
import '../models/roster_category.dart';
import '../models/team.dart';
import 'ai_rookie_signing_policy.dart';

/// Drives deterministic AI rookie signing decisions for non-human franchises.
///
/// Each call applies at most one decision so callers can persist and resume
/// between decisions. Draft history and existing contracts are never rewritten.
final class RookieAiSigningService {
  const RookieAiSigningService({
    this.policy = const AiRookieSigningPolicy(),
    this.signingService = const RookieSigningService(),
  });

  final AiRookieSigningPolicy policy;
  final RookieSigningService signingService;

  /// Validates the draft and backfills decisions for AI contracts saved before
  /// the decision state existed. Never creates or alters a contract.
  GmCareer initialize(GmCareer career) {
    _requireCompletedDraft(career);
    var state = career.aiRookieSigning;
    for (final contract in career.rookieSigningLedger.ordered) {
      if (contract.teamId == career.userFranchiseId) continue;
      if (state.hasDecision(contract.playerId)) continue;
      final rights =
          career.draftExecutionState.draftRights[contract.playerId.value];
      final selection = _selectionFor(career, contract.playerId);
      if (rights == null || selection == null) continue;
      state = state.withDecision(
        AiSigningDecision(
          teamId: contract.teamId,
          prospectId: contract.playerId,
          draftSeasonYear: selection.seasonYear,
          overallPick: selection.overallPick,
          decision: contract.category == RosterCategory.twoWay
              ? AiSigningDecisionType.signedTwoWay
              : AiSigningDecisionType.signedStandard,
          reason: AiSigningReason.signedExistingContract,
          contractId: contract.id,
        ),
      );
    }
    if (identical(state, career.aiRookieSigning)) return career;
    return career.copyWith(aiRookieSigning: state);
  }

  /// AI-owned rights without a decision, in overall-pick order.
  List<DraftRights> pendingRights(GmCareer career) {
    final rights =
        career.draftExecutionState.draftRights.values
            .where((right) => right.owningTeamId != career.userFranchiseId)
            .where(
              (right) => !career.aiRookieSigning.hasDecision(right.prospectId),
            )
            .toList()
          ..sort((a, b) => a.overallPick.compareTo(b.overallPick));
    return rights;
  }

  /// Applies exactly one pending decision; returns the same career when done.
  GmCareer applyNextDecision(GmCareer career) {
    _requireCompletedDraft(career);
    final pending = pendingRights(career);
    if (pending.isEmpty) return career;

    final rights = pending.first;
    final prospect = career.draftClass.byId(rights.prospectId);
    final selection = _selectionFor(career, rights.prospectId);
    final team = _teamById(career, rights.owningTeamId);
    if (prospect == null || selection == null || team == null) {
      throw StateError(
        'Cannot evaluate draft right ${rights.prospectId.value}',
      );
    }

    final existing = career.rookieSigningLedger.forPlayer(rights.prospectId);
    if (existing != null) {
      return career.copyWith(
        aiRookieSigning: career.aiRookieSigning.withDecision(
          AiSigningDecision(
            teamId: existing.teamId,
            prospectId: existing.playerId,
            draftSeasonYear: selection.seasonYear,
            overallPick: selection.overallPick,
            decision: existing.category == RosterCategory.twoWay
                ? AiSigningDecisionType.signedTwoWay
                : AiSigningDecisionType.signedStandard,
            reason: AiSigningReason.signedExistingContract,
            contractId: existing.id,
          ),
        ),
      );
    }

    final choice = policy.decide(
      prospect: prospect.toPublicView(),
      team: team,
      situation: team.situation ?? FranchiseSituation.playIn,
      overallPick: rights.overallPick,
    );
    final decision = AiSigningDecision(
      teamId: team.id,
      prospectId: prospect.id,
      draftSeasonYear: selection.seasonYear,
      overallPick: selection.overallPick,
      decision: switch (choice.category) {
        RosterCategory.standard => AiSigningDecisionType.signedStandard,
        RosterCategory.twoWay => AiSigningDecisionType.signedTwoWay,
        _ => AiSigningDecisionType.deferred,
      },
      reason: choice.reason,
      contractId: choice.isSigning ? RookieContract.idFor(prospect.id) : null,
    );

    if (!choice.isSigning) {
      return career.copyWith(
        aiRookieSigning: career.aiRookieSigning.withDecision(decision),
      );
    }
    final signed = signingService.signDraftedRookie(
      career: career,
      teamId: team.id,
      prospectId: prospect.id,
      category: choice.category!,
      durationYears: choice.durationYears!,
    );
    return signed.copyWith(
      aiRookieSigning: signed.aiRookieSigning.withDecision(decision),
    );
  }

  /// Initializes and applies decisions until every AI right is evaluated.
  GmCareer advanceAll(GmCareer career) {
    var current = initialize(career);
    while (pendingRights(current).isNotEmpty) {
      final next = applyNextDecision(current);
      if (identical(next, current)) break;
      current = next;
    }
    return current;
  }

  void _requireCompletedDraft(GmCareer career) {
    if (!career.draftExecutionState.isCompleted) {
      throw StateError(
        'Cannot evaluate AI rookie signings before the draft completes',
      );
    }
  }

  static DraftSelection? _selectionFor(GmCareer career, PlayerId playerId) {
    for (final selection in career.draftExecutionState.selections) {
      if (selection.prospectId == playerId) return selection;
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
