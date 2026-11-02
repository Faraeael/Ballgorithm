import '../models/ids.dart';
import '../models/league.dart';
import '../models/team.dart';
import 'court_lineup.dart';
import 'game_rules.dart';
import 'game_validation.dart';

/// Validated inputs for one deterministic game.
final class GameInput {
  GameInput._({
    required this.gameId,
    required this.league,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.homeLineup,
    required this.awayLineup,
    required this.seed,
    required this.rules,
  });

  factory GameInput.create({
    required String gameId,
    required League league,
    required TeamId homeTeamId,
    required TeamId awayTeamId,
    required CourtLineup homeLineup,
    required CourtLineup awayLineup,
    required int seed,
    required GameRules rules,
  }) {
    final issues = <GameValidationIssue>[];
    if (gameId.trim().isEmpty) {
      issues.add(
        const GameValidationIssue(
          code: GameValidationCode.emptyGameId,
          path: 'gameId',
          message: 'gameId must not be empty',
        ),
      );
    }
    if (homeTeamId == awayTeamId) {
      issues.add(
        const GameValidationIssue(
          code: GameValidationCode.teamsNotDistinct,
          path: 'teams',
          message: 'home and away teams must differ',
        ),
      );
    }
    final homeTeam = _team(league, homeTeamId);
    final awayTeam = _team(league, awayTeamId);
    if (homeTeam == null) {
      issues.add(
        GameValidationIssue(
          code: GameValidationCode.teamNotFound,
          path: 'homeTeamId',
          message: 'team ${homeTeamId.value} is not in the league',
        ),
      );
    }
    if (awayTeam == null) {
      issues.add(
        GameValidationIssue(
          code: GameValidationCode.teamNotFound,
          path: 'awayTeamId',
          message: 'team ${awayTeamId.value} is not in the league',
        ),
      );
    }
    if (homeTeam != null) {
      _checkOwnership(homeTeam, homeLineup, 'homeLineup', issues);
    }
    if (awayTeam != null) {
      _checkOwnership(awayTeam, awayLineup, 'awayLineup', issues);
    }
    final overlap = homeLineup.playerIds.toSet()
      ..retainAll(awayLineup.playerIds);
    if (overlap.isNotEmpty) {
      issues.add(
        GameValidationIssue(
          code: GameValidationCode.duplicatePlayerAcrossLineups,
          path: 'lineups',
          message: 'players appear on both lineups: ${overlap.join(', ')}',
        ),
      );
    }
    try {
      rules.validate();
    } on GameValidationException catch (error) {
      issues.addAll(error.issues);
    }
    if (issues.isNotEmpty) throw GameValidationException(issues);
    return GameInput._(
      gameId: gameId,
      league: league,
      homeTeamId: homeTeamId,
      awayTeamId: awayTeamId,
      homeLineup: homeLineup,
      awayLineup: awayLineup,
      seed: seed,
      rules: rules,
    );
  }

  final String gameId;
  final League league;
  final TeamId homeTeamId;
  final TeamId awayTeamId;
  final CourtLineup homeLineup;
  final CourtLineup awayLineup;
  final int seed;
  final GameRules rules;

  Team get homeTeam => _team(league, homeTeamId)!;
  Team get awayTeam => _team(league, awayTeamId)!;

  int get normalizedSeed {
    final masked = seed & 0xFFFFFFFF;
    return masked == 0 ? 0x9E3779B9 : masked;
  }

  bool get homeStarts => normalizedSeed.isEven;

  TeamId get startingTeamId => homeStarts ? homeTeamId : awayTeamId;

  TeamId opponentOf(TeamId teamId) =>
      teamId == homeTeamId ? awayTeamId : homeTeamId;

  CourtLineup lineupFor(TeamId teamId) =>
      teamId == homeTeamId ? homeLineup : awayLineup;

  /// True when the player is in the immutable **starting** lineup.
  ///
  /// This is not current eligibility: replay tracks the active five from
  /// substitutions. Named explicitly so callers cannot confuse the two.
  bool isStartingPlayer(TeamId teamId, PlayerId playerId) =>
      lineupFor(teamId).containsPlayer(playerId);

  static Team? _team(League league, TeamId id) {
    for (final team in league.teams) {
      if (team.id == id) return team;
    }
    return null;
  }

  static void _checkOwnership(
    Team team,
    CourtLineup lineup,
    String path,
    List<GameValidationIssue> issues,
  ) {
    final rosterIds = {for (final player in team.players) player.id.value};
    for (var i = 0; i < lineup.slots.length; i++) {
      final playerId = lineup.slots[i].playerId;
      if (!rosterIds.contains(playerId.value)) {
        issues.add(
          GameValidationIssue(
            code: GameValidationCode.foreignLineupPlayer,
            path: '$path.slots[$i]',
            message:
                'player ${playerId.value} does not belong to '
                '${team.id.value}',
          ),
        );
      }
    }
  }
}
