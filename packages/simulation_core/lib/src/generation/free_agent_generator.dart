import '../models/free_agent.dart';
import '../models/ids.dart';
import '../models/player.dart';
import '../models/player_attributes.dart';
import '../models/player_career_profile.dart';
import '../models/position.dart';
import 'deterministic_random.dart';
import 'name_corpus.dart';
import 'position_attribute_offsets.dart';

/// Deterministic generator for the initial free-agent population.
///
/// Uses an isolated PRNG stream so league, draft, profile and AI sequences are
/// untouched. Draw order is part of the free-agent generation contract.
final class FreeAgentGenerator {
  const FreeAgentGenerator();

  /// Isolated stream: `(seed ^ 0xFA5E0001) & 0x7FFFFFFF`.
  FreeAgentPool generate({required int seed}) {
    final random = DeterministicRandom((seed ^ 0xFA5E0001) & 0x7FFFFFFF);

    final names = [
      for (final first in firstNames)
        for (final last in lastNames) (first, last),
    ];
    random.shuffle(names);

    final positions = <Position>[
      for (final position in Position.values)
        for (var i = 0; i < 18; i++) position,
    ];
    random.shuffle(positions);

    final entries = <FreeAgentEntry>[];
    for (var index = 0; index < FreeAgentPool.expectedSize; index++) {
      final name = names[index];
      final position = positions[index];
      final age = _age(random);
      final targetBase = _targetBase(age, random);
      final attributes = _attributes(
        random: random,
        position: position,
        targetBase: targetBase,
      );
      final overall = attributes.overallRating;
      final potential = (overall + _potentialMargin(age, random)).clamp(
        overall,
        100,
      );
      final trajectory = DevelopmentTrajectory
          .values[random.nextInt(DevelopmentTrajectory.values.length)];
      final player = Player(
        id: PlayerId('free-agent-${index + 1}'),
        firstName: name.$1,
        lastName: name.$2,
        position: position,
        attributes: attributes,
      );
      entries.add(
        FreeAgentEntry(
          player: player,
          profile: PlayerCareerProfile(
            playerId: player.id,
            age: age,
            potential: potential,
            trajectory: trajectory,
          ),
        ),
      );
    }
    final pool = FreeAgentPool(entries: entries);
    pool.validateInitialGeneration();
    return pool;
  }

  static int _age(DeterministicRandom random) {
    final roll = random.nextInt(100);
    if (roll < 35) return 20 + random.nextInt(4);
    if (roll < 75) return 24 + random.nextInt(6);
    return 30 + random.nextInt(7);
  }

  static int _targetBase(int age, DeterministicRandom random) {
    if (age <= 23) return 56 + random.nextInt(15);
    if (age <= 29) return 62 + random.nextInt(19);
    return 58 + random.nextInt(18);
  }

  static int _potentialMargin(int age, DeterministicRandom random) {
    if (age <= 21) return 8 + random.nextInt(21);
    if (age <= 24) return 4 + random.nextInt(15);
    if (age <= 28) return 1 + random.nextInt(8);
    return random.nextInt(3);
  }

  static PlayerAttributes _attributes({
    required DeterministicRandom random,
    required Position position,
    required int targetBase,
  }) {
    final offsets = positionAttributeOffsets[position]!;
    final values = <String, int>{};
    for (final attribute in PlayerAttributes.attributeNames) {
      final noise =
          ((random.nextDouble() +
                      random.nextDouble() +
                      random.nextDouble() -
                      1.5) *
                  18)
              .round();
      values[attribute] = (targetBase + offsets[attribute]! + noise)
          .clamp(20, 95)
          .toInt();
    }
    return PlayerAttributes.fromJson(values);
  }
}
