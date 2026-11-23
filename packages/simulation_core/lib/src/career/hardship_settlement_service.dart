import '../finance/financial_rules.dart';
import '../models/free_agent_acquisition.dart';
import '../models/free_agent_market.dart';
import '../models/free_agent_offer.dart';
import '../models/hardship_settlement.dart';
import '../models/ids.dart';
import '../models/roster_category.dart';
import '../models/roster_rules.dart';
import '../models/offseason_clearance.dart';
import '../models/team.dart';
import '../validation/validation_result.dart';
import 'career_phase.dart';
import 'competitive_offer_ranker.dart';
import 'free_agent_acquisition_service.dart';
import 'free_agent_offer_evaluator.dart';
import 'gm_career.dart';

final class HardshipTeamAssessment {
  HardshipTeamAssessment({
    required this.teamId,
    required this.abbreviation,
    required this.standardCount,
    required this.missingPlayers,
    required this.currentPayroll,
    required this.normalCapRoom,
    required this.ordinaryRelief,
    required this.projectedCash,
    required List<HardshipOffer> proposedOffers,
    required this.additionalAuthority,
    required this.combinedOverage,
    required List<String> blockers,
  }) : proposedOffers = List.unmodifiable(proposedOffers),
       blockers = List.unmodifiable(blockers);

  final TeamId teamId;
  final String abbreviation;
  final int standardCount;
  final int missingPlayers;
  final int currentPayroll;
  final int normalCapRoom;
  final int ordinaryRelief;
  final int projectedCash;
  final List<HardshipOffer> proposedOffers;
  final int additionalAuthority;
  final int combinedOverage;
  final List<String> blockers;

  bool get eligible => proposedOffers.isNotEmpty && additionalAuthority > 0;

  int get projectedCashAfterOffers =>
      projectedCash -
      proposedOffers.fold<int>(0, (sum, offer) => sum + offer.firstYearSalary);
}

final class HardshipPreparationReport {
  const HardshipPreparationReport({
    required this.career,
    required this.candidateCountsByTeam,
    required this.optionCountsByTeam,
    required this.exploredStates,
    required this.searchTruncated,
    required this.completedTeams,
    required this.filledSlots,
    required this.elapsedMicroseconds,
  });

  final GmCareer career;
  final Map<String, int> candidateCountsByTeam;
  final Map<String, int> optionCountsByTeam;
  final int exploredStates;
  final bool searchTruncated;
  final int completedTeams;
  final int filledSlots;
  final int elapsedMicroseconds;
}

/// One deterministic settlement after the original clearance has completed.
final class HardshipSettlementService {
  const HardshipSettlementService({
    this.evaluator = const FreeAgentOfferEvaluator(),
    this.ranker = const CompetitiveOfferRanker(),
    this.acquisition = const FreeAgentAcquisitionService(),
  });

  static const int _maxSingleCandidatesPerTeam = 24;
  static const int _maxOptionsPerTeam = 64;
  static const int _maxSearchStates = 20000;

  final FreeAgentOfferEvaluator evaluator;
  final CompetitiveOfferRanker ranker;
  final FreeAgentAcquisitionService acquisition;

