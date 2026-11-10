/// Competitive franchise situations for GM Career mode.
enum FranchiseSituation {
  tanking(
    'tanking',
    displayName: 'Tanking / Rebuilding',
    description:
        'Rebuilding roster with low current strength and future draft focus.',
    userOpeningDraftPick: 1,
    baseStarterRating: 46,
    baseBenchRating: 40,
  ),
  playIn(
    'playIn',
    displayName: 'Play-In Contender',
    description:
        'Middle-tier competitive roster with reliable starters and clear weaknesses.',
    userOpeningDraftPick: 12,
    baseStarterRating: 54,
    baseBenchRating: 46,
  ),
  playoff(
    'playoff',
    displayName: 'Playoff Team',
    description:
        'Strong established roster with high-quality starters and competitive depth.',
    userOpeningDraftPick: 20,
    baseStarterRating: 62,
    baseBenchRating: 52,
  ),
  contender(
    'contender',
    displayName: 'Championship Contender',
    description:
        'Elite current roster with championship-caliber starting five and deep bench.',
    userOpeningDraftPick: 30,
    baseStarterRating: 70,
    baseBenchRating: 58,
  );

  const FranchiseSituation(
    this.jsonValue, {
    required this.displayName,
    required this.description,
    required this.userOpeningDraftPick,
    required this.baseStarterRating,
    required this.baseBenchRating,
  });

  final String jsonValue;
  final String displayName;
  final String description;

  /// Opening rookie draft pick guaranteed specifically to the PLAYER-SELECTED
  /// franchise when starting a new GM career in this situation.
  ///
  /// This is situation-level metadata for the human manager's starting pick;
  /// it is NOT assigned to all AI franchises within the same tier.
  final int userOpeningDraftPick;

  /// Alias preserved for backward compatibility with T01 references.
  int get targetDraftPick => userOpeningDraftPick;

  final int baseStarterRating;
  final int baseBenchRating;

  static FranchiseSituation fromJson(String value) => values.firstWhere(
    (e) => e.jsonValue == value || e.name == value,
    orElse: () => throw ArgumentError.value(
      value,
      'situation',
      'Unknown franchise situation',
    ),
  );
}
