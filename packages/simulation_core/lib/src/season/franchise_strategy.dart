import '../models/ids.dart';
import '../models/team.dart';
import '../simulation/court_lineup.dart';
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

    final presetName = json['rotationPreset'] as String? ?? 'balanced';
    final preset = RotationPreset.values.firstWhere(
      (p) => p.name == presetName,
      orElse: () => RotationPreset.balanced,
    );

    final targetsMap = (json['rotationTargets'] as Map?)?.cast<String, int>();
    final List<RotationTarget> targets;
    if (targetsMap != null && targetsMap.isNotEmpty) {
      targets = [
        for (final p in team.players)
          RotationTarget(playerId: p.id, seconds: targetsMap[p.id.value] ?? 0),
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

  Map<String, dynamic> toJson() => {
    'teamId': teamId.value,
    'startingLineup': startingLineup.playerIds,
    'rotationTargets': {
      for (final entry in teamPlan.targetSeconds.entries)
        entry.key.value: entry.value,
    },
  };
}
