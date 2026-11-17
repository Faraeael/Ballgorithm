import '../domain_versions.dart' as domain_versions;
import '../models/league.dart';
import '../season/season_fixture.dart';
import '../simulation/game_fingerprint.dart';
import '../simulation/game_input.dart';
import '../simulation/game_simulator.dart';
import '../simulation/game_versions.dart';
import 'career_phase.dart';
import 'gm_career.dart';
import 'playoff_state.dart';
import 'regular_season_game_adapter.dart';
import 'regular_season_game_input_evidence.dart';
import 'regular_season_game_result.dart';

/// One simulated game and its deduplicatable game-time league snapshot.
typedef PlayoffGameSimulation = ({
  RegularSeasonGameResult result,
  String leagueSnapshotJson,
});

final class PlayoffGameService {
  const PlayoffGameService({this.adapter = const RegularSeasonGameAdapter()});

  final RegularSeasonGameAdapter adapter;

  PlayoffGameSimulation simulateGame(
    GmCareer career, {
    required String expectedGameId,
  }) {
    career.validate();
    final state = _requirePlayoffs(career);
    final game = state.nextEligibleGames
        .where((identity) => identity.id == expectedGameId)
        .firstOrNull;
    if (game == null) {
      throw StateError('Playoff game is not currently eligible');
    }
    return _simulateEligibleGame(
      career: career,
      game: game,
      adapter: adapter,
      simulationLeague: adapter.simulationLeagueFor(career),
    );
  }
}

/// Minimal, isolate-transferable inputs for simulating one playoff slate.
final class PlayoffSlateWorkOrder {
  PlayoffSlateWorkOrder({
    required this.seasonId,
    required this.seasonYear,
    required List<PlayoffGameIdentity> games,
    required List<GameInput> inputs,
    required List<String> expectedFingerprints,
  }) : games = List.unmodifiable(games),
       inputs = List.unmodifiable(inputs),
       expectedFingerprints = List.unmodifiable(expectedFingerprints);

  final String seasonId;
  final int seasonYear;
  final List<PlayoffGameIdentity> games;
  final List<GameInput> inputs;
  final List<String> expectedFingerprints;
}

/// Compact simulation results and deduplicated snapshots returned by a worker.
final class PlayoffSlateWorkerOutput {
  PlayoffSlateWorkerOutput({
    required List<RegularSeasonGameResult> results,
    required Map<String, String> snapshots,
  }) : results = List.unmodifiable(results),
       snapshots = Map.unmodifiable(snapshots);

  final List<RegularSeasonGameResult> results;
  final Map<String, String> snapshots;
}

final class PlayoffSlateService {
  const PlayoffSlateService({this.adapter = const RegularSeasonGameAdapter()});

  final RegularSeasonGameAdapter adapter;

  /// Validates [career] and builds deterministic [GameInput]s for the next slate.
  PlayoffSlateWorkOrder prepareSlate(GmCareer career) {
    career.validate();
    final state = _requirePlayoffs(career);
    if (state.isComplete) throw StateError('Playoffs are already complete');
    final games = state.nextEligibleGames;
    if (games.isEmpty) throw StateError('No playoff slate is eligible');
    final simulationLeague = adapter.simulationLeagueFor(career);
    final inputs = <GameInput>[];
    final expectedFingerprints = <String>[];
    for (final game in games) {
      if (state.gameIdentities[game.id] != game) {
        throw StateError('Playoff game is not currently eligible');
      }
      final input = adapter.createGameInput(
        career,
        gameId: game.id,
        homeTeamId: game.homeTeamId,
        awayTeamId: game.awayTeamId,
        seed: game.gameSeed,
        simulationLeague: simulationLeague,
      );
      inputs.add(input);
      expectedFingerprints.add(GameFingerprint.of(input));
    }
    return PlayoffSlateWorkOrder(
      seasonId: state.seasonId,
      seasonYear: state.seasonYear,
      games: games,
      inputs: inputs,
      expectedFingerprints: expectedFingerprints,
    );
  }

  /// Simulates a prepared [order] without requiring the full [GmCareer] graph.
  PlayoffSlateWorkerOutput simulatePreparedSlate(PlayoffSlateWorkOrder order) {
    final results = <RegularSeasonGameResult>[];
    final snapshots = <String, String>{};
    for (var i = 0; i < order.games.length; i++) {
      final game = order.games[i];
      final input = order.inputs[i];
      final simulated = _simulateInput(
        input: input,
        game: game,
        seasonId: order.seasonId,
        seasonYear: order.seasonYear,
      );
      results.add(simulated.result);
      final evidence = simulated.result.inputEvidence!;
      final prior = snapshots.putIfAbsent(
        evidence.leagueSnapshotId,
        () => simulated.leagueSnapshotJson,
      );
      if (prior != simulated.leagueSnapshotJson) {
        throw const FormatException(
          'Playoff game-time snapshot digest collision',
        );
      }
    }
    return PlayoffSlateWorkerOutput(results: results, snapshots: snapshots);
  }

