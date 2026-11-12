import '../validation/validation_result.dart';
import 'free_agent_market.dart';
import 'ids.dart';

enum OffseasonClearanceStatus {
  notStarted('notStarted'),
  collectingHumanOffers('collectingHumanOffers'),
  preparedForResolution('preparedForResolution'),
  resolving('resolving'),
  complete('complete'),
  blocked('blocked'),
  cleared('cleared');

  const OffseasonClearanceStatus(this.jsonValue);

  final String jsonValue;

  static OffseasonClearanceStatus fromJson(String value) => values.firstWhere(
    (status) => status.jsonValue == value || status.name == value,
    orElse: () => throw ArgumentError.value(
      value,
      'clearanceStatus',
      'Unknown clearance status: $value',
    ),
  );
}

/// Approved cap exception for one compliance transaction.
final class CapException {
  CapException({
    required this.teamId,
    required this.amount,
    required this.missingPlayers,
    required this.reason,
  }) {
    if (amount <= 0 ||
        amount > 800 ||
        missingPlayers < 1 ||
        missingPlayers > 2 ||
        amount > 400 * missingPlayers ||
        reason.trim().isEmpty) {
      throw const FormatException('Malformed cap exception');
    }
  }

  factory CapException.fromJson(Map<String, dynamic> json) {
    final teamId = json['teamId'];
    final amount = json['amount'];
    final missingPlayers = json['missingPlayers'];
    final reason = json['reason'];
    if (teamId is! String ||
        amount is! int ||
        missingPlayers is! int ||
        reason is! String) {
      throw const FormatException('Malformed cap exception JSON');
    }
    return CapException(
      teamId: TeamId(teamId),
      amount: amount,
      missingPlayers: missingPlayers,
      reason: reason,
    );
  }

  final TeamId teamId;
  final int amount;
  final int missingPlayers;
  final String reason;

  Map<String, Object?> toJson() => {
    'teamId': teamId.value,
    'amount': amount,
    'missingPlayers': missingPlayers,
    'reason': reason,
  };
}

/// Durable bounded compliance pass after the two market rounds.
final class OffseasonClearanceState {
  OffseasonClearanceState({
    required this.status,
    required this.seasonYear,
    required List<FreeAgentMarketOffer> humanOffers,
    required List<FreeAgentMarketOffer> aiOffers,
    required List<PlayerId> resolutionOrder,
    required this.nextResolutionIndex,
    required List<FreeAgentMarketOutcome> outcomes,
    List<CapException> capExceptions = const [],
  }) : humanOffers = List.unmodifiable(humanOffers),
       aiOffers = List.unmodifiable(aiOffers),
       resolutionOrder = List.unmodifiable(resolutionOrder),
       outcomes = List.unmodifiable(outcomes),
       capExceptions = List.unmodifiable(capExceptions) {
    validate();
  }

  factory OffseasonClearanceState.initial({required int seasonYear}) =>
      OffseasonClearanceState(
        status: OffseasonClearanceStatus.notStarted,
        seasonYear: seasonYear,
        humanOffers: const [],
        aiOffers: const [],
        resolutionOrder: const [],
        nextResolutionIndex: 0,
        outcomes: const [],
      );

