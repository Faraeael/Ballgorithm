import '../finance/financial_rules.dart';
import '../validation/validation_result.dart';
import 'free_agent_market.dart';
import 'ids.dart';
import 'player_contract.dart';
import 'roster_category.dart';

const String hardshipAuthorizationReason = 'mandatoryRosterCompletion-v1';

enum HardshipSettlementStatus {
  notStarted('notStarted'),
  preparedForResolution('preparedForResolution'),
  resolving('resolving'),
  complete('complete');

  const HardshipSettlementStatus(this.jsonValue);

  final String jsonValue;

  static HardshipSettlementStatus fromJson(String value) => values.firstWhere(
    (status) => status.jsonValue == value || status.name == value,
    orElse: () => throw ArgumentError.value(
      value,
      'hardshipSettlementStatus',
      'Unknown hardship settlement status: $value',
    ),
  );
}

enum HardshipAuthorizationStatus {
  unused('unused'),
  consumed('consumed');

  const HardshipAuthorizationStatus(this.jsonValue);

  final String jsonValue;

  static HardshipAuthorizationStatus fromJson(String value) =>
      values.firstWhere(
        (status) => status.jsonValue == value || status.name == value,
        orElse: () => throw ArgumentError.value(
          value,
          'hardshipAuthorizationStatus',
          'Unknown hardship authorization status: $value',
        ),
      );
}

/// A standard-player offer in the separate, one-time hardship settlement.
final class HardshipOffer {
  HardshipOffer({
    required this.offerId,
    required this.playerId,
    required this.teamId,
    required this.seasonYear,
    required this.durationYears,
    required this.firstYearSalary,
    required this.source,
  }) {
    requireValid();
  }

  factory HardshipOffer.fromJson(Map<String, dynamic> json) {
    final offerId = json['offerId'];
    final playerId = json['playerId'];
    final teamId = json['teamId'];
    final seasonYear = json['seasonYear'];
    final durationYears = json['durationYears'];
    final firstYearSalary = json['firstYearSalary'];
    final source = json['source'];
    if (offerId is! String ||
        playerId is! String ||
        teamId is! String ||
        seasonYear is! int ||
        durationYears is! int ||
        firstYearSalary is! int ||
        source is! String) {
      throw const FormatException('Malformed HardshipOffer JSON');
    }
    return HardshipOffer(
      offerId: offerId,
      playerId: PlayerId(playerId),
      teamId: TeamId(teamId),
      seasonYear: seasonYear,
      durationYears: durationYears,
      firstYearSalary: firstYearSalary,
      source: FreeAgentMarketOfferSource.fromJson(source),
    );
  }

  static String idFor({
    required TeamId teamId,
    required PlayerId playerId,
    required int seasonYear,
  }) => 'hardship-offer-${teamId.value}-${playerId.value}-$seasonYear';

  final String offerId;
  final PlayerId playerId;
  final TeamId teamId;
  final int seasonYear;
  final int durationYears;
  final int firstYearSalary;
  final FreeAgentMarketOfferSource source;

  RosterCategory get category => RosterCategory.standard;

  List<int> get salarySchedule =>
      FinancialRules.standardSchedule(firstYearSalary, durationYears);

  List<ValidationIssue> validationIssues() {
    final issues = <ValidationIssue>[];
    if (offerId !=
        idFor(teamId: teamId, playerId: playerId, seasonYear: seasonYear)) {
      issues.add(_issue('offerId', 'offer id does not match its identity'));
    }
    if (playerId.value.trim().isEmpty) {
      issues.add(_issue('playerId', 'player id must not be empty'));
    }
    if (teamId.value.trim().isEmpty) {
      issues.add(_issue('teamId', 'team id must not be empty'));
    }
    if (seasonYear < 1) {
      issues.add(_issue('seasonYear', 'season must be >= 1'));
    }
    if (firstYearSalary < FinancialRules.minimumSalary ||
        firstYearSalary > FinancialRules.maximumSalary) {
      issues.add(_issue('firstYearSalary', 'salary must be 400..8000 CU'));
    }
    if (durationYears < PlayerContract.minDurationYears ||
        durationYears > FinancialRules.maxDurationForCategory(category)) {
      issues.add(_issue('durationYears', 'invalid standard contract duration'));
    } else if (firstYearSalary >= FinancialRules.minimumSalary &&
        firstYearSalary <= FinancialRules.maximumSalary &&
        salarySchedule.any((salary) => salary > FinancialRules.maximumSalary)) {
      issues.add(_issue('salarySchedule', 'salary schedule exceeds 8000 CU'));
    }
    return issues;
  }

