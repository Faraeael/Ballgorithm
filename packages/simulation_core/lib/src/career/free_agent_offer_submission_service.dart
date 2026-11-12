import '../models/free_agent_offer.dart';
import '../models/ids.dart';
import '../models/roster_category.dart';
import '../validation/validation_result.dart';
import 'free_agent_acquisition_service.dart';
import 'free_agent_offer_evaluator.dart';
import 'gm_career.dart';

/// Result of one formal offer workflow submission.
enum FreeAgentOfferSubmissionStatus {
  accepted('accepted'),
  rejected('rejected'),
  invalidTerms('invalidTerms'),
  financiallyIllegal('financiallyIllegal');

  const FreeAgentOfferSubmissionStatus(this.jsonValue);

  final String jsonValue;
}

final class FreeAgentOfferSubmissionResult {
  const FreeAgentOfferSubmissionResult({
    required this.career,
    required this.decision,
    required this.status,
    required this.recorded,
    required this.attemptNumber,
    required this.remainingAttempts,
  });

  final GmCareer career;
  final FreeAgentOfferDecision decision;
  final FreeAgentOfferSubmissionStatus status;

  /// True when a player-side offer record was persisted in [career].
  final bool recorded;
  final int attemptNumber;
  final int remainingAttempts;
}

/// Formal human offer workflow: evaluate, record the player decision, and
/// acquire only when the evaluator accepts.
final class FreeAgentOfferSubmissionService {
  const FreeAgentOfferSubmissionService({
    this.evaluator = const FreeAgentOfferEvaluator(),
    this.acquisition = const FreeAgentAcquisitionService(),
  });

  final FreeAgentOfferEvaluator evaluator;
  final FreeAgentAcquisitionService acquisition;

  FreeAgentOfferSubmissionResult submit({
    required GmCareer career,
    required TeamId teamId,
    required PlayerId freeAgentId,
    required RosterCategory category,
    required int durationYears,
    required int agreedFirstYearSalary,
  }) {
    final decision = evaluator.evaluate(
      career: career,
      teamId: teamId,
      freeAgentId: freeAgentId,
      category: category,
      durationYears: durationYears,
      agreedFirstYearSalary: agreedFirstYearSalary,
    );
    final keyAttempts = career.freeAgentOffers.attemptsFor(
      teamId: teamId,
      playerId: freeAgentId,
      seasonYear: career.currentYear,
    );
    final remaining =
        FreeAgentOfferAttempt.maximumPlayerSideAttempts - keyAttempts.length;

    if (decision.status == FreeAgentOfferStatus.invalidTerms ||
        decision.status == FreeAgentOfferStatus.financiallyIllegal) {
      return FreeAgentOfferSubmissionResult(
        career: career,
        decision: decision,
        status: decision.status == FreeAgentOfferStatus.invalidTerms
            ? FreeAgentOfferSubmissionStatus.invalidTerms
            : FreeAgentOfferSubmissionStatus.financiallyIllegal,
        recorded: false,
        attemptNumber: keyAttempts.length + 1,
        remainingAttempts: remaining,
      );
    }

    if (remaining <= 0) {
      throw DomainValidationException([
        const ValidationIssue(
          code: ValidationCode.freeAgentOfferLimitReached,
          path: 'freeAgentOffers',
          message: 'No formal player-side offers remain for this player',
        ),
      ]);
    }
    if (keyAttempts.isNotEmpty) {
      final previous = keyAttempts.last;
      if (!previous.outcome.isAccepted &&
          previous.category == category &&
          previous.durationYears == durationYears &&
          previous.firstYearSalary == agreedFirstYearSalary) {
        throw DomainValidationException([
          const ValidationIssue(
            code: ValidationCode.freeAgentOfferDuplicate,
            path: 'freeAgentOffers',
            message: 'An identical offer was already rejected',
          ),
        ]);
      }
    }

    final attemptNumber = keyAttempts.length + 1;
    final accepted = decision.status == FreeAgentOfferStatus.acceptable;
    if (accepted) {
      final acquired = acquisition.acquire(
        career: career,
        teamId: teamId,
        freeAgentId: freeAgentId,
        category: category,
        durationYears: durationYears,
        agreedFirstYearSalary: agreedFirstYearSalary,
      );
      final acquisitionRecord = acquired.freeAgentPool.acquisitions.forPlayer(
        freeAgentId,
      );
      if (acquisitionRecord == null) {
        throw StateError('Accepted offer did not create an acquisition record');
      }
      final attempt = FreeAgentOfferAttempt(
        offerId: FreeAgentOfferAttempt.idFor(
          teamId,
          freeAgentId,
          career.currentYear,
          attemptNumber,
        ),
        playerId: freeAgentId,
        teamId: teamId,
        seasonYear: career.currentYear,
        category: category,
        durationYears: durationYears,
        firstYearSalary: agreedFirstYearSalary,
        outcome: FreeAgentOfferOutcome.accepted,
        reasonCode: decision.reasonCode,
        attemptNumber: attemptNumber,
        acquisitionTransactionId: acquisitionRecord.transactionId,
      );
      return FreeAgentOfferSubmissionResult(
        career: acquired.copyWith(
          freeAgentOffers: acquired.freeAgentOffers.add(attempt),
        ),
        decision: decision,
        status: FreeAgentOfferSubmissionStatus.accepted,
        recorded: true,
        attemptNumber: attemptNumber,
        remainingAttempts: remaining - 1,
      );
    }

    final attempt = FreeAgentOfferAttempt(
      offerId: FreeAgentOfferAttempt.idFor(
        teamId,
        freeAgentId,
        career.currentYear,
        attemptNumber,
      ),
      playerId: freeAgentId,
      teamId: teamId,
      seasonYear: career.currentYear,
      category: category,
      durationYears: durationYears,
      firstYearSalary: agreedFirstYearSalary,
      outcome: _outcomeFor(decision.status),
      reasonCode: decision.reasonCode,
      attemptNumber: attemptNumber,
    );
    return FreeAgentOfferSubmissionResult(
      career: career.copyWith(
        freeAgentOffers: career.freeAgentOffers.add(attempt),
      ),
      decision: decision,
      status: FreeAgentOfferSubmissionStatus.rejected,
      recorded: true,
      attemptNumber: attemptNumber,
      remainingAttempts: remaining - 1,
    );
  }

  static FreeAgentOfferOutcome _outcomeFor(FreeAgentOfferStatus status) =>
      switch (status) {
        FreeAgentOfferStatus.salaryTooLow => FreeAgentOfferOutcome.salaryTooLow,
        FreeAgentOfferStatus.unfavorableDuration =>
          FreeAgentOfferOutcome.unfavorableDuration,
        FreeAgentOfferStatus.poorFit => FreeAgentOfferOutcome.poorFit,
        FreeAgentOfferStatus.inappropriateCategory =>
          FreeAgentOfferOutcome.inappropriateCategory,
        _ => throw ArgumentError.value(
          status,
          'status',
          'Not a player-side rejection status',
        ),
      };
}
