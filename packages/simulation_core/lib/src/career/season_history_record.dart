import '../models/ids.dart';
import 'playoff_state.dart';

final _digestPattern = RegExp(r'^[0-9a-f]{64}$');

/// Final regular-season standing entry for one franchise in an archived year.
final class SeasonStandingSummary {
  SeasonStandingSummary({
    required this.rank,
    required this.teamId,
    required this.wins,
    required this.losses,
  }) {
    validate();
  }

  factory SeasonStandingSummary.fromJson(Map<String, dynamic> json) {
    final rank = json['rank'];
    final teamId = json['teamId'];
    final wins = json['wins'];
    final losses = json['losses'];
    if (rank is! int || teamId is! String || wins is! int || losses is! int) {
      throw const FormatException('Malformed SeasonStandingSummary JSON');
    }
    return SeasonStandingSummary(
      rank: rank,
      teamId: TeamId(teamId),
      wins: wins,
      losses: losses,
    );
  }

  final int rank;
  final TeamId teamId;
  final int wins;
  final int losses;

  void validate() {
    if (rank < 1 ||
        rank > 30 ||
        teamId.value.trim().isEmpty ||
        wins < 0 ||
        losses < 0 ||
        wins + losses != 82) {
      throw const FormatException('Invalid SeasonStandingSummary');
    }
  }

  Map<String, Object?> toJson() => {
    'rank': rank,
    'teamId': teamId.value,
    'wins': wins,
    'losses': losses,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeasonStandingSummary &&
          rank == other.rank &&
          teamId == other.teamId &&
          wins == other.wins &&
          losses == other.losses;

  @override
  int get hashCode => Object.hash(rank, teamId, wins, losses);
}

/// Authoritative Play-In outcome summary for an archived season.
final class PlayInOutcomeSummary {
  PlayInOutcomeSummary({
    required this.game1WinnerTeamId,
    required this.game2WinnerTeamId,
    required this.game3WinnerTeamId,
    required this.seed15TeamId,
    required this.seed16TeamId,
  }) {
    validate();
  }

  factory PlayInOutcomeSummary.fromJson(Map<String, dynamic> json) {
    final g1 = json['game1WinnerTeamId'];
    final g2 = json['game2WinnerTeamId'];
    final g3 = json['game3WinnerTeamId'];
    final s15 = json['seed15TeamId'];
    final s16 = json['seed16TeamId'];
    if (g1 is! String ||
        g2 is! String ||
        g3 is! String ||
        s15 is! String ||
        s16 is! String) {
      throw const FormatException('Malformed PlayInOutcomeSummary JSON');
    }
    return PlayInOutcomeSummary(
      game1WinnerTeamId: TeamId(g1),
      game2WinnerTeamId: TeamId(g2),
      game3WinnerTeamId: TeamId(g3),
      seed15TeamId: TeamId(s15),
      seed16TeamId: TeamId(s16),
    );
  }

  final TeamId game1WinnerTeamId;
  final TeamId game2WinnerTeamId;
  final TeamId game3WinnerTeamId;
  final TeamId seed15TeamId;
  final TeamId seed16TeamId;

  void validate() {
    if (game1WinnerTeamId.value.trim().isEmpty ||
        game2WinnerTeamId.value.trim().isEmpty ||
        game3WinnerTeamId.value.trim().isEmpty ||
        seed15TeamId != game1WinnerTeamId ||
        seed16TeamId != game3WinnerTeamId ||
        seed15TeamId == seed16TeamId) {
      throw const FormatException('Invalid PlayInOutcomeSummary');
    }
  }

  Map<String, Object?> toJson() => {
    'game1WinnerTeamId': game1WinnerTeamId.value,
    'game2WinnerTeamId': game2WinnerTeamId.value,
    'game3WinnerTeamId': game3WinnerTeamId.value,
    'seed15TeamId': seed15TeamId.value,
    'seed16TeamId': seed16TeamId.value,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayInOutcomeSummary &&
          game1WinnerTeamId == other.game1WinnerTeamId &&
          game2WinnerTeamId == other.game2WinnerTeamId &&
          game3WinnerTeamId == other.game3WinnerTeamId &&
          seed15TeamId == other.seed15TeamId &&
          seed16TeamId == other.seed16TeamId;

  @override
  int get hashCode => Object.hash(
    game1WinnerTeamId,
    game2WinnerTeamId,
    game3WinnerTeamId,
    seed15TeamId,
    seed16TeamId,
  );
}

/// Authoritative outcome of one completed best-of-seven playoff series.
final class PlayoffSeriesSummary {
  PlayoffSeriesSummary({
    required this.seriesIndex,
    required this.round,
    required this.firstTeamId,
    required this.secondTeamId,
    required this.winnerTeamId,
    required this.firstTeamWins,
    required this.secondTeamWins,
  }) {
    validate();
  }

