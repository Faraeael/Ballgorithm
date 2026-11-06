import '../models/ids.dart';
import '../models/team.dart';
import 'court_lineup.dart';
import 'game_rules.dart';
import 'game_validation.dart';

/// Frozen M005 rotation presets. Names are part of the canonical JSON.
enum RotationPreset {
  balanced('balanced'),
  starterHeavy('starterHeavy'),
  custom('custom');

  const RotationPreset(this.jsonValue);

  final String jsonValue;
}

/// One explicit integer-second target for a roster player.
final class RotationTarget {
  const RotationTarget({required this.playerId, required this.seconds});

  final PlayerId playerId;
  final int seconds;
}

/// One team's playing-time plan.
///
/// Structural identity is the preset plus canonical roster-ordered targets.
/// Construction only rejects foreign or duplicate players and negative
/// seconds; roster completeness, the exact team total, the per-player cap,
/// starter positivity and preset agreement are validated by `GameInput.create`
/// because they need the game rules and the starting lineup.
final class TeamRotationPlan {
  TeamRotationPlan._(this.preset, this.targetSeconds, this._rosterOrder);

  factory TeamRotationPlan.create({
    required Team team,
    required RotationPreset preset,
    required List<RotationTarget> targets,
  }) {
    final issues = <GameValidationIssue>[];
    final rosterIds = {for (final player in team.players) player.id.value};
    final seen = <String>{};
    for (var index = 0; index < targets.length; index++) {
      final target = targets[index];
      if (!rosterIds.contains(target.playerId.value)) {
        issues.add(
          GameValidationIssue(
            code: GameValidationCode.foreignRotationPlayer,
            path: 'rotationPlan.targets[$index].playerId',
            message:
                'player ${target.playerId.value} does not belong to '
                '${team.id.value}',
          ),
        );
      }
      if (!seen.add(target.playerId.value)) {
        issues.add(
          GameValidationIssue(
            code: GameValidationCode.duplicateRotationPlayer,
            path: 'rotationPlan.targets[$index].playerId',
            message: 'duplicate rotation target ${target.playerId.value}',
          ),
        );
      }
      if (target.seconds < 0) {
        issues.add(
          GameValidationIssue(
            code: GameValidationCode.invalidRotationSeconds,
            path: 'rotationPlan.targets[$index].seconds',
            message: 'seconds must not be negative, got ${target.seconds}',
          ),
        );
      }
    }
    if (issues.isNotEmpty) throw GameValidationException(issues);

    final targetSeconds = Map<PlayerId, int>.unmodifiable({
      for (final target in targets) target.playerId: target.seconds,
    });
    final rosterOrder = List<PlayerId>.unmodifiable([
      for (final player in team.players)
        if (targetSeconds.containsKey(player.id)) player.id,
    ]);
    return TeamRotationPlan._(preset, targetSeconds, rosterOrder);
  }

  final RotationPreset preset;
  final Map<PlayerId, int> targetSeconds;
  final List<PlayerId> _rosterOrder;

  int secondsFor(PlayerId playerId) => targetSeconds[playerId] ?? 0;

  /// Re-bases the plan on [team]'s canonical roster order, dropping keys the
  /// roster does not contain. `GameInput.create` uses this so a caller cannot
  /// fingerprint a non-canonical target order.
  TeamRotationPlan canonicalizeFor(Team team) => TeamRotationPlan.create(
    team: team,
    preset: preset,
    targets: [
      for (final player in team.players)
        if (targetSeconds.containsKey(player.id))
          RotationTarget(
            playerId: player.id,
            seconds: targetSeconds[player.id]!,
          ),
    ],
  );

  /// Canonical JSON: preset plus targets in canonical roster order, never map
  /// insertion order.
  Map<String, Object?> toJson() => {
    'preset': preset.jsonValue,
    'targets': [
      for (final playerId in _rosterOrder)
        {'playerId': playerId.value, 'seconds': targetSeconds[playerId]},
    ],
  };
}

