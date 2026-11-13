import 'career_phase.dart';
import 'gm_career.dart';
import 'offseason_readiness_gate.dart';
import 'regular_season_schedule_generator.dart';

/// Adds the schedule once to a valid, entered regular-season career.
final class RegularSeasonScheduleService {
  const RegularSeasonScheduleService({
    this.generator = const RegularSeasonScheduleGenerator(),
    this.readinessGate = const OffseasonReadinessGate(),
  });

  final RegularSeasonScheduleGenerator generator;
  final OffseasonReadinessGate readinessGate;

  GmCareer generate(GmCareer career) {
    if (career.phase != CareerPhase.regularSeason) {
      throw StateError('Career has not entered regular season');
    }
    career.validate();
    final state = career.regularSeasonState;
    if (state == null) {
      throw StateError('Regular-season state is missing');
    }
    if (state.schedule != null) {
      throw StateError('Regular-season schedule already exists');
    }
    if (state.gameResults.isNotEmpty) {
      throw StateError('Cannot generate schedule after game results exist');
    }
    final readiness = readinessGate.evaluate(career);
    if (readiness.status != OffseasonReadinessStatus.cleared ||
        readiness.readyCount != career.league.teams.length) {
      throw StateError('Career no longer satisfies offseason readiness');
    }

    final schedule = generator.generate(
      seasonId: state.seasonId,
      seasonYear: state.seasonYear,
      scheduleSeed: state.scheduleSeed,
      openingTeams: state.openingTeams,
    );
    return career.copyWith(
      schemaVersion: GmCareer.currentSchemaVersion,
      regularSeasonState: state.copyWith(schedule: schedule),
    );
  }
}
