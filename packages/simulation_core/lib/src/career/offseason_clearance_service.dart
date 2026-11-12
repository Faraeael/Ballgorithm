import '../finance/career_finances.dart';
import '../finance/financial_rules.dart';
import '../models/free_agent_acquisition.dart';
import '../models/free_agent_market.dart';
import '../models/free_agent_offer.dart';
import '../models/ids.dart';
import '../models/offseason_clearance.dart';
import '../models/roster_category.dart';
import '../models/roster_rules.dart';
import '../models/team_finances.dart';
import '../validation/validation_result.dart';
import 'competitive_offer_ranker.dart';
import 'free_agent_acquisition_service.dart';
import 'free_agent_market_value_service.dart';
import 'free_agent_offer_evaluator.dart';
import 'gm_career.dart';
import 'offseason_readiness_gate.dart';

/// Bounded compliance-only pass after both competitive market rounds.
final class OffseasonClearanceService {
  const OffseasonClearanceService({
    this.market = const FreeAgentMarketValueService(),
    this.evaluator = const FreeAgentOfferEvaluator(),
    this.ranker = const CompetitiveOfferRanker(),
    this.acquisition = const FreeAgentAcquisitionService(),
    this.readiness = const OffseasonReadinessGate(),
  });

  final FreeAgentMarketValueService market;
  final FreeAgentOfferEvaluator evaluator;
  final CompetitiveOfferRanker ranker;
  final FreeAgentAcquisitionService acquisition;
  final OffseasonReadinessGate readiness;

  GmCareer start(GmCareer career) {
    if (career.freeAgentMarket.status != FreeAgentMarketStatus.marketComplete) {
      throw StateError('Clearance requires both market rounds complete');
    }
    if (career.offseasonClearance.status !=
        OffseasonClearanceStatus.notStarted) {
      throw StateError('Clearance has already started');
    }
    final granted = _grantApprovedExceptions(career);
    return _replace(
      granted,
      granted.offseasonClearance.copyWith(
        status: OffseasonClearanceStatus.collectingHumanOffers,
        seasonYear: granted.currentYear,
      ),
    );
  }

  GmCareer _grantApprovedExceptions(GmCareer career) {
    final exceptions = <CapException>[];
    final teamFinances = career.finances.teamFinances.values.toList();
    final updatedFinances = <String, TeamFinances>{};
    for (final team in career.league.teams) {
      final standard = team.roster.standardCount;
      final need = RosterRules.minRegularSeasonStandard - standard;
      if (need <= 0 || need > FinancialRules.maximumReliefDeals) continue;
      final finances = career.finances.financesFor(team.id);
      if (finances.capGrandfathered || finances.capException > 0) continue;
      final capRoom =
          FinancialRules.salaryCap -
          career.finances.capPayrollFor(team.id, career.currentYear);
      final missing = FinancialRules.minimumSalary * need - capRoom;
      if (missing <= 0) continue;
      final amount = missing > FinancialRules.maximumReliefOverage
          ? FinancialRules.maximumReliefOverage
          : missing;
      exceptions.add(
        CapException(
          teamId: team.id,
          amount: amount,
          missingPlayers: need,
          reason: 'minimumRosterRelief-v1: $need minimum deal(s)',
        ),
      );
      updatedFinances[team.id.value] = TeamFinances(
        teamId: finances.teamId,
        operatingBudget: finances.operatingBudget,
        cash: finances.cash,
        revenueBaseline: finances.revenueBaseline,
        season: finances.season,
        capGrandfathered: finances.capGrandfathered,
        grandfatheredPayroll: finances.grandfatheredPayroll,
        capException: amount,
      );
    }
    if (exceptions.isEmpty) return career;
    final updated = CareerFinances(
      contracts: career.finances.contracts.values,
      schedules: career.finances.schedules.values,
      teamFinances: [
        for (final record in teamFinances)
          updatedFinances[record.teamId.value] ?? record,
      ],
      staffCommitments: career.finances.staffCommitments.values,
      facilities: career.finances.facilities.values,
    );
    return career.copyWith(
      finances: updated,
      offseasonClearance: career.offseasonClearance.copyWith(
        capExceptions: exceptions,
        status: OffseasonClearanceStatus.collectingHumanOffers,
      ),
    );
  }