  factory PlayoffSeriesSummary.fromJson(Map<String, dynamic> json) {
    final seriesIndex = json['seriesIndex'];
    final round = json['round'];
    final firstTeamId = json['firstTeamId'];
    final secondTeamId = json['secondTeamId'];
    final winnerTeamId = json['winnerTeamId'];
    final firstTeamWins = json['firstTeamWins'];
    final secondTeamWins = json['secondTeamWins'];
    if (seriesIndex is! int ||
        round is! String ||
        firstTeamId is! String ||
        secondTeamId is! String ||
        winnerTeamId is! String ||
        firstTeamWins is! int ||
        secondTeamWins is! int) {
      throw const FormatException('Malformed PlayoffSeriesSummary JSON');
    }
    return PlayoffSeriesSummary(
      seriesIndex: seriesIndex,
      round: PlayoffRound.values.firstWhere(
        (e) => e.name == round,
        orElse: () => throw FormatException('Unknown PlayoffRound: $round'),
      ),
      firstTeamId: TeamId(firstTeamId),
      secondTeamId: TeamId(secondTeamId),
      winnerTeamId: TeamId(winnerTeamId),
      firstTeamWins: firstTeamWins,
      secondTeamWins: secondTeamWins,
    );
  }

  final int seriesIndex;
  final PlayoffRound round;
  final TeamId firstTeamId;
  final TeamId secondTeamId;
  final TeamId winnerTeamId;
  final int firstTeamWins;
  final int secondTeamWins;

  void validate() {
    if (seriesIndex < 0 ||
        seriesIndex > 14 ||
        firstTeamId.value.trim().isEmpty ||
        secondTeamId.value.trim().isEmpty ||
        firstTeamId == secondTeamId ||
        firstTeamWins < 0 ||
        firstTeamWins > 4 ||
        secondTeamWins < 0 ||
        secondTeamWins > 4) {
      throw const FormatException('Invalid PlayoffSeriesSummary');
    }
    final expectedWinner = firstTeamWins == 4 && secondTeamWins < 4
        ? firstTeamId
        : secondTeamWins == 4 && firstTeamWins < 4
        ? secondTeamId
        : null;
    if (expectedWinner == null || winnerTeamId != expectedWinner) {
      throw const FormatException('Invalid PlayoffSeriesSummary winner');
    }
  }

  Map<String, Object?> toJson() => {
    'seriesIndex': seriesIndex,
    'round': round.name,
    'firstTeamId': firstTeamId.value,
    'secondTeamId': secondTeamId.value,
    'winnerTeamId': winnerTeamId.value,
    'firstTeamWins': firstTeamWins,
    'secondTeamWins': secondTeamWins,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayoffSeriesSummary &&
          seriesIndex == other.seriesIndex &&
          round == other.round &&
          firstTeamId == other.firstTeamId &&
          secondTeamId == other.secondTeamId &&
          winnerTeamId == other.winnerTeamId &&
          firstTeamWins == other.firstTeamWins &&
          secondTeamWins == other.secondTeamWins;

  @override
  int get hashCode => Object.hash(
    seriesIndex,
    round,
    firstTeamId,
    secondTeamId,
    winnerTeamId,
    firstTeamWins,
    secondTeamWins,
  );
}

/// Compact, immutable historical summary of one completed GM career season.
///
/// Full game-level ledgers and input evidence are stored in the external
/// per-season archive identified by [archiveId] and verified by [archiveDigest].
final class SeasonHistoryRecord {
  SeasonHistoryRecord({
    required this.seasonYear,
    required this.seasonId,
    required this.championTeamId,
    required List<SeasonStandingSummary> regularSeasonStandings,
    required this.playInOutcome,
    required List<PlayoffSeriesSummary> playoffSeries,
    required this.archiveId,
    required this.archiveDigest,
  }) : regularSeasonStandings = List.unmodifiable(regularSeasonStandings),
       playoffSeries = List.unmodifiable(playoffSeries) {
    validate();
  }

  factory SeasonHistoryRecord.fromJson(Map<String, dynamic> json) {
    final seasonYear = json['seasonYear'];
    final seasonId = json['seasonId'];
    final championTeamId = json['championTeamId'];
    final rawStandings = json['regularSeasonStandings'];
    final rawPlayIn = json['playInOutcome'];
    final rawSeries = json['playoffSeries'];
    final archiveId = json['archiveId'];
    final archiveDigest = json['archiveDigest'];
    if (seasonYear is! int ||
        seasonId is! String ||
        championTeamId is! String ||
        rawStandings is! List ||
        rawPlayIn is! Map<String, dynamic> ||
        rawSeries is! List ||
        archiveId is! String ||
        archiveDigest is! String) {
      throw const FormatException('Malformed SeasonHistoryRecord JSON');
    }
    return SeasonHistoryRecord(
      seasonYear: seasonYear,
      seasonId: seasonId,
      championTeamId: TeamId(championTeamId),
      regularSeasonStandings: [
        for (final item in rawStandings)
          if (item is Map<String, dynamic>)
            SeasonStandingSummary.fromJson(item)
          else
            throw const FormatException(
              'Malformed SeasonStandingSummary entry',
            ),
      ],
      playInOutcome: PlayInOutcomeSummary.fromJson(rawPlayIn),
      playoffSeries: [
        for (final item in rawSeries)
          if (item is Map<String, dynamic>)
            PlayoffSeriesSummary.fromJson(item)
          else
            throw const FormatException('Malformed PlayoffSeriesSummary entry'),
      ],
      archiveId: archiveId,
      archiveDigest: archiveDigest,
    );
  }

