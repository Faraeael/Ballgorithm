import '../domain_versions.dart' as domain_versions;
import '../models/league.dart';
import '../season/season_fixture.dart';
import '../simulation/game_fingerprint.dart';
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

final class PlayoffSlateService {
  const PlayoffSlateService({this.adapter = const RegularSeasonGameAdapter()});

  final RegularSeasonGameAdapter adapter;

  GmCareer simulateNextSlate(GmCareer career) {
    career.validate();
    final state = _requirePlayoffs(career);
    if (state.isComplete) throw StateError('Playoffs are already complete');
    final games = state.nextEligibleGames;
    if (games.isEmpty) throw StateError('No playoff slate is eligible');
    final simulationLeague = adapter.simulationLeagueFor(career);
    final results = <RegularSeasonGameResult>[];
    final snapshots = <String, String>{};
    for (final game in games) {
      final simulated = _simulateEligibleGame(
        career: career,
        game: game,
        adapter: adapter,
        simulationLeague: simulationLeague,
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
    final regularSeason = career.regularSeasonState!;
    final nextState = state.withResults(
      results: results,
      addedSnapshots: snapshots,
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
      seasonId: state.seasonId,
      seasonYear: state.seasonYear,
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
