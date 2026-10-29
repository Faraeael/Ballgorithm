import '../models/ids.dart';
import 'active_lineup.dart';

/// One team's active five plus its team identity.
///
/// The probability model never holds team state; it only reads ratings from
/// these players.
final class TeamOnCourt {
  const TeamOnCourt({required this.teamId, required this.lineup});

  final TeamId teamId;
  final ActiveLineup lineup;
}

/// Live offensive-phase classification from the A1 duration model.
enum PhaseKind {
  transition('transition'),
  earlyOffense('earlyOffense'),
  halfCourt('halfCourt');

  const PhaseKind(this.wire);

  final String wire;
}

/// A1 phase type plus its planned integer duration in seconds.
///
/// The orchestrator owns clock precedence; this model never clamps the planned
/// duration against the game or shot clock.
final class PhaseDuration {
  const PhaseDuration({required this.kind, required this.seconds});

  final PhaseKind kind;
  final int seconds;
}

/// Shot location band. `shotValue` is the counted field-goal value.
enum ShotZone {
  inside(2, 'inside'),
  midrange(2, 'midrange'),
  three(3, 'three');

  const ShotZone(this.shotValue, this.wire);

  final int shotValue;
  final String wire;
}

/// Turnover classification for later event translation.
enum TurnoverKind {
  /// Linked to a defender; `Turnover.stolenById` is set.
  steal('steal'),

  /// Live non-steal giveaway (bad pass, travel, lost ball).
  nonSteal('nonSteal');

  const TurnoverKind(this.wire);

  final String wire;
}

/// A terminal offensive decision. T009/T010 translate these into events;
/// nothing here emits ledger entries.
sealed class OffensiveAction {
  const OffensiveAction({required this.offenseTeamId});

  final TeamId offenseTeamId;
}

/// Field-goal attempt decision.
///
/// Canonical rules encoded as assertions:
/// - a block is only possible on a miss;
/// - an assist is only possible on a make, by a teammate;
/// - a shooting foul on a miss awards no counted FGA;
/// - a made and-one is a counted FGA/FGM plus exactly one FT.
final class ShotAttemptAction extends OffensiveAction {
  const ShotAttemptAction({
    required super.offenseTeamId,
    required this.shooterId,
    required this.zone,
    required this.made,
    required this.andOne,
    required this.freeThrowsAwarded,
    this.assistedById,
    this.blockedById,
    this.foulingDefenderId,
  }) : assert(assistedById == null || (made && assistedById != shooterId)),
       assert(blockedById == null || !made),
       assert(!andOne || (made && foulingDefenderId != null)),
       assert(!andOne || freeThrowsAwarded == 1),
       assert(made || !andOne),
       assert(
         !made ||
             (!andOne && freeThrowsAwarded == 0) ||
             (andOne && foulingDefenderId != null),
       ),
       assert(
         made ||
             freeThrowsAwarded == 0 ||
             freeThrowsAwarded == 2 ||
             freeThrowsAwarded == 3,
       ),
       assert(foulingDefenderId == null || !made || andOne);

  final PlayerId shooterId;
  final ShotZone zone;
  final bool made;
  final bool andOne;

  /// Awarded free throws for the fouling path: 1 for an and-one, `shotValue`
  /// for a missed shooting-foul attempt, otherwise 0.
  final int freeThrowsAwarded;
  final PlayerId? assistedById;
  final PlayerId? blockedById;
  final PlayerId? foulingDefenderId;

  int get shotValue => zone.shotValue;
}

/// Live turnover decision.
final class TurnoverAction extends OffensiveAction {
  const TurnoverAction({
    required super.offenseTeamId,
    required this.playerId,
    required this.kind,
    this.stolenById,
  }) : assert(kind != TurnoverKind.steal || stolenById != null),
       assert(kind != TurnoverKind.nonSteal || stolenById == null);

  final PlayerId playerId;
  final TurnoverKind kind;
  final PlayerId? stolenById;
}

/// Normal offensive foul: player PF plus player turnover, no made basket.
final class OffensiveFoulAction extends OffensiveAction {
  const OffensiveFoulAction({
    required super.offenseTeamId,
    required this.playerId,
    required this.victimId,
  });

  /// The offending offensive player; also the charged turnover owner.
  final PlayerId playerId;

  /// The defender drawn into the foul.
  final PlayerId victimId;
}

/// Defensive non-shooting foul. Possession is retained by the offense; the
/// later orchestrator decides bonus/free throws and the OD-12 shot-clock reset.
final class NonShootingFoulAction extends OffensiveAction {
  const NonShootingFoulAction({
    required super.offenseTeamId,
    required this.committingPlayerId,
    required this.drawnByPlayerId,
  });

  final PlayerId committingPlayerId;
  final PlayerId drawnByPlayerId;
}

/// Rebound decision after an eligible live miss.
final class ReboundIntent {
  const ReboundIntent({
    required this.teamId,
    required this.playerId,
    required this.offensive,
  });

  final TeamId teamId;
  final PlayerId playerId;
  final bool offensive;

  /// An offensive rebound continues the same possession; it never starts a
  /// new one.
  bool get continuesPossession => offensive;
}

/// Deterministic free-throw group result. Does not emit event groups.
final class FreeThrowGroupIntent {
  FreeThrowGroupIntent({
    required this.teamId,
    required this.shooterId,
    required List<bool> madeByAttempt,
  }) : madeByAttempt = List.unmodifiable(madeByAttempt) {
    if (this.madeByAttempt.isEmpty) {
      throw ArgumentError.value(
        madeByAttempt,
        'madeByAttempt',
        'free-throw group requires at least one attempt',
      );
    }
  }

  final TeamId teamId;
  final PlayerId shooterId;
  final List<bool> madeByAttempt;

  int get attempts => madeByAttempt.length;

  int get madeCount => madeByAttempt.where((made) => made).length;

  bool get missedFinalAttempt => !madeByAttempt.last;
}
