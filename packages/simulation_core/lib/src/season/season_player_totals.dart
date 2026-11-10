import 'season_fixture.dart';

final class SeasonPlayerTotals {
  const SeasonPlayerTotals({
    required this.playerId,
    required this.teamId,
    required this.gamesPlayed,
    required this.secondsPlayed,
    required this.points,
    required this.fgm,
    required this.fga,
    required this.threePm,
    required this.threePa,
    required this.ftm,
    required this.fta,
    required this.oreb,
    required this.dreb,
    required this.rebounds,
    required this.assists,
    required this.steals,
    required this.blocks,
    required this.turnovers,
    required this.personalFouls,
  });

  factory SeasonPlayerTotals.initial({
    required String playerId,
    required String teamId,
  }) => SeasonPlayerTotals(
    playerId: playerId,
    teamId: teamId,
    gamesPlayed: 0,
    secondsPlayed: 0,
    points: 0,
    fgm: 0,
    fga: 0,
    threePm: 0,
    threePa: 0,
    ftm: 0,
    fta: 0,
    oreb: 0,
    dreb: 0,
    rebounds: 0,
    assists: 0,
    steals: 0,
    blocks: 0,
    turnovers: 0,
    personalFouls: 0,
  );

  factory SeasonPlayerTotals.fromJson(Map<String, dynamic> json) =>
      SeasonPlayerTotals(
        playerId: json['playerId'] as String,
        teamId: json['teamId'] as String,
        gamesPlayed: json['gamesPlayed'] as int,
        secondsPlayed: json['secondsPlayed'] as int,
        points: json['points'] as int,
        fgm: json['fgm'] as int,
        fga: json['fga'] as int,
        threePm: json['threePm'] as int,
        threePa: json['threePa'] as int,
        ftm: json['ftm'] as int,
        fta: json['fta'] as int,
        oreb: json['oreb'] as int,
        dreb: json['dreb'] as int,
        rebounds: json['rebounds'] as int,
        assists: json['assists'] as int,
        steals: json['steals'] as int,
        blocks: json['blocks'] as int,
        turnovers: json['turnovers'] as int,
        personalFouls: json['personalFouls'] as int,
      );

  final String playerId;
  final String teamId;
  final int gamesPlayed;
  final int secondsPlayed;
  final int points;
  final int fgm;
  final int fga;
  final int threePm;
  final int threePa;
  final int ftm;
  final int fta;
  final int oreb;
  final int dreb;
  final int rebounds;
  final int assists;
  final int steals;
  final int blocks;
  final int turnovers;
  final int personalFouls;

  // Zero-denominator safe rates
  double? get fieldGoalPercentage => fga == 0 ? null : fgm / fga;
  double? get threePointPercentage => threePa == 0 ? null : threePm / threePa;
  double? get freeThrowPercentage => fta == 0 ? null : ftm / fta;

  // Per-game averages
  double get minutesPerGame =>
      gamesPlayed == 0 ? 0.0 : (secondsPlayed / 60) / gamesPlayed;
  double get pointsPerGame => gamesPlayed == 0 ? 0.0 : points / gamesPlayed;
  double get reboundsPerGame => gamesPlayed == 0 ? 0.0 : rebounds / gamesPlayed;
  double get assistsPerGame => gamesPlayed == 0 ? 0.0 : assists / gamesPlayed;
  double get stealsPerGame => gamesPlayed == 0 ? 0.0 : steals / gamesPlayed;
  double get blocksPerGame => gamesPlayed == 0 ? 0.0 : blocks / gamesPlayed;
  double get turnoversPerGame =>
      gamesPlayed == 0 ? 0.0 : turnovers / gamesPlayed;

  SeasonPlayerTotals applyGame(SeasonPlayerGameLine line) {
    return SeasonPlayerTotals(
      playerId: playerId,
      teamId: teamId,
      gamesPlayed: gamesPlayed + 1,
      secondsPlayed: secondsPlayed + line.secondsPlayed,
      points: points + line.points,
      fgm: fgm + line.fgm,
      fga: fga + line.fga,
      threePm: threePm + line.threePm,
      threePa: threePa + line.threePa,
      ftm: ftm + line.ftm,
      fta: fta + line.fta,
      oreb: oreb + line.oreb,
      dreb: dreb + line.dreb,
      rebounds: rebounds + line.rebounds,
      assists: assists + line.assists,
      steals: steals + line.steals,
      blocks: blocks + line.blocks,
      turnovers: turnovers + line.turnovers,
      personalFouls: personalFouls + line.personalFouls,
    );
  }

  Map<String, dynamic> toJson() => {
    'playerId': playerId,
    'teamId': teamId,
    'gamesPlayed': gamesPlayed,
    'secondsPlayed': secondsPlayed,
    'points': points,
    'fgm': fgm,
    'fga': fga,
    'threePm': threePm,
    'threePa': threePa,
    'ftm': ftm,
    'fta': fta,
    'oreb': oreb,
    'dreb': dreb,
    'rebounds': rebounds,
    'assists': assists,
    'steals': steals,
    'blocks': blocks,
    'turnovers': turnovers,
    'personalFouls': personalFouls,
  };
}
