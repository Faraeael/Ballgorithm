import '../finance/financial_rules.dart';
import '../validation/validation_result.dart';
import 'ids.dart';
import 'roster_category.dart';

enum FreeAgentMarketStatus {
  notStarted('notStarted'),
  collectingHumanOffers('collectingHumanOffers'),
  preparedForResolution('preparedForResolution'),
  resolving('resolving'),
  roundComplete('roundComplete'),
  marketComplete('marketComplete'),
  recoveryRequired('recoveryRequired');

  const FreeAgentMarketStatus(this.jsonValue);

  final String jsonValue;

  static FreeAgentMarketStatus fromJson(String value) => values.firstWhere(
    (status) => status.jsonValue == value || status.name == value,
    orElse: () => throw ArgumentError.value(
      value,
      'marketStatus',
      'Unknown market status: $value',
    ),
  );
}

enum FreeAgentMarketOfferSource {
  human('human'),
  ai('ai');

  const FreeAgentMarketOfferSource(this.jsonValue);

  final String jsonValue;

  static FreeAgentMarketOfferSource fromJson(String value) => values.firstWhere(
    (source) => source.jsonValue == value || source.name == value,
    orElse: () => throw ArgumentError.value(
      value,
      'offerSource',
      'Unknown offer source: $value',
    ),
  );
}

enum FreeAgentMarketOfferOutcome {
  accepted('accepted'),
  rejected('rejected'),
  outbid('outbid'),
  financiallyUnavailable('financiallyUnavailable'),
  invalid('invalid');

  const FreeAgentMarketOfferOutcome(this.jsonValue);

  final String jsonValue;

  static FreeAgentMarketOfferOutcome fromJson(String value) =>
      values.firstWhere(
        (outcome) => outcome.jsonValue == value || outcome.name == value,
        orElse: () => throw ArgumentError.value(
          value,
          'offerOutcome',
          'Unknown offer outcome: $value',
        ),
      );
}

/// One staged market offer. It is pending until the round resolves.
final class FreeAgentMarketOffer {
  FreeAgentMarketOffer({
    required this.offerId,
    required this.playerId,
    required this.teamId,
    required this.roundNumber,
    required this.seasonYear,
    required this.category,
    required this.durationYears,
    required this.firstYearSalary,
    required this.source,
  }) {
    requireValid();
  }

  factory FreeAgentMarketOffer.fromJson(Map<String, dynamic> json) {
    final offerId = json['offerId'];
    final playerId = json['playerId'];
    final teamId = json['teamId'];
    final roundNumber = json['roundNumber'];
    final seasonYear = json['seasonYear'];
    final category = json['category'];
    final durationYears = json['durationYears'];
    final firstYearSalary = json['firstYearSalary'];
    final source = json['source'];
    if (offerId is! String ||
        playerId is! String ||
        teamId is! String ||
        roundNumber is! int ||
        seasonYear is! int ||
        category is! String ||
        durationYears is! int ||
        firstYearSalary is! int ||
        source is! String) {
      throw const FormatException('Malformed FreeAgentMarketOffer JSON');
    }
    return FreeAgentMarketOffer(
      offerId: offerId,
      playerId: PlayerId(playerId),
      teamId: TeamId(teamId),
      roundNumber: roundNumber,
      seasonYear: seasonYear,
      category: RosterCategory.fromJson(category),
      durationYears: durationYears,
      firstYearSalary: firstYearSalary,
      source: FreeAgentMarketOfferSource.fromJson(source),
    );
  }

  static String idFor({
    required TeamId teamId,
    required PlayerId playerId,
    required int roundNumber,
    required int seasonYear,
  }) =>
      'market-offer-${teamId.value}-${playerId.value}-$seasonYear-$roundNumber';

  final String offerId;
  final PlayerId playerId;
  final TeamId teamId;
  final int roundNumber;
  final int seasonYear;
  final RosterCategory category;
  final int durationYears;
  final int firstYearSalary;
  final FreeAgentMarketOfferSource source;

  List<int> get salarySchedule => category == RosterCategory.twoWay
      ? FinancialRules.twoWaySchedule(durationYears)
      : FinancialRules.standardSchedule(firstYearSalary, durationYears);

