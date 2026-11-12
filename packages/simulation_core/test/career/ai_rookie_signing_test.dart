import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import '../support/financial_fixtures.dart';

const _seed = 20261028;
const _team = TeamId('team-1');
const _aiService = RookieAiSigningService();
const _policy = AiRookieSigningPolicy();

void main() {
  final careers = <FranchiseSituation, GmCareer>{};

  setUpAll(() {
    for (final situation in FranchiseSituation.values) {
      careers[situation] = _completedCareer(situation);
    }
  });

  group('M008-T07C AI signing policy', () {
    test('situation changes the strategic choice', () {
      final prospect = _view(overall: 52, range: '62–68', age: 21);
      final tanking = _policyTeam(
        situation: FranchiseSituation.tanking,
        targetCount: 0,
      );
      final contender = _policyTeam(
        situation: FranchiseSituation.contender,
        targetCount: 0,
      );

      final tankingChoice = _policy.decide(
        prospect: prospect,
        team: tanking,
        situation: FranchiseSituation.tanking,
        overallPick: 40,
      );
      final contenderChoice = _policy.decide(
        prospect: prospect,
        team: contender,
        situation: FranchiseSituation.contender,
        overallPick: 40,
      );

      expect(tankingChoice.category, RosterCategory.standard);
      expect(tankingChoice.durationYears, 4);
      expect(contenderChoice.category, RosterCategory.twoWay);
      expect(contenderChoice.durationYears, 1);
      expect(tankingChoice.category, isNot(contenderChoice.category));
    });

    test('roster position depth changes the choice', () {
      final prospect = _view(overall: 58, range: '66–72', age: 21);
      final shallow = _policyTeam(
        situation: FranchiseSituation.playIn,
        targetCount: 0,
      );
      final deep = _policyTeam(
        situation: FranchiseSituation.playIn,
        targetCount: 3,
      );

      final shallowChoice = _policy.decide(
        prospect: prospect,
        team: shallow,
        situation: FranchiseSituation.playIn,
        overallPick: 40,
      );
      final deepChoice = _policy.decide(
        prospect: prospect,
        team: deep,
        situation: FranchiseSituation.playIn,
        overallPick: 40,
      );

      expect(shallowChoice.category, RosterCategory.standard);
      expect(deepChoice.isSigning, isFalse);
      expect(deepChoice.reason, AiSigningReason.deferredLowFit);
    });

    test('first-round prospects receive the preservation bonus', () {
      final prospect = _view(overall: 64, range: '80–86', age: 20);
      final team = _policyTeam(
        situation: FranchiseSituation.playoff,
        targetCount: 2,
      );
      final secondRound = _policy.decide(
        prospect: prospect,
        team: team,
        situation: FranchiseSituation.playoff,
        overallPick: 40,
      );
      final firstRound = _policy.decide(
        prospect: prospect,
        team: team,
        situation: FranchiseSituation.playoff,
        overallPick: 20,
      );
      expect(firstRound.category, RosterCategory.standard);
      expect(secondRound.category, RosterCategory.twoWay);
    });

    test('a full standard roster defers instead of signing', () {
      final prospect = _view(overall: 70, range: '80–86', age: 22);
      final team = _policyTeam(
        situation: FranchiseSituation.playIn,
        standard: 15,
        targetCount: 0,
      );
      final choice = _policy.decide(
        prospect: prospect,
        team: team,
        situation: FranchiseSituation.playIn,
        overallPick: 40,
      );
      expect(choice.isSigning, isFalse);
      expect(choice.reason, AiSigningReason.deferredNoStandardSlot);
    });

    test('a full two-way pool defers developmental prospects', () {
      final prospect = _view(overall: 50, range: '58–64', age: 19);
      final team = _policyTeam(
        situation: FranchiseSituation.playIn,
        twoWay: 3,
        targetCount: 3,
      );
      final choice = _policy.decide(
        prospect: prospect,
        team: team,
        situation: FranchiseSituation.playIn,
        overallPick: 40,
      );
      expect(choice.isSigning, isFalse);
      expect(choice.reason, AiSigningReason.deferredNoTwoWaySlot);
    });

    test('a full offseason roster defers regardless of quality', () {
      final prospect = _view(overall: 75, range: '85–91', age: 20);
      final team = _policyTeam(
        situation: FranchiseSituation.tanking,
        standard: 12,
        twoWay: 3,
        trainingCamp: 6,
        targetCount: 0,
      );
      final choice = _policy.decide(
        prospect: prospect,
        team: team,
        situation: FranchiseSituation.tanking,
        overallPick: 1,
      );
      expect(choice.isSigning, isFalse);
      expect(choice.reason, AiSigningReason.deferredRosterFull);
    });

    test('duration choices stay inside RookieContract bounds', () {
      final prospect = _view(overall: 70, range: '80–86', age: 19);
      for (final situation in FranchiseSituation.values) {
        final team = _policyTeam(situation: situation, targetCount: 0);
        final choice = _policy.decide(
          prospect: prospect,
          team: team,
          situation: situation,
          overallPick: 1,
        );
        if (choice.isSigning) {
          expect(
            choice.durationYears,
            inInclusiveRange(
              RookieContract.minDurationYears,
              RookieContract.maxDurationFor(choice.category!),
            ),
          );
        }
      }
    });

    test('range midpoint parsing is tolerant and deterministic', () {
      expect(AiRookieSigningPolicy.rangeMidpoint('85–91'), 88);
      expect(AiRookieSigningPolicy.rangeMidpoint('64-70'), 67);
      expect(AiRookieSigningPolicy.rangeMidpoint('72'), 72);
      expect(AiRookieSigningPolicy.rangeMidpoint('unknown'), 60);
    });
  });

  group('M008-T07C AI signing service', () {
    test('1-3. every AI right is decided and human rights are untouched', () {
      final career = careers[FranchiseSituation.playIn]!;
      final advanced = _aiService.advanceAll(career);
      final aiRights = _aiRights(career);

      expect(advanced.aiRookieSigning.length, aiRights.length);
      expect(aiRights.length, 58);
      for (final right in aiRights) {
        final decision = advanced.aiRookieSigning.forProspect(right.prospectId);
        expect(decision, isNotNull, reason: right.prospectId.value);
        expect(
          decision!.decision,
          isIn([
            AiSigningDecisionType.signedStandard,
            AiSigningDecisionType.signedTwoWay,
            AiSigningDecisionType.deferred,
          ]),
        );
      }
      for (final right in _userRights(career)) {
        expect(advanced.aiRookieSigning.hasDecision(right.prospectId), isFalse);
        expect(
          advanced.rookieSigningLedger.isSigned(right.prospectId),
          isFalse,
        );
      }
      expect(_aiService.pendingRights(advanced), isEmpty);
    });

    test('4-5, 11-12. contracts, rosters and profiles stay consistent', () {
      final career = careers[FranchiseSituation.tanking]!;
      final advanced = _aiService.advanceAll(career);
      var signed = 0;
      for (final decision in advanced.aiRookieSigning.ordered) {
        final contract = advanced.rookieSigningLedger.forPlayer(
          decision.prospectId,
        );
        if (!decision.isSigned) {
          expect(contract, isNull);
          continue;
        }
        signed++;
        expect(contract, isNotNull);
        expect(contract!.teamId, decision.teamId);
        expect(contract.id, decision.contractId);
        expect(
          contract.durationYears,
          inInclusiveRange(
            RookieContract.minDurationYears,
            RookieContract.maxDurationFor(contract.category),
          ),
        );
        final team = advanced.league.teams.firstWhere(
          (t) => t.id == contract.teamId,
        );
        final player = team.players.firstWhere(
          (p) => p.id == contract.playerId,
        );
        expect(team.roster.categoryOf(player.id), contract.category);
        final prospect = advanced.draftClass.byId(contract.playerId)!;
        final profile = advanced.careerProfiles.forPlayer(contract.playerId)!;
        expect(profile.age, prospect.age);
        expect(profile.potential, prospect.potential);
        expect(profile.trajectory, prospect.trajectory);
      }
      expect(signed, greaterThan(0));
    });

    test('6-8. hidden prospect data cannot change AI decisions', () {
      final career = careers[FranchiseSituation.playoff]!;
      final changedClass = RookieDraftClass(
        seasonYear: career.draftClass.seasonYear,
        prospects: [
          for (final prospect in career.draftClass.prospects)
            RookieProspect(
              id: prospect.id,
              firstName: prospect.firstName,
              lastName: prospect.lastName,
              position: prospect.position,
              age: prospect.age,
              attributes: prospect.attributes,
              potential: 100,
              trajectory: DevelopmentTrajectory.lateBloomer,
              projectedRank: prospect.projectedRank,
              estimatedPotentialGrade: prospect.estimatedPotentialGrade,
              estimatedPotentialRange: prospect.estimatedPotentialRange,
            ),
        ],
      );
      final changed = career.copyWith(draftClass: changedClass);
      final baseline = _aiService.advanceAll(career);
      final alternative = _aiService.advanceAll(changed);

      expect(
        jsonEncode(alternative.aiRookieSigning.toJson()),
        jsonEncode(baseline.aiRookieSigning.toJson()),
      );
      expect(
        alternative.rookieSigningLedger.ordered
            .map((c) => '${c.playerId.value}:${c.category.jsonValue}')
            .toList(),
        baseline.rookieSigningLedger.ordered
            .map((c) => '${c.playerId.value}:${c.category.jsonValue}')
            .toList(),
      );
    });

    test('9-10. deferred and unprocessed decisions are distinct', () {
      final career = careers[FranchiseSituation.contender]!;
      final advanced = _aiService.advanceAll(career);
      final deferred = advanced.aiRookieSigning.ordered.where(
        (d) => !d.isSigned,
      );
      expect(deferred, isNotEmpty);
      for (final decision in deferred) {
        expect(
          advanced.rookieSigningLedger.isSigned(decision.prospectId),
          isFalse,
        );
        expect(
          advanced.draftExecutionState.draftRights.containsKey(
            decision.prospectId.value,
          ),
          isTrue,
        );
      }
      expect(_aiService.pendingRights(advanced), isEmpty);
      expect(
        advanced.aiRookieSigning.hasDecision(deferred.first.prospectId),
        isTrue,
      );
    });

    test('13. draft history and prospect class are unchanged', () {
      final career = careers[FranchiseSituation.playIn]!;
      final advanced = _aiService.advanceAll(career);
      expect(
        jsonEncode(advanced.draftExecutionState.toJson()),
        jsonEncode(career.draftExecutionState.toJson()),
      );
      expect(
        jsonEncode(advanced.draftClass.toJson()),
        jsonEncode(career.draftClass.toJson()),
      );
      expect(advanced.draftExecutionState.selections.length, 60);
      expect(advanced.draftExecutionState.draftRights.length, 60);
    });

    test('14. repeated processing is idempotent', () {
      final career = careers[FranchiseSituation.playIn]!;
      final once = _aiService.advanceAll(career);
      final twice = _aiService.advanceAll(once);
      expect(GmCareerCodec.encode(twice), GmCareerCodec.encode(once));
      expect(twice.rookieSigningLedger.length, once.rookieSigningLedger.length);
    });

    test('15-16. save/load and interrupted evaluation resume exactly', () {
      final career = careers[FranchiseSituation.playIn]!;
      final full = _aiService.advanceAll(career);

      final reloaded = GmCareerCodec.decode(GmCareerCodec.encode(full));
      expect(
        jsonEncode(reloaded.aiRookieSigning.toJson()),
        jsonEncode(full.aiRookieSigning.toJson()),
      );
      expect(
        jsonEncode(reloaded.rookieSigningLedger.toJson()),
        jsonEncode(full.rookieSigningLedger.toJson()),
      );

      var partial = _aiService.initialize(career);
      for (var i = 0; i < 7; i++) {
        partial = _aiService.applyNextDecision(partial);
      }
      final restored = GmCareerCodec.decode(GmCareerCodec.encode(partial));
      final resumed = _aiService.advanceAll(restored);
      expect(GmCareerCodec.encode(resumed), GmCareerCodec.encode(full));
    });

    test('17. invalid commands mutate nothing', () {
      final initial = GmCareer.fromSetupResult(
        const CareerSetupService().generate(
          const CareerSetupRequest(
            selectedTeamId: _team,
            selectedSituation: FranchiseSituation.playIn,
            seed: _seed,
          ),
        ),
        id: 't07c-incomplete',
      );
      final before = GmCareerCodec.encode(initial);
      expect(() => _aiService.advanceAll(initial), throwsA(isA<StateError>()));
      expect(
        () => _aiService.applyNextDecision(initial),
        throwsA(isA<StateError>()),
      );
      expect(GmCareerCodec.encode(initial), before);
    });

    test('18. human contracts and rosters stay unchanged', () {
      final career = careers[FranchiseSituation.playIn]!;
      final humanRight = _userRights(career).first;
      final withHuman = const RookieSigningService().signDraftedRookie(
        career: career,
        teamId: _team,
        prospectId: humanRight.prospectId,
        category: RosterCategory.standard,
        durationYears: 3,
      );
      final humanContract = withHuman.rookieSigningLedger.forPlayer(
        humanRight.prospectId,
      )!;
      final humanRoster = withHuman.userTeam.players.map((p) => p.id).toList();

      final advanced = _aiService.advanceAll(withHuman);
      expect(
        jsonEncode(
          advanced.rookieSigningLedger
              .forPlayer(humanRight.prospectId)!
              .toJson(),
        ),
        jsonEncode(humanContract.toJson()),
      );
      expect(advanced.userTeam.players.map((p) => p.id).toList(), humanRoster);
      expect(
        advanced.aiRookieSigning.hasDecision(humanRight.prospectId),
        isFalse,
      );
    });

    test('19. v5 saves migrate with an empty decision state', () {
      final career = careers[FranchiseSituation.playIn]!;
      final advanced = _aiService.advanceAll(career);
      final v6 =
          jsonDecode(GmCareerCodec.encode(advanced)) as Map<String, dynamic>;
      final v5 = Map<String, dynamic>.from(v6)
        ..['schemaVersion'] = 5
        ..remove('aiRookieSigning');
      final migrated = GmCareerCodec.decode(jsonEncode(v5));

      expect(migrated.schemaVersion, GmCareer.currentSchemaVersion);
      expect(migrated.aiRookieSigning.isEmpty, isTrue);
      expect(
        jsonEncode(migrated.rookieSigningLedger.toJson()),
        jsonEncode(advanced.rookieSigningLedger.toJson()),
      );
      expect(
        jsonEncode(migrated.draftExecutionState.toJson()),
        jsonEncode(advanced.draftExecutionState.toJson()),
      );

      final resumed = _aiService.advanceAll(migrated);
      expect(resumed.aiRookieSigning.length, advanced.aiRookieSigning.length);
      expect(
        jsonEncode(resumed.rookieSigningLedger.toJson()),
        jsonEncode(advanced.rookieSigningLedger.toJson()),
      );
    });

    test('19b. existing AI contracts are recognized, not duplicated', () {
      final career = careers[FranchiseSituation.playIn]!;
      final aiRight = _aiRights(career).first;
      final withAiContract = const RookieSigningService().signDraftedRookie(
        career: career,
        teamId: aiRight.owningTeamId,
        prospectId: aiRight.prospectId,
        category: RosterCategory.standard,
        durationYears: 3,
      );
      final advanced = _aiService.advanceAll(withAiContract);

      final decision = advanced.aiRookieSigning.forProspect(
        aiRight.prospectId,
      )!;
      expect(decision.decision, AiSigningDecisionType.signedStandard);
      expect(decision.reason, AiSigningReason.signedExistingContract);
      expect(
        advanced.rookieSigningLedger
            .forPlayer(aiRight.prospectId)!
            .durationYears,
        3,
      );
      expect(
        advanced.rookieSigningLedger.ordered
            .where((c) => c.playerId == aiRight.prospectId)
            .length,
        1,
      );
    });

    test('capacity limits are respected for expanded AI rosters', () {
      final career = careers[FranchiseSituation.playIn]!;
      final pickOne = career.draftExecutionState.draftRights.values.firstWhere(
        (rights) => rights.overallPick == 1,
      );
      final expanded = _expandTeam(career, pickOne.owningTeamId, standard: 3);
      final advanced = _aiService.advanceAll(expanded);

      for (final decision in advanced.aiRookieSigning.ordered.where(
        (d) => d.teamId == pickOne.owningTeamId,
      )) {
        expect(decision.decision, isNot(AiSigningDecisionType.signedStandard));
      }
      final team = advanced.league.teams.firstWhere(
        (t) => t.id == pickOne.owningTeamId,
      );
      expect(team.roster.standardCount, lessThanOrEqualTo(15));
      expect(team.roster.totalContractedCount, lessThanOrEqualTo(21));
    });

    test('corrupt decision records are rejected on decode', () {
      final advanced = _aiService.advanceAll(
        careers[FranchiseSituation.playIn]!,
      );
      final humanRight = _userRights(careers[FranchiseSituation.playIn]!).first;
      final signed = advanced.aiRookieSigning.ordered.firstWhere(
        (d) => d.isSigned,
      );
      final deferred = advanced.aiRookieSigning.ordered.firstWhere(
        (d) => !d.isSigned,
      );

      FormatException failure(Map<String, dynamic> json) {
        try {
          GmCareerCodec.decode(jsonEncode(json));
        } on FormatException catch (error) {
          return error;
        }
        fail('Expected FormatException');
      }

      Map<String, dynamic> base() =>
          jsonDecode(GmCareerCodec.encode(advanced)) as Map<String, dynamic>;
      Map<String, dynamic> decisions(Map<String, dynamic> json) =>
          ((json['aiRookieSigning'] as Map<String, dynamic>)['decisions']
              as Map<String, dynamic>);

      final missing = base()..remove('aiRookieSigning');
      expect(
        failure(missing).message,
        contains('Missing or invalid aiRookieSigning'),
      );

      final human = base();
      decisions(human)[humanRight.prospectId.value] = {
        'teamId': _team.value,
        'prospectId': humanRight.prospectId.value,
        'draftSeasonYear': 1,
        'overallPick': humanRight.overallPick,
        'decision': 'deferred',
        'reason': 'deferredLowFit',
      };
      expect(failure(human).message, contains('targets the human franchise'));

      final noContract = base();
      decisions(noContract)[deferred.prospectId.value] = {
        'teamId': deferred.teamId.value,
        'prospectId': deferred.prospectId.value,
        'draftSeasonYear': deferred.draftSeasonYear,
        'overallPick': deferred.overallPick,
        'decision': 'signedStandard',
        'reason': 'signedStandardQuality',
        'contractId': 'rookie-contract-missing',
      };
      expect(failure(noContract).message, contains('lacks a rookie contract'));

      final deferredWithContract = base();
      decisions(deferredWithContract)[signed.prospectId.value] = {
        'teamId': signed.teamId.value,
        'prospectId': signed.prospectId.value,
        'draftSeasonYear': signed.draftSeasonYear,
        'overallPick': signed.overallPick,
        'decision': 'deferred',
        'reason': 'deferredLowFit',
      };
      expect(
        failure(deferredWithContract).message,
        contains('contradicts a signed contract'),
      );

      final wrongPick = base();
      (decisions(wrongPick)[signed.prospectId.value]
          as Map<String, dynamic>)['overallPick'] = signed.overallPick == 60
          ? 59
          : signed.overallPick + 1;
      expect(
        failure(wrongPick).message,
        contains('does not match its draft selection'),
      );

      final wrongTeam = base();
      (decisions(wrongTeam)[signed.prospectId.value]
          as Map<String, dynamic>)['teamId'] = signed.teamId.value == 'team-1'
          ? 'team-2'
          : 'team-1';
      expect(failure(wrongTeam).message, contains('current draft ownership'));
    });
  });

  group('M008-T07C AI offseason simulations', () {
    for (final situation in FranchiseSituation.values) {
      test('${situation.name}: distributions and readiness', () {
        final career = careers[situation]!;
        final advanced = _aiService.advanceAll(career);
        final decisions = advanced.aiRookieSigning.ordered;
        final standard = decisions
            .where((d) => d.decision == AiSigningDecisionType.signedStandard)
            .length;
        final twoWay = decisions
            .where((d) => d.decision == AiSigningDecisionType.signedTwoWay)
            .length;
        final deferred = decisions
            .where((d) => d.decision == AiSigningDecisionType.deferred)
            .length;

        final aiTeams = advanced.league.teams
            .where((t) => t.id != advanced.userFranchiseId)
            .toList();
        var ready = 0;
        var belowMinimum = 0;
        var holdingUnsignedRights = 0;
        var withTwoWayRookies = 0;
        var failingOtherChecks = 0;
        for (final team in aiTeams) {
          final readiness = team.roster.validateRegularSeasonReadiness();
          if (readiness.isValid) ready++;
          if (team.roster.standardCount <
              RosterRules.minRegularSeasonStandard) {
            belowMinimum++;
          }
          if (team.roster.twoWayPlayers.any(
            (p) => advanced.rookieSigningLedger.isSigned(p.id),
          )) {
            withTwoWayRookies++;
          }
          if (advanced.draftExecutionState.draftRights.values.any(
            (rights) =>
                rights.owningTeamId == team.id &&
                !advanced.rookieSigningLedger.isSigned(rights.prospectId),
          )) {
            holdingUnsignedRights++;
          }
          if (!readiness.isValid &&
              team.roster.standardCount >=
                  RosterRules.minRegularSeasonStandard) {
            failingOtherChecks++;
          }
        }

        // ignore: avoid_print
        print(
          'T07C ${situation.name}: standard=$standard twoWay=$twoWay '
          'deferred=$deferred decisions=${decisions.length} '
          'ready=$ready belowMin=$belowMinimum '
          'unsignedRights=$holdingUnsignedRights '
          'twoWayRookies=$withTwoWayRookies '
          'otherFailing=$failingOtherChecks',
        );

        expect(standard + twoWay + deferred, _aiRights(career).length);
        expect(ready + belowMinimum, aiTeams.length);
        expect(
          advanced.rookieSigningLedger.ordered.where(
            (c) => c.teamId == advanced.userFranchiseId,
          ),
          isEmpty,
        );
      });
    }
  });
}

