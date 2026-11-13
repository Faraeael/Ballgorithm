import '../finance/financial_rules.dart';
import '../finance/financial_transactions.dart';
import '../models/franchise_situation.dart';
import '../models/free_agent.dart';
import '../models/ids.dart';
import '../models/player_contract.dart';
import '../models/roster_category.dart';
import '../models/offseason_clearance.dart';
import '../models/free_agent_market.dart';
import '../models/hardship_settlement.dart';
import '../models/team.dart';
import 'career_phase.dart';
import 'free_agent_market_value_service.dart';
import 'gm_career.dart';

/// Outcome of one hypothetical free-agent offer.
enum FreeAgentOfferStatus {
  acceptable('acceptable'),
  invalidTerms('invalidTerms'),
  financiallyIllegal('financiallyIllegal'),
  salaryTooLow('salaryTooLow'),
  unfavorableDuration('unfavorableDuration'),
  poorFit('poorFit'),
  inappropriateCategory('inappropriateCategory');

  const FreeAgentOfferStatus(this.jsonValue);

  final String jsonValue;
}

/// Read-only offer decision plus the public valuation used.
final class FreeAgentOfferDecision {
  const FreeAgentOfferDecision({
    required this.status,
    required this.reasonCode,
    required this.explanation,
    required this.valuation,
  });

  final FreeAgentOfferStatus status;
  final String reasonCode;
  final String explanation;
  final MarketValuation valuation;

  bool get isAcceptable => status == FreeAgentOfferStatus.acceptable;

  /// True for acceptable offers and player-side rejections. False for invalid
  /// terms or franchise financial/roster failure.
  bool get isFinanciallyLegal =>
      status != FreeAgentOfferStatus.invalidTerms &&
      status != FreeAgentOfferStatus.financiallyIllegal;
}

/// Player response without implying that the franchise can afford the offer.
final class PlayerOfferWillingness {
  const PlayerOfferWillingness({
    required this.status,
    required this.reasonCode,
    required this.explanation,
    required this.valuation,
  });

  final FreeAgentOfferStatus status;
  final String reasonCode;
  final String explanation;
  final MarketValuation valuation;

  bool get accepts => status == FreeAgentOfferStatus.acceptable;
}

/// Deterministic, public-information offer acceptance policy.
///
/// The evaluator never mutates the career, pool, roster, contracts, ledger or
/// cash. It only computes whether the franchise could make the offer and whether
/// the player would accept it.
final class FreeAgentOfferEvaluator {
  const FreeAgentOfferEvaluator({
    this.market = const FreeAgentMarketValueService(),
  });

  final FreeAgentMarketValueService market;

