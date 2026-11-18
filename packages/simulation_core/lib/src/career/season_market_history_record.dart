import '../models/ai_rookie_signing.dart';
import '../models/draft_execution_state.dart';
import '../models/draft_order.dart';
import '../models/free_agent_acquisition.dart';
import '../models/free_agent_market.dart';
import '../models/free_agent_offer.dart';
import '../models/hardship_settlement.dart';
import '../models/offseason_clearance.dart';
import 'gm_career.dart';

/// Immutable, season-scoped archive of all draft, free-agency, clearance, and
/// hardship transaction evidence for one completed career season (Schema v25).
final class SeasonMarketHistoryRecord {
  SeasonMarketHistoryRecord({
    required this.seasonYear,
    required this.draftOrder,
    required this.draftExecutionState,
    required this.aiRookieSigning,
    required this.freeAgentAcquisitions,
    required this.freeAgentOffers,
    required this.freeAgentMarket,
    required this.offseasonClearance,
    required this.hardshipSettlement,
  }) {
    validate();
  }

  factory SeasonMarketHistoryRecord.fromCareer(GmCareer career) =>
      SeasonMarketHistoryRecord(
        seasonYear: career.currentYear,
        draftOrder: career.draftOrder,
        draftExecutionState: career.draftExecutionState,
        aiRookieSigning: career.aiRookieSigning,
        freeAgentAcquisitions: career.freeAgentPool.acquisitions,
        freeAgentOffers: career.freeAgentOffers,
        freeAgentMarket: career.freeAgentMarket,
        offseasonClearance: career.offseasonClearance,
        hardshipSettlement: career.hardshipSettlement,
      );

  factory SeasonMarketHistoryRecord.fromJson(Map<String, dynamic> json) {
    final seasonYear = json['seasonYear'];
    final rawDraftOrder = json['draftOrder'];
    final rawDraftExecution = json['draftExecutionState'];
    final rawAiSigning = json['aiRookieSigning'];
    final rawAcquisitions = json['freeAgentAcquisitions'];
    final rawOffers = json['freeAgentOffers'];
    final rawMarket = json['freeAgentMarket'];
    final rawClearance = json['offseasonClearance'];
    final rawHardship = json['hardshipSettlement'];

    if (seasonYear is! int ||
        rawDraftOrder is! Map<String, dynamic> ||
        rawDraftExecution is! Map<String, dynamic> ||
        rawAiSigning is! Map<String, dynamic> ||
        rawAcquisitions is! Map<String, dynamic> ||
        rawOffers is! Map<String, dynamic> ||
        rawMarket is! Map<String, dynamic> ||
        rawClearance is! Map<String, dynamic> ||
        rawHardship is! Map<String, dynamic>) {
      throw const FormatException('Malformed SeasonMarketHistoryRecord JSON');
    }

    return SeasonMarketHistoryRecord(
      seasonYear: seasonYear,
      draftOrder: DraftOrder.fromJson(rawDraftOrder),
      draftExecutionState: DraftExecutionState.fromJson(rawDraftExecution),
      aiRookieSigning: AiRookieSigningState.fromJson(rawAiSigning),
      freeAgentAcquisitions: FreeAgentAcquisitionLedger.fromJson(
        rawAcquisitions,
      ),
      freeAgentOffers: FreeAgentOfferLedger.fromJson(rawOffers),
      freeAgentMarket: FreeAgentMarketState.fromJson(rawMarket),
      offseasonClearance: OffseasonClearanceState.fromJson(rawClearance),
      hardshipSettlement: HardshipSettlement.fromJson(rawHardship),
    );
  }

  final int seasonYear;
  final DraftOrder draftOrder;
  final DraftExecutionState draftExecutionState;
  final AiRookieSigningState aiRookieSigning;
  final FreeAgentAcquisitionLedger freeAgentAcquisitions;
  final FreeAgentOfferLedger freeAgentOffers;
  final FreeAgentMarketState freeAgentMarket;
  final OffseasonClearanceState offseasonClearance;
  final HardshipSettlement hardshipSettlement;

  void validate() {
    if (seasonYear < 1) {
      throw FormatException(
        'SeasonMarketHistoryRecord seasonYear $seasonYear must be >= 1',
      );
    }
    draftOrder.validate();
    freeAgentMarket.validate();
    offseasonClearance.validate();
    hardshipSettlement.validate();

    if (freeAgentMarket.seasonYear != seasonYear ||
        offseasonClearance.seasonYear != seasonYear ||
        hardshipSettlement.seasonYear != seasonYear) {
      throw FormatException(
        'SeasonMarketHistoryRecord $seasonYear has mismatched market/clearance/'
        'hardship seasonYear',
      );
    }
    for (final selection in draftExecutionState.selections) {
      if (selection.seasonYear != seasonYear) {
        throw FormatException(
          'SeasonMarketHistoryRecord $seasonYear contains draft selection from '
          'year ${selection.seasonYear}',
        );
      }
    }
    for (final acq in freeAgentAcquisitions.entries.values) {
      if (acq.seasonYear != seasonYear) {
        throw FormatException(
          'SeasonMarketHistoryRecord $seasonYear contains FA acquisition '
          '${acq.transactionId} from year ${acq.seasonYear}',
        );
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'seasonYear': seasonYear,
    'draftOrder': draftOrder.toJson(),
    'draftExecutionState': draftExecutionState.toJson(),
    'aiRookieSigning': aiRookieSigning.toJson(),
    'freeAgentAcquisitions': freeAgentAcquisitions.toJson(),
    'freeAgentOffers': freeAgentOffers.toJson(),
    'freeAgentMarket': freeAgentMarket.toJson(),
    'offseasonClearance': offseasonClearance.toJson(),
    'hardshipSettlement': hardshipSettlement.toJson(),
  };
}
