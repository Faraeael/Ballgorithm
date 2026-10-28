import '../models/league.dart';
import '../models/player.dart';
import '../models/position.dart';
import 'validation_result.dart';

/// League-wide invariants that no single entity can check in isolation.
/// Used for generated leagues, decoded snapshots and tests.
abstract final class LeagueValidator {
  static ValidationResult validate(League league) {
    final issues = <ValidationIssue>[];
    final config = league.config;

    if (league.teams.length != config.teamCount) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.teamCountMismatch,
          path: 'teams',
          message:
              'expected ${config.teamCount} teams, got ${league.teams.length}',
        ),
      );
    }

    final seenPlayerIds = <String, int>{};
    for (var t = 0; t < league.teams.length; t++) {
      final team = league.teams[t];
      final roster = team.roster;
      final rosterPath = 'teams[$t].roster';

      if (roster.size != config.playersPerTeam) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.rosterSizeMismatch,
            path: rosterPath,
            message:
                'team ${team.id.value} has ${roster.size} players, '
                'expected ${config.playersPerTeam}',
          ),
        );
      }

      for (final position in Position.values) {
        if (!roster.covers(position)) {
          issues.add(
            ValidationIssue(
              code: ValidationCode.positionCoverageMissing,
              path: rosterPath,
              message: 'team ${team.id.value} has no ${position.shortName}',
            ),
          );
        }
      }

      for (var p = 0; p < roster.players.length; p++) {
        final player = roster.players[p];
        final playerPath = '$rosterPath.players[$p]';
        _checkPlayerFields(player, playerPath, issues);
        final previousTeam = seenPlayerIds[player.id.value];
        if (previousTeam != null) {
          issues.add(
            ValidationIssue(
              code: ValidationCode.duplicatePlayerAcrossTeams,
              path: playerPath,
              message:
                  'player ${player.id.value} appears in teams '
                  '$previousTeam and $t',
            ),
          );
        } else {
          seenPlayerIds[player.id.value] = t;
        }
      }
    }

    return ValidationResult(issues);
  }

  static void _checkPlayerFields(
    Player player,
    String path,
    List<ValidationIssue> issues,
  ) {
    if (player.id.value.trim().isEmpty) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.playerIdEmpty,
          path: path,
          message: 'player id must not be empty',
        ),
      );
    }
    if (player.fullName.isEmpty) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.playerNameEmpty,
          path: path,
          message: 'player name must not be empty',
        ),
      );
    }
    for (final entry in player.attributes.asMap.entries) {
      final value = entry.value;
      if (value < 0 || value > 100) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.attributeOutOfRange,
            path: '$path.attributes.${entry.key}',
            message: '${entry.key} must be 0..100, got $value',
          ),
        );
      }
    }
  }
}