  FreeAgentOfferDecision evaluate({
    required GmCareer career,
    required TeamId teamId,
    required PlayerId freeAgentId,
    required RosterCategory category,
    required int durationYears,
    required int agreedFirstYearSalary,
    bool clearanceOffer = false,
    String? hardshipOfferId,
  }) {
    final entry = career.freeAgentPool.byId(freeAgentId);
    if (entry == null) {
      return _invalid('unknownPlayer', 'Player is not available');
    }
    final team = _team(career, teamId);
    if (team == null) {
      return _invalid('unknownTeam', 'Franchise does not exist');
    }
    if (category != RosterCategory.standard &&
        category != RosterCategory.twoWay) {
      return _invalid(
        'unsupportedCategory',
        'Offers must be standard or two-way',
      );
    }
    final maxDuration = FinancialRules.maxDurationForCategory(category);
    if (durationYears < PlayerContract.minDurationYears ||
        durationYears > maxDuration) {
      return _invalid(
        'invalidDuration',
        'Duration must be 1..$maxDuration for ${category.jsonValue}',
      );
    }
    final view = entry.toPublicView();
    final valuation = category == RosterCategory.twoWay
        ? _twoWayValuation(view)
        : market.estimate(view);

    final List<int> salaries;
    if (category == RosterCategory.twoWay) {
      if (agreedFirstYearSalary != FinancialRules.twoWaySalary) {
        return _invalid('invalidSalary', 'Two-way salary must be 250 CU');
      }
      salaries = FinancialRules.twoWaySchedule(durationYears);
    } else {
      if (agreedFirstYearSalary < FinancialRules.minimumSalary ||
          agreedFirstYearSalary > FinancialRules.maximumSalary) {
        return _invalid(
          'invalidSalary',
          'Standard salary must be 400..8000 CU',
        );
      }
      salaries = FinancialRules.standardSchedule(
        agreedFirstYearSalary,
        durationYears,
      );
      for (var i = 0; i < salaries.length; i++) {
        if (salaries[i] > FinancialRules.maximumSalary) {
          return _invalid(
            'invalidSalary',
            'Salary year ${i + 1} exceeds 8000 CU',
          );
        }
      }
    }

    final legality = _financialLegality(
      career: career,
      team: team,
      entry: entry,
      category: category,
      durationYears: durationYears,
      salaries: salaries,
      clearanceOffer: clearanceOffer,
      hardshipOfferId: hardshipOfferId,
    );
    if (legality != null) {
      return FreeAgentOfferDecision(
        status: FreeAgentOfferStatus.financiallyIllegal,
        reasonCode: legality,
        explanation: _legalityExplanation(legality),
        valuation: valuation,
      );
    }

    return _playerDecision(
      career: career,
      team: team,
      view: view,
      category: category,
      durationYears: durationYears,
      salary: agreedFirstYearSalary,
      valuation: valuation,
    );
  }

  /// Evaluates player response only; it does not assess cap, cash or roster
  /// legality. Use [evaluate] before treating this as a legal offer.
  PlayerOfferWillingness evaluateWillingness({
    required GmCareer career,
    required TeamId teamId,
    required PlayerId freeAgentId,
    required RosterCategory category,
    required int durationYears,
    required int salary,
  }) {
    final entry = career.freeAgentPool.byId(freeAgentId);
    final team = _team(career, teamId);
    if (entry == null || team == null) {
      return PlayerOfferWillingness(
        status: FreeAgentOfferStatus.invalidTerms,
        reasonCode: entry == null ? 'unknownPlayer' : 'unknownTeam',
        explanation: entry == null
            ? 'Player is not available'
            : 'Franchise does not exist',
        valuation: _emptyValuation(),
      );
    }
    if (category != RosterCategory.standard &&
        category != RosterCategory.twoWay) {
      return PlayerOfferWillingness(
        status: FreeAgentOfferStatus.invalidTerms,
        reasonCode: 'unsupportedCategory',
        explanation: 'Offers must be standard or two-way',
        valuation: _emptyValuation(),
      );
    }
    final maxDuration = FinancialRules.maxDurationForCategory(category);
    if (durationYears < PlayerContract.minDurationYears ||
        durationYears > maxDuration) {
      return PlayerOfferWillingness(
        status: FreeAgentOfferStatus.invalidTerms,
        reasonCode: 'invalidDuration',
        explanation: 'Duration must be 1..$maxDuration',
        valuation: _emptyValuation(),
      );
    }
    final salaryValid = category == RosterCategory.twoWay
        ? salary == FinancialRules.twoWaySalary
        : salary >= FinancialRules.minimumSalary &&
              salary <= FinancialRules.maximumSalary;
    if (!salaryValid) {
      return PlayerOfferWillingness(
        status: FreeAgentOfferStatus.invalidTerms,
        reasonCode: 'invalidSalary',
        explanation: 'Salary is outside the allowed category range',
        valuation: _emptyValuation(),
      );
    }
    final view = entry.toPublicView();
    final valuation = category == RosterCategory.twoWay
        ? _twoWayValuation(view)
        : market.estimate(view);
    final decision = _playerDecision(
      career: career,
      team: team,
      view: view,
      category: category,
      durationYears: durationYears,
      salary: salary,
      valuation: valuation,
    );
    return PlayerOfferWillingness(
      status: decision.status,
      reasonCode: decision.reasonCode,
      explanation: decision.explanation,
      valuation: valuation,
    );
  }

