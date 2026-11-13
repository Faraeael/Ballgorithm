/// Represents the lifecycle phase of a GM Career.
enum CareerPhase {
  openingOffseason('openingOffseason', 'Opening Offseason'),
  regularSeason('regularSeason', 'Regular Season');

  const CareerPhase(this.jsonValue, this.displayName);

  final String jsonValue;
  final String displayName;

  static CareerPhase fromJson(String value) => values.firstWhere(
    (e) => e.jsonValue == value || e.name == value,
    orElse: () => throw FormatException('Unknown career phase: $value'),
  );
}
