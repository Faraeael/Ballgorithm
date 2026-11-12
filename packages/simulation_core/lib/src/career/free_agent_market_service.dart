import '../finance/financial_rules.dart';
import '../models/free_agent_market.dart';
import '../models/free_agent_offer.dart';
import '../models/ids.dart';
import '../models/roster_category.dart';
import '../models/roster_rules.dart';
import '../validation/validation_result.dart';
import 'ai_free_agent_offer_policy.dart';
import 'career_phase.dart';
import 'competitive_offer_ranker.dart';
import 'free_agent_acquisition_service.dart';
import 'free_agent_offer_evaluator.dart';
import 'gm_career.dart';

/// Shared two-round free-agency market orchestration.
final class FreeAgentMarketService {
  const FreeAgentMarketService({
    this.offerEvaluator = const FreeAgentOfferEvaluator(),
    this.aiPolicy = const AiFreeAgentOfferPolicy(),
    this.ranker = const CompetitiveOfferRanker(),
    this.acquisition = const FreeAgentAcquisitionService(),
  });

  final FreeAgentOfferEvaluator offerEvaluator;
  final AiFreeAgentOfferPolicy aiPolicy;
  final CompetitiveOfferRanker ranker;
  final FreeAgentAcquisitionService acquisition;

  GmCareer startRound(GmCareer career) {
    if (career.phase != CareerPhase.openingOffseason) {
      throw StateError('Free agency requires the opening offseason');
    }
    final market = career.freeAgentMarket;
    if (market.status == FreeAgentMarketStatus.notStarted) {
      return _replaceMarket(
        career,
        market.copyWith(
          status: FreeAgentMarketStatus.collectingHumanOffers,
          roundNumber: 1,
          seasonYear: career.currentYear,
          humanOffers: const [],
          aiOffers: const [],
          resolutionOrder: const [],
          nextResolutionIndex: 0,
          outcomes: const [],
          completedRounds: 0,
        ),
      );
    }
    if (market.status == FreeAgentMarketStatus.roundComplete &&
        market.roundNumber == 1) {
      return _replaceMarket(
        career,
        market.copyWith(
          status: FreeAgentMarketStatus.collectingHumanOffers,
          roundNumber: 2,
          seasonYear: career.currentYear,
          humanOffers: const [],
          aiOffers: const [],
          resolutionOrder: const [],
          nextResolutionIndex: 0,
          outcomes: const [],
          completedRounds: 1,
        ),
      );
    }
    throw StateError('No free-agency round can be started now');
  }

  GmCareer stageHumanOffer({
    required GmCareer career,
    required TeamId teamId,
    required PlayerId playerId,
    required RosterCategory category,
    required int durationYears,
    required int firstYearSalary,
  }) {
    final market = career.freeAgentMarket;
    if (market.status != FreeAgentMarketStatus.collectingHumanOffers) {
      throw StateError('Human offers are not being collected');
    }
    if (teamId != career.userFranchiseId) {
      throw ArgumentError.value(teamId.value, 'teamId', 'Not the human team');
    }
    if (career.freeAgentPool.byId(playerId) == null) {
      _fail(ValidationCode.freeAgentInvalid, 'Player is not available');
    }
    if (market.pendingHumanOffer(teamId: teamId, playerId: playerId) != null) {
      _fail(
        ValidationCode.freeAgentOfferDuplicate,
        'A pending offer already exists for this player',
      );
    }
    final remaining = career.freeAgentOffers.remainingAttempts(
      teamId: teamId,
      playerId: playerId,
      seasonYear: career.currentYear,
    );
    if (remaining <= 0) {
      _fail(
        ValidationCode.freeAgentOfferLimitReached,
        'No player-side offers remain for this player',
      );
    }
    final priorAttempts = career.freeAgentOffers.attemptsFor(
      teamId: teamId,
      playerId: playerId,
      seasonYear: career.currentYear,
    );
    if (priorAttempts.any(
      (attempt) =>
          !attempt.outcome.isAccepted &&
          attempt.category == category &&
          attempt.durationYears == durationYears &&
          attempt.firstYearSalary == firstYearSalary,
    )) {
      _fail(
        ValidationCode.freeAgentOfferDuplicate,
        'An identical offer was already rejected',
      );
    }
    final decision = offerEvaluator.evaluate(
      career: career,
      teamId: teamId,
      freeAgentId: playerId,
      category: category,
      durationYears: durationYears,
      agreedFirstYearSalary: firstYearSalary,
    );
    if (!decision.isFinanciallyLegal) {
      _fail(ValidationCode.freeAgentOfferInvalid, decision.explanation);
    }
    _validateReservation(
      career: career,
      market: market,
      category: category,
      firstYearSalary: firstYearSalary,
    );
    final offer = FreeAgentMarketOffer(
      offerId: FreeAgentMarketOffer.idFor(
        teamId: teamId,
        playerId: playerId,
        roundNumber: market.roundNumber,
        seasonYear: career.currentYear,
      ),
      playerId: playerId,
      teamId: teamId,
      roundNumber: market.roundNumber,
      seasonYear: career.currentYear,
      category: category,
      durationYears: durationYears,
      firstYearSalary: firstYearSalary,
      source: FreeAgentMarketOfferSource.human,
    );
    return _replaceMarket(
      career,
      market.copyWith(humanOffers: [...market.humanOffers, offer]),
    );
  }

