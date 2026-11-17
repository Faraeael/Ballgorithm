import 'career_phase.dart';
import 'gm_career.dart';
import 'offseason_readiness_gate.dart';
import 'playoff_state.dart';

final class PlayoffEntryService {
  const PlayoffEntryService({
    this.readinessGate = const OffseasonReadinessGate(),
  });

  final OffseasonReadinessGate readinessGate;

  GmCareer enter(GmCareer career) {
    career.validate();
    if (career.phase != CareerPhase.playIn ||
        career.playInState == null ||
        career.playoffState != null) {
      throw StateError('Career is not eligible for playoff entry');
    }
    final season = career.regularSeasonState!;
    final playIn = career.playInState!;
    final schedule = season.schedule;
    if (schedule == null ||
        schedule.rounds.length != 82 ||
        schedule.totalFixtures != 1230 ||
        season.completedRounds != 82 ||
        season.completedGames != 1230 ||
        season.gameResults.length != 1230 ||
        career.league.teams.any(
          (team) => season.standings.table[team.id.value]?.gamesPlayed != 82,
        )) {
      throw StateError('Regular season is not fully complete');
    }
    if (!playIn.isComplete ||
        playIn.gameResults.length != 3 ||
        playIn.qualifiedTeams.length != 16 ||
        playIn.qualifiedTeams.map((team) => team.$2).toSet().length != 16 ||
        playIn.qualifiedTeams.any((team) => team.$1 < 1 || team.$1 > 16) ||
        playIn.qualifiedTeams.firstWhere((team) => team.$1 == 15).$2 !=
            playIn
                .gameResults['${playIn.seasonId}-playin-g1']!
                .summary
                .winnerTeamId ||
        playIn.qualifiedTeams.firstWhere((team) => team.$1 == 16).$2 !=
            playIn
                .gameResults['${playIn.seasonId}-playin-g3']!
                .summary
                .winnerTeamId) {
      throw StateError('Play-In qualification is incomplete or invalid');
    }
    final readiness = readinessGate.evaluate(career);
    if (readiness.status != OffseasonReadinessStatus.cleared ||
        readiness.readyCount != career.league.teams.length) {
      throw StateError(
        'Career has unresolved transactions or readiness issues',
      );
    }
    final next = career.copyWith(
      schemaVersion: GmCareer.currentSchemaVersion,
      phase: CareerPhase.playoffs,
      playoffState: PlayoffState.initial(
        seasonId: season.seasonId,
        seasonYear: season.seasonYear,
        scheduleSeed: season.scheduleSeed,
        qualifiedTeams: playIn.qualifiedTeams,
        franchiseIds: [for (final team in season.openingTeams) team.teamId],
      ),
    );
    next.validate();
    return next;
  }
}
