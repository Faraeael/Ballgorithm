import '../models/ids.dart';
import '../season/season_seed.dart';
import 'regular_season_game_input_evidence.dart';
import 'regular_season_game_result.dart';
import 'regular_season_state.dart';

const _playInGameCount = 3;
const _playInSeedIndices = [83, 84, 85];

String _gameId(String seasonId, int gameNumber) =>
    '$seasonId-playin-g$gameNumber';

int _seedForMatchup({
  required int scheduleSeed,
  required List<TeamId> ranking,
  required TeamId home,
  required TeamId away,
  required int rematchIndex,
}) {
  final ids = ranking.map((id) => id.value).toList()..sort();
  final homeIndex = ids.indexOf(home.value);
  final awayIndex = ids.indexOf(away.value);
  if (homeIndex < 0 || homeIndex >= 30 || awayIndex < 0 || awayIndex >= 30) {
    throw const FormatException('Play-In team index is outside 0..29');
  }
  return deriveGameSeed(
    leagueSeed: scheduleSeed,
    homeIndex: homeIndex,
    awayIndex: awayIndex,
    rematchIndex: rematchIndex,
  );
}

final class PlayInGameIdentity {
  const PlayInGameIdentity({
    required this.id,
    required this.rematchIndex,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.gameSeed,
  });

  factory PlayInGameIdentity.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final rematchIndex = json['rematchIndex'];
    final homeTeamId = json['homeTeamId'];
    final awayTeamId = json['awayTeamId'];
    final gameSeed = json['gameSeed'];
    if (id is! String ||
        rematchIndex is! int ||
        !json.containsKey('homeTeamId') ||
        !json.containsKey('awayTeamId') ||
        !json.containsKey('gameSeed') ||
        (homeTeamId != null && homeTeamId is! String) ||
        (awayTeamId != null && awayTeamId is! String) ||
        (gameSeed != null && gameSeed is! int)) {
      throw const FormatException('Malformed Play-In game identity');
    }
    return PlayInGameIdentity(
      id: id,
      rematchIndex: rematchIndex,
      homeTeamId: homeTeamId == null ? null : TeamId(homeTeamId as String),
      awayTeamId: awayTeamId == null ? null : TeamId(awayTeamId as String),
      gameSeed: gameSeed as int?,
    );
  }

  final String id;
  final int rematchIndex;
  final TeamId? homeTeamId;
  final TeamId? awayTeamId;
  final int? gameSeed;

  Map<String, Object?> toJson() => {
    'id': id,
    'rematchIndex': rematchIndex,
    'homeTeamId': homeTeamId?.value,
    'awayTeamId': awayTeamId?.value,
    'gameSeed': gameSeed,
  };
}

final class PlayInFixture {
  const PlayInFixture({
    required this.gameNumber,
    required this.id,
    required this.rematchIndex,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.gameSeed,
    required this.isCompleted,
  });

  final int gameNumber;
  final String id;
  final int rematchIndex;
  final TeamId homeTeamId;
  final TeamId awayTeamId;
  final int gameSeed;
  final bool isCompleted;
}

/// Frozen regular-season rank and independent Play-In result authority.
final class PlayInState {
  PlayInState({
    required this.seasonId,
    required this.seasonYear,
    required List<TeamId> originalRanking,
    required this.rankingRuleset,
    required List<PlayInGameIdentity> gameIdentities,
    required Map<String, RegularSeasonGameResult> gameResults,
    required Map<String, String> gameInputSnapshots,
  }) : originalRanking = List.unmodifiable(originalRanking),
       gameIdentities = List.unmodifiable(gameIdentities),
       gameResults = Map.unmodifiable(gameResults),
       gameInputSnapshots = Map.unmodifiable(gameInputSnapshots) {
    validate();
  }