  GmCareer cancelHumanOffer({
    required GmCareer career,
    required PlayerId playerId,
  }) {
    final market = career.freeAgentMarket;
    if (market.status != FreeAgentMarketStatus.collectingHumanOffers) {
      throw StateError('Offers are locked for resolution');
    }
    return _replaceMarket(
      career,
      market.copyWith(
        humanOffers: [
          for (final offer in market.humanOffers)
            if (offer.playerId != playerId) offer,
        ],
      ),
    );
  }

  GmCareer prepareResolution(GmCareer career) {
    final market = career.freeAgentMarket;
    if (market.status != FreeAgentMarketStatus.collectingHumanOffers) {
      throw StateError('Market is not collecting offers');
    }
    final aiOffers = aiPolicy.generateOffers(
      career: career,
      marketState: market,
    );
    final offeredIds = {
      for (final offer in [...market.humanOffers, ...aiOffers])
        offer.playerId.value,
    }.toList()..sort();
    return _replaceMarket(
      career,
      market.copyWith(
        status: FreeAgentMarketStatus.preparedForResolution,
        aiOffers: aiOffers,
        resolutionOrder: [for (final id in offeredIds) PlayerId(id)],
        nextResolutionIndex: 0,
        outcomes: const [],
      ),
    );
  }

