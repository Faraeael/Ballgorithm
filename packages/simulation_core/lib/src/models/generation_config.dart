import '../domain_versions.dart';
import '../validation/validation_result.dart';

/// Inputs that fully determine generated output together with
/// [prngImplementationId] and [coreEngineVersion].
final class GenerationConfig {
  const GenerationConfig({
    this.seed = 1,
    this.teamCount = 8,
    this.playersPerTeam = 12,
    this.engineVersion = coreEngineVersion,
  });

  factory GenerationConfig.fromJson(Map<String, Object?> json) {
    final seed = json['seed'];
    final teamCount = json['teamCount'];
    final playersPerTeam = json['playersPerTeam'];
    final engineVersion = json['engineVersion'];
    if (seed is! int ||
        teamCount is! int ||
        playersPerTeam is! int ||
        engineVersion is! String) {
      throw DomainValidationException(const [
        ValidationIssue(
          code: ValidationCode.malformedJson,
          path: 'generation',
          message:
              'generation requires int seed, teamCount, playersPerTeam and string engineVersion',
        ),
      ]);
    }
    return GenerationConfig(
      seed: seed,
      teamCount: teamCount,
      playersPerTeam: playersPerTeam,
      engineVersion: engineVersion,
    );
  }

  static const int minTeamCount = 1;
  static const int maxTeamCount = 8;
  static const int minPlayersPerTeam = 5;

  final int seed;
  final int teamCount;
  final int playersPerTeam;
  final String engineVersion;

  ValidationResult validate() {
    final issues = <ValidationIssue>[];
    if (teamCount < minTeamCount || teamCount > maxTeamCount) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.teamCountOutOfRange,
          path: 'generation.teamCount',
          message:
              'teamCount must be $minTeamCount..$maxTeamCount, got $teamCount',
        ),
      );
    }
    if (playersPerTeam < minPlayersPerTeam) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.playersPerTeamOutOfRange,
          path: 'generation.playersPerTeam',
          message:
              'playersPerTeam must be >= $minPlayersPerTeam, got $playersPerTeam',
        ),
      );
    }
    if (engineVersion.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          code: ValidationCode.engineVersionEmpty,
          path: 'generation.engineVersion',
          message: 'engineVersion must not be empty',
        ),
      );
    }
    return ValidationResult(issues);
  }

  /// Field validation plus this build's engine-version compatibility policy:
  /// a config may only be used by the engine version it names.
  ValidationResult validateForEngine() {
    final issues = [...validate().issues];
    if (engineVersion.trim().isNotEmpty && engineVersion != coreEngineVersion) {
      issues.add(
        ValidationIssue(
          code: ValidationCode.engineVersionMismatch,
          path: 'generation.engineVersion',
          message:
              'generator implements $coreEngineVersion, '
              'config requested $engineVersion',
        ),
      );
    }
    return ValidationResult(issues);
  }

  Map<String, Object?> toJson() => {
    'seed': seed,
    'teamCount': teamCount,
    'playersPerTeam': playersPerTeam,
    'engineVersion': engineVersion,
    'prng': prngImplementationId,
  };
}
