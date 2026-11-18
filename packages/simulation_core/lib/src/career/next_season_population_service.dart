import '../generation/deterministic_random.dart';
import '../generation/draft_generator.dart';
import '../generation/free_agent_generator.dart';
import '../generation/name_corpus.dart';
import '../models/draft_order.dart';
import '../models/draft_pick.dart';
import '../models/free_agent.dart';
import '../models/free_agent_acquisition.dart';
import '../models/free_agent_market.dart';
import '../models/free_agent_offer.dart';
import '../models/hardship_settlement.dart';
import '../models/ids.dart';
import '../models/offseason_clearance.dart';
import '../models/player_career_profile.dart';
import '../models/position.dart';
import 'career_phase.dart';
import 'gm_career.dart';
import 'next_season_population_plan.dart';
import 'play_in_state.dart';
import 'season_archive.dart';
import 'season_history_record.dart';
import 'season_rollover_plan.dart';

/// Pure deterministic generator for Year N+1 draft order, rookie draft class,
/// free-agent population, and market initialization (M009-T05C-C2-C2B).
///
/// Consumes a completed Year N [GmCareer] and C2-A [SeasonRolloverPlan] without
/// mutating [career], advancing `currentYear`, or constructing a Year N+1 `GmCareer`.
final class NextSeasonPopulationService {
  const NextSeasonPopulationService();

  /// Provisional technical defaults per rollover contract §2.3
  /// (pending final owner gameplay-policy approval).
  static const int provisionalFreeAgentPoolFloor = FreeAgentPool.expectedSize;
  static const int provisionalPositionFloor = FreeAgentPool.minPerPosition;

  static const int _draftDomainTag = 0x44524146; // 'DRAF'
  static const int _freeAgentTopUpDomainTag = 0x46415450; // 'FATP'