  List<ValidationIssue> validationIssues() {
    final issues = <ValidationIssue>[];
    if (offerId.trim().isEmpty) issues.add(_issue('offerId', 'empty offer id'));
    if (playerId.value.trim().isEmpty) {
      issues.add(_issue('playerId', 'empty player'));
    }
    if (teamId.value.trim().isEmpty) issues.add(_issue('teamId', 'empty team'));
    if (roundNumber < 1 || roundNumber > 2) {
      issues.add(_issue('roundNumber', 'round must be 1 or 2'));
    }
    if (seasonYear < 1) issues.add(_issue('seasonYear', 'season must be >= 1'));
    if (category != RosterCategory.standard &&
        category != RosterCategory.twoWay) {
      issues.add(_issue('category', 'category must be standard or two-way'));
    } else {
      final maxDuration = FinancialRules.maxDurationForCategory(category);
      if (durationYears < 1 || durationYears > maxDuration) {
        issues.add(_issue('durationYears', 'duration must be 1..$maxDuration'));
      }
      if (category == RosterCategory.twoWay &&
          firstYearSalary != FinancialRules.twoWaySalary) {
        issues.add(_issue('firstYearSalary', 'two-way salary must be 250'));
      }
      if (category == RosterCategory.standard &&
          (firstYearSalary < FinancialRules.minimumSalary ||
              firstYearSalary > FinancialRules.maximumSalary)) {
        issues.add(
          _issue('firstYearSalary', 'standard salary must be 400..8000'),
        );
      }
      if (durationYears >= 1 &&
          durationYears <= maxDuration &&
          salarySchedule.any(
            (salary) => salary > FinancialRules.maximumSalary,
          )) {
        issues.add(_issue('salarySchedule', 'salary schedule exceeds 8000'));
      }
    }
    return issues;
  }

  void requireValid() => ValidationResult(validationIssues()).throwIfInvalid();

  ValidationIssue _issue(String path, String message) => ValidationIssue(
    code: ValidationCode.freeAgentOfferInvalid,
    path: 'freeAgentMarket.offer.$path',
    message: message,
  );

  Map<String, Object?> toJson() => {
    'offerId': offerId,
    'playerId': playerId.value,
    'teamId': teamId.value,
    'roundNumber': roundNumber,
    'seasonYear': seasonYear,
    'category': category.jsonValue,
    'durationYears': durationYears,
    'firstYearSalary': firstYearSalary,
    'source': source.jsonValue,
  };
}

final class FreeAgentMarketOfferResult {
  const FreeAgentMarketOfferResult({
    required this.offerId,
    required this.teamId,
    required this.outcome,
    required this.reasonCode,
  });

  factory FreeAgentMarketOfferResult.fromJson(Map<String, dynamic> json) {
    final offerId = json['offerId'];
    final teamId = json['teamId'];
    final outcome = json['outcome'];
    final reasonCode = json['reasonCode'];
    if (offerId is! String ||
        teamId is! String ||
        outcome is! String ||
        reasonCode is! String) {
      throw const FormatException('Malformed market offer result JSON');
    }
    return FreeAgentMarketOfferResult(
      offerId: offerId,
      teamId: TeamId(teamId),
      outcome: FreeAgentMarketOfferOutcome.fromJson(outcome),
      reasonCode: reasonCode,
    );
  }

  final String offerId;
  final TeamId teamId;
  final FreeAgentMarketOfferOutcome outcome;
  final String reasonCode;

  Map<String, Object?> toJson() => {
    'offerId': offerId,
    'teamId': teamId.value,
    'outcome': outcome.jsonValue,
    'reasonCode': reasonCode,
  };
}

final class FreeAgentMarketOutcome {
  FreeAgentMarketOutcome({
    required this.playerId,
    required this.winningTeamId,
    required this.winningOfferId,
    required List<FreeAgentMarketOfferResult> results,
  }) : results = List.unmodifiable(results);

