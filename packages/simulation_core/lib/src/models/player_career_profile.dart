import '../generation/deterministic_random.dart';
import 'franchise_situation.dart';
import 'ids.dart';
import 'league.dart';
import 'player.dart';

/// Trajectory of a player's career development curve.
enum DevelopmentTrajectory {
  earlyBloomer(
    'earlyBloomer',
    displayName: 'Early Bloomer',
    description:
        'Reaches peak ability early (age 21–24); earlier plateau and decline.',
  ),
  steady(
    'steady',
    displayName: 'Steady Progression',
    description: 'Predictable standard progression peaking around age 25–28.',
  ),
  lateBloomer(
    'lateBloomer',
    displayName: 'Late Bloomer',
    description:
        'Slower initial development with a surge in mid-to-late 20s (age 26–30).',
  ),
  volatile(
    'volatile',
    displayName: 'Wildcard / Volatile',
    description:
        'Unpredictable progression with higher variance in ceiling outcomes.',
  );

  const DevelopmentTrajectory(
    this.jsonValue, {
    required this.displayName,
    required this.description,
  });

  final String jsonValue;
  final String displayName;
  final String description;

  static DevelopmentTrajectory fromJson(String value) => values.firstWhere(
    (e) => e.jsonValue == value || e.name == value,
    orElse: () => throw ArgumentError.value(
      value,
      'trajectory',
      'Unknown development trajectory',
    ),
  );
}

/// Career metadata for one player, isolated from simulation-relevant attributes.
///
/// Contains biological age, development ceiling potential (0..100), and
/// progression trajectory curve. Does NOT affect in-game simulation probabilities
/// or GameFingerprint.
final class PlayerCareerProfile {
  const PlayerCareerProfile({
    required this.playerId,
    required this.age,
    required this.potential,
    required this.trajectory,
  });

  factory PlayerCareerProfile.fromJson(Map<String, dynamic> json) {
    final rawId = json['playerId'] as String?;
    final rawAge = json['age'] as int?;
    final rawPotential = json['potential'] as int?;
    final rawTrajectory = json['trajectory'] as String?;

    if (rawId == null ||
        rawAge == null ||
        rawPotential == null ||
        rawTrajectory == null) {
      throw const FormatException('Malformed PlayerCareerProfile JSON');
    }

    if (rawAge < minAge || rawAge > maxAge) {
      throw FormatException(
        'Age $rawAge is outside valid range $minAge..$maxAge',
      );
    }
    if (rawPotential < 0 || rawPotential > 100) {
      throw FormatException('Potential $rawPotential is outside 0..100');
    }

    return PlayerCareerProfile(
      playerId: PlayerId(rawId),
      age: rawAge,
      potential: rawPotential,
      trajectory: DevelopmentTrajectory.fromJson(rawTrajectory),
    );
  }

  static const int minAge = 19;
  static const int maxAge = 38;

  final PlayerId playerId;
  final int age;
  final int potential;
  final DevelopmentTrajectory trajectory;

