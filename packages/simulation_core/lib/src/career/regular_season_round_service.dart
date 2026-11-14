import '../domain_versions.dart' as domain_versions;
import '../models/roster_category.dart';
import '../season/season_fixture.dart';
import '../simulation/game_fingerprint.dart';
import '../simulation/game_simulator.dart';
import '../simulation/game_versions.dart';
import 'career_phase.dart';
import 'gm_career.dart';
import 'regular_season_game_adapter.dart';
import 'regular_season_game_input_evidence.dart';
import 'regular_season_game_result.dart';
import 'regular_season_schedule.dart';

/// Simulates one complete next round in local state, then validates once.
final class RegularSeasonRoundService {
  const RegularSeasonRoundService({
    this.adapter = const RegularSeasonGameAdapter(),
  });

  final RegularSeasonGameAdapter adapter;

  GmCareer simulateNextRound(
    GmCareer career, {
    required int expectedRoundNumber,
  }) => _simulateNextRound(career, expectedRoundNumber: expectedRoundNumber);

  /// Test-only hook that fails a fixture without replacing the simulator.
  GmCareer simulateNextRoundForTesting(
    GmCareer career, {
    required int expectedRoundNumber,
    required void Function() beforeGame,
  }) => _simulateNextRound(
    career,
    expectedRoundNumber: expectedRoundNumber,
    beforeGame: beforeGame,
  );

  GmCareer _simulateNextRound(
    GmCareer career, {
    required int expectedRoundNumber,
    void Function()? beforeGame,
  }) {
    career.validate();
    if (career.phase != CareerPhase.regularSeason) {
      throw StateError('Career is not in regular season');
    }
    final state = career.regularSeasonState!;
    final schedule = state.schedule;
    if (schedule == null) {
      throw StateError('Regular-season schedule is missing');
    }
    final next = state.nextUnfinishedRound;
    if (next == null) throw StateError('Regular season is complete');
    if (expectedRoundNumber != next) throw StateError('Expected round $next');

    final results = Map<String, RegularSeasonGameResult>.of(state.gameResults);
    final gameInputSnapshots = Map<String, String>.of(state.gameInputSnapshots);
    final simulationLeague = adapter.simulationLeagueFor(career);
    final simulator = GameSimulator();
    for (final fixture in schedule.fixturesForRound(next)) {
      if (fixture.status != RegularSeasonFixtureStatus.scheduled) {
        throw StateError('Round $next is not wholly scheduled');
      }
      final input = adapter.createInput(
        career,
        fixture,
        simulationLeague: simulationLeague,
      );
      beforeGame?.call();
      final game = simulator.simulate(input);
      if (game.inputFingerprint != GameFingerprint.of(input) ||
          game.inputFingerprint != GameFingerprint.of(game.input) ||
          game.input.gameId != fixture.id ||
          game.input.seed != fixture.gameSeed ||
          game.input.homeTeamId != fixture.homeTeamId ||
          game.input.awayTeamId != fixture.awayTeamId) {
        throw const FormatException(
          'Simulation result does not match fixture input',
        );
      }
      final captured = RegularSeasonGameInputEvidence.capture(input);
      final previousSnapshot = gameInputSnapshots.putIfAbsent(
        captured.evidence.leagueSnapshotId,
        () => captured.leagueSnapshotJson,
      );
      if (previousSnapshot != captured.leagueSnapshotJson) {
        throw const FormatException(
          'Game-time league snapshot digest collision',
        );
      }
      final result = RegularSeasonGameResult(
        fixtureId: fixture.id,
        seasonId: fixture.seasonId,
        seasonYear: fixture.seasonYear,
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
      _validateResult(career, fixture, result);
      if (results.containsKey(fixture.id)) {
        throw const FormatException('Duplicate regular-season result');
      }
      results[fixture.id] = result;
    }
    final updatedSchedule = RegularSeasonSchedule(
      seasonId: schedule.seasonId,
      seasonYear: schedule.seasonYear,
      scheduleSeed: schedule.scheduleSeed,
      rounds: [
        for (final round in schedule.rounds)
          RegularSeasonRound(
            roundNumber: round.roundNumber,
            fixtures: [
              for (final fixture in round.fixtures)
                fixture.roundNumber == next
                    ? RegularSeasonFixture(
                        id: fixture.id,
                        seasonId: fixture.seasonId,
                        seasonYear: fixture.seasonYear,
                        roundNumber: fixture.roundNumber,
                        fixturePosition: fixture.fixturePosition,
                        homeTeamId: fixture.homeTeamId,
                        awayTeamId: fixture.awayTeamId,
                        gameSeed: fixture.gameSeed,
                        status: RegularSeasonFixtureStatus.completed,
                      )
                    : fixture,
            ],
          ),
      ],
    );
    final updatedState = state.copyWith(
      schedule: updatedSchedule,
      gameResults: results,
      gameInputSnapshots: gameInputSnapshots,
    );
    return career.copyWith(
      schemaVersion: GmCareer.currentSchemaVersion,
      regularSeasonState: updatedState,
    );
  }

  void _validateResult(
    GmCareer career,
    RegularSeasonFixture fixture,
    RegularSeasonGameResult result,
  ) {
    final participants = {fixture.homeTeamId.value, fixture.awayTeamId.value};
    final standardPlayers = <String>{};
    final teams = <String, String>{};
    for (final team in career.league.teams) {
      if (!participants.contains(team.id.value)) continue;
      for (final player in team.players) {
        if (team.roster.categoryOf(player.id) == RosterCategory.standard) {
          standardPlayers.add(player.id.value);
          teams[player.id.value] = team.id.value;
        }
      }
    }
    result.validateFor(
      fixture: fixture,
      expectedSeasonId: career.regularSeasonState!.seasonId,
      expectedSeasonYear: career.currentYear,
      standardPlayers: standardPlayers,
      playerTeams: teams,
    );
  }
}
