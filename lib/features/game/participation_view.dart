import 'package:simulation_core/simulation_core.dart';

/// How a displayed player entered the game.
enum ParticipationRole { starter, substitute }

/// Authoritative disqualification state for one displayed player.
enum DisqualificationStatus {
  none,

  /// Reached the foul limit and was replaced at a substitution window.
  fouledOut,

  /// Reached the foul limit with no eligible inactive roster player left, so
  /// the player continued.
  continuedDepleted,

  /// Reached the foul limit at the final horn; `GameEnded` voided the pending
  /// replacement obligation, so this is not depleted-roster continuation.
  fouledOutAtHorn,
}

/// One row of the results player table, derived from the validated result.
final class ParticipantRow {
  const ParticipantRow({
    required this.player,
    required this.box,
    required this.role,
    required this.status,
  });

  final Player player;
  final PlayerBoxScore box;
  final ParticipationRole role;
  final DisqualificationStatus status;

  int get secondsPlayed => box.secondsPlayed;
}

/// Builds the participants-only projection for [team].
///
/// Starters keep canonical `CourtLineup` slot order; entrants follow in order
/// of first entry. Participation is entry, never minutes.
List<ParticipantRow> participationRows(GameResult result, Team team) {
  final starters = result.input.lineupFor(team.id).playerIds;
  final roster = {for (final player in team.players) player.id.value: player};
  final entrantOrder = <String>[];
  final seen = <String>{...starters};

  final fouls = <String, int>{};
  final sixthFoulIndex = <String, int>{};
  final activeAtSixth = <String, Set<String>>{};
  final replaced = <String>{};
  final active = [...starters];

  for (var index = 0; index < result.events.length; index++) {
    final event = result.events[index];
    if (event is PersonalFoul) {
      final playerId = event.committingPlayerId;
      final count = (fouls[playerId] ?? 0) + 1;
      fouls[playerId] = count;
      if (count == result.input.rules.foulOutLimit) {
        sixthFoulIndex[playerId] = index;
        activeAtSixth[playerId] = {...active};
      }
    } else if (event is Substitution && event.teamId == team.id.value) {
      replaced.add(event.playerOutId);
      final slot = active.indexOf(event.playerOutId);
      if (slot != -1) active[slot] = event.playerInId;
      if (seen.add(event.playerInId)) entrantOrder.add(event.playerInId);
    }
  }

  DisqualificationStatus statusOf(String playerId) {
    final sixth = sixthFoulIndex[playerId];
    if (sixth == null) return DisqualificationStatus.none;
    if (replaced.contains(playerId)) {
      return DisqualificationStatus.fouledOut;
    }
    final tail = result.events.skip(sixth + 1);
    final onlyGameEnd = tail.every(
      (event) =>
          event is PossessionEnded ||
          event is PeriodEnded ||
          event is GameEnded,
    );
    if (onlyGameEnd) return DisqualificationStatus.fouledOutAtHorn;
    final activeIds = activeAtSixth[playerId] ?? const <String>{};
    final eligibleBench = roster.keys.where(
      (id) => !activeIds.contains(id) && (fouls[id] ?? 0) < 6,
    );
    if (eligibleBench.isEmpty) {
      return DisqualificationStatus.continuedDepleted;
    }
    return DisqualificationStatus.fouledOut;
  }

  ParticipantRow row(String playerId, ParticipationRole role) {
    final player = roster[playerId]!;
    return ParticipantRow(
      player: player,
      box: result.boxScore.players[playerId]!,
      role: role,
      status: statusOf(playerId),
    );
  }

  return [
    for (final id in starters) row(id, ParticipationRole.starter),
    for (final id in entrantOrder) row(id, ParticipationRole.substitute),
  ];
}

/// Formats exact seconds as `M:SS`; never decimal minutes.
String formatMinutes(int seconds) {
  final whole = seconds < 0 ? 0 : seconds;
  return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}';
}

String roleLabel(ParticipationRole role) => switch (role) {
  ParticipationRole.starter => 'STARTER',
  ParticipationRole.substitute => 'SUBSTITUTE',
};

String? statusLabel(DisqualificationStatus status) => switch (status) {
  DisqualificationStatus.none => null,
  DisqualificationStatus.fouledOut => 'Fouled out',
  DisqualificationStatus.continuedDepleted =>
    'Fouled out — continued (no bench)',
  DisqualificationStatus.fouledOutAtHorn => 'Fouled out at the horn',
};