  /// Validates profile against player attributes. Potential must be >= current overall.
  void validate(Player player) {
    if (player.id != playerId) {
      throw StateError(
        'Profile player ID (${playerId.value}) does not match player (${player.id.value})',
      );
    }
    if (age < minAge || age > maxAge) {
      throw StateError('Age $age outside valid bounds $minAge..$maxAge');
    }
    final overall = player.attributes.overallRating;
    if (potential < overall || potential > 100) {
      throw StateError(
        'Potential $potential must be between current overall ($overall) and 100',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'playerId': playerId.value,
    'age': age,
    'potential': potential,
    'trajectory': trajectory.jsonValue,
  };
}

/// Collection of career profiles for all players in a league.
///
/// Versioned independently of M001 league snapshots and M007 season state.
final class LeagueCareerProfiles {
  LeagueCareerProfiles({
    this.schemaVersion = currentSchemaVersion,
    required this.leagueSeed,
    required Map<String, PlayerCareerProfile> profiles,
  }) : profiles = Map.unmodifiable(profiles);

  factory LeagueCareerProfiles.fromJson(Map<String, dynamic> json) {
    final version = json['schemaVersion'] as int?;
    final seed = json['leagueSeed'] as int?;
    final rawMap = json['profiles'] as Map<String, dynamic>?;

    if (version == null || version != currentSchemaVersion) {
      throw FormatException(
        'Unsupported career profiles schema version: $version (expected $currentSchemaVersion)',
      );
    }
    if (seed == null) {
      throw const FormatException('Missing leagueSeed in career profiles JSON');
    }
    if (rawMap == null) {
      throw const FormatException(
        'Missing profiles map in career profiles JSON',
      );
    }

    final parsed = <String, PlayerCareerProfile>{};
    for (final entry in rawMap.entries) {
      parsed[entry.key] = PlayerCareerProfile.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }

    return LeagueCareerProfiles(
      schemaVersion: version,
      leagueSeed: seed,
      profiles: parsed,
    );
  }

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final int leagueSeed;
  final Map<String, PlayerCareerProfile> profiles;

  int get length => profiles.length;

  PlayerCareerProfile? forPlayer(PlayerId id) => profiles[id.value];

  /// Generates career profiles deterministically for a 30-team league.
  /// Uses an independent PRNG stream to preserve attribute draw sequences.
  static LeagueCareerProfiles generate({
    required League league,
    required int seed,
  }) {
    final rng = DeterministicRandom((seed ^ 0xCA5EE800) & 0x7FFFFFFF);
    final profileMap = <String, PlayerCareerProfile>{};

    for (final team in league.teams) {
      final situation = team.situation ?? FranchiseSituation.playIn;

      for (var p = 0; p < team.players.length; p++) {
        final player = team.players[p];
        final currentOverall = player.attributes.overallRating;

        // 1. Generate plausible biological age (19..38) based on situation
        final age = _generateAge(rng, situation);

        // 2. Trajectory curve
        final trajectory = DevelopmentTrajectory
            .values[rng.nextInt(DevelopmentTrajectory.values.length)];

        // 3. Potential ceiling: realistic upside margin above current overall based on age
        final potential = _generatePotential(
          rng,
          situation,
          currentOverall,
          age,
        );

        final profile = PlayerCareerProfile(
          playerId: player.id,
          age: age,
          potential: potential,
          trajectory: trajectory,
        );
        profileMap[player.id.value] = profile;
      }
    }

    final result = LeagueCareerProfiles(leagueSeed: seed, profiles: profileMap);
    result.validate(league);
    return result;
  }

  static int _generateAge(
    DeterministicRandom rng,
    FranchiseSituation situation,
  ) {
    final roll = rng.nextInt(100);
    switch (situation) {
      case FranchiseSituation.tanking:
        // 75% young (19..24), 15% mid (25..29), 10% veterans (30..34)
        if (roll < 75) {
          return 19 + rng.nextInt(6);
        } else if (roll < 90) {
          return 25 + rng.nextInt(5);
        } else {
          return 30 + rng.nextInt(5);
        }
      case FranchiseSituation.playIn:
        // 30% young (20..24), 50% prime (25..30), 20% veterans (31..35)
        if (roll < 30) {
          return 20 + rng.nextInt(5);
        } else if (roll < 80) {
          return 25 + rng.nextInt(6);
        } else {
          return 31 + rng.nextInt(5);
        }
      case FranchiseSituation.playoff:
        // 20% young (21..24), 60% prime (25..30), 20% veterans (31..36)
        if (roll < 20) {
          return 21 + rng.nextInt(4);
        } else if (roll < 80) {
          return 25 + rng.nextInt(6);
        } else {
          return 31 + rng.nextInt(6);
        }
      case FranchiseSituation.contender:
        // 15% young (22..25), 55% prime (26..31), 30% veteran core (32..38)
        if (roll < 15) {
          return 22 + rng.nextInt(4);
        } else if (roll < 70) {
          return 26 + rng.nextInt(6);
        } else {
          return 32 + rng.nextInt(7);
        }
    }
  }

  static int _generatePotential(
    DeterministicRandom rng,
    FranchiseSituation situation,
    int currentOverall,
    int age,
  ) {
    // Remaining development upside diminishes naturally with age
    int maxMargin;
    int minMargin;

    if (age <= 21) {
      minMargin = 8;
      maxMargin = 28;
    } else if (age <= 24) {
      minMargin = 4;
      maxMargin = 18;
    } else if (age <= 28) {
      minMargin = 1;
      maxMargin = 8;
    } else {
      // Age 29+: at peak or past peak
      minMargin = 0;
      maxMargin = 2;
    }

    // Situation upside bias: rebuilding prospects receive extra upside margin
    if (situation == FranchiseSituation.tanking && age <= 23) {
      maxMargin += 4;
    }

    final span = (maxMargin - minMargin + 1).clamp(1, 100);
    final margin = minMargin + rng.nextInt(span);
    return (currentOverall + margin).clamp(currentOverall, 100);
  }

  /// Validates that all league players have a unique, consistent profile.
  void validate(League league) {
    final playerIds = <String>{};
    for (final team in league.teams) {
      for (final player in team.players) {
        playerIds.add(player.id.value);
        final profile = profiles[player.id.value];
        if (profile == null) {
          throw StateError(
            'Missing career profile for player ${player.id.value}',
          );
        }
        profile.validate(player);
      }
    }

    for (final key in profiles.keys) {
      if (!playerIds.contains(key)) {
        throw StateError('Foreign player profile found: $key');
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'leagueSeed': leagueSeed,
    'profiles': {
      for (final entry in profiles.entries) entry.key: entry.value.toJson(),
    },
  };
}
