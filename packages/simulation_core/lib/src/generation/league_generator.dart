import '../models/franchise_situation.dart';
import '../models/generation_config.dart';
import '../models/ids.dart';
import '../models/league.dart';
import '../models/player.dart';
import '../models/player_attributes.dart';
import '../models/position.dart';
import '../models/roster.dart';
import '../models/team.dart';
import '../validation/validation_result.dart';
import 'deterministic_random.dart';
import 'name_corpus.dart';
import 'position_attribute_offsets.dart';

/// Builds a complete fictional league from a seed.
///
/// Draw order is part of the contract: team order by catalog, then per team
/// position shuffle, then per player name pair and attributes in
/// [PlayerAttributes.attributeNames] order.
final class LeagueGenerator {
  const LeagueGenerator();

  /// Mean rating before positional offsets and noise.
  static const int baseRating = 52;

  League generate(
    GenerationConfig config, {
    TeamId? userTeamId,
    FranchiseSituation? userSituation,
  }) {
    config.validateForEngine().throwIfInvalid();
    final requestedPlayers = config.teamCount * config.playersPerTeam;
    if (requestedPlayers > namePairCapacity) {
      throw DomainValidationException([
        ValidationIssue(
          code: ValidationCode.nameCapacityExceeded,
          path: 'generation.playersPerTeam',
          message:
              'teamCount * playersPerTeam ($requestedPlayers) exceeds '
              'the $namePairCapacity unique player names available',
        ),
      ]);
    }

    final random = DeterministicRandom(config.seed);
    final names = _namePairs();
    random.shuffle(names);
    var nameCursor = 0;

    final teams = <Team>[];

    if (config.teamCount <= 8) {
      // Legacy M001 generation: preserved 100% byte-identical
      for (var t = 0; t < config.teamCount; t++) {
        final seedTeam = teamCatalog[t];
        final positions = [
          for (var p = 0; p < config.playersPerTeam; p++)
            Position.values[p % Position.values.length],
        ];
        random.shuffle(positions);

        final players = <Player>[];
        for (var p = 0; p < config.playersPerTeam; p++) {
          final name = names[nameCursor++];
          players.add(
            Player(
              id: PlayerId('player-${t + 1}-${p + 1}'),
              firstName: name.$1,
              lastName: name.$2,
              position: positions[p],
              attributes: _generateAttributes(random, positions[p]),
            ),
          );
        }

        teams.add(
          Team(
            id: TeamId(seedTeam.id),
            name: seedTeam.name,
            abbreviation: seedTeam.abbreviation,
            roster: Roster(players),
          ),
        );
      }
    } else {
      // Expanded 30-team M008 generation with competitive situations
      final situations = <FranchiseSituation>[
        ...List.filled(5, FranchiseSituation.contender),
        ...List.filled(9, FranchiseSituation.playoff),
        ...List.filled(9, FranchiseSituation.playIn),
        ...List.filled(7, FranchiseSituation.tanking),
      ];
      final situationRng = DeterministicRandom(config.seed ^ 0x51704710);
      situationRng.shuffle(situations);

      if (userTeamId != null || userSituation != null) {
        if (userTeamId == null || userSituation == null) {
          throw ArgumentError(
            'Both userTeamId and userSituation must be provided together for career generation',
          );
        }
        final userIndex = teamCatalog.indexWhere(
          (t) => t.id == userTeamId.value,
        );
        if (userIndex == -1) {
          throw ArgumentError.value(
            userTeamId.value,
            'userTeamId',
            'Unknown franchise ID: ${userTeamId.value}',
          );
        }
        if (situations[userIndex] != userSituation) {
          final swapIndex = situations.indexWhere((s) => s == userSituation);
          if (swapIndex != -1) {
            final temp = situations[userIndex];
            situations[userIndex] = situations[swapIndex];
            situations[swapIndex] = temp;
          }
        }
      }
      for (var t = 0; t < config.teamCount; t++) {
        final seedTeam = teamCatalog[t];
        final situation = situations[t];

        // First 5 players cover all 5 positions (starting five)
        final starterPositions = List<Position>.of(Position.values);
        random.shuffle(starterPositions);

        final benchPositions = [
          for (var p = 0; p < config.playersPerTeam - 5; p++)
            Position.values[p % Position.values.length],
        ];
        random.shuffle(benchPositions);
        final positions = [...starterPositions, ...benchPositions];

        final players = <Player>[];
        for (var p = 0; p < config.playersPerTeam; p++) {
          final name = names[nameCursor++];
          final isStarter = p < 5;

          // Starters vs bench base ratings with star-player tiering
          int targetBase;
          if (isStarter) {
            targetBase = situation.baseStarterRating;
            if (p == 0) targetBase += 4; // Primary star
            if (p == 1) targetBase += 2; // Secondary star
          } else {
            targetBase = situation.baseBenchRating;
            if (p == 5) targetBase += 3; // 6th man
          }

          players.add(
            Player(
              id: PlayerId('player-${t + 1}-${p + 1}'),
              firstName: name.$1,
              lastName: name.$2,
              position: positions[p],
              attributes: _generateSituationAttributes(
                random: random,
                position: positions[p],
                targetBaseRating: targetBase,
                teamIndex: t,
              ),
            ),
          );
        }

        teams.add(
          Team(
            id: TeamId(seedTeam.id),
            name: seedTeam.name,
            abbreviation: seedTeam.abbreviation,
            roster: Roster(players),
            situation: situation,
          ),
        );
      }
    }
    return League.create(
      id: LeagueId('league-${config.seed}'),
      name: 'Fictional League ${config.seed}',
      config: config,
      teams: teams,
    );
  }

