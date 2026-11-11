/// Canonical NBA-aligned player roster contract categories for GM Career mode.
enum RosterCategory {
  standard(
    'standard',
    displayName: 'Standard',
    description:
        'Active standard player contract. Eligible for regular season and active game rotation.',
  ),
  twoWay(
    'twoWay',
    displayName: 'Two-Way',
    description:
        'Developmental two-way contract. Does not count against 15-player standard roster cap.',
  ),
  trainingCamp(
    'trainingCamp',
    displayName: 'Training Camp',
    description:
        'Offseason camp invitee contract. Permitted only during offseason phases.',
  );

  const RosterCategory(
    this.jsonValue, {
    required this.displayName,
    required this.description,
  });

  final String jsonValue;
  final String displayName;
  final String description;

  static RosterCategory fromJson(String value) => values.firstWhere(
    (e) => e.jsonValue == value || e.name == value,
    orElse: () => throw ArgumentError.value(
      value,
      'category',
      'Unknown roster category: $value',
    ),
  );
}
