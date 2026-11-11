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
final class FreeAgentPool {
  FreeAgentPool({required List<FreeAgentEntry> entries})
    : entries = List.unmodifiable(entries) {
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
    return FreeAgentPool(entries: entries);
  }

  static const int expectedSize = 90;
  static const int minPerPosition = 12;
  static const int minAge = 20;
  static const int maxAge = 36;

  final List<FreeAgentEntry> entries;

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
    if (entries.length != expectedSize) {
      throw FormatException(
        'Invalid free-agent pool size: expected $expectedSize, '
        'got ${entries.length}',
      );
    }
    final seen = <String>{};
    final positionCounts = <Position, int>{};
    for (final entry in entries) {
      entry.validate();
      if (!seen.add(entry.id.value)) {
        throw FormatException('Duplicate free-agent ID: ${entry.id.value}');
      }
      positionCounts[entry.player.position] =
          (positionCounts[entry.player.position] ?? 0) + 1;
    }
    for (final position in Position.values) {
      if ((positionCounts[position] ?? 0) < minPerPosition) {
        throw FormatException(
          'Position ${position.shortName} has fewer than '
          '$minPerPosition free agents',
        );
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'entries': [for (final entry in entries) entry.toJson()],
  };
}