  NextSeasonPopulationPlan plan({
    required GmCareer career,
    required SeasonRolloverPlan rolloverPlan,
    List<SeasonStandingSummary>? completedStandings,
  }) {
    career.validate();
    rolloverPlan.validate();

    final completedYear = career.currentYear;
    final targetYear = completedYear + 1;

    if (career.phase != CareerPhase.playoffs) {
      throw StateError(
        'Cannot generate Year $targetYear population outside '
        'CareerPhase.playoffs (got ${career.phase.name})',
      );
    }
    if (rolloverPlan.careerId != career.id ||
        rolloverPlan.completedYear != completedYear ||
        rolloverPlan.targetYear != targetYear) {
      throw StateError(
        'SeasonRolloverPlan (${rolloverPlan.careerId} y${rolloverPlan.completedYear}) '
        'does not match career (${career.id} y$completedYear)',
      );
    }

    // Validates complete 1,230-game regular season, Play-In, and playoff championship.
    SeasonArchive.fromCareer(career);

    final standings =
        completedStandings ?? _extractRegularSeasonStandings(career);
    _validateStandings(career: career, standings: standings);

    final nextDraftOrder = _buildReverseStandingsDraftOrder(standings);

    final draftSeed = _saltedSeed(
      career.generationSeed,
      targetYear,
      _draftDomainTag,
    );
    final nextDraftClass = const DraftGenerator().generateDraftClass(
      league: career.league,
      seed: draftSeed,
      seasonYear: targetYear,
    );

    // Build complete occupied & historical identity set for collision detection.
    final continuingRosterIds = <String>{
      for (final roster in rolloverPlan.proposedRosters.values)
        for (final entry in roster.entries) entry.player.id.value,
    };
    final carriedDraftRightsIds = rolloverPlan.proposedDraftRightsCarryover.keys
        .toSet();
    final retiredExcludedIds = <String>{
      for (final r in career.retiredPlayers) r.playerId.value,
      for (final r in rolloverPlan.retirements) r.playerId.value,
    };
    final newDraftProspectIds = <String>{
      for (final p in nextDraftClass.prospects) p.id.value,
    };
    final occupiedIds = <String>{
      ...continuingRosterIds,
      ...carriedDraftRightsIds,
      ...retiredExcludedIds,
      ...newDraftProspectIds,
    };
    final allHistoricalIds = <String>{
      ...occupiedIds,
      for (final t in career.league.teams)
        for (final p in t.players) p.id.value,
      for (final p in career.draftClass.prospects) p.id.value,
      for (final id in career.freeAgentPool.initialPlayerIds) id.value,
      ...career.rookieSigningLedger.contracts.keys,
      ...career.careerDraftRights.keys,
    };

    // Ensure new draft prospects do not collide with any prior/continuing ID.
    final priorNonNewDraftIds = allHistoricalIds.difference(
      newDraftProspectIds,
    );
    for (final pid in newDraftProspectIds) {
      if (priorNonNewDraftIds.contains(pid)) {
        throw StateError('New draft prospect $pid collides with existing ID');
      }
    }

    // Build Year N+1 free-agent entries from C2-A carried + expired snapshots.
    final faEntries = <FreeAgentEntry>[];
    final faIds = <String>{};
    final expiredRookieFreeAgentIds = <String>{};
    final usedNames = <String>{
      for (final t in career.league.teams)
        for (final p in t.players) p.fullName,
      for (final p in nextDraftClass.prospects) p.fullName,
    };

    void addExistingFreeAgent(
      AgedPlayerSnapshot snap, {
      required bool isExpiredContract,
    }) {
      snap.validate();
      final pid = snap.player.id.value;
      if (occupiedIds.contains(pid)) {
        throw StateError(
          'Free-agent candidate $pid collides with roster, draft rights, '
          'new draft class, or retirement',
        );
      }
      if (!faIds.add(pid)) {
        throw StateError('Duplicate free-agent identity $pid');
      }
      if (snap.nextProfile.age < PlayerCareerProfile.minAge ||
          snap.nextProfile.age > PlayerCareerProfile.maxAge) {
        throw StateError(
          'Free-agent candidate $pid age ${snap.nextProfile.age} out of '
          '${PlayerCareerProfile.minAge}..${PlayerCareerProfile.maxAge}',
        );
      }
      if (isExpiredContract &&
          career.rookieSigningLedger.isSigned(snap.player.id)) {
        expiredRookieFreeAgentIds.add(pid);
      }
      usedNames.add(snap.player.fullName);
      faEntries.add(
        FreeAgentEntry(player: snap.player, profile: snap.nextProfile),
      );
    }

    for (final snap in rolloverPlan.carriedForwardFreeAgents) {
      addExistingFreeAgent(snap, isExpiredContract: false);
    }
    for (final snap in rolloverPlan.eligibleExpiringFreeAgents) {
      addExistingFreeAgent(snap, isExpiredContract: true);
    }

    final carriedCount = rolloverPlan.carriedForwardFreeAgents.length;
    final expiredCount = rolloverPlan.eligibleExpiringFreeAgents.length;

    // Count positions and deterministically top up only to provisional floors.
    final positionCounts = <Position, int>{
      for (final p in Position.values) p: 0,
    };
    for (final entry in faEntries) {
      positionCounts[entry.player.position] =
          (positionCounts[entry.player.position] ?? 0) + 1;
    }

    final topUpSeed = _saltedSeed(
      career.generationSeed,
      targetYear,
      _freeAgentTopUpDomainTag,
    );
    final topUpRandom = DeterministicRandom(topUpSeed);
    final availableNames = <(String, String)>[
      for (final fn in firstNames)
        for (final ln in lastNames)
          if (!usedNames.contains('$fn $ln')) (fn, ln),
    ];
    topUpRandom.shuffle(availableNames);
    var nameIndex = 0;
    var seq = 1;
    var generatedCount = 0;
    const faGen = FreeAgentGenerator();

    void generateTopUpAt(Position position) {
      while (allHistoricalIds.contains('fa-y$targetYear-$seq') ||
          faIds.contains('fa-y$targetYear-$seq')) {
        seq++;
      }
      final pid = PlayerId('fa-y$targetYear-$seq');
      seq++;
      final name = availableNames[nameIndex++];
      final entry = faGen.generateEntry(
        random: topUpRandom,
        id: pid,
        position: position,
        firstName: name.$1,
        lastName: name.$2,
      );
      faIds.add(pid.value);
      faEntries.add(entry);
      positionCounts[position] = (positionCounts[position] ?? 0) + 1;
      generatedCount++;
    }

    // 1. Satisfy per-position floor (12 per Position).
    for (final pos in Position.values) {
      while ((positionCounts[pos] ?? 0) < provisionalPositionFloor) {
        generateTopUpAt(pos);
      }
    }

    // 2. Satisfy total pool floor (90 total).
    var roundRobin = 0;
    while (faEntries.length < provisionalFreeAgentPoolFloor) {
      generateTopUpAt(Position.values[roundRobin % Position.values.length]);
      roundRobin++;
    }

    faEntries.sort((a, b) => a.id.value.compareTo(b.id.value));
    final nextFreeAgentPool = FreeAgentPool(
      seasonYear: targetYear,
      entries: faEntries,
      initialPlayerIds: [for (final e in faEntries) e.id],
      acquisitions: FreeAgentAcquisitionLedger.empty(),
    );

    final marketInit = NextSeasonMarketInitState(
      freeAgentMarket: FreeAgentMarketState.initial(seasonYear: targetYear),
      freeAgentOffers: FreeAgentOfferLedger.empty(),
      offseasonClearance: OffseasonClearanceState.initial(
        seasonYear: targetYear,
      ),
      hardshipSettlement: HardshipSettlement.initial(seasonYear: targetYear),
    );

    return NextSeasonPopulationPlan(
      careerId: career.id,
      completedYear: completedYear,
      targetYear: targetYear,
      nextDraftOrder: nextDraftOrder,
      nextDraftClass: nextDraftClass,
      nextFreeAgentPool: nextFreeAgentPool,
      carriedForwardFreeAgentCount: carriedCount,
      expiredContractEntrantCount: expiredCount,
      generatedFreeAgentCount: generatedCount,
      perPositionCounts: positionCounts,
      sourceFreeAgentIds: faIds,
      retiredExcludedIds: retiredExcludedIds,
      expiredRookieFreeAgentIds: expiredRookieFreeAgentIds,
      priorYearAcquisitionsRetained: career
          .freeAgentPool
          .acquisitions
          .entries
          .values
          .toList(),
      priorYearOfferCount: career.freeAgentOffers.length,
      priorYearMarketRound: career.freeAgentMarket.completedRounds,
      marketInit: marketInit,
      allOccupiedAndHistoricalIds: {...allHistoricalIds, ...faIds},
    );
  }

