import 'dart:convert';

import '../generation/league_generator.dart';
import '../models/generation_config.dart';
import '../models/ids.dart';
import '../models/league.dart';
import 'franchise_strategy.dart';
import 'season_player_totals.dart';
import 'season_schedule.dart';
import 'season_standing.dart';
import 'season_state.dart';

final class SeasonCodec {
  const SeasonCodec._();

  static const int currentSchemaVersion = 1;

  static String encode(SeasonState state) {
    final map = {
      'schemaVersion': state.schemaVersion,
      'id': state.id,
      'leagueSeed': state.leagueSeed,
      'userFranchiseId': state.userFranchiseId.value,
      'currentRoundNumber': state.currentRoundNumber,
      'userStrategy': state.userStrategy.toJson(),
      'schedule': state.schedule.toJson(),
      'standings': state.standings.toJson(),
      'playerStats': state.playerStats.map((k, v) => MapEntry(k, v.toJson())),
    };
    return jsonEncode(map);
  }

  static SeasonState decode(String jsonString, {League? existingLeague}) {
    final dynamic raw;
    try {
      raw = jsonDecode(jsonString);
    } catch (e) {
      throw FormatException('Failed to parse season JSON: $e');
    }

    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid season JSON format: expected Map');
    }

    final schemaVersion = raw['schemaVersion'];
    if (schemaVersion is! int || schemaVersion != currentSchemaVersion) {
      throw FormatException(
        'Unsupported season schema version: $schemaVersion (supported: $currentSchemaVersion)',
      );
    }

    final leagueSeed = raw['leagueSeed'] as int?;
    if (leagueSeed == null) {
      throw const FormatException('Missing leagueSeed in season JSON');
    }

    final league =
        existingLeague ??
        const LeagueGenerator().generate(GenerationConfig(seed: leagueSeed));

    final userFranchiseId = TeamId(raw['userFranchiseId'] as String);
    final userTeam = league.teams.firstWhere(
      (t) => t.id == userFranchiseId,
      orElse: () => throw FormatException(
        'User team ${userFranchiseId.value} not found in league',
      ),
    );

    final currentRoundNumber = raw['currentRoundNumber'] as int;
    final strategy = FranchiseStrategy.fromJson(
      raw['userStrategy'] as Map<String, dynamic>,
      userTeam,
    );
    final schedule = SeasonSchedule.fromJson(
      raw['schedule'] as Map<String, dynamic>,
    );
    final standings = LeagueStandings.fromJson(
      raw['standings'] as Map<String, dynamic>,
    );

    final rawStats = raw['playerStats'] as Map<String, dynamic>;
    final playerStats = rawStats.map(
      (k, v) =>
          MapEntry(k, SeasonPlayerTotals.fromJson(v as Map<String, dynamic>)),
    );

    return SeasonState(
      schemaVersion: schemaVersion,
      id: raw['id'] as String,
      leagueSeed: leagueSeed,
      league: league,
      userFranchiseId: userFranchiseId,
      userStrategy: strategy,
      schedule: schedule,
      currentRoundNumber: currentRoundNumber,
      standings: standings,
      playerStats: playerStats,
    );
  }
}
