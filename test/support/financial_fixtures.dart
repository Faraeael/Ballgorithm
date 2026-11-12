import 'package:simulation_core/simulation_core.dart';

/// Test-only fixture builder for roster changes. Production changes must use
/// `FinancialTransactions`.
GmCareer withBootstrappedLeague(
  GmCareer career,
  League league, {
  LeagueCareerProfiles? careerProfiles,
  RookieSigningLedger? rookieSigningLedger,
}) {
  final profiles = careerProfiles ?? career.careerProfiles;
  final ledger = rookieSigningLedger ?? career.rookieSigningLedger;
  return career.copyWith(
    league: league,
    careerProfiles: profiles,
    rookieSigningLedger: ledger,
    finances: FinancialMigration.bootstrapFromCareerState(
      league: league,
      careerProfiles: profiles,
      rookieSigningLedger: ledger,
      currentYear: career.currentYear,
    ),
  );
}

GmCareer withBootstrappedTeam(
  GmCareer career,
  Team updatedTeam, {
  LeagueCareerProfiles? careerProfiles,
}) {
  final league = League.create(
    id: career.league.id,
    name: career.league.name,
    config: career.league.config,
    teams: [
      for (final candidate in career.league.teams)
        candidate.id == updatedTeam.id ? updatedTeam : candidate,
    ],
    enforceRosterSize: false,
  );
  return withBootstrappedLeague(career, league, careerProfiles: careerProfiles);
}
