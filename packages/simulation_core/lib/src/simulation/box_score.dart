/// Immutable box-score values derived only from a validated event ledger.
final class PlayerBoxScore {
  const PlayerBoxScore({
    required this.playerId,
    required this.teamId,
    required this.points,
    required this.fgm,
    required this.fga,
    required this.twoPm,
    required this.twoPa,
    required this.threePm,
    required this.threePa,
    required this.ftm,
    required this.fta,
    required this.assists,
    required this.oreb,
    required this.dreb,
    required this.rebounds,
    required this.turnovers,
    required this.steals,
    required this.blocks,
    required this.personalFouls,
  });

  final String playerId;
  final String teamId;
  final int points;
  final int fgm;
  final int fga;
  final int twoPm;
  final int twoPa;
  final int threePm;
  final int threePa;
  final int ftm;
  final int fta;
  final int assists;
  final int oreb;
  final int dreb;
  final int rebounds;
  final int turnovers;
  final int steals;
  final int blocks;
  final int personalFouls;
}

final class TeamBoxScore {
  const TeamBoxScore({
    required this.teamId,
    required this.points,
    required this.fgm,
    required this.fga,
    required this.twoPm,
    required this.twoPa,
    required this.threePm,
    required this.threePa,
    required this.ftm,
    required this.fta,
    required this.assists,
    required this.oreb,
    required this.dreb,
    required this.rebounds,
    required this.turnovers,
    required this.steals,
    required this.blocks,
    required this.personalFouls,
  });

  final String teamId;
  final int points;
  final int fgm;
  final int fga;
  final int twoPm;
  final int twoPa;
  final int threePm;
  final int threePa;
  final int ftm;
  final int fta;
  final int assists;
  final int oreb;
  final int dreb;
  final int rebounds;
  final int turnovers;
  final int steals;
  final int blocks;
  final int personalFouls;
}

final class GameBoxScore {
  GameBoxScore({
    required Map<String, PlayerBoxScore> players,
    required Map<String, TeamBoxScore> teams,
    required Map<String, Map<int, int>> periodPoints,
  }) : players = Map<String, PlayerBoxScore>.unmodifiable(players),
       teams = Map<String, TeamBoxScore>.unmodifiable(teams),
       periodPoints = Map<String, Map<int, int>>.unmodifiable({
         for (final entry in periodPoints.entries)
           entry.key: Map<int, int>.unmodifiable(entry.value),
       });

  final Map<String, PlayerBoxScore> players;
  final Map<String, TeamBoxScore> teams;

  /// teamId -> period -> points.
  final Map<String, Map<int, int>> periodPoints;
}