  void requireValid() => ValidationResult(validationIssues()).throwIfInvalid();

  ValidationIssue _issue(String path, String message) => ValidationIssue(
    code: ValidationCode.freeAgentOfferInvalid,
    path: 'hardshipOffer.$path',
    message: message,
  );

  Map<String, Object?> toJson() => {
    'offerId': offerId,
    'playerId': playerId.value,
    'teamId': teamId.value,
    'seasonYear': seasonYear,
    'durationYears': durationYears,
    'firstYearSalary': firstYearSalary,
    'source': source.jsonValue,
  };
}

/// Exact hardship authority for one franchise's sealed roster-completion offers.
final class HardshipAuthorization {
  HardshipAuthorization({
    required this.authorizationId,
    required this.teamId,
    required this.seasonYear,
    required this.additionalAmount,
    required this.existingOrdinaryRelief,
    required this.maximumCombinedOverage,
    required this.missingPlayers,
    required List<String> authorizedOfferIds,
    required this.reason,
    required this.status,
    required this.usedAmount,
    required List<String> transactionIds,
  }) : authorizedOfferIds = List.unmodifiable(authorizedOfferIds),
       transactionIds = List.unmodifiable(transactionIds) {
    requireValid();
  }

  factory HardshipAuthorization.fromJson(Map<String, dynamic> json) {
    final authorizationId = json['authorizationId'];
    final teamId = json['teamId'];
    final seasonYear = json['seasonYear'];
    final additionalAmount = json['additionalAmount'];
    final existingOrdinaryRelief = json['existingOrdinaryRelief'];
    final maximumCombinedOverage = json['maximumCombinedOverage'];
    final missingPlayers = json['missingPlayers'];
    final rawOfferIds = json['authorizedOfferIds'];
    final reason = json['reason'];
    final status = json['status'];
    final usedAmount = json['usedAmount'];
    final rawTransactions = json['transactionIds'];
    if (authorizationId is! String ||
        teamId is! String ||
        seasonYear is! int ||
        additionalAmount is! int ||
        existingOrdinaryRelief is! int ||
        maximumCombinedOverage is! int ||
        missingPlayers is! int ||
        rawOfferIds is! List ||
        reason is! String ||
        status is! String ||
        usedAmount is! int ||
        rawTransactions is! List ||
        rawOfferIds.any((value) => value is! String) ||
        rawTransactions.any((value) => value is! String)) {
      throw const FormatException('Malformed HardshipAuthorization JSON');
    }
    return HardshipAuthorization(
      authorizationId: authorizationId,
      teamId: TeamId(teamId),
      seasonYear: seasonYear,
      additionalAmount: additionalAmount,
      existingOrdinaryRelief: existingOrdinaryRelief,
      maximumCombinedOverage: maximumCombinedOverage,
      missingPlayers: missingPlayers,
      authorizedOfferIds: rawOfferIds.cast<String>(),
      reason: reason,
      status: HardshipAuthorizationStatus.fromJson(status),
      usedAmount: usedAmount,
      transactionIds: rawTransactions.cast<String>(),
    );
  }

  static String idFor(TeamId teamId, int seasonYear) =>
      'hardship-authorization-${teamId.value}-$seasonYear';

