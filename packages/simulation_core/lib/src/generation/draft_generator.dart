import '../models/draft_order.dart';
import '../models/draft_pick.dart';
import '../models/franchise_situation.dart';
import '../models/ids.dart';
import '../models/league.dart';
import '../models/player_attributes.dart';
import '../models/player_career_profile.dart';
import '../models/position.dart';
import '../models/rookie_draft_class.dart';
import '../models/rookie_prospect.dart';
import 'deterministic_random.dart';
import 'name_corpus.dart';

/// Generates deterministic rookie draft classes and 2-round draft orders
/// for 30-team GM career mode.
final class DraftGenerator {
  const DraftGenerator();

  /// Generates the complete 2-round, 60-pick opening draft order.
  DraftOrder generateDraftOrder({
    required League league,
    required int seed,
    required TeamId userTeamId,
    required FranchiseSituation userSituation,
  }) {
    if (league.teams.length != 30) {
      throw ArgumentError.value(
        league.teams.length,
        'league.teams.length',
        'Expected 30 teams for draft order generation',
      );
    }

    final rng = DeterministicRandom((seed ^ 0xD8AF7001) & 0x7FFFFFFF);

    // Group franchises by competitive situation tier
    final tankingTeams = <TeamId>[];
    final playInTeams = <TeamId>[];
    final playoffTeams = <TeamId>[];
    final contenderTeams = <TeamId>[];

    for (final team in league.teams) {
      final situation = team.situation ?? FranchiseSituation.playIn;
      switch (situation) {
        case FranchiseSituation.tanking:
          tankingTeams.add(team.id);
        case FranchiseSituation.playIn:
          playInTeams.add(team.id);
        case FranchiseSituation.playoff:
          playoffTeams.add(team.id);
        case FranchiseSituation.contender:
          contenderTeams.add(team.id);
      }
    }

    // Sort team IDs canonically before shuffling for repeatable baseline order
    tankingTeams.sort((a, b) => a.value.compareTo(b.value));
    playInTeams.sort((a, b) => a.value.compareTo(b.value));
    playoffTeams.sort((a, b) => a.value.compareTo(b.value));
    contenderTeams.sort((a, b) => a.value.compareTo(b.value));

    // Round 1 team allocation (1..30)
    final round1Order = List<TeamId?>.filled(30, null);

    void allocateTier({
      required List<TeamId> tierTeams,
      required int startPick,
      required int endPick,
      required int? guaranteedUserPick,
    }) {
      final availablePicks = [for (var p = startPick; p <= endPick; p++) p];

      final teamsToPlace = List<TeamId>.from(tierTeams);

      if (guaranteedUserPick != null && teamsToPlace.contains(userTeamId)) {
        round1Order[guaranteedUserPick - 1] = userTeamId;
        availablePicks.remove(guaranteedUserPick);
        teamsToPlace.remove(userTeamId);
      }

      rng.shuffle(teamsToPlace);
      for (var i = 0; i < teamsToPlace.length; i++) {
        round1Order[availablePicks[i] - 1] = teamsToPlace[i];
      }
    }

    // Tier 1: Tanking (Picks 1..7)
    allocateTier(
      tierTeams: tankingTeams,
      startPick: 1,
      endPick: 7,
      guaranteedUserPick: userSituation == FranchiseSituation.tanking
          ? 1
          : null,
    );

    // Tier 2: Play-In (Picks 8..16)
    allocateTier(
      tierTeams: playInTeams,
      startPick: 8,
      endPick: 16,
      guaranteedUserPick: userSituation == FranchiseSituation.playIn
          ? 12
          : null,
    );

    // Tier 3: Playoff (Picks 17..25)
    allocateTier(
      tierTeams: playoffTeams,
      startPick: 17,
      endPick: 25,
      guaranteedUserPick: userSituation == FranchiseSituation.playoff
          ? 20
          : null,
    );

    // Tier 4: Contender (Picks 26..30)
    allocateTier(
      tierTeams: contenderTeams,
      startPick: 26,
      endPick: 30,
      guaranteedUserPick: userSituation == FranchiseSituation.contender
          ? 30
          : null,
    );

    final picks = <DraftPick>[];

    // Build Round 1 picks
    for (var i = 0; i < 30; i++) {
      final teamId = round1Order[i]!;
      picks.add(
        DraftPick(
          round: 1,
          pickInRound: i + 1,
          overallPick: i + 1,
          originalOwnerTeamId: teamId,
          currentOwnerTeamId: teamId,
        ),
      );
    }

    // Round 2 mirrors Round 1 ordering initially (Picks 31..60)
    for (var i = 0; i < 30; i++) {
      final originalTeamId = round1Order[i]!;
      picks.add(
        DraftPick(
          round: 2,
          pickInRound: i + 1,
          overallPick: 30 + i + 1,
          originalOwnerTeamId: originalTeamId,
          currentOwnerTeamId: originalTeamId,
        ),
      );
    }

    return DraftOrder(picks: picks);
  }

