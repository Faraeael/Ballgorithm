import '../models/free_agent.dart';
import '../models/free_agent_acquisition.dart';
import '../models/free_agent_market.dart';
import '../models/free_agent_offer.dart';
import '../models/hardship_settlement.dart';
import '../models/ids.dart';
import '../models/league.dart';
import '../models/offseason_clearance.dart';
import '../models/player_career_profile.dart';
import '../models/player_contract.dart';
import '../models/roster_category.dart';
import '../validation/validation_result.dart';
import 'career_phase.dart';
import 'gm_career.dart';
import 'free_agent_offer_evaluator.dart';
import '../finance/financial_rules.dart';
import '../finance/financial_transactions.dart';

/// Atomic acquisition of one available free agent by one franchise.
///
/// The caller supplies explicit proposed terms. T08D enforces financial
/// legality; it does not decide what offer a player would accept.
final class FreeAgentAcquisitionService {
  const FreeAgentAcquisitionService();

  GmCareer acquire({
    required GmCareer career,
    required TeamId teamId,
    required PlayerId freeAgentId,
    required RosterCategory category,
    required int durationYears,
    required int agreedFirstYearSalary,
    AcquisitionOrigin origin = AcquisitionOrigin.initialPool,
    String? hardshipOfferId,
    HardshipSettlement? hardshipSettlementAfterAcquisition,
    FreeAgentOfferLedger? freeAgentOffersAfterAcquisition,
  }) {
    if (career.phase != CareerPhase.openingOffseason) {
      throw StateError('Free-agent acquisition requires the opening offseason');
    }
    final entry = career.freeAgentPool.byId(freeAgentId);
    if (entry == null) {
      _fail(
        ValidationCode.freeAgentInvalid,
        'Player ${freeAgentId.value} is not in the available free-agent pool',
      );
    }
    if (career.freeAgentPool.acquisitions.hasPlayer(freeAgentId)) {
      _fail(
        ValidationCode.freeAgentAcquisitionInvalid,
        'Player ${freeAgentId.value} has already been acquired',
      );
    }
    final team = career.league.teams
        .where((candidate) => candidate.id == teamId)
        .firstOrNull;
    if (team == null) {
      _fail(
        ValidationCode.freeAgentInvalid,
        'Franchise ${teamId.value} does not exist',
      );
    }
    if (category != RosterCategory.standard &&
        category != RosterCategory.twoWay) {
      _fail(
        ValidationCode.contractInvalid,
        'Free-agent contracts must be standard or two-way',
      );
    }
    final maxDuration = FinancialRules.maxDurationForCategory(category);
    if (durationYears < PlayerContract.minDurationYears ||
        durationYears > maxDuration) {
      _fail(
        ValidationCode.contractInvalid,
        'Contract duration must be '
        '${PlayerContract.minDurationYears}..$maxDuration for '
        '${category.jsonValue}, got $durationYears',
      );
    }

    final List<int> salaries;
    if (category == RosterCategory.twoWay) {
      if (agreedFirstYearSalary != FinancialRules.twoWaySalary) {
        _fail(
          ValidationCode.salaryOutOfBounds,
          'Two-way salary must be exactly ${FinancialRules.twoWaySalary} CU',
        );
      }
      salaries = FinancialRules.twoWaySchedule(durationYears);
    } else {
      if (agreedFirstYearSalary < FinancialRules.minimumSalary ||
          agreedFirstYearSalary > FinancialRules.maximumSalary) {
        _fail(
          ValidationCode.salaryOutOfBounds,
          'Standard salary must be '
          '${FinancialRules.minimumSalary}..'
          '${FinancialRules.maximumSalary} CU',
        );
      }
      salaries = FinancialRules.standardSchedule(
        agreedFirstYearSalary,
        durationYears,
      );
      for (var i = 0; i < salaries.length; i++) {
        if (salaries[i] > FinancialRules.maximumSalary) {
          _fail(
            ValidationCode.salaryOutOfBounds,
            'Salary year ${i + 1} (${salaries[i]}) exceeds the maximum '
            '${FinancialRules.maximumSalary} CU',
          );
        }
      }
    }

    final updatedRoster = team.roster.withPlayer(
      entry.player,
      category: category,
    );
    final capacity = updatedRoster.validateStructure(phase: career.phase);
    if (!capacity.isValid) {
      _fail(
        ValidationCode.rosterCapacityExceeded,
        'Roster capacity exceeded: ${capacity.issues.join('; ')}',
      );
    }

    final capPayroll = career.finances.capPayrollFor(
      teamId,
      career.currentYear,
    );
    final addedCapSalary = category == RosterCategory.standard
        ? salaries.first
        : 0;
    if (origin == AcquisitionOrigin.clearance) {
      if (hardshipOfferId != null ||
          hardshipSettlementAfterAcquisition != null ||
          freeAgentOffersAfterAcquisition != null) {
        _fail(
          ValidationCode.freeAgentAcquisitionInvalid,
          'Clearance acquisition cannot carry hardship authorization',
        );
      }
      _validateClearanceAuthorization(
        career: career,
        teamId: teamId,
        freeAgentId: freeAgentId,
        category: category,
        durationYears: durationYears,
        salary: agreedFirstYearSalary,
      );
    } else if (origin == AcquisitionOrigin.hardship) {
      if (hardshipOfferId == null ||
          hardshipSettlementAfterAcquisition == null ||
          freeAgentOffersAfterAcquisition == null) {
        _fail(
          ValidationCode.freeAgentAcquisitionInvalid,
          'Hardship acquisition requires one authorized settlement commit',
        );
      }
      _validateHardshipAuthorization(
        career: career,
        teamId: teamId,
        freeAgentId: freeAgentId,
        category: category,
        durationYears: durationYears,
        salary: agreedFirstYearSalary,
        offerId: hardshipOfferId,
        settlementAfterAcquisition: hardshipSettlementAfterAcquisition,
        offersAfterAcquisition: freeAgentOffersAfterAcquisition,
      );
    } else if (hardshipOfferId != null ||
        hardshipSettlementAfterAcquisition != null ||
        freeAgentOffersAfterAcquisition != null) {
      _fail(
        ValidationCode.freeAgentAcquisitionInvalid,
        'Ordinary acquisition cannot carry hardship authorization',
      );
    }
    final capException = switch (origin) {
      AcquisitionOrigin.clearance =>
        career.finances.financesFor(teamId).capException,
      AcquisitionOrigin.hardship =>
        career.finances.financesFor(teamId).capException +
            career.hardshipSettlement
                .authorizationFor(teamId)!
                .additionalAmount,
      AcquisitionOrigin.initialPool => 0,
    };
    final payrollAfter = capPayroll + addedCapSalary;
    if (payrollAfter > FinancialRules.salaryCap + capException ||
        (payrollAfter > FinancialRules.salaryCap &&
            agreedFirstYearSalary != FinancialRules.minimumSalary &&
            origin != AcquisitionOrigin.hardship)) {
      _fail(
        ValidationCode.capBreach,
        'Cap payroll $payrollAfter exceeds its authorized limit',
      );
    }

    final contract = PlayerContract(
      id: PlayerContract.idFor(freeAgentId, career.currentYear),
      playerId: freeAgentId,
      teamId: teamId,
      category: category,
      startYear: career.currentYear,
      durationYears: durationYears,
      source: ContractSource.freeAgent,
    );
    final updatedFinances = FinancialTransactions.addContract(
      finances: career.finances,
      contract: contract,
      annualSalaries: salaries,
    );
    if (updatedFinances.projectedEndOfSeasonCash(teamId, career.currentYear) <
        0) {
      _fail(
        ValidationCode.cashInsufficient,
        'Franchise ${teamId.value} would fail current-year cash solvency',
      );
    }

    final acquisition = FreeAgentAcquisition(
      transactionId: FreeAgentAcquisition.idFor(
        freeAgentId,
        career.currentYear,
      ),
      playerId: freeAgentId,
      teamId: teamId,
      contractId: contract.id,
      seasonYear: career.currentYear,
      category: category,
      origin: origin,
    );
    final updatedPool = FreeAgentPool(
      entries: [
        for (final candidate in career.freeAgentPool.entries)
          if (candidate.id != freeAgentId) candidate,
      ],
      initialPlayerIds: career.freeAgentPool.initialPlayerIds,
      acquisitions: career.freeAgentPool.acquisitions.add(acquisition),
    );
    final updatedTeam = team.copyWith(roster: updatedRoster);
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
      profiles: {
        ...career.careerProfiles.profiles,
        freeAgentId.value: entry.profile,
      },
    );
    return career.copyWith(
      league: updatedLeague,
      careerProfiles: updatedProfiles,
      freeAgentPool: updatedPool,
      finances: updatedFinances,
      hardshipSettlement: hardshipSettlementAfterAcquisition,
      freeAgentOffers: freeAgentOffersAfterAcquisition,
    );
  }

  void _validateClearanceAuthorization({
    required GmCareer career,
    required TeamId teamId,
    required PlayerId freeAgentId,
    required RosterCategory category,
    required int durationYears,
    required int salary,
  }) {
    final state = career.offseasonClearance;
    if (category != RosterCategory.standard ||
        !state.isResolvable ||
        state.seasonYear != career.currentYear ||
        career.freeAgentMarket.status != FreeAgentMarketStatus.marketComplete ||
        state.nextResolutionIndex >= state.resolutionOrder.length ||
        state.resolutionOrder[state.nextResolutionIndex] != freeAgentId) {
      _fail(
        ValidationCode.freeAgentAcquisitionInvalid,
        'Clearance acquisition has no active authorization',
      );
    }
    final authorizedOffer = state.allOffers.any(
      (offer) =>
          offer.playerId == freeAgentId &&
          offer.teamId == teamId &&
          offer.category == category &&
          offer.durationYears == durationYears &&
          offer.firstYearSalary == salary,
    );
    if (!authorizedOffer) {
      _fail(
        ValidationCode.freeAgentAcquisitionInvalid,
        'Clearance acquisition does not match a sealed offer',
      );
    }
    final team = career.league.teams.firstWhere(
      (candidate) => candidate.id == teamId,
    );
    if (team.roster.standardCount >= FinancialRules.minimumStandardRoster) {
      _fail(
        ValidationCode.rosterCapacityExceeded,
        'Clearance cannot sign an optional 15th standard player',
      );
    }
    if (career.freeAgentOffers.remainingAttempts(
          teamId: teamId,
          playerId: freeAgentId,
          seasonYear: career.currentYear,
        ) <=
        0) {
      _fail(
        ValidationCode.freeAgentOfferLimitReached,
        'Clearance offer has no player-side attempt remaining',
      );
    }
    career.validate();
    final decision = const FreeAgentOfferEvaluator().evaluate(
      career: career,
      teamId: teamId,
      freeAgentId: freeAgentId,
      category: category,
      durationYears: durationYears,
      agreedFirstYearSalary: salary,
      clearanceOffer: true,
    );
    if (!decision.isAcceptable) {
      _fail(
        ValidationCode.freeAgentOfferInvalid,
        'Clearance transaction is not an acceptable offer: '
        '${decision.reasonCode}',
      );
    }
  }

  void _validateHardshipAuthorization({
    required GmCareer career,
    required TeamId teamId,
    required PlayerId freeAgentId,
    required RosterCategory category,
    required int durationYears,
    required int salary,
    required String offerId,
    required HardshipSettlement? settlementAfterAcquisition,
    required FreeAgentOfferLedger? offersAfterAcquisition,
  }) {
    final settlement = career.hardshipSettlement;
    final authorization = settlement.authorizationFor(teamId);
    final offer = settlement.offerById(offerId);
    final team = career.league.teams.firstWhere(
      (candidate) => candidate.id == teamId,
    );
    if (category != RosterCategory.standard ||
        !settlement.isResolvable ||
        settlement.seasonYear != career.currentYear ||
        career.freeAgentMarket.status != FreeAgentMarketStatus.marketComplete ||
        career.offseasonClearance.status != OffseasonClearanceStatus.complete ||
        settlement.nextResolutionIndex >= settlement.resolutionOrder.length ||
        settlement.resolutionOrder[settlement.nextResolutionIndex] !=
            freeAgentId ||
        team.roster.standardCount >= FinancialRules.minimumStandardRoster ||
        offer == null ||
        offer.teamId != teamId ||
        offer.playerId != freeAgentId ||
        offer.seasonYear != career.currentYear ||
        offer.durationYears != durationYears ||
        offer.firstYearSalary != salary ||
        authorization == null ||
        !authorization.authorizedOfferIds.contains(offerId) ||
        authorization.existingOrdinaryRelief !=
            career.finances.financesFor(teamId).capException) {
      _fail(
        ValidationCode.freeAgentAcquisitionInvalid,
        'Hardship acquisition has no exact active authorization',
      );
    }
    if (career.freeAgentOffers.remainingAttempts(
          teamId: teamId,
          playerId: freeAgentId,
          seasonYear: career.currentYear,
        ) <=
        0) {
      _fail(
        ValidationCode.freeAgentOfferLimitReached,
        'Hardship offer has no player-side attempt remaining',
      );
    }
    career.validate();
    final decision = const FreeAgentOfferEvaluator().evaluate(
      career: career,
      teamId: teamId,
      freeAgentId: freeAgentId,
      category: category,
      durationYears: durationYears,
      agreedFirstYearSalary: salary,
      hardshipOfferId: offerId,
    );
    if (!decision.isAcceptable) {
      _fail(
        ValidationCode.freeAgentOfferInvalid,
        'Hardship transaction is not acceptable: ${decision.reasonCode}',
      );
    }
    final transactionId = FreeAgentAcquisition.idFor(
      freeAgentId,
      career.currentYear,
    );
    final committedOffer = settlementAfterAcquisition?.offerById(offerId);
    final committedOutcome = settlementAfterAcquisition?.outcomes
        .where((outcome) => outcome.playerId == freeAgentId)
        .firstOrNull;
    final committedAuthorization = settlementAfterAcquisition?.authorizationFor(
      teamId,
    );
    final committedAttempt = offersAfterAcquisition?.entries[offerId];
    if (committedOffer == null ||
        committedOutcome?.winningOfferId != offerId ||
        committedOutcome?.winningTeamId != teamId ||
        !committedOutcome!.results.any(
          (result) =>
              result.offerId == offerId &&
              result.outcome == FreeAgentMarketOfferOutcome.accepted,
        ) ||
        committedAuthorization == null ||
        committedAuthorization.status != HardshipAuthorizationStatus.consumed ||
        !committedAuthorization.transactionIds.contains(transactionId) ||
        committedAttempt == null ||
        !committedAttempt.outcome.isAccepted ||
        committedAttempt.playerId != freeAgentId ||
        committedAttempt.teamId != teamId ||
        committedAttempt.seasonYear != career.currentYear ||
        committedAttempt.durationYears != durationYears ||
        committedAttempt.firstYearSalary != salary ||
        committedAttempt.acquisitionTransactionId != transactionId) {
      _fail(
        ValidationCode.freeAgentAcquisitionInvalid,
        'Hardship acquisition lacks one atomic recorded settlement result',
      );
    }
  }

  static Never _fail(ValidationCode code, String message) =>
      throw DomainValidationException([
        ValidationIssue(
          code: code,
          path: 'freeAgentAcquisition',
          message: message,
        ),
      ]);
}
