import '../generation/deterministic_random.dart';
import '../models/franchise_situation.dart';
import '../models/public_prospect_scouting_view.dart';
import '../models/team.dart';

/// Strategy engine for AI franchise rookie draft decision making.
///
/// Evaluates prospects purely using restricted [PublicProspectScoutingView] instances.
/// By architecture and compile-time contract, hidden true potential and development
/// trajectory are completely inaccessible to this evaluator.
final class AiDraftStrategy {
  const AiDraftStrategy();

  /// Evaluates available prospects and returns the highest scoring prospect for [team].
  PublicProspectScoutingView selectBestProspect({
    required List<PublicProspectScoutingView> availableProspects,
    required Team team,
    required FranchiseSituation situation,
    required int overallPick,
    required int seed,
  }) {
    if (availableProspects.isEmpty) {
      throw ArgumentError.value(
        availableProspects,
        'availableProspects',
        'Cannot select from empty prospect pool',
      );
    }

    PublicProspectScoutingView? bestProspect;
    var bestScore = double.negativeInfinity;

    for (final prospect in availableProspects) {
      final score = scoreProspect(
        prospect: prospect,
        team: team,
        situation: situation,
        overallPick: overallPick,
        seed: seed,
      );

      if (score > bestScore) {
        bestScore = score;
        bestProspect = prospect;
      } else if (score == bestScore && bestProspect != null) {
        // Canonical public-board order, then identity, independent of input order.
        if (prospect.projectedRank < bestProspect.projectedRank ||
            (prospect.projectedRank == bestProspect.projectedRank &&
                prospect.id.value.compareTo(bestProspect.id.value) < 0)) {
          bestProspect = prospect;
        }
      }
    }

    return bestProspect!;
  }

  /// Computes an explainable weighted score for [prospect] from [team]'s perspective.
  double scoreProspect({
    required PublicProspectScoutingView prospect,
    required Team team,
    required FranchiseSituation situation,
    required int overallPick,
    required int seed,
  }) {
    // 1. Consensus public talent baseline
    final rankScore = (91 - prospect.projectedRank) * 1.0; // 1..90
    final ovrScore = (prospect.overallRating - 40) * 1.5; // ~0..45

    const gradeValues = {
      'A+': 36.0,
      'A': 30.0,
      'A-': 24.0,
      'B+': 18.0,
      'B': 13.0,
      'B-': 8.0,
      'C+': 4.0,
      'C': 0.0,
    };
    final gradeBonus = gradeValues[prospect.estimatedPotentialGrade] ?? 10.0;
    final youthBonus = (23 - prospect.age) * 5.0; // 5..20

    // 2. Roster positional need
    var posCount = 0;
    var positionRatingTotal = 0;
    for (final player in team.players) {
      if (player.position == prospect.position) {
        posCount++;
        positionRatingTotal += player.attributes.overallRating;
      }
    }

    double needScore;
    if (posCount <= 1) {
      needScore = 24.0; // Urgent need
    } else if (posCount == 2) {
      needScore = 12.0; // Moderate need / rotation depth
    } else if (posCount == 3) {
      needScore = 0.0; // Neutral
    } else {
      needScore = -16.0; // Crowded position
    }

    if (posCount > 0) {
      final posAvgOvr = positionRatingTotal / posCount;
      if (posAvgOvr < 50.0) {
        needScore += 8.0; // Weak position boost
      }
    }

    // 3. Situation-driven weighting
    double baseScore;
    switch (situation) {
      case FranchiseSituation.tanking:
        // Prioritize long-term ceiling, estimated grade upside, and youth
        baseScore =
            (rankScore * 0.8) +
            (gradeBonus * 1.6) +
            (youthBonus * 1.4) +
            (needScore * 0.4) +
            (ovrScore * 0.6);
      case FranchiseSituation.playIn:
        // Balance immediate contribution with future improvement
        baseScore =
            (rankScore * 0.9) +
            (gradeBonus * 1.1) +
            (youthBonus * 0.9) +
            (needScore * 1.1) +
            (ovrScore * 1.0);
      case FranchiseSituation.playoff:
        // Prioritize contributors who address positional needs while retaining talent floor
        baseScore =
            (rankScore * 0.85) +
            (gradeBonus * 0.8) +
            (youthBonus * 0.6) +
            (needScore * 1.4) +
            (ovrScore * 1.3);
      case FranchiseSituation.contender:
        // Win-now: prioritize immediate readiness, role suitability, and positional depth
        baseScore =
            (rankScore * 0.6) +
            (gradeBonus * 0.5) +
            (youthBonus * 0.3) +
            (needScore * 1.8) +
            (ovrScore * 1.8);
    }

    // Stable 31-bit mixing avoids runtime-dependent String.hashCode.
    var mixedSeed = seed & 0x7fffffff;
    for (final value in [
      team.id.value,
      prospect.id.value,
      overallPick.toString(),
    ]) {
      for (final unit in value.codeUnits) {
        mixedSeed = ((mixedSeed * 31) + unit) & 0x7fffffff;
      }
      mixedSeed = ((mixedSeed * 31) + 255) & 0x7fffffff;
    }
    final rng = DeterministicRandom(mixedSeed);
    final variation = (rng.nextDouble() * 6.0) - 3.0; // -3.0..+3.0

    return baseScore + variation;
  }
}