  /// Every first/last name combination, so a shuffle yields unique names.
  static List<(String, String)> _namePairs() => [
    for (final first in firstNames)
      for (final last in lastNames) (first, last),
  ];

  static PlayerAttributes _generateAttributes(
    DeterministicRandom random,
    Position position,
  ) {
    final offsets = positionAttributeOffsets[position]!;

    int rating(String attribute) {
      // Irwin-Hall(3) noise, mean 0, roughly -27..+27.
      final noise =
          ((random.nextDouble() +
                      random.nextDouble() +
                      random.nextDouble() -
                      1.5) *
                  18)
              .round();
      return (baseRating + offsets[attribute]! + noise).clamp(0, 100).toInt();
    }

    return PlayerAttributes(
      insideScoring: rating('insideScoring'),
      midrange: rating('midrange'),
      threePoint: rating('threePoint'),
      freeThrow: rating('freeThrow'),
      passing: rating('passing'),
      ballHandling: rating('ballHandling'),
      perimeterDefense: rating('perimeterDefense'),
      interiorDefense: rating('interiorDefense'),
      rebounding: rating('rebounding'),
      athleticism: rating('athleticism'),
      stamina: rating('stamina'),
      basketballIQ: rating('basketballIQ'),
    );
  }

  static PlayerAttributes _generateSituationAttributes({
    required DeterministicRandom random,
    required Position position,
    required int targetBaseRating,
    required int teamIndex,
  }) {
    final offsets = positionAttributeOffsets[position]!;
    // Style bias per team based on teamIndex
    final styleMod = (teamIndex % 3);

    int rating(String attribute) {
      final noise =
          ((random.nextDouble() +
                      random.nextDouble() +
                      random.nextDouble() -
                      1.5) *
                  18)
              .round();

      var styleOffset = 0;
      if (styleMod == 0) {
        // Perimeter / shooting bias
        if (attribute == 'threePoint' || attribute == 'midrange') {
          styleOffset = 2;
        }
      } else if (styleMod == 1) {
        // Interior / defensive bias
        if (attribute == 'interiorDefense' || attribute == 'rebounding') {
          styleOffset = 2;
        }
      } else {
        // Athleticism & transition bias
        if (attribute == 'athleticism' || attribute == 'stamina') {
          styleOffset = 2;
        }
      }

      return (targetBaseRating + offsets[attribute]! + styleOffset + noise)
          .clamp(0, 100)
          .toInt();
    }

    return PlayerAttributes(
      insideScoring: rating('insideScoring'),
      midrange: rating('midrange'),
      threePoint: rating('threePoint'),
      freeThrow: rating('freeThrow'),
      passing: rating('passing'),
      ballHandling: rating('ballHandling'),
      perimeterDefense: rating('perimeterDefense'),
      interiorDefense: rating('interiorDefense'),
      rebounding: rating('rebounding'),
      athleticism: rating('athleticism'),
      stamina: rating('stamina'),
      basketballIQ: rating('basketballIQ'),
    );
  }
}
