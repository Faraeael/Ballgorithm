import '../models/ids.dart';
import '../simulation/game_result.dart';

final class SeasonPlayerGameLine {
  const SeasonPlayerGameLine({
    required this.playerId,
    required this.teamId,
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
    required this.secondsPlayed,
  });

  factory SeasonPlayerGameLine.fromJson(Map<String, dynamic> json) =>
      SeasonPlayerGameLine(
        playerId: json['playerId'] as String,
        teamId: json['teamId'] as String,
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
        secondsPlayed: json['secondsPlayed'] as int,
      );

  final String playerId;
  final String teamId;
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
  final int secondsPlayed;

  Map<String, dynamic> toJson() => {
    'playerId': playerId,
    'teamId': teamId,
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
    'secondsPlayed': secondsPlayed,
  };
}

final class SeasonGameSummary {
  SeasonGameSummary({
    required this.homeScore,
    required this.awayScore,
    required this.winnerTeamId,
    required Map<String, int> periodScoresHome,
    required Map<String, int> periodScoresAway,
    required Map<String, SeasonPlayerGameLine> playerLines,
  }) : periodScoresHome = Map.unmodifiable(periodScoresHome),
       periodScoresAway = Map.unmodifiable(periodScoresAway),
       playerLines = Map.unmodifiable(playerLines);

  factory SeasonGameSummary.fromResult(GameResult result) {
    final homeId = result.homeTeamId.value;
    final awayId = result.awayTeamId.value;
    final lines = <String, SeasonPlayerGameLine>{};

    for (final entry in result.boxScore.players.entries) {
      final p = entry.value;
      lines[entry.key] = SeasonPlayerGameLine(
        playerId: p.playerId,
        teamId: p.teamId,
        points: p.points,
        fgm: p.fgm,
        fga: p.fga,
        threePm: p.threePm,
        threePa: p.threePa,
        ftm: p.ftm,
        fta: p.fta,
        oreb: p.oreb,
        dreb: p.dreb,
        rebounds: p.rebounds,
        assists: p.assists,
        steals: p.steals,
        blocks: p.blocks,
        turnovers: p.turnovers,
        personalFouls: p.personalFouls,
        secondsPlayed: p.secondsPlayed,
      );
    }

    final pHome = <String, int>{};
    final pAway = <String, int>{};
    for (var i = 1; i <= result.periodsPlayed; i++) {
      final label = i <= 4 ? 'Q$i' : 'OT${i - 4}';
      pHome[label] = result.boxScore.periodPoints[homeId]?[i] ?? 0;
      pAway[label] = result.boxScore.periodPoints[awayId]?[i] ?? 0;
    }

    return SeasonGameSummary(
      homeScore: result.homeScore,
      awayScore: result.awayScore,
      winnerTeamId: result.winnerTeamId,
      periodScoresHome: pHome,
      periodScoresAway: pAway,
      playerLines: lines,
    );
  }

  factory SeasonGameSummary.fromJson(Map<String, dynamic> json) =>
      SeasonGameSummary(
        homeScore: json['homeScore'] as int,
        awayScore: json['awayScore'] as int,
        winnerTeamId: TeamId(json['winnerTeamId'] as String),
        periodScoresHome: (json['periodScoresHome'] as Map).cast<String, int>(),
        periodScoresAway: (json['periodScoresAway'] as Map).cast<String, int>(),
        playerLines: (json['playerLines'] as Map).map(
          (k, v) => MapEntry(
            k as String,
            SeasonPlayerGameLine.fromJson(v as Map<String, dynamic>),
          ),
        ),
      );

  final int homeScore;
  final int awayScore;
  final TeamId winnerTeamId;
  final Map<String, int> periodScoresHome;
  final Map<String, int> periodScoresAway;
  final Map<String, SeasonPlayerGameLine> playerLines;

  Map<String, dynamic> toJson() => {
    'homeScore': homeScore,
    'awayScore': awayScore,
    'winnerTeamId': winnerTeamId.value,
    'periodScoresHome': periodScoresHome,
    'periodScoresAway': periodScoresAway,
    'playerLines': playerLines.map((k, v) => MapEntry(k, v.toJson())),
  };
}

final class SeasonFixture {
  const SeasonFixture({
    required this.roundNumber,
    required this.fixtureIndex,
    required this.id,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.seed,
    this.summary,
  });

  factory SeasonFixture.fromJson(Map<String, dynamic> json) => SeasonFixture(
    roundNumber: json['roundNumber'] as int,
    fixtureIndex: json['fixtureIndex'] as int,
    id: json['id'] as String,
    homeTeamId: TeamId(json['homeTeamId'] as String),
    awayTeamId: TeamId(json['awayTeamId'] as String),
    seed: json['seed'] as int,
    summary: json['summary'] == null
        ? null
        : SeasonGameSummary.fromJson(json['summary'] as Map<String, dynamic>),
  );

  final int roundNumber;
  final int fixtureIndex;
  final String id;
  final TeamId homeTeamId;
  final TeamId awayTeamId;
  final int seed;
  final SeasonGameSummary? summary;

  bool get isCompleted => summary != null;

  SeasonFixture copyWithSummary(SeasonGameSummary newSummary) => SeasonFixture(
    roundNumber: roundNumber,
    fixtureIndex: fixtureIndex,
    id: id,
    homeTeamId: homeTeamId,
    awayTeamId: awayTeamId,
    seed: seed,
    summary: newSummary,
  );

  Map<String, dynamic> toJson() => {
    'roundNumber': roundNumber,
    'fixtureIndex': fixtureIndex,
    'id': id,
    'homeTeamId': homeTeamId.value,
    'awayTeamId': awayTeamId.value,
    'seed': seed,
    'summary': summary?.toJson(),
  };
}
