import '../models/ids.dart';
import '../models/league.dart';
import '../models/roster_category.dart';
import '../season/season_seed.dart';
import 'play_in_state.dart';
import 'regular_season_game_input_evidence.dart';
import 'regular_season_game_result.dart';
import 'regular_season_state.dart';

const _playoffSeriesCount = 15;
const _playoffGamesPerSeries = 7;
const _playoffGameFirstRematchIndex = 86;
const _playoffGameLastRematchIndex = 190;

const _firstRoundSeeds = <(int, int)>[
  (1, 16),
  (8, 9),
  (4, 13),
  (5, 12),
  (3, 14),
  (6, 11),
  (2, 15),
  (7, 10),
];

const _seriesDependencies = <(int, int)>[
  (0, 1),
  (2, 3),
  (4, 5),
  (6, 7),
  (8, 9),
  (10, 11),
  (12, 13),
];

const _earlyHomeGames = {1, 2, 5, 7};

String _seriesId(String seasonId, int seriesIndex) =>
    '$seasonId-playoff-s${seriesIndex + 1}';

String _gameId(String seasonId, int seriesIndex, int gameNumber) =>
    '${_seriesId(seasonId, seriesIndex)}-g$gameNumber';

int _rematchIndex(int seriesIndex, int gameNumber) =>
    _playoffGameFirstRematchIndex +
    (seriesIndex * _playoffGamesPerSeries) +
    (gameNumber - 1);

int _normalizedSeed(int seed) => seed == 0 ? 0x9E3779B9 : seed;

int _derivePlayoffSeed({
  required int scheduleSeed,
  required List<String> sortedTeamIds,
  required TeamId home,
  required TeamId away,
  required int rematchIndex,
}) {
  final homeIndex = sortedTeamIds.indexOf(home.value);
  final awayIndex = sortedTeamIds.indexOf(away.value);
  if (home == away ||
      homeIndex < 0 ||
      homeIndex >= 30 ||
      awayIndex < 0 ||
      awayIndex >= 30 ||
      rematchIndex < _playoffGameFirstRematchIndex ||
      rematchIndex > _playoffGameLastRematchIndex) {
    throw const FormatException('Invalid playoff game seed inputs');
  }
  return deriveGameSeed(
    leagueSeed: scheduleSeed,
    homeIndex: homeIndex,
    awayIndex: awayIndex,
    rematchIndex: rematchIndex,
  );
}

enum PlayoffRound {
  roundOf16('Round of 16'),
  quarterfinals('Quarterfinals'),
  semifinals('Semifinals'),
  finals('Finals');

  const PlayoffRound(this.displayName);
  final String displayName;
}

final class PlayoffTeamQualification {
  const PlayoffTeamQualification({
    required this.playoffSeed,
    required this.teamId,
    required this.originalRegularSeasonRank,
  });

  factory PlayoffTeamQualification.fromJson(Map<String, dynamic> json) {
    final seed = json['playoffSeed'];
    final teamId = json['teamId'];
    final originalRank = json['originalRegularSeasonRank'];
    if (seed is! int || teamId is! String || originalRank is! int) {
      throw const FormatException('Malformed playoff qualification');
    }
    return PlayoffTeamQualification(
      playoffSeed: seed,
      teamId: TeamId(teamId),
      originalRegularSeasonRank: originalRank,
    );
  }

  final int playoffSeed;
  final TeamId teamId;
  final int originalRegularSeasonRank;

  Map<String, Object?> toJson() => {
    'playoffSeed': playoffSeed,
    'teamId': teamId.value,
    'originalRegularSeasonRank': originalRegularSeasonRank,
  };
}

final class PlayoffSeriesIdentity {
  const PlayoffSeriesIdentity({
    required this.seriesIndex,
    required this.id,
    required this.firstTeamId,
    required this.secondTeamId,
  });

  factory PlayoffSeriesIdentity.fromJson(Map<String, dynamic> json) {
    final index = json['seriesIndex'];
    final id = json['id'];
    final first = json['firstTeamId'];
    final second = json['secondTeamId'];
    if (index is! int ||
        id is! String ||
        !json.containsKey('firstTeamId') ||
        !json.containsKey('secondTeamId') ||
        (first != null && first is! String) ||
        (second != null && second is! String)) {
      throw const FormatException('Malformed playoff series identity');
    }
    return PlayoffSeriesIdentity(
      seriesIndex: index,
      id: id,
      firstTeamId: first == null ? null : TeamId(first as String),
      secondTeamId: second == null ? null : TeamId(second as String),
    );
  }

