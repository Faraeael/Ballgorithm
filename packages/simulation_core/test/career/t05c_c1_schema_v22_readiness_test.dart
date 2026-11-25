import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

String _asV21Json(GmCareer career) {
  final map = jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;
  map['schemaVersion'] = 21;
  map.remove('retiredPlayers');
  map.remove('seasonSettlements');
  map.remove('careerDraftRights');
  map.remove('carriedUnsignedProspects');
  map.remove('marketHistory');
  map.remove('userRotation');
  (map['freeAgentPool'] as Map<String, dynamic>).remove('seasonYear');
  return jsonEncode(map);
}

String _asV20Json(GmCareer career) {
  final map = jsonDecode(_asV21Json(career)) as Map<String, dynamic>;
  map['schemaVersion'] = 20;
  map.remove('seasonHistory');
  return jsonEncode(map);
}

GmCareer _newOpeningCareer({int seed = 20261118}) {
  final setup = const CareerSetupService().generate(
    CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.tanking,
      seed: seed,
    ),
  );
  return GmCareer.fromSetupResult(setup, id: 'career-c1-$seed');
}

GmCareer _buildYear2Shell(GmCareer y1, {DraftOrder? customDraftOrder}) {
  final nextOrder =
      customDraftOrder ??
      DraftOrder(
        picks: [
          for (var i = 0; i < y1.draftOrder.picks.length; i++)
            DraftPick(
              round: y1.draftOrder.picks[i].round,
              pickInRound: y1.draftOrder.picks[i].pickInRound,
              overallPick: y1.draftOrder.picks[i].overallPick,
              originalOwnerTeamId: y1.draftOrder.picks[i].originalOwnerTeamId,
              currentOwnerTeamId: y1.draftOrder.picks[i].currentOwnerTeamId,
            ),
        ],
      );
  final nextLeague = y1.league;
  final nextFinances = FinancialMigration.bootstrapFromCareerState(
    league: nextLeague,
    careerProfiles: y1.careerProfiles,
    rookieSigningLedger: RookieSigningLedger.empty(),
    currentYear: 2,
  );
  return y1.copyWith(
    currentYear: 2,
    phase: CareerPhase.openingOffseason,
    league: nextLeague,
    draftOrder: nextOrder,
    draftClass: const DraftGenerator().generateDraftClass(
      league: nextLeague,
      seed: y1.generationSeed + 2,
      seasonYear: 2,
    ),
    draftExecutionState: DraftExecutionState.initial(),
    freeAgentPool: FreeAgentPool(
      seasonYear: 2,
      entries: y1.freeAgentPool.entries,
    ),
    freeAgentMarket: FreeAgentMarketState.initial(seasonYear: 2),
    offseasonClearance: OffseasonClearanceState.initial(seasonYear: 2),
    hardshipSettlement: HardshipSettlement.initial(seasonYear: 2),
    finances: nextFinances,
    regularSeasonState: null,
    playInState: null,
    playoffState: null,
  );
}