  /// Generates exactly 90 unique rookie prospects with public rankings and hidden potentials.
  RookieDraftClass generateDraftClass({
    required League league,
    required int seed,
    int seasonYear = 1,
  }) {
    final rng = DeterministicRandom((seed ^ 0x5EE00090) & 0x7FFFFFFF);

    // Collect existing names from league to avoid duplicate full names
    final existingNames = <String>{};
    for (final team in league.teams) {
      for (final player in team.players) {
        existingNames.add(player.fullName);
      }
    }

    // Available unique name pairs from corpus not in existing league
    final namePairs = <(String, String)>[];
    for (final fn in firstNames) {
      for (final ln in lastNames) {
        final fullName = '$fn $ln';
        if (!existingNames.contains(fullName)) {
          namePairs.add((fn, ln));
        }
      }
    }
    rng.shuffle(namePairs);

    // Position allocation: 18 for each of the 5 canonical positions = 90
    final positions = <Position>[
      ...List.filled(18, Position.pg),
      ...List.filled(18, Position.sg),
      ...List.filled(18, Position.sf),
      ...List.filled(18, Position.pf),
      ...List.filled(18, Position.c),
    ];
    rng.shuffle(positions);

    // Internal raw prospect representations
    final rawProspects = <_RawProspect>[];

    for (var i = 0; i < 90; i++) {
      final name = namePairs[i];
      final pos = positions[i];

      // Biological age: 19..22 with realistic distribution
      final ageRoll = rng.nextInt(10);
      final int age;
      if (ageRoll < 4) {
        age = 19; // 40% freshmen/young international
      } else if (ageRoll < 7) {
        age = 20; // 30% sophomores
      } else if (ageRoll < 9) {
        age = 21; // 20% juniors
      } else {
        age = 22; // 10% seniors
      }

      // Archetype & talent distribution
      // Base talent tier:
      // Index 0..7: Elite tier
      // Index 8..23: High starter/lottery tier
      // Index 24..54: Rotation/fringe starter tier
      // Index 55..89: Developmental/sleeper tier
      final int baseRating;
      final int upsideMargin;
      final DevelopmentTrajectory trajectory;

      if (i < 8) {
        // Elite tier
        baseRating = 58 + rng.nextInt(10); // 58..67
        upsideMargin = 20 + rng.nextInt(16); // +20..35
        trajectory = age <= 20
            ? (rng.nextInt(2) == 0
                  ? DevelopmentTrajectory.volatile
                  : DevelopmentTrajectory.steady)
            : DevelopmentTrajectory.earlyBloomer;
      } else if (i < 24) {
        // High lottery tier
        baseRating = 53 + rng.nextInt(9); // 53..61
        upsideMargin = 15 + rng.nextInt(15); // +15..29
        trajectory = DevelopmentTrajectory.values[rng.nextInt(4)];
      } else if (i < 55) {
        // Rotation / depth tier
        baseRating = 48 + rng.nextInt(8); // 48..55
        upsideMargin = 10 + rng.nextInt(16); // +10..25
        trajectory = age >= 21
            ? DevelopmentTrajectory.earlyBloomer
            : (rng.nextInt(2) == 0
                  ? DevelopmentTrajectory.steady
                  : DevelopmentTrajectory.lateBloomer);
      } else {
        // Developmental / sleeper / late-round tier
        baseRating = 42 + rng.nextInt(9); // 42..50
        // Some late sleepers have surprise upside
        final isSleeper = rng.nextInt(5) == 0;
        upsideMargin = isSleeper
            ? (16 + rng.nextInt(12))
            : (5 + rng.nextInt(12));
        trajectory = isSleeper
            ? DevelopmentTrajectory.lateBloomer
            : DevelopmentTrajectory.steady;
      }

      final attributes = _generateProspectAttributes(rng, pos, baseRating);

      final overall = attributes.overallRating;
      // Potential must be >= overall and <= 100
      final potential = (overall + upsideMargin).clamp(overall, 99);

      // Imperfect evaluation score: mixture of current ability, potential, and estimation noise
      // Noise creates realistic draft day surprises (underrated steals & overrated busts)
      final evaluationNoise = rng.nextInt(25) - 12; // -12..+12
      final perceivedScore =
          (overall * 0.45) + (potential * 0.55) + evaluationNoise;

      // Estimated potential grade and range for public scouting view
      final potNoise = rng.nextInt(7) - 3; // -3..+3
      final estimatedPotential = (potential + potNoise).clamp(overall, 100);

      final String grade;
      if (estimatedPotential >= 90) {
        grade = 'A+';
      } else if (estimatedPotential >= 85) {
        grade = 'A';
      } else if (estimatedPotential >= 80) {
        grade = 'A-';
      } else if (estimatedPotential >= 75) {
        grade = 'B+';
      } else if (estimatedPotential >= 70) {
        grade = 'B';
      } else if (estimatedPotential >= 65) {
        grade = 'B-';
      } else if (estimatedPotential >= 60) {
        grade = 'C+';
      } else {
        grade = 'C';
      }

      final rangeLow = (estimatedPotential - 3).clamp(overall, 100);
      final rangeHigh = (estimatedPotential + 3).clamp(rangeLow, 100);
      final range = '$rangeLow–$rangeHigh';

      rawProspects.add(
        _RawProspect(
          firstName: name.$1,
          lastName: name.$2,
          position: pos,
          age: age,
          attributes: attributes,
          potential: potential,
          trajectory: trajectory,
          perceivedScore: perceivedScore,
          estimatedPotentialGrade: grade,
          estimatedPotentialRange: range,
        ),
      );
    }

    // Sort by perceivedScore descending to establish public projected rank
    rawProspects.sort((a, b) {
      final cmp = b.perceivedScore.compareTo(a.perceivedScore);
      if (cmp != 0) return cmp;
      return a.lastName.compareTo(b.lastName);
    });

    final prospects = <RookieProspect>[];
    for (var r = 0; r < rawProspects.length; r++) {
      final raw = rawProspects[r];
      final rank = r + 1;
      prospects.add(
        RookieProspect(
          id: PlayerId('prospect-y$seasonYear-$rank'),
          firstName: raw.firstName,
          lastName: raw.lastName,
          position: raw.position,
          age: raw.age,
          attributes: raw.attributes,
          potential: raw.potential,
          trajectory: raw.trajectory,
          projectedRank: rank,
          estimatedPotentialGrade: raw.estimatedPotentialGrade,
          estimatedPotentialRange: raw.estimatedPotentialRange,
        ),
      );
    }

    return RookieDraftClass(seasonYear: seasonYear, prospects: prospects);
  }