  final String authorizationId;
  final TeamId teamId;
  final int seasonYear;
  final int additionalAmount;
  final int existingOrdinaryRelief;
  final int maximumCombinedOverage;
  final int missingPlayers;
  final List<String> authorizedOfferIds;
  final String reason;
  final HardshipAuthorizationStatus status;
  final int usedAmount;
  final List<String> transactionIds;

  List<ValidationIssue> validationIssues() {
    final issues = <ValidationIssue>[];
    if (authorizationId != idFor(teamId, seasonYear)) {
      issues.add(_issue('authorizationId', 'id does not match team/season'));
    }
    if (teamId.value.trim().isEmpty || seasonYear < 1) {
      issues.add(_issue('identity', 'team and season must be valid'));
    }
    if (existingOrdinaryRelief < 0 ||
        existingOrdinaryRelief > FinancialRules.maximumReliefOverage) {
      issues.add(
        _issue('existingOrdinaryRelief', 'ordinary relief must be 0..800'),
      );
    }
    if (additionalAmount < 1 ||
        additionalAmount + existingOrdinaryRelief > maximumCombinedOverage ||
        maximumCombinedOverage !=
            FinancialRules.maximumCombinedHardshipOverage) {
      issues.add(
        _issue('additionalAmount', 'combined overage exceeds 1000 CU'),
      );
    }
    if (missingPlayers < 1 || missingPlayers > 2) {
      issues.add(_issue('missingPlayers', 'shortage must be one or two'));
    }
    if (authorizedOfferIds.isEmpty ||
        authorizedOfferIds.toSet().length != authorizedOfferIds.length) {
      issues.add(
        _issue('authorizedOfferIds', 'offer references must be unique'),
      );
    }
    if (reason != hardshipAuthorizationReason) {
      issues.add(_issue('reason', 'unknown hardship authorization reason'));
    }
    if (usedAmount < 0 || usedAmount > additionalAmount) {
      issues.add(_issue('usedAmount', 'used relief exceeds authorization'));
    }
    if (transactionIds.toSet().length != transactionIds.length ||
        transactionIds.any((value) => value.trim().isEmpty)) {
      issues.add(
        _issue('transactionIds', 'transactions must be unique and valid'),
      );
    }
    if (status == HardshipAuthorizationStatus.unused &&
        (usedAmount != 0 || transactionIds.isNotEmpty)) {
      issues.add(_issue('status', 'unused authority cannot have transactions'));
    }
    if (status == HardshipAuthorizationStatus.consumed &&
        transactionIds.isEmpty) {
      issues.add(_issue('status', 'consumed authority requires a transaction'));
    }
    return issues;
  }

  void requireValid() => ValidationResult(validationIssues()).throwIfInvalid();

  ValidationIssue _issue(String path, String message) => ValidationIssue(
    code: ValidationCode.financialTeamInvalid,
    path: 'hardshipAuthorization.$path',
    message: message,
  );

  HardshipAuthorization copyWith({
    HardshipAuthorizationStatus? status,
    int? usedAmount,
    List<String>? transactionIds,
  }) => HardshipAuthorization(
    authorizationId: authorizationId,
    teamId: teamId,
    seasonYear: seasonYear,
    additionalAmount: additionalAmount,
    existingOrdinaryRelief: existingOrdinaryRelief,
    maximumCombinedOverage: maximumCombinedOverage,
    missingPlayers: missingPlayers,
    authorizedOfferIds: authorizedOfferIds,
    reason: reason,
    status: status ?? this.status,
    usedAmount: usedAmount ?? this.usedAmount,
    transactionIds: transactionIds ?? this.transactionIds,
  );

  Map<String, Object?> toJson() => {
    'authorizationId': authorizationId,
    'teamId': teamId.value,
    'seasonYear': seasonYear,
    'additionalAmount': additionalAmount,
    'existingOrdinaryRelief': existingOrdinaryRelief,
    'maximumCombinedOverage': maximumCombinedOverage,
    'missingPlayers': missingPlayers,
    'authorizedOfferIds': authorizedOfferIds,
    'reason': reason,
    'status': status.jsonValue,
    'usedAmount': usedAmount,
    'transactionIds': transactionIds,
  };
}

