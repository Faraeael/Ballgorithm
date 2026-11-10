import '../models/ids.dart';
import '../models/team.dart';
import '../simulation/court_lineup.dart';
import '../simulation/game_input.dart';
import '../simulation/game_rules.dart';
import '../simulation/rotation_plan.dart';

final class FranchiseStrategy {
  const FranchiseStrategy({
    required this.teamId,
    required this.startingLineup,
    required this.rotationPlan,
  });

  factory FranchiseStrategy.defaultFor(Team team, {GameRules? rules}) {
    final lineup = CourtLineup.defaultFor(team);
    final effectiveRules = rules ?? GameRules.standard;
    final targets = RotationPlan.expandPreset(
      preset: RotationPreset.balanced,
      team: team,
      lineup: lineup,
      rules: effectiveRules,
    );
    final teamPlan = TeamRotationPlan.create(
      team: team,
      preset: RotationPreset.balanced,
      targets: [
        for (final p in team.players)
          RotationTarget(playerId: p.id, seconds: targets[p.id]!),
      ],
    );
    return FranchiseStrategy(
      teamId: team.id,
      startingLineup: lineup,
      rotationPlan: RotationPlan(home: teamPlan, away: teamPlan),
    );
  }

  factory FranchiseStrategy.fromJson(
    Map<String, dynamic> json,
    Team team, {
    GameRules? rules,
  }) {
    final effectiveRules = rules ?? GameRules.standard;
    final teamId = TeamId(json['teamId'] as String);
    if (teamId != team.id) {
      throw ArgumentError.value(
        teamId.value,
        'teamId',
        'Strategy team ID does not match provided team ${team.id.value}',
      );
    }

    final lineupPlayerIds = (json['startingLineup'] as List).cast<String>();
    final slotOrderedPlayers = [
      for (final id in lineupPlayerIds)
        team.players.firstWhere((p) => p.id.value == id),
    ];
    final lineup = CourtLineup.create(
      team: team,
      slotOrderedPlayers: slotOrderedPlayers,
    );

    final rawPresetName = json['rotationPreset'] as String?;
    final targetsMap = (json['rotationTargets'] as Map?)?.cast<String, int>();

    final RotationPreset preset;
    final List<RotationTarget> targets;

    if (rawPresetName != null) {
      // Explicit preset recorded
      preset = RotationPreset.values.firstWhere(
        (p) => p.name == rawPresetName,
        orElse: () => RotationPreset.custom,
      );

      if (targetsMap != null && targetsMap.isNotEmpty) {
        targets = [
          for (final p in team.players)
            RotationTarget(
              playerId: p.id,
              seconds: targetsMap[p.id.value] ?? 0,
            ),
        ];
      } else {
        final expanded = RotationPlan.expandPreset(
          preset: preset,
          team: team,
          lineup: lineup,
          rules: effectiveRules,
        );
        targets = [
          for (final p in team.players)
            RotationTarget(playerId: p.id, seconds: expanded[p.id]!),
        ];
      }
    } else {
      // Legacy save without rotationPreset:
      // Derive preset safely from existing targets without losing custom configurations.
      final balancedExpanded = RotationPlan.expandPreset(
        preset: RotationPreset.balanced,
        team: team,
        lineup: lineup,
        rules: effectiveRules,
      );
      final startersExpanded = RotationPlan.expandPreset(
        preset: RotationPreset.starterHeavy,
        team: team,
        lineup: lineup,
        rules: effectiveRules,
      );

      final totalSeconds =
          targetsMap?.values.fold(0, (sum, sec) => sum + sec) ?? 0;
      final expectedTotal = RotationPlan.regulationTeamTotal(effectiveRules);

      var matchesBalanced =
          targetsMap != null && targetsMap.length == team.players.length;
      if (matchesBalanced) {
        for (final p in team.players) {
          if (targetsMap[p.id.value] != balancedExpanded[p.id]) {
            matchesBalanced = false;
            break;
          }
        }
      }

      var matchesStarters =
          targetsMap != null && targetsMap.length == team.players.length;
      if (matchesStarters) {
        for (final p in team.players) {
          if (targetsMap[p.id.value] != startersExpanded[p.id]) {
            matchesStarters = false;
            break;
          }
        }
      }

      if (matchesBalanced) {
        preset = RotationPreset.balanced;
        targets = [
          for (final p in team.players)
            RotationTarget(playerId: p.id, seconds: balancedExpanded[p.id]!),
        ];
      } else if (matchesStarters) {
        preset = RotationPreset.starterHeavy;
        targets = [
          for (final p in team.players)
            RotationTarget(playerId: p.id, seconds: startersExpanded[p.id]!),
        ];
      } else if (targetsMap != null && totalSeconds == expectedTotal) {
        // Valid custom targets (e.g. user adjusted minutes or legacy starter swap):
        // Preserve as Custom rotation plan
        preset = RotationPreset.custom;
        targets = [
          for (final p in team.players)
            RotationTarget(
              playerId: p.id,
              seconds: targetsMap[p.id.value] ?? 0,
            ),
        ];
      } else {
        // Fallback: repair corrupted/empty legacy targets safely to Balanced
        preset = RotationPreset.balanced;
        targets = [
          for (final p in team.players)
            RotationTarget(playerId: p.id, seconds: balancedExpanded[p.id]!),
        ];
      }
    }

    final teamPlan = TeamRotationPlan.create(
      team: team,
      preset: preset,
      targets: targets,
    );
    return FranchiseStrategy(
      teamId: teamId,
      startingLineup: lineup,
      rotationPlan: RotationPlan(home: teamPlan, away: teamPlan),
    );
  }

  final TeamId teamId;
  final CourtLineup startingLineup;
  final RotationPlan rotationPlan;

  TeamRotationPlan get teamPlan => rotationPlan.home;

  void validate({required Team team, GameRules? rules}) {
    final effectiveRules = rules ?? GameRules.standard;
    GameInput.validateLineupAndPlan(
      team: team,
      lineup: startingLineup,
      plan: teamPlan,
      rules: effectiveRules,
    );
  }

  Map<String, dynamic> toJson() => {
    'teamId': teamId.value,
    'startingLineup': startingLineup.playerIds,
    'rotationPreset': teamPlan.preset.name,
    'rotationTargets': {
      for (final entry in teamPlan.targetSeconds.entries)
        entry.key.value: entry.value,
    },
  };
}