  HardshipTeamAssessment assessTeam(GmCareer career, TeamId teamId) {
    final team = career.league.teams
        .where((candidate) => candidate.id == teamId)
        .firstOrNull;
    if (team == null) {
      throw ArgumentError.value(teamId, 'teamId', 'Unknown franchise');
    }
    final finances = career.finances.financesFor(teamId);
    final payroll = career.finances.capPayrollFor(teamId, career.currentYear);
    final capRoom = FinancialRules.salaryCap - payroll;
    final missing =
        RosterRules.minRegularSeasonStandard - team.roster.standardCount;
    final ordinaryRelief = finances.capException;
    final projectedCash = career.finances.projectedEndOfSeasonCash(
      teamId,
      career.currentYear,
    );
    final blockers = <String>[];

    if (career.phase != CareerPhase.openingOffseason) {
      blockers.add('Career is outside the opening offseason');
    }
    if (career.freeAgentMarket.status != FreeAgentMarketStatus.marketComplete ||
        career.freeAgentMarket.completedRounds != 2) {
      blockers.add('Both competitive market rounds must be complete');
    }
    if (career.offseasonClearance.status != OffseasonClearanceStatus.complete) {
      blockers.add('Original clearance must be complete');
    }
    if (career.hardshipSettlement.status !=
        HardshipSettlementStatus.notStarted) {
      blockers.add('Hardship settlement already started');
    }
    if (missing <= 0) blockers.add('No mandatory standard roster vacancy');
    if (missing > FinancialRules.maximumReliefDeals) {
      blockers.add('Shortage exceeds two standard players');
    }
    if (finances.capGrandfathered) {
      blockers.add('Grandfathered payroll cannot use hardship authority');
    }
    if (projectedCash < 0) blockers.add('Current projected cash is insolvent');
    if (blockers.isNotEmpty) {
      return HardshipTeamAssessment(
        teamId: teamId,
        abbreviation: team.abbreviation,
        standardCount: team.roster.standardCount,
        missingPlayers: missing > 0 ? missing : 0,
        currentPayroll: payroll,
        normalCapRoom: capRoom,
        ordinaryRelief: ordinaryRelief,
        projectedCash: projectedCash,
        proposedOffers: const [],
        additionalAuthority: 0,
        combinedOverage: ordinaryRelief,
        blockers: blockers,
      );
    }

    final candidates = <_HardshipCandidate>[];
    var attemptsBlocked = 0;
    for (final entry in career.freeAgentPool.entries) {
      if (career.freeAgentOffers.remainingAttempts(
            teamId: teamId,
            playerId: entry.id,
            seasonYear: career.currentYear,
          ) <=
          0) {
        attemptsBlocked++;
        continue;
      }
      final candidate = _cheapestAcceptableContract(
        career: career,
        teamId: teamId,
        playerId: entry.id,
      );
      if (candidate != null) candidates.add(candidate);
    }
    candidates.sort(_compareCandidates);
    if (candidates.isEmpty) {
      blockers.add(
        attemptsBlocked == career.freeAgentPool.length
            ? 'All remaining free agents have exhausted player-side attempts'
            : 'No available free agent accepts a standard contract',
      );
      return HardshipTeamAssessment(
        teamId: teamId,
        abbreviation: team.abbreviation,
        standardCount: team.roster.standardCount,
        missingPlayers: missing,
        currentPayroll: payroll,
        normalCapRoom: capRoom,
        ordinaryRelief: ordinaryRelief,
        projectedCash: projectedCash,
        proposedOffers: const [],
        additionalAuthority: 0,
        combinedOverage: ordinaryRelief,
        blockers: blockers,
      );
    }

    var ordinarySlots = 0;
    var ordinarySalary = 0;
    for (final candidate in candidates) {
      if (ordinarySlots >= missing) break;
      final nextSalary = ordinarySalary + candidate.offer.firstYearSalary;
      final payrollAfter = payroll + nextSalary;
      final ordinaryLegal =
          payrollAfter <= FinancialRules.salaryCap ||
          (candidate.offer.firstYearSalary == FinancialRules.minimumSalary &&
              payrollAfter <= FinancialRules.salaryCap + ordinaryRelief);
      if (ordinaryLegal && projectedCash >= nextSalary) {
        ordinarySlots++;
        ordinarySalary = nextSalary;
      }
    }
    if (ordinarySlots >= missing) {
      blockers.add(
        'Existing cap room and ordinary relief can fund all vacancies',
      );
      return HardshipTeamAssessment(
        teamId: teamId,
        abbreviation: team.abbreviation,
        standardCount: team.roster.standardCount,
        missingPlayers: missing,
        currentPayroll: payroll,
        normalCapRoom: capRoom,
        ordinaryRelief: ordinaryRelief,
        projectedCash: projectedCash,
        proposedOffers: const [],
        additionalAuthority: 0,
        combinedOverage: ordinaryRelief,
        blockers: blockers,
      );
    }

    final selected = <HardshipOffer>[];
    var committedSalary = 0;
    for (final candidate in candidates) {
      if (selected.length >= missing) break;
      var effectiveSelected0 = selected.isNotEmpty ? selected.first : null;
      var effectiveNextOffer = candidate.offer;
      if (effectiveSelected0 != null) {
        final firstPlayer = career.freeAgentPool
            .byId(effectiveSelected0.playerId)!
            .player;
        final secondPlayer = career.freeAgentPool
            .byId(effectiveNextOffer.playerId)!
            .player;
        if (firstPlayer.position == secondPlayer.position) {
          if (effectiveSelected0.playerId.value.compareTo(
                effectiveNextOffer.playerId.value,
              ) <
              0) {
            final adjustedSecond = _cheapestAcceptableContract(
              career: career,
              teamId: teamId,
              playerId: effectiveNextOffer.playerId,
              teamOverride: team.copyWith(
                roster: team.roster.withPlayer(
                  firstPlayer,
                  category: RosterCategory.standard,
                ),
              ),
            );
            if (adjustedSecond == null) continue;
            effectiveNextOffer = adjustedSecond.offer;
          } else {
            final adjustedFirst = _cheapestAcceptableContract(
              career: career,
              teamId: teamId,
              playerId: effectiveSelected0.playerId,
              teamOverride: team.copyWith(
                roster: team.roster.withPlayer(
                  secondPlayer,
                  category: RosterCategory.standard,
                ),
              ),
            );
            if (adjustedFirst == null) continue;
            effectiveSelected0 = adjustedFirst.offer;
          }
        }
      }
      final nextSalary =
          (effectiveSelected0?.firstYearSalary ?? 0) +
          effectiveNextOffer.firstYearSalary;
      final overage = payroll + nextSalary - FinancialRules.salaryCap;
      final additional = overage > ordinaryRelief
          ? overage - ordinaryRelief
          : 0;
      if (ordinaryRelief + additional >
              FinancialRules.maximumCombinedHardshipOverage ||
          projectedCash - nextSalary < 0) {
        continue;
      }
      if (effectiveSelected0 != null) {
        selected[0] = effectiveSelected0;
      }
      selected.add(effectiveNextOffer);
      committedSalary = nextSalary;
    }
    final totalOverage = payroll + committedSalary - FinancialRules.salaryCap;
    final additional = totalOverage > ordinaryRelief
        ? totalOverage - ordinaryRelief
        : 0;
    if (selected.isEmpty || additional <= 0) {
      blockers.add(
        'No willing contract fits cash and the 1,000 CU combined overage ceiling',
      );
      return HardshipTeamAssessment(
        teamId: teamId,
        abbreviation: team.abbreviation,
        standardCount: team.roster.standardCount,
        missingPlayers: missing,
        currentPayroll: payroll,
        normalCapRoom: capRoom,
        ordinaryRelief: ordinaryRelief,
        projectedCash: projectedCash,
        proposedOffers: const [],
        additionalAuthority: 0,
        combinedOverage: ordinaryRelief,
        blockers: blockers,
      );
    }
    if (selected.length < missing) {
      blockers.add(
        'Only ${selected.length} willing contract(s) fit the approved ceiling '
        'for $missing vacancy/vacancies',
      );
    }
    return HardshipTeamAssessment(
      teamId: teamId,
      abbreviation: team.abbreviation,
      standardCount: team.roster.standardCount,
      missingPlayers: missing,
      currentPayroll: payroll,
      normalCapRoom: capRoom,
      ordinaryRelief: ordinaryRelief,
      projectedCash: projectedCash,
      proposedOffers: selected,
      additionalAuthority: additional,
      combinedOverage: ordinaryRelief + additional,
      blockers: blockers,
    );
  }

