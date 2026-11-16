import 'career_phase.dart';
import 'gm_career.dart';
import 'offseason_readiness_gate.dart';
import 'play_in_state.dart';

final class PlayInEntryService {
  const PlayInEntryService({
    this.readinessGate = const OffseasonReadinessGate(),
  });

  final OffseasonReadinessGate readinessGate;

  GmCareer enter(GmCareer career) {
    career.validate();
    if (career.phase != CareerPhase.regularSeason ||
        career.playInState != null) {
      throw StateError('Career is not eligible for Play-In entry');
    }
    final season = career.regularSeasonState!;
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
    final readiness = readinessGate.evaluate(career);
    if (readiness.status != OffseasonReadinessStatus.cleared ||
        readiness.readyCount != career.league.teams.length) {
      throw StateError(
        'Career has unresolved transactions or readiness issues',
      );
    }
    final next = career.copyWith(
      schemaVersion: GmCareer.currentSchemaVersion,
      phase: CareerPhase.playIn,
      playInState: PlayInState.initial(
        seasonId: season.seasonId,
        seasonYear: season.seasonYear,
        scheduleSeed: season.scheduleSeed,
        originalRanking: PlayInRanking.rank(season),
      ),
    );
    next.validate();
    return next;
  }
}
