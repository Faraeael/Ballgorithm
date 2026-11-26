import '../models/ids.dart';
import 'gm_career.dart';
import 'trade_service.dart';
import 'trade_valuation.dart';

/// Public-safe trade decision; never exposes a candidate career.
enum TradeOfferStatus { illegal, legalRejected, legalAccepted }

final class TradeTeamPreview {
  const TradeTeamPreview({
    required this.teamId,
    required this.capPayrollBefore,
    required this.capPayrollAfter,
    required this.cashPayrollBefore,
    required this.cashPayrollAfter,
    required this.projectedCashAfterDebtBefore,
    required this.projectedCashAfterDebtAfter,
    required this.standardPlayersBefore,
    required this.standardPlayersAfter,
    required this.twoWayPlayersBefore,
    required this.twoWayPlayersAfter,
    required this.minimumRosterReserveBefore,
    required this.minimumRosterReserveAfter,
  });
  final TeamId teamId;
  final int capPayrollBefore;
  final int capPayrollAfter;
  final int cashPayrollBefore;
  final int cashPayrollAfter;
  final int projectedCashAfterDebtBefore;
  final int projectedCashAfterDebtAfter;
  final int standardPlayersBefore;
  final int standardPlayersAfter;
  final int twoWayPlayersBefore;
  final int twoWayPlayersAfter;
  final int minimumRosterReserveBefore;
  final int minimumRosterReserveAfter;
}

final class TradeOfferQuote {
  const TradeOfferQuote._(
    this.status,
    this.legalReason,
    this.valuation,
    this.teamPreviews,
    this._career,
    this._proposal,
  );

  final TradeOfferStatus status;
  final PlayerTradeRejection? legalReason;
  final TradeValuation? valuation;
  final Map<TeamId, TradeTeamPreview> teamPreviews;
  final GmCareer _career;
  final PlayerTradeProposal _proposal;
}

final class TradeQuoteRejected implements Exception {
  const TradeQuoteRejected(this.status, {this.reason});
  final TradeOfferStatus status;
  final Object? reason;
}

/// Evaluation is read-only. Execution accepts only an unchanged accepted quote.
abstract final class TradeOfferService {
  static TradeOfferQuote evaluate(
    GmCareer career,
    PlayerTradeProposal proposal,
  ) {
    try {
      final candidate = PlayerTradeService.buildCandidate(career, proposal);
      final valuation = TradeValuationService.evaluate(
        career,
        proposal,
        candidate,
      );
      return TradeOfferQuote._(
        valuation.accepted
            ? TradeOfferStatus.legalAccepted
            : TradeOfferStatus.legalRejected,
        null,
        valuation,
        _previews(career, candidate, proposal),
        career,
        proposal,
      );
    } on PlayerTradeRejected catch (error) {
      return TradeOfferQuote._(
        TradeOfferStatus.illegal,
        error.reason,
        null,
        const {},
        career,
        proposal,
      );
    }
  }

  static Map<TeamId, TradeTeamPreview> _previews(
    GmCareer before,
    GmCareer after,
    PlayerTradeProposal proposal,
  ) => Map.unmodifiable({
    for (final id in [proposal.firstTeam, proposal.secondTeam])
      id: TradeTeamPreview(
        teamId: id,
        capPayrollBefore: before.finances.capPayrollFor(id, before.currentYear),
        capPayrollAfter: after.finances.capPayrollFor(id, after.currentYear),
        cashPayrollBefore: before.finances.cashPayrollFor(
          id,
          before.currentYear,
        ),
        cashPayrollAfter: after.finances.cashPayrollFor(id, after.currentYear),
        projectedCashAfterDebtBefore:
            before.finances.projectedEndOfSeasonCash(id, before.currentYear) -
            before.finances.debtFor(id),
        projectedCashAfterDebtAfter:
            after.finances.projectedEndOfSeasonCash(id, after.currentYear) -
            after.finances.debtFor(id),
        minimumRosterReserveBefore: PlayerTradeService.minimumRosterReserve(
          before.league.teams
              .firstWhere((team) => team.id == id)
              .roster
              .standardCount,
        ),
        minimumRosterReserveAfter: PlayerTradeService.minimumRosterReserve(
          after.league.teams
              .firstWhere((team) => team.id == id)
              .roster
              .standardCount,
        ),
        standardPlayersBefore: before.league.teams
            .firstWhere((team) => team.id == id)
            .roster
            .standardCount,
        standardPlayersAfter: after.league.teams
            .firstWhere((team) => team.id == id)
            .roster
            .standardCount,
        twoWayPlayersBefore: before.league.teams
            .firstWhere((team) => team.id == id)
            .roster
            .twoWayCount,
        twoWayPlayersAfter: after.league.teams
            .firstWhere((team) => team.id == id)
            .roster
            .twoWayCount,
      ),
  });

  static GmCareer executeAccepted(
    GmCareer current,
    PlayerTradeProposal proposal,
    TradeOfferQuote quote,
  ) {
    if (!identical(current, quote._career) ||
        !identical(proposal, quote._proposal) ||
        quote.status != TradeOfferStatus.legalAccepted) {
      throw TradeQuoteRejected(quote.status);
    }
    final live = evaluate(current, proposal);
    if (live.status != TradeOfferStatus.legalAccepted) {
      throw TradeQuoteRejected(
        live.status,
        reason: live.legalReason ?? live.valuation?.reason,
      );
    }
    return PlayerTradeService.buildCandidate(current, proposal);
  }
}
