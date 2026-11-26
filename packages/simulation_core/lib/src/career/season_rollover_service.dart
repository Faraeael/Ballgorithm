import '../finance/financial_rollover_plan.dart';
import '../finance/financial_rollover_service.dart';
import '../models/ai_rookie_signing.dart';
import '../models/draft_execution_state.dart';
import '../models/league.dart';
import '../models/player_career_profile.dart';
import '../models/roster.dart';
import 'career_phase.dart';
import 'gm_career.dart';
import 'next_season_population_plan.dart';
import 'next_season_population_service.dart';
import 'rollover_validation_proof.dart';
import 'season_archive.dart';
import 'season_history_record.dart';
import 'season_market_history_record.dart';
import 'season_rollover_plan.dart';
import 'season_rollover_planner.dart';

/// Complete, typed result of a pure Year N -> Year N+1 rollover transition.
final class SeasonRolloverResult {
  const SeasonRolloverResult({
    required this.nextCareer,
    required this.rolloverPlan,
    required this.financialPlan,
    required this.populationPlan,
    required this.marketHistoryRecord,
  });

  final GmCareer nextCareer;
  final SeasonRolloverPlan rolloverPlan;
  final FinancialRolloverPlan financialPlan;
  final NextSeasonPopulationPlan populationPlan;
  final SeasonMarketHistoryRecord marketHistoryRecord;
}

/// Complete archive + rollover bundle computed in a single validated pass.
final class PreparedSeasonArchiveTransition {
  const PreparedSeasonArchiveTransition({
    required this.archive,
    required this.archiveJson,
    required this.archiveDigest,
    required this.archiveRecord,
    required this.rolloverResult,
  });

  final SeasonArchive archive;
  final String archiveJson;
  final String archiveDigest;
  final SeasonHistoryRecord archiveRecord;
  final SeasonRolloverResult rolloverResult;
}

/// Pure, deterministic, authoritative Year N -> Year N+1 career assembly service
/// (M009-T05C-C2-C2C).
///
/// Recomputes all C2-A, C2-B, and C2-C2B plans internally from [current],
/// verifies [archiveRecord] against the canonical [SeasonArchive] SHA-256 digest,
/// and returns a fully validated Year N+1 [GmCareer] in memory without mutating
/// [current] or performing any disk persistence.
final class SeasonRolloverService {
  const SeasonRolloverService();

  GmCareer rollover({
    required GmCareer current,
    required SeasonHistoryRecord archiveRecord,
  }) => rolloverWithPlans(
    current: current,
    archiveRecord: archiveRecord,
  ).nextCareer;

  /// Validates [current] once, extracts and encodes its canonical [SeasonArchive],
  /// derives the bound [SeasonHistoryRecord], and computes the Year N+1 rollover.
  PreparedSeasonArchiveTransition prepareArchiveAndRollover({
    required GmCareer current,
  }) {
    _checkPreconditions(current);
    final proof = RolloverValidationProof.validateCompletedSeason(current);
    final encoded = SeasonArchiveCodec.encodeWithDigestWithProof(
      proof.archive,
      proof,
    );
    final record = proof.archive.toHistoryRecordWithProof(
      encoded.digest,
      proof,
    );
    final rolloverResult = _rolloverFromProof(
      proof: proof,
      archiveRecord: record,
    );
    return PreparedSeasonArchiveTransition(
      archive: proof.archive,
      archiveJson: encoded.json,
      archiveDigest: encoded.digest,
      archiveRecord: record,
      rolloverResult: rolloverResult,
    );
  }

  SeasonRolloverResult rolloverWithPlans({
    required GmCareer current,
    required SeasonHistoryRecord archiveRecord,
  }) {
    _checkPreconditions(current);
    final proof = RolloverValidationProof.validateCompletedSeason(current);

    // Reconstruct canonical digest and verify caller-supplied archiveRecord.
    final encoded = SeasonArchiveCodec.encodeWithDigestWithProof(
      proof.archive,
      proof,
    );
    final expectedRecord = proof.archive.toHistoryRecordWithProof(
      encoded.digest,
      proof,
    );
    final teamIds = {for (final t in current.league.teams) t.id.value};
    archiveRecord.validate(validTeamIds: teamIds, expectedCareerId: current.id);
    if (!_recordsMatch(archiveRecord, expectedRecord)) {
      throw StateError(
        'Supplied SeasonHistoryRecord does not match canonical SeasonArchive '
        'for ${current.id} year ${current.currentYear}',
      );
    }

    return _rolloverFromProof(proof: proof, archiveRecord: archiveRecord);
  }

  void _checkPreconditions(GmCareer current) {
    final completedYear = current.currentYear;
    if (current.phase != CareerPhase.playoffs) {
      throw StateError(
        'Cannot roll over outside CareerPhase.playoffs '
        '(got ${current.phase.name})',
      );
    }
    if (current.seasonHistory.any((r) => r.seasonYear == completedYear)) {
      throw StateError(
        'Season $completedYear has already been archived in seasonHistory',
      );
    }
    if (current.seasonSettlements.any((s) => s.seasonYear == completedYear)) {
      throw StateError(
        'Season $completedYear has already been settled in seasonSettlements',
      );
    }
    if (current.marketHistory.any((m) => m.seasonYear == completedYear)) {
      throw StateError(
        'Season $completedYear has already been recorded in marketHistory',
      );
    }
  }