  factory PlayInState.initial({
    required String seasonId,
    required int seasonYear,
    required int scheduleSeed,
    required List<TeamId> originalRanking,
  }) => PlayInState(
    seasonId: seasonId,
    seasonYear: seasonYear,
    originalRanking: originalRanking,
    rankingRuleset: rankingRulesetVersion,
    gameIdentities: [
      for (var game = 1; game <= _playInGameCount; game++)
        PlayInGameIdentity(
          id: _gameId(seasonId, game),
          rematchIndex: _playInSeedIndices[game - 1],
          homeTeamId: game == 1
              ? originalRanking[14]
              : game == 2
              ? originalRanking[16]
              : null,
          awayTeamId: game == 1
              ? originalRanking[15]
              : game == 2
              ? originalRanking[17]
              : null,
          gameSeed: game == 1
              ? _seedForMatchup(
                  scheduleSeed: scheduleSeed,
                  ranking: originalRanking,
                  home: originalRanking[14],
                  away: originalRanking[15],
                  rematchIndex: 83,
                )
              : game == 2
              ? _seedForMatchup(
                  scheduleSeed: scheduleSeed,
                  ranking: originalRanking,
                  home: originalRanking[16],
                  away: originalRanking[17],
                  rematchIndex: 84,
                )
              : null,
        ),
    ],
    gameResults: const {},
    gameInputSnapshots: const {},
  );

  factory PlayInState.fromJson(Map<String, dynamic> json) {
    final seasonId = json['seasonId'];
    final seasonYear = json['seasonYear'];
    final rankingRuleset = json['rankingRuleset'];
    final rawRanking = json['originalRanking'];
    final rawIdentities = json['gameIdentities'];
    final rawResults = json['gameResults'];
    final rawSnapshots = json['gameInputSnapshots'];
    if (seasonId is! String ||
        seasonYear is! int ||
        rankingRuleset is! String ||
        rawRanking is! List ||
        rawIdentities is! List ||
        rawResults is! Map<String, dynamic> ||
        rawSnapshots is! Map<String, dynamic> ||
        rawSnapshots.values.any((value) => value is! String)) {
      throw const FormatException('Malformed Play-In state');
    }
    final results = <String, RegularSeasonGameResult>{};
    for (final entry in rawResults.entries) {
      if (entry.value is! Map<String, dynamic>) {
        throw const FormatException('Malformed Play-In game result');
      }
      results[entry.key] = RegularSeasonGameResult.fromJson(
        entry.value as Map<String, dynamic>,
        schemaVersion: 19,
      );
    }
    return PlayInState(
      seasonId: seasonId,
      seasonYear: seasonYear,
      originalRanking: [
        for (final value in rawRanking)
          if (value is String)
            TeamId(value)
          else
            throw const FormatException('Malformed Play-In ranking'),
      ],
      rankingRuleset: rankingRuleset,
      gameIdentities: [
        for (final value in rawIdentities)
          if (value is Map<String, dynamic>)
            PlayInGameIdentity.fromJson(value)
          else
            throw const FormatException('Malformed Play-In game identity'),
      ],
      gameResults: results,
      gameInputSnapshots: rawSnapshots.cast<String, String>(),
    );
  }

  static const rankingRulesetVersion = 'm009-postseason-seeding-v1';

  final String seasonId;
  final int seasonYear;
  final List<TeamId> originalRanking;
  final String rankingRuleset;
  final List<PlayInGameIdentity> gameIdentities;
  final Map<String, RegularSeasonGameResult> gameResults;
  final Map<String, String> gameInputSnapshots;

  bool get isComplete => gameResults.containsKey(_gameId(seasonId, 3));

  List<(int, TeamId, int)> get qualifiedTeams {
    final qualifiers = <(int, TeamId, int)>[
      for (var seed = 1; seed <= 14; seed++)
        (seed, originalRanking[seed - 1], seed),
    ];
    final game1 = gameResults[_gameId(seasonId, 1)];
    if (game1 != null) {
      qualifiers.add((
        15,
        game1.summary.winnerTeamId,
        _originalSeed(game1.summary.winnerTeamId),
      ));
    }
    final game3 = gameResults[_gameId(seasonId, 3)];
    if (game3 != null) {
      qualifiers.add((
        16,
        game3.summary.winnerTeamId,
        _originalSeed(game3.summary.winnerTeamId),
      ));
    }
    return List.unmodifiable(qualifiers);
  }

  Set<TeamId> get eliminatedTeams {
    final eliminated = <TeamId>{...originalRanking.skip(18)};
    final game2 = gameResults[_gameId(seasonId, 2)];
    if (game2 != null) {
      eliminated.add(_loser(game2));
    }
    final game3 = gameResults[_gameId(seasonId, 3)];
    if (game3 != null) {
      eliminated.add(_loser(game3));
    }
    return Set.unmodifiable(eliminated);
  }