  static int _saltedSeed(int baseSeed, int targetYear, int domainTag) {
    final mixed =
        (baseSeed ^ (targetYear * 0x9E3779B1) ^ domainTag) & 0x7FFFFFFF;
    return mixed == 0 ? (domainTag & 0x7FFFFFFF) : mixed;
  }

  static List<SeasonStandingSummary> _extractRegularSeasonStandings(
    GmCareer career,
  ) {
    final rs = career.regularSeasonState!;
    final ranked = PlayInRanking.rank(rs);
    final table = rs.standings.table;
    return [
      for (var i = 0; i < ranked.length; i++)
        SeasonStandingSummary(
          rank: i + 1,
          teamId: ranked[i],
          wins: table[ranked[i].value]!.wins,
          losses: table[ranked[i].value]!.losses,
        ),
    ];
  }

  static void _validateStandings({
    required GmCareer career,
    required List<SeasonStandingSummary> standings,
  }) {
    if (standings.length != 30) {
      throw StateError(
        'Expected 30 regular-season standings entries, got ${standings.length}',
      );
    }
    final expectedTeamIds = {for (final t in career.league.teams) t.id.value};
    final seenTeams = <String>{};
    final seenRanks = <int>{};
    var totalWins = 0;
    var totalLosses = 0;
    for (final s in standings) {
      s.validate();
      if (!expectedTeamIds.contains(s.teamId.value)) {
        throw StateError(
          'Standings entry references unknown team ${s.teamId.value}',
        );
      }
      if (!seenTeams.add(s.teamId.value)) {
        throw StateError('Duplicate team ${s.teamId.value} in standings');
      }
      if (!seenRanks.add(s.rank)) {
        throw StateError('Duplicate rank ${s.rank} in standings');
      }
      totalWins += s.wins;
      totalLosses += s.losses;
    }
    if (seenTeams.length != 30 ||
        seenRanks.length != 30 ||
        totalWins != 1230 ||
        totalLosses != 1230) {
      throw StateError(
        'Inconsistent regular-season standings totals '
        '(wins=$totalWins, losses=$totalLosses)',
      );
    }
  }

  static DraftOrder _buildReverseStandingsDraftOrder(
    List<SeasonStandingSummary> standings,
  ) {
    final sorted = List<SeasonStandingSummary>.from(standings)
      ..sort((a, b) {
        final byWins = a.wins.compareTo(b.wins);
        if (byWins != 0) return byWins;
        final byRank = b.rank.compareTo(a.rank);
        if (byRank != 0) return byRank;
        return a.teamId.value.compareTo(b.teamId.value);
      });

    final picks = <DraftPick>[];
    for (var i = 0; i < 30; i++) {
      final teamId = sorted[i].teamId;
      picks.add(
        DraftPick(
          round: 1,
          pickInRound: i + 1,
          overallPick: i + 1,
          originalOwnerTeamId: teamId,
          currentOwnerTeamId: teamId,
        ),
      );
    }
    for (var i = 0; i < 30; i++) {
      final teamId = sorted[i].teamId;
      picks.add(
        DraftPick(
          round: 2,
          pickInRound: i + 1,
          overallPick: 30 + i + 1,
          originalOwnerTeamId: teamId,
          currentOwnerTeamId: teamId,
        ),
      );
    }
    return DraftOrder(picks: picks);
  }
}