  final int seasonYear;
  final String seasonId;
  final TeamId championTeamId;
  final List<SeasonStandingSummary> regularSeasonStandings;
  final PlayInOutcomeSummary playInOutcome;
  final List<PlayoffSeriesSummary> playoffSeries;
  final String archiveId;
  final String archiveDigest;

  void validate({Set<String>? validTeamIds, String? expectedCareerId}) {
    if (seasonYear < 1 ||
        seasonId.trim().isEmpty ||
        championTeamId.value.trim().isEmpty ||
        archiveId.trim().isEmpty ||
        !_digestPattern.hasMatch(archiveDigest)) {
      throw const FormatException('Invalid SeasonHistoryRecord metadata');
    }
    if (expectedCareerId != null &&
        seasonId != '$expectedCareerId-season-$seasonYear') {
      throw const FormatException('SeasonHistoryRecord seasonId mismatch');
    }
    if (regularSeasonStandings.length != 30) {
      throw const FormatException(
        'SeasonHistoryRecord requires 30 regular-season standings',
      );
    }
    final standingTeams = <String>{};
    for (var i = 0; i < regularSeasonStandings.length; i++) {
      final entry = regularSeasonStandings[i];
      entry.validate();
      if (entry.rank != i + 1 || !standingTeams.add(entry.teamId.value)) {
        throw const FormatException('Invalid SeasonHistoryRecord standings');
      }
      if (validTeamIds != null && !validTeamIds.contains(entry.teamId.value)) {
        throw const FormatException(
          'SeasonHistoryRecord references unknown standing franchise',
        );
      }
    }
    playInOutcome.validate();
    if (validTeamIds != null &&
        (!validTeamIds.contains(playInOutcome.game1WinnerTeamId.value) ||
            !validTeamIds.contains(playInOutcome.game2WinnerTeamId.value) ||
            !validTeamIds.contains(playInOutcome.game3WinnerTeamId.value) ||
            !validTeamIds.contains(championTeamId.value))) {
      throw const FormatException(
        'SeasonHistoryRecord references unknown franchise',
      );
    }
    if (playoffSeries.length != 15) {
      throw const FormatException(
        'SeasonHistoryRecord requires 15 playoff series summaries',
      );
    }
    for (var i = 0; i < playoffSeries.length; i++) {
      final s = playoffSeries[i];
      s.validate();
      if (s.seriesIndex != i) {
        throw const FormatException('Playoff series summaries out of order');
      }
      if (validTeamIds != null &&
          (!validTeamIds.contains(s.firstTeamId.value) ||
              !validTeamIds.contains(s.secondTeamId.value))) {
        throw const FormatException(
          'SeasonHistoryRecord series references unknown franchise',
        );
      }
    }
    if (playoffSeries[14].winnerTeamId != championTeamId) {
      throw const FormatException(
        'SeasonHistoryRecord champion does not match Finals winner',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'seasonYear': seasonYear,
    'seasonId': seasonId,
    'championTeamId': championTeamId.value,
    'regularSeasonStandings': [
      for (final entry in regularSeasonStandings) entry.toJson(),
    ],
    'playInOutcome': playInOutcome.toJson(),
    'playoffSeries': [for (final s in playoffSeries) s.toJson()],
    'archiveId': archiveId,
    'archiveDigest': archiveDigest,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SeasonHistoryRecord) return false;
    if (seasonYear != other.seasonYear ||
        seasonId != other.seasonId ||
        championTeamId != other.championTeamId ||
        playInOutcome != other.playInOutcome ||
        archiveId != other.archiveId ||
        archiveDigest != other.archiveDigest ||
        regularSeasonStandings.length != other.regularSeasonStandings.length ||
        playoffSeries.length != other.playoffSeries.length) {
      return false;
    }
    for (var i = 0; i < regularSeasonStandings.length; i++) {
      if (regularSeasonStandings[i] != other.regularSeasonStandings[i]) {
        return false;
      }
    }
    for (var i = 0; i < playoffSeries.length; i++) {
      if (playoffSeries[i] != other.playoffSeries[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    seasonYear,
    seasonId,
    championTeamId,
    Object.hashAll(regularSeasonStandings),
    playInOutcome,
    Object.hashAll(playoffSeries),
    archiveId,
    archiveDigest,
  );
}
