import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../finance/financial_rules.dart';
import '../models/ids.dart';
import 'staff_member.dart';

/// Isolated deterministic staff identities (M011).
///
/// Every value is derived from SHA-256 of a namespaced key, so generation
/// never consumes player-generation or simulation PRNG streams and is stable
/// across runtimes.
abstract final class StaffIdentityGenerator {
  static const String _namespace = 'ballgorithm-staff-identity-v1';

  static const List<String> _firstNames = [
    'Abel',
    'Bram',
    'Cormac',
    'Dorian',
    'Elio',
    'Fenwick',
    'Garrick',
    'Hollis',
    'Isidro',
    'Jarek',
    'Kellan',
    'Lucan',
    'Marlow',
    'Niall',
    'Orrin',
    'Pascal',
    'Quill',
    'Rowan',
    'Soren',
    'Tobin',
    'Ulric',
    'Vance',
    'Wendell',
    'Yorick',
    'Ada',
    'Briony',
    'Celeste',
    'Delphine',
    'Elodie',
    'Freya',
    'Greer',
    'Hazel',
  ];

  static const List<String> _lastNames = [
    'Ashgrove',
    'Blackthorn',
    'Caldmore',
    'Dunleavy',
    'Everhart',
    'Fairbrook',
    'Glenmoor',
    'Hollowell',
    'Ironside',
    'Jessamy',
    'Kestrell',
    'Larchmont',
    'Marrowby',
    'Northcott',
    'Oakhurst',
    'Pellingham',
    'Quarrington',
    'Redfern',
    'Stonebridge',
    'Thistlewood',
    'Underhill',
    'Vantwell',
    'Whitmarsh',
    'Yarborough',
  ];

  /// A fictional person for [id]. Head coaches receive a philosophy.
  static StaffMember person({
    required String id,
    required int generationSeed,
    required StaffCategory role,
    required StaffTier tier,
    StaffEmploymentStatus status = StaffEmploymentStatus.available,
    TeamId? teamId,
    String? commitmentId,
  }) {
    final bytes = sha256
        .convert(utf8.encode('$_namespace|$generationSeed|$id'))
        .bytes;
    int pick(int a, int b, int modulo) => ((bytes[a] << 8) | bytes[b]) % modulo;
    final isCoach = role == StaffCategory.headCoach;
    final age = isCoach ? 38 + pick(4, 5, 28) : 28 + pick(4, 5, 33);
    return StaffMember(
      id: id,
      firstName: _firstNames[pick(0, 1, _firstNames.length)],
      lastName: _lastNames[pick(2, 3, _lastNames.length)],
      age: age,
      role: role,
      tier: tier,
      experienceYears: pick(6, 7, age - 24),
      status: status,
      philosophy: isCoach
          ? CoachPhilosophy.values[pick(8, 9, CoachPhilosophy.values.length)]
          : null,
      teamId: teamId,
      commitmentId: commitmentId,
    );
  }
}
