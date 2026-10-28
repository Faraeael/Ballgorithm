import '../domain_versions.dart';
import '../validation/league_validator.dart';
import '../validation/validation_result.dart';
import 'generation_config.dart';
import 'ids.dart';
import 'player.dart';
import 'roster.dart';
import 'team.dart';

/// Aggregate root. Construct with [League.create] so league-wide rules
/// (counts, position coverage, cross-team player uniqueness) are enforced.
final class League {
  League._({
    required this.id,
    required this.name,
    required this.config,
    required List<Team> teams,
  }) : teams = List.unmodifiable(teams) {
    final issues = <ValidationIssue>[];
    if (id.value.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.leagueIdEmpty,
          path: 'league.id',
          message: 'league id must not be empty',
        ),
      );
    }
    if (name.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.leagueNameEmpty,
          path: 'league.name',
          message: 'league name must not be empty',
        ),
      );
    }
    final teamIds = <String>{};
    for (final team in this.teams) {
      if (!teamIds.add(team.id.value)) {
        issues.add(
          ValidationIssue(
            code: ValidationCode.duplicateTeamId,
            path: 'teams',
            message: 'duplicate team id ${team.id.value}',
          ),
        );
      }
    }
    ValidationResult(issues).throwIfInvalid();
  }

  factory League.create({
    required LeagueId id,
    required String name,
    required GenerationConfig config,
    required List<Team> teams,
  }) {
    config.validateForEngine().throwIfInvalid();
    final league = League._(id: id, name: name, config: config, teams: teams);
    LeagueValidator.validate(league).throwIfInvalid();
    return league;
  }

  factory League.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != snapshotSchemaVersion) {
      throw DomainValidationException([
        ValidationIssue(
          code: ValidationCode.unsupportedSchemaVersion,
          path: 'schemaVersion',
          message:
              'expected schemaVersion $snapshotSchemaVersion, got $schemaVersion',
        ),
      ]);
    }
    final rawId = json['id'];
    final rawName = json['name'];
    final rawGeneration = json['generation'];
    final rawTeams = json['teams'];
    if (rawId is! String ||
        rawName is! String ||
        rawGeneration is! Map<String, Object?> ||
        rawTeams is! List<Object?>) {
      throw DomainValidationException(const [
        ValidationIssue(
          code: ValidationCode.malformedJson,
          path: 'league',
          message:
              'league requires string id, name, generation map and team list',
        ),
      ]);
    }
    final teams = <Team>[];
    for (var t = 0; t < rawTeams.length; t++) {
      final rawTeam = rawTeams[t];
      if (rawTeam is! Map<String, Object?>) {
        throw DomainValidationException([
          ValidationIssue(
            code: ValidationCode.malformedJson,
            path: 'teams[$t]',
            message: 'team must be an object',
          ),
        ]);
      }
      final rawTeamId = rawTeam['id'];
      final rawTeamName = rawTeam['name'];
      final rawAbbreviation = rawTeam['abbreviation'];
      if (rawTeamId is! String ||
          rawTeamName is! String ||
          rawAbbreviation is! String) {
        throw DomainValidationException([
          ValidationIssue(
            code: ValidationCode.malformedJson,
            path: 'teams[$t]',
            message: 'team requires string id, name and abbreviation',
          ),
        ]);
      }
      final rawRoster = rawTeam['roster'];
      final rawPlayers = rawRoster is Map<String, Object?>
          ? rawRoster['players']
          : null;
      if (rawPlayers is! List<Object?>) {
        throw DomainValidationException([
          ValidationIssue(
            code: ValidationCode.malformedJson,
            path: 'teams[$t].roster.players',
            message: 'roster requires a player list',
          ),
        ]);
      }
      final players = <Player>[];
      for (var p = 0; p < rawPlayers.length; p++) {
        final rawPlayer = rawPlayers[p];
        if (rawPlayer is! Map<String, Object?>) {
          throw DomainValidationException([
            ValidationIssue(
              code: ValidationCode.malformedJson,
              path: 'teams[$t].roster.players[$p]',
              message: 'player must be an object',
            ),
          ]);
        }
        players.add(
          Player.fromJson(rawPlayer, path: 'teams[$t].roster.players[$p]'),
        );
      }
      teams.add(
        Team(
          id: TeamId(rawTeamId),
          name: rawTeamName,
          abbreviation: rawAbbreviation,
          roster: Roster(players),
        ),
      );
    }
    return League.create(
      id: LeagueId(rawId),
      name: rawName,
      config: GenerationConfig.fromJson(rawGeneration),
      teams: teams,
    );
  }

  final LeagueId id;
  final String name;
  final GenerationConfig config;
  final List<Team> teams;

  Map<String, Object?> toJson() => {
    'schemaVersion': snapshotSchemaVersion,
    'engineVersion': coreEngineVersion,
    'generation': config.toJson(),
    'id': id.value,
    'name': name,
    'teams': [for (final team in teams) team.toJson()],
  };
}