  SeasonRolloverResult _rolloverFromProof({
    required RolloverValidationProof proof,
    required SeasonHistoryRecord archiveRecord,
  }) {
    final current = proof.career;
    final completedYear = current.currentYear;

    // Recompute all three rollover plans internally using validated proof.
    final rolloverPlan = const SeasonRolloverPlanner().planWithProof(
      current,
      proof,
    );
    final financialPlan = const FinancialRolloverService().planWithProof(
      career: current,
      rolloverPlan: rolloverPlan,
      proof: proof,
    );
    final populationPlan = const NextSeasonPopulationService().planWithProof(
      career: current,
      rolloverPlan: rolloverPlan,
      proof: proof,
      completedStandings: archiveRecord.regularSeasonStandings,
    );

    // Rebuild 30-team league with continuing contracted players & categories.
    final nextTeams = [
      for (final team in current.league.teams)
        team.copyWith(
          roster: Roster(
            [
              for (final e
                  in rolloverPlan.proposedRosters[team.id.value]!.entries)
                e.player,
            ],
            categories: {
              for (final e
                  in rolloverPlan.proposedRosters[team.id.value]!.entries)
                e.player.id.value: e.category,
            },
          ),
        ),
    ];
    final nextLeague = League.create(
      id: current.league.id,
      name: current.league.name,
      config: current.league.config,
      teams: nextTeams,
      enforceRosterSize: false,
      enforcePositionCoverage: false,
    );

    // Rebuild LeagueCareerProfiles for surviving actively rostered players only.
    final nextProfiles = LeagueCareerProfiles(
      schemaVersion: current.careerProfiles.schemaVersion,
      leagueSeed: current.careerProfiles.leagueSeed,
      profiles: {
        for (final roster in rolloverPlan.proposedRosters.values)
          for (final entry in roster.entries)
            entry.player.id.value: entry.nextProfile,
      },
    );

    final marketHistoryRecord = SeasonMarketHistoryRecord.fromCareer(current);

    final nextCareer = GmCareer(
      id: current.id,
      schemaVersion: GmCareer.currentSchemaVersion,
      generationSeed: current.generationSeed,
      userFranchiseId: current.userFranchiseId,
      originalSituation: current.originalSituation,
      currentYear: completedYear + 1,
      phase: CareerPhase.openingOffseason,
      league: nextLeague,
      careerProfiles: nextProfiles,
      userOpeningDraftPick: current.userOpeningDraftPick,
      draftOrder: populationPlan.nextDraftOrder,
      draftClass: populationPlan.nextDraftClass,
      draftExecutionState: DraftExecutionState.initial(),
      rookieSigningLedger: current.rookieSigningLedger,
      aiRookieSigning: AiRookieSigningState.empty(),
      freeAgentPool: populationPlan.nextFreeAgentPool,
      freeAgentOffers: populationPlan.marketInit.freeAgentOffers,
      freeAgentMarket: populationPlan.marketInit.freeAgentMarket,
      offseasonClearance: populationPlan.marketInit.offseasonClearance,
      hardshipSettlement: populationPlan.marketInit.hardshipSettlement,
      finances: financialPlan.proposedCareerFinances,
      regularSeasonState: null,
      playInState: null,
      playoffState: null,
      seasonHistory: [...current.seasonHistory, archiveRecord],
      retiredPlayers: [...current.retiredPlayers, ...rolloverPlan.retirements],
      seasonSettlements: [
        ...current.seasonSettlements,
        financialPlan.proposedSettlementRecord,
      ],
      careerDraftRights: rolloverPlan.proposedDraftRightsCarryover,
      carriedUnsignedProspects: rolloverPlan.proposedCarriedUnsignedProspects,
      marketHistory: [...current.marketHistory, marketHistoryRecord],
      tradeHistory: current.tradeHistory,
      // M010: preferences carry over; validity is re-checked at season entry.
      userRotation: current.userRotation,
      // M011: identities carry over; expired commitments end employment.
      staff: current.staff.rolledOver(financialPlan.proposedCareerFinances),
    );

    return SeasonRolloverResult(
      nextCareer: nextCareer,
      rolloverPlan: rolloverPlan,
      financialPlan: financialPlan,
      populationPlan: populationPlan,
      marketHistoryRecord: marketHistoryRecord,
    );
  }

  static bool _recordsMatch(SeasonHistoryRecord a, SeasonHistoryRecord b) {
    if (a.seasonYear != b.seasonYear ||
        a.seasonId != b.seasonId ||
        a.championTeamId != b.championTeamId ||
        a.archiveId != b.archiveId ||
        a.archiveDigest != b.archiveDigest ||
        a.playInOutcome != b.playInOutcome ||
        a.regularSeasonStandings.length != b.regularSeasonStandings.length ||
        a.playoffSeries.length != b.playoffSeries.length) {
      return false;
    }
    for (var i = 0; i < a.regularSeasonStandings.length; i++) {
      if (a.regularSeasonStandings[i] != b.regularSeasonStandings[i]) {
        return false;
      }
    }
    for (var i = 0; i < a.playoffSeries.length; i++) {
      if (a.playoffSeries[i] != b.playoffSeries[i]) {
        return false;
      }
    }
    return true;
  }
}