  factory FreeAgentMarketOutcome.fromJson(Map<String, dynamic> json) {
    final playerId = json['playerId'];
    final winningTeamId = json['winningTeamId'];
    final winningOfferId = json['winningOfferId'];
    final rawResults = json['results'];
    if (playerId is! String ||
        (winningTeamId != null && winningTeamId is! String) ||
        (winningOfferId != null && winningOfferId is! String) ||
        rawResults is! List) {
      throw const FormatException('Malformed market outcome JSON');
    }
    return FreeAgentMarketOutcome(
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
            throw const FormatException('Malformed market result'),
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

/// Persistent shared-market state for the two opening-offseason rounds.
final class FreeAgentMarketState {
  FreeAgentMarketState({
    required this.status,
    required this.roundNumber,
    required this.seasonYear,
    required List<FreeAgentMarketOffer> humanOffers,
    required List<FreeAgentMarketOffer> aiOffers,
    required List<PlayerId> resolutionOrder,
    required this.nextResolutionIndex,
    required List<FreeAgentMarketOutcome> outcomes,
    required this.completedRounds,
  }) : humanOffers = List.unmodifiable(humanOffers),
       aiOffers = List.unmodifiable(aiOffers),
       resolutionOrder = List.unmodifiable(resolutionOrder),
       outcomes = List.unmodifiable(outcomes) {
    validate();
  }

  factory FreeAgentMarketState.initial({required int seasonYear}) =>
      FreeAgentMarketState(
        status: FreeAgentMarketStatus.notStarted,
        roundNumber: 1,
        seasonYear: seasonYear,
        humanOffers: const [],
        aiOffers: const [],
        resolutionOrder: const [],
        nextResolutionIndex: 0,
        outcomes: const [],
        completedRounds: 0,
      );

  factory FreeAgentMarketState.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    final roundNumber = json['roundNumber'];
    final seasonYear = json['seasonYear'];
    final rawHuman = json['humanOffers'];
    final rawAi = json['aiOffers'];
    final rawOrder = json['resolutionOrder'];
    final nextResolutionIndex = json['nextResolutionIndex'];
    final rawOutcomes = json['outcomes'];
    final completedRounds = json['completedRounds'];
    if (status is! String ||
        roundNumber is! int ||
        seasonYear is! int ||
        rawHuman is! List ||
        rawAi is! List ||
        rawOrder is! List ||
        nextResolutionIndex is! int ||
        rawOutcomes is! List ||
        completedRounds is! int) {
      throw const FormatException('Malformed FreeAgentMarketState JSON');
    }
    return FreeAgentMarketState(
      status: FreeAgentMarketStatus.fromJson(status),
      roundNumber: roundNumber,
      seasonYear: seasonYear,
      humanOffers: [
        for (final raw in rawHuman)
          if (raw is Map<String, dynamic>)
            FreeAgentMarketOffer.fromJson(raw)
          else
            throw const FormatException('Malformed human market offer'),
      ],
      aiOffers: [
        for (final raw in rawAi)
          if (raw is Map<String, dynamic>)
            FreeAgentMarketOffer.fromJson(raw)
          else
            throw const FormatException('Malformed AI market offer'),
      ],
      resolutionOrder: [
        for (final raw in rawOrder)
          if (raw is String)
            PlayerId(raw)
          else
            throw const FormatException('Malformed resolution order'),
      ],
      nextResolutionIndex: nextResolutionIndex,
      outcomes: [
        for (final raw in rawOutcomes)
          if (raw is Map<String, dynamic>)
            FreeAgentMarketOutcome.fromJson(raw)
          else
            throw const FormatException('Malformed market outcome'),
      ],
      completedRounds: completedRounds,
    );
  }

  final FreeAgentMarketStatus status;
  final int roundNumber;
  final int seasonYear;
  final List<FreeAgentMarketOffer> humanOffers;
  final List<FreeAgentMarketOffer> aiOffers;
  final List<PlayerId> resolutionOrder;
  final int nextResolutionIndex;
  final List<FreeAgentMarketOutcome> outcomes;
  final int completedRounds;

  Iterable<FreeAgentMarketOffer> get allOffers => [...humanOffers, ...aiOffers];

  bool get isCollecting =>
      status == FreeAgentMarketStatus.collectingHumanOffers;

  bool get isResolvable =>
      status == FreeAgentMarketStatus.preparedForResolution ||
      status == FreeAgentMarketStatus.resolving;

  bool get isRoundComplete =>
      status == FreeAgentMarketStatus.roundComplete ||
      status == FreeAgentMarketStatus.marketComplete;

  FreeAgentMarketOffer? pendingHumanOffer({
    required TeamId teamId,
    required PlayerId playerId,
  }) {
    for (final offer in humanOffers) {
      if (offer.teamId == teamId && offer.playerId == playerId) return offer;
    }
    return null;
  }

  List<FreeAgentMarketOffer> offersFor(PlayerId playerId) => [
    for (final offer in allOffers)
      if (offer.playerId == playerId) offer,
  ];

  void validate() {
    final issues = <ValidationIssue>[];
    if (roundNumber < 1 || roundNumber > 2) {
      issues.add(_issue('roundNumber', 'round must be 1 or 2'));
    }
    if (completedRounds < 0 || completedRounds > 2) {
      issues.add(_issue('completedRounds', 'completedRounds must be 0..2'));
    }
    final offerIds = <String>{};
    final teamPlayerKeys = <String>{};
    for (final offer in allOffers) {
      issues.addAll(offer.validationIssues());
      if (!offerIds.add(offer.offerId)) {
        issues.add(_issue('offers', 'duplicate offer id ${offer.offerId}'));
      }
      final key =
          '${offer.teamId.value}:${offer.playerId.value}:${offer.roundNumber}';
      if (!teamPlayerKeys.add(key)) {
        issues.add(
          _issue(
            'offers',
            'duplicate team/player offer ${offer.teamId.value}/'
                '${offer.playerId.value}',
          ),
        );
      }
      if (offer.roundNumber != roundNumber || offer.seasonYear != seasonYear) {
        issues.add(_issue('offers', 'offer round/season mismatch'));
      }
    }
    final offeredIds = {
      for (final offer in allOffers) offer.playerId.value,
    }.toList()..sort();
    final orderIds = [for (final id in resolutionOrder) id.value];
    if (resolutionOrder.toSet().length != resolutionOrder.length) {
      issues.add(_issue('resolutionOrder', 'duplicate player in order'));
    }
    if (status == FreeAgentMarketStatus.notStarted) {
      if (allOffers.isNotEmpty ||
          resolutionOrder.isNotEmpty ||
          outcomes.isNotEmpty ||
          nextResolutionIndex != 0) {
        issues.add(_issue('status', 'notStarted must be empty'));
      }
    } else if (status == FreeAgentMarketStatus.collectingHumanOffers) {
      if (aiOffers.isNotEmpty ||
          resolutionOrder.isNotEmpty ||
          outcomes.isNotEmpty ||
          nextResolutionIndex != 0) {
        issues.add(_issue('status', 'collecting must have only human offers'));
      }
      if (roundNumber == 2 && completedRounds != 1) {
        issues.add(_issue('roundNumber', 'round 2 requires round 1 complete'));
      }
    } else if (status == FreeAgentMarketStatus.preparedForResolution ||
        status == FreeAgentMarketStatus.resolving) {
      if (orderIds.join(',') != offeredIds.join(',')) {
        issues.add(
          _issue('resolutionOrder', 'order must equal sorted offered players'),
        );
      }
      if (nextResolutionIndex < 0 ||
          nextResolutionIndex > resolutionOrder.length) {
        issues.add(_issue('nextResolutionIndex', 'cursor out of range'));
      }
      if (status == FreeAgentMarketStatus.resolving &&
          nextResolutionIndex >= resolutionOrder.length) {
        issues.add(
          _issue('nextResolutionIndex', 'resolving requires pending decisions'),
        );
      }
    } else if (isRoundComplete) {
      if (orderIds.join(',') != offeredIds.join(',')) {
        issues.add(
          _issue('resolutionOrder', 'order must equal sorted offered players'),
        );
      }
      if (nextResolutionIndex != resolutionOrder.length) {
        issues.add(
          _issue('nextResolutionIndex', 'complete requires full cursor'),
        );
      }
      if (outcomes.length != resolutionOrder.length) {
        issues.add(
          _issue('outcomes', 'one outcome per ordered player required'),
        );
      }
      for (var i = 0; i < outcomes.length; i++) {
        if (outcomes[i].playerId != resolutionOrder[i]) {
          issues.add(
            _issue('outcomes', 'outcomes must follow resolution order'),
          );
          break;
        }
      }
      if (completedRounds != roundNumber) {
        issues.add(_issue('completedRounds', 'completed rounds mismatch'));
      }
      if (status == FreeAgentMarketStatus.marketComplete && roundNumber != 2) {
        issues.add(_issue('status', 'marketComplete requires round 2'));
      }
    }
    if (status == FreeAgentMarketStatus.resolving) {
      for (var i = 0; i < outcomes.length; i++) {
        if (i >= resolutionOrder.length ||
            outcomes[i].playerId != resolutionOrder[i]) {
          issues.add(_issue('outcomes', 'outcomes must be a resolved prefix'));
          break;
        }
      }
      if (outcomes.length != nextResolutionIndex) {
        issues.add(_issue('outcomes', 'outcomes must match cursor'));
      }
    }
    for (final outcome in outcomes) {
      final resultIds = <String>{};
      var acceptedResult = 0;
      for (final result in outcome.results) {
        if (!offerIds.contains(result.offerId)) {
          issues.add(
            _issue(
              'outcomes',
              'result references unknown offer ${result.offerId}',
            ),
          );
        }
        if (!resultIds.add(result.offerId)) {
          issues.add(
            _issue('outcomes', 'duplicate result for offer ${result.offerId}'),
          );
        }
        if (result.outcome == FreeAgentMarketOfferOutcome.accepted) {
          acceptedResult++;
          if (outcome.winningTeamId != result.teamId ||
              outcome.winningOfferId != result.offerId) {
            issues.add(
              _issue('outcomes', 'accepted result does not match winner'),
            );
          }
        }
      }
      if (acceptedResult > 1) {
        issues.add(_issue('outcomes', 'multiple accepted offers for a player'));
      }
      if (acceptedResult == 0 &&
          (outcome.winningTeamId != null || outcome.winningOfferId != null)) {
        issues.add(_issue('outcomes', 'winner without accepted result'));
      }
      if (acceptedResult == 1 &&
          (outcome.winningTeamId == null || outcome.winningOfferId == null)) {
        issues.add(_issue('outcomes', 'accepted result without winner'));
      }
    }
    ValidationResult(issues).throwIfInvalid();
  }

  ValidationIssue _issue(String path, String message) => ValidationIssue(
    code: ValidationCode.freeAgentPoolInvalid,
    path: 'freeAgentMarket.$path',
    message: message,
  );

  FreeAgentMarketState copyWith({
    FreeAgentMarketStatus? status,
    int? roundNumber,
    int? seasonYear,
    List<FreeAgentMarketOffer>? humanOffers,
    List<FreeAgentMarketOffer>? aiOffers,
    List<PlayerId>? resolutionOrder,
    int? nextResolutionIndex,
    List<FreeAgentMarketOutcome>? outcomes,
    int? completedRounds,
  }) => FreeAgentMarketState(
    status: status ?? this.status,
    roundNumber: roundNumber ?? this.roundNumber,
    seasonYear: seasonYear ?? this.seasonYear,
    humanOffers: humanOffers ?? this.humanOffers,
    aiOffers: aiOffers ?? this.aiOffers,
    resolutionOrder: resolutionOrder ?? this.resolutionOrder,
    nextResolutionIndex: nextResolutionIndex ?? this.nextResolutionIndex,
    outcomes: outcomes ?? this.outcomes,
    completedRounds: completedRounds ?? this.completedRounds,
  );

  Map<String, Object?> toJson() => {
    'status': status.jsonValue,
    'roundNumber': roundNumber,
    'seasonYear': seasonYear,
    'humanOffers': [for (final offer in humanOffers) offer.toJson()],
    'aiOffers': [for (final offer in aiOffers) offer.toJson()],
    'resolutionOrder': [for (final id in resolutionOrder) id.value],
    'nextResolutionIndex': nextResolutionIndex,
    'outcomes': [for (final outcome in outcomes) outcome.toJson()],
    'completedRounds': completedRounds,
  };
}
