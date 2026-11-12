import '../finance/financial_rules.dart';
import '../models/free_agent.dart';
import '../models/free_agent_market.dart';
import '../models/franchise_situation.dart';
import '../models/roster_category.dart';
import '../models/roster_rules.dart';
import '../models/team.dart';
import 'free_agent_market_value_service.dart';
import 'free_agent_offer_evaluator.dart';
import 'gm_career.dart';

/// Deterministic, public-information-only AI offer generation.
final class AiFreeAgentOfferPolicy {
  const AiFreeAgentOfferPolicy({
    this.market = const FreeAgentMarketValueService(),
    this.evaluator = const FreeAgentOfferEvaluator(),
  });

  final FreeAgentMarketValueService market;
  final FreeAgentOfferEvaluator evaluator;

  List<FreeAgentMarketOffer> generateOffers({
    required GmCareer career,
    required FreeAgentMarketState marketState,
  }) {
    final offers = <FreeAgentMarketOffer>[];
    final targetCounts = <String, int>{};
    final aiTeams =
        career.league.teams
            .where((team) => team.id != career.userFranchiseId)
            .toList()
          ..sort(
            (a, b) => _fnv1a(
              '${marketState.roundNumber}:${a.id.value}',
            ).compareTo(_fnv1a('${marketState.roundNumber}:${b.id.value}')),
          );
    for (final team in aiTeams) {
      final standardNeed =
          FinancialRules.minimumStandardRoster - team.roster.standardCount;
      final twoWayNeed =
          FinancialRules.maximumTwoWayPlayers - team.roster.twoWayCount;
      if (standardNeed <= 0 && twoWayNeed <= 0) continue;
      final twoWayLimit = twoWayNeed > 0 ? 1 : 0;

      final candidates = [
        for (final entry in career.freeAgentPool.entries)
          if (career.freeAgentOffers.remainingAttempts(
                teamId: team.id,
                playerId: entry.id,
                seasonYear: career.currentYear,
              ) >
              0)
            entry,
      ]..sort((a, b) => _compareCandidates(a, b, team, targetCounts));

      var standardAdded = 0;
      var twoWayAdded = 0;
      var committedCash = 0;
      var committedCap = 0;
      var standardCount = team.roster.standardCount;
      var twoWayCount = team.roster.twoWayCount;
      var totalCount = team.roster.totalContractedCount;
      final capPayroll = career.finances.capPayrollFor(
        team.id,
        career.currentYear,
      );
      final projectedCash = career.finances.projectedEndOfSeasonCash(
        team.id,
        career.currentYear,
      );

      for (final entry in candidates) {
        final needStandard = standardNeed - standardAdded;
        final needTwoWay = twoWayLimit - twoWayAdded;
        if (needStandard <= 0 && needTwoWay <= 0) break;
        final view = entry.toPublicView();
        final valuation = market.estimate(view);
        final category = needStandard > 0
            ? RosterCategory.standard
            : RosterCategory.twoWay;
        if (category == RosterCategory.twoWay &&
            (view.overallRating >= 65 || view.age >= 27)) {
          continue;
        }
        final duration = category == RosterCategory.standard
            ? valuation.preferredDurationYears
            : (view.age <= 22 ? 2 : 1);
        final maxSalary = category == RosterCategory.standard
            ? FreeAgentMarketValueService.maxYearOneForDuration(duration)
            : FinancialRules.twoWaySalary;
        final salary = category == RosterCategory.standard
            ? (valuation.estimatedAnnualSalary > maxSalary
                  ? maxSalary
                  : valuation.estimatedAnnualSalary)
            : FinancialRules.twoWaySalary;

        int? acceptedSalary;
        for (final candidateSalary
            in category == RosterCategory.standard
                ? [salary, valuation.acceptableMaximum.clamp(400, maxSalary)]
                : [salary]) {
          final decision = evaluator.evaluate(
            career: career,
            teamId: team.id,
            freeAgentId: entry.id,
            category: category,
            durationYears: duration,
            agreedFirstYearSalary: candidateSalary,
          );
          if (!decision.isFinanciallyLegal) continue;
          if (decision.isAcceptable) {
            acceptedSalary = candidateSalary;
            break;
          }
        }
        if (acceptedSalary == null) continue;
        final priorAttempts = career.freeAgentOffers.attemptsFor(
          teamId: team.id,
          playerId: entry.id,
          seasonYear: career.currentYear,
        );
        if (priorAttempts.any(
          (attempt) =>
              !attempt.outcome.isAccepted &&
              attempt.category == category &&
              attempt.durationYears == duration &&
              attempt.firstYearSalary == acceptedSalary,
        )) {
          continue;
        }

        final addedCap = category == RosterCategory.standard
            ? acceptedSalary
            : 0;
        final addedStandard = category == RosterCategory.standard ? 1 : 0;
        final addedTwoWay = category == RosterCategory.twoWay ? 1 : 0;
        if (capPayroll + committedCap + addedCap > FinancialRules.salaryCap) {
          continue;
        }
        if (standardCount + standardAdded + addedStandard >
            RosterRules.maxOffseasonStandard) {
          continue;
        }
        if (twoWayCount + twoWayAdded + addedTwoWay >
            RosterRules.maxOffseasonTwoWay) {
          continue;
        }
        if (totalCount + standardAdded + twoWayAdded + 1 >
            RosterRules.maxOffseasonTotal) {
          continue;
        }
        if (projectedCash - committedCash - acceptedSalary < 0) continue;

        offers.add(
          FreeAgentMarketOffer(
            offerId: FreeAgentMarketOffer.idFor(
              teamId: team.id,
              playerId: entry.id,
              roundNumber: marketState.roundNumber,
              seasonYear: career.currentYear,
            ),
            playerId: entry.id,
            teamId: team.id,
            roundNumber: marketState.roundNumber,
            seasonYear: career.currentYear,
            category: category,
            durationYears: duration,
            firstYearSalary: acceptedSalary,
            source: FreeAgentMarketOfferSource.ai,
          ),
        );
        standardAdded += addedStandard;
        twoWayAdded += addedTwoWay;
        committedCap += addedCap;
        committedCash += acceptedSalary;
        targetCounts[entry.id.value] = (targetCounts[entry.id.value] ?? 0) + 1;
      }
    }
    return offers;
  }