GmCareer _completedCareer(FranchiseSituation situation) {
  final setup = const CareerSetupService().generate(
    CareerSetupRequest(
      selectedTeamId: _team,
      selectedSituation: situation,
      seed: _seed,
    ),
  );
  var career = GmCareer.fromSetupResult(setup, id: 't07c-${situation.name}');
  const draft = DraftExecutionService();
  career = draft.startDraft(career);
  while (!career.draftExecutionState.isCompleted) {
    career =
        career.draftExecutionState.isHumanTurn(
          order: career.draftOrder,
          userTeamId: career.userFranchiseId,
        )
        ? draft.makeHumanSelection(
            career: career,
            prospectId: career.draftExecutionState
                .availableProspects(career.draftClass)
                .first
                .id,
          )
        : draft.executeAiSelection(career);
  }
  return career;
}

List<DraftRights> _userRights(GmCareer career) => career
    .draftExecutionState
    .draftRights
    .values
    .where((rights) => rights.owningTeamId == career.userFranchiseId)
    .toList();

List<DraftRights> _aiRights(GmCareer career) => career
    .draftExecutionState
    .draftRights
    .values
    .where((rights) => rights.owningTeamId != career.userFranchiseId)
    .toList();

GmCareer _expandTeam(
  GmCareer career,
  TeamId teamId, {
  int standard = 0,
  int twoWay = 0,
  int trainingCamp = 0,
}) {
  final team = career.league.teams.firstWhere((t) => t.id == teamId);
  var roster = team.roster;
  final added = <Player>[];
  void add(int count, String prefix, RosterCategory category) {
    for (var i = 0; i < count; i++) {
      final player = _testPlayer('$prefix-${teamId.value}-$i');
      added.add(player);
      roster = roster.withPlayer(player, category: category);
    }
  }

  add(standard, 'ai-std', RosterCategory.standard);
  add(twoWay, 'ai-tw', RosterCategory.twoWay);
  add(trainingCamp, 'ai-tc', RosterCategory.trainingCamp);
  final updated = team.copyWith(roster: roster);
  final updatedLeague = League.create(
    id: career.league.id,
    name: career.league.name,
    config: career.league.config,
    teams: [
      for (final candidate in career.league.teams)
        candidate.id == teamId ? updated : candidate,
    ],
    enforceRosterSize: false,
  );
  return withBootstrappedLeague(
    career,
    updatedLeague,
    careerProfiles: LeagueCareerProfiles(
      leagueSeed: career.careerProfiles.leagueSeed,
      profiles: {
        ...career.careerProfiles.profiles,
        for (final player in added)
          player.id.value: PlayerCareerProfile(
            playerId: player.id,
            age: 24,
            potential: 60,
            trajectory: DevelopmentTrajectory.steady,
          ),
      },
    ),
  );
}

