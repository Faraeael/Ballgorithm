import '../finance/financial_rules.dart';
import '../validation/validation_result.dart';
import 'ids.dart';
import 'roster_category.dart';

/// Persisted player-side outcome of a formal free-agent offer.
enum FreeAgentOfferOutcome {
  accepted('accepted'),
  salaryTooLow('salaryTooLow'),
  unfavorableDuration('unfavorableDuration'),
  poorFit('poorFit'),
  inappropriateCategory('inappropriateCategory');

  const FreeAgentOfferOutcome(this.jsonValue);

  final String jsonValue;

  static FreeAgentOfferOutcome fromJson(String value) => values.firstWhere(
    (outcome) => outcome.jsonValue == value || outcome.name == value,
    orElse: () => throw ArgumentError.value(
      value,
      'outcome',
      'Unknown free-agent offer outcome: $value',
    ),
  );

  bool get isAccepted => this == accepted;
}

/// One durable formal free-agent offer attempt.
final class FreeAgentOfferAttempt {
  FreeAgentOfferAttempt({
    required this.offerId,
    required this.playerId,
    required this.teamId,
    required this.seasonYear,
    required this.category,
    required this.durationYears,
    required this.firstYearSalary,
    required this.outcome,
    required this.reasonCode,
    required this.attemptNumber,
    this.acquisitionTransactionId,
  }) {
    requireValid();
  }

  factory FreeAgentOfferAttempt.fromJson(Map<String, dynamic> json) {
    final offerId = json['offerId'];
    final playerId = json['playerId'];
    final teamId = json['teamId'];
    final seasonYear = json['seasonYear'];
    final category = json['category'];
    final durationYears = json['durationYears'];
    final firstYearSalary = json['firstYearSalary'];
    final outcome = json['outcome'];
    final reasonCode = json['reasonCode'];
    final attemptNumber = json['attemptNumber'];
    final acquisitionTransactionId = json['acquisitionTransactionId'];
    if (offerId is! String ||
        playerId is! String ||
        teamId is! String ||
        seasonYear is! int ||
        category is! String ||
        durationYears is! int ||
        firstYearSalary is! int ||
        outcome is! String ||
        reasonCode is! String ||
        attemptNumber is! int ||
        (acquisitionTransactionId != null &&
            acquisitionTransactionId is! String)) {
      throw const FormatException('Malformed FreeAgentOfferAttempt JSON');
    }
    return FreeAgentOfferAttempt(
      offerId: offerId,
      playerId: PlayerId(playerId),
      teamId: TeamId(teamId),
      seasonYear: seasonYear,
      category: RosterCategory.fromJson(category),
      durationYears: durationYears,
      firstYearSalary: firstYearSalary,
      outcome: FreeAgentOfferOutcome.fromJson(outcome),
      reasonCode: reasonCode,
      attemptNumber: attemptNumber,
      acquisitionTransactionId: acquisitionTransactionId as String?,
    );
  }

  static String idFor(
    TeamId teamId,
    PlayerId playerId,
    int seasonYear,
    int attemptNumber,
  ) =>
      'free-agent-offer-${teamId.value}-${playerId.value}-$seasonYear-$attemptNumber';

  static const int maximumPlayerSideAttempts = 2;

  final String offerId;
  final PlayerId playerId;
  final TeamId teamId;
  final int seasonYear;
  final RosterCategory category;
  final int durationYears;
  final int firstYearSalary;
  final FreeAgentOfferOutcome outcome;
  final String reasonCode;
  final int attemptNumber;

  /// Set only for an accepted offer.
  final String? acquisitionTransactionId;

  List<int> get salarySchedule => category == RosterCategory.twoWay
      ? FinancialRules.twoWaySchedule(durationYears)
      : FinancialRules.standardSchedule(firstYearSalary, durationYears);