void main() {
  group('M009-T05C-C1: Schema v22 & Multi-Season Validator Readiness', () {
    test(
      '1 & 4: fresh v22 career construction and deterministic round-trip',
      () {
        final career = _newOpeningCareer();
        expect(career.schemaVersion, GmCareerCodec.currentSchemaVersion);
        expect(GmCareerCodec.currentSchemaVersion, greaterThanOrEqualTo(22));
        expect(career.retiredPlayers, isEmpty);
        expect(career.seasonSettlements, isEmpty);
        expect(career.careerDraftRights, isEmpty);
        expect(career.freeAgentPool.seasonYear, 1);

        final encoded1 = GmCareerCodec.encode(career);
        final decoded = GmCareerCodec.decode(encoded1);
        final encoded2 = GmCareerCodec.encode(decoded);
        expect(encoded2, equals(encoded1));
      },
    );

    test(
      '2, 5, 6, 20: v21 -> v22 lossless migration preserves all data without mutation',
      () {
        final career = _newOpeningCareer();
        final v21Json = _asV21Json(career);
        final migrated = GmCareerCodec.decode(v21Json);

        expect(migrated.schemaVersion, GmCareerCodec.currentSchemaVersion);
        expect(migrated.currentYear, career.currentYear);
        expect(migrated.phase, career.phase);
        expect(migrated.id, career.id);
        expect(
          migrated.finances.contracts.length,
          career.finances.contracts.length,
        );
        for (final entry in career.finances.contracts.entries) {
          final migratedSchedule = migrated.finances.scheduleFor(entry.key)!;
          final originalSchedule = career.finances.scheduleFor(entry.key)!;
          expect(
            migratedSchedule.annualSalaries,
            equals(originalSchedule.annualSalaries),
          );
        }
        for (final tid in career.finances.teamFinances.keys) {
          final before = career.finances.teamFinances[tid]!;
          final after = migrated.finances.teamFinances[tid]!;
          expect(after.cash, before.cash);
          expect(after.operatingBudget, before.operatingBudget);
          expect(after.revenueBaseline, before.revenueBaseline);
        }
        expect(
          migrated.freeAgentPool.initialPlayerIds,
          equals(career.freeAgentPool.initialPlayerIds),
        );
        expect(migrated.freeAgentPool.seasonYear, 1);
        expect(migrated.retiredPlayers, isEmpty);
        expect(migrated.seasonSettlements, isEmpty);
        expect(migrated.careerDraftRights, isEmpty);
        expect(
          GmCareerCodec.encode(migrated),
          equals(GmCareerCodec.encode(career)),
        );
      },
    );

    test(
      '3: legacy v20 save migrates cleanly to v22 and rejects v22 fields on <v22',
      () {
        final career = _newOpeningCareer();
        final v20Json = _asV20Json(career);
        final migrated = GmCareerCodec.decode(v20Json);
        expect(migrated.schemaVersion, GmCareerCodec.currentSchemaVersion);
        expect(migrated.seasonHistory, isEmpty);
        expect(migrated.retiredPlayers, isEmpty);

        final pollutedV21 =
            jsonDecode(_asV21Json(career)) as Map<String, dynamic>;
        pollutedV21['retiredPlayers'] = <Object?>[];
        expect(
          () => GmCareerCodec.decode(jsonEncode(pollutedV21)),
          throwsFormatException,
        );
      },
    );

    test(
      '7, 8, 9: expired rookie history allowed; active rookie & duplicate contracts strict',
      () {
        final y1 = _newOpeningCareer();
        final y2Base = _buildYear2Shell(y1);
        final sampleTeam = y2Base.league.teams.first;
        final samplePlayer = sampleTeam.players.first;

        // Expired 1-year rookie contract from Year 1 survives in rookieSigningLedger in Year 2
        final expiredRookie = RookieContract(
          id: RookieContract.idFor(PlayerId('historical-rookie-1')),
          playerId: PlayerId('historical-rookie-1'),
          teamId: sampleTeam.id,
          overallPick: 5,
          category: RosterCategory.standard,
          startYear: 1,
          durationYears: 1,
          draftSeasonYear: 1,
        );
        final y2WithExpiredRookie = y2Base.copyWith(
          rookieSigningLedger: RookieSigningLedger(
            contracts: {'historical-rookie-1': expiredRookie},
          ),
        );
        expect(y2WithExpiredRookie.rookieSigningLedger.length, 1);

        // Active rookie contract from Year 1 (2-year deal) still requires linked PlayerContract in Year 2
        final activeRookie = RookieContract(
          id: RookieContract.idFor(samplePlayer.id),
          playerId: samplePlayer.id,
          teamId: sampleTeam.id,
          overallPick: 6,
          category: RosterCategory.standard,
          startYear: 1,
          durationYears: 2,
          draftSeasonYear: 1,
        );
        expect(
          () => y2Base.copyWith(
            rookieSigningLedger: RookieSigningLedger(
              contracts: {samplePlayer.id.value: activeRookie},
            ),
          ),
          throwsA(isA<DomainValidationException>()),
        );

        // Duplicate active contracts rejected
        final existingContract = y2Base.finances.contracts.values.first;
        expect(
          () => CareerFinances(
            contracts: [existingContract, existingContract],
            schedules: y2Base.finances.schedules.values,
            teamFinances: y2Base.finances.teamFinances.values,
            staffCommitments: y2Base.finances.staffCommitments.values,
            facilities: y2Base.finances.facilities.values,
          ),
          throwsA(isA<DomainValidationException>()),
        );
      },
    );

    test(
      '10, 11, 12: Year 1 opening-pick entitlement strict; Year 2 draft order decoupled',
      () {
        final y1 = _newOpeningCareer();
        // Swap pick 1 and pick 2 original owners
        final swappedPicks = [
          for (var i = 0; i < y1.draftOrder.picks.length; i++)
            if (i == 0)
              DraftPick(
                round: 1,
                pickInRound: 1,
                overallPick: 1,
                originalOwnerTeamId: y1.draftOrder.picks[1].originalOwnerTeamId,
                currentOwnerTeamId: y1.draftOrder.picks[1].currentOwnerTeamId,
              )
            else if (i == 1)
              DraftPick(
                round: 1,
                pickInRound: 2,
                overallPick: 2,
                originalOwnerTeamId: y1.draftOrder.picks[0].originalOwnerTeamId,
                currentOwnerTeamId: y1.draftOrder.picks[0].currentOwnerTeamId,
              )
            else
              y1.draftOrder.picks[i],
        ];
        final swappedOrder = DraftOrder(picks: swappedPicks);

        // Year 1 rejects losing userOpeningDraftPick entitlement
        expect(
          () => y1.copyWith(draftOrder: swappedOrder),
          throwsFormatException,
        );

        // Year 2 accepts swappedOrder cleanly
        final y2 = _buildYear2Shell(y1, customDraftOrder: swappedOrder);
        expect(y2.currentYear, 2);
        expect(
          y2.draftOrder.pickAt(1).originalOwnerTeamId,
          isNot(y2.userFranchiseId),
        );

        // Invalid draft ownership still rejected in Year 2
        final unknownTeamPicks = [
          DraftPick(
            round: 1,
            pickInRound: 1,
            overallPick: 1,
            originalOwnerTeamId: TeamId('unknown-team'),
            currentOwnerTeamId: y1.draftOrder.picks[0].currentOwnerTeamId,
          ),
          for (var i = 1; i < y1.draftOrder.picks.length; i++)
            y1.draftOrder.picks[i],
        ];
        expect(
          () => _buildYear2Shell(
            y1,
            customDraftOrder: DraftOrder(picks: unknownTeamPicks),
          ),
          throwsFormatException,
        );
      },
    );

    test(
      '13, 14, 15, 16: FreeAgentPool season metadata, age 38 support, and collision checks',
      () {
        final y1 = _newOpeningCareer();

        // Year 1 still rejects non-90 snapshot
        expect(
          () => y1.copyWith(
            freeAgentPool: FreeAgentPool(
              seasonYear: 1,
              entries: y1.freeAgentPool.entries.take(5).toList(),
            ),
          ),
          throwsFormatException,
        );

        // Year 2 accepts smaller pool with 38-year-old veteran
        final vet = y1.freeAgentPool.entries.first;
        final vet38 = FreeAgentEntry(
          player: vet.player,
          profile: PlayerCareerProfile(
            playerId: vet.id,
            age: 38,
            potential: vet.profile.potential,
            trajectory: vet.profile.trajectory,
          ),
        );
        final y2 = _buildYear2Shell(y1).copyWith(
          freeAgentPool: FreeAgentPool(seasonYear: 2, entries: [vet38]),
        );
        expect(y2.freeAgentPool.seasonYear, 2);
        expect(y2.freeAgentPool.entries.single.profile.age, 38);

        // Mismatched seasonYear rejected
        expect(
          () => y2.copyWith(
            freeAgentPool: FreeAgentPool(seasonYear: 1, entries: [vet38]),
          ),
          throwsFormatException,
        );

        // Cross-roster free-agent identity collision rejected
        final rosteredPlayer = y2.league.teams.first.players.first;
        final rosteredProfile = y2.careerProfiles.forPlayer(rosteredPlayer.id)!;
        expect(
          () => y2.copyWith(
            freeAgentPool: FreeAgentPool(
              seasonYear: 2,
              entries: [
                FreeAgentEntry(
                  player: rosteredPlayer,
                  profile: rosteredProfile,
                ),
              ],
            ),
          ),
          throwsFormatException,
        );
      },
    );

    test(
      '17, 18, 19: RetiredPlayerRecord, SeasonSettlementRecord, and careerDraftRights validation',
      () {
        final y1 = _newOpeningCareer();
        final y2Base = _buildYear2Shell(y1);
        final teamIds = [for (final t in y2Base.league.teams) t.id];

        final retired = RetiredPlayerRecord(
          playerId: PlayerId('retired-legend-1'),
          fullName: 'Retired Legend',
          position: Position.c,
          finalAge: 38,
          retiredAfterYear: 1,
          lastTeamId: teamIds.first,
          finalOverall: 74,
        );
        final settlement = SeasonSettlementRecord(
          seasonYear: 1,
          settledTeamIds: teamIds,
          totalRevenue: 1500000,
          totalExpenses: 1200000,
        );
        final rights = DraftRights(
          prospectId: PlayerId('y1-unsigned-prospect'),
          owningTeamId: teamIds.first,
          overallPick: 45,
          seasonYear: 1,
        );
        final carriedProspect = CarriedUnsignedProspect(
          playerId: rights.prospectId,
          firstName: 'Unsigned',
          lastName: 'Prospect',
          position: Position.sg,
          attributes: y2Base.league.teams.first.players.first.attributes,
          age: 20,
          potential: 85,
          trajectory: DevelopmentTrajectory.steady,
          draftSeasonYear: 1,
          overallPick: 45,
          projectedRank: 45,
          estimatedPotentialGrade: 'B',
          estimatedPotentialRange: '80-86',
        );

        final y2Full = y2Base.copyWith(
          retiredPlayers: [retired],
          seasonSettlements: [settlement],
          careerDraftRights: {rights.prospectId.value: rights},
          carriedUnsignedProspects: {rights.prospectId.value: carriedProspect},
        );
        final decoded = GmCareerCodec.decode(GmCareerCodec.encode(y2Full));
        expect(decoded.retiredPlayers, equals([retired]));
        expect(decoded.seasonSettlements, equals([settlement]));
        expect(decoded.careerDraftRights[rights.prospectId.value], isNotNull);

        // Invalid retiredAfterYear >= currentYear rejected
        expect(
          () => y2Base.copyWith(
            retiredPlayers: [
              RetiredPlayerRecord(
                playerId: PlayerId('retired-y2'),
                fullName: 'Future Retiree',
                position: Position.pg,
                finalAge: 35,
                retiredAfterYear: 2,
                finalOverall: 70,
              ),
            ],
          ),
          throwsFormatException,
        );

        // Duplicate SeasonSettlementRecord rejected
        expect(
          () => y2Base.copyWith(seasonSettlements: [settlement, settlement]),
          throwsFormatException,
        );

        // careerDraftRights colliding with rostered player rejected
        final rostered = y2Base.league.teams.first.players.first;
        expect(
          () => y2Base.copyWith(
            careerDraftRights: {
              rostered.id.value: DraftRights(
                prospectId: rostered.id,
                owningTeamId: teamIds.first,
                overallPick: 12,
                seasonYear: 1,
              ),
            },
          ),
          throwsFormatException,
        );
      },
    );
  });
}