  final int seriesIndex;
  final String id;
  final TeamId? firstTeamId;
  final TeamId? secondTeamId;

  PlayoffRound get round =>
      PlayoffRound.values[seriesIndex < 8
          ? 0
          : seriesIndex < 12
          ? 1
          : seriesIndex < 14
          ? 2
          : 3];

  bool get isResolved => firstTeamId != null && secondTeamId != null;

  Map<String, Object?> toJson() => {
    'seriesIndex': seriesIndex,
    'id': id,
    'firstTeamId': firstTeamId?.value,
    'secondTeamId': secondTeamId?.value,
  };
}

final class PlayoffGameIdentity {
  const PlayoffGameIdentity({
    required this.id,
    required this.seriesIndex,
    required this.gameNumber,
    required this.rematchIndex,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.gameSeed,
  });

  factory PlayoffGameIdentity.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final seriesIndex = json['seriesIndex'];
    final gameNumber = json['gameNumber'];
    final rematchIndex = json['rematchIndex'];
    final home = json['homeTeamId'];
    final away = json['awayTeamId'];
    final seed = json['gameSeed'];
    if (id is! String ||
        seriesIndex is! int ||
        gameNumber is! int ||
        rematchIndex is! int ||
        home is! String ||
        away is! String ||
        seed is! int) {
      throw const FormatException('Malformed playoff game identity');
    }
    return PlayoffGameIdentity(
      id: id,
      seriesIndex: seriesIndex,
      gameNumber: gameNumber,
      rematchIndex: rematchIndex,
      homeTeamId: TeamId(home),
      awayTeamId: TeamId(away),
      gameSeed: seed,
    );
  }

  final String id;
  final int seriesIndex;
  final int gameNumber;
  final int rematchIndex;
  final TeamId homeTeamId;
  final TeamId awayTeamId;
  final int gameSeed;

  Map<String, Object?> toJson() => {
    'id': id,
    'seriesIndex': seriesIndex,
    'gameNumber': gameNumber,
    'rematchIndex': rematchIndex,
    'homeTeamId': homeTeamId.value,
    'awayTeamId': awayTeamId.value,
    'gameSeed': gameSeed,
  };
}

/// Immutable 16-team bracket whose outcomes derive only from validated games.
final class PlayoffState {
  PlayoffState._({
    required this.seasonId,
    required this.seasonYear,
    required this.bracketRuleset,
    required this.homeCourtRuleset,
    required List<PlayoffTeamQualification> qualifiedTeams,
    required List<PlayoffSeriesIdentity> series,
    required Map<String, PlayoffGameIdentity> gameIdentities,
    required Map<String, RegularSeasonGameResult> gameResults,
    required Map<String, String> gameInputSnapshots,
  }) : qualifiedTeams = List.unmodifiable(qualifiedTeams),
       series = List.unmodifiable(series),
       gameIdentities = Map.unmodifiable(gameIdentities),
       gameResults = Map.unmodifiable(gameResults),
       gameInputSnapshots = Map.unmodifiable(gameInputSnapshots) {
    _validateShape();
  }

