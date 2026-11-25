import '../models/ids.dart';
import '../models/player.dart';
import '../models/position.dart';
import '../models/team.dart';
import '../simulation/court_lineup.dart';
import '../simulation/game_input.dart';
import '../simulation/game_rules.dart';
import '../simulation/game_validation.dart';
import '../simulation/rotation_plan.dart';
import 'career_rotation_settings.dart';
import 'gm_career.dart';
import 'regular_season_game_adapter.dart';

/// Why a manual plan does not resolve against the current standard roster.
enum CareerRotationIssueCode {
  /// A saved starter is no longer on the standard roster.
  starterUnavailable,

  /// A player with positive custom seconds is no longer on the standard roster.
  targetPlayerUnavailable,

  /// The M005 lineup/plan validation rejected the resolved plan; see
  /// [CareerRotationIssue.validationCode].
  planInvalid,
}

final class CareerRotationIssue {
  const CareerRotationIssue({
    required this.code,
    required this.message,
    this.playerId,
    this.slot,
    this.seconds,
    this.validationCode,
  });

  final CareerRotationIssueCode code;
  final String message;
  final PlayerId? playerId;
  final Position? slot;
  final int? seconds;
  final GameValidationCode? validationCode;

  @override
  String toString() => '${code.name}: $message';
}

/// The lineup and plan for one team side, or the reasons it cannot be built.
final class CareerRotationResolution {
  const CareerRotationResolution({
    this.lineup,
    this.plan,
    this.issues = const [],
    this.unassignedPlayerIds = const [],
  });

  final CourtLineup? lineup;
  final TeamRotationPlan? plan;
  final List<CareerRotationIssue> issues;

  /// Standard players absent from a custom plan (new since the last edit).
  /// They play 0 s and are informational, not blocking.
  final List<PlayerId> unassignedPlayerIds;

  bool get isValid => issues.isEmpty;
}

/// A deterministic, unapplied repair of an obsolete manual plan.
final class CareerRotationRepairProposal {
  const CareerRotationRepairProposal({
    required this.settings,
    required this.remainingIssues,
  });

  final CareerRotationSettings settings;

  /// Issues the repair cannot fix without redistributing custom seconds.
  final List<CareerRotationIssue> remainingIssues;

  bool get isApplicable => remainingIssues.isEmpty;
}

/// Thrown when a manual plan cannot be used for a simulation or entry.
final class CareerRotationInvalidException implements Exception {
  CareerRotationInvalidException(List<CareerRotationIssue> issues)
    : issues = List.unmodifiable(issues);

  final List<CareerRotationIssue> issues;

  @override
  String toString() =>
      'Manual rotation is invalid: ${issues.map((i) => i.message).join('; ')}';
}

/// Resolves the human franchise's persisted preferences into the existing
/// M005 lineup and plan contracts. Pure, deterministic, no randomness.
abstract final class CareerRotationService {
  /// The current automatic behaviour: first player per primary position in
  /// roster order plus the balanced preset. AI teams always use this.
  static ({CourtLineup lineup, TeamRotationPlan plan}) automaticFor(
    Team standardTeam, {
    GameRules? rules,
  }) {
    final effectiveRules = rules ?? GameRules.standard;
    final lineup = CourtLineup.defaultFor(standardTeam);
    final plan = TeamRotationPlan.create(
      team: standardTeam,
      preset: RotationPreset.balanced,
      targets: [
        for (final entry in RotationPlan.expandPreset(
          preset: RotationPreset.balanced,
          team: standardTeam,
          lineup: lineup,
          rules: effectiveRules,
        ).entries)
          RotationTarget(playerId: entry.key, seconds: entry.value),
      ],
    );
    return (lineup: lineup, plan: plan);
  }

