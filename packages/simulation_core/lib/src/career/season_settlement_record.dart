import '../models/ids.dart';

/// Immutable evidence that one completed season's financial obligations were
/// settled across all 30 franchises, preventing double settlement.
final class SeasonSettlementRecord {
  SeasonSettlementRecord({
    required this.seasonYear,
    required List<TeamId> settledTeamIds,
    required this.totalRevenue,
    required this.totalExpenses,
  }) : settledTeamIds = List.unmodifiable(
         List<TeamId>.from(settledTeamIds)
           ..sort((a, b) => a.value.compareTo(b.value)),
       ) {
    validate();
  }

  factory SeasonSettlementRecord.fromJson(Map<String, dynamic> json) {
    final seasonYear = json['seasonYear'];
    final rawTeams = json['settledTeamIds'];
    final totalRevenue = json['totalRevenue'];
    final totalExpenses = json['totalExpenses'];
    if (seasonYear is! int ||
        rawTeams is! List ||
        totalRevenue is! int ||
        totalExpenses is! int) {
      throw const FormatException('Malformed SeasonSettlementRecord JSON');
    }
    final teamIds = <TeamId>[];
    for (final raw in rawTeams) {
      if (raw is! String || raw.trim().isEmpty) {
        throw const FormatException(
          'Malformed teamId in SeasonSettlementRecord',
        );
      }
      teamIds.add(TeamId(raw));
    }
    return SeasonSettlementRecord(
      seasonYear: seasonYear,
      settledTeamIds: teamIds,
      totalRevenue: totalRevenue,
      totalExpenses: totalExpenses,
    );
  }

  final int seasonYear;
  final List<TeamId> settledTeamIds;
  final int totalRevenue;
  final int totalExpenses;

  void validate() {
    if (seasonYear < 1) {
      throw FormatException(
        'SeasonSettlementRecord seasonYear must be >= 1, got $seasonYear',
      );
    }
    if (settledTeamIds.length != 30) {
      throw FormatException(
        'SeasonSettlementRecord requires 30 settled teams, got '
        '${settledTeamIds.length}',
      );
    }
    final seen = <String>{};
    for (final id in settledTeamIds) {
      if (id.value.trim().isEmpty || !seen.add(id.value)) {
        throw FormatException(
          'Invalid or duplicate teamId in SeasonSettlementRecord: ${id.value}',
        );
      }
    }
    if (totalRevenue < 0 || totalExpenses < 0) {
      throw const FormatException(
        'SeasonSettlementRecord revenue and expenses must be non-negative',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'seasonYear': seasonYear,
    'settledTeamIds': [for (final id in settledTeamIds) id.value],
    'totalRevenue': totalRevenue,
    'totalExpenses': totalExpenses,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SeasonSettlementRecord) return false;
    if (seasonYear != other.seasonYear ||
        totalRevenue != other.totalRevenue ||
        totalExpenses != other.totalExpenses ||
        settledTeamIds.length != other.settledTeamIds.length) {
      return false;
    }
    for (var i = 0; i < settledTeamIds.length; i++) {
      if (settledTeamIds[i] != other.settledTeamIds[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    seasonYear,
    Object.hashAll(settledTeamIds),
    totalRevenue,
    totalExpenses,
  );
}