/// Both teams' playing-time plans. Team order is canonical: home then away.
final class RotationPlan {
  const RotationPlan({required this.home, required this.away});

  final TeamRotationPlan home;
  final TeamRotationPlan away;

  Map<String, Object?> toJson() => {
    'home': home.toJson(),
    'away': away.toJson(),
  };

  /// Regulation per-player cap `C = Σ regulation period lengths`.
  static int regulationCap(GameRules rules) {
    var cap = 0;
    for (var period = 1; period <= rules.periods; period++) {
      cap += rules.periodLength(period);
    }
    return cap;
  }

  /// Regulation team total `T = 5 × C`.
  static int regulationTeamTotal(GameRules rules) => 5 * regulationCap(rules);

  /// Expands a preset into explicit integer-second targets for [team].
  ///
  /// [lineup] must be a valid five-player lineup for [team]; callers should
  /// validate it first. Remainder seconds go to starters in canonical
  /// court-slot order first, then to selected reserves in canonical roster
  /// order (owner decision 2026-11-06). The expansion is pure integer
  /// arithmetic and consumes no randomness.
  static Map<PlayerId, int> expandPreset({
    required RotationPreset preset,
    required Team team,
    required CourtLineup lineup,
    required GameRules rules,
  }) {
    if (preset == RotationPreset.custom) {
      throw GameValidationException([
        const GameValidationIssue(
          code: GameValidationCode.invalidRotationPreset,
          path: 'rotationPlan.preset',
          message: 'custom plans are not expanded',
        ),
      ]);
    }

    final rosterSize = team.players.length;
    final cap = regulationCap(rules);
    final total = 5 * cap;
    if (rosterSize < 5) {
      throw GameValidationException([
        GameValidationIssue(
          code: GameValidationCode.invalidRosterSizeForRotation,
          path: 'rotationPlan.targets',
          message: 'rotation requires at least five players, got $rosterSize',
        ),
      ]);
    }
    if (rosterSize == 5) {
      return Map<PlayerId, int>.unmodifiable({
        for (final player in team.players) player.id: cap,
      });
    }

    final preferred = preset == RotationPreset.balanced ? 9 : 8;
    final reserveCount = (rosterSize < preferred ? rosterSize : preferred) - 5;
    final starterWeight = preset == RotationPreset.balanced ? 3 : 5;
    const reserveWeight = 2;
    final weightTotal = 5 * starterWeight + reserveCount * reserveWeight;

    final starters = lineup.playerIds;
    final starterIds = {for (final id in starters) id};
    final reserveIds = [
      for (final player in team.players)
        if (!starterIds.contains(player.id.value)) player.id.value,
    ].take(reserveCount).toList();
    final participants = [...starters, ...reserveIds];

    final targets = <String, int>{};
    for (final id in participants) {
      final weight = starterIds.contains(id) ? starterWeight : reserveWeight;
      targets[id] = total * weight ~/ weightTotal;
    }
    var remainder = total - targets.values.fold(0, (a, b) => a + b);
    if (remainder < 0 || remainder >= participants.length) {
      throw GameValidationException([
        GameValidationIssue(
          code: GameValidationCode.invalidRotationTotal,
          path: 'rotationPlan.targets',
          message: 'remainder $remainder is outside 0..${participants.length}',
        ),
      ]);
    }
    for (var index = 0; index < remainder; index++) {
      final id = participants[index];
      targets[id] = targets[id]! + 1;
    }

    final expanded = <PlayerId, int>{};
    for (final player in team.players) {
      final seconds = targets[player.id.value] ?? 0;
      if (seconds < 0 || seconds > cap) {
        throw GameValidationException([
          GameValidationIssue(
            code: GameValidationCode.invalidRotationSeconds,
            path: 'rotationPlan.targets',
            message:
                'player ${player.id.value} target $seconds is outside '
                '0..$cap',
          ),
        ]);
      }
      expanded[player.id] = seconds;
    }
    return Map<PlayerId, int>.unmodifiable(expanded);
  }
}