  FreeAgentOfferDecision _playerDecision({
    required GmCareer career,
    required Team team,
    required PublicFreeAgentView view,
    required RosterCategory category,
    required int durationYears,
    required int salary,
    required MarketValuation valuation,
  }) {
    if (category == RosterCategory.twoWay) {
      if (view.overallRating >= 65 || view.age >= 27) {
        return FreeAgentOfferDecision(
          status: FreeAgentOfferStatus.inappropriateCategory,
          reasonCode: 'notTwoWayEligible',
          explanation:
              'Player is an established rotation option and will not accept '
              'a two-way contract.',
          valuation: valuation,
        );
      }
      return FreeAgentOfferDecision(
        status: FreeAgentOfferStatus.acceptable,
        reasonCode: 'acceptedTwoWay',
        explanation:
            'Player accepts a developmental two-way opportunity at 250 CU.',
        valuation: valuation,
      );
    }

    if (view.age >= 35 && durationYears > 2) {
      return FreeAgentOfferDecision(
        status: FreeAgentOfferStatus.unfavorableDuration,
        reasonCode: 'veteranDuration',
        explanation: 'Veteran player will not commit to more than two years.',
        valuation: valuation,
      );
    }

    var fitBp = _situationFit(team, view);
    fitBp += _depthFit(team, view);
    if (fitBp < -2000) fitBp = -2000;
    if (fitBp > 2000) fitBp = 2000;

    final baseRequired = _round(
      valuation.acceptableMinimum * (10000 - fitBp) ~/ 10000,
    );
    final durationGap = (durationYears - valuation.preferredDurationYears)
        .abs();
    final durationBp = durationGap * 300;
    final requiredSalary = _clamp(
      _round(baseRequired * (10000 + durationBp) ~/ 10000),
    );

    if (salary >= requiredSalary) {
      return FreeAgentOfferDecision(
        status: FreeAgentOfferStatus.acceptable,
        reasonCode: 'accepted',
        explanation:
            'Player accepts the offer: salary, duration and role meet the '
            'public expectation.',
        valuation: valuation,
      );
    }
    if (salary >= baseRequired) {
      return FreeAgentOfferDecision(
        status: FreeAgentOfferStatus.unfavorableDuration,
        reasonCode: 'durationCompensation',
        explanation:
            'Player declines the proposed duration without additional '
            'compensation.',
        valuation: valuation,
      );
    }
    if (fitBp <= -1200) {
      return FreeAgentOfferDecision(
        status: FreeAgentOfferStatus.poorFit,
        reasonCode: 'roleOrFranchiseFit',
        explanation:
            'Player declines the role and franchise situation as presented.',
        valuation: valuation,
      );
    }
    return FreeAgentOfferDecision(
      status: FreeAgentOfferStatus.salaryTooLow,
      reasonCode: 'salaryBelowExpectation',
      explanation:
          'Player declines: the offered salary is below the expected public '
          'market range for this role.',
      valuation: valuation,
    );
  }

