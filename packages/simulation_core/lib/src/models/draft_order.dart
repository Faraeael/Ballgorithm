import 'draft_pick.dart';
import 'ids.dart';

/// The authoritative 2-round, 60-pick order for an annual rookie draft.
final class DraftOrder {
  DraftOrder({required List<DraftPick> picks})
    : picks = List.unmodifiable(picks) {
    validate();
  }

  factory DraftOrder.fromJson(Map<String, dynamic> json) {
    final rawPicks = json['picks'] as List<dynamic>?;
    if (rawPicks == null) {
      throw const FormatException('Missing picks list in DraftOrder JSON');
    }
    final picks = rawPicks
        .map((p) => DraftPick.fromJson(p as Map<String, dynamic>))
        .toList();
    return DraftOrder(picks: picks);
  }

  final List<DraftPick> picks;

  int get totalPicks => picks.length;

  List<DraftPick> get round1Picks => picks.where((p) => p.round == 1).toList();

  List<DraftPick> get round2Picks => picks.where((p) => p.round == 2).toList();

  List<DraftPick> picksForTeam(TeamId teamId) =>
      picks.where((p) => p.currentOwnerTeamId == teamId).toList();

  DraftPick pickAt(int overallPick) =>
      picks.firstWhere((p) => p.overallPick == overallPick);

  void validate() {
    if (picks.length != 60) {
      throw FormatException(
        'Invalid draft order: expected 60 picks, got ${picks.length}',
      );
    }

    final seenOverall = <int>{};
    final round1Teams = <String>{};
    final round2Teams = <String>{};

    for (var i = 0; i < picks.length; i++) {
      final pick = picks[i];
      if (pick.overallPick != i + 1) {
        throw FormatException(
          'Pick at index $i has overallPick ${pick.overallPick}, expected ${i + 1}',
        );
      }
      if (!seenOverall.add(pick.overallPick)) {
        throw FormatException('Duplicate overall pick: ${pick.overallPick}');
      }

      if (pick.round == 1) {
        if (pick.pickInRound != pick.overallPick) {
          throw FormatException(
            'Round 1 pickInRound ${pick.pickInRound} does not match overallPick ${pick.overallPick}',
          );
        }
        if (!round1Teams.add(pick.originalOwnerTeamId.value)) {
          throw FormatException(
            'Duplicate original team in Round 1: ${pick.originalOwnerTeamId.value}',
          );
        }
      } else if (pick.round == 2) {
        if (pick.pickInRound != pick.overallPick - 30) {
          throw FormatException(
            'Round 2 pickInRound ${pick.pickInRound} does not match overallPick ${pick.overallPick}',
          );
        }
        if (!round2Teams.add(pick.originalOwnerTeamId.value)) {
          throw FormatException(
            'Duplicate original team in Round 2: ${pick.originalOwnerTeamId.value}',
          );
        }
      } else {
        throw FormatException('Invalid draft round: ${pick.round}');
      }
    }

    if (round1Teams.length != 30) {
      throw FormatException(
        'Round 1 must include all 30 teams, found ${round1Teams.length}',
      );
    }
    if (round2Teams.length != 30) {
      throw FormatException(
        'Round 2 must include all 30 teams, found ${round2Teams.length}',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'picks': picks.map((p) => p.toJson()).toList(),
  };
}
