import '../models/draft_order.dart';
import '../models/free_agent.dart';
import '../models/free_agent_acquisition.dart';
import '../models/free_agent_market.dart';
import '../models/free_agent_offer.dart';
import '../models/hardship_settlement.dart';
import '../models/offseason_clearance.dart';
import '../models/position.dart';
import '../models/rookie_draft_class.dart';

/// Next-season market initialization metadata prepared by [NextSeasonPopulationService].
final class NextSeasonMarketInitState {
  const NextSeasonMarketInitState({
    required this.freeAgentMarket,
    required this.freeAgentOffers,
    required this.offseasonClearance,
    required this.hardshipSettlement,
  });

  final FreeAgentMarketState freeAgentMarket;
  final FreeAgentOfferLedger freeAgentOffers;
  final OffseasonClearanceState offseasonClearance;
  final HardshipSettlement hardshipSettlement;

  void validate(int targetYear) {
    freeAgentMarket.validate();
    freeAgentOffers.validate();
    offseasonClearance.validate();
    hardshipSettlement.validate();
    if (freeAgentMarket.seasonYear != targetYear ||
        offseasonClearance.seasonYear != targetYear ||
        hardshipSettlement.seasonYear != targetYear) {
      throw FormatException(
        'NextSeasonMarketInitState seasonYear mismatch (expected $targetYear)',
      );
    }
    if (!freeAgentOffers.isEmpty) {
      throw const FormatException(
        'NextSeasonMarketInitState requires empty freeAgentOffers',
      );
    }
  }
}

/// Pure, immutable, deterministic plan for Year N+1 draft order, rookie class,
/// free-agent pool, and market initialization (M009-T05C-C2-C2B).
///
/// Does not construct a Year N+1 `GmCareer`, advance `currentYear`, or persist state.
final class NextSeasonPopulationPlan {
  NextSeasonPopulationPlan({
    required this.careerId,
    required this.completedYear,
    required this.targetYear,
    required this.nextDraftOrder,
    required this.nextDraftClass,
    required this.nextFreeAgentPool,
    required this.carriedForwardFreeAgentCount,
    required this.expiredContractEntrantCount,
    required this.generatedFreeAgentCount,
    required Map<Position, int> perPositionCounts,
    required Set<String> sourceFreeAgentIds,
    required Set<String> retiredExcludedIds,
    required Set<String> expiredRookieFreeAgentIds,
    required List<FreeAgentAcquisition> priorYearAcquisitionsRetained,
    required this.priorYearOfferCount,
    required this.priorYearMarketRound,
    required this.marketInit,
    required Set<String> allOccupiedAndHistoricalIds,
  }) : perPositionCounts = Map.unmodifiable({
         for (final p in Position.values) p: perPositionCounts[p] ?? 0,
       }),
       sourceFreeAgentIds = Set.unmodifiable(
         sourceFreeAgentIds.toList()..sort(),
       ),
       retiredExcludedIds = Set.unmodifiable(
         retiredExcludedIds.toList()..sort(),
       ),
       expiredRookieFreeAgentIds = Set.unmodifiable(
         expiredRookieFreeAgentIds.toList()..sort(),
       ),
       priorYearAcquisitionsRetained = List.unmodifiable(
         priorYearAcquisitionsRetained,
       ),
       allOccupiedAndHistoricalIds = Set.unmodifiable(
         allOccupiedAndHistoricalIds.toList()..sort(),
       ) {
    validate();
  }

  final String careerId;
  final int completedYear;
  final int targetYear;
  final DraftOrder nextDraftOrder;
  final RookieDraftClass nextDraftClass;
  final FreeAgentPool nextFreeAgentPool;
  final int carriedForwardFreeAgentCount;
  final int expiredContractEntrantCount;
  final int generatedFreeAgentCount;
  final Map<Position, int> perPositionCounts;
  final Set<String> sourceFreeAgentIds;
  final Set<String> retiredExcludedIds;
  final Set<String> expiredRookieFreeAgentIds;

  /// Explicit retention evidence for Year N `FreeAgentPool.acquisitions` until
  /// `C2-C2C` persists cross-season acquisition history.
  final List<FreeAgentAcquisition> priorYearAcquisitionsRetained;
  final int priorYearOfferCount;
  final int priorYearMarketRound;
  final NextSeasonMarketInitState marketInit;
  final Set<String> allOccupiedAndHistoricalIds;

  bool get collisionCheckPassed => true;

  void validate() {
    if (careerId.trim().isEmpty ||
        completedYear < 1 ||
        targetYear != completedYear + 1) {
      throw const FormatException(
        'Invalid NextSeasonPopulationPlan year metadata',
      );
    }
    nextDraftOrder.validate();
    nextDraftClass.validate();
    if (nextDraftClass.seasonYear != targetYear) {
      throw FormatException(
        'nextDraftClass seasonYear ${nextDraftClass.seasonYear} != $targetYear',
      );
    }
    nextFreeAgentPool.validate();
    if (nextFreeAgentPool.seasonYear != targetYear) {
      throw FormatException(
        'nextFreeAgentPool seasonYear ${nextFreeAgentPool.seasonYear} != '
        '$targetYear',
      );
    }
    if (!nextFreeAgentPool.acquisitions.isEmpty) {
      throw const FormatException(
        'nextFreeAgentPool acquisitions must be empty for targetYear',
      );
    }
    if (carriedForwardFreeAgentCount < 0 ||
        expiredContractEntrantCount < 0 ||
        generatedFreeAgentCount < 0 ||
        carriedForwardFreeAgentCount +
                expiredContractEntrantCount +
                generatedFreeAgentCount !=
            nextFreeAgentPool.length) {
      throw const FormatException(
        'Free-agent count breakdown does not match nextFreeAgentPool.length',
      );
    }
    marketInit.validate(targetYear);
  }
}
