import 'career_phase.dart';
import 'gm_career.dart';
import 'offseason_readiness_gate.dart';
import 'regular_season_state.dart';

final class RegularSeasonEntryBlocked implements Exception {
  const RegularSeasonEntryBlocked(this.readiness);

  final OffseasonReadinessResult readiness;

  @override
  String toString() =>
      'Regular-season entry blocked: ${readiness.reasons.join('; ')}';
}

/// Starts regular season only after the authoritative offseason gate clears.
final class RegularSeasonEntryService {
  const RegularSeasonEntryService({
    this.readinessGate = const OffseasonReadinessGate(),
  });

  final OffseasonReadinessGate readinessGate;

  GmCareer start(GmCareer career) {
    if (career.phase != CareerPhase.openingOffseason ||
        career.regularSeasonState != null) {
      throw StateError('Career has already left opening offseason');
    }
    career.validate();

    final readiness = readinessGate.evaluate(career);
    if (readiness.status != OffseasonReadinessStatus.cleared ||
        readiness.readyCount != career.league.teams.length) {
      throw RegularSeasonEntryBlocked(readiness);
    }

    final state = RegularSeasonState(
      seasonId: RegularSeasonState.seasonIdFor(career.id, career.currentYear),
      seasonYear: career.currentYear,
      scheduleSeed: career.generationSeed,
      openingTeams: [
        for (final team in career.league.teams)
          RegularSeasonTeamIdentity.fromTeam(team),
      ],
      gameResults: const {},
    );
    return career.copyWith(
      schemaVersion: GmCareer.currentSchemaVersion,
      phase: CareerPhase.regularSeason,
      regularSeasonState: state,
    );
  }
}