  /// Resolves exactly one player. The caller persists each returned career.
  GmCareer resolveNext(GmCareer career) {
    final market = career.freeAgentMarket;
    if (!market.isResolvable) {
      throw StateError('Market is not ready for resolution');
    }
    if (market.nextResolutionIndex >= market.resolutionOrder.length) {
      return _completeRound(career);
    }
    final playerId = market.resolutionOrder[market.nextResolutionIndex];
    final offers = market.offersFor(playerId);
    final results = <FreeAgentMarketOfferResult>[];
    final rejections = <FreeAgentMarketOffer, FreeAgentOfferDecision>{};
    final accepted = <FreeAgentMarketOffer>[];

    for (final offer in offers) {
      final decision = offerEvaluator.evaluate(
        career: career,
        teamId: offer.teamId,
        freeAgentId: offer.playerId,
        category: offer.category,
        durationYears: offer.durationYears,
        agreedFirstYearSalary: offer.firstYearSalary,
      );
      switch (decision.status) {
        case FreeAgentOfferStatus.acceptable:
          accepted.add(offer);
        case FreeAgentOfferStatus.invalidTerms:
        case FreeAgentOfferStatus.financiallyIllegal:
          results.add(
            FreeAgentMarketOfferResult(
              offerId: offer.offerId,
              teamId: offer.teamId,
              outcome: FreeAgentMarketOfferOutcome.financiallyUnavailable,
              reasonCode: decision.reasonCode,
            ),
          );
        case FreeAgentOfferStatus.salaryTooLow:
        case FreeAgentOfferStatus.unfavorableDuration:
        case FreeAgentOfferStatus.poorFit:
        case FreeAgentOfferStatus.inappropriateCategory:
          rejections[offer] = decision;
          results.add(
            FreeAgentMarketOfferResult(
              offerId: offer.offerId,
              teamId: offer.teamId,
              outcome: FreeAgentMarketOfferOutcome.rejected,
              reasonCode: decision.reasonCode,
            ),
          );
      }
    }

    final ranked = ranker.rank(
      career: career,
      playerId: playerId,
      offers: accepted,
    );
    GmCareer? won;
    FreeAgentMarketOffer? winner;
    for (final offer in ranked) {
      try {
        won = acquisition.acquire(
          career: career,
          teamId: offer.teamId,
          freeAgentId: offer.playerId,
          category: offer.category,
          durationYears: offer.durationYears,
          agreedFirstYearSalary: offer.firstYearSalary,
        );
        winner = offer;
        break;
      } on DomainValidationException catch (error) {
        results.add(
          FreeAgentMarketOfferResult(
            offerId: offer.offerId,
            teamId: offer.teamId,
            outcome: FreeAgentMarketOfferOutcome.financiallyUnavailable,
            reasonCode: error.codes.map((code) => code.name).join(','),
          ),
        );
      }
    }

    if (winner != null) {
      final unavailable = {
        for (final result in results)
          if (result.outcome ==
              FreeAgentMarketOfferOutcome.financiallyUnavailable)
            result.offerId,
      };
      for (final offer in ranked) {
        if (offer.offerId == winner.offerId) continue;
        if (unavailable.contains(offer.offerId)) continue;
        results.add(
          FreeAgentMarketOfferResult(
            offerId: offer.offerId,
            teamId: offer.teamId,
            outcome: FreeAgentMarketOfferOutcome.outbid,
            reasonCode: 'outbid',
          ),
        );
      }
    }

    var ledger = career.freeAgentOffers;
    for (final entry in rejections.entries) {
      ledger = _appendAttempt(
        ledger: ledger,
        offer: entry.key,
        outcome: _outcomeFor(entry.value.status),
        reasonCode: entry.value.reasonCode,
        acquisitionTransactionId: null,
        seasonYear: career.currentYear,
      );
    }
    if (winner != null) {
      final acquisitionRecord = won!.freeAgentPool.acquisitions.forPlayer(
        playerId,
      )!;
      ledger = _appendAttempt(
        ledger: ledger,
        offer: winner,
        outcome: FreeAgentOfferOutcome.accepted,
        reasonCode: 'accepted',
        acquisitionTransactionId: acquisitionRecord.transactionId,
        seasonYear: career.currentYear,
      );
      final acceptedResult = FreeAgentMarketOfferResult(
        offerId: winner.offerId,
        teamId: winner.teamId,
        outcome: FreeAgentMarketOfferOutcome.accepted,
        reasonCode: 'accepted',
      );
      results
        ..removeWhere(
          (result) =>
              result.offerId == winner!.offerId &&
              result.outcome == FreeAgentMarketOfferOutcome.outbid,
        )
        ..add(acceptedResult);
    }

    final outcome = FreeAgentMarketOutcome(
      playerId: playerId,
      winningTeamId: winner?.teamId,
      winningOfferId: winner?.offerId,
      results: results,
    );
    final nextIndex = market.nextResolutionIndex + 1;
    final complete = nextIndex >= market.resolutionOrder.length;
    final outcomes = [...market.outcomes, outcome];
    final updatedState = market.copyWith(
      status: complete
          ? (market.roundNumber == 2
                ? FreeAgentMarketStatus.marketComplete
                : FreeAgentMarketStatus.roundComplete)
          : FreeAgentMarketStatus.resolving,
      nextResolutionIndex: nextIndex,
      outcomes: outcomes,
      completedRounds: complete ? market.roundNumber : market.completedRounds,
      roundHistory: complete
          ? [...market.roundHistory, _roundRecord(market, outcomes)]
          : market.roundHistory,
    );
    final base = won ?? career;
    return _replaceMarket(base.copyWith(freeAgentOffers: ledger), updatedState);
  }

  GmCareer _completeRound(GmCareer career) {
    final market = career.freeAgentMarket;
    final status = market.roundNumber == 2
        ? FreeAgentMarketStatus.marketComplete
        : FreeAgentMarketStatus.roundComplete;
    final alreadyRecorded = market.roundHistory.any(
      (record) => record.roundNumber == market.roundNumber,
    );
    return _replaceMarket(
      career,
      market.copyWith(
        status: status,
        completedRounds: market.roundNumber,
        roundHistory: alreadyRecorded
            ? market.roundHistory
            : [...market.roundHistory, _roundRecord(market, market.outcomes)],
      ),
    );
  }

  FreeAgentMarketRoundRecord _roundRecord(
    FreeAgentMarketState market,
    List<FreeAgentMarketOutcome> outcomes,
  ) => FreeAgentMarketRoundRecord(
    roundNumber: market.roundNumber,
    seasonYear: market.seasonYear,
    humanOffers: market.humanOffers,
    aiOffers: market.aiOffers,
    resolutionOrder: market.resolutionOrder,
    outcomes: outcomes,
  );

