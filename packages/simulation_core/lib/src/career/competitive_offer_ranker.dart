import '../models/free_agent.dart';
import '../models/free_agent_market.dart';
import '../models/franchise_situation.dart';
import '../models/ids.dart';
import '../models/team.dart';
import 'gm_career.dart';

/// Deterministic ranking among offers that already passed T08E acceptance.
final class CompetitiveOfferRanker {
  const CompetitiveOfferRanker();

  List<FreeAgentMarketOffer> rank({
    required GmCareer career,
    required PlayerId playerId,
    required List<FreeAgentMarketOffer> offers,
  }) {
    final entry = career.freeAgentPool.byId(playerId);
    if (entry == null) return const [];
    final view = entry.toPublicView();
    final ranked = [...offers]
      ..sort((a, b) {
        final aTeam = career.league.teams.firstWhere((t) => t.id == a.teamId);
        final bTeam = career.league.teams.firstWhere((t) => t.id == b.teamId);
        final aScore = _utility(a, aTeam, view);
        final bScore = _utility(b, bTeam, view);
        if (aScore != bScore) return bScore.compareTo(aScore);
        final aKey = _fnv1a(
          '${a.playerId.value}:${a.teamId.value}:${a.roundNumber}',
        );
        final bKey = _fnv1a(
          '${b.playerId.value}:${b.teamId.value}:${b.roundNumber}',
        );
        if (aKey != bKey) return aKey.compareTo(bKey);
        return a.offerId.compareTo(b.offerId);
      });
    return ranked;
  }

  /// Additive, transitive utility. Salary is weighted at 10 CU per salary CU,
  /// fit is at most +/-2,000 and duration at most -300, so salary stays the
  /// dominant term while fit and duration can decide near-equal offers.
  int _utility(
    FreeAgentMarketOffer offer,
    Team team,
    PublicFreeAgentView view,
  ) {
    final durationGap = (offer.durationYears - _preferred(view)).abs();
    return offer.firstYearSalary * 10 + _fit(team, view) - durationGap * 100;
  }

  int _preferred(PublicFreeAgentView view) {
    if (view.age <= 23) return 2;
    if (view.age <= 28) return 3;
    if (view.age <= 31) return 2;
    return 1;
  }

  int _fit(Team team, PublicFreeAgentView view) {
    var score = 0;
    final situation = team.situation ?? FranchiseSituation.playIn;
    score += switch (situation) {
      FranchiseSituation.tanking =>
        view.age <= 24 ? 1200 : (view.age >= 30 ? -1000 : 0),
      FranchiseSituation.contender =>
        view.age >= 30 ? 1000 : (view.age <= 24 ? -300 : 0),
      FranchiseSituation.playoff => view.age >= 30 ? 500 : 0,
      _ => 0,
    };
    final samePosition = team.players
        .where((player) => player.position == view.position)
        .toList();
    final stronger = samePosition
        .where(
          (player) => player.attributes.overallRating >= view.overallRating - 2,
        )
        .length;
    score += stronger >= 2
        ? -1200
        : (stronger == 1 ? -400 : (samePosition.isEmpty ? 800 : 0));
    return score;
  }

  static int _fnv1a(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}
