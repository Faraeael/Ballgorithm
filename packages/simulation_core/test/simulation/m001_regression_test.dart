import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

void main() {
  test('M001 versions and default snapshot remain pinned', () {
    expect(coreEngineVersion, '1.0.0');
    expect(snapshotSchemaVersion, 1);
    expect(prngImplementationId, 'xorshift32-v1');
    expect(gameSimulationVersion, 1);
    expect(gameRulesVersion, 1);
    expect(gameEventSchemaVersion, 2);
    final rules = GameRules.standard;
    expect(rules.periods, 4);
    expect(rules.periodSeconds, 720);
    expect(rules.overtimeSeconds, 300);
    expect(rules.shotClockSeconds, 24);
    expect(rules.maxOvertimes, 10);
    expect(rules.maxEvents, 50000);
    expect(rules.maxZeroTimeEvents, 64);
    expect(rules.bonusRegulationFouls, 5);
    expect(rules.bonusOvertimeFouls, 4);
    expect(rules.phaseWeights, [1500, 3000, 5500]);
    expect(rules.phaseDurations, [
      [2, 7],
      [5, 11],
      [10, 22],
    ]);

    const generator = LeagueGenerator();
    const config = GenerationConfig(seed: 20261028);
    final league = generator.generate(config);
    final json = jsonEncode(league.toJson());
    expect(json.length, 29263);
    final first = league.teams.first.players.first;
    expect(first.fullName, 'Jonas Cortez');
    expect(first.position, Position.sg);
    expect(first.attributes.asMap, {
      'insideScoring': 56,
      'midrange': 74,
      'threePoint': 69,
      'freeThrow': 52,
      'passing': 64,
      'ballHandling': 48,
      'perimeterDefense': 58,
      'interiorDefense': 46,
      'rebounding': 28,
      'athleticism': 67,
      'stamina': 52,
      'basketballIQ': 44,
    });
  });
}