  /// Null when financially legal; otherwise a public reason code.
  String? _financialLegality({
    required GmCareer career,
    required Team team,
    required FreeAgentEntry entry,
    required RosterCategory category,
    required int durationYears,
    required List<int> salaries,
    required bool clearanceOffer,
    required String? hardshipOfferId,
  }) {
    if (career.phase != CareerPhase.openingOffseason) {
      return 'wrongPhase';
    }
    if (career.freeAgentPool.acquisitions.hasPlayer(entry.id)) {
      return 'alreadyAcquired';
    }
    final roster = team.roster.withPlayer(entry.player, category: category);
    if (!roster.validateStructure(phase: career.phase).isValid) {
      return 'rosterCapacityExceeded';
    }
    final capPayroll = career.finances.capPayrollFor(
      team.id,
      career.currentYear,
    );
    if (clearanceOffer && hardshipOfferId != null) {
      return 'conflictingFinancialAuthority';
    }
    if (category == RosterCategory.standard) {
      final ordinaryException = clearanceOffer
          ? _authorizedClearanceException(career, team)
          : 0;
      final hardshipException = hardshipOfferId == null
          ? 0
          : _authorizedHardshipRelief(
              career,
              team,
              entry.id,
              durationYears,
              salaries.first,
              hardshipOfferId,
            );
      if (hardshipOfferId != null && hardshipException == 0) {
        return 'hardshipNotAuthorized';
      }
      final payrollAfter = capPayroll + salaries.first;
      final allowedRelief = hardshipOfferId == null
          ? ordinaryException
          : career.finances.financesFor(team.id).capException +
                hardshipException;
      if (payrollAfter > FinancialRules.salaryCap + allowedRelief) {
        return 'capBreach';
      }
      if (payrollAfter > FinancialRules.salaryCap &&
          salaries.first != FinancialRules.minimumSalary &&
          hardshipOfferId == null) {
        return 'capBreach';
      }
    } else if (clearanceOffer || hardshipOfferId != null) {
      return 'hardshipCategoryInvalid';
    }
    final contract = PlayerContract(
      id: PlayerContract.idFor(entry.id, career.currentYear),
      playerId: entry.id,
      teamId: team.id,
      category: category,
      startYear: career.currentYear,
      durationYears: durationYears,
      source: ContractSource.freeAgent,
    );
    final finances = FinancialTransactions.addContract(
      finances: career.finances,
      contract: contract,
      annualSalaries: salaries,
    );
    if (finances.projectedEndOfSeasonCash(team.id, career.currentYear) < 0) {
      return 'cashInsufficient';
    }
    return null;
  }

  int _authorizedClearanceException(GmCareer career, Team team) {
    final clearance = career.offseasonClearance;
    if (clearance.seasonYear != career.currentYear ||
        career.freeAgentMarket.status != FreeAgentMarketStatus.marketComplete ||
        ![
          OffseasonClearanceStatus.collectingHumanOffers,
          OffseasonClearanceStatus.preparedForResolution,
          OffseasonClearanceStatus.resolving,
          OffseasonClearanceStatus.complete,
        ].contains(clearance.status) ||
        team.roster.standardCount >= FinancialRules.minimumStandardRoster) {
      return 0;
    }
    final exception = clearance.capExceptions
        .where((candidate) => candidate.teamId == team.id)
        .firstOrNull;
    if (exception == null ||
        career.finances.financesFor(team.id).capException != exception.amount) {
      return 0;
    }
    return exception.amount;
  }

  int _authorizedHardshipRelief(
    GmCareer career,
    Team team,
    PlayerId playerId,
    int durationYears,
    int salary,
    String offerId,
  ) {
    final settlement = career.hardshipSettlement;
    final authorization = settlement.authorizationFor(team.id);
    final offer = settlement.offerById(offerId);
    if (career.phase != CareerPhase.openingOffseason ||
        career.freeAgentMarket.status != FreeAgentMarketStatus.marketComplete ||
        career.offseasonClearance.status != OffseasonClearanceStatus.complete ||
        !settlement.isResolvable ||
        settlement.seasonYear != career.currentYear ||
        settlement.nextResolutionIndex >= settlement.resolutionOrder.length ||
        settlement.resolutionOrder[settlement.nextResolutionIndex] !=
            playerId ||
        team.roster.standardCount >= FinancialRules.minimumStandardRoster ||
        offer == null ||
        offer.teamId != team.id ||
        offer.playerId != playerId ||
        offer.seasonYear != career.currentYear ||
        offer.durationYears != durationYears ||
        offer.firstYearSalary != salary ||
        authorization == null ||
        authorization.status != HardshipAuthorizationStatus.unused &&
            authorization.status != HardshipAuthorizationStatus.consumed ||
        !authorization.authorizedOfferIds.contains(offerId) ||
        authorization.seasonYear != career.currentYear ||
        authorization.existingOrdinaryRelief !=
            career.finances.financesFor(team.id).capException ||
        authorization.additionalAmount < 1 ||
        authorization.existingOrdinaryRelief + authorization.additionalAmount >
            FinancialRules.maximumCombinedHardshipOverage ||
        authorization.maximumCombinedOverage !=
            FinancialRules.maximumCombinedHardshipOverage ||
        authorization.usedAmount > authorization.additionalAmount) {
      return 0;
    }
    return authorization.additionalAmount;
  }