  TeamId _loser(RegularSeasonGameResult result) =>
      result.summary.winnerTeamId == result.homeTeamId
      ? result.awayTeamId
      : result.homeTeamId;

  int _originalSeed(TeamId id) => originalRanking.indexOf(id) + 1;

  PlayInFixture? fixture({required int gameNumber, required int scheduleSeed}) {
    if (gameNumber < 1 || gameNumber > _playInGameCount) {
      throw RangeError.range(gameNumber, 1, _playInGameCount, 'gameNumber');
    }
    final identity = gameIdentities[gameNumber - 1];
    TeamId home;
    TeamId away;
    if (gameNumber == 1) {
      home = originalRanking[14];
      away = originalRanking[15];
    } else if (gameNumber == 2) {
      home = originalRanking[16];
      away = originalRanking[17];
    } else {
      final game1 = gameResults[_gameId(seasonId, 1)];
      final game2 = gameResults[_gameId(seasonId, 2)];
      if (game1 == null || game2 == null) return null;
      home = _loser(game1);
      away = game2.summary.winnerTeamId;
    }
    final seed = _seedForMatchup(
      scheduleSeed: scheduleSeed,
      ranking: originalRanking,
      home: home,
      away: away,
      rematchIndex: identity.rematchIndex,
    );
    if ((identity.homeTeamId != null && identity.homeTeamId != home) ||
        (identity.awayTeamId != null && identity.awayTeamId != away) ||
        (identity.gameSeed != null && identity.gameSeed != seed)) {
      throw const FormatException(
        'Play-In fixture differs from persisted identity',
      );
    }
    return PlayInFixture(
      gameNumber: gameNumber,
      id: identity.id,
      rematchIndex: identity.rematchIndex,
      homeTeamId: home,
      awayTeamId: away,
      gameSeed: seed,
      isCompleted: gameResults.containsKey(identity.id),
    );
  }

  PlayInState withResult({
    required RegularSeasonGameResult result,
    required String leagueSnapshotJson,
    required int scheduleSeed,
  }) {
    if (gameResults.containsKey(result.fixtureId)) {
      throw const FormatException('Duplicate Play-In game result');
    }
    final gameNumber =
        gameIdentities.indexWhere(
          (identity) => identity.id == result.fixtureId,
        ) +
        1;
    if (gameNumber == 0) {
      throw const FormatException('Unknown Play-In game result');
    }
    final fixture = this.fixture(
      gameNumber: gameNumber,
      scheduleSeed: scheduleSeed,
    );
    if (fixture == null ||
        result.homeTeamId != fixture.homeTeamId ||
        result.awayTeamId != fixture.awayTeamId ||
        result.gameSeed != fixture.gameSeed) {
      throw const FormatException('Play-In result does not match fixture');
    }
    final evidence = result.inputEvidence;
    if (evidence == null) {
      throw const FormatException(
        'Play-In game result lacks historical evidence',
      );
    }
    final snapshots = Map<String, String>.of(gameInputSnapshots);
    final snapshotId = evidence.leagueSnapshotId;
    final existing = snapshots.putIfAbsent(
      snapshotId,
      () => leagueSnapshotJson,
    );
    if (existing != leagueSnapshotJson) {
      throw const FormatException(
        'Play-In game-time snapshot digest collision',
      );
    }
    final results = {...gameResults, result.fixtureId: result};
    final identities = List<PlayInGameIdentity>.of(gameIdentities);
    identities[gameNumber - 1] = PlayInGameIdentity(
      id: fixture.id,
      rematchIndex: fixture.rematchIndex,
      homeTeamId: fixture.homeTeamId,
      awayTeamId: fixture.awayTeamId,
      gameSeed: fixture.gameSeed,
    );
    final game1 = results[_gameId(seasonId, 1)];
    final game2 = results[_gameId(seasonId, 2)];
    if (game1 != null && game2 != null) {
      final home = _loser(game1);
      final away = game2.summary.winnerTeamId;
      identities[2] = PlayInGameIdentity(
        id: _gameId(seasonId, 3),
        rematchIndex: 85,
        homeTeamId: home,
        awayTeamId: away,
        gameSeed: _seedForMatchup(
          scheduleSeed: scheduleSeed,
          ranking: originalRanking,
          home: home,
          away: away,
          rematchIndex: 85,
        ),
      );
    }
    return PlayInState(
      seasonId: seasonId,
      seasonYear: seasonYear,
      originalRanking: originalRanking,
      rankingRuleset: rankingRuleset,
      gameIdentities: identities,
      gameResults: results,
      gameInputSnapshots: snapshots,
    );
  }