final class HardshipOutcome {
  HardshipOutcome({
    required this.playerId,
    required this.winningTeamId,
    required this.winningOfferId,
    required List<FreeAgentMarketOfferResult> results,
  }) : results = List.unmodifiable(results);

  factory HardshipOutcome.fromJson(Map<String, dynamic> json) {
    final playerId = json['playerId'];
    final winningTeamId = json['winningTeamId'];
    final winningOfferId = json['winningOfferId'];
    final rawResults = json['results'];
    if (playerId is! String ||
        (winningTeamId != null && winningTeamId is! String) ||
        (winningOfferId != null && winningOfferId is! String) ||
        rawResults is! List) {
      throw const FormatException('Malformed HardshipOutcome JSON');
    }
    return HardshipOutcome(
      playerId: PlayerId(playerId),
      winningTeamId: winningTeamId == null
          ? null
          : TeamId(winningTeamId as String),
      winningOfferId: winningOfferId as String?,
      results: [
        for (final raw in rawResults)
          if (raw is Map<String, dynamic>)
            FreeAgentMarketOfferResult.fromJson(raw)
          else
            throw const FormatException('Malformed hardship result'),
      ],
    );
  }

  final PlayerId playerId;
  final TeamId? winningTeamId;
  final String? winningOfferId;
  final List<FreeAgentMarketOfferResult> results;

  Map<String, Object?> toJson() => {
    'playerId': playerId.value,
    if (winningTeamId != null) 'winningTeamId': winningTeamId!.value,
    if (winningOfferId != null) 'winningOfferId': winningOfferId,
    'results': [for (final result in results) result.toJson()],
  };
}

/// Independent, resumable hardship settlement. Never part of market history.
final class HardshipSettlement {
  HardshipSettlement({
    required this.status,
    required this.seasonYear,
    required this.humanParticipationConfirmed,
    required List<HardshipOffer> offers,
    required List<PlayerId> resolutionOrder,
    required this.nextResolutionIndex,
    required List<HardshipOutcome> outcomes,
    required List<HardshipAuthorization> authorizations,
  }) : offers = List.unmodifiable(offers),
       resolutionOrder = List.unmodifiable(resolutionOrder),
       outcomes = List.unmodifiable(outcomes),
       authorizations = List.unmodifiable(authorizations) {
    validate();
  }

  factory HardshipSettlement.initial({required int seasonYear}) =>
      HardshipSettlement(
        status: HardshipSettlementStatus.notStarted,
        seasonYear: seasonYear,
        humanParticipationConfirmed: false,
        offers: const [],
        resolutionOrder: const [],
        nextResolutionIndex: 0,
        outcomes: const [],
        authorizations: const [],
      );