  static PlayerAttributes _generateProspectAttributes(
    DeterministicRandom rng,
    Position position,
    int targetBaseRating,
  ) {
    final offsets = _positionOffsets[position]!;
    final styleMod = rng.nextInt(3);

    int rating(String attribute) {
      final noise = rng.nextInt(7) - 3; // -3..+3
      var styleOffset = 0;

      if (styleMod == 0) {
        if (attribute == 'threePoint' || attribute == 'midrange') {
          styleOffset = 3;
        }
      } else if (styleMod == 1) {
        if (attribute == 'interiorDefense' || attribute == 'rebounding') {
          styleOffset = 3;
        }
      } else {
        if (attribute == 'athleticism' || attribute == 'stamina') {
          styleOffset = 3;
        }
      }

      return (targetBaseRating + offsets[attribute]! + styleOffset + noise)
          .clamp(0, 100);
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

  static const Map<Position, Map<String, int>> _positionOffsets = {
    Position.pg: {
      'insideScoring': -8,
      'midrange': 4,
      'threePoint': 6,
      'freeThrow': 6,
      'passing': 14,
      'ballHandling': 16,
      'perimeterDefense': 2,
      'interiorDefense': -14,
      'rebounding': -18,
      'athleticism': 6,
      'stamina': 4,
      'basketballIQ': 6,
    },
    Position.sg: {
      'insideScoring': -4,
      'midrange': 8,
      'threePoint': 12,
      'freeThrow': 6,
      'passing': 0,
      'ballHandling': 8,
      'perimeterDefense': 4,
      'interiorDefense': -8,
      'rebounding': -12,
      'athleticism': 10,
      'stamina': 2,
      'basketballIQ': 2,
    },
    Position.sf: {
      'insideScoring': 4,
      'midrange': 4,
      'threePoint': 4,
      'freeThrow': 0,
      'passing': 0,
      'ballHandling': 0,
      'perimeterDefense': 6,
      'interiorDefense': 2,
      'rebounding': 2,
      'athleticism': 8,
      'stamina': 4,
      'basketballIQ': 2,
    },
    Position.pf: {
      'insideScoring': 10,
      'midrange': 2,
      'threePoint': -8,
      'freeThrow': -4,
      'passing': -4,
      'ballHandling': -8,
      'perimeterDefense': -4,
      'interiorDefense': 8,
      'rebounding': 10,
      'athleticism': 4,
      'stamina': 2,
      'basketballIQ': 0,
    },
    Position.c: {
      'insideScoring': 14,
      'midrange': -4,
      'threePoint': -16,
      'freeThrow': -8,
      'passing': -6,
      'ballHandling': -12,
      'perimeterDefense': -10,
      'interiorDefense': 14,
      'rebounding': 16,
      'athleticism': 0,
      'stamina': 0,
      'basketballIQ': 2,
    },
  };
}

final class _RawProspect {
  const _RawProspect({
    required this.firstName,
    required this.lastName,
    required this.position,
    required this.age,
    required this.attributes,
    required this.potential,
    required this.trajectory,
    required this.perceivedScore,
    required this.estimatedPotentialGrade,
    required this.estimatedPotentialRange,
  });

  final String firstName;
  final String lastName;
  final Position position;
  final int age;
  final PlayerAttributes attributes;
  final int potential;
  final DevelopmentTrajectory trajectory;
  final double perceivedScore;
  final String estimatedPotentialGrade;
  final String estimatedPotentialRange;
}
