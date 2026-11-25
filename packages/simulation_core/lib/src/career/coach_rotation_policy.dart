import '../models/ids.dart';
import '../models/player.dart';
import '../models/position.dart';
import '../models/team.dart';
import '../simulation/court_lineup.dart';
import '../simulation/game_input.dart';
import '../simulation/game_rules.dart';
import '../simulation/game_validation.dart';
import '../simulation/rotation_plan.dart';
import 'staff_member.dart';

/// Deterministic head-coach lineup and playing-time policy (M011 §3).
///
/// Pure integer arithmetic over the standard roster; consumes no randomness
/// and adds no attribute bonuses. Every result is checked with
/// `GameInput.validateLineupAndPlan`.
abstract final class CoachRotationPolicy {
  /// Rotation size of the deep-rotation philosophy.
  static const int deepRotationSize = 10;

  /// Starter and reserve weights of the deep-rotation custom plan
  /// (3 : 2 → 1,728 s and 1,152 s under standard rules; total 14,400 s).
  static const int deepStarterWeight = 3;
  static const int deepReserveWeight = 2;

  /// The coach's lineup and plan for [standardTeam], or `null` when the
  /// computed plan does not validate (the caller then uses the automatic
  /// rotation and reports the coach plan as unavailable).
  static ({CourtLineup lineup, TeamRotationPlan plan})? planFor(
    CoachPhilosophy philosophy,
    Team standardTeam, {
    GameRules? rules,
  }) {
    final effectiveRules = rules ?? GameRules.standard;
    try {
      final lineup = CourtLineup.create(
        team: standardTeam,
        slotOrderedPlayers: selectStarters(philosophy, standardTeam),
      );
      final plan = _planFor(philosophy, standardTeam, lineup, effectiveRules);
      GameInput.validateLineupAndPlan(
        team: standardTeam,
        lineup: lineup,
        plan: plan,
        rules: effectiveRules,
      );
      return (lineup: lineup, plan: plan);
    } on GameValidationException {
      return null;
    }
  }

  /// Slot-ordered starters: for PG, SG, SF, PF, C, the best-scoring unchosen
  /// player whose primary position matches, else the best-scoring unchosen
  /// player. Ties: higher overall rating (defensive score only), then roster
  /// order (roster order is unique, so the id tie-break is never reached).
  static List<Player> selectStarters(
    CoachPhilosophy philosophy,
    Team standardTeam,
  ) {
    final ranked = _ranked(standardTeam.players, philosophy);
    final chosen = <Player>[];
    final taken = <String>{};
    for (final slot in Position.values) {
      Player? pick;
      for (final p in ranked) {
        if (!taken.contains(p.id.value) && p.position == slot) {
          pick = p;
          break;
        }
      }
      pick ??= ranked.where((p) => !taken.contains(p.id.value)).firstOrNull;
      if (pick == null) break; // Fewer than five players; validation rejects.
      chosen.add(pick);
      taken.add(pick.id.value);
    }
    return chosen;
  }

  /// Starter score used by [philosophy] (higher is better).
  static int starterScore(CoachPhilosophy philosophy, Player player) {
    final a = player.attributes;
    return switch (philosophy) {
      CoachPhilosophy.defensiveMinded =>
        a.perimeterDefense + a.interiorDefense + a.rebounding,
      _ => a.overallRating,
    };
  }

  static List<Player> _ranked(List<Player> roster, CoachPhilosophy philosophy) {
    final order = {for (var i = 0; i < roster.length; i++) roster[i].id: i};
    return [...roster]..sort((x, y) {
      var c = starterScore(
        philosophy,
        y,
      ).compareTo(starterScore(philosophy, x));
      if (c != 0) return c;
      c = y.attributes.overallRating.compareTo(x.attributes.overallRating);
      if (c != 0) return c;
      return order[x.id]!.compareTo(order[y.id]!);
    });
  }

  static TeamRotationPlan _planFor(
    CoachPhilosophy philosophy,
    Team team,
    CourtLineup lineup,
    GameRules rules,
  ) {
    final preset = switch (philosophy) {
      CoachPhilosophy.starFocused => RotationPreset.starterHeavy,
      CoachPhilosophy.deepRotation
          when team.players.length >= deepRotationSize =>
        RotationPreset.custom,
      // Deep rotation with fewer than ten standard players: balanced (§3).
      _ => RotationPreset.balanced,
    };
    final seconds = preset == RotationPreset.custom
        ? _deepRotationSeconds(team, lineup, rules)
        : RotationPlan.expandPreset(
            preset: preset,
            team: team,
            lineup: lineup,
            rules: rules,
          );
    return TeamRotationPlan.create(
      team: team,
      preset: preset,
      targets: [
        for (final p in team.players)
          RotationTarget(playerId: p.id, seconds: seconds[p.id] ?? 0),
      ],
    );
  }

  /// Starters weight 3, the five best remaining players by overall rating
  /// (ties: roster order) weight 2, everyone else 0. Remainder seconds, if
  /// the rules ever leave any, go to starters in slot order then reserves.
  static Map<PlayerId, int> _deepRotationSeconds(
    Team team,
    CourtLineup lineup,
    GameRules rules,
  ) {
    final total = RotationPlan.regulationTeamTotal(rules);
    final starters = [for (final id in lineup.playerIds) PlayerId(id)];
    final starterSet = starters.toSet();
    final reserves = _ranked([
      for (final p in team.players)
        if (!starterSet.contains(p.id)) p,
    ], CoachPhilosophy.balanced).take(deepRotationSize - 5).map((p) => p.id);
    final participants = [...starters, ...reserves];
    const weightTotal = 5 * deepStarterWeight + 5 * deepReserveWeight;
    final unit = total ~/ weightTotal;
    final result = <PlayerId, int>{
      for (final id in participants)
        id:
            unit *
            (starterSet.contains(id) ? deepStarterWeight : deepReserveWeight),
    };
    var remainder = total - unit * weightTotal;
    for (var i = 0; remainder > 0; i = (i + 1) % participants.length) {
      result[participants[i]] = result[participants[i]]! + 1;
      remainder--;
    }
    return result;
  }
}
