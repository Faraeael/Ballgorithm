import '../domain_versions.dart' as domain_versions;
import '../season/season_fixture.dart';
import '../simulation/game_fingerprint.dart';
import '../simulation/game_simulator.dart';
import '../simulation/game_versions.dart';
import 'career_phase.dart';
import 'gm_career.dart';
import 'regular_season_game_adapter.dart';
import 'regular_season_game_input_evidence.dart';
import 'regular_season_game_result.dart';

final class PlayInGameService {
  const PlayInGameService({this.adapter = const RegularSeasonGameAdapter()});

  final RegularSeasonGameAdapter adapter;

  GmCareer simulateGame(GmCareer career, {required String expectedGameId}) {
    career.validate();
    if (career.phase != CareerPhase.playIn) {
      throw StateError('Career is not in the Play-In phase');
    }
    final season = career.regularSeasonState!;
    final playIn = career.playInState!;
    final gameNumber =
        playIn.gameIdentities.indexWhere(
          (identity) => identity.id == expectedGameId,
        ) +
        1;
    if (gameNumber == 0) throw StateError('Unknown Play-In game');
    if (playIn.gameResults.containsKey(expectedGameId)) {
      throw StateError('Play-In game is already complete');
    }
    final fixture = playIn.fixture(
      gameNumber: gameNumber,
      scheduleSeed: season.scheduleSeed,
    );
    if (fixture == null) {
      throw StateError('Play-In Game 3 requires completed Games 1 and 2');
    }
    final simulationLeague = adapter.simulationLeagueFor(career);
    final input = adapter.createGameInput(
      career,
      gameId: fixture.id,
      homeTeamId: fixture.homeTeamId,
      awayTeamId: fixture.awayTeamId,
      seed: fixture.gameSeed,
      simulationLeague: simulationLeague,
    );
    final game = GameSimulator().simulate(input);
    if (game.inputFingerprint != GameFingerprint.of(input) ||
        game.inputFingerprint != GameFingerprint.of(game.input) ||
        game.input.gameId != fixture.id ||
        game.input.seed != fixture.gameSeed ||
        game.input.homeTeamId != fixture.homeTeamId ||
        game.input.awayTeamId != fixture.awayTeamId) {
      throw const FormatException(
        'Simulation result does not match Play-In fixture',
      );
    }
    final captured = RegularSeasonGameInputEvidence.capture(input);
    final result = RegularSeasonGameResult(
      fixtureId: fixture.id,
      seasonId: playIn.seasonId,
      seasonYear: playIn.seasonYear,
      homeTeamId: fixture.homeTeamId,
      awayTeamId: fixture.awayTeamId,
      gameSeed: fixture.gameSeed,
      inputFingerprint: game.inputFingerprint,
      simulationVersion: game.simulationVersion,
      rulesVersion: game.rulesVersion,
      eventSchemaVersion: game.eventSchemaVersion,
      prngImplementationId: game.prngImplementationId,
      fingerprintVersion: gameFingerprintVersion,
      coreEngineVersion: domain_versions.coreEngineVersion,
      leagueSchemaVersion: domain_versions.snapshotSchemaVersion,
      inputEvidence: captured.evidence,
      periodsPlayed: game.periodsPlayed,
      summary: SeasonGameSummary.fromResult(game),
    );
    final nextPlayIn = playIn.withResult(
      result: result,
      leagueSnapshotJson: captured.leagueSnapshotJson,
      scheduleSeed: season.scheduleSeed,
    );
    final next = career.copyWith(
      schemaVersion: GmCareer.currentSchemaVersion,
      playInState: nextPlayIn,
    );
    next.validate();
    return next;
  }
}