  MarketValuation _emptyValuation() => const MarketValuation(
    estimatedAnnualSalary: FinancialRules.minimumSalary,
    acceptableMinimum: FinancialRules.minimumSalary,
    acceptableMaximum: FinancialRules.minimumSalary,
    preferredDurationYears: 1,
    expectedRole: ExpectedPlayerRole.developmental,
    explanation: 'No public player valuation available',
  );

  int _situationFit(Team team, PublicFreeAgentView view) {
    final age = view.age;
    return switch (team.situation) {
      FranchiseSituation.tanking => age <= 24 ? 1200 : (age >= 30 ? -1000 : 0),
      FranchiseSituation.contender => age >= 30 ? 1000 : (age <= 24 ? -300 : 0),
      FranchiseSituation.playoff => age >= 30 ? 500 : 0,
      _ => 0,
    };
  }

  int _depthFit(Team team, PublicFreeAgentView view) {
    final samePosition = team.players
        .where((player) => player.position == view.position)
        .toList();
    final stronger = samePosition
        .where(
          (player) => player.attributes.overallRating >= view.overallRating - 2,
        )
        .length;
    if (stronger >= 2) return -1200;
    if (stronger == 1) return -400;
    if (samePosition.isEmpty) return 800;
    return 0;
  }

  FreeAgentOfferDecision _invalid(String code, String explanation) =>
      FreeAgentOfferDecision(
        status: FreeAgentOfferStatus.invalidTerms,
        reasonCode: code,
        explanation: explanation,
        valuation: const MarketValuation(
          estimatedAnnualSalary: 0,
          acceptableMinimum: 0,
          acceptableMaximum: 0,
          preferredDurationYears: 0,
          expectedRole: ExpectedPlayerRole.developmental,
          explanation: 'No valuation: offer terms are invalid.',
        ),
      );

  MarketValuation _twoWayValuation(PublicFreeAgentView view) => MarketValuation(
    estimatedAnnualSalary: FinancialRules.twoWaySalary,
    acceptableMinimum: FinancialRules.twoWaySalary,
    acceptableMaximum: FinancialRules.twoWaySalary,
    preferredDurationYears: view.age <= 22 ? 2 : 1,
    expectedRole: market.expectedRole(view),
    explanation:
        'Two-way compensation is fixed at 250 CU by the approved rules.',
  );

  String _legalityExplanation(String code) => switch (code) {
    'capBreach' => 'Franchise cannot fit the offer under the 41,000 CU cap.',
    'cashInsufficient' => 'Franchise would fail current-year cash solvency.',
    'rosterCapacityExceeded' => 'Franchise roster category is full.',
    'alreadyAcquired' => 'Player has already been acquired.',
    'wrongPhase' => 'Acquisition is not allowed in this career phase.',
    _ => 'Offer is not financially legal.',
  };

  static int _round(int value) => ((value + 5) ~/ 10) * 10;

  static int _clamp(int value) => value < FinancialRules.minimumSalary
      ? FinancialRules.minimumSalary
      : (value > FinancialRules.maximumSalary
            ? FinancialRules.maximumSalary
            : value);

  static Team? _team(GmCareer career, TeamId teamId) {
    for (final team in career.league.teams) {
      if (team.id == teamId) return team;
    }
    return null;
  }
}
