import '../finance/financial_rules.dart';
import '../models/ids.dart';

/// Per-franchise financial settlement ledger entry for one completed season.
final class TeamSettlementEntry {
  TeamSettlementEntry({
    required this.teamId,
    required this.startingCash,
    required this.startingDebt,
    required this.revenue,
    required this.activePlayerSalaryExpense,
    required this.retiredGuaranteeExpense,
    required this.staffExpense,
    required this.facilityMaintenanceExpense,
    required this.endingCash,
    required this.endingDebt,
  }) {
    validate();
  }

  factory TeamSettlementEntry.fromJson(Map<String, dynamic> json) {
    final teamId = json['teamId'];
    final startingCash = json['startingCash'];
    final startingDebt = json['startingDebt'];
    final revenue = json['revenue'];
    final activePlayerSalaryExpense = json['activePlayerSalaryExpense'];
    final retiredGuaranteeExpense = json['retiredGuaranteeExpense'];
    final staffExpense = json['staffExpense'];
    final facilityMaintenanceExpense = json['facilityMaintenanceExpense'];
    final endingCash = json['endingCash'];
    final endingDebt = json['endingDebt'];
    if (teamId is! String ||
        startingCash is! int ||
        startingDebt is! int ||
        revenue is! int ||
        activePlayerSalaryExpense is! int ||
        retiredGuaranteeExpense is! int ||
        staffExpense is! int ||
        facilityMaintenanceExpense is! int ||
        endingCash is! int ||
        endingDebt is! int) {
      throw const FormatException('Malformed TeamSettlementEntry JSON');
    }
    return TeamSettlementEntry(
      teamId: TeamId(teamId),
      startingCash: startingCash,
      startingDebt: startingDebt,
      revenue: revenue,
      activePlayerSalaryExpense: activePlayerSalaryExpense,
      retiredGuaranteeExpense: retiredGuaranteeExpense,
      staffExpense: staffExpense,
      facilityMaintenanceExpense: facilityMaintenanceExpense,
      endingCash: endingCash,
      endingDebt: endingDebt,
    );
  }

  final TeamId teamId;
  final int startingCash;
  final int startingDebt;
  final int revenue;
  final int activePlayerSalaryExpense;
  final int retiredGuaranteeExpense;
  final int staffExpense;
  final int facilityMaintenanceExpense;
  final int endingCash;
  final int endingDebt;

  int get totalExpenses =>
      activePlayerSalaryExpense +
      retiredGuaranteeExpense +
      staffExpense +
      facilityMaintenanceExpense;