  List<ValidationIssue> validationIssues() {
    final issues = <ValidationIssue>[];
    if (offerId.trim().isEmpty) {
      issues.add(_issue('offerId', 'offer id must not be empty'));
    }
    if (playerId.value.trim().isEmpty) {
      issues.add(_issue('playerId', 'offer player id must not be empty'));
    }
    if (teamId.value.trim().isEmpty) {
      issues.add(_issue('teamId', 'offer team id must not be empty'));
    }
    if (seasonYear < 1) {
      issues.add(_issue('seasonYear', 'offer season must be >= 1'));
    }
    if (category != RosterCategory.standard &&
        category != RosterCategory.twoWay) {
      issues.add(
        _issue('category', 'offer category must be standard or two-way'),
      );
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
      if (durationYears >= 1 && durationYears <= maxDuration) {
        final schedule = salarySchedule;
        if (schedule.any((salary) => salary > FinancialRules.maximumSalary)) {
          issues.add(_issue('salarySchedule', 'salary schedule exceeds 8000'));
        }
      }
    }
    if (attemptNumber < 1 || attemptNumber > maximumPlayerSideAttempts) {
      issues.add(
        _issue(
          'attemptNumber',
          'attempt number must be 1..$maximumPlayerSideAttempts',
        ),
      );
    }
    if (reasonCode.trim().isEmpty) {
      issues.add(_issue('reasonCode', 'reason code must not be empty'));
    }
    if (outcome.isAccepted) {
      if (acquisitionTransactionId == null ||
          acquisitionTransactionId!.trim().isEmpty) {
        issues.add(
          _issue(
            'acquisitionTransactionId',
            'accepted offer requires an acquisition link',
          ),
        );
      }
    } else if (acquisitionTransactionId != null) {
      issues.add(
        _issue(
          'acquisitionTransactionId',
          'rejected offer must not link an acquisition',
        ),
      );
    }
    return issues;
  }

  void requireValid() {
    ValidationResult(validationIssues()).throwIfInvalid();
  }

  ValidationIssue _issue(String path, String message) => ValidationIssue(
    code: ValidationCode.freeAgentOfferInvalid,
    path: 'freeAgentOffers.$path',
    message: message,
  );

  Map<String, Object?> toJson() => {
    'offerId': offerId,
    'playerId': playerId.value,
    'teamId': teamId.value,
    'seasonYear': seasonYear,
    'category': category.jsonValue,
    'durationYears': durationYears,
    'firstYearSalary': firstYearSalary,
    'outcome': outcome.jsonValue,
    'reasonCode': reasonCode,
    'attemptNumber': attemptNumber,
    if (acquisitionTransactionId != null)
      'acquisitionTransactionId': acquisitionTransactionId,
  };
}

/// Persistent formal free-agent offer history.
final class FreeAgentOfferLedger {
  factory FreeAgentOfferLedger({
    required Iterable<FreeAgentOfferAttempt> entries,
  }) {
    final list = entries.toList();
    final ids = <String>{};
    final keys = <String>{};
    for (final entry in list) {
      if (!ids.add(entry.offerId)) {
        throw DomainValidationException([
          ValidationIssue(
            code: ValidationCode.freeAgentOfferDuplicate,
            path: 'freeAgentOffers',
            message: 'duplicate offer id ${entry.offerId}',
          ),
        ]);
      }
      final key = _key(entry.teamId, entry.playerId, entry.seasonYear);
      final attemptKey = '$key:${entry.attemptNumber}';
      if (!keys.add(attemptKey)) {
        throw DomainValidationException([
          ValidationIssue(
            code: ValidationCode.freeAgentOfferDuplicate,
            path: 'freeAgentOffers',
            message:
                'duplicate attempt ${entry.attemptNumber} for '
                '${entry.playerId.value}',
          ),
        ]);
      }
    }
    final ledger = FreeAgentOfferLedger._({
      for (final entry in list) entry.offerId: entry,
    });
    ledger.validate();
    return ledger;
  }

  FreeAgentOfferLedger._(Map<String, FreeAgentOfferAttempt> entries)
    : entries = Map.unmodifiable(entries);

  factory FreeAgentOfferLedger.empty() =>
      FreeAgentOfferLedger(entries: const []);

