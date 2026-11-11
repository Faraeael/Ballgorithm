import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

void main() {
  const service = DraftExecutionService();
  const strategy = AiDraftStrategy();
  const seed = 20261028;
  late List<GmCareer> careers;

  setUpAll(() {
    careers = [
      for (final situation in FranchiseSituation.values)
        GmCareer.fromSetupResult(
          const CareerSetupService().generate(
            CareerSetupRequest(
              selectedTeamId: TeamId('team-${situation.index + 1}'),
              selectedSituation: situation,
              seed: seed,
            ),
          ),
        ),
    ];
  });

  GmCareer finish(GmCareer career) {
    var current = service.startDraft(career);
    while (!current.draftExecutionState.isCompleted) {
      current = service.advanceUntilHumanOrComplete(current);
      if (current.draftExecutionState.isCompleted) break;
      expect(
        current.draftExecutionState.isHumanTurn(
          order: current.draftOrder,
          userTeamId: current.userFranchiseId,
        ),
        isTrue,
      );
      final count = current.draftExecutionState.completedSelectionsCount;
      current = service.makeHumanSelection(
        career: current,
        prospectId: current.draftExecutionState
            .availableProspects(current.draftClass)
            .first
            .id,
      );
      expect(current.draftExecutionState.completedSelectionsCount, count + 1);
    }
    return current;
  }

  PublicProspectScoutingView prospect(
    String id,
    Position position, {
    int rating = 60,
    int age = 22,
    String grade = 'B',
  }) => PublicProspectScoutingView(
    id: PlayerId(id),
    firstName: 'Public',
    lastName: id,
    position: position,
    age: age,
    attributes: careers.first.draftClass.rankedFirst.attributes,
    overallRating: rating,
    projectedRank: 20,
    estimatedPotentialGrade: grade,
    estimatedPotentialRange: '70–90',
  );

  PublicProspectScoutingView choose(
    List<PublicProspectScoutingView> pool,
    Team team,
    FranchiseSituation situation,
  ) => strategy.selectBestProspect(
    availableProspects: pool,
    team: team,
    situation: situation,
    overallPick: 20,
    seed: seed,
  );

  group('M008-T06A draft execution', () {
    test('start only starts; AI batches halt at each human boundary', () {
      const expectedPicks = [1, 12, 20, 30];
      for (var i = 0; i < careers.length; i++) {
        final initial = careers[i];
        final started = service.startDraft(initial);
        expect(started.draftExecutionState.completedSelectionsCount, 0);
        expect(started.draftExecutionState.currentOverallPick, 1);
        expect(initial.draftExecutionState.isNotStarted, isTrue);
        var current = service.advanceUntilHumanOrComplete(started);
        expect(
          current.draftExecutionState.currentOverallPick,
          expectedPicks[i],
        );
        final count = current.draftExecutionState.completedSelectionsCount;
        current = service.makeHumanSelection(
          career: current,
          prospectId: current.draftExecutionState
              .availableProspects(current.draftClass)
              .first
              .id,
        );
        expect(current.draftExecutionState.completedSelectionsCount, count + 1);
        current = service.advanceUntilHumanOrComplete(current);
        expect(
          current.draftExecutionState.currentOverallPick,
          expectedPicks[i] + 30,
        );
      }
    });

    for (final situation in FranchiseSituation.values) {
      test(
        '${situation.name}: complete 60 picks with explicit human commands',
        () {
          final initial = careers[situation.index];
          final completed = finish(initial);
          final state = completed.draftExecutionState;
          expect(state.completedSelectionsCount, 60);
          expect(state.currentOverallPick, isNull);
          expect(
            state.selections.map((s) => s.prospectId).toSet(),
            hasLength(60),
          );
          expect(state.undraftedProspects(completed.draftClass), hasLength(30));
          expect(state.draftRights, hasLength(60));
          for (var i = 0; i < 60; i++) {
            final selection = state.selections[i];
            final pick = completed.draftOrder.pickAt(i + 1);
            expect(selection.overallPick, i + 1);
            expect(selection.originalOwnerTeamId, pick.originalOwnerTeamId);
            expect(selection.selectingTeamId, pick.currentOwnerTeamId);
            final rights = state.draftRights[selection.prospectId.value]!;
            expect(rights.owningTeamId, selection.selectingTeamId);
            expect(rights.overallPick, selection.overallPick);
          }
          expect(
            jsonEncode(completed.league.teams.map((t) => t.toJson()).toList()),
            jsonEncode(initial.league.teams.map((t) => t.toJson()).toList()),
          );
          expect(
            () => service.makeHumanSelection(
              career: completed,
              prospectId: state
                  .undraftedProspects(completed.draftClass)
                  .first
                  .id,
            ),
            throwsA(isA<StateError>()),
          );
        },
      );
    }

    test('same inputs produce byte-identical nonempty AI histories', () {
      final a = finish(careers[1]);
      final b = finish(careers[1]);
      expect(a.draftExecutionState.completedSelectionsCount, 60);
      expect(GmCareerCodec.encode(a), GmCareerCodec.encode(b));
    });

    test('situations change actual selection, independent of pool order', () {
      final team = careers.first.league.teams.first.copyWith(
        roster: Roster([]),
      );
      final young = prospect(
        'young',
        Position.pg,
        rating: 51,
        age: 19,
        grade: 'A',
      );
      final ready = prospect('ready', Position.c, rating: 66);
      for (final pool in [
        [young, ready],
        [ready, young],
      ]) {
        expect(choose(pool, team, FranchiseSituation.tanking).id, young.id);
        expect(choose(pool, team, FranchiseSituation.contender).id, ready.id);
      }
    });

    test('roster needs change actual selection, independent of pool order', () {
      final original = careers.first.league.teams.first;
      Team crowded(Position position) => original.copyWith(
        roster: Roster([
          for (var i = 0; i < 4; i++)
            Player(
              id: PlayerId('veteran-$i'),
              firstName: 'Veteran',
              lastName: '$i',
              position: position,
              attributes: original.players.first.attributes,
            ),
        ]),
      );
      final guard = prospect('guard', Position.pg);
      final center = prospect('center', Position.c);
      for (final pool in [
        [guard, center],
        [center, guard],
      ]) {
        expect(
          choose(pool, crowded(Position.pg), FranchiseSituation.contender).id,
          center.id,
        );
        expect(
          choose(pool, crowded(Position.c), FranchiseSituation.contender).id,
          guard.id,
        );
      }
    });

    test(
      'hidden potential and trajectory changes cannot affect public decisions',
      () {
        final original = careers.first.draftClass.rankedFirst;
        final altered = RookieProspect.fromJson({
          ...original.toJson(),
          'potential': original.potential == 100 ? original.overallRating : 100,
          'trajectory': DevelopmentTrajectory.values
              .firstWhere((value) => value != original.trajectory)
              .jsonValue,
        });
        expect(altered.potential, isNot(original.potential));
        expect(altered.trajectory, isNot(original.trajectory));
        final team = careers.first.league.teams.first;
        final rival = prospect('rival', Position.c);
        for (final situation in FranchiseSituation.values) {
          double score(RookieProspect value) => strategy.scoreProspect(
            prospect: value.toPublicView(),
            team: team,
            situation: situation,
            overallPick: 20,
            seed: seed,
          );
          expect(score(altered), score(original));
          expect(
            choose([original.toPublicView(), rival], team, situation).id,
            choose([rival, altered.toPublicView()], team, situation).id,
          );
        }
      },
    );
    test('equal public scores use canonical identity rather than pool order', () {
      final team = careers.first.league.teams.first.copyWith(
        roster: Roster([]),
      );
      // These IDs collide under the stable seed mix, forcing an exact score tie.
      final a = prospect('Aa', Position.pg);
      final b = prospect('BB', Position.pg);
      expect(
        strategy.scoreProspect(
          prospect: a,
          team: team,
          situation: FranchiseSituation.playIn,
          overallPick: 20,
          seed: seed,
        ),
        strategy.scoreProspect(
          prospect: b,
          team: team,
          situation: FranchiseSituation.playIn,
          overallPick: 20,
          seed: seed,
        ),
      );
      expect(choose([a, b], team, FranchiseSituation.playIn).id, a.id);
      expect(choose([b, a], team, FranchiseSituation.playIn).id, a.id);
    });

    test('candidate noise varies, remains limited, and repeats exactly', () {
      final team = careers.first.league.teams.first.copyWith(
        roster: Roster([]),
      );
      final scores = [
        for (var i = 0; i < 12; i++)
          strategy.scoreProspect(
            prospect: prospect('candidate-$i', Position.pg),
            team: team,
            situation: FranchiseSituation.playIn,
            overallPick: 20,
            seed: seed,
          ),
      ];
      expect(scores.toSet().length, greaterThan(1));
      final sorted = [...scores]..sort();
      expect(sorted.last - sorted.first, lessThanOrEqualTo(6));
      for (var i = 0; i < scores.length; i++) {
        expect(
          strategy.scoreProspect(
            prospect: prospect('candidate-$i', Position.pg),
            team: team,
            situation: FranchiseSituation.playIn,
            overallPick: 20,
            seed: seed,
          ),
          scores[i],
        );
      }
    });

    test('invalid human commands preserve original immutable career', () {
      final started = service.advanceUntilHumanOrComplete(
        service.startDraft(careers[1]),
      );
      final before = GmCareerCodec.encode(started);
      expect(
        () => service.makeHumanSelection(
          career: started,
          prospectId: const PlayerId('fake-id'),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => service.makeHumanSelection(
          career: started,
          prospectId: started.draftExecutionState.selections.first.prospectId,
        ),
        throwsA(isA<StateError>()),
      );
      expect(GmCareerCodec.encode(started), before);
      expect(
        () => service.makeHumanSelection(
          career: careers[1],
          prospectId: careers[1].draftClass.rankedFirst.id,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'mid-draft reload preserves full save and produces identical continuation',
      () {
        final mid = service.advanceUntilHumanOrComplete(
          service.startDraft(careers[1]),
        );
        final encoded = GmCareerCodec.encode(mid);
        final reloaded = GmCareerCodec.decode(encoded);
        expect(GmCareerCodec.encode(reloaded), encoded);
        expect(reloaded.draftExecutionState.completedSelectionsCount, 11);
        expect(reloaded.draftExecutionState.currentOverallPick, 12);
        GmCareer resume(GmCareer career) {
          final next = service.makeHumanSelection(
            career: career,
            prospectId: career.draftExecutionState
                .availableProspects(career.draftClass)
                .first
                .id,
          );
          expect(next.draftExecutionState.completedSelectionsCount, 12);
          return service.advanceUntilHumanOrComplete(next);
        }

        final resumed = resume(reloaded);
        expect(resumed.draftExecutionState.currentOverallPick, 42);
        expect(
          GmCareerCodec.encode(resumed),
          GmCareerCodec.encode(resume(mid)),
        );
      },
    );

    test('legacy migrations preserve every pre-existing save field', () {
      final current =
          jsonDecode(GmCareerCodec.encode(careers.first))
              as Map<String, dynamic>;
      for (final version in [1, 2, 3]) {
        final legacy = Map<String, dynamic>.from(current)
          ..['schemaVersion'] = version
          ..remove('draftExecutionState');
        if (version == 1) {
          legacy.remove('draftOrder');
          legacy.remove('draftClass');
        }
        if (version < 3) legacy.remove('rosterMemberships');
        final migrated = GmCareerCodec.decode(jsonEncode(legacy));
        expect(migrated.schemaVersion, GmCareer.currentSchemaVersion);
        expect(migrated.draftExecutionState.isNotStarted, isTrue);
        final saved =
            jsonDecode(GmCareerCodec.encode(migrated)) as Map<String, dynamic>;
        for (final entry in legacy.entries) {
          if (entry.key == 'schemaVersion') continue;
          expect(
            saved[entry.key],
            entry.value,
            reason: 'v$version field ${entry.key}',
          );
        }
      }
    });
  });
}