PublicProspectScoutingView _view({
  required int overall,
  required String range,
  required int age,
}) => PublicProspectScoutingView(
  id: const PlayerId('prospect-policy'),
  firstName: 'Policy',
  lastName: 'Prospect',
  position: Position.sg,
  age: age,
  attributes: _attributes(overall),
  overallRating: overall,
  projectedRank: 40,
  estimatedPotentialGrade: 'B',
  estimatedPotentialRange: range,
);

Team _policyTeam({
  required FranchiseSituation situation,
  int standard = 12,
  int twoWay = 0,
  int trainingCamp = 0,
  required int targetCount,
}) {
  final players = <Player>[];
  final categories = <String, RosterCategory>{};
  void add(int count, Position position, RosterCategory category) {
    for (var i = 0; i < count; i++) {
      final player = Player(
        id: PlayerId('policy-${players.length}'),
        firstName: 'Policy',
        lastName: '${players.length}',
        position: position,
        attributes: _attributes(50),
      );
      players.add(player);
      categories[player.id.value] = category;
    }
  }

  final target = targetCount.clamp(0, standard).toInt();
  add(target, Position.sg, RosterCategory.standard);
  add(standard - target, Position.pg, RosterCategory.standard);
  add(twoWay, Position.c, RosterCategory.twoWay);
  add(trainingCamp, Position.pf, RosterCategory.trainingCamp);
  return Team(
    id: const TeamId('policy-team'),
    name: 'Policy Team',
    abbreviation: 'PLT',
    roster: Roster(players, categories: categories),
    situation: situation,
  );
}

Player _testPlayer(String id) => Player(
  id: PlayerId(id),
  firstName: 'Added',
  lastName: id,
  position: Position.sg,
  attributes: _attributes(50),
);

PlayerAttributes _attributes(int value) => PlayerAttributes(
  insideScoring: value,
  midrange: value,
  threePoint: value,
  freeThrow: value,
  passing: value,
  ballHandling: value,
  perimeterDefense: value,
  interiorDefense: value,
  rebounding: value,
  athleticism: value,
  stamina: value,
  basketballIQ: value,
);