  /// Verifies [output] against [order] and settles the authoritative [career].
  GmCareer applyPreparedSlate(
    GmCareer career, {
    required PlayoffSlateWorkOrder order,
    required PlayoffSlateWorkerOutput output,
  }) {
    career.validate();
    final state = _requirePlayoffs(career);
    if (state.isComplete) throw StateError('Playoffs are already complete');
    if (state.seasonId != order.seasonId ||
        state.seasonYear != order.seasonYear) {
      throw const FormatException('Playoff slate season mismatch');
    }
    final eligible = state.nextEligibleGames;
    if (eligible.length != order.games.length ||
        output.results.length != order.games.length) {
      throw const FormatException('Playoff slate result count mismatch');
    }
    for (var i = 0; i < order.games.length; i++) {
      final expectedGame = order.games[i];
      if (eligible[i] != expectedGame) {
        throw StateError('Playoff slate eligibility changed');
      }
      final result = output.results[i];
      final evidence = result.inputEvidence;
      if (result.fixtureId != expectedGame.id ||
          result.seasonId != order.seasonId ||
          result.seasonYear != order.seasonYear ||
          result.homeTeamId != expectedGame.homeTeamId ||
          result.awayTeamId != expectedGame.awayTeamId ||
          result.gameSeed != expectedGame.gameSeed ||
          result.inputFingerprint != order.expectedFingerprints[i] ||
          evidence == null ||
          !output.snapshots.containsKey(evidence.leagueSnapshotId)) {
        throw const FormatException(
          'Playoff worker result does not match prepared slate',
        );
      }
    }
    final regularSeason = career.regularSeasonState!;
    final nextState = state.withResults(
      results: output.results,
      addedSnapshots: output.snapshots,
      scheduleSeed: regularSeason.scheduleSeed,
      franchiseIds: [
        for (final team in regularSeason.openingTeams) team.teamId,
      ],
    );
    return career.copyWith(
      schemaVersion: GmCareer.currentSchemaVersion,
      playoffState: nextState,
    );
  }

  GmCareer simulateNextSlate(GmCareer career) {
    final order = prepareSlate(career);
    final output = simulatePreparedSlate(order);
    return applyPreparedSlate(career, order: order, output: output);
  }
}

PlayoffState _requirePlayoffs(GmCareer career) {
  if (career.phase != CareerPhase.playoffs || career.playoffState == null) {
    throw StateError('Career is not in the playoffs phase');
  }
  return career.playoffState!;
}

PlayoffGameSimulation _simulateEligibleGame({
  required GmCareer career,
  required PlayoffGameIdentity game,
  required RegularSeasonGameAdapter adapter,
  required League simulationLeague,
}) {
  final state = _requirePlayoffs(career);
  if (state.gameIdentities[game.id] != game ||
      !state.nextEligibleGames.any((eligible) => eligible.id == game.id)) {
    throw StateError('Playoff game is not currently eligible');
  }
  final input = adapter.createGameInput(
    career,
    gameId: game.id,
    homeTeamId: game.homeTeamId,
    awayTeamId: game.awayTeamId,
    seed: game.gameSeed,
    simulationLeague: simulationLeague,
  );
  return _simulateInput(
    input: input,
    game: game,
    seasonId: state.seasonId,
    seasonYear: state.seasonYear,
  );
}

PlayoffGameSimulation _simulateInput({
  required GameInput input,
  required PlayoffGameIdentity game,
  required String seasonId,
  required int seasonYear,
}) {
  final played = GameSimulator().simulate(input);
  if (played.inputFingerprint != GameFingerprint.of(input) ||
      played.inputFingerprint != GameFingerprint.of(played.input) ||
      played.input.gameId != game.id ||
      played.input.seed != game.gameSeed ||
      played.input.homeTeamId != game.homeTeamId ||
      played.input.awayTeamId != game.awayTeamId) {
    throw const FormatException(
      'Simulation result does not match playoff fixture',
    );
  }
  final captured = RegularSeasonGameInputEvidence.capture(input);
  return (
    result: RegularSeasonGameResult(
      fixtureId: game.id,
      seasonId: seasonId,
      seasonYear: seasonYear,
      homeTeamId: game.homeTeamId,
      awayTeamId: game.awayTeamId,
      gameSeed: game.gameSeed,
      inputFingerprint: played.inputFingerprint,
      simulationVersion: played.simulationVersion,
      rulesVersion: played.rulesVersion,
      eventSchemaVersion: played.eventSchemaVersion,
      prngImplementationId: played.prngImplementationId,
      fingerprintVersion: gameFingerprintVersion,
      coreEngineVersion: domain_versions.coreEngineVersion,
      leagueSchemaVersion: domain_versions.snapshotSchemaVersion,
      inputEvidence: captured.evidence,
      periodsPlayed: played.periodsPlayed,
      summary: SeasonGameSummary.fromResult(played),
    ),
    leagueSnapshotJson: captured.leagueSnapshotJson,
  );
}