  factory FreeAgentOfferLedger.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    if (rawEntries is! List) {
      throw const FormatException('Malformed FreeAgentOfferLedger JSON');
    }
    final entries = <FreeAgentOfferAttempt>[];
    for (final raw in rawEntries) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Malformed offer entry');
      }
      entries.add(FreeAgentOfferAttempt.fromJson(raw));
    }
    return FreeAgentOfferLedger(entries: entries);
  }

  final Map<String, FreeAgentOfferAttempt> entries;

  int get length => entries.length;

  bool get isEmpty => entries.isEmpty;

  static String _key(TeamId teamId, PlayerId playerId, int seasonYear) =>
      '${teamId.value}:${playerId.value}:$seasonYear';

  List<FreeAgentOfferAttempt> attemptsFor({
    required TeamId teamId,
    required PlayerId playerId,
    required int seasonYear,
  }) {
    final key = _key(teamId, playerId, seasonYear);
    final attempts = [
      for (final entry in entries.values)
        if (_key(entry.teamId, entry.playerId, entry.seasonYear) == key) entry,
    ]..sort((a, b) => a.attemptNumber.compareTo(b.attemptNumber));
    return attempts;
  }

  int remainingAttempts({
    required TeamId teamId,
    required PlayerId playerId,
    required int seasonYear,
  }) =>
      FreeAgentOfferAttempt.maximumPlayerSideAttempts -
      attemptsFor(
        teamId: teamId,
        playerId: playerId,
        seasonYear: seasonYear,
      ).length;

  FreeAgentOfferLedger add(FreeAgentOfferAttempt attempt) {
    if (entries.containsKey(attempt.offerId)) {
      throw DomainValidationException([
        ValidationIssue(
          code: ValidationCode.freeAgentOfferDuplicate,
          path: 'freeAgentOffers',
          message: 'duplicate offer id ${attempt.offerId}',
        ),
      ]);
    }
    return FreeAgentOfferLedger(entries: [...entries.values, attempt]);
  }

  void validate() {
    final issues = <ValidationIssue>[];
    for (final entry in entries.values) {
      issues.addAll(entry.validationIssues());
    }
    final grouped = <String, List<FreeAgentOfferAttempt>>{};
    for (final entry in entries.values) {
      final key = _key(entry.teamId, entry.playerId, entry.seasonYear);
      (grouped[key] ??= []).add(entry);
    }
    for (final attempts in grouped.values) {
      attempts.sort((a, b) => a.attemptNumber.compareTo(b.attemptNumber));
      if (attempts.length > FreeAgentOfferAttempt.maximumPlayerSideAttempts) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.freeAgentOfferLimitReached,
            path: 'freeAgentOffers',
            message:
                'more than ${FreeAgentOfferAttempt.maximumPlayerSideAttempts} '
                'player-side attempts for one player',
          ),
        );
      }
      for (var i = 0; i < attempts.length; i++) {
        if (attempts[i].attemptNumber != i + 1) {
          issues.add(
            ValidationIssue(
              code: ValidationCode.freeAgentOfferInvalid,
              path: 'freeAgentOffers',
              message: 'attempt numbers must be contiguous from 1',
            ),
          );
        }
      }
      final accepted = attempts.where((a) => a.outcome.isAccepted).toList();
      if (accepted.length > 1) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.freeAgentOfferInvalid,
            path: 'freeAgentOffers',
            message: 'multiple accepted offers for one player/team/season',
          ),
        );
      }
      if (accepted.isNotEmpty) {
        final last = attempts.last;
        if (!last.outcome.isAccepted) {
          issues.add(
            ValidationIssue(
              code: ValidationCode.freeAgentOfferInvalid,
              path: 'freeAgentOffers',
              message: 'accepted offer must be the final attempt',
            ),
          );
        }
      }
    }
    ValidationResult(issues).throwIfInvalid();
  }

  Map<String, Object?> toJson() {
    final ordered = entries.values.toList()
      ..sort((a, b) => a.offerId.compareTo(b.offerId));
    return {
      'entries': [for (final entry in ordered) entry.toJson()],
    };
  }
}