  /// Resolves [settings] against [standardTeam] (standard roster only, in
  /// canonical roster order, as used for career game inputs).
  static CareerRotationResolution resolve(
    CareerRotationSettings settings,
    Team standardTeam, {
    GameRules? rules,
  }) {
    final effectiveRules = rules ?? GameRules.standard;
    if (!settings.isManual) {
      final auto = automaticFor(standardTeam, rules: effectiveRules);
      return CareerRotationResolution(lineup: auto.lineup, plan: auto.plan);
    }
    final byId = {
      for (final player in standardTeam.players) player.id.value: player,
    };
    final issues = <CareerRotationIssue>[];
    for (var index = 0; index < settings.starters.length; index++) {
      final id = settings.starters[index];
      if (!byId.containsKey(id.value)) {
        final slot = Position.values[index];
        issues.add(
          CareerRotationIssue(
            code: CareerRotationIssueCode.starterUnavailable,
            playerId: id,
            slot: slot,
            message:
                '${slot.shortName} starter ${id.value} is not on the standard '
                'roster',
          ),
        );
      }
    }
    final isCustom = settings.preset == RotationPreset.custom;
    final unassigned = <PlayerId>[];
    if (isCustom) {
      for (final entry in settings.customTargets.entries) {
        if (entry.value > 0 && !byId.containsKey(entry.key)) {
          issues.add(
            CareerRotationIssue(
              code: CareerRotationIssueCode.targetPlayerUnavailable,
              playerId: PlayerId(entry.key),
              seconds: entry.value,
              message:
                  '${entry.key} has ${entry.value} s assigned but is not on '
                  'the standard roster',
            ),
          );
        }
      }
      for (final player in standardTeam.players) {
        if (!settings.customTargets.containsKey(player.id.value)) {
          unassigned.add(player.id);
        }
      }
    }
    if (issues.isNotEmpty) {
      return CareerRotationResolution(
        issues: issues,
        unassignedPlayerIds: unassigned,
      );
    }
    try {
      final lineup = CourtLineup.create(
        team: standardTeam,
        slotOrderedPlayers: [
          for (final id in settings.starters) byId[id.value]!,
        ],
      );
      final Map<PlayerId, int> seconds = isCustom
          ? {
              for (final player in standardTeam.players)
                player.id: settings.customTargets[player.id.value] ?? 0,
            }
          : RotationPlan.expandPreset(
              preset: settings.preset,
              team: standardTeam,
              lineup: lineup,
              rules: effectiveRules,
            );
      final plan = TeamRotationPlan.create(
        team: standardTeam,
        preset: settings.preset,
        targets: [
          for (final player in standardTeam.players)
            RotationTarget(playerId: player.id, seconds: seconds[player.id]!),
        ],
      );
      GameInput.validateLineupAndPlan(
        team: standardTeam,
        lineup: lineup,
        plan: plan,
        rules: effectiveRules,
      );
      return CareerRotationResolution(
        lineup: lineup,
        plan: plan,
        unassignedPlayerIds: unassigned,
      );
    } on GameValidationException catch (error) {
      return CareerRotationResolution(
        issues: [
          for (final issue in error.issues)
            CareerRotationIssue(
              code: CareerRotationIssueCode.planInvalid,
              validationCode: issue.code,
              message: '${issue.code.name}: ${issue.message}',
            ),
        ],
        unassignedPlayerIds: unassigned,
      );
    }
  }

  /// Resolves the career's saved preferences for the human franchise.
  static CareerRotationResolution resolveForCareer(GmCareer career) => resolve(
    career.userRotation,
    RegularSeasonGameAdapter.standardTeamFor(career.userTeam),
  );

  /// Proposes a deterministic repair for an obsolete manual plan without
  /// applying it. Returns `null` when there is nothing to repair.
  ///
  /// Unavailable starters are replaced by the first standard non-starter whose
  /// primary position matches the slot, else the first standard non-starter,
  /// in roster order. Departed players' custom targets are dropped; custom
  /// seconds are never redistributed, so a resulting budget shortfall stays a
  /// remaining issue.
  static CareerRotationRepairProposal? proposeRepair(
    CareerRotationSettings settings,
    Team standardTeam, {
    GameRules? rules,
  }) {
    if (!settings.isManual) return null;
    final current = resolve(settings, standardTeam, rules: rules);
    if (current.isValid) return null;

    final rosterIds = {for (final p in standardTeam.players) p.id.value};
    final starters = <PlayerId?>[
      for (final id in settings.starters)
        rosterIds.contains(id.value) ? id : null,
    ];
    final taken = {
      for (final id in starters)
        if (id != null) id.value,
    };
    for (var index = 0; index < starters.length; index++) {
      if (starters[index] != null) continue;
      final slot = Position.values[index];
      final free = [
        for (final p in standardTeam.players)
          if (!taken.contains(p.id.value)) p,
      ];
      final Player? pick =
          free.where((p) => p.position == slot).firstOrNull ?? free.firstOrNull;
      if (pick == null) {
        return CareerRotationRepairProposal(
          settings: settings,
          remainingIssues: current.issues,
        );
      }
      starters[index] = pick.id;
      taken.add(pick.id.value);
    }
    final isCustom = settings.preset == RotationPreset.custom;
    final proposed = CareerRotationSettings.manual(
      starters: [for (final id in starters) id!],
      preset: settings.preset,
      customTargets: isCustom
          ? {
              for (final entry in settings.customTargets.entries)
                if (rosterIds.contains(entry.key)) entry.key: entry.value,
            }
          : null,
    );
    return CareerRotationRepairProposal(
      settings: proposed,
      remainingIssues: resolve(proposed, standardTeam, rules: rules).issues,
    );
  }
}