  List<HardshipOffer> proposedHumanOffers(GmCareer career) =>
      assessTeam(career, career.userFranchiseId).proposedOffers;

  GmCareer prepare(
    GmCareer career, {
    required bool humanParticipationConfirmed,
  }) => prepareWithReport(
    career,
    humanParticipationConfirmed: humanParticipationConfirmed,
  ).career;

  HardshipPreparationReport prepareWithReport(
    GmCareer career, {
    required bool humanParticipationConfirmed,
  }) {
    if (career.phase != CareerPhase.openingOffseason ||
        career.freeAgentMarket.status != FreeAgentMarketStatus.marketComplete ||
        career.offseasonClearance.status != OffseasonClearanceStatus.complete ||
        career.hardshipSettlement.status !=
            HardshipSettlementStatus.notStarted) {
      _fail('Hardship settlement is not authorized in this career state');
    }
    career.validate();
    final stopwatch = Stopwatch()..start();

    final teams = [...career.league.teams]
      ..sort((left, right) => left.id.value.compareTo(right.id.value));

    final humanOffers = humanParticipationConfirmed
        ? assessTeam(career, career.userFranchiseId).proposedOffers
        : const <HardshipOffer>[];
    final humanTargets = <String>{
      for (final offer in humanOffers) offer.playerId.value,
    };

    final teamPlans = <_TeamHardshipPlan>[];
    final candidateCountsByTeam = <String, int>{};
    final optionCountsByTeam = <String, int>{};
    var optionsTruncated = false;

    for (final team in teams) {
      if (team.id == career.userFranchiseId) continue;
      final plan = _buildTeamPlan(career, team, humanTargets);
      if (plan == null) continue;
      candidateCountsByTeam[team.id.value] = plan.affordableCandidateCount;
      optionCountsByTeam[team.id.value] = plan.options.length;
      if (plan.optionsTruncated) optionsTruncated = true;
      if (plan.options.isNotEmpty) {
        teamPlans.add(plan);
      }
    }

    final solved = _solveJointAllocation(teamPlans);

    final offers = <HardshipOffer>[...humanOffers];
    for (final plan in teamPlans) {
      final chosen = solved.assignments[plan.teamId.value];
      if (chosen != null) {
        offers.addAll(chosen.offers);
      }
    }
    offers.sort((left, right) {
      final team = left.teamId.value.compareTo(right.teamId.value);
      return team != 0
          ? team
          : left.playerId.value.compareTo(right.playerId.value);
    });

    final authorizations = <HardshipAuthorization>[];
    for (final team in teams) {
      final teamOffers = offers
          .where((offer) => offer.teamId == team.id)
          .toList();
      if (teamOffers.isEmpty) continue;
      final payroll = career.finances.capPayrollFor(
        team.id,
        career.currentYear,
      );
      final ordinaryRelief = career.finances.financesFor(team.id).capException;
      final missing =
          RosterRules.minRegularSeasonStandard - team.roster.standardCount;
      final proposedTotal = teamOffers.fold<int>(
        0,
        (sum, offer) => sum + offer.firstYearSalary,
      );
      final overage = payroll + proposedTotal - FinancialRules.salaryCap;
      final requiredAdditional = overage > ordinaryRelief
          ? overage - ordinaryRelief
          : 0;
      if (requiredAdditional < 1 ||
          ordinaryRelief + requiredAdditional >
              FinancialRules.maximumCombinedHardshipOverage) {
        _fail('Coordinated hardship offer exceeds exact legal authority');
      }
      authorizations.add(
        HardshipAuthorization(
          authorizationId: HardshipAuthorization.idFor(
            team.id,
            career.currentYear,
          ),
          teamId: team.id,
          seasonYear: career.currentYear,
          additionalAmount: requiredAdditional,
          existingOrdinaryRelief: ordinaryRelief,
          maximumCombinedOverage: FinancialRules.maximumCombinedHardshipOverage,
          missingPlayers: missing,
          authorizedOfferIds: [for (final offer in teamOffers) offer.offerId],
          reason: hardshipAuthorizationReason,
          status: HardshipAuthorizationStatus.unused,
          usedAmount: 0,
          transactionIds: const [],
        ),
      );
    }
    final order = {for (final offer in offers) offer.playerId.value}.toList()
      ..sort();
    final settlement = HardshipSettlement(
      status: offers.isEmpty
          ? HardshipSettlementStatus.complete
          : HardshipSettlementStatus.preparedForResolution,
      seasonYear: career.currentYear,
      humanParticipationConfirmed: humanParticipationConfirmed,
      offers: offers,
      resolutionOrder: [for (final id in order) PlayerId(id)],
      nextResolutionIndex: 0,
      outcomes: const [],
      authorizations: authorizations,
    );
    stopwatch.stop();
    return HardshipPreparationReport(
      career: career.copyWith(hardshipSettlement: settlement),
      candidateCountsByTeam: Map.unmodifiable(candidateCountsByTeam),
      optionCountsByTeam: Map.unmodifiable(optionCountsByTeam),
      exploredStates: solved.exploredStates,
      searchTruncated: solved.truncated || optionsTruncated,
      completedTeams: solved.completedTeams,
      filledSlots: solved.filledSlots,
      elapsedMicroseconds: stopwatch.elapsedMicroseconds,
    );
  }

