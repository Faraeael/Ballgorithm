import '../models/ids.dart';
import '../models/league.dart';

final class SeasonStanding {
  const SeasonStanding({
    required this.teamId,
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    required this.pointsFor,
    required this.pointsAgainst,
    required this.streak,
    required this.streakCount,
  });

  factory SeasonStanding.initial(TeamId teamId) => SeasonStanding(
    teamId: teamId,
    gamesPlayed: 0,
    wins: 0,
    losses: 0,
    pointsFor: 0,
    pointsAgainst: 0,
    streak: '-',
    streakCount: 0,
  );

  factory SeasonStanding.fromJson(Map<String, dynamic> json) => SeasonStanding(
    teamId: TeamId(json['teamId'] as String),
    gamesPlayed: json['gamesPlayed'] as int,
    wins: json['wins'] as int,
    losses: json['losses'] as int,
    pointsFor: json['pointsFor'] as int,
    pointsAgainst: json['pointsAgainst'] as int,
    streak: json['streak'] as String,
    streakCount: json['streakCount'] as int,
  );

  final TeamId teamId;
  final int gamesPlayed;
  final int wins;
  final int losses;
  final int pointsFor;
  final int pointsAgainst;
  final String streak;
  final int streakCount;

  int get pointDifferential => pointsFor - pointsAgainst;

  double get winPercentage => gamesPlayed == 0 ? 0.0 : wins / gamesPlayed;

  SeasonStanding recordGame({
    required int scored,
    required int allowed,
    required bool won,
  }) {
    final nextGp = gamesPlayed + 1;
    final nextWins = won ? wins + 1 : wins;
    final nextLosses = won ? losses : losses + 1;
    final nextPf = pointsFor + scored;
    final nextPa = pointsAgainst + allowed;

    final nextCount = won
        ? (streakCount > 0 ? streakCount + 1 : 1)
        : (streakCount < 0 ? streakCount - 1 : -1);

    final nextStreak = won ? 'W$nextCount' : 'L${-nextCount}';

    return SeasonStanding(
      teamId: teamId,
      gamesPlayed: nextGp,
      wins: nextWins,
      losses: nextLosses,
      pointsFor: nextPf,
      pointsAgainst: nextPa,
      streak: nextStreak,
      streakCount: nextCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'teamId': teamId.value,
    'gamesPlayed': gamesPlayed,
    'wins': wins,
    'losses': losses,
    'pointsFor': pointsFor,
    'pointsAgainst': pointsAgainst,
    'streak': streak,
    'streakCount': streakCount,
  };
}

final class LeagueStandings {
  LeagueStandings({required Map<String, SeasonStanding> table})
    : table = Map.unmodifiable(table);

  factory LeagueStandings.initial(League league) {
    return LeagueStandings(
      table: {
        for (final team in league.teams)
          team.id.value: SeasonStanding.initial(team.id),
      },
    );
  }

  factory LeagueStandings.fromJson(Map<String, dynamic> json) =>
      LeagueStandings(
        table: (json['table'] as Map).map(
          (k, v) => MapEntry(
            k as String,
            SeasonStanding.fromJson(v as Map<String, dynamic>),
          ),
        ),
      );

  final Map<String, SeasonStanding> table;

  /// Deterministic ranking hierarchy:
  /// 1. Wins (descending)
  /// 2. Point differential (descending)
  /// 3. Points for (descending)
  /// 4. TeamId string value (ascending)
  List<SeasonStanding> get ranked {
    final list = table.values.toList();
    list.sort((a, b) {
      final byWins = b.wins.compareTo(a.wins);
      if (byWins != 0) return byWins;

      final byDiff = b.pointDifferential.compareTo(a.pointDifferential);
      if (byDiff != 0) return byDiff;

      final byPf = b.pointsFor.compareTo(a.pointsFor);
      if (byPf != 0) return byPf;

      return a.teamId.value.compareTo(b.teamId.value);
    });
    return List.unmodifiable(list);
  }

  LeagueStandings applyGame({
    required TeamId homeId,
    required TeamId awayId,
    required int homeScore,
    required int awayScore,
  }) {
    final homeStanding = table[homeId.value]!;
    final awayStanding = table[awayId.value]!;

    final homeWon = homeScore > awayScore;
    final updatedHome = homeStanding.recordGame(
      scored: homeScore,
      allowed: awayScore,
      won: homeWon,
    );
    final updatedAway = awayStanding.recordGame(
      scored: awayScore,
      allowed: homeScore,
      won: !homeWon,
    );

    return LeagueStandings(
      table: {
        for (final entry in table.entries)
          if (entry.key == homeId.value)
            homeId.value: updatedHome
          else if (entry.key == awayId.value)
            awayId.value: updatedAway
          else
            entry.key: entry.value,
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'table': table.map((k, v) => MapEntry(k, v.toJson())),
  };
}
