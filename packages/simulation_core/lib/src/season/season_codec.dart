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

    if (existingLeague != null && existingLeague.config.seed != leagueSeed) {
      throw FormatException(
        'League seed mismatch: expected $leagueSeed but got ${existingLeague.config.seed}',
      );
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
    if (currentRoundNumber < 1 || currentRoundNumber > 15) {
      throw FormatException(
        'Invalid currentRoundNumber: $currentRoundNumber (expected 1..15)',
      );
    }

    final strategy = FranchiseStrategy.fromJson(
      raw['userStrategy'] as Map<String, dynamic>,
      userTeam,
    );
    final schedule = SeasonSchedule.fromJson(
      raw['schedule'] as Map<String, dynamic>,
    );

    if (schedule.rounds.length != 14) {
      throw FormatException(
        'Invalid schedule: expected exactly 14 rounds, found ${schedule.rounds.length}',
      );
    }

    final fixtureIds = <String>{};
    for (final r in schedule.rounds) {
      if (r.fixtures.length != 4) {
        throw FormatException(
          'Round ${r.roundNumber} must contain exactly 4 fixtures (found ${r.fixtures.length})',
        );
      }
      for (final f in r.fixtures) {
        if (!fixtureIds.add(f.id)) {
          throw FormatException('Duplicate fixture ID in schedule: ${f.id}');
        }
        if (r.roundNumber < currentRoundNumber) {
          if (!f.isCompleted) {
            throw FormatException(
              'Past round ${r.roundNumber} contains incomplete fixture ${f.id}',
            );
          }
        } else {
          if (f.isCompleted) {
            throw FormatException(
              'Active or future round ${r.roundNumber} contains premature completed fixture ${f.id}',
            );
          }
        }
      }
    }
    if (fixtureIds.length != 56) {
      throw FormatException(
        'Invalid schedule: expected 56 distinct fixtures, found ${fixtureIds.length}',
      );
    }

    final standings = LeagueStandings.fromJson(
      raw['standings'] as Map<String, dynamic>,
    );

    // Validate standings consistency with archived fixtures
    var expectedStandings = LeagueStandings.initial(league);
    for (final r in schedule.rounds) {
      if (r.roundNumber >= currentRoundNumber) break;
      for (final f in r.fixtures) {
        final sum = f.summary!;
        expectedStandings = expectedStandings.applyGame(
          homeId: f.homeTeamId,
          awayId: f.awayTeamId,
          homeScore: sum.homeScore,
          awayScore: sum.awayScore,
        );
      }
    }

    for (final team in league.teams) {
      final actual = standings.table[team.id.value];
      final expected = expectedStandings.table[team.id.value]!;
      if (actual == null) {
        throw FormatException(
          'Missing standings entry for team ${team.id.value}',
        );
      }
      if (actual.wins != expected.wins ||
          actual.losses != expected.losses ||
          actual.pointsFor != expected.pointsFor ||
          actual.pointsAgainst != expected.pointsAgainst ||
          actual.streak != expected.streak ||
          actual.streakCount != expected.streakCount) {
        throw FormatException(
          'Standings for team ${team.id.value} do not match archived fixture results',
        );
      }
    }

    final rawStats = raw['playerStats'] as Map<String, dynamic>;
    final playerStats = rawStats.map(
      (k, v) =>
          MapEntry(k, SeasonPlayerTotals.fromJson(v as Map<String, dynamic>)),
    );

    // Validate player statistics reconciliation
    final expectedTotals = <String, SeasonPlayerTotals>{
      for (final t in league.teams)
        for (final p in t.players)
          p.id.value: SeasonPlayerTotals.initial(
            playerId: p.id.value,
            teamId: t.id.value,
          ),
    };
    for (final r in schedule.rounds) {
      if (r.roundNumber >= currentRoundNumber) break;
      for (final f in r.fixtures) {
        for (final entry in f.summary!.playerLines.entries) {
          final pId = entry.key;
          final line = entry.value;
          final currentTot = expectedTotals[pId];
          if (currentTot != null) {
            expectedTotals[pId] = currentTot.applyGame(line);
          }
        }
      }
    }

    for (final t in league.teams) {
      for (final p in t.players) {
        final actual = playerStats[p.id.value];
        final expected = expectedTotals[p.id.value]!;
        if (actual == null) {
          throw FormatException(
            'Missing player stats for player ${p.id.value}',
          );
        }
        if (actual.points != expected.points ||
            actual.fgm != expected.fgm ||
            actual.fga != expected.fga ||
            actual.rebounds != expected.rebounds ||
            actual.assists != expected.assists ||
            actual.steals != expected.steals ||
            actual.blocks != expected.blocks ||
            actual.turnovers != expected.turnovers ||
            actual.gamesPlayed != expected.gamesPlayed ||
            actual.secondsPlayed != expected.secondsPlayed) {
          throw FormatException(
            'Player stats for ${p.id.value} do not match archived game box scores',
          );
        }
      }
    }

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
