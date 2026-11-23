import '../finance/financial_rules.dart';
import '../models/free_agent.dart';
import '../models/free_agent_market.dart';
import '../models/free_agent_offer.dart';
import '../models/franchise_situation.dart';
import '../models/ids.dart';
import '../models/position.dart';
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
      final positionCounts = <Position, int>{
        for (final position in Position.values) position: 0,
      };
      for (final player in team.players) {
        positionCounts[player.position] =
            (positionCounts[player.position] ?? 0) + 1;
      }
      final needsCoverageBoost =
          standardNeed <= 0 &&
          team.roster.standardCount < RosterRules.maxOffseasonStandard &&
          positionCounts.values.any((count) => count == 0);
      if (standardNeed <= 0 && twoWayNeed <= 0 && !needsCoverageBoost) {
        continue;
      }
      final twoWayLimit = twoWayNeed > 0 ? 1 : 0;

      final baseCandidates = [
        for (final entry in career.freeAgentPool.entries)
          if (career.freeAgentOffers.remainingAttempts(
                teamId: team.id,
                playerId: entry.id,
                seasonYear: career.currentYear,
              ) >
              0)
            entry,
      ]..sort((a, b) => _compareBasePriority(a, b, team, targetCounts));

      var standardAdded = 0;
      var twoWayAdded = 0;
      var committedCash = 0;
      var committedCap = 0;
      final standardCount = team.roster.standardCount;
      final twoWayCount = team.roster.twoWayCount;
      final totalCount = team.roster.totalContractedCount;
      final capPayroll = career.finances.capPayrollFor(
        team.id,
        career.currentYear,
      );
      final projectedCash = career.finances.projectedEndOfSeasonCash(
        team.id,
        career.currentYear,
      );
      final offeredPlayerIds = <String>{};
      final stagedForTeam =
          <({FreeAgentEntry entry, FreeAgentMarketOffer offer})>[];
      var simulatedTeam = team;

      final byPosition = <Position, List<FreeAgentEntry>>{
        for (final pos in Position.values) pos: <FreeAgentEntry>[],
      };
      for (final entry in baseCandidates) {
        byPosition[entry.player.position]!.add(entry);
      }

      final cursors = <Position, int>{
        for (final pos in Position.values) pos: 0,
      };

      void runPass({
        required RosterCategory category,
        required int maxOffers,
        required bool uncoveredPositionsOnly,
        required Map<Position, int> passCursors,
      }) {
        if (maxOffers <= 0) return;
        var stagedInPass = 0;
        while (stagedInPass < maxOffers) {
          final entry = _nextCandidate(
            byPosition,
            passCursors,
            positionCounts,
            team,
            targetCounts,
          );
          if (entry == null) break;
          if (offeredPlayerIds.contains(entry.id.value)) continue;

          final view = entry.toPublicView();
          final coversUncovered = (positionCounts[view.position] ?? 0) == 0;
          if (uncoveredPositionsOnly && !coversUncovered) continue;
          if (category == RosterCategory.twoWay &&
              (view.overallRating >= 65 || view.age >= 27)) {
            continue;
          }

          final valuation = market.estimate(view);
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

          final priorAttempts = career.freeAgentOffers.attemptsFor(
            teamId: team.id,
            playerId: entry.id,
            seasonYear: career.currentYear,
          );
          final int? acceptedSalary;
          if (category == RosterCategory.standard) {
            acceptedSalary = _lowestAcceptableStandardSalary(
              career: career,
              willingnessTeam: simulatedTeam,
              team: team,
              playerId: entry.id,
              durationYears: duration,
              estimatedSalary: salary,
              upperBoundSalary: valuation.acceptableMaximum.clamp(
                FinancialRules.minimumSalary,
                maxSalary,
              ),
              priorAttempts: priorAttempts,
            );
          } else {
            final alreadyRejected = priorAttempts.any(
              (attempt) =>
                  !attempt.outcome.isAccepted &&
                  attempt.category == RosterCategory.twoWay &&
                  attempt.durationYears == duration &&
                  attempt.firstYearSalary == salary,
            );
            if (alreadyRejected) {
              acceptedSalary = null;
            } else {
              final decision = evaluator.evaluate(
                career: career,
                teamId: team.id,
                freeAgentId: entry.id,
                category: RosterCategory.twoWay,
                durationYears: duration,
                agreedFirstYearSalary: salary,
              );
              acceptedSalary =
                  decision.isFinanciallyLegal && decision.isAcceptable
                  ? salary
                  : null;
            }
          }
          if (acceptedSalary == null) continue;

          final addedCap = category == RosterCategory.standard
              ? acceptedSalary
              : 0;
          final addedStandard = category == RosterCategory.standard ? 1 : 0;
          final addedTwoWay = category == RosterCategory.twoWay ? 1 : 0;
          final standardPlayersAfter =
              standardCount + standardAdded + addedStandard;
          final remainingMandatorySlots =
              standardPlayersAfter < FinancialRules.minimumStandardRoster
              ? FinancialRules.minimumStandardRoster - standardPlayersAfter
              : 0;

          if (category == RosterCategory.standard &&
              standardPlayersAfter <= FinancialRules.minimumStandardRoster &&
              !coversUncovered) {
            final uncoveredAfter = positionCounts.values
                .where((count) => count == 0)
                .length;
            if (remainingMandatorySlots < uncoveredAfter) {
              continue;
            }
          }

          final minimumFutureStandardCost =
              remainingMandatorySlots * FinancialRules.minimumSalary;
          if (category == RosterCategory.standard &&
              capPayroll + committedCap + addedCap + minimumFutureStandardCost >
                  FinancialRules.salaryCap) {
            continue;
          }
          if (standardPlayersAfter > RosterRules.maxOffseasonStandard) {
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
          if (projectedCash -
                  committedCash -
                  acceptedSalary -
                  minimumFutureStandardCost <
              0) {
            continue;
          }

          final stagedOffer = FreeAgentMarketOffer(
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
          );
          stagedForTeam.add((entry: entry, offer: stagedOffer));
          simulatedTeam = simulatedTeam.copyWith(
            roster: simulatedTeam.roster.withPlayer(
              entry.player,
              category: category,
            ),
          );
          offeredPlayerIds.add(entry.id.value);
          positionCounts[view.position] =
              (positionCounts[view.position] ?? 0) + 1;
          standardAdded += addedStandard;
          twoWayAdded += addedTwoWay;
          committedCap += addedCap;
          committedCash += acceptedSalary;
          targetCounts[entry.id.value] =
              (targetCounts[entry.id.value] ?? 0) + 1;
          stagedInPass++;
        }
      }

      if (standardNeed > 0) {
        runPass(
          category: RosterCategory.standard,
          maxOffers: standardNeed,
          uncoveredPositionsOnly: false,
          passCursors: cursors,
        );
      }
      if (standardCount + standardAdded >=
          FinancialRules.minimumStandardRoster) {
        runPass(
          category: RosterCategory.twoWay,
          maxOffers: twoWayLimit,
          uncoveredPositionsOnly: false,
          passCursors: cursors,
        );
      }
      final uncoveredAfterPrimary = positionCounts.values
          .where((count) => count == 0)
          .length;
      if (uncoveredAfterPrimary > 0 &&
          standardCount + standardAdded < RosterRules.maxOffseasonStandard) {
        runPass(
          category: RosterCategory.standard,
          maxOffers:
              RosterRules.maxOffseasonStandard -
              (standardCount + standardAdded),
          uncoveredPositionsOnly: true,
          passCursors: {for (final pos in Position.values) pos: 0},
        );
      }

      // FreeAgentMarketService resolves offers sorted by playerId ascending,
      // so later-staged offers with smaller IDs can lower _depthFit for
      // earlier-staged same-position offers during resolution. Re-verify
      // against the resolution-ordered prefix roster and bump if affordable.
      if (stagedForTeam.length > 1) {
        final byResolutionOrder = List.of(stagedForTeam)
          ..sort(
            (a, b) => a.offer.playerId.value.compareTo(b.offer.playerId.value),
          );
        final remainingMandatoryAfterStaged =
            standardCount + standardAdded < FinancialRules.minimumStandardRoster
            ? FinancialRules.minimumStandardRoster -
                  (standardCount + standardAdded)
            : 0;
        final reserve =
            remainingMandatoryAfterStaged * FinancialRules.minimumSalary;
        var spareCap =
            FinancialRules.salaryCap - capPayroll - committedCap - reserve;
        var spareCash = projectedCash - committedCash - reserve;
        var prefixTeam = team;
        final adjustedByOfferId = <String, FreeAgentMarketOffer>{};
        for (final item in byResolutionOrder) {
          final currentOffer = item.offer;
          if (currentOffer.category == RosterCategory.standard) {
            final view = item.entry.toPublicView();
            final valuation = market.estimate(view);
            final maxSalary = FreeAgentMarketValueService.maxYearOneForDuration(
              currentOffer.durationYears,
            );
            final estimatedSalary = valuation.estimatedAnnualSalary > maxSalary
                ? maxSalary
                : valuation.estimatedAnnualSalary;
            final safeSalary = _lowestAcceptableStandardSalary(
              career: career,
              willingnessTeam: prefixTeam,
              team: team,
              playerId: currentOffer.playerId,
              durationYears: currentOffer.durationYears,
              estimatedSalary: estimatedSalary,
              upperBoundSalary: valuation.acceptableMaximum.clamp(
                FinancialRules.minimumSalary,
                maxSalary,
              ),
              priorAttempts: career.freeAgentOffers.attemptsFor(
                teamId: team.id,
                playerId: currentOffer.playerId,
                seasonYear: career.currentYear,
              ),
            );
            if (safeSalary != null &&
                safeSalary > currentOffer.firstYearSalary) {
              final delta = safeSalary - currentOffer.firstYearSalary;
              if (delta <= spareCap && delta <= spareCash) {
                spareCap -= delta;
                spareCash -= delta;
                adjustedByOfferId[currentOffer.offerId] = FreeAgentMarketOffer(
                  offerId: currentOffer.offerId,
                  playerId: currentOffer.playerId,
                  teamId: currentOffer.teamId,
                  roundNumber: currentOffer.roundNumber,
                  seasonYear: currentOffer.seasonYear,
                  category: currentOffer.category,
                  durationYears: currentOffer.durationYears,
                  firstYearSalary: safeSalary,
                  source: currentOffer.source,
                );
              }
            }
          }
          prefixTeam = prefixTeam.copyWith(
            roster: prefixTeam.roster.withPlayer(
              item.entry.player,
              category: currentOffer.category,
            ),
          );
        }
        for (final item in stagedForTeam) {
          offers.add(adjustedByOfferId[item.offer.offerId] ?? item.offer);
        }
      } else {
        for (final item in stagedForTeam) {
          offers.add(item.offer);
        }
      }
    }
    return offers;
  }

  int? _lowestAcceptableStandardSalary({
    required GmCareer career,
    required Team willingnessTeam,
    required Team team,
    required PlayerId playerId,
    required int durationYears,
    required int estimatedSalary,
    required int upperBoundSalary,
    required List<FreeAgentOfferAttempt> priorAttempts,
  }) {
    var low = FinancialRules.minimumSalary;
    var high = upperBoundSalary + 1;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      final willingness = evaluator.evaluateWillingness(
        career: career,
        teamId: team.id,
        freeAgentId: playerId,
        category: RosterCategory.standard,
        durationYears: durationYears,
        salary: mid,
        teamOverride: willingnessTeam,
      );
      if (willingness.accepts) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    if (low > upperBoundSalary) return null;
    final candidates = <int>{
      low,
      if (estimatedSalary >= low && estimatedSalary <= upperBoundSalary)
        estimatedSalary,
      upperBoundSalary,
    };
    for (final candidate in candidates) {
      if (priorAttempts.any(
        (attempt) =>
            !attempt.outcome.isAccepted &&
            attempt.category == RosterCategory.standard &&
            attempt.durationYears == durationYears &&
            attempt.firstYearSalary == candidate,
      )) {
        continue;
      }
      final decision = evaluator.evaluate(
        career: career,
        teamId: team.id,
        freeAgentId: playerId,
        category: RosterCategory.standard,
        durationYears: durationYears,
        agreedFirstYearSalary: candidate,
      );
      if (decision.isFinanciallyLegal && decision.isAcceptable) {
        return candidate;
      }
    }
    return null;
  }

  FreeAgentEntry? _nextCandidate(
    Map<Position, List<FreeAgentEntry>> byPosition,
    Map<Position, int> cursors,
    Map<Position, int> positionCounts,
    Team team,
    Map<String, int> targetCounts,
  ) {
    Position? bestPos;
    FreeAgentEntry? bestEntry;
    var bestUncovered = 2;
    var bestContested = 1 << 30;
    var bestCount = 1 << 30;
    for (final pos in Position.values) {
      final list = byPosition[pos]!;
      final idx = cursors[pos]!;
      if (idx >= list.length) continue;
      final candidate = list[idx];
      final count = positionCounts[pos] ?? 0;
      final uncovered = count == 0 ? 0 : 1;
      final contested = targetCounts[candidate.id.value] ?? 0;
      final isBetter =
          bestEntry == null ||
          uncovered < bestUncovered ||
          (uncovered == bestUncovered &&
              (contested < bestContested ||
                  (contested == bestContested &&
                      (count < bestCount ||
                          (count == bestCount &&
                              _compareBasePriority(
                                    candidate,
                                    bestEntry,
                                    team,
                                    targetCounts,
                                  ) <
                                  0)))));
      if (isBetter) {
        bestPos = pos;
        bestEntry = candidate;
        bestUncovered = uncovered;
        bestContested = contested;
        bestCount = count;
      }
    }
    if (bestPos != null) {
      cursors[bestPos] = cursors[bestPos]! + 1;
    }
    return bestEntry;
  }

  int _compareBasePriority(
    FreeAgentEntry a,
    FreeAgentEntry b,
    Team team,
    Map<String, int> targetCounts,
  ) {
    final aView = a.toPublicView();
    final bView = b.toPublicView();
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
