import 'game_validation.dart';
import 'game_versions.dart';

/// Versioned M002 game rules. Defaults are the frozen specification values.
final class GameRules {
  GameRules({
    this.rulesVersion = gameRulesVersion,
    this.periods = 4,
    this.periodSeconds = 720,
    this.overtimeSeconds = 300,
    this.maxOvertimes = 10,
    this.shotClockSeconds = 24,
    this.offensiveReboundResetSeconds = 14,
    this.nonBonusFoulResetFloorSeconds = 14,
    this.bonusRegulationFouls = 5,
    this.bonusOvertimeFouls = 4,
    this.maxEvents = 50000,
    this.maxZeroTimeEvents = 64,
    this.actionDurationModelVersion = gameActionDurationModelVersion,
    List<int> phaseWeights = const [1500, 3000, 5500],
    List<List<int>> phaseDurations = const [
      [2, 7],
      [5, 11],
      [10, 22],
    ],
    List<List<int>> orebPhaseDurations = const [
      [2, 6],
      [4, 9],
      [7, 15],
    ],
    List<List<int>> retainedFoulPhaseDurations = const [
      [2, 7],
      [4, 10],
      [8, 16],
    ],
  }) : phaseWeights = List<int>.unmodifiable(phaseWeights),
       phaseDurations = List<List<int>>.unmodifiable([
         for (final bracket in phaseDurations) List<int>.unmodifiable(bracket),
       ]),
       orebPhaseDurations = List<List<int>>.unmodifiable([
         for (final bracket in orebPhaseDurations)
           List<int>.unmodifiable(bracket),
       ]),
       retainedFoulPhaseDurations = List<List<int>>.unmodifiable([
         for (final bracket in retainedFoulPhaseDurations)
           List<int>.unmodifiable(bracket),
       ]);
  static final GameRules standard = GameRules();

  final int rulesVersion;
  final int periods;
  final int periodSeconds;
  final int overtimeSeconds;
  final int maxOvertimes;
  final int shotClockSeconds;
  final int offensiveReboundResetSeconds;
  final int nonBonusFoulResetFloorSeconds;
  final int bonusRegulationFouls;
  final int bonusOvertimeFouls;
  final int maxEvents;
  final int maxZeroTimeEvents;
  final int actionDurationModelVersion;
  final List<int> phaseWeights;
  final List<List<int>> phaseDurations;
  final List<List<int>> orebPhaseDurations;
  final List<List<int>> retainedFoulPhaseDurations;
  bool isOvertime(int period) => period > periods;

  int periodLength(int period) =>
      isOvertime(period) ? overtimeSeconds : periodSeconds;

  int bonusThreshold(int period) =>
      isOvertime(period) ? bonusOvertimeFouls : bonusRegulationFouls;