  void validate() {
    if (teamId.value.trim().isEmpty) {
      throw const FormatException('TeamSettlementEntry requires teamId');
    }
    for (final v in [
      startingCash,
      startingDebt,
      revenue,
      activePlayerSalaryExpense,
      retiredGuaranteeExpense,
      staffExpense,
      facilityMaintenanceExpense,
      endingCash,
      endingDebt,
    ]) {
      if (v < 0 || v > FinancialRules.maximumBalance) {
        throw FormatException(
          'TeamSettlementEntry monetary value $v out of bounds '
          '0..${FinancialRules.maximumBalance}',
        );
      }
    }
    if (endingCash > 0 && endingDebt > 0) {
      throw const FormatException(
        'TeamSettlementEntry cannot hold both positive cash and positive debt',
      );
    }
    final lhs = startingCash - startingDebt + revenue - totalExpenses;
    final rhs = endingCash - endingDebt;
    if (lhs != rhs) {
      throw FormatException(
        'TeamSettlementEntry ${teamId.value} does not reconcile: '
        '$lhs != $rhs',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'teamId': teamId.value,
    'startingCash': startingCash,
    'startingDebt': startingDebt,
    'revenue': revenue,
    'activePlayerSalaryExpense': activePlayerSalaryExpense,
    'retiredGuaranteeExpense': retiredGuaranteeExpense,
    'staffExpense': staffExpense,
    'facilityMaintenanceExpense': facilityMaintenanceExpense,
    'endingCash': endingCash,
    'endingDebt': endingDebt,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TeamSettlementEntry &&
          teamId == other.teamId &&
          startingCash == other.startingCash &&
          startingDebt == other.startingDebt &&
          revenue == other.revenue &&
          activePlayerSalaryExpense == other.activePlayerSalaryExpense &&
          retiredGuaranteeExpense == other.retiredGuaranteeExpense &&
          staffExpense == other.staffExpense &&
          facilityMaintenanceExpense == other.facilityMaintenanceExpense &&
          endingCash == other.endingCash &&
          endingDebt == other.endingDebt;

  @override
  int get hashCode => Object.hash(
    teamId,
    startingCash,
    startingDebt,
    revenue,
    activePlayerSalaryExpense,
    retiredGuaranteeExpense,
    staffExpense,
    facilityMaintenanceExpense,
    endingCash,
    endingDebt,
  );
}

/// Immutable evidence that one completed season's financial obligations were
/// settled across all 30 franchises, preventing double settlement.
final class SeasonSettlementRecord {
  SeasonSettlementRecord({
    required this.seasonYear,
    required List<TeamId> settledTeamIds,
    required this.totalRevenue,
    required this.totalExpenses,
    List<TeamSettlementEntry> teamEntries = const [],
  }) : settledTeamIds = List.unmodifiable(
         List<TeamId>.from(settledTeamIds)
           ..sort((a, b) => a.value.compareTo(b.value)),
       ),
       teamEntries = List.unmodifiable(
         List<TeamSettlementEntry>.from(teamEntries)
           ..sort((a, b) => a.teamId.value.compareTo(b.teamId.value)),
       ) {
    validate();
  }

  factory SeasonSettlementRecord.fromJson(Map<String, dynamic> json) {
    final seasonYear = json['seasonYear'];
    final rawTeams = json['settledTeamIds'];
    final totalRevenue = json['totalRevenue'];
    final totalExpenses = json['totalExpenses'];
    final rawEntries = json['teamEntries'];
    if (seasonYear is! int ||
        rawTeams is! List ||
        totalRevenue is! int ||
        totalExpenses is! int ||
        (rawEntries != null && rawEntries is! List)) {
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
    final teamEntries = <TeamSettlementEntry>[];
    if (rawEntries is List) {
      for (final raw in rawEntries) {
        if (raw is! Map<String, dynamic>) {
          throw const FormatException(
            'Malformed TeamSettlementEntry in SeasonSettlementRecord',
          );
        }
        teamEntries.add(TeamSettlementEntry.fromJson(raw));
      }
    }
    return SeasonSettlementRecord(
      seasonYear: seasonYear,
      settledTeamIds: teamIds,
      totalRevenue: totalRevenue,
      totalExpenses: totalExpenses,
      teamEntries: teamEntries,
    );
  }

  final int seasonYear;
  final List<TeamId> settledTeamIds;
  final int totalRevenue;
  final int totalExpenses;
  final List<TeamSettlementEntry> teamEntries;

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
    if (teamEntries.isNotEmpty) {
      if (teamEntries.length != 30) {
        throw FormatException(
          'SeasonSettlementRecord teamEntries must contain 30 entries, got '
          '${teamEntries.length}',
        );
      }
      var revSum = 0;
      var expSum = 0;
      final entryTeamIds = <String>{};
      for (final entry in teamEntries) {
        entry.validate();
        if (!entryTeamIds.add(entry.teamId.value) ||
            !seen.contains(entry.teamId.value)) {
          throw FormatException(
            'Invalid or duplicate teamEntries teamId: ${entry.teamId.value}',
          );
        }
        revSum += entry.revenue;
        expSum += entry.totalExpenses;
      }
      if (revSum != totalRevenue || expSum != totalExpenses) {
        throw const FormatException(
          'SeasonSettlementRecord teamEntries totals do not match aggregates',
        );
      }
    }
  }

  Map<String, Object?> toJson() => {
    'seasonYear': seasonYear,
    'settledTeamIds': [for (final id in settledTeamIds) id.value],
    'totalRevenue': totalRevenue,
    'totalExpenses': totalExpenses,
    if (teamEntries.isNotEmpty)
      'teamEntries': [for (final entry in teamEntries) entry.toJson()],
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SeasonSettlementRecord) return false;
    if (seasonYear != other.seasonYear ||
        totalRevenue != other.totalRevenue ||
        totalExpenses != other.totalExpenses ||
        settledTeamIds.length != other.settledTeamIds.length ||
        teamEntries.length != other.teamEntries.length) {
      return false;
    }
    for (var i = 0; i < settledTeamIds.length; i++) {
      if (settledTeamIds[i] != other.settledTeamIds[i]) {
        return false;
      }
    }
    for (var i = 0; i < teamEntries.length; i++) {
      if (teamEntries[i] != other.teamEntries[i]) {
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
    Object.hashAll(teamEntries),
  );
}