  _TeamHardshipPlan? _buildTeamPlan(
    GmCareer career,
    Team team,
    Set<String> humanTargets,
  ) {
    final finances = career.finances.financesFor(team.id);
    final payroll = career.finances.capPayrollFor(team.id, career.currentYear);
    final missing =
        RosterRules.minRegularSeasonStandard - team.roster.standardCount;
    final ordinaryRelief = finances.capException;
    final projectedCash = career.finances.projectedEndOfSeasonCash(
      team.id,
      career.currentYear,
    );
    if (missing <= 0 ||
        missing > FinancialRules.maximumReliefDeals ||
        finances.capGrandfathered ||
        projectedCash < 0) {
      return null;
    }

    final candidates = <_HardshipCandidate>[];
    for (final entry in career.freeAgentPool.entries) {
      if (career.freeAgentOffers.remainingAttempts(
            teamId: team.id,
            playerId: entry.id,
            seasonYear: career.currentYear,
          ) <=
          0) {
        continue;
      }
      final candidate = _cheapestAcceptableContract(
        career: career,
        teamId: team.id,
        playerId: entry.id,
      );
      if (candidate != null) candidates.add(candidate);
    }
    if (candidates.isEmpty) return null;
    candidates.sort(_compareCandidates);

    var ordinarySlots = 0;
    var ordinarySalary = 0;
    for (final candidate in candidates) {
      if (ordinarySlots >= missing) break;
      final nextSalary = ordinarySalary + candidate.offer.firstYearSalary;
      final payrollAfter = payroll + nextSalary;
      final ordinaryLegal =
          payrollAfter <= FinancialRules.salaryCap ||
          (candidate.offer.firstYearSalary == FinancialRules.minimumSalary &&
              payrollAfter <= FinancialRules.salaryCap + ordinaryRelief);
      if (ordinaryLegal && projectedCash >= nextSalary) {
        ordinarySlots++;
        ordinarySalary = nextSalary;
      }
    }
    if (ordinarySlots >= missing) return null;

    final affordableSingles = <_HardshipCandidate>[];
    for (final candidate in candidates) {
      final salary = candidate.offer.firstYearSalary;
      final overage = payroll + salary - FinancialRules.salaryCap;
      final additional = overage > ordinaryRelief
          ? overage - ordinaryRelief
          : 0;
      if (ordinaryRelief + additional <=
              FinancialRules.maximumCombinedHardshipOverage &&
          projectedCash - salary >= 0) {
        affordableSingles.add(candidate);
      }
    }
    if (affordableSingles.isEmpty) return null;

    final bounded = affordableSingles.length > _maxSingleCandidatesPerTeam
        ? affordableSingles.sublist(0, _maxSingleCandidatesPerTeam)
        : affordableSingles;
    final truncatedSingles =
        affordableSingles.length > _maxSingleCandidatesPerTeam;

    final options = <_HardshipOption>[];
    if (missing == 1) {
      for (final c in bounded) {
        final salary = c.offer.firstYearSalary;
        final overage = payroll + salary - FinancialRules.salaryCap;
        final additional = overage > ordinaryRelief
            ? overage - ordinaryRelief
            : 0;
        if (additional < 1 ||
            ordinaryRelief + additional >
                FinancialRules.maximumCombinedHardshipOverage ||
            projectedCash - salary < 0) {
          continue;
        }
        options.add(
          _HardshipOption(
            offers: [c.offer],
            targetIds: {c.offer.playerId.value},
            filledSlots: 1,
            isComplete: true,
            humanConflictCount: humanTargets.contains(c.offer.playerId.value)
                ? 1
                : 0,
            additionalAuthority: additional,
            totalFirstYearSalary: salary,
            totalScheduleSalary: c.totalSalary,
            canonicalKey: c.offer.playerId.value,
          ),
        );
      }
    } else {
      for (var i = 0; i < bounded.length; i++) {
        for (var j = i + 1; j < bounded.length; j++) {
          final a = bounded[i];
          final b = bounded[j];
          var first = a;
          var second = b;
          if (first.offer.playerId.value.compareTo(
                second.offer.playerId.value,
              ) >
              0) {
            first = b;
            second = a;
          }
          final firstPlayer = career.freeAgentPool
              .byId(first.offer.playerId)!
              .player;
          final secondPlayer = career.freeAgentPool
              .byId(second.offer.playerId)!
              .player;
          if (firstPlayer.position == secondPlayer.position) {
            final adjustedSecond = _cheapestAcceptableContract(
              career: career,
              teamId: team.id,
              playerId: second.offer.playerId,
              teamOverride: team.copyWith(
                roster: team.roster.withPlayer(
                  firstPlayer,
                  category: RosterCategory.standard,
                ),
              ),
            );
            if (adjustedSecond == null) continue;
            second = adjustedSecond;
          }
          final totalFirst =
              first.offer.firstYearSalary + second.offer.firstYearSalary;
          final overage = payroll + totalFirst - FinancialRules.salaryCap;
          final additional = overage > ordinaryRelief
              ? overage - ordinaryRelief
              : 0;
          if (additional < 1 ||
              ordinaryRelief + additional >
                  FinancialRules.maximumCombinedHardshipOverage ||
              projectedCash - totalFirst < 0) {
            continue;
          }
          final humanConflicts =
              (humanTargets.contains(first.offer.playerId.value) ? 1 : 0) +
              (humanTargets.contains(second.offer.playerId.value) ? 1 : 0);
          options.add(
            _HardshipOption(
              offers: [first.offer, second.offer],
              targetIds: {
                first.offer.playerId.value,
                second.offer.playerId.value,
              },
              filledSlots: 2,
              isComplete: true,
              humanConflictCount: humanConflicts,
              additionalAuthority: additional,
              totalFirstYearSalary: totalFirst,
              totalScheduleSalary: first.totalSalary + second.totalSalary,
              canonicalKey:
                  '${first.offer.playerId.value},${second.offer.playerId.value}',
            ),
          );
        }
      }
      // Single-slot partial fallbacks for secondary slot-maximization when full
      // 2-slot completion is infeasible across competing teams.
      for (final c in bounded) {
        final salary = c.offer.firstYearSalary;
        final overage = payroll + salary - FinancialRules.salaryCap;
        final additional = overage > ordinaryRelief
            ? overage - ordinaryRelief
            : 0;
        if (additional < 1 ||
            ordinaryRelief + additional >
                FinancialRules.maximumCombinedHardshipOverage ||
            projectedCash - salary < 0) {
          continue;
        }
        options.add(
          _HardshipOption(
            offers: [c.offer],
            targetIds: {c.offer.playerId.value},
            filledSlots: 1,
            isComplete: false,
            humanConflictCount: humanTargets.contains(c.offer.playerId.value)
                ? 1
                : 0,
            additionalAuthority: additional,
            totalFirstYearSalary: salary,
            totalScheduleSalary: c.totalSalary,
            canonicalKey: c.offer.playerId.value,
          ),
        );
      }
    }

    if (options.isEmpty) return null;
    options.sort(_compareOptions);
    final retained = options.length > _maxOptionsPerTeam
        ? options.sublist(0, _maxOptionsPerTeam)
        : options;
    return _TeamHardshipPlan(
      teamId: team.id,
      missingPlayers: missing,
      affordableCandidateCount: affordableSingles.length,
      options: retained,
      optionsTruncated: truncatedSingles || options.length > _maxOptionsPerTeam,
    );
  }

