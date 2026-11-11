import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _seed = 20261028;
const _team = TeamId('team-1');
const _service = RookieSigningService();

void main() {
  final careers = <FranchiseSituation, GmCareer>{};

  setUpAll(() {
    for (final situation in FranchiseSituation.values) {
      careers[situation] = _completedCareer(situation);
    }
  });

  group('M008-T07A rookie signing engine', () {
    test('1. standard signing adds a contracted roster player', () {
      final career = careers[FranchiseSituation.playIn]!;
      final rights = _userRights(career).first;
      final prospect = career.draftClass.byId(rights.prospectId)!;

      final signed = _service.signDraftedRookie(
        career: career,
        teamId: _team,
        prospectId: rights.prospectId,
        category: RosterCategory.standard,
        durationYears: 4,
      );

      final team = signed.userTeam;
      expect(team.roster.size, 13);
      expect(team.roster.standardCount, 13);
      expect(team.roster.twoWayCount, 0);

      final player = team.players.firstWhere((p) => p.id == prospect.id);
      expect(player.fullName, prospect.fullName);
      expect(player.position, prospect.position);
      expect(player.attributes.asMap, prospect.attributes.asMap);
      expect(player.attributes.overallRating, prospect.overallRating);

      final contract = signed.rookieSigningLedger.forPlayer(prospect.id)!;
      expect(contract.id, RookieContract.idFor(prospect.id));
      expect(contract.teamId, _team);
      expect(contract.category, RosterCategory.standard);
      expect(contract.startYear, 1);
      expect(contract.durationYears, 4);
      expect(contract.endYear, 4);
      expect(contract.draftSeasonYear, 1);
      expect(contract.overallPick, rights.overallPick);
    });

    test('2. two-way signing consumes no standard slot', () {
      final career = careers[FranchiseSituation.tanking]!;
      final rights = _userRights(career).first;

      final signed = _service.signDraftedRookie(
        career: career,
        teamId: _team,
        prospectId: rights.prospectId,
        category: RosterCategory.twoWay,
        durationYears: 2,
      );

      expect(signed.userTeam.roster.size, 13);
      expect(signed.userTeam.roster.standardCount, 12);
      expect(signed.userTeam.roster.twoWayCount, 1);
      expect(
        signed.userTeam.roster.categoryOf(rights.prospectId),
        RosterCategory.twoWay,
      );
    });

    test('3. undrafted prospects and unknown prospects are rejected', () {
      final career = careers[FranchiseSituation.playoff]!;
      final undrafted = career.draftExecutionState
          .undraftedProspects(career.draftClass)
          .first;

      expect(
        () => _service.signDraftedRookie(
          career: career,
          teamId: _team,
          prospectId: undrafted.id,
          category: RosterCategory.standard,
          durationYears: 3,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('was not drafted'),
          ),
        ),
      );
      expect(
        () => _service.signDraftedRookie(
          career: career,
          teamId: _team,
          prospectId: const PlayerId('prospect-unknown'),
          category: RosterCategory.standard,
          durationYears: 3,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('4. prospects owned by another franchise are rejected', () {
      final career = careers[FranchiseSituation.playIn]!;
      final foreign = career.draftExecutionState.draftRights.values.firstWhere(
        (rights) => rights.owningTeamId != _team,
      );

      expect(
        () => _service.signDraftedRookie(
          career: career,
          teamId: _team,
          prospectId: foreign.prospectId,
          category: RosterCategory.standard,
          durationYears: 3,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('draft rights'),
          ),
        ),
      );
    });

    test('5. duplicate signing is rejected', () {
      final career = careers[FranchiseSituation.contender]!;
      final rights = _userRights(career).first;
      final signed = _sign(career, rights.prospectId);

      expect(
        () => _service.signDraftedRookie(
          career: signed,
          teamId: _team,
          prospectId: rights.prospectId,
          category: RosterCategory.standard,
          durationYears: 3,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('already signed'),
          ),
        ),
      );
    });

    test('6. signing requires a completed draft', () {
      final initial = GmCareer.fromSetupResult(
        const CareerSetupService().generate(
          CareerSetupRequest(
            selectedTeamId: _team,
            selectedSituation: FranchiseSituation.playIn,
            seed: _seed,
          ),
        ),
        id: 't07a-incomplete',
      );
      final prospect = initial.draftClass.rankedFirst;
      expect(
        () => _service.signDraftedRookie(
          career: initial,
          teamId: _team,
          prospectId: prospect.id,
          category: RosterCategory.standard,
          durationYears: 3,
        ),
        throwsA(isA<StateError>()),
      );
      final started = const DraftExecutionService().startDraft(initial);
      expect(
        () => _service.signDraftedRookie(
          career: started,
          teamId: _team,
          prospectId: prospect.id,
          category: RosterCategory.standard,
          durationYears: 3,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('7. a 16th standard player is rejected', () {
      final career = _expanded(
        careers[FranchiseSituation.playIn]!,
        standard: 3,
      );
      expect(career.userTeam.roster.standardCount, 15);
      final rights = _userRights(career).first;

      expect(
        () => _service.signDraftedRookie(
          career: career,
          teamId: _team,
          prospectId: rights.prospectId,
          category: RosterCategory.standard,
          durationYears: 3,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Standard player count (16)'),
          ),
        ),
      );
    });

    test('8. a fourth two-way player is rejected', () {
      final career = _expanded(careers[FranchiseSituation.playIn]!, twoWay: 3);
      expect(career.userTeam.roster.twoWayCount, 3);
      final rights = _userRights(career).first;

      expect(
        () => _service.signDraftedRookie(
          career: career,
          teamId: _team,
          prospectId: rights.prospectId,
          category: RosterCategory.twoWay,
          durationYears: 1,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Two-way player count (4)'),
          ),
        ),
      );
    });

    test('9. a 22nd total offseason contracted player is rejected', () {
      final career = _expanded(
        careers[FranchiseSituation.playIn]!,
        twoWay: 3,
        trainingCamp: 6,
      );
      expect(career.userTeam.roster.totalContractedCount, 21);
      final rights = _userRights(career).first;

      expect(
        () => _service.signDraftedRookie(
          career: career,
          teamId: _team,
          prospectId: rights.prospectId,
          category: RosterCategory.standard,
          durationYears: 2,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Total contracted roster count (22)'),
          ),
        ),
      );
    });

    test('10. career profile preserves hidden prospect data', () {
      final career = careers[FranchiseSituation.playoff]!;
      final rights = _userRights(career).first;
      final prospect = career.draftClass.byId(rights.prospectId)!;
      final signed = _sign(career, rights.prospectId);

      final profile = signed.careerProfiles.forPlayer(prospect.id)!;
      expect(profile.age, prospect.age);
      expect(profile.potential, prospect.potential);
      expect(profile.trajectory, prospect.trajectory);
      expect(signed.careerProfiles.length, career.careerProfiles.length + 1);
    });

    test('11. draft history and prospect class are unchanged', () {
      final career = careers[FranchiseSituation.playIn]!;
      final rights = _userRights(career).first;
      final before = jsonEncode(career.draftExecutionState.toJson());
      final classBefore = jsonEncode(career.draftClass.toJson());

      final signed = _sign(career, rights.prospectId);

      expect(jsonEncode(signed.draftExecutionState.toJson()), before);
      expect(jsonEncode(signed.draftClass.toJson()), classBefore);
      expect(signed.draftExecutionState.completedSelectionsCount, 60);
      expect(
        signed.draftExecutionState.undraftedProspects(signed.draftClass).length,
        30,
      );
      expect(
        signed.draftExecutionState.selections
            .where((s) => s.prospectId == rights.prospectId)
            .length,
        1,
      );
    });

    test('12. signed rookies leave derived unsigned rights', () {
      final career = careers[FranchiseSituation.tanking]!;
      final rights = _userRights(career).toList();
      expect(rights.length, 2);
      expect(career.unsignedDraftRights.length, 60);

      final signed = _sign(career, rights[0].prospectId);

      expect(signed.unsignedDraftRights.length, 59);
      expect(
        signed.unsignedDraftRights.any(
          (r) => r.prospectId == rights[0].prospectId,
        ),
        isFalse,
      );
      expect(
        signed.unsignedDraftRights.any(
          (r) => r.prospectId == rights[1].prospectId,
        ),
        isTrue,
      );
    });

    test('13. invalid category and duration combinations are rejected', () {
      final career = careers[FranchiseSituation.playIn]!;
      final rights = _userRights(career).first;

      void expectArgument(RosterCategory category, int duration) {
        expect(
          () => _service.signDraftedRookie(
            career: career,
            teamId: _team,
            prospectId: rights.prospectId,
            category: category,
            durationYears: duration,
          ),
          throwsA(isA<ArgumentError>()),
          reason: '${category.jsonValue} $duration',
        );
      }

      expectArgument(RosterCategory.trainingCamp, 1);
      expectArgument(RosterCategory.standard, 0);
      expectArgument(RosterCategory.standard, 5);
      expectArgument(RosterCategory.twoWay, 3);
    });

    test('14. save/load preserves rosters, contracts and rights', () {
      final career = careers[FranchiseSituation.contender]!;
      final rights = _userRights(career).toList();
      final first = _sign(career, rights[0].prospectId);
      final signed = _service.signDraftedRookie(
        career: first,
        teamId: _team,
        prospectId: rights[1].prospectId,
        category: RosterCategory.twoWay,
        durationYears: 2,
      );

      final decoded = GmCareerCodec.decode(GmCareerCodec.encode(signed));

      expect(decoded.schemaVersion, 5);
      expect(decoded.userTeam.roster.size, 14);
      expect(decoded.userTeam.roster.standardCount, 13);
      expect(decoded.userTeam.roster.twoWayCount, 1);
      expect(decoded.rookieSigningLedger.length, 2);
      expect(
        jsonEncode(decoded.rookieSigningLedger.toJson()),
        jsonEncode(signed.rookieSigningLedger.toJson()),
      );
      expect(decoded.unsignedDraftRights.length, 58);
      expect(
        decoded.draftExecutionState.selections.length,
        signed.draftExecutionState.selections.length,
      );
      for (final contract in signed.rookieSigningLedger.contracts.values) {
        final player = decoded.userTeam.players.firstWhere(
          (p) => p.id == contract.playerId,
        );
        expect(
          decoded.userTeam.roster.categoryOf(player.id),
          contract.category,
        );
        expect(decoded.careerProfiles.forPlayer(contract.playerId), isNotNull);
      }
    });

    test('15. identical commands produce identical encoded careers', () {
      final a = _sign(
        careers[FranchiseSituation.playIn]!,
        _userRights(careers[FranchiseSituation.playIn]!).first.prospectId,
      );
      final b = _sign(
        careers[FranchiseSituation.playIn]!,
        _userRights(careers[FranchiseSituation.playIn]!).first.prospectId,
      );
      expect(GmCareerCodec.encode(a), GmCareerCodec.encode(b));
    });

    test('16. corrupt roster or signing combinations are rejected', () {
      final career = _sign(
        careers[FranchiseSituation.playIn]!,
        _userRights(careers[FranchiseSituation.playIn]!).first.prospectId,
      );
      final signedId = career.rookieSigningLedger.ordered.single.playerId;

      FormatException decodeFailure(Map<String, dynamic> json) {
        try {
          GmCareerCodec.decode(jsonEncode(json));
        } on FormatException catch (e) {
          return e;
        }
        fail('Expected FormatException');
      }

      Map<String, dynamic> base() =>
          jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;

      // Missing ledger section in v5.
      final missingSection = base()..remove('rookieSigningLedger');
      expect(
        decodeFailure(missingSection).message,
        contains('Missing or invalid rookieSigningLedger'),
      );

      // Roster record without signing evidence.
      final noLedger = base();
      (noLedger['rookieSigningLedger'] as Map<String, dynamic>)['contracts'] =
          <String, dynamic>{};
      expect(
        decodeFailure(noLedger).message,
        contains('on a roster without a rookie contract'),
      );

      // Contract whose player is absent from every roster.
      final orphan = base();
      final contracts =
          (orphan['rookieSigningLedger'] as Map<String, dynamic>)['contracts']
              as Map<String, dynamic>;
      final undrafted = career.draftExecutionState
          .undraftedProspects(career.draftClass)
          .first;
      contracts[undrafted.id.value] = {
        'id': RookieContract.idFor(undrafted.id),
        'playerId': undrafted.id.value,
        'teamId': _team.value,
        'category': 'standard',
        'startYear': 1,
        'durationYears': 3,
        'draftSeasonYear': 1,
        'overallPick': 1,
      };
      expect(decodeFailure(orphan).message, contains('was never drafted'));

      // Contract coordinates that disagree with the recorded selection.
      final mismatch = base();
      final mismatchContract =
          ((mismatch['rookieSigningLedger']
                      as Map<String, dynamic>)['contracts']
                  as Map<String, dynamic>)[signedId.value]
              as Map<String, dynamic>;
      mismatchContract['teamId'] = 'team-2';
      expect(
        decodeFailure(mismatch).message,
        contains('does not match its draft selection'),
      );

      // Roster category conflicting with the contract category.
      final categoryConflict = base();
      final memberships =
          categoryConflict['rosterMemberships'] as Map<String, dynamic>;
      final members = memberships[_team.value] as List<dynamic>;
      for (final entry in members) {
        final map = entry as Map<String, dynamic>;
        if (map['playerId'] == signedId.value) {
          map['category'] = 'twoWay';
        }
      }
      expect(
        decodeFailure(categoryConflict).message,
        contains('does not match contract'),
      );

      // Ledger key that does not match its contract player.
      final keyMismatch = base();
      final keyContracts =
          (keyMismatch['rookieSigningLedger']
                  as Map<String, dynamic>)['contracts']
              as Map<String, dynamic>;
      keyContracts['other-player'] =
          keyContracts.remove(signedId.value) as Map<String, dynamic>;
      expect(
        decodeFailure(keyMismatch).message,
        contains('ledger key does not match'),
      );

      // Missing career profile for the signed rookie.
      final missingProfile = base();
      final profiles =
          ((missingProfile['careerProfiles']
                      as Map<String, dynamic>)['profiles']
                  as Map<String, dynamic>)
              .remove(signedId.value);
      expect(profiles, isNotNull);
      expect(
        decodeFailure(missingProfile).message,
        contains('Missing career profile'),
      );
    });

    test('17. v1-v4 saves migrate with an empty ledger and intact data', () {
      final career = careers[FranchiseSituation.playIn]!;
      final completed =
          jsonDecode(GmCareerCodec.encode(career)) as Map<String, dynamic>;

      final v4 = Map<String, dynamic>.from(completed)
        ..['schemaVersion'] = 4
        ..remove('rookieSigningLedger');
      final migrated = GmCareerCodec.decode(jsonEncode(v4));
      expect(migrated.schemaVersion, 5);
      expect(migrated.rookieSigningLedger.isEmpty, isTrue);
      expect(migrated.draftExecutionState.isCompleted, isTrue);
      expect(migrated.draftExecutionState.selections.length, 60);
      expect(migrated.draftExecutionState.draftRights.length, 60);
      expect(migrated.unsignedDraftRights.length, 60);
      for (var i = 0; i < 30; i++) {
        expect(migrated.league.teams[i].players.length, 12);
        expect(migrated.league.teams[i].roster.standardCount, 12);
      }
      // Migrated v4 careers can sign without inventing prior signings.
      final rights = _userRights(migrated).first;
      expect(_sign(migrated, rights.prospectId).rookieSigningLedger.length, 1);

      final v3 = Map<String, dynamic>.from(completed)
        ..['schemaVersion'] = 3
        ..remove('rookieSigningLedger')
        ..remove('draftExecutionState');
      final migratedV3 = GmCareerCodec.decode(jsonEncode(v3));
      expect(migratedV3.rookieSigningLedger.isEmpty, isTrue);
      expect(migratedV3.draftExecutionState.isNotStarted, isTrue);
      expect(migratedV3.draftClass.length, 90);

      final v2 = Map<String, dynamic>.from(completed)
        ..['schemaVersion'] = 2
        ..remove('rookieSigningLedger')
        ..remove('draftExecutionState')
        ..remove('rosterMemberships');
      final migratedV2 = GmCareerCodec.decode(jsonEncode(v2));
      expect(migratedV2.rookieSigningLedger.isEmpty, isTrue);
      expect(migratedV2.draftClass.prospects.length, 90);

      final v1 = Map<String, dynamic>.from(v2)
        ..['schemaVersion'] = 1
        ..remove('draftOrder')
        ..remove('draftClass');
      final migratedV1 = GmCareerCodec.decode(jsonEncode(v1));
      expect(migratedV1.rookieSigningLedger.isEmpty, isTrue);
      expect(migratedV1.draftOrder.totalPicks, 60);
      expect(migratedV1.draftClass.length, 90);
      expect(migratedV1.userOpeningDraftPick, career.userOpeningDraftPick);
    });

    test('18. v5 writer always emits the signing ledger', () {
      final career = careers[FranchiseSituation.playIn]!;
      final older = career.copyWith(schemaVersion: 4);
      final encoded = jsonDecode(GmCareerCodec.encode(older));
      expect(encoded['schemaVersion'], 5);
      expect(encoded['rookieSigningLedger'], {
        'contracts': <String, dynamic>{},
      });
    });

    test('19. failed commands leave the input career untouched', () {
      final career = careers[FranchiseSituation.playIn]!;
      final before = GmCareerCodec.encode(career);
      final rights = _userRights(career).first;
      for (final command in [
        () => _service.signDraftedRookie(
          career: career,
          teamId: _team,
          prospectId: rights.prospectId,
          category: RosterCategory.standard,
          durationYears: 9,
        ),
        () => _service.signDraftedRookie(
          career: career,
          teamId: const TeamId('team-2'),
          prospectId: rights.prospectId,
          category: RosterCategory.standard,
          durationYears: 2,
        ),
      ]) {
        expect(command, throwsA(anything));
      }
      expect(GmCareerCodec.encode(career), before);
      expect(career.rookieSigningLedger.isEmpty, isTrue);
    });
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
  var career = GmCareer.fromSetupResult(setup, id: 't07a-${situation.name}');
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

List<DraftRights> _userRights(GmCareer career) =>
    career.draftExecutionState.draftRights.values
        .where((rights) => rights.owningTeamId == career.userFranchiseId)
        .toList()
      ..sort((a, b) => a.overallPick.compareTo(b.overallPick));

GmCareer _sign(GmCareer career, PlayerId prospectId) =>
    _service.signDraftedRookie(
      career: career,
      teamId: _team,
      prospectId: prospectId,
      category: RosterCategory.standard,
      durationYears: 3,
    );

GmCareer _expanded(
  GmCareer career, {
  int standard = 0,
  int twoWay = 0,
  int trainingCamp = 0,
}) {
  var roster = career.userTeam.roster;
  final added = <Player>[];
  for (var i = 0; i < standard; i++) {
    final player = _testPlayer('added-std-$i');
    added.add(player);
    roster = roster.withPlayer(player, category: RosterCategory.standard);
  }
  for (var i = 0; i < twoWay; i++) {
    final player = _testPlayer('added-tw-$i');
    added.add(player);
    roster = roster.withPlayer(player, category: RosterCategory.twoWay);
  }
  for (var i = 0; i < trainingCamp; i++) {
    final player = _testPlayer('added-tc-$i');
    added.add(player);
    roster = roster.withPlayer(player, category: RosterCategory.trainingCamp);
  }
  return career.withUpdatedTeam(
    career.userTeam.copyWith(roster: roster),
    careerProfiles: LeagueCareerProfiles(
      leagueSeed: career.careerProfiles.leagueSeed,
      profiles: {
        ...career.careerProfiles.profiles,
        for (final player in added)
          player.id.value: PlayerCareerProfile(
            playerId: player.id,
            age: 23,
            potential: 60,
            trajectory: DevelopmentTrajectory.steady,
          ),
      },
    ),
  );
}

Player _testPlayer(String id) => Player(
  id: PlayerId(id),
  firstName: 'Added',
  lastName: id,
  position: Position.sg,
  attributes: PlayerAttributes(
    insideScoring: 50,
    midrange: 50,
    threePoint: 50,
    freeThrow: 50,
    passing: 50,
    ballHandling: 50,
    perimeterDefense: 50,
    interiorDefense: 50,
    rebounding: 50,
    athleticism: 50,
    stamina: 50,
    basketballIQ: 50,
  ),
);