  GmCareer stageHumanOffer({
    required GmCareer career,
    required TeamId teamId,
    required PlayerId playerId,
    required int durationYears,
    required int firstYearSalary,
  }) {
    final clearance = career.offseasonClearance;
    if (clearance.status != OffseasonClearanceStatus.collectingHumanOffers) {
      throw StateError('Clearance offers are not being collected');
    }
    if (teamId != career.userFranchiseId) {
      throw ArgumentError.value(teamId.value, 'teamId', 'Not the human team');
    }
    final team = career.userTeam;
    final requiredPlayers =
        RosterRules.minRegularSeasonStandard - team.roster.standardCount;
    if (requiredPlayers <= 0) {
      _fail(ValidationCode.rosterCapacityExceeded, 'Roster is already full');
    }
    if (career.freeAgentPool.byId(playerId) == null) {
      _fail(ValidationCode.freeAgentInvalid, 'Player is not available');
    }
    if (clearance.humanOffers.length >= requiredPlayers) {
      _fail(
        ValidationCode.rosterCapacityExceeded,
        'Only $requiredPlayers clearance contract(s) are permitted',
      );
    }
    if (clearance.humanOffers.any((offer) => offer.playerId == playerId)) {
      _fail(
        ValidationCode.freeAgentOfferDuplicate,
        'A clearance offer already exists for this player',
      );
    }
    if (career.freeAgentOffers.remainingAttempts(
          teamId: teamId,
          playerId: playerId,
          seasonYear: career.currentYear,
        ) <=
        0) {
      _fail(
        ValidationCode.freeAgentOfferLimitReached,
        'No player-side offers remain for this player',
      );
    }
    final decision = evaluator.evaluate(
      career: career,
      teamId: teamId,
      freeAgentId: playerId,
      category: RosterCategory.standard,
      durationYears: durationYears,
      agreedFirstYearSalary: firstYearSalary,
      clearanceOffer: true,
    );
    if (!decision.isFinanciallyLegal) {
      _fail(ValidationCode.freeAgentOfferInvalid, decision.explanation);
    }
    _validateReservation(
      career: career,
      playerId: playerId,
      durationYears: durationYears,
      salary: firstYearSalary,
      humanOffers: clearance.humanOffers,
    );
    final offer = FreeAgentMarketOffer(
      offerId: FreeAgentMarketOffer.idFor(
        teamId: teamId,
        playerId: playerId,
        roundNumber: 3,
        seasonYear: career.currentYear,
      ),
      playerId: playerId,
      teamId: teamId,
      roundNumber: 3,
      seasonYear: career.currentYear,
      category: RosterCategory.standard,
      durationYears: durationYears,
      firstYearSalary: firstYearSalary,
      source: FreeAgentMarketOfferSource.human,
    );
    return _replace(
      career,
      clearance.copyWith(humanOffers: [...clearance.humanOffers, offer]),
    );
  }

  GmCareer prepare(GmCareer career) {
    final clearance = career.offseasonClearance;
    if (clearance.status != OffseasonClearanceStatus.collectingHumanOffers) {
      throw StateError('Clearance is not collecting offers');
    }
    final aiOffers = _generateAiOffers(career);
    final ids = {
      for (final offer in [...clearance.humanOffers, ...aiOffers])
        offer.playerId.value,
    }.toList()..sort();
    return _replace(
      career,
      clearance.copyWith(
        status: OffseasonClearanceStatus.preparedForResolution,
        aiOffers: aiOffers,
        resolutionOrder: [for (final id in ids) PlayerId(id)],
        nextResolutionIndex: 0,
        outcomes: const [],
      ),
    );
  }