  factory HardshipSettlement.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    final seasonYear = json['seasonYear'];
    final humanParticipationConfirmed = json['humanParticipationConfirmed'];
    final rawOffers = json['offers'];
    final rawOrder = json['resolutionOrder'];
    final nextResolutionIndex = json['nextResolutionIndex'];
    final rawOutcomes = json['outcomes'];
    final rawAuthorizations = json['authorizations'];
    if (status is! String ||
        seasonYear is! int ||
        humanParticipationConfirmed is! bool ||
        rawOffers is! List ||
        rawOrder is! List ||
        nextResolutionIndex is! int ||
        rawOutcomes is! List ||
        rawAuthorizations is! List) {
      throw const FormatException('Malformed HardshipSettlement JSON');
    }
    return HardshipSettlement(
      status: HardshipSettlementStatus.fromJson(status),
      seasonYear: seasonYear,
      humanParticipationConfirmed: humanParticipationConfirmed,
      offers: [
        for (final raw in rawOffers)
          if (raw is Map<String, dynamic>)
            HardshipOffer.fromJson(raw)
          else
            throw const FormatException('Malformed hardship offer'),
      ],
      resolutionOrder: [
        for (final raw in rawOrder)
          if (raw is String)
            PlayerId(raw)
          else
            throw const FormatException('Malformed hardship resolution order'),
      ],
      nextResolutionIndex: nextResolutionIndex,
      outcomes: [
        for (final raw in rawOutcomes)
          if (raw is Map<String, dynamic>)
            HardshipOutcome.fromJson(raw)
          else
            throw const FormatException('Malformed hardship outcome'),
      ],
      authorizations: [
        for (final raw in rawAuthorizations)
          if (raw is Map<String, dynamic>)
            HardshipAuthorization.fromJson(raw)
          else
            throw const FormatException('Malformed hardship authorization'),
      ],
    );
  }

  final HardshipSettlementStatus status;
  final int seasonYear;
  final bool humanParticipationConfirmed;
  final List<HardshipOffer> offers;
  final List<PlayerId> resolutionOrder;
  final int nextResolutionIndex;
  final List<HardshipOutcome> outcomes;
  final List<HardshipAuthorization> authorizations;

  bool get isResolvable =>
      status == HardshipSettlementStatus.preparedForResolution ||
      status == HardshipSettlementStatus.resolving;
  bool get isComplete => status == HardshipSettlementStatus.complete;

  List<HardshipOffer> offersFor(PlayerId playerId) => [
    for (final offer in offers)
      if (offer.playerId == playerId) offer,
  ];

  HardshipAuthorization? authorizationFor(TeamId teamId) =>
      authorizations.where((entry) => entry.teamId == teamId).firstOrNull;

  HardshipOffer? offerById(String offerId) =>
      offers.where((offer) => offer.offerId == offerId).firstOrNull;

  void validate() {
    if (seasonYear < 1) {
      throw const FormatException('Hardship season must be >= 1');
    }
    final offerIds = <String>{};
    final teamPlayers = <String>{};
    for (final offer in offers) {
      offerIds.add(offer.offerId);
      if (!teamPlayers.add('${offer.teamId.value}:${offer.playerId.value}')) {
        throw const FormatException('Duplicate team/player hardship offer');
      }
      if (offer.seasonYear != seasonYear) {
        throw const FormatException('Hardship offer season mismatch');
      }
    }
    if (offerIds.length != offers.length) {
      throw const FormatException('Duplicate hardship offer id');
    }
    final ordered = {for (final offer in offers) offer.playerId.value}.toList()
      ..sort();
    if (resolutionOrder.map((id) => id.value).join(',') != ordered.join(',')) {
      throw const FormatException('Hardship order must match offered players');
    }
    if (resolutionOrder.toSet().length != resolutionOrder.length) {
      throw const FormatException('Duplicate hardship resolution player');
    }
    if (status == HardshipSettlementStatus.notStarted) {
      if (humanParticipationConfirmed ||
          offers.isNotEmpty ||
          resolutionOrder.isNotEmpty ||
          nextResolutionIndex != 0 ||
          outcomes.isNotEmpty ||
          authorizations.isNotEmpty) {
        throw const FormatException(
          'Unstarted hardship settlement is not empty',
        );
      }
    } else if (status == HardshipSettlementStatus.preparedForResolution) {
      if (nextResolutionIndex != 0 || outcomes.isNotEmpty || offers.isEmpty) {
        throw const FormatException(
          'Prepared hardship settlement has no offers or has progress',
        );
      }
      if (authorizations.isEmpty) {
        throw const FormatException('Hardship offers lack authorization');
      }
    } else if (status == HardshipSettlementStatus.resolving) {
      if (nextResolutionIndex < 0 ||
          nextResolutionIndex >= resolutionOrder.length ||
          outcomes.length != nextResolutionIndex) {
        throw const FormatException('Invalid hardship resolution cursor');
      }
    } else if (status == HardshipSettlementStatus.complete) {
      if (nextResolutionIndex != resolutionOrder.length ||
          outcomes.length != resolutionOrder.length) {
        throw const FormatException(
          'Completed hardship settlement is incomplete',
        );
      }
    }
    final outcomePlayers = <String>{};
    for (var index = 0; index < outcomes.length; index++) {
      final outcome = outcomes[index];
      if (outcome.playerId != resolutionOrder[index] ||
          !outcomePlayers.add(outcome.playerId.value)) {
        throw const FormatException('Hardship outcomes do not match cursor');
      }
      final expected = {
        for (final offer in offersFor(outcome.playerId)) offer.offerId,
      };
      final seen = <String>{};
      var acceptedCount = 0;
      for (final result in outcome.results) {
        final offer = offerById(result.offerId);
        if (offer == null ||
            offer.playerId != outcome.playerId ||
            offer.teamId != result.teamId ||
            !seen.add(result.offerId)) {
          throw const FormatException('Hardship result does not match offer');
        }
        if (result.outcome == FreeAgentMarketOfferOutcome.accepted) {
          acceptedCount++;
          if (outcome.winningTeamId != result.teamId ||
              outcome.winningOfferId != result.offerId) {
            throw const FormatException(
              'Hardship winner does not match result',
            );
          }
        }
      }
      if (seen.length != expected.length || !seen.containsAll(expected)) {
        throw const FormatException('Hardship outcome omits an offer result');
      }
      if (acceptedCount > 1 ||
          (acceptedCount == 0 &&
              (outcome.winningTeamId != null ||
                  outcome.winningOfferId != null)) ||
          (acceptedCount == 1 &&
              (outcome.winningTeamId == null ||
                  outcome.winningOfferId == null))) {
        throw const FormatException('Invalid hardship winner count');
      }
    }
    final authorizationTeams = <String>{};
    for (final authorization in authorizations) {
      if (!authorizationTeams.add(authorization.teamId.value) ||
          authorization.seasonYear != seasonYear) {
        throw const FormatException(
          'Duplicate or wrong-season hardship authority',
        );
      }
      final teamOfferIds = {
        for (final offer in offers)
          if (offer.teamId == authorization.teamId) offer.offerId,
      };
      if (teamOfferIds.length != authorization.authorizedOfferIds.length ||
          !teamOfferIds.containsAll(authorization.authorizedOfferIds)) {
        throw const FormatException(
          'Hardship authority offer linkage mismatch',
        );
      }
    }
    if (offers.any(
      (offer) => !authorizationTeams.contains(offer.teamId.value),
    )) {
      throw const FormatException('Hardship offer lacks team authorization');
    }
  }

  HardshipSettlement copyWith({
    HardshipSettlementStatus? status,
    bool? humanParticipationConfirmed,
    List<HardshipOffer>? offers,
    List<PlayerId>? resolutionOrder,
    int? nextResolutionIndex,
    List<HardshipOutcome>? outcomes,
    List<HardshipAuthorization>? authorizations,
  }) => HardshipSettlement(
    status: status ?? this.status,
    seasonYear: seasonYear,
    humanParticipationConfirmed:
        humanParticipationConfirmed ?? this.humanParticipationConfirmed,
    offers: offers ?? this.offers,
    resolutionOrder: resolutionOrder ?? this.resolutionOrder,
    nextResolutionIndex: nextResolutionIndex ?? this.nextResolutionIndex,
    outcomes: outcomes ?? this.outcomes,
    authorizations: authorizations ?? this.authorizations,
  );

  Map<String, Object?> toJson() => {
    'status': status.jsonValue,
    'seasonYear': seasonYear,
    'humanParticipationConfirmed': humanParticipationConfirmed,
    'offers': [for (final offer in offers) offer.toJson()],
    'resolutionOrder': [for (final id in resolutionOrder) id.value],
    'nextResolutionIndex': nextResolutionIndex,
    'outcomes': [for (final outcome in outcomes) outcome.toJson()],
    'authorizations': [
      for (final authorization in authorizations) authorization.toJson(),
    ],
  };
}