  GameRules validate() {
    final issues = <GameValidationIssue>[];

    void check(
      bool condition,
      GameValidationCode code,
      String path,
      String message,
    ) {
      if (!condition) {
        issues.add(
          GameValidationIssue(code: code, path: path, message: message),
        );
      }
    }

    check(
      rulesVersion == gameRulesVersion,
      GameValidationCode.unsupportedRulesVersion,
      'rules.rulesVersion',
      'unsupported rules version $rulesVersion',
    );
    check(
      periods == 4,
      GameValidationCode.invalidRules,
      'rules.periods',
      'regulation must have four periods, got $periods',
    );
    check(
      periodSeconds > 0 && periodSeconds <= 1800,
      GameValidationCode.invalidRules,
      'rules.periodSeconds',
      'periodSeconds must be 1..1800, got $periodSeconds',
    );
    check(
      overtimeSeconds > 0 && overtimeSeconds <= 600,
      GameValidationCode.invalidRules,
      'rules.overtimeSeconds',
      'overtimeSeconds must be 1..600, got $overtimeSeconds',
    );
    check(
      maxOvertimes >= 0 && maxOvertimes <= 10,
      GameValidationCode.invalidRules,
      'rules.maxOvertimes',
      'maxOvertimes must be 0..10, got $maxOvertimes',
    );
    check(
      shotClockSeconds >= 1 && shotClockSeconds <= 24,
      GameValidationCode.invalidRules,
      'rules.shotClockSeconds',
      'shotClockSeconds must be 1..24, got $shotClockSeconds',
    );
    check(
      offensiveReboundResetSeconds >= 1 &&
          offensiveReboundResetSeconds <= shotClockSeconds,
      GameValidationCode.invalidRules,
      'rules.offensiveReboundResetSeconds',
      'offensiveReboundResetSeconds must be 1..shotClockSeconds',
    );
    check(
      nonBonusFoulResetFloorSeconds >= 1 &&
          nonBonusFoulResetFloorSeconds <= shotClockSeconds,
      GameValidationCode.invalidRules,
      'rules.nonBonusFoulResetFloorSeconds',
      'nonBonusFoulResetFloorSeconds must be 1..shotClockSeconds',
    );
    check(
      bonusRegulationFouls >= 1 && bonusRegulationFouls <= 10,
      GameValidationCode.invalidRules,
      'rules.bonusRegulationFouls',
      'bonusRegulationFouls must be 1..10',
    );
    check(
      bonusOvertimeFouls >= 1 && bonusOvertimeFouls <= 10,
      GameValidationCode.invalidRules,
      'rules.bonusOvertimeFouls',
      'bonusOvertimeFouls must be 1..10',
    );
    check(
      maxEvents >= 1,
      GameValidationCode.invalidRules,
      'rules.maxEvents',
      'maxEvents must be positive',
    );
    check(
      maxZeroTimeEvents >= 1,
      GameValidationCode.invalidRules,
      'rules.maxZeroTimeEvents',
      'maxZeroTimeEvents must be positive',
    );
    check(
      actionDurationModelVersion == gameActionDurationModelVersion,
      GameValidationCode.unsupportedRulesVersion,
      'rules.actionDurationModelVersion',
      'unsupported duration model version $actionDurationModelVersion',
    );
    check(
      phaseWeights.length == 3 &&
          phaseWeights.every((weight) => weight > 0) &&
          phaseWeights.reduce((a, b) => a + b) == 10000,
      GameValidationCode.invalidRules,
      'rules.phaseWeights',
      'phaseWeights must be three positive basis-point weights summing to 10000',
    );
    check(
      phaseDurations.length == 3 &&
          phaseDurations.every(
            (bracket) =>
                bracket.length == 2 &&
                bracket[0] > 0 &&
                bracket[1] >= bracket[0],
          ),
      GameValidationCode.invalidRules,
      'rules.phaseDurations',
      'phaseDurations must be three [min, max] integer brackets',
    );
    check(
      orebPhaseDurations.length == 3 &&
          orebPhaseDurations.every(
            (bracket) =>
                bracket.length == 2 &&
                bracket[0] > 0 &&
                bracket[1] >= bracket[0],
          ),
      GameValidationCode.invalidRules,
      'rules.orebPhaseDurations',
      'orebPhaseDurations must be three [min, max] integer brackets',
    );
    check(
      retainedFoulPhaseDurations.length == 3 &&
          retainedFoulPhaseDurations.every(
            (bracket) =>
                bracket.length == 2 &&
                bracket[0] > 0 &&
                bracket[1] >= bracket[0],
          ),
      GameValidationCode.invalidRules,
      'rules.retainedFoulPhaseDurations',
      'retainedFoulPhaseDurations must be three [min, max] integer brackets',
    );
    if (issues.isNotEmpty) throw GameValidationException(issues);
    return this;
  }

  Map<String, Object?> toJson() => {
    'rulesVersion': rulesVersion,
    'periods': periods,
    'periodSeconds': periodSeconds,
    'overtimeSeconds': overtimeSeconds,
    'maxOvertimes': maxOvertimes,
    'shotClockSeconds': shotClockSeconds,
    'offensiveReboundResetSeconds': offensiveReboundResetSeconds,
    'nonBonusFoulResetFloorSeconds': nonBonusFoulResetFloorSeconds,
    'bonusRegulationFouls': bonusRegulationFouls,
    'bonusOvertimeFouls': bonusOvertimeFouls,
    'maxEvents': maxEvents,
    'maxZeroTimeEvents': maxZeroTimeEvents,
    'gameActionDurationModelVersion': actionDurationModelVersion,
    'phaseWeights': List<int>.of(phaseWeights),
    'phaseDurations': [
      for (final bracket in phaseDurations) List<int>.of(bracket),
    ],
    'orebPhaseDurations': [
      for (final bracket in orebPhaseDurations) List<int>.of(bracket),
    ],
    'retainedFoulPhaseDurations': [
      for (final bracket in retainedFoulPhaseDurations) List<int>.of(bracket),
    ],
  };
}
