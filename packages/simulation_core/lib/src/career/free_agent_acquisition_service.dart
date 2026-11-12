import '../models/free_agent.dart';
import '../models/free_agent_acquisition.dart';
import '../models/free_agent_market.dart';
import '../models/ids.dart';
import '../models/league.dart';
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
      _validateClearanceAuthorization(
        career: career,
        teamId: teamId,
        freeAgentId: freeAgentId,
        category: category,
        durationYears: durationYears,
        salary: agreedFirstYearSalary,
      );
    }
    final capException = origin == AcquisitionOrigin.clearance
        ? career.finances.financesFor(teamId).capException
        : 0;
    final payrollAfter = capPayroll + addedCapSalary;
    if (payrollAfter > FinancialRules.salaryCap + capException ||
        (payrollAfter > FinancialRules.salaryCap &&
            agreedFirstYearSalary != FinancialRules.minimumSalary)) {
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

  static Never _fail(ValidationCode code, String message) =>
      throw DomainValidationException([
        ValidationIssue(
          code: code,
          path: 'freeAgentAcquisition',
          message: message,
        ),
      ]);
}