  void validate({RegularSeasonState? regularSeasonState}) {
    if (seasonId.trim().isEmpty ||
        seasonYear < 1 ||
        rankingRuleset != rankingRulesetVersion ||
        originalRanking.length != 30 ||
        originalRanking.toSet().length != 30 ||
        gameIdentities.length != _playInGameCount ||
        gameIdentities.map((game) => game.id).toSet().length !=
            _playInGameCount) {
      throw const FormatException('Invalid Play-In identity or ranking');
    }
    for (var index = 0; index < _playInGameCount; index++) {
      final identity = gameIdentities[index];
      if (identity.id != _gameId(seasonId, index + 1) ||
          identity.rematchIndex != _playInSeedIndices[index]) {
        throw const FormatException('Invalid Play-In game identity');
      }
    }
    if (gameIdentities
        .take(2)
        .any(
          (identity) =>
              identity.homeTeamId == null ||
              identity.awayTeamId == null ||
              identity.gameSeed == null,
        )) {
      throw const FormatException(
        'Play-In initial fixture identity is incomplete',
      );
    }
    final thirdIdentity = gameIdentities[2];
    final hasGame3Prerequisites =
        gameResults.containsKey(_gameId(seasonId, 1)) &&
        gameResults.containsKey(_gameId(seasonId, 2));
    if (gameResults.containsKey(_gameId(seasonId, 3)) &&
        !hasGame3Prerequisites) {
      throw const FormatException('Play-In Game 3 lacks prerequisites');
    }
    final game3IdentityPresent =
        thirdIdentity.homeTeamId != null &&
        thirdIdentity.awayTeamId != null &&
        thirdIdentity.gameSeed != null;
    if (game3IdentityPresent != hasGame3Prerequisites ||
        (!game3IdentityPresent &&
            (thirdIdentity.homeTeamId != null ||
                thirdIdentity.awayTeamId != null ||
                thirdIdentity.gameSeed != null))) {
      throw const FormatException(
        'Play-In Game 3 identity/prerequisites disagree',
      );
    }
    final expectedIds = {
      _gameId(seasonId, 1),
      _gameId(seasonId, 2),
      _gameId(seasonId, 3),
    };
    if (gameResults.keys.any((id) => !expectedIds.contains(id))) {
      throw const FormatException('Unknown Play-In result identity');
    }
    final referencedSnapshots = <String>{};
    for (final entry in gameResults.entries) {
      final result = entry.value;
      if (result.fixtureId != entry.key ||
          result.seasonId != seasonId ||
          result.seasonYear != seasonYear ||
          result.inputEvidence == null) {
        throw const FormatException('Play-In result identity mismatch');
      }
      referencedSnapshots.add(result.inputEvidence!.leagueSnapshotId);
    }
    if (referencedSnapshots.length != gameInputSnapshots.length ||
        !referencedSnapshots.containsAll(gameInputSnapshots.keys)) {
      throw const FormatException(
        'Play-In snapshots are missing or unreferenced',
      );
    }
    if (regularSeasonState != null) {
      if (regularSeasonState.schedule == null ||
          regularSeasonState.seasonId != seasonId ||
          regularSeasonState.seasonYear != seasonYear ||
          originalRanking
              .toSet()
              .difference(
                regularSeasonState.openingTeams
                    .map((team) => team.teamId)
                    .toSet(),
              )
              .isNotEmpty ||
          regularSeasonState.openingTeams
              .map((team) => team.teamId)
              .toSet()
              .difference(originalRanking.toSet())
              .isNotEmpty) {
        throw const FormatException(
          'Play-In identity differs from regular season',
        );
      }
      if (regularSeasonState.schedule!.allFixtures.any(
        (fixture) => expectedIds.contains(fixture.id),
      )) {
        throw const FormatException(
          'Play-In fixture ID collides with regular season',
        );
      }
      final ranking = PlayInRanking.rank(regularSeasonState);
      if (!_sameTeams(ranking, originalRanking)) {
        throw const FormatException('Frozen Play-In ranking mismatch');
      }
      final scheduleSeeds = {
        for (final fixture in regularSeasonState.schedule!.allFixtures)
          _normalizedSeed(fixture.gameSeed),
      };
      final sortedIds = originalRanking.map((id) => id.value).toList()..sort();
      int teamIndex(TeamId id) {
        final index = sortedIds.indexOf(id.value);
        if (index < 0 || index >= 30) {
          throw const FormatException('Play-In team index is outside 0..29');
        }
        return index;
      }

      final playInSeeds = <int>{};
      void addSeed(TeamId home, TeamId away, int rematchIndex) {
        if (home == away || rematchIndex < 83 || rematchIndex > 85) {
          throw const FormatException('Invalid Play-In seed inputs');
        }
        final seed = _normalizedSeed(
          deriveGameSeed(
            leagueSeed: regularSeasonState.scheduleSeed,
            homeIndex: teamIndex(home),
            awayIndex: teamIndex(away),
            rematchIndex: rematchIndex,
          ),
        );
        if (scheduleSeeds.contains(seed) || !playInSeeds.add(seed)) {
          throw const FormatException('Play-In game seed collision');
        }
      }

      addSeed(originalRanking[14], originalRanking[15], 83);
      addSeed(originalRanking[16], originalRanking[17], 84);
      for (final game1Loser in originalRanking.skip(14).take(2)) {
        for (final game2Winner in originalRanking.skip(16).take(2)) {
          addSeed(game1Loser, game2Winner, 85);
        }
      }
      final seedSet = <int>{};
      for (var gameNumber = 1; gameNumber <= _playInGameCount; gameNumber++) {
        final game = fixture(
          gameNumber: gameNumber,
          scheduleSeed: regularSeasonState.scheduleSeed,
        );
        final result = gameResults[_gameId(seasonId, gameNumber)];
        if (result == null) continue;
        if (game == null || !seedSet.add(game.gameSeed)) {
          throw const FormatException('Invalid or duplicate Play-In game seed');
        }
        _validateResult(result, game, regularSeasonState);
        if (gameNumber == 3) {
          final firstLoser = _loser(gameResults[_gameId(seasonId, 1)]!);
          final secondWinner =
              gameResults[_gameId(seasonId, 2)]!.summary.winnerTeamId;
          if (game.homeTeamId != firstLoser ||
              game.awayTeamId != secondWinner) {
            throw const FormatException(
              'Play-In Game 3 participants are invalid',
            );
          }
        }
      }
      if (gameResults.containsKey(_gameId(seasonId, 1)) &&
          gameResults.containsKey(_gameId(seasonId, 2)) &&
          fixture(
                gameNumber: 3,
                scheduleSeed: regularSeasonState.scheduleSeed,
              ) ==
              null) {
        throw const FormatException('Play-In Game 3 fixture is missing');
      }
      if (isComplete &&
          qualifiedTeams.map((entry) => entry.$2).toSet().length != 16) {
        throw const FormatException('Play-In qualification is not unique');
      }
    }
  }

