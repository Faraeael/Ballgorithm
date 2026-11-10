/// Competitive franchise situations for GM Career mode.
enum FranchiseSituation {
  tanking(
    'tanking',
    displayName: 'Tanking / Rebuilding',
    description:
        'Rebuilding roster with low current strength and future draft focus.',
    targetDraftPick: 1,
    baseStarterRating: 46,
    baseBenchRating: 40,
  ),
  playIn(
    'playIn',
    displayName: 'Play-In Contender',
    description:
        'Middle-tier competitive roster with reliable starters and clear weaknesses.',
    targetDraftPick: 12,
    baseStarterRating: 54,
    baseBenchRating: 46,
  ),
  playoff(
    'playoff',
    displayName: 'Playoff Team',
    description:
        'Strong established roster with high-quality starters and competitive depth.',
    targetDraftPick: 20,
    baseStarterRating: 62,
    baseBenchRating: 52,
  ),
  contender(
    'contender',
    displayName: 'Championship Contender',
    description:
        'Elite current roster with championship-caliber starting five and deep bench.',
    targetDraftPick: 30,
    baseStarterRating: 70,
    baseBenchRating: 58,
  );

  const FranchiseSituation(
    this.jsonValue, {
    required this.displayName,
    required this.description,
    required this.targetDraftPick,
    required this.baseStarterRating,
    required this.baseBenchRating,
  });

  final String jsonValue;
  final String displayName;
  final String description;
  final int targetDraftPick;
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
