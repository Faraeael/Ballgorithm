import 'season_fixture.dart';

final class SeasonRound {
  SeasonRound({
    required this.roundNumber,
    required List<SeasonFixture> fixtures,
  }) : fixtures = List.unmodifiable(fixtures);

  factory SeasonRound.fromJson(Map<String, dynamic> json) => SeasonRound(
    roundNumber: json['roundNumber'] as int,
    fixtures: [
      for (final f in json['fixtures'] as List)
        SeasonFixture.fromJson(f as Map<String, dynamic>),
    ],
  );

  final int roundNumber;
  final List<SeasonFixture> fixtures;

  bool get isCompleted => fixtures.every((f) => f.isCompleted);

  SeasonRound copyWithUpdatedFixture(SeasonFixture updated) {
    return SeasonRound(
      roundNumber: roundNumber,
      fixtures: [for (final f in fixtures) f.id == updated.id ? updated : f],
    );
  }

  Map<String, dynamic> toJson() => {
    'roundNumber': roundNumber,
    'fixtures': [for (final f in fixtures) f.toJson()],
  };
}