  int _compareCandidates(
    FreeAgentEntry a,
    FreeAgentEntry b,
    Team team,
    Map<String, int> targetCounts,
  ) {
    final aView = a.toPublicView();
    final bView = b.toPublicView();
    final aPosition = team.players
        .where((player) => player.position == aView.position)
        .length;
    final bPosition = team.players
        .where((player) => player.position == bView.position)
        .length;
    if (aPosition != bPosition) return aPosition.compareTo(bPosition);
    final aContested = targetCounts[a.id.value] ?? 0;
    final bContested = targetCounts[b.id.value] ?? 0;
    if (aContested != bContested) return aContested.compareTo(bContested);
    final situation = team.situation ?? FranchiseSituation.playIn;
    switch (situation) {
      case FranchiseSituation.tanking:
        if (aView.age != bView.age) return aView.age.compareTo(bView.age);
        if (aView.overallRating != bView.overallRating) {
          return bView.overallRating.compareTo(aView.overallRating);
        }
      case FranchiseSituation.contender:
        if (aView.overallRating != bView.overallRating) {
          return bView.overallRating.compareTo(aView.overallRating);
        }
        if (aView.age != bView.age) return bView.age.compareTo(aView.age);
      case FranchiseSituation.playoff:
        if (aView.overallRating != bView.overallRating) {
          return bView.overallRating.compareTo(aView.overallRating);
        }
        if (aView.age != bView.age) return bView.age.compareTo(aView.age);
      case FranchiseSituation.playIn:
        if (aView.overallRating != bView.overallRating) {
          return bView.overallRating.compareTo(aView.overallRating);
        }
    }
    final aKey = _fnv1a('${team.id.value}:${a.id.value}');
    final bKey = _fnv1a('${team.id.value}:${b.id.value}');
    if (aKey != bKey) return aKey.compareTo(bKey);
    return a.id.value.compareTo(b.id.value);
  }

  static int _fnv1a(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}