  void _validateReservation({
    required GmCareer career,
    required FreeAgentMarketState market,
    required RosterCategory category,
    required int firstYearSalary,
  }) {
    final pending = market.humanOffers;
    final standardPending = pending
        .where((offer) => offer.category == RosterCategory.standard)
        .length;
    final twoWayPending = pending
        .where((offer) => offer.category == RosterCategory.twoWay)
        .length;
    final standardSalary = pending
        .where((offer) => offer.category == RosterCategory.standard)
        .fold<int>(0, (sum, offer) => sum + offer.firstYearSalary);
    final allSalary = pending.fold<int>(
      0,
      (sum, offer) => sum + offer.firstYearSalary,
    );
    final team = career.userTeam;
    final capPayroll = career.finances.capPayrollFor(
      team.id,
      career.currentYear,
    );
    if (category == RosterCategory.standard &&
        capPayroll + standardSalary + firstYearSalary >
            FinancialRules.salaryCap) {
      _fail(ValidationCode.capBreach, 'Reserved cap commitments exceed cap');
    }
    if (team.roster.standardCount +
            standardPending +
            (category == RosterCategory.standard ? 1 : 0) >
        RosterRules.maxOffseasonStandard) {
      _fail(
        ValidationCode.rosterCapacityExceeded,
        'Reserved standard roster capacity exceeded',
      );
    }
    if (team.roster.twoWayCount +
            twoWayPending +
            (category == RosterCategory.twoWay ? 1 : 0) >
        RosterRules.maxOffseasonTwoWay) {
      _fail(
        ValidationCode.rosterCapacityExceeded,
        'Reserved two-way roster capacity exceeded',
      );
    }
    if (team.roster.totalContractedCount + pending.length + 1 >
        RosterRules.maxOffseasonTotal) {
      _fail(
        ValidationCode.rosterCapacityExceeded,
        'Reserved total roster capacity exceeded',
      );
    }
    final projected = career.finances.projectedEndOfSeasonCash(
      team.id,
      career.currentYear,
    );
    if (projected - allSalary - firstYearSalary < 0) {
      _fail(
        ValidationCode.cashInsufficient,
        'Reserved cash commitments fail solvency',
      );
    }
  }

  FreeAgentOfferLedger _appendAttempt({
    required FreeAgentOfferLedger ledger,
    required FreeAgentMarketOffer offer,
    required FreeAgentOfferOutcome outcome,
    required String reasonCode,
    required String? acquisitionTransactionId,
    required int seasonYear,
  }) {
    final attempts = ledger.attemptsFor(
      teamId: offer.teamId,
      playerId: offer.playerId,
      seasonYear: seasonYear,
    );
    if (attempts.length >= FreeAgentOfferAttempt.maximumPlayerSideAttempts) {
      _fail(
        ValidationCode.freeAgentOfferLimitReached,
        'Player-side attempt limit reached for ${offer.teamId.value}/'
        '${offer.playerId.value}',
      );
    }
    final attempt = FreeAgentOfferAttempt(
      offerId: FreeAgentOfferAttempt.idFor(
        offer.teamId,
        offer.playerId,
        seasonYear,
        attempts.length + 1,
      ),
      playerId: offer.playerId,
      teamId: offer.teamId,
      seasonYear: seasonYear,
      category: offer.category,
      durationYears: offer.durationYears,
      firstYearSalary: offer.firstYearSalary,
      outcome: outcome,
      reasonCode: reasonCode,
      attemptNumber: attempts.length + 1,
      acquisitionTransactionId: acquisitionTransactionId,
    );
    return ledger.add(attempt);
  }

  static FreeAgentOfferOutcome _outcomeFor(FreeAgentOfferStatus status) =>
      switch (status) {
        FreeAgentOfferStatus.salaryTooLow => FreeAgentOfferOutcome.salaryTooLow,
        FreeAgentOfferStatus.unfavorableDuration =>
          FreeAgentOfferOutcome.unfavorableDuration,
        FreeAgentOfferStatus.poorFit => FreeAgentOfferOutcome.poorFit,
        FreeAgentOfferStatus.inappropriateCategory =>
          FreeAgentOfferOutcome.inappropriateCategory,
        _ => throw ArgumentError.value(status, 'status'),
      };

  static GmCareer _replaceMarket(
    GmCareer career,
    FreeAgentMarketState market,
  ) => career.copyWith(freeAgentMarket: market);

  static Never _fail(ValidationCode code, String message) =>
      throw DomainValidationException([
        ValidationIssue(code: code, path: 'freeAgentMarket', message: message),
      ]);
}
