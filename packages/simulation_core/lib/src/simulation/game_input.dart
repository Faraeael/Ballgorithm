import '../models/ids.dart';
import '../models/league.dart';
import '../models/team.dart';
import 'court_lineup.dart';
import 'game_rules.dart';
import 'game_validation.dart';
import 'rotation_plan.dart';

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
    this.rotationPlan,
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
    RotationPlan? rotationPlan,
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
    var rulesValid = true;
    try {
      rules.validate();
    } on GameValidationException catch (error) {
      rulesValid = false;
      issues.addAll(error.issues);
    }
    if (rulesValid &&
        rotationPlan != null &&
        homeTeam != null &&
        awayTeam != null) {
      _checkTeamPlan(
        rotationPlan.home,
        homeTeam,
        homeLineup,
        'rotationPlan.home',
        rules,
        issues,
      );
      _checkTeamPlan(
        rotationPlan.away,
        awayTeam,
        awayLineup,
        'rotationPlan.away',
        rules,
        issues,
      );
    }
    if (issues.isNotEmpty) throw GameValidationException(issues);
    return GameInput._(
      gameId: gameId,
      league: league,
      homeTeamId: homeTeamId,
      awayTeamId: awayTeamId,
      homeLineup: _canonicalLineup(league, homeTeam!, homeLineup),
      awayLineup: _canonicalLineup(league, awayTeam!, awayLineup),
      seed: seed,
      rules: rules,
      rotationPlan: rotationPlan == null
          ? null
          : RotationPlan(
              home: rotationPlan.home.canonicalizeFor(homeTeam),
              away: rotationPlan.away.canonicalizeFor(awayTeam),
            ),
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

  /// Optional playing-time plan. `null` preserves legacy no-rotation behavior.
  final RotationPlan? rotationPlan;

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

  /// Rebuilds a lineup from this league's roster so slot player references are
  /// the canonical objects covered by the input fingerprint.
  static CourtLineup _canonicalLineup(
    League league,
    Team team,
    CourtLineup supplied,
  ) {
    final rosterById = {
      for (final player in team.players) player.id.value: player,
    };
    return CourtLineup.create(
      team: team,
      slotOrderedPlayers: [
        for (final playerId in supplied.playerIds) rosterById[playerId]!,
      ],
    );
  }

  /// Validates that a starting lineup and rotation plan are compatible and legal
  /// under the given game rules.
  static void validateLineupAndPlan({
    required Team team,
    required CourtLineup lineup,
    required TeamRotationPlan plan,
    GameRules? rules,
  }) {
    final effectiveRules = rules ?? GameRules.standard;
    final issues = <GameValidationIssue>[];
    _checkOwnership(team, lineup, 'lineup', issues);
    _checkTeamPlan(plan, team, lineup, 'rotationPlan', effectiveRules, issues);
    if (issues.isNotEmpty) {
      throw GameValidationException(issues);
    }
  }

  static void _checkTeamPlan(
    TeamRotationPlan plan,
    Team team,
    CourtLineup lineup,
    String path,
    GameRules rules,
    List<GameValidationIssue> issues,
  ) {
    final rosterSize = team.players.length;
    if (rosterSize < 5) {
      issues.add(
        GameValidationIssue(
          code: GameValidationCode.invalidRosterSizeForRotation,
          path: path,
          message: 'rotation requires at least five players, got $rosterSize',
        ),
      );
      return;
    }

    final cap = RotationPlan.regulationCap(rules);
    final total = RotationPlan.regulationTeamTotal(rules);
    final rosterIds = {for (final player in team.players) player.id.value};
    final targetIds = {
      for (final playerId in plan.targetSeconds.keys) playerId.value,
    };
    for (final playerId in targetIds) {
      if (!rosterIds.contains(playerId)) {
        issues.add(
          GameValidationIssue(
            code: GameValidationCode.foreignRotationPlayer,
            path: path,
            message: 'player $playerId does not belong to ${team.id.value}',
          ),
        );
      }
    }
    for (final playerId in rosterIds) {
      if (!targetIds.contains(playerId)) {
        issues.add(
          GameValidationIssue(
            code: GameValidationCode.missingRotationPlayer,
            path: path,
            message: 'missing rotation target for $playerId',
          ),
        );
      }
    }

    var sum = 0;
    for (final entry in plan.targetSeconds.entries) {
      if (entry.value < 0 || entry.value > cap) {
        issues.add(
          GameValidationIssue(
            code: GameValidationCode.invalidRotationSeconds,
            path: path,
            message:
                'player ${entry.key.value} target ${entry.value} is outside '
                '0..$cap',
          ),
        );
      }
      sum += entry.value;
    }
    if (sum != total) {
      issues.add(
        GameValidationIssue(
          code: GameValidationCode.invalidRotationTotal,
          path: path,
          message: 'targets sum to $sum, expected $total',
        ),
      );
    }

    for (final playerId in lineup.playerIds) {
      if (plan.secondsFor(PlayerId(playerId)) <= 0) {
        issues.add(
          GameValidationIssue(
            code: GameValidationCode.starterTargetNotPositive,
            path: path,
            message: 'starter $playerId must have a positive target',
          ),
        );
      }
    }

    if (plan.preset != RotationPreset.custom) {
      final expanded = RotationPlan.expandPreset(
        preset: plan.preset,
        team: team,
        lineup: lineup,
        rules: rules,
      );
      var matches = expanded.length == plan.targetSeconds.length;
      if (matches) {
        for (final entry in expanded.entries) {
          if (plan.targetSeconds[entry.key] != entry.value) {
            matches = false;
            break;
          }
        }
      }
      if (!matches) {
        issues.add(
          GameValidationIssue(
            code: GameValidationCode.rotationPresetMismatch,
            path: path,
            message: 'targets do not match the ${plan.preset.jsonValue} preset',
          ),
        );
      }
    }
  }

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
