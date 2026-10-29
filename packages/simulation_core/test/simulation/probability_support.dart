import 'package:simulation_core/simulation_core.dart';

/// Synthetic 50/50 ratings used by the probability-model tests.
PlayerAttributes attrs({
  int insideScoring = 50,
  int midrange = 50,
  int threePoint = 50,
  int freeThrow = 50,
  int passing = 50,
  int ballHandling = 50,
  int perimeterDefense = 50,
  int interiorDefense = 50,
  int rebounding = 50,
  int athleticism = 50,
  int stamina = 50,
  int basketballIQ = 50,
}) => PlayerAttributes(
  insideScoring: insideScoring,
  midrange: midrange,
  threePoint: threePoint,
  freeThrow: freeThrow,
  passing: passing,
  ballHandling: ballHandling,
  perimeterDefense: perimeterDefense,
  interiorDefense: interiorDefense,
  rebounding: rebounding,
  athleticism: athleticism,
  stamina: stamina,
  basketballIQ: basketballIQ,
);

Player playerOf(
  Position position, {
  PlayerAttributes? attributes,
  String teamPrefix = 'home',
}) => Player(
  id: PlayerId('$teamPrefix-${position.shortName}'),
  firstName: teamPrefix,
  lastName: position.shortName,
  position: position,
  attributes: attributes ?? attrs(),
);

/// Canonical five, optionally overriding attributes per position.
ActiveLineup lineupOf({
  Map<Position, PlayerAttributes> overrides = const {},
  String teamPrefix = 'home',
}) => ActiveLineup.create([
  for (final position in Position.values)
    playerOf(position, attributes: overrides[position], teamPrefix: teamPrefix),
]);

TeamOnCourt teamOnCourt(
  String teamId, {
  Map<Position, PlayerAttributes> overrides = const {},
}) => TeamOnCourt(
  teamId: TeamId(teamId),
  lineup: lineupOf(overrides: overrides, teamPrefix: teamId),
);

/// Walks normalized basis-point weights for the draw the model consumed.
int indexForDraw(List<int> weights, int draw) {
  var running = 0;
  for (var i = 0; i < weights.length; i++) {
    running += weights[i];
    if (draw < running) return i;
  }
  return weights.length - 1;
}