  factory OffseasonClearanceState.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    final seasonYear = json['seasonYear'];
    final rawHuman = json['humanOffers'];
    final rawAi = json['aiOffers'];
    final rawOrder = json['resolutionOrder'];
    final nextResolutionIndex = json['nextResolutionIndex'];
    final rawOutcomes = json['outcomes'];
    final rawExceptions = json['capExceptions'];
    if (status is! String ||
        seasonYear is! int ||
        rawHuman is! List ||
        rawAi is! List ||
        rawOrder is! List ||
        nextResolutionIndex is! int ||
        rawOutcomes is! List ||
        (rawExceptions != null && rawExceptions is! List)) {
      throw const FormatException('Malformed OffseasonClearanceState JSON');
    }
    return OffseasonClearanceState(
      status: OffseasonClearanceStatus.fromJson(status),
      seasonYear: seasonYear,
      humanOffers: [
        for (final raw in rawHuman)
          if (raw is Map<String, dynamic>)
            FreeAgentMarketOffer.fromJson(raw)
          else
            throw const FormatException('Malformed clearance human offer'),
      ],
      aiOffers: [
        for (final raw in rawAi)
          if (raw is Map<String, dynamic>)
            FreeAgentMarketOffer.fromJson(raw)
          else
            throw const FormatException('Malformed clearance AI offer'),
      ],
      resolutionOrder: [
        for (final raw in rawOrder)
          if (raw is String)
            PlayerId(raw)
          else
            throw const FormatException('Malformed clearance order'),
      ],
      nextResolutionIndex: nextResolutionIndex,
      outcomes: [
        for (final raw in rawOutcomes)
          if (raw is Map<String, dynamic>)
            FreeAgentMarketOutcome.fromJson(raw)
          else
            throw const FormatException('Malformed clearance outcome'),
      ],
      capExceptions: rawExceptions == null
          ? const []
          : [
              for (final raw in rawExceptions)
                if (raw is Map<String, dynamic>)
                  CapException.fromJson(raw)
                else
                  throw const FormatException('Malformed cap exception'),
            ],
    );
  }

  final OffseasonClearanceStatus status;
  final int seasonYear;
  final List<FreeAgentMarketOffer> humanOffers;
  final List<FreeAgentMarketOffer> aiOffers;
  final List<PlayerId> resolutionOrder;
  final int nextResolutionIndex;
  final List<FreeAgentMarketOutcome> outcomes;
  final List<CapException> capExceptions;

  bool get isCollecting =>
      status == OffseasonClearanceStatus.collectingHumanOffers;
  bool get isResolvable =>
      status == OffseasonClearanceStatus.preparedForResolution ||
      status == OffseasonClearanceStatus.resolving;
  bool get isComplete =>
      status == OffseasonClearanceStatus.complete ||
      status == OffseasonClearanceStatus.cleared;

  Iterable<FreeAgentMarketOffer> get allOffers => [...humanOffers, ...aiOffers];

  bool isExceptionApproved(TeamId teamId) =>
      capExceptions.any((exception) => exception.teamId == teamId);

  void validate() {
    final issues = <ValidationIssue>[];
    final offerIds = <String>{};
    final keys = <String>{};
    for (final offer in allOffers) {
      issues.addAll(offer.validationIssues());
      if (offer.roundNumber != 3) {
        issues.add(_issue('offers', 'clearance offers must use round 3'));
      }
      if (!offerIds.add(offer.offerId)) {
        issues.add(_issue('offers', 'duplicate clearance offer'));
      }
      if (!keys.add('${offer.teamId.value}:${offer.playerId.value}')) {
        issues.add(_issue('offers', 'duplicate team/player clearance offer'));
      }
    }
    final offered = {
      for (final offer in allOffers) offer.playerId.value,
    }.toList()..sort();
    final order = [for (final id in resolutionOrder) id.value];
    if ((status == OffseasonClearanceStatus.preparedForResolution ||
            status == OffseasonClearanceStatus.resolving ||
            status == OffseasonClearanceStatus.complete ||
            status == OffseasonClearanceStatus.cleared) &&
        offered.join(',') != order.join(',')) {
      issues.add(_issue('resolutionOrder', 'order must match offers'));
    }
    if (status == OffseasonClearanceStatus.notStarted) {
      if (allOffers.isNotEmpty ||
          resolutionOrder.isNotEmpty ||
          outcomes.isNotEmpty ||
          nextResolutionIndex != 0) {
        issues.add(_issue('status', 'notStarted must be empty'));
      }
    }
    if (status == OffseasonClearanceStatus.collectingHumanOffers &&
        aiOffers.isNotEmpty) {
      issues.add(_issue('status', 'AI offers must be sealed after collect'));
    }
    if (status == OffseasonClearanceStatus.preparedForResolution ||
        status == OffseasonClearanceStatus.resolving) {
      if (nextResolutionIndex < 0 ||
          nextResolutionIndex > resolutionOrder.length) {
        issues.add(_issue('nextResolutionIndex', 'cursor out of range'));
      }
    }
    if (status == OffseasonClearanceStatus.resolving) {
      if (outcomes.length != nextResolutionIndex) {
        issues.add(_issue('outcomes', 'outcomes must match cursor'));
      }
    }
    if (isComplete) {
      if (nextResolutionIndex != resolutionOrder.length ||
          outcomes.length != resolutionOrder.length) {
        issues.add(_issue('outcomes', 'complete requires full resolution'));
      }
      for (var i = 0; i < outcomes.length; i++) {
        if (outcomes[i].playerId != resolutionOrder[i]) {
          issues.add(_issue('outcomes', 'outcomes must follow order'));
          break;
        }
      }
    }
    for (final outcome in outcomes) {
      final expected = {
        for (final offer in allOffers)
          if (offer.playerId == outcome.playerId) offer.offerId,
      };
      final seen = <String>{};
      var accepted = 0;
      for (final result in outcome.results) {
        final offer = allOffers.where(
          (candidate) => candidate.offerId == result.offerId,
        );
        if (offer.isEmpty ||
            offer.single.playerId != outcome.playerId ||
            offer.single.teamId != result.teamId ||
            !seen.add(result.offerId)) {
          issues.add(_issue('outcomes', 'result does not match its offer'));
        }
        if (result.outcome == FreeAgentMarketOfferOutcome.accepted) {
          accepted++;
          if (outcome.winningTeamId != result.teamId ||
              outcome.winningOfferId != result.offerId) {
            issues.add(_issue('outcomes', 'accepted result must be winner'));
          }
        }
      }
      if (seen.length != expected.length || !seen.containsAll(expected)) {
        issues.add(_issue('outcomes', 'every offer needs one outcome'));
      }
      if (accepted > 1) {
        issues.add(_issue('outcomes', 'multiple accepted offers'));
      }
      if (accepted == 0 &&
          (outcome.winningTeamId != null || outcome.winningOfferId != null)) {
        issues.add(_issue('outcomes', 'winner without accepted result'));
      }
    }
    final exceptionTeams = <String>{};
    for (final exception in capExceptions) {
      if (!exceptionTeams.add(exception.teamId.value)) {
        issues.add(_issue('capExceptions', 'duplicate team exception'));
      }
    }
    ValidationResult(issues).throwIfInvalid();
  }

  ValidationIssue _issue(String path, String message) => ValidationIssue(
    code: ValidationCode.freeAgentOfferInvalid,
    path: 'offseasonClearance.$path',
    message: message,
  );

  OffseasonClearanceState copyWith({
    OffseasonClearanceStatus? status,
    int? seasonYear,
    List<FreeAgentMarketOffer>? humanOffers,
    List<FreeAgentMarketOffer>? aiOffers,
    List<PlayerId>? resolutionOrder,
    int? nextResolutionIndex,
    List<FreeAgentMarketOutcome>? outcomes,
    List<CapException>? capExceptions,
  }) => OffseasonClearanceState(
    status: status ?? this.status,
    seasonYear: seasonYear ?? this.seasonYear,
    humanOffers: humanOffers ?? this.humanOffers,
    aiOffers: aiOffers ?? this.aiOffers,
    resolutionOrder: resolutionOrder ?? this.resolutionOrder,
    nextResolutionIndex: nextResolutionIndex ?? this.nextResolutionIndex,
    outcomes: outcomes ?? this.outcomes,
    capExceptions: capExceptions ?? this.capExceptions,
  );

  Map<String, Object?> toJson() => {
    'status': status.jsonValue,
    'seasonYear': seasonYear,
    'humanOffers': [for (final offer in humanOffers) offer.toJson()],
    'aiOffers': [for (final offer in aiOffers) offer.toJson()],
    'resolutionOrder': [for (final id in resolutionOrder) id.value],
    'nextResolutionIndex': nextResolutionIndex,
    'outcomes': [for (final outcome in outcomes) outcome.toJson()],
    'capExceptions': [
      for (final exception in capExceptions) exception.toJson(),
    ],
  };
}
