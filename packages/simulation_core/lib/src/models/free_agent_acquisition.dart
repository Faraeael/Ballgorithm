import '../validation/validation_result.dart';
import 'ids.dart';
import 'roster_category.dart';

/// Where an acquired player came from. Only the initial pool is implemented.
enum AcquisitionOrigin {
  initialPool('initialPool'),
  clearance('clearance'),
  hardship('hardship');

  const AcquisitionOrigin(this.jsonValue);

  final String jsonValue;

  static AcquisitionOrigin fromJson(String value) => values.firstWhere(
    (origin) => origin.jsonValue == value || origin.name == value,
    orElse: () => throw ArgumentError.value(
      value,
      'origin',
      'Unknown acquisition origin: $value',
    ),
  );
}

/// One authoritative free-agent acquisition.
final class FreeAgentAcquisition {
  FreeAgentAcquisition({
    required this.transactionId,
    required this.playerId,
    required this.teamId,
    required this.contractId,
    required this.seasonYear,
    required this.category,
    this.origin = AcquisitionOrigin.initialPool,
  }) {
    requireValid();
  }

  factory FreeAgentAcquisition.fromJson(Map<String, dynamic> json) {
    final transactionId = json['transactionId'];
    final playerId = json['playerId'];
    final teamId = json['teamId'];
    final contractId = json['contractId'];
    final seasonYear = json['seasonYear'];
    final category = json['category'];
    final origin = json['origin'];
    if (transactionId is! String ||
        playerId is! String ||
        teamId is! String ||
        contractId is! String ||
        seasonYear is! int ||
        category is! String ||
        origin is! String) {
      throw const FormatException('Malformed FreeAgentAcquisition JSON');
    }
    return FreeAgentAcquisition(
      transactionId: transactionId,
      playerId: PlayerId(playerId),
      teamId: TeamId(teamId),
      contractId: contractId,
      seasonYear: seasonYear,
      category: RosterCategory.fromJson(category),
      origin: AcquisitionOrigin.fromJson(origin),
    );
  }

  static String idFor(PlayerId playerId, int seasonYear) =>
      'free-agent-acquisition-${playerId.value}-$seasonYear';

  final String transactionId;
  final PlayerId playerId;
  final TeamId teamId;
  final String contractId;
  final int seasonYear;
  final RosterCategory category;
  final AcquisitionOrigin origin;

  List<ValidationIssue> validationIssues() {
    final issues = <ValidationIssue>[];
    if (transactionId.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.freeAgentAcquisitionInvalid,
          path: 'freeAgentAcquisitions.transactionId',
          message: 'acquisition transaction id must not be empty',
        ),
      );
    }
    if (playerId.value.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.freeAgentAcquisitionInvalid,
          path: 'freeAgentAcquisitions.playerId',
          message: 'acquisition player id must not be empty',
        ),
      );
    }
    if (teamId.value.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.freeAgentAcquisitionInvalid,
          path: 'freeAgentAcquisitions.teamId',
          message: 'acquisition team id must not be empty',
        ),
      );
    }
    if (contractId.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.freeAgentAcquisitionInvalid,
          path: 'freeAgentAcquisitions.contractId',
          message: 'acquisition contract id must not be empty',
        ),
      );
    }
    if (seasonYear < 1) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.freeAgentAcquisitionInvalid,
          path: 'freeAgentAcquisitions.seasonYear',
          message: 'acquisition season must be >= 1, got $seasonYear',
        ),
      );
    }
    if (category != RosterCategory.standard &&
        category != RosterCategory.twoWay) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.freeAgentAcquisitionInvalid,
          path: 'freeAgentAcquisitions.category',
          message:
              'acquisition category must be standard or twoWay, '
              'got ${category.jsonValue}',
        ),
      );
    }
    return issues;
  }

  void requireValid() {
    ValidationResult(validationIssues()).throwIfInvalid();
  }

  Map<String, Object?> toJson() => {
    'transactionId': transactionId,
    'playerId': playerId.value,
    'teamId': teamId.value,
    'contractId': contractId,
    'seasonYear': seasonYear,
    'category': category.jsonValue,
    'origin': origin.jsonValue,
  };
}

