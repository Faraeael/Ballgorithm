import 'free_agent_acquisition.dart';
import 'ids.dart';
import 'player.dart';
import 'player_attributes.dart';
import 'player_career_profile.dart';
import 'position.dart';

/// One persistent unsigned free agent: player identity plus career profile.
final class FreeAgentEntry {
  const FreeAgentEntry({required this.player, required this.profile});

  factory FreeAgentEntry.fromJson(Map<String, dynamic> json) {
    final rawPlayer = json['player'];
    final rawProfile = json['profile'];
    if (rawPlayer is! Map<String, dynamic> ||
        rawProfile is! Map<String, dynamic>) {
      throw const FormatException('Malformed FreeAgentEntry JSON');
    }
    final player = Player.fromJson(rawPlayer, path: 'freeAgent.player');
    final profile = PlayerCareerProfile.fromJson(rawProfile);
    return FreeAgentEntry(player: player, profile: profile)..validate();
  }

  final Player player;
  final PlayerCareerProfile profile;

  PlayerId get id => player.id;

  /// Public evaluation contract; hidden potential and trajectory are omitted.
  PublicFreeAgentView toPublicView() => PublicFreeAgentView.fromEntry(this);

  void validate() {
    try {
      profile.validate(player);
    } on StateError catch (error) {
      throw FormatException('Invalid free-agent profile: ${error.message}');
    }
    if (profile.age < FreeAgentPool.minAge ||
        profile.age > FreeAgentPool.maxAge) {
      throw FormatException(
        'Free agent age ${profile.age} outside '
        '${FreeAgentPool.minAge}..${FreeAgentPool.maxAge}',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'player': player.toJson(),
    'profile': profile.toJson(),
  };
}

/// Public free-agent information: observable attributes and overall only.
final class PublicFreeAgentView {
  const PublicFreeAgentView({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.position,
    required this.age,
    required this.attributes,
    required this.overallRating,
  });

  factory PublicFreeAgentView.fromEntry(FreeAgentEntry entry) =>
      PublicFreeAgentView(
        id: entry.player.id,
        firstName: entry.player.firstName,
        lastName: entry.player.lastName,
        position: entry.player.position,
        age: entry.profile.age,
        attributes: entry.player.attributes,
        overallRating: entry.player.attributes.overallRating,
      );

  final PlayerId id;
  final String firstName;
  final String lastName;
  final Position position;
  final int age;
  final PlayerAttributes attributes;
  final int overallRating;

  String get fullName => '$firstName $lastName'.trim();

  /// Public payload only: no hidden potential or development trajectory.
  Map<String, Object?> toJson() => {
    'id': id.value,
    'firstName': firstName,
    'lastName': lastName,
    'position': position.shortName,
    'age': age,
    'attributes': attributes.toJson(),
    'overallRating': overallRating,
  };
}

/// The authoritative free-agent population of a GM career.
///
/// The initial generation must contain 90 entries with at least 12 per
/// position; ongoing market state may shrink after authorized acquisitions.
final class FreeAgentPool {
  FreeAgentPool({
    required List<FreeAgentEntry> entries,
    List<PlayerId>? initialPlayerIds,
    FreeAgentAcquisitionLedger? acquisitions,
  }) : entries = List.unmodifiable(entries),
       initialPlayerIds = List.unmodifiable(
         initialPlayerIds ?? [for (final entry in entries) entry.id],
       ),
       acquisitions = acquisitions ?? FreeAgentAcquisitionLedger.empty() {
    validate();
  }

  factory FreeAgentPool.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    if (rawEntries is! List) {
      throw const FormatException('Malformed FreeAgentPool JSON');
    }
    final entries = <FreeAgentEntry>[];
    for (final rawEntry in rawEntries) {
      if (rawEntry is! Map<String, dynamic>) {
        throw const FormatException('Malformed free-agent entry');
      }
      entries.add(FreeAgentEntry.fromJson(rawEntry));
    }
    final rawInitialIds = json['initialPlayerIds'];
    List<PlayerId>? initialPlayerIds;
    if (rawInitialIds != null) {
      if (rawInitialIds is! List) {
        throw const FormatException('Malformed initial free-agent IDs');
      }
      initialPlayerIds = [];
      for (final rawId in rawInitialIds) {
        if (rawId is! String || rawId.trim().isEmpty) {
          throw const FormatException('Malformed initial free-agent ID');
        }
        initialPlayerIds.add(PlayerId(rawId));
      }
    }
    final rawAcquisitions = json['acquisitions'];
    FreeAgentAcquisitionLedger? acquisitions;
    if (rawAcquisitions != null) {
      if (rawAcquisitions is! Map<String, dynamic>) {
        throw const FormatException('Malformed free-agent acquisition ledger');
      }
      acquisitions = FreeAgentAcquisitionLedger.fromJson(rawAcquisitions);
    }
    return FreeAgentPool(
      entries: entries,
      initialPlayerIds: initialPlayerIds,
      acquisitions: acquisitions,
    );
  }

  static const int expectedSize = 90;
  static const int minPerPosition = 12;
  static const int minAge = 20;
  static const int maxAge = 36;

  final List<FreeAgentEntry> entries;

  /// The original generated free-agent identities, frozen at creation.
  final List<PlayerId> initialPlayerIds;

  /// Authoritative acquisition history for this market.
  final FreeAgentAcquisitionLedger acquisitions;

  int get length => entries.length;

  Set<String> get playerIds => {for (final entry in entries) entry.id.value};

  FreeAgentEntry? byId(PlayerId id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  bool contains(PlayerId id) => byId(id) != null;

  void validate() {
    final seen = <String>{};
    for (final entry in entries) {
      entry.validate();
      if (!seen.add(entry.id.value)) {
        throw FormatException('Duplicate free-agent ID: ${entry.id.value}');
      }
    }
    final initialSeen = <String>{};
    for (final id in initialPlayerIds) {
      if (!initialSeen.add(id.value)) {
        throw FormatException('Duplicate initial free-agent ID: ${id.value}');
      }
    }
    for (final id in playerIds) {
      if (!initialSeen.contains(id)) {
        throw FormatException(
          'Free-agent $id is not part of the initial identity snapshot',
        );
      }
    }
    for (final acquisition in acquisitions.entries.values) {
      final id = acquisition.playerId.value;
      if (!initialSeen.contains(id)) {
        throw FormatException(
          'Acquisition references unknown free-agent identity $id',
        );
      }
      final stillAvailable = playerIds.contains(id);
      if (stillAvailable) {
        throw FormatException(
          'Acquired free-agent $id is still in the available pool',
        );
      }
    }
    for (final id in initialPlayerIds) {
      final available = playerIds.contains(id.value);
      final acquired = acquisitions.hasPlayer(id);
      if (available == acquired) {
        throw FormatException(
          available
              ? 'Initial free-agent ${id.value} is both available and acquired'
              : 'Initial free-agent ${id.value} is missing without an '
                    'acquisition record',
        );
      }
    }
  }

  /// Enforces the frozen initial-generation contract. Called by the generator,
  /// not by ongoing market validation.
  void validateInitialGeneration() {
    validate();
    if (entries.length != expectedSize) {
      throw FormatException(
        'Invalid initial free-agent pool size: expected $expectedSize, '
        'got ${entries.length}',
      );
    }
    final positionCounts = <Position, int>{};
    for (final entry in entries) {
      positionCounts[entry.player.position] =
          (positionCounts[entry.player.position] ?? 0) + 1;
    }
    for (final position in Position.values) {
      if ((positionCounts[position] ?? 0) < minPerPosition) {
        throw FormatException(
          'Position ${position.shortName} has fewer than '
          '$minPerPosition initial free agents',
        );
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'entries': [for (final entry in entries) entry.toJson()],
    'initialPlayerIds': [for (final id in initialPlayerIds) id.value],
    'acquisitions': acquisitions.toJson(),
  };
}