  static int _compareOptions(_HardshipOption a, _HardshipOption b) {
    if (a.isComplete != b.isComplete) return a.isComplete ? -1 : 1;
    var compare = a.humanConflictCount.compareTo(b.humanConflictCount);
    if (compare != 0) return compare;
    compare = a.additionalAuthority.compareTo(b.additionalAuthority);
    if (compare != 0) return compare;
    compare = a.totalFirstYearSalary.compareTo(b.totalFirstYearSalary);
    if (compare != 0) return compare;
    compare = a.totalScheduleSalary.compareTo(b.totalScheduleSalary);
    if (compare != 0) return compare;
    return a.canonicalKey.compareTo(b.canonicalKey);
  }

  _JointHardshipSolution _solveJointAllocation(List<_TeamHardshipPlan> plans) {
    if (plans.isEmpty) {
      return const _JointHardshipSolution(
        assignments: {},
        exploredStates: 0,
        truncated: false,
        completedTeams: 0,
        filledSlots: 0,
      );
    }

    // MRV order: fewest complete options first (or fewest total options), ties
    // broken deterministically by teamId.
    final ordered = [...plans]
      ..sort((a, b) {
        final aComp = a.completeOptionCount;
        final bComp = b.completeOptionCount;
        final aHasComp = aComp > 0 ? 0 : 1;
        final bHasComp = bComp > 0 ? 0 : 1;
        if (aHasComp != bHasComp) return aHasComp.compareTo(bHasComp);
        if (aComp != bComp) return aComp.compareTo(bComp);
        final byLen = a.options.length.compareTo(b.options.length);
        if (byLen != 0) return byLen;
        return a.teamId.value.compareTo(b.teamId.value);
      });

    final n = ordered.length;
    final remComplete = List<int>.filled(n + 1, 0);
    final remMaxSlots = List<int>.filled(n + 1, 0);
    final remMinAuthWhenComplete = List<int>.filled(n + 1, 0);
    for (var i = n - 1; i >= 0; i--) {
      final p = ordered[i];
      remComplete[i] = remComplete[i + 1] + (p.completeOptionCount > 0 ? 1 : 0);
      remMaxSlots[i] =
          remMaxSlots[i + 1] +
          (p.completeOptionCount > 0 ? p.missingPlayers : 1);
      final minAuth = p.completeOptionCount > 0
          ? p.options
                .where((o) => o.isComplete)
                .map((o) => o.additionalAuthority)
                .reduce((x, y) => x < y ? x : y)
          : 0;
      remMinAuthWhenComplete[i] = remMinAuthWhenComplete[i + 1] + minAuth;
    }

    var bestCompleted = -1;
    var bestSlots = -1;
    var bestHumanConflicts = 1 << 30;
    var bestAdditional = 1 << 30;
    var bestFirstYear = 1 << 30;
    Map<String, _HardshipOption> bestAssignments = const {};

    var explored = 0;
    var truncated = false;
    final usedPlayers = <String>{};
    final current = <String, _HardshipOption>{};

    void search(
      int idx,
      int curCompleted,
      int curSlots,
      int curHumanConflicts,
      int curAdditional,
      int curFirstYear,
    ) {
      if (explored >= _maxSearchStates) {
        truncated = true;
        return;
      }
      explored++;

      if (idx == n) {
        final better =
            curCompleted > bestCompleted ||
            (curCompleted == bestCompleted &&
                (curSlots > bestSlots ||
                    (curSlots == bestSlots &&
                        (curHumanConflicts < bestHumanConflicts ||
                            (curHumanConflicts == bestHumanConflicts &&
                                (curAdditional < bestAdditional ||
                                    (curAdditional == bestAdditional &&
                                        curFirstYear < bestFirstYear)))))));
        if (better) {
          bestCompleted = curCompleted;
          bestSlots = curSlots;
          bestHumanConflicts = curHumanConflicts;
          bestAdditional = curAdditional;
          bestFirstYear = curFirstYear;
          bestAssignments = Map<String, _HardshipOption>.of(current);
        }
        return;
      }

      if (curCompleted + remComplete[idx] < bestCompleted) return;
      if (curCompleted + remComplete[idx] == bestCompleted) {
        if (curSlots + remMaxSlots[idx] < bestSlots) return;
        if (curSlots + remMaxSlots[idx] == bestSlots) {
          if (curHumanConflicts > bestHumanConflicts) return;
          if (curHumanConflicts == bestHumanConflicts &&
              bestCompleted == n &&
              curAdditional + remMinAuthWhenComplete[idx] >= bestAdditional) {
            return;
          }
        }
      }

      final plan = ordered[idx];
      for (final opt in plan.options) {
        if (truncated) return;
        var conflict = false;
        for (final pid in opt.targetIds) {
          if (usedPlayers.contains(pid)) {
            conflict = true;
            break;
          }
        }
        if (conflict) continue;

        usedPlayers.addAll(opt.targetIds);
        current[plan.teamId.value] = opt;
        search(
          idx + 1,
          curCompleted + (opt.isComplete ? 1 : 0),
          curSlots + opt.filledSlots,
          curHumanConflicts + opt.humanConflictCount,
          curAdditional + opt.additionalAuthority,
          curFirstYear + opt.totalFirstYearSalary,
        );
        current.remove(plan.teamId.value);
        usedPlayers.removeAll(opt.targetIds);
      }

      // Skip branch (needed when joint conflicts force sacrificing one team).
      if (!truncated &&
          (curCompleted + remComplete[idx + 1] >= bestCompleted)) {
        search(
          idx + 1,
          curCompleted,
          curSlots,
          curHumanConflicts,
          curAdditional,
          curFirstYear,
        );
      }
    }

    search(0, 0, 0, 0, 0, 0);
    return _JointHardshipSolution(
      assignments: bestAssignments,
      exploredStates: explored,
      truncated: truncated,
      completedTeams: bestCompleted < 0 ? 0 : bestCompleted,
      filledSlots: bestSlots < 0 ? 0 : bestSlots,
    );
  }