/// Persistent, authoritative free-agent acquisition history.
final class FreeAgentAcquisitionLedger {
  factory FreeAgentAcquisitionLedger({
    required Iterable<FreeAgentAcquisition> entries,
  }) {
    final list = entries.toList();
    final txIds = <String>{};
    final playerIds = <String>{};
    for (final entry in list) {
      if (!txIds.add(entry.transactionId)) {
        throw DomainValidationException([
          ValidationIssue(
            code: ValidationCode.freeAgentAcquisitionInvalid,
            path: 'freeAgentAcquisitions',
            message: 'duplicate transaction id ${entry.transactionId}',
          ),
        ]);
      }
      if (!playerIds.add(entry.playerId.value)) {
        throw DomainValidationException([
          ValidationIssue(
            code: ValidationCode.freeAgentAcquisitionInvalid,
            path: 'freeAgentAcquisitions',
            message: 'multiple acquisitions for player ${entry.playerId.value}',
          ),
        ]);
      }
    }
    final ledger = FreeAgentAcquisitionLedger._({
      for (final entry in list) entry.transactionId: entry,
    });
    ledger.validate();
    return ledger;
  }

  FreeAgentAcquisitionLedger._(Map<String, FreeAgentAcquisition> entries)
    : entries = Map.unmodifiable(entries);

  factory FreeAgentAcquisitionLedger.empty() =>
      FreeAgentAcquisitionLedger(entries: const []);

  factory FreeAgentAcquisitionLedger.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    if (rawEntries is! List) {
      throw const FormatException('Malformed FreeAgentAcquisitionLedger JSON');
    }
    final parsed = <FreeAgentAcquisition>[];
    for (final raw in rawEntries) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Malformed acquisition entry');
      }
      parsed.add(FreeAgentAcquisition.fromJson(raw));
    }
    return FreeAgentAcquisitionLedger(entries: parsed);
  }

  final Map<String, FreeAgentAcquisition> entries;

  int get length => entries.length;

  bool get isEmpty => entries.isEmpty;

  bool hasPlayer(PlayerId playerId) =>
      entries.values.any((entry) => entry.playerId == playerId);

  FreeAgentAcquisition? forPlayer(PlayerId playerId) {
    for (final entry in entries.values) {
      if (entry.playerId == playerId) return entry;
    }
    return null;
  }

  List<FreeAgentAcquisition> get ordered {
    final ordered = entries.values.toList()
      ..sort((a, b) => a.transactionId.compareTo(b.transactionId));
    return ordered;
  }

  FreeAgentAcquisitionLedger add(FreeAgentAcquisition acquisition) {
    if (entries.containsKey(acquisition.transactionId) ||
        hasPlayer(acquisition.playerId)) {
      throw DomainValidationException([
        ValidationIssue(
          code: ValidationCode.freeAgentAcquisitionInvalid,
          path: 'freeAgentAcquisitions',
          message: 'duplicate acquisition for ${acquisition.playerId.value}',
        ),
      ]);
    }
    return FreeAgentAcquisitionLedger(
      entries: [...entries.values, acquisition],
    );
  }

  void validate() {
    final issues = <ValidationIssue>[];
    final txIds = <String>{};
    final playerIds = <String>{};
    for (final entry in entries.values) {
      issues.addAll(entry.validationIssues());
      if (!txIds.add(entry.transactionId)) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.freeAgentAcquisitionInvalid,
            path: 'freeAgentAcquisitions',
            message: 'duplicate transaction id ${entry.transactionId}',
          ),
        );
      }
      if (!playerIds.add(entry.playerId.value)) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.freeAgentAcquisitionInvalid,
            path: 'freeAgentAcquisitions',
            message: 'multiple acquisitions for player ${entry.playerId.value}',
          ),
        );
      }
    }
    ValidationResult(issues).throwIfInvalid();
  }

  Map<String, Object?> toJson() => {
    'entries': [for (final entry in ordered) entry.toJson()],
  };
}