  factory PlayoffState.initial({
    required String seasonId,
    required int seasonYear,
    required int scheduleSeed,
    required List<(int, TeamId, int)> qualifiedTeams,
    required List<TeamId> franchiseIds,
  }) {
    final qualifications = [
      for (final (seed, teamId, originalRank) in qualifiedTeams)
        PlayoffTeamQualification(
          playoffSeed: seed,
          teamId: teamId,
          originalRegularSeasonRank: originalRank,
        ),
    ]..sort((a, b) => a.playoffSeed.compareTo(b.playoffSeed));
    final bySeed = {for (final team in qualifications) team.playoffSeed: team};
    final slots = <PlayoffSeriesIdentity>[];
    final gameIdentities = <String, PlayoffGameIdentity>{};
    for (var index = 0; index < _playoffSeriesCount; index++) {
      TeamId? first;
      TeamId? second;
      if (index < 8) {
        final (firstSeed, secondSeed) = _firstRoundSeeds[index];
        first = bySeed[firstSeed]?.teamId;
        second = bySeed[secondSeed]?.teamId;
      }
      final slot = PlayoffSeriesIdentity(
        seriesIndex: index,
        id: _seriesId(seasonId, index),
        firstTeamId: first,
        secondTeamId: second,
      );
      slots.add(slot);
      if (slot.isResolved) {
        _addGameIdentities(
          target: gameIdentities,
          seasonId: seasonId,
          seriesIndex: index,
          firstTeamId: first!,
          secondTeamId: second!,
          qualifications: qualifications,
          scheduleSeed: scheduleSeed,
          franchiseIds: franchiseIds,
        );
      }
    }
    return PlayoffState._(
      seasonId: seasonId,
      seasonYear: seasonYear,
      bracketRuleset: bracketRulesetVersion,
      homeCourtRuleset: homeCourtRulesetVersion,
      qualifiedTeams: qualifications,
      series: slots,
      gameIdentities: gameIdentities,
      gameResults: const {},
      gameInputSnapshots: const {},
    );
  }