  void _validateResult(
    RegularSeasonGameResult result,
    PlayInFixture fixture,
    RegularSeasonState regularSeasonState,
  ) {
    final evidence = result.inputEvidence!;
    final snapshotJson = gameInputSnapshots[evidence.leagueSnapshotId]!;
    final historicalLeague = RegularSeasonGameInputEvidence.parseLeagueSnapshot(
      snapshotId: evidence.leagueSnapshotId,
      leagueSnapshotJson: snapshotJson,
      openingTeamIds: {
        for (final team in regularSeasonState.openingTeams) team.teamId.value,
      },
    );
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
    final players = <String>{};
    final teams = <String, String>{};
    for (final team in historicalInput.league.teams) {
      if (team.id != fixture.homeTeamId && team.id != fixture.awayTeamId) {
        continue;
      }
      for (final player in team.players) {
        players.add(player.id.value);
        teams[player.id.value] = team.id.value;
      }
    }
    result.validateForIdentity(
      fixtureId: fixture.id,
      fixtureSeasonId: seasonId,
      fixtureSeasonYear: seasonYear,
      expectedSeasonId: seasonId,
      expectedSeasonYear: seasonYear,
      expectedHomeTeamId: fixture.homeTeamId,
      expectedAwayTeamId: fixture.awayTeamId,
      expectedGameSeed: fixture.gameSeed,
      standardPlayers: players,
      playerTeams: teams,
    );
  }