  GmCareer resolveNext(GmCareer career) {
    final settlement = career.hardshipSettlement;
    if (!settlement.isResolvable) {
      _fail('Hardship settlement is not ready for resolution');
    }
    if (settlement.nextResolutionIndex >= settlement.resolutionOrder.length) {
      return career.copyWith(
        hardshipSettlement: settlement.copyWith(
          status: HardshipSettlementStatus.complete,
        ),
      );
    }
    final playerId = settlement.resolutionOrder[settlement.nextResolutionIndex];
    final offers = settlement.offersFor(playerId);
    final results = <FreeAgentMarketOfferResult>[];
    final rejected = <HardshipOffer, FreeAgentOfferDecision>{};
    final acceptable = <HardshipOffer>[];
    for (final offer in offers) {
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
      final decision = evaluator.evaluate(
        career: career,
        teamId: offer.teamId,
        freeAgentId: offer.playerId,
        category: RosterCategory.standard,
        durationYears: offer.durationYears,
        agreedFirstYearSalary: offer.firstYearSalary,
        hardshipOfferId: offer.offerId,
      );
      if (decision.status == FreeAgentOfferStatus.acceptable) {
        acceptable.add(offer);
      } else if (decision.status == FreeAgentOfferStatus.financiallyIllegal ||
          decision.status == FreeAgentOfferStatus.invalidTerms) {
        results.add(
          FreeAgentMarketOfferResult(
            offerId: offer.offerId,
            teamId: offer.teamId,
            outcome: FreeAgentMarketOfferOutcome.financiallyUnavailable,
            reasonCode: decision.reasonCode,
          ),
        );
      } else {
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
    final ranked = ranker.rankHardship(
      career: career,
      playerId: playerId,
      offers: acceptable,
    );
    HardshipOffer? winner;
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
      winner = offer;
      break;
    }
    if (winner != null) {
      for (final offer in ranked) {
        if (offer.offerId == winner.offerId ||
            results.any((result) => result.offerId == offer.offerId)) {
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
      for (final offer in offers) {
        if (!acceptable.contains(offer) ||
            offer.offerId == winner.offerId ||
            results.any((result) => result.offerId == offer.offerId)) {
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
      results.add(
        FreeAgentMarketOfferResult(
          offerId: winner.offerId,
          teamId: winner.teamId,
          outcome: FreeAgentMarketOfferOutcome.accepted,
          reasonCode: 'accepted',
        ),
      );
    }
    var ledger = career.freeAgentOffers;
    for (final entry in rejected.entries) {
      ledger = _appendAttempt(
        ledger: ledger,
        offer: entry.key,
        outcome: _attemptOutcome(entry.value.status),
        reasonCode: entry.value.reasonCode,
        transactionId: null,
      );
    }
    final nextIndex = settlement.nextResolutionIndex + 1;
    final complete = nextIndex >= settlement.resolutionOrder.length;
    final authorizations = [...settlement.authorizations];
    if (winner != null) {
      final acquisitionId = FreeAgentAcquisition.idFor(
        winner.playerId,
        career.currentYear,
      );
      final authorizationIndex = authorizations.indexWhere(
        (authorization) => authorization.teamId == winner!.teamId,
      );
      if (authorizationIndex < 0) {
        _fail('Winning hardship offer lacks cap authorization');
      }
      final authorization = authorizations[authorizationIndex];
      final payrollAfter =
          career.finances.capPayrollFor(winner.teamId, career.currentYear) +
          winner.firstYearSalary;
      final actualOverage =
          payrollAfter -
          FinancialRules.salaryCap -
          authorization.existingOrdinaryRelief;
      final usedAmount = actualOverage > 0 ? actualOverage : 0;
      if (usedAmount > authorization.additionalAmount) {
        _fail('Winning offer exceeds exact hardship authority');
      }
      authorizations[authorizationIndex] = authorization.copyWith(
        status: HardshipAuthorizationStatus.consumed,
        usedAmount: usedAmount,
        transactionIds: [...authorization.transactionIds, acquisitionId],
      );
      ledger = _appendAttempt(
        ledger: ledger,
        offer: winner,
        outcome: FreeAgentOfferOutcome.accepted,
        reasonCode: 'accepted',
        transactionId: acquisitionId,
      );
    }
    final outcome = HardshipOutcome(
      playerId: playerId,
      winningTeamId: winner?.teamId,
      winningOfferId: winner?.offerId,
      results: results,
    );
    final nextSettlement = settlement.copyWith(
      status: complete
          ? HardshipSettlementStatus.complete
          : HardshipSettlementStatus.resolving,
      nextResolutionIndex: nextIndex,
      outcomes: [...settlement.outcomes, outcome],
      authorizations: authorizations,
    );
    if (winner == null) {
      return career.copyWith(
        freeAgentOffers: ledger,
        hardshipSettlement: nextSettlement,
      );
    }
    return acquisition.acquire(
      career: career,
      teamId: winner.teamId,
      freeAgentId: winner.playerId,
      category: RosterCategory.standard,
      durationYears: winner.durationYears,
      agreedFirstYearSalary: winner.firstYearSalary,
      origin: AcquisitionOrigin.hardship,
      hardshipOfferId: winner.offerId,
      hardshipSettlementAfterAcquisition: nextSettlement,
      freeAgentOffersAfterAcquisition: ledger,
    );
  }

  _HardshipCandidate? _cheapestAcceptableContract({
    required GmCareer career,
    required TeamId teamId,
    required PlayerId playerId,
    Team? teamOverride,
  }) {
    _HardshipCandidate? cheapest;
    for (
      var duration = 1;
      duration <=
          FinancialRules.maxDurationForCategory(RosterCategory.standard);
      duration++
    ) {
      var low = FinancialRules.minimumSalary;
      var high = FinancialRules.maximumSalary + 1;
      while (low < high) {
        final salary = low + (high - low) ~/ 2;
        final willingness = evaluator.evaluateWillingness(
          career: career,
          teamId: teamId,
          freeAgentId: playerId,
          category: RosterCategory.standard,
          durationYears: duration,
          salary: salary,
          teamOverride: teamOverride,
        );
        if (willingness.accepts) {
          high = salary;
        } else {
          low = salary + 1;
        }
      }
      if (low > FinancialRules.maximumSalary) continue;
      final willingness = evaluator.evaluateWillingness(
        career: career,
        teamId: teamId,
        freeAgentId: playerId,
        category: RosterCategory.standard,
        durationYears: duration,
        salary: low,
        teamOverride: teamOverride,
      );
      if (!willingness.accepts) continue;
      if (FinancialRules.standardSchedule(
        low,
        duration,
      ).any((salary) => salary > FinancialRules.maximumSalary)) {
        continue;
      }
      final offer = HardshipOffer(
        offerId: HardshipOffer.idFor(
          teamId: teamId,
          playerId: playerId,
          seasonYear: career.currentYear,
        ),
        playerId: playerId,
        teamId: teamId,
        seasonYear: career.currentYear,
        durationYears: duration,
        firstYearSalary: low,
        source: teamId == career.userFranchiseId
            ? FreeAgentMarketOfferSource.human
            : FreeAgentMarketOfferSource.ai,
      );
      final candidate = _HardshipCandidate(offer);
      if (cheapest == null || _compareCandidates(candidate, cheapest) < 0) {
        cheapest = candidate;
      }
    }
    return cheapest;
  }

  static int _compareCandidates(
    _HardshipCandidate left,
    _HardshipCandidate right,
  ) {
    var compare = left.offer.firstYearSalary.compareTo(
      right.offer.firstYearSalary,
    );
    if (compare != 0) return compare;
    compare = left.totalSalary.compareTo(right.totalSalary);
    if (compare != 0) return compare;
    compare = left.offer.durationYears.compareTo(right.offer.durationYears);
    if (compare != 0) return compare;
    return left.offer.playerId.value.compareTo(right.offer.playerId.value);
  }

  FreeAgentOfferLedger _appendAttempt({
    required FreeAgentOfferLedger ledger,
    required HardshipOffer offer,
    required FreeAgentOfferOutcome outcome,
    required String reasonCode,
    required String? transactionId,
  }) {
    final attempts = ledger.attemptsFor(
      teamId: offer.teamId,
      playerId: offer.playerId,
      seasonYear: offer.seasonYear,
    );
    if (attempts.length >= FreeAgentOfferAttempt.maximumPlayerSideAttempts) {
      _fail('Hardship offer has no player-side attempt remaining');
    }
    return ledger.add(
      FreeAgentOfferAttempt(
        offerId: offer.offerId,
        playerId: offer.playerId,
        teamId: offer.teamId,
        seasonYear: offer.seasonYear,
        category: RosterCategory.standard,
        durationYears: offer.durationYears,
        firstYearSalary: offer.firstYearSalary,
        outcome: outcome,
        reasonCode: reasonCode,
        attemptNumber: attempts.length + 1,
        acquisitionTransactionId: transactionId,
      ),
    );
  }

  static FreeAgentOfferOutcome _attemptOutcome(FreeAgentOfferStatus status) =>
      switch (status) {
        FreeAgentOfferStatus.salaryTooLow => FreeAgentOfferOutcome.salaryTooLow,
        FreeAgentOfferStatus.unfavorableDuration =>
          FreeAgentOfferOutcome.unfavorableDuration,
        FreeAgentOfferStatus.poorFit => FreeAgentOfferOutcome.poorFit,
        FreeAgentOfferStatus.inappropriateCategory =>
          FreeAgentOfferOutcome.inappropriateCategory,
        _ => throw ArgumentError.value(status, 'status'),
      };

  static Never _fail(String message) => throw DomainValidationException([
    ValidationIssue(
      code: ValidationCode.freeAgentAcquisitionInvalid,
      path: 'hardshipSettlement',
      message: message,
    ),
  ]);
}

final class _HardshipCandidate {
  const _HardshipCandidate(this.offer);

  final HardshipOffer offer;

  int get totalSalary => offer.salarySchedule.fold<int>(0, (a, b) => a + b);
}

final class _HardshipOption {
  const _HardshipOption({
    required this.offers,
    required this.targetIds,
    required this.filledSlots,
    required this.isComplete,
    required this.humanConflictCount,
    required this.additionalAuthority,
    required this.totalFirstYearSalary,
    required this.totalScheduleSalary,
    required this.canonicalKey,
  });

  final List<HardshipOffer> offers;
  final Set<String> targetIds;
  final int filledSlots;
  final bool isComplete;
  final int humanConflictCount;
  final int additionalAuthority;
  final int totalFirstYearSalary;
  final int totalScheduleSalary;
  final String canonicalKey;
}

final class _TeamHardshipPlan {
  _TeamHardshipPlan({
    required this.teamId,
    required this.missingPlayers,
    required this.affordableCandidateCount,
    required this.options,
    required this.optionsTruncated,
  }) : completeOptionCount = options.where((o) => o.isComplete).length;

  final TeamId teamId;
  final int missingPlayers;
  final int affordableCandidateCount;
  final List<_HardshipOption> options;
  final bool optionsTruncated;
  final int completeOptionCount;
}

final class _JointHardshipSolution {
  const _JointHardshipSolution({
    required this.assignments,
    required this.exploredStates,
    required this.truncated,
    required this.completedTeams,
    required this.filledSlots,
  });

  final Map<String, _HardshipOption> assignments;
  final int exploredStates;
  final bool truncated;
  final int completedTeams;
  final int filledSlots;
}
