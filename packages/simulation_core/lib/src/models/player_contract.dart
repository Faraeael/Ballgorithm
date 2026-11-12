import '../validation/validation_result.dart';
import 'ids.dart';
import 'roster_category.dart';

/// Why a [PlayerContract] exists.
enum ContractSource {
  legacy('legacy'),
  rookie('rookie'),
  freeAgent('freeAgent'),
  extension('extension'),
  trade('trade');

  const ContractSource(this.jsonValue);

  final String jsonValue;

  static ContractSource fromJson(String value) => values.firstWhere(
    (source) => source.jsonValue == value || source.name == value,
    orElse: () => throw ArgumentError.value(
      value,
      'source',
      'Unknown contract source: $value',
    ),
  );
}

/// The single employment authority for one rostered player.
///
/// Salary money lives only in the matching `ContractFinancials` record. Renewals
/// create a new contract; existing records are immutable.
final class PlayerContract {
  PlayerContract({
    required this.id,
    required this.playerId,
    required this.teamId,
    required this.category,
    required this.startYear,
    required this.durationYears,
    required this.source,
    this.rookieContractId,
  }) {
    requireValid();
  }

  factory PlayerContract.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final playerId = json['playerId'];
    final teamId = json['teamId'];
    final category = json['category'];
    final startYear = json['startYear'];
    final durationYears = json['durationYears'];
    final source = json['source'];
    final rookieContractId = json['rookieContractId'];
    if (id is! String ||
        playerId is! String ||
        teamId is! String ||
        category is! String ||
        startYear is! int ||
        durationYears is! int ||
        source is! String ||
        (rookieContractId != null && rookieContractId is! String)) {
      throw const FormatException('Malformed PlayerContract JSON');
    }
    return PlayerContract(
      id: id,
      playerId: PlayerId(playerId),
      teamId: TeamId(teamId),
      category: RosterCategory.fromJson(category),
      startYear: startYear,
      durationYears: durationYears,
      source: ContractSource.fromJson(source),
      rookieContractId: rookieContractId as String?,
    )..requireValid();
  }

  static const int minDurationYears = 1;
  static const int maxDurationYears = 4;

  static String idFor(PlayerId playerId, int startYear) =>
      'contract-${playerId.value}-$startYear';

  final String id;
  final PlayerId playerId;
  final TeamId teamId;
  final RosterCategory category;
  final int startYear;
  final int durationYears;
  final ContractSource source;

  /// Set only when `source == rookie`; links to the historical
  /// `RookieContract.id` that recorded the draft signing.
  final String? rookieContractId;

  bool isActiveIn(int year) =>
      year >= startYear && year < startYear + durationYears;

  List<ValidationIssue> validationIssues() {
    final issues = <ValidationIssue>[];
    if (id.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.contractInvalid,
          path: 'contract.id',
          message: 'contract id must not be empty',
        ),
      );
    }
    if (playerId.value.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.contractInvalid,
          path: 'contract.playerId',
          message: 'contract player id must not be empty',
        ),
      );
    }
    if (teamId.value.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.contractInvalid,
          path: 'contract.teamId',
          message: 'contract team id must not be empty',
        ),
      );
    }
    if (startYear < 1) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.contractInvalid,
          path: 'contract.startYear',
          message: 'contract startYear must be >= 1, got $startYear',
        ),
      );
    }
    if (durationYears < minDurationYears || durationYears > maxDurationYears) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.contractInvalid,
          path: 'contract.durationYears',
          message:
              'contract duration must be '
              '$minDurationYears..$maxDurationYears, got $durationYears',
        ),
      );
    }
    if (source == ContractSource.rookie) {
      if (rookieContractId == null || rookieContractId!.trim().isEmpty) {
        issues.add(
          const ValidationIssue(
            code: ValidationCode.rookieLinkMismatch,
            path: 'contract.rookieContractId',
            message: 'rookie contract requires a rookieContractId link',
          ),
        );
      }
    } else if (rookieContractId != null) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.rookieLinkMismatch,
          path: 'contract.rookieContractId',
          message: 'only rookie contracts may link a RookieContract',
        ),
      );
    }
    return issues;
  }

  void requireValid() {
    ValidationResult(validationIssues()).throwIfInvalid();
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'playerId': playerId.value,
    'teamId': teamId.value,
    'category': category.jsonValue,
    'startYear': startYear,
    'durationYears': durationYears,
    'source': source.jsonValue,
    if (rookieContractId != null) 'rookieContractId': rookieContractId,
  };
}