  Map<String, Object?> toJson() => {
    'seasonId': seasonId,
    'seasonYear': seasonYear,
    'originalRanking': [for (final id in originalRanking) id.value],
    'rankingRuleset': rankingRuleset,
    'gameIdentities': [for (final game in gameIdentities) game.toJson()],
    'gameResults': {
      for (final entry in gameResults.entries) entry.key: entry.value.toJson(),
    },
    'gameInputSnapshots': gameInputSnapshots,
  };
}

final class PlayInRanking {
  const PlayInRanking._();

  static List<TeamId> rank(RegularSeasonState state) {
    final schedule = state.schedule;
    if (schedule == null ||
        state.completedRounds != 82 ||
        state.completedGames != 1230) {
      throw const FormatException(
        'Play-In ranking requires a completed regular season',
      );
    }
    final ordinalById = <String, int>{};
    for (final team in state.openingTeams) {
      final match = RegExp(
        r'^team-([1-9]|[12][0-9]|30)$',
      ).firstMatch(team.teamId.value);
      final ordinal = int.tryParse(match?.group(1) ?? '');
      if (ordinal == null || ordinalById.containsValue(ordinal)) {
        throw const FormatException(
          'Unsupported or duplicate generated team ID',
        );
      }
      ordinalById[team.teamId.value] = ordinal;
    }
    if (ordinalById.length != 30 ||
        !ordinalById.values.toSet().containsAll(
          List.generate(30, (i) => i + 1),
        )) {
      throw const FormatException(
        'Generated team IDs must cover team-1 through team-30',
      );
    }
    final standings = state.standings;
    final teamsByWins = <int, List<TeamId>>{};
    for (final standing in standings.table.values) {
      teamsByWins.putIfAbsent(standing.wins, () => []).add(standing.teamId);
    }
    final headToHeadWins = <(String, String, String), int>{};
    for (final round in schedule.rounds) {
      for (final fixture in round.fixtures) {
        final result = state.gameResults[fixture.id];
        if (result == null) continue;
        final key = _pair(fixture.homeTeamId.value, fixture.awayTeamId.value);
        if (result.summary.winnerTeamId.value == fixture.homeTeamId.value ||
            result.summary.winnerTeamId.value == fixture.awayTeamId.value) {
          final winnerKey = (key.$1, key.$2, result.summary.winnerTeamId.value);
          headToHeadWins[(winnerKey.$1, winnerKey.$2, winnerKey.$3)] =
              (headToHeadWins[(winnerKey.$1, winnerKey.$2, winnerKey.$3)] ??
                  0) +
              1;
        }
      }
    }
    int headToHead(TeamId team, TeamId opponent) {
      final key = _pair(team.value, opponent.value);
      return headToHeadWins[(key.$1, key.$2, team.value)] ?? 0;
    }

    final ranked = standings.table.values.toList();
    ranked.sort((a, b) {
      final byWins = b.wins.compareTo(a.wins);
      if (byWins != 0) return byWins;
      final tiedGroup = teamsByWins[a.wins]!;
      if (tiedGroup.length == 2) {
        final byHeadToHead = headToHead(
          b.teamId,
          a.teamId,
        ).compareTo(headToHead(a.teamId, b.teamId));
        if (byHeadToHead != 0) return byHeadToHead;
      }
      final byDifferential = b.pointDifferential.compareTo(a.pointDifferential);
      if (byDifferential != 0) return byDifferential;
      final byPoints = b.pointsFor.compareTo(a.pointsFor);
      if (byPoints != 0) return byPoints;
      return ordinalById[a.teamId.value]!.compareTo(
        ordinalById[b.teamId.value]!,
      );
    });
    return List.unmodifiable(ranked.map((standing) => standing.teamId));
  }

  static (String, String) _pair(String first, String second) =>
      first.compareTo(second) < 0 ? (first, second) : (second, first);
}

bool _sameTeams(List<TeamId> first, List<TeamId> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

int _normalizedSeed(int seed) => seed == 0 ? 0x9E3779B9 : seed;
