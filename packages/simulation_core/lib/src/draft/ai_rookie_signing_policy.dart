import '../models/ai_rookie_signing.dart';
import '../models/franchise_situation.dart';
import '../models/public_prospect_scouting_view.dart';
import '../models/roster_category.dart';
import '../models/roster_rules.dart';
import '../models/team.dart';

/// Deterministic AI signing choice for one drafted prospect.
final class AiSigningChoice {
  const AiSigningChoice.sign({
    required RosterCategory this.category,
    required int this.durationYears,
    required this.reason,
  });

  const AiSigningChoice.defer(this.reason)
    : category = null,
      durationYears = null;

  final RosterCategory? category;
  final int? durationYears;
  final AiSigningReason reason;

  bool get isSigning => category != null;
}

/// Public-information-only scoring policy for AI rookie signings.
///
/// No PRNG, clock, hash code or hidden prospect field participates. The same
/// public state always yields the same choice.
final class AiRookieSigningPolicy {
  const AiRookieSigningPolicy();

  AiSigningChoice decide({
    required PublicProspectScoutingView prospect,
    required Team team,
    required FranchiseSituation situation,
    required int overallPick,
  }) {
    final roster = team.roster;
    if (roster.totalContractedCount >= RosterRules.maxOffseasonTotal) {
      return const AiSigningChoice.defer(AiSigningReason.deferredRosterFull);
    }

    final weights = _weightsFor(situation);
    final quality = prospect.overallRating.toDouble();
    final upside = rangeMidpoint(prospect.estimatedPotentialRange);
    final youth = (22 - prospect.age).clamp(0, 3) / 3 * 100;
    final depth = roster.players
        .where((player) => player.position == prospect.position)
        .length;
    final need = (3 - depth).clamp(0, 3) / 3 * 100;
    var fit =
        weights.quality * quality +
        weights.upside * upside +
        weights.youth * youth +
        weights.need * need;
    if (overallPick <= 30) fit += 6;

    if (fit >= _standardThreshold(situation)) {
      if (roster.standardCount < RosterRules.maxOffseasonStandard) {
        return AiSigningChoice.sign(
          category: RosterCategory.standard,
          durationYears: _standardDuration(situation),
          reason: need >= 50
              ? AiSigningReason.signedStandardNeed
              : AiSigningReason.signedStandardQuality,
        );
      }
      return const AiSigningChoice.defer(
        AiSigningReason.deferredNoStandardSlot,
      );
    }

    final developmental = prospect.age <= 20 || upside - quality >= 10;
    if (developmental && fit >= _twoWayThreshold(situation)) {
      if (roster.twoWayCount < RosterRules.maxOffseasonTwoWay) {
        return AiSigningChoice.sign(
          category: RosterCategory.twoWay,
          durationYears: _twoWayDuration(situation),
          reason: AiSigningReason.signedTwoWayDevelopment,
        );
      }
      return const AiSigningChoice.defer(AiSigningReason.deferredNoTwoWaySlot);
    }
    return const AiSigningChoice.defer(AiSigningReason.deferredLowFit);
  }

  /// Midpoint of a public ceiling range such as `85–91`; 60 when unreadable.
  static double rangeMidpoint(String range) {
    final values = RegExp(
      r'\d+',
    ).allMatches(range).map((match) => int.parse(match.group(0)!)).toList();
    if (values.isEmpty) return 60;
    if (values.length == 1) return values.first.toDouble();
    return (values[0] + values[1]) / 2;
  }

  static _Weights _weightsFor(FranchiseSituation situation) =>
      switch (situation) {
        FranchiseSituation.tanking => const _Weights(0.25, 0.45, 0.20, 0.10),
        FranchiseSituation.playIn => const _Weights(0.40, 0.30, 0.15, 0.15),
        FranchiseSituation.playoff => const _Weights(0.55, 0.15, 0.05, 0.25),
        FranchiseSituation.contender => const _Weights(0.65, 0.05, 0.00, 0.30),
      };

  static double _standardThreshold(FranchiseSituation situation) =>
      switch (situation) {
        FranchiseSituation.tanking => 55,
        FranchiseSituation.playIn => 60,
        FranchiseSituation.playoff => 65,
        FranchiseSituation.contender => 70,
      };

  static double _twoWayThreshold(FranchiseSituation situation) =>
      switch (situation) {
        FranchiseSituation.tanking => 45,
        FranchiseSituation.playIn => 50,
        FranchiseSituation.playoff => 55,
        FranchiseSituation.contender => 60,
      };

  static int _standardDuration(FranchiseSituation situation) =>
      switch (situation) {
        FranchiseSituation.tanking => 4,
        FranchiseSituation.playIn => 3,
        FranchiseSituation.playoff => 2,
        FranchiseSituation.contender => 2,
      };

  static int _twoWayDuration(FranchiseSituation situation) =>
      switch (situation) {
        FranchiseSituation.tanking => 2,
        FranchiseSituation.playIn => 2,
        FranchiseSituation.playoff => 1,
        FranchiseSituation.contender => 1,
      };
}

final class _Weights {
  const _Weights(this.quality, this.upside, this.youth, this.need);

  final double quality;
  final double upside;
  final double youth;
  final double need;
}