  factory PlayoffState.fromJson(Map<String, dynamic> json) {
    final seasonId = json['seasonId'];
    final seasonYear = json['seasonYear'];
    final bracketRuleset = json['bracketRuleset'];
    final homeCourtRuleset = json['homeCourtRuleset'];
    final rawQualifications = json['qualifiedTeams'];
    final rawSeries = json['series'];
    final rawIdentities = json['gameIdentities'];
    final rawResults = json['gameResults'];
    final rawSnapshots = json['gameInputSnapshots'];
    if (seasonId is! String ||
        seasonYear is! int ||
        bracketRuleset is! String ||
        homeCourtRuleset is! String ||
        rawQualifications is! List ||
        rawSeries is! List ||
        rawIdentities is! Map<String, dynamic> ||
        rawResults is! Map<String, dynamic> ||
        rawSnapshots is! Map<String, dynamic> ||
        rawSnapshots.values.any((value) => value is! String)) {
      throw const FormatException('Malformed playoff state');
    }
    final identities = <String, PlayoffGameIdentity>{};
    for (final entry in rawIdentities.entries) {
      if (entry.value is! Map<String, dynamic>) {
        throw const FormatException('Malformed playoff game identity');
      }
      identities[entry.key] = PlayoffGameIdentity.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    final results = <String, RegularSeasonGameResult>{};
    for (final entry in rawResults.entries) {
      if (entry.value is! Map<String, dynamic>) {
        throw const FormatException('Malformed playoff game result');
      }
      results[entry.key] = RegularSeasonGameResult.fromJson(
        entry.value as Map<String, dynamic>,
        schemaVersion: 20,
      );
    }
    return PlayoffState._(
      seasonId: seasonId,
      seasonYear: seasonYear,
      bracketRuleset: bracketRuleset,
      homeCourtRuleset: homeCourtRuleset,
      qualifiedTeams: [
        for (final value in rawQualifications)
          if (value is Map<String, dynamic>)
            PlayoffTeamQualification.fromJson(value)
          else
            throw const FormatException('Malformed playoff qualification'),
      ],
      series: [
        for (final value in rawSeries)
          if (value is Map<String, dynamic>)
            PlayoffSeriesIdentity.fromJson(value)
          else
            throw const FormatException('Malformed playoff series'),
      ],
      gameIdentities: identities,
      gameResults: results,
      gameInputSnapshots: rawSnapshots.cast<String, String>(),
    );
  }

  static const bracketRulesetVersion = 'm009-fixed-playoff-bracket-v1';
  static const homeCourtRulesetVersion = 'm009-original-rank-home-court-v1';

  final String seasonId;
  final int seasonYear;
  final String bracketRuleset;
  final String homeCourtRuleset;
  final List<PlayoffTeamQualification> qualifiedTeams;
  final List<PlayoffSeriesIdentity> series;
  final Map<String, PlayoffGameIdentity> gameIdentities;
  final Map<String, RegularSeasonGameResult> gameResults;
  final Map<String, String> gameInputSnapshots;

  bool get isComplete => seriesWinner(14) != null;
  TeamId? get champion => isComplete ? seriesWinner(14) : null;

  PlayoffRound? get currentRound {
    for (final round in PlayoffRound.values) {
      if (series.any(
        (slot) => slot.round == round && seriesWinner(slot.seriesIndex) == null,
      )) {
        return round;
      }
    }
    return null;
  }

  Set<TeamId> get eliminatedTeams {
    final eliminated = <TeamId>{};
    for (final slot in series) {
      final winner = seriesWinner(slot.seriesIndex);
      if (winner == null) continue;
      final loser = slot.firstTeamId == winner
          ? slot.secondTeamId
          : slot.firstTeamId;
      if (loser != null) eliminated.add(loser);
    }
    return Set.unmodifiable(eliminated);
  }

  PlayoffSeriesIdentity seriesAt(int seriesIndex) {
    if (seriesIndex < 0 || seriesIndex >= _playoffSeriesCount) {
      throw RangeError.range(seriesIndex, 0, _playoffSeriesCount - 1);
    }
    return series[seriesIndex];
  }

  int seriesWins(int seriesIndex, TeamId teamId) {
    final slot = seriesAt(seriesIndex);
    if (teamId != slot.firstTeamId && teamId != slot.secondTeamId) return 0;
    var wins = 0;
    for (final result in _resultsForSeries(seriesIndex)) {
      if (result.summary.winnerTeamId == teamId) wins++;
    }
    return wins;
  }

  TeamId? seriesWinner(int seriesIndex) {
    final slot = seriesAt(seriesIndex);
    if (!slot.isResolved) return null;
    var firstWins = 0;
    var secondWins = 0;
    for (final result in _resultsForSeries(seriesIndex)) {
      if (result.summary.winnerTeamId == slot.firstTeamId) {
        if (++firstWins == 4) return slot.firstTeamId;
      } else if (result.summary.winnerTeamId == slot.secondTeamId) {
        if (++secondWins == 4) return slot.secondTeamId;
      } else {
        return null;
      }
    }
    return null;
  }

  List<PlayoffGameIdentity> get nextEligibleGames {
    final round = currentRound;
    if (round == null) return const [];
    return List.unmodifiable([
      for (final slot in series)
        if (slot.round == round && seriesWinner(slot.seriesIndex) == null)
          gameIdentities[_gameId(
            seasonId,
            slot.seriesIndex,
            _resultsForSeries(slot.seriesIndex).length + 1,
          )]!,
    ]);
  }

  PlayoffState withResults({
    required List<RegularSeasonGameResult> results,
    required Map<String, String> addedSnapshots,
    required int scheduleSeed,
    required List<TeamId> franchiseIds,
  }) {
    if (results.isEmpty) throw const FormatException('Empty playoff slate');
    final nextResults = Map<String, RegularSeasonGameResult>.of(gameResults);
    for (final result in results) {
      if (nextResults.containsKey(result.fixtureId) ||
          !gameIdentities.containsKey(result.fixtureId)) {
        throw const FormatException('Duplicate or unknown playoff game result');
      }
      nextResults[result.fixtureId] = result;
    }
    final snapshots = Map<String, String>.of(gameInputSnapshots);
    for (final entry in addedSnapshots.entries) {
      final old = snapshots[entry.key];
      if (old != null && old != entry.value) {
        throw const FormatException('Playoff snapshot digest collision');
      }
      snapshots[entry.key] = entry.value;
    }
    final nextSlots = List<PlayoffSeriesIdentity>.of(series);
    final nextIdentities = Map<String, PlayoffGameIdentity>.of(gameIdentities);
    for (var index = 8; index < _playoffSeriesCount; index++) {
      if (nextSlots[index].isResolved) continue;
      final (firstDependency, secondDependency) =
          _seriesDependencies[index - 8];
      final firstWinner = _seriesWinnerFrom(
        nextResults,
        nextSlots,
        firstDependency,
        seasonId,
      );
      final secondWinner = _seriesWinnerFrom(
        nextResults,
        nextSlots,
        secondDependency,
        seasonId,
      );
      if (firstWinner == null || secondWinner == null) continue;
      nextSlots[index] = PlayoffSeriesIdentity(
        seriesIndex: index,
        id: _seriesId(seasonId, index),
        firstTeamId: firstWinner,
        secondTeamId: secondWinner,
      );
      _addGameIdentities(
        target: nextIdentities,
        seasonId: seasonId,
        seriesIndex: index,
        firstTeamId: firstWinner,
        secondTeamId: secondWinner,
        qualifications: qualifiedTeams,
        scheduleSeed: scheduleSeed,
        franchiseIds: franchiseIds,
      );
    }
    return PlayoffState._(
      seasonId: seasonId,
      seasonYear: seasonYear,
      bracketRuleset: bracketRuleset,
      homeCourtRuleset: homeCourtRuleset,
      qualifiedTeams: qualifiedTeams,
      series: nextSlots,
      gameIdentities: nextIdentities,
      gameResults: nextResults,
      gameInputSnapshots: snapshots,
    );
  }

  void validate({
    required RegularSeasonState regularSeason,
    required PlayInState playIn,
  }) {
    _validateShape();
    final schedule = regularSeason.schedule;
    if (schedule == null ||
        schedule.seasonId != seasonId ||
        schedule.seasonYear != seasonYear ||
        regularSeason.seasonId != seasonId ||
        regularSeason.seasonYear != seasonYear ||
        regularSeason.completedRounds != 82 ||
        regularSeason.completedGames != 1230 ||
        regularSeason.gameResults.length != 1230 ||
        schedule.totalFixtures != 1230 ||
        !playIn.isComplete ||
        playIn.seasonId != seasonId ||
        playIn.seasonYear != seasonYear) {
      throw const FormatException(
        'Playoffs require completed season and Play-In',
      );
    }
    playIn.validate(regularSeasonState: regularSeason);
    final fromPlayIn = playIn.qualifiedTeams;
    if (fromPlayIn.length != 16 || qualifiedTeams.length != 16) {
      throw const FormatException(
        'Playoff qualification must contain 16 teams',
      );
    }
    for (var index = 0; index < 16; index++) {
      final actual = qualifiedTeams[index];
      final (seed, teamId, originalRank) = fromPlayIn[index];
      if (actual.playoffSeed != seed ||
          actual.teamId != teamId ||
          actual.originalRegularSeasonRank != originalRank) {
        throw const FormatException('Playoff qualification snapshot changed');
      }
    }
    final originalRankByTeam = {
      for (final team in qualifiedTeams)
        team.teamId.value: team.originalRegularSeasonRank,
    };
    final expectedSeries = <(TeamId?, TeamId?)>[];
    final bySeed = {for (final team in qualifiedTeams) team.playoffSeed: team};
    for (final (firstSeed, secondSeed) in _firstRoundSeeds) {
      expectedSeries.add((
        bySeed[firstSeed]!.teamId,
        bySeed[secondSeed]!.teamId,
      ));
    }
    for (var index = 0; index < 7; index++) {
      expectedSeries.add((null, null));
    }
    for (var index = 8; index < _playoffSeriesCount; index++) {
      final (firstDependency, secondDependency) =
          _seriesDependencies[index - 8];
      final first = seriesWinner(firstDependency);
      final second = seriesWinner(secondDependency);
      expectedSeries[index] = first == null || second == null
          ? (null, null)
          : (first, second);
    }
    final expectedIdentities = <String, PlayoffGameIdentity>{};
    for (var index = 0; index < _playoffSeriesCount; index++) {
      final (first, second) = expectedSeries[index];
      final slot = series[index];
      if (slot.firstTeamId != first || slot.secondTeamId != second) {
        throw FormatException(
          'Playoff series $index participants mismatch: expected '
          '${first?.value ?? 'unresolved'} vs ${second?.value ?? 'unresolved'}, '
          'stored ${slot.firstTeamId?.value ?? 'unresolved'} vs '
          '${slot.secondTeamId?.value ?? 'unresolved'}',
        );
      }
      if (first == null || second == null) continue;
      _addGameIdentities(
        target: expectedIdentities,
        seasonId: seasonId,
        seriesIndex: index,
        firstTeamId: first,
        secondTeamId: second,
        qualifications: qualifiedTeams,
        scheduleSeed: regularSeason.scheduleSeed,
        franchiseIds: regularSeason.openingTeams
            .map((team) => team.teamId)
            .toList(),
      );
    }
    if (expectedIdentities.length != gameIdentities.length) {
      throw const FormatException('Playoff game identity count mismatch');
    }
    for (final entry in expectedIdentities.entries) {
      final actual = gameIdentities[entry.key];
      final expected = entry.value;
      if (actual == null ||
          actual.seriesIndex != expected.seriesIndex ||
          actual.gameNumber != expected.gameNumber ||
          actual.rematchIndex != expected.rematchIndex ||
          actual.homeTeamId != expected.homeTeamId ||
          actual.awayTeamId != expected.awayTeamId ||
          actual.gameSeed != expected.gameSeed) {
        throw const FormatException('Playoff game identity changed');
      }
    }
    final priorSeeds = <int>{
      for (final fixture in schedule.allFixtures)
        _normalizedSeed(fixture.gameSeed),
      for (final identity in playIn.gameIdentities)
        if (identity.gameSeed != null) _normalizedSeed(identity.gameSeed!),
    };
    final playoffSeeds = <int>{};
    for (final identity in gameIdentities.values) {
      final normalized = _normalizedSeed(identity.gameSeed);
      if (priorSeeds.contains(normalized) || !playoffSeeds.add(normalized)) {
        throw const FormatException('Playoff game seed collision');
      }
    }
    final openingTeamIds = {
      for (final team in regularSeason.openingTeams) team.teamId.value,
    };
    final historicalLeagues = <String, League>{
      for (final entry in gameInputSnapshots.entries)
        entry.key: RegularSeasonGameInputEvidence.parseLeagueSnapshot(
          snapshotId: entry.key,
          leagueSnapshotJson: entry.value,
          openingTeamIds: openingTeamIds,
        ),
    };
    for (final slot in series) {
      if (!slot.isResolved) continue;
      for (
        var gameNumber = 1;
        gameNumber <= _playoffGamesPerSeries;
        gameNumber++
      ) {
        final id = _gameId(seasonId, slot.seriesIndex, gameNumber);
        final result = gameResults[id];
        if (result == null) continue;
        final identity = gameIdentities[id]!;
        final evidence = result.inputEvidence;
        if (evidence == null ||
            result.fingerprintVersion == null ||
            result.coreEngineVersion == null ||
            result.leagueSchemaVersion == null) {
          throw const FormatException(
            'Playoff result lacks historical evidence',
          );
        }
        final snapshotJson = gameInputSnapshots[evidence.leagueSnapshotId];
        final historicalLeague = historicalLeagues[evidence.leagueSnapshotId];
        if (snapshotJson == null || historicalLeague == null) {
          throw const FormatException('Playoff historical snapshot is missing');
        }
        final historicalInput = evidence.validate(
          leagueSnapshotId: evidence.leagueSnapshotId,
          leagueSnapshotJson: snapshotJson,
          league: historicalLeague,
          inputFingerprint: result.inputFingerprint,
          homeTeamId: result.homeTeamId.value,
          awayTeamId: result.awayTeamId.value,
          gameSeed: result.gameSeed,
          simulationVersion: result.simulationVersion,
          rulesVersion: result.rulesVersion,
          eventSchemaVersion: result.eventSchemaVersion,
          prngImplementationId: result.prngImplementationId,
          fingerprintVersion: result.fingerprintVersion!,
          coreEngineVersion: result.coreEngineVersion!,
          leagueSchemaVersion: result.leagueSchemaVersion!,
        );
        final playerTeams = <String, String>{};
        for (final team in historicalInput.league.teams) {
          if (team.id != identity.homeTeamId &&
              team.id != identity.awayTeamId) {
            continue;
          }
          for (final player in team.players) {
            if (team.roster.categoryOf(player.id) == RosterCategory.standard) {
              playerTeams[player.id.value] = team.id.value;
            }
          }
        }
        result.validateForIdentity(
          fixtureId: identity.id,
          fixtureSeasonId: seasonId,
          fixtureSeasonYear: seasonYear,
          expectedSeasonId: seasonId,
          expectedSeasonYear: seasonYear,
          expectedHomeTeamId: identity.homeTeamId,
          expectedAwayTeamId: identity.awayTeamId,
          expectedGameSeed: identity.gameSeed,
          standardPlayers: playerTeams.keys.toSet(),
          playerTeams: playerTeams,
        );
      }
    }
    final referencedSnapshots = {
      for (final result in gameResults.values)
        result.inputEvidence!.leagueSnapshotId,
    };
    if (referencedSnapshots.length != gameInputSnapshots.length ||
        !referencedSnapshots.containsAll(gameInputSnapshots.keys)) {
      throw const FormatException(
        'Playoff snapshots are missing or unreferenced',
      );
    }
    if (originalRankByTeam.values.toSet().length != 16) {
      throw const FormatException('Playoff original ranks are not unique');
    }
  }

  Map<String, Object?> toJson() => {
    'seasonId': seasonId,
    'seasonYear': seasonYear,
    'bracketRuleset': bracketRuleset,
    'homeCourtRuleset': homeCourtRuleset,
    'qualifiedTeams': [for (final team in qualifiedTeams) team.toJson()],
    'series': [for (final slot in series) slot.toJson()],
    'gameIdentities': {
      for (final entry in gameIdentities.entries)
        entry.key: entry.value.toJson(),
    },
    'gameResults': {
      for (final entry in gameResults.entries) entry.key: entry.value.toJson(),
    },
    'gameInputSnapshots': gameInputSnapshots,
  };

  List<RegularSeasonGameResult> _resultsForSeries(int seriesIndex) => [
    for (var gameNumber = 1; gameNumber <= _playoffGamesPerSeries; gameNumber++)
      ?gameResults[_gameId(seasonId, seriesIndex, gameNumber)],
  ];

  void _validateShape() {
    if (seasonId.trim().isEmpty ||
        seasonYear < 1 ||
        bracketRuleset != bracketRulesetVersion ||
        homeCourtRuleset != homeCourtRulesetVersion ||
        qualifiedTeams.length != 16 ||
        series.length != _playoffSeriesCount ||
        qualifiedTeams.map((team) => team.playoffSeed).toSet().length != 16 ||
        qualifiedTeams.map((team) => team.teamId).toSet().length != 16 ||
        qualifiedTeams.any(
          (team) =>
              team.playoffSeed < 1 ||
              team.playoffSeed > 16 ||
              team.originalRegularSeasonRank < 1 ||
              team.originalRegularSeasonRank > 30,
        )) {
      throw const FormatException('Invalid playoff state identity');
    }
    for (var index = 0; index < 16; index++) {
      if (qualifiedTeams[index].playoffSeed != index + 1) {
        throw const FormatException(
          'Playoff seeds must be ordered 1 through 16',
        );
      }
    }
    for (var index = 0; index < _playoffSeriesCount; index++) {
      final slot = series[index];
      if (slot.seriesIndex != index ||
          slot.id != _seriesId(seasonId, index) ||
          (slot.firstTeamId == null) != (slot.secondTeamId == null) ||
          (slot.isResolved && slot.firstTeamId == slot.secondTeamId)) {
        throw const FormatException('Invalid playoff series slot');
      }
    }
    final rematchIndices = <int>{};
    for (final entry in gameIdentities.entries) {
      final identity = entry.value;
      if (entry.key != identity.id ||
          identity.seriesIndex < 0 ||
          identity.seriesIndex >= _playoffSeriesCount ||
          identity.gameNumber < 1 ||
          identity.gameNumber > _playoffGamesPerSeries ||
          identity.id !=
              _gameId(seasonId, identity.seriesIndex, identity.gameNumber) ||
          identity.rematchIndex !=
              _rematchIndex(identity.seriesIndex, identity.gameNumber) ||
          identity.rematchIndex < _playoffGameFirstRematchIndex ||
          identity.rematchIndex > _playoffGameLastRematchIndex ||
          identity.homeTeamId == identity.awayTeamId ||
          !rematchIndices.add(identity.rematchIndex)) {
        throw const FormatException('Invalid playoff game identity');
      }
    }
    for (final entry in gameResults.entries) {
      if (entry.key != entry.value.fixtureId ||
          !gameIdentities.containsKey(entry.key)) {
        throw const FormatException('Unknown playoff result identity');
      }
    }
    for (final slot in series) {
      if (!slot.isResolved) continue;
      var firstWins = 0;
      var secondWins = 0;
      var clinched = false;
      for (
        var gameNumber = 1;
        gameNumber <= _playoffGamesPerSeries;
        gameNumber++
      ) {
        final id = _gameId(seasonId, slot.seriesIndex, gameNumber);
        final result = gameResults[id];
        if (result == null) {
          if (gameResults.keys.any((key) {
            final later = gameIdentities[key];
            return later != null &&
                later.seriesIndex == slot.seriesIndex &&
                later.gameNumber > gameNumber;
          })) {
            throw const FormatException(
              'Playoff series games are out of order',
            );
          }
          continue;
        }
        if (clinched) {
          throw const FormatException('Playoff game follows series clinch');
        }
        if (result.summary.winnerTeamId == slot.firstTeamId) {
          firstWins++;
        } else if (result.summary.winnerTeamId == slot.secondTeamId) {
          secondWins++;
        } else {
          throw const FormatException(
            'Playoff winner is not a series participant',
          );
        }
        clinched = firstWins == 4 || secondWins == 4;
      }
    }
    final referenced = <String>{};
    for (final result in gameResults.values) {
      final evidence = result.inputEvidence;
      if (evidence == null) {
        throw const FormatException('Playoff result lacks historical evidence');
      }
      referenced.add(evidence.leagueSnapshotId);
    }
    if (referenced.length != gameInputSnapshots.length ||
        !referenced.containsAll(gameInputSnapshots.keys)) {
      throw const FormatException('Playoff snapshot references are invalid');
    }
  }
}

TeamId? _seriesWinnerFrom(
  Map<String, RegularSeasonGameResult> results,
  List<PlayoffSeriesIdentity> series,
  int seriesIndex,
  String seasonId,
) {
  final slot = series[seriesIndex];
  if (!slot.isResolved) return null;
  var firstWins = 0;
  var secondWins = 0;
  for (var gameNumber = 1; gameNumber <= _playoffGamesPerSeries; gameNumber++) {
    final result = results[_gameId(seasonId, seriesIndex, gameNumber)];
    if (result == null) break;
    if (result.summary.winnerTeamId == slot.firstTeamId) {
      firstWins++;
    } else if (result.summary.winnerTeamId == slot.secondTeamId) {
      secondWins++;
    } else {
      return null;
    }
    if (firstWins == 4) return slot.firstTeamId;
    if (secondWins == 4) return slot.secondTeamId;
  }
  return null;
}

void _addGameIdentities({
  required Map<String, PlayoffGameIdentity> target,
  required String seasonId,
  required int seriesIndex,
  required TeamId firstTeamId,
  required TeamId secondTeamId,
  required List<PlayoffTeamQualification> qualifications,
  required int scheduleSeed,
  required List<TeamId> franchiseIds,
}) {
  final rankById = {
    for (final team in qualifications)
      team.teamId.value: team.originalRegularSeasonRank,
  };
  final sortedIds = franchiseIds.map((team) => team.value).toList()..sort();
  final firstIsHigherRank =
      rankById[firstTeamId.value]! < rankById[secondTeamId.value]!;
  final higherRank = firstIsHigherRank ? firstTeamId : secondTeamId;
  final lowerRank = firstIsHigherRank ? secondTeamId : firstTeamId;
  for (var gameNumber = 1; gameNumber <= _playoffGamesPerSeries; gameNumber++) {
    final higherRankHosts = _earlyHomeGames.contains(gameNumber);
    final home = higherRankHosts ? higherRank : lowerRank;
    final away = higherRankHosts ? lowerRank : higherRank;
    final rematchIndex = _rematchIndex(seriesIndex, gameNumber);
    final id = _gameId(seasonId, seriesIndex, gameNumber);
    final identity = PlayoffGameIdentity(
      id: id,
      seriesIndex: seriesIndex,
      gameNumber: gameNumber,
      rematchIndex: rematchIndex,
      homeTeamId: home,
      awayTeamId: away,
      gameSeed: _derivePlayoffSeed(
        scheduleSeed: scheduleSeed,
        sortedTeamIds: sortedIds,
        home: home,
        away: away,
        rematchIndex: rematchIndex,
      ),
    );
    if (target.containsKey(id)) {
      throw const FormatException('Duplicate playoff game identity');
    }
    target[id] = identity;
  }
}
