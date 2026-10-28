/// Immutable replay state exposed after validating a ledger.
final class GameState {
  const GameState({
    required this.started,
    required this.ended,
    required this.period,
    required this.gameClock,
    required this.shotClock,
    required this.eventCount,
    this.possessionId,
    this.offenseTeamId,
  });

  static const GameState initial = GameState(
    started: false,
    ended: false,
    period: 0,
    gameClock: 0,
    shotClock: null,
    eventCount: 0,
  );

  final bool started;
  final bool ended;
  final int period;
  final int gameClock;
  final int? shotClock;
  final int eventCount;
  final String? possessionId;
  final String? offenseTeamId;

  bool get hasOpenPossession => possessionId != null;

  GameState copyWith({
    bool? started,
    bool? ended,
    int? period,
    int? gameClock,
    int? shotClock,
    bool clearShotClock = false,
    int? eventCount,
    String? possessionId,
    String? offenseTeamId,
    bool clearPossession = false,
  }) => GameState(
    started: started ?? this.started,
    ended: ended ?? this.ended,
    period: period ?? this.period,
    gameClock: gameClock ?? this.gameClock,
    shotClock: clearShotClock ? null : (shotClock ?? this.shotClock),
    eventCount: eventCount ?? this.eventCount,
    possessionId: clearPossession ? null : (possessionId ?? this.possessionId),
    offenseTeamId: clearPossession
        ? null
        : (offenseTeamId ?? this.offenseTeamId),
  );
}