  GmCareer resolveNext(GmCareer career) {
    final clearance = career.offseasonClearance;
    if (!clearance.isResolvable) {
      throw StateError('Clearance is not ready for resolution');
    }
    if (clearance.nextResolutionIndex >= clearance.resolutionOrder.length) {
      return _complete(career);
    }
    final playerId = clearance.resolutionOrder[clearance.nextResolutionIndex];
    final offers = [
      for (final offer in clearance.allOffers)
        if (offer.playerId == playerId) offer,
    ];
    final results = <FreeAgentMarketOfferResult>[];
    final rejected = <FreeAgentMarketOffer, FreeAgentOfferDecision>{};
    final accepted = <FreeAgentMarketOffer>[];
    for (final offer in offers) {
      final decision = evaluator.evaluate(
        career: career,
        teamId: offer.teamId,
        freeAgentId: offer.playerId,
        category: offer.category,
        durationYears: offer.durationYears,
        agreedFirstYearSalary: offer.firstYearSalary,
        clearanceOffer: true,
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
        default:
          rejected[offer] = decision;
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
      final team = career.league.teams.firstWhere(
        (candidate) => candidate.id == offer.teamId,
      );
      if (team.roster.standardCount >= RosterRules.minRegularSeasonStandard) {
        results.add(
          FreeAgentMarketOfferResult(
            offerId: offer.offerId,
            teamId: offer.teamId,
            outcome: FreeAgentMarketOfferOutcome.financiallyUnavailable,
            reasonCode: 'rosterAlreadyAtMinimum',
          ),
        );
        continue;
      }
      try {
        won = acquisition.acquire(
          career: career,
          teamId: offer.teamId,
          freeAgentId: offer.playerId,
          category: offer.category,
          durationYears: offer.durationYears,
          agreedFirstYearSalary: offer.firstYearSalary,
          origin: AcquisitionOrigin.clearance,
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
        if (offer.offerId == winner.offerId ||
            unavailable.contains(offer.offerId)) {
          continue;
        }
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
    for (final entry in rejected.entries) {
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
      results
        ..removeWhere(
          (result) =>
              result.offerId == winner!.offerId &&
              result.outcome == FreeAgentMarketOfferOutcome.outbid,
        )
        ..add(
          FreeAgentMarketOfferResult(
            offerId: winner.offerId,
            teamId: winner.teamId,
            outcome: FreeAgentMarketOfferOutcome.accepted,
            reasonCode: 'accepted',
          ),
        );
    }
    final outcome = FreeAgentMarketOutcome(
      playerId: playerId,
      winningTeamId: winner?.teamId,
      winningOfferId: winner?.offerId,
      results: results,
    );
    final nextIndex = clearance.nextResolutionIndex + 1;
    final complete = nextIndex >= clearance.resolutionOrder.length;
    final updated = clearance.copyWith(
      status: complete
          ? OffseasonClearanceStatus.complete
          : OffseasonClearanceStatus.resolving,
      nextResolutionIndex: nextIndex,
      outcomes: [...clearance.outcomes, outcome],
    );
    return _replace((won ?? career).copyWith(freeAgentOffers: ledger), updated);
  }

  GmCareer markCleared(GmCareer career) {
    final gate = readiness.evaluate(career);
    if (gate.status != OffseasonReadinessStatus.readyForConfirmation) {
      _fail(
        ValidationCode.financialTeamInvalid,
        'League is not ready for clearance: ${gate.reasons.join('; ')}',
      );
    }
    return _replace(
      career,
      career.offseasonClearance.copyWith(
        status: OffseasonClearanceStatus.cleared,
      ),
    );
  }

  List<FreeAgentMarketOffer> _generateAiOffers(GmCareer career) {
    final offers = <FreeAgentMarketOffer>[];
    final aiTeams =
        career.league.teams
            .where((team) => team.id != career.userFranchiseId)
            .toList()
          ..sort(
            (a, b) =>
                _fnv('3:${a.id.value}').compareTo(_fnv('3:${b.id.value}')),
          );
    for (final team in aiTeams) {
      final need =
          RosterRules.minRegularSeasonStandard - team.roster.standardCount;
      if (need <= 0) continue;
      final candidates =
          [
            for (final entry in career.freeAgentPool.entries)
              if (career.freeAgentOffers.remainingAttempts(
                    teamId: team.id,
                    playerId: entry.id,
                    seasonYear: career.currentYear,
                  ) >
                  0)
                entry,
          ]..sort((a, b) {
            final aView = a.toPublicView();
            final bView = b.toPublicView();
            if (aView.overallRating != bView.overallRating) {
              return bView.overallRating.compareTo(aView.overallRating);
            }
            return _fnv(
              '${team.id.value}:${a.id.value}',
            ).compareTo(_fnv('${team.id.value}:${b.id.value}'));
          });
      var added = 0;
      var committedCap = 0;
      var committedCash = 0;
      final capPayroll = career.finances.capPayrollFor(
        team.id,
        career.currentYear,
      );
      final allowedCap =
          FinancialRules.salaryCap +
          career.finances.financesFor(team.id).capException;
      final projected = career.finances.projectedEndOfSeasonCash(
        team.id,
        career.currentYear,
      );
      for (final entry in candidates) {
        if (added >= need) break;
        final view = entry.toPublicView();
        final valuation = market.estimate(view);
        final duration = valuation.preferredDurationYears;
        int? salary;
        for (final candidate in <int>{
          FinancialRules.minimumSalary,
          valuation.acceptableMinimum,
          valuation.estimatedAnnualSalary,
          valuation.acceptableMaximum,
        }) {
          if (salary != null) break;
          final decision = evaluator.evaluate(
            career: career,
            teamId: team.id,
            freeAgentId: entry.id,
            category: RosterCategory.standard,
            durationYears: duration,
            agreedFirstYearSalary: candidate,
            clearanceOffer: true,
          );
          if (!decision.isAcceptable) continue;
          final totalCap = capPayroll + committedCap + candidate;
          if (totalCap > allowedCap ||
              (totalCap > FinancialRules.salaryCap &&
                  candidate != FinancialRules.minimumSalary)) {
            continue;
          }
          if (projected - committedCash - candidate < 0) continue;
          salary = candidate;
        }
        if (salary == null) continue;
        final offer = FreeAgentMarketOffer(
          offerId: FreeAgentMarketOffer.idFor(
            teamId: team.id,
            playerId: entry.id,
            roundNumber: 3,
            seasonYear: career.currentYear,
          ),
          playerId: entry.id,
          teamId: team.id,
          roundNumber: 3,
          seasonYear: career.currentYear,
          category: RosterCategory.standard,
          durationYears: duration,
          firstYearSalary: salary,
          source: FreeAgentMarketOfferSource.ai,
        );
        offers.add(offer);
        added++;
        committedCap += salary;
        committedCash += salary;
      }
    }
    return offers;
  }

  void _validateReservation({
    required GmCareer career,
    required PlayerId playerId,
    required int durationYears,
    required int salary,
    required List<FreeAgentMarketOffer> humanOffers,
  }) {
    final team = career.userTeam;
    final requiredPlayers =
        RosterRules.minRegularSeasonStandard - team.roster.standardCount;
    if (humanOffers.length >= requiredPlayers) {
      _fail(ValidationCode.rosterCapacityExceeded, 'Too many clearance offers');
    }
    final capPayroll = career.finances.capPayrollFor(
      team.id,
      career.currentYear,
    );
    final pendingCap = humanOffers.fold<int>(
      0,
      (sum, offer) => sum + offer.firstYearSalary,
    );
    final finances = career.finances.financesFor(team.id);
    final totalCap = capPayroll + pendingCap + salary;
    final allowedCap = FinancialRules.salaryCap + finances.capException;
    if (totalCap > allowedCap) {
      _fail(ValidationCode.capBreach, 'Clearance cap reservation exceeded');
    }
    if (totalCap > FinancialRules.salaryCap &&
        salary != FinancialRules.minimumSalary) {
      _fail(
        ValidationCode.capBreach,
        'Cap exception can only fund 400 CU minimum deals',
      );
    }
    final projected = career.finances.projectedEndOfSeasonCash(
      team.id,
      career.currentYear,
    );
    if (projected - pendingCap - salary < 0) {
      _fail(
        ValidationCode.cashInsufficient,
        'Clearance cash reservation failed',
      );
    }
    if (team.roster.standardCount + humanOffers.length + 1 >
        RosterRules.maxOffseasonStandard) {
      _fail(
        ValidationCode.rosterCapacityExceeded,
        'Clearance standard roster capacity exceeded',
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
        'Clearance attempt limit reached',
      );
    }
    return ledger.add(
      FreeAgentOfferAttempt(
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
      ),
    );
  }

  GmCareer _complete(GmCareer career) => _replace(
    career,
    career.offseasonClearance.copyWith(
      status: OffseasonClearanceStatus.complete,
    ),
  );

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

  static GmCareer _replace(
    GmCareer career,
    OffseasonClearanceState clearance,
  ) => career.copyWith(offseasonClearance: clearance);

  static Never _fail(ValidationCode code, String message) =>
      throw DomainValidationException([
        ValidationIssue(
          code: code,
          path: 'offseasonClearance',
          message: message,
        ),
      ]);

  static int _fnv(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}
