/// Optional, passive A1 phase trace for calibration diagnostics (T015).
///
/// Disabled by default. When an observer is supplied to `GameSimulator`, it is
/// called once per sampled A1 phase with the values that the simulator already
/// knows: the drawn phase kind and planned duration, the game/shot clocks
/// immediately before the draw, and how the phase resolved. The observer runs
/// after the resolution is decided and before the corresponding state mutation;
/// it cannot consume randomness, alter state or change the ledger.
library;

/// How a sampled A1 phase resolved in `GameSimulator._playPossession`.
enum PhaseResolution {
  /// A shot attempt (including a legal release at shot clock zero).
  legalShot,

  /// A foul action that was applied (retained possession, FTs or horn award).
  legalFoul,

  /// A live turnover or offensive foul that was applied inside the possession.
  legalTurnover,

  /// Planned duration exceeded the available shot clock with game time left.
  shotClockOvershoot,

  /// No released attempt or qualifying award existed when the shot clock
  /// reached zero, including `duration == shotClock` exact exhaustion.
  shotClockExpiryNoAttempt,

  /// A live turnover or offensive foul that would land on the period horn and is
  /// therefore discarded without an event.
  actionDiscardedAtHorn,

  /// Game clock expired before the shot clock (`D > Rg < Rs`): no action.
  gameClockFirst,

  /// Game and shot clock expired together (`D > Rg == Rs`): horn precedence.
  simultaneousExpiry,
}

/// One sampled A1 phase observation.
final class PhaseTraceRecord {
  const PhaseTraceRecord({
    required this.sequence,
    required this.period,
    required this.kind,
    required this.plannedSeconds,
    required this.gameClockBefore,
    required this.shotClockBefore,
    required this.resolution,
  });

  /// Monotonic trace index within the simulation (1-based).
  final int sequence;
  final int period;
  final String kind;
  final int plannedSeconds;
  final int gameClockBefore;
  final int shotClockBefore;
  final PhaseResolution resolution;

  @override
  String toString() =>
      'phase#$sequence p$period $kind ${plannedSeconds}s '
      'clock=$gameClockBefore shot=$shotClockBefore ${resolution.name}';
}
