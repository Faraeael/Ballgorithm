import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import '../support/career_season_fixtures.dart';

const _market = StaffMarketService();
const _adapter = RegularSeasonGameAdapter();
final _rules = GameRules.standard;

Team _standard(GmCareer c, TeamId id) =>
    RegularSeasonGameAdapter.standardTeamFor(
      c.league.teams.firstWhere((t) => t.id == id),
    );

GmCareer _withPhilosophy(GmCareer c, TeamId team, CoachPhilosophy p) {
  final m = c.staff.employedHeadCoach(team)!;
  return c.copyWith(
    staff: c.staff.withMember(
      StaffMember(
        id: m.id,
        firstName: m.firstName,
        lastName: m.lastName,
        age: m.age,
        role: m.role,
        tier: m.tier,
        experienceYears: m.experienceYears,
        status: m.status,
        philosophy: p,
        teamId: m.teamId,
        commitmentId: m.commitmentId,
      ),
    ),
  );
}

Map<String, dynamic> _template(RegularSeasonGameResult r) =>
    jsonDecode(r.inputEvidence!.payloadTemplateJson) as Map<String, dynamic>;

List<String> _lineup(Map<String, dynamic> template, String side) => [
  for (final s in template['${side}Lineup'] as List)
    (s as Map)['playerId'] as String,
];

Object? _canon(Object? json) => jsonDecode(jsonEncode(json));

/// Asserts a stored game used [decisionFor] for both sides.
void _expectDecisionUsed(GmCareer c, RegularSeasonGameResult r) {
  final template = _template(r);
  for (final (side, id) in [('home', r.homeTeamId), ('away', r.awayTeamId)]) {
    final decision = CareerRotationService.decisionFor(c, _standard(c, id));
    expect(_lineup(template, side), decision.lineup.playerIds, reason: side);
    expect(
      (template['rotationPlan'] as Map)[side],
      _canon(decision.plan.toJson()),
      reason: side,
    );
  }
}

void main() {
  late GmCareer cleared;
  late GmCareer scheduled;
  late GmCareer enabled;

  setUpAll(() {
    cleared = clearOffseason(preFreeAgencyOffseason());
    scheduled = scheduledSeason(cleared);
    enabled = _market.enableCoaching(scheduled);
  });

  group('M011-T03 coach rotation policy', () {
    test(
      'every philosophy yields a valid, deterministic plan for all teams',
      () {
        for (final source in enabled.league.teams) {
          final team = RegularSeasonGameAdapter.standardTeamFor(source);
          for (final p in CoachPhilosophy.values) {
            final a = CoachRotationPolicy.planFor(p, team)!;
            final b = CoachRotationPolicy.planFor(p, team)!;
            expect(a.lineup.playerIds, b.lineup.playerIds);
            expect(_canon(a.plan.toJson()), _canon(b.plan.toJson()));
            expect(a.lineup.playerIds.toSet(), hasLength(5));
            final ids = {for (final pl in team.players) pl.id.value};
            expect(ids.containsAll(a.lineup.playerIds), isTrue);
            final seconds = a.plan.targetSeconds.values;
            expect(seconds.fold(0, (x, y) => x + y), 14400);
            expect(seconds.every((s) => s >= 0 && s <= 2880), isTrue);
            for (final id in a.lineup.playerIds) {
              expect(a.plan.secondsFor(PlayerId(id)), greaterThan(0));
            }
            GameInput.validateLineupAndPlan(
              team: team,
              lineup: a.lineup,
              plan: a.plan,
              rules: _rules,
            );
          }
        }
      },
    );

    test('presets and the deep-rotation allocation are exact', () {
      final team = _standard(enabled, enabled.userFranchiseId);
      expect(team.players.length, greaterThanOrEqualTo(10));
      final balanced = CoachRotationPolicy.planFor(
        CoachPhilosophy.balanced,
        team,
      )!;
      final star = CoachRotationPolicy.planFor(
        CoachPhilosophy.starFocused,
        team,
      )!;
      final deep = CoachRotationPolicy.planFor(
        CoachPhilosophy.deepRotation,
        team,
      )!;
      expect(balanced.plan.preset, RotationPreset.balanced);
      expect(star.plan.preset, RotationPreset.starterHeavy);
      expect(deep.plan.preset, RotationPreset.custom);
      // Same OVR starters; minutes differ.
      expect(star.lineup.playerIds, balanced.lineup.playerIds);
      expect(deep.lineup.playerIds, balanced.lineup.playerIds);
      int playing(TeamRotationPlan p) =>
          p.targetSeconds.values.where((s) => s > 0).length;
      expect(playing(balanced.plan), 9);
      expect(playing(star.plan), 8);
      expect(playing(deep.plan), 10);

      final starters = {for (final id in deep.lineup.playerIds) PlayerId(id)};
      final reserves = [
        for (final e in deep.plan.targetSeconds.entries)
          if (e.value > 0 && !starters.contains(e.key)) e.key,
      ];
      for (final id in starters) {
        expect(deep.plan.secondsFor(id), 1728);
      }
      expect(reserves, hasLength(5));
      for (final id in reserves) {
        expect(deep.plan.secondsFor(id), 1152);
      }
      // Reserves are the five best remaining players by OVR.
      final rest = [
        for (final p in team.players)
          if (!starters.contains(p.id)) p,
      ];
      final minReserveOvr = [
        for (final p in rest)
          if (reserves.contains(p.id)) p.attributes.overallRating,
      ].reduce((a, b) => a < b ? a : b);
      for (final p in rest) {
        if (!reserves.contains(p.id)) {
          expect(p.attributes.overallRating, lessThanOrEqualTo(minReserveOvr));
        }
      }
    });

    test(
      'starters are the best eligible player per position by philosophy',
      () {
        for (final source in enabled.league.teams) {
          final team = RegularSeasonGameAdapter.standardTeamFor(source);
          for (final p in [
            CoachPhilosophy.balanced,
            CoachPhilosophy.defensiveMinded,
          ]) {
            final starters = CoachRotationPolicy.selectStarters(p, team);
            final chosen = {for (final s in starters) s.id};
            for (var i = 0; i < 5; i++) {
              final slot = Position.values[i];
              final s = starters[i];
              if (s.position != slot) {
                // Out of position only when no same-position player is left.
                expect(
                  team.players.where(
                    (x) => x.position == slot && !chosen.contains(x.id),
                  ),
                  isEmpty,
                );
                continue;
              }
              for (final other in team.players) {
                if (other.position == slot && !chosen.contains(other.id)) {
                  expect(
                    CoachRotationPolicy.starterScore(p, other),
                    lessThanOrEqualTo(CoachRotationPolicy.starterScore(p, s)),
                  );
                }
              }
            }
          }
        }
      },
    );

    test('philosophies produce observably different plans', () {
      var defensiveDiffers = 0;
      var anyDiffersFromM010 = 0;
      for (final source in enabled.league.teams) {
        final team = RegularSeasonGameAdapter.standardTeamFor(source);
        final bal = CoachRotationPolicy.planFor(
          CoachPhilosophy.balanced,
          team,
        )!;
        final def = CoachRotationPolicy.planFor(
          CoachPhilosophy.defensiveMinded,
          team,
        )!;
        if (bal.lineup.playerIds.join() != def.lineup.playerIds.join()) {
          defensiveDiffers++;
        }
        final auto = CareerRotationService.automaticFor(team);
        if (bal.lineup.playerIds.join() != auto.lineup.playerIds.join()) {
          anyDiffersFromM010++;
        }
      }
      expect(defensiveDiffers, greaterThan(0));
      expect(anyDiffersFromM010, greaterThan(0));
    });

    test(
      'deep rotation with fewer than ten players falls back to balanced',
      () {
        final full = _standard(enabled, enabled.userFranchiseId);
        final nine = full.copyWith(
          roster: Roster(full.players.take(9).toList()),
        );
        final deep = CoachRotationPolicy.planFor(
          CoachPhilosophy.deepRotation,
          nine,
        )!;
        final bal = CoachRotationPolicy.planFor(
          CoachPhilosophy.balanced,
          nine,
        )!;
        expect(deep.plan.preset, RotationPreset.balanced);
        expect(_canon(deep.plan.toJson()), _canon(bal.plan.toJson()));
      },
    );
  });

  group('M011-T03 authoritative decision and game inputs', () {
    test('coaching disabled: every side is the M010 automatic rotation', () {
      for (final f
          in scheduled.regularSeasonState!.schedule!.rounds.first.fixtures) {
        final input = _adapter.createInput(scheduled, f);
        for (final id in [f.homeTeamId, f.awayTeamId]) {
          final d = CareerRotationService.decisionFor(
            scheduled,
            _standard(scheduled, id),
          );
          expect(d.authority, RotationAuthority.automatic);
          final auto = CareerRotationService.automaticFor(
            _standard(scheduled, id),
          );
          expect(d.lineup.playerIds, auto.lineup.playerIds);
        }
        // While disabled, coach philosophies are inert.
        var changed = scheduled;
        for (final id in [f.homeTeamId, f.awayTeamId]) {
          changed = _withPhilosophy(changed, id, CoachPhilosophy.deepRotation);
        }
        expect(
          GameFingerprint.of(_adapter.createInput(changed, f)),
          GameFingerprint.of(input),
        );
      }
    });

    test('enabled: human AUTO and both AI sides use their own coaches', () {
      final user = enabled.userFranchiseId;
      final f = enabled.regularSeasonState!.schedule!.allFixtures.firstWhere(
        (f) => f.homeTeamId == user || f.awayTeamId == user,
      );
      final aiFixture = enabled.regularSeasonState!.schedule!.allFixtures
          .firstWhere((f) => f.homeTeamId != user && f.awayTeamId != user);
      for (final fixture in [f, aiFixture]) {
        final input = _adapter.createInput(enabled, fixture);
        for (final (id, lineup) in [
          (fixture.homeTeamId, input.homeLineup),
          (fixture.awayTeamId, input.awayLineup),
        ]) {
          final team = _standard(enabled, id);
          final coach = enabled.staff.employedHeadCoach(id)!;
          final d = CareerRotationService.decisionFor(enabled, team);
          expect(d.authority, RotationAuthority.headCoach);
          expect(d.coach, coach);
          expect(
            lineup.playerIds,
            CoachRotationPolicy.planFor(
              coach.philosophy!,
              team,
            )!.lineup.playerIds,
          );
        }
      }
    });

    test('human MANUAL takes precedence over the coach', () {
      final user = enabled.userFranchiseId;
      final team = _standard(enabled, user);
      final manual = CareerRotationSettings.manual(
        starters: [
          for (final id in CourtLineup.defaultFor(team).playerIds.reversed)
            PlayerId(id),
        ],
        preset: RotationPreset.starterHeavy,
      );
      final c = enabled.copyWith(userRotation: manual);
      final d = CareerRotationService.decisionFor(c, team);
      expect(d.authority, RotationAuthority.manual);
      expect(d.lineup.playerIds, [for (final id in manual.starters) id.value]);
      // AUTO preview still reports what the coach would do.
      expect(
        CareerRotationService.autoDecisionFor(c, team).authority,
        RotationAuthority.headCoach,
      );
    });

    test('dismissed coaches never decide; vacancy uses the automatic plan', () {
      var c = _market.enableCoaching(cleared);
      final user = c.userFranchiseId;
      final ai = c.league.teams.firstWhere((t) => t.id != user).id;
      final dismissed = c.staff.employedHeadCoach(ai)!;
      c = _market.dismissHeadCoach(c, teamId: ai);
      c = scheduledSeason(c);
      final team = _standard(c, ai);
      final d = CareerRotationService.decisionFor(c, team);
      expect(d.authority, RotationAuthority.vacantFallback);
      expect(d.coach, isNull);
      expect(
        c.staff.members[dismissed.id]!.status,
        StaffEmploymentStatus.dismissed,
      );
      expect(
        d.lineup.playerIds,
        CareerRotationService.automaticFor(team).lineup.playerIds,
      );
      // The vacant side of a real fixture gets the automatic plan.
      final f = c.regularSeasonState!.schedule!.allFixtures.firstWhere(
        (f) => f.homeTeamId == ai || f.awayTeamId == ai,
      );
      final input = _adapter.createInput(c, f);
      final lineup = f.homeTeamId == ai ? input.homeLineup : input.awayLineup;
      expect(lineup.playerIds, d.lineup.playerIds);
    });

    test('coach philosophy changes participation in a controlled game', () {
      final user = enabled.userFranchiseId;
      final f = enabled.regularSeasonState!.schedule!.allFixtures.firstWhere(
        (f) => f.homeTeamId == user || f.awayTeamId == user,
      );
      Map<CoachPhilosophy, List<int>> played = {};
      for (final p in [
        CoachPhilosophy.starFocused,
        CoachPhilosophy.balanced,
        CoachPhilosophy.deepRotation,
      ]) {
        final c = _withPhilosophy(enabled, user, p);
        final counts = <int>[];
        for (final seed in [11, 22, 33]) {
          final input = _adapter.createGameInput(
            c,
            gameId: 'm011-participation-$seed',
            homeTeamId: f.homeTeamId,
            awayTeamId: f.awayTeamId,
            seed: seed,
          );
          final result = GameSimulator().simulate(input);
          counts.add(
            result.boxScore.players.values
                .where((b) => b.teamId == user.value && b.secondsPlayed > 0)
                .length,
          );
        }
        played[p] = counts;
      }
      // Seeded, same opponent and seed set; only the coach changed.
      for (var i = 0; i < 3; i++) {
        expect(
          played[CoachPhilosophy.deepRotation]![i],
          greaterThan(played[CoachPhilosophy.starFocused]![i]),
          reason: '$played',
        );
      }
      // ignore: avoid_print
      print(
        'M011 participation (players with minutes, seeds 11/22/33): $played',
      );
    });
  });

  group('M011-T03 history and postseason', () {
    test(
      'regular season, Play-In and playoffs use coaches; earlier games stay fixed',
      () {
        // Round 1 with coaching off, then activation, then round 2.
        const rounds = RegularSeasonRoundService();
        var c = rounds.simulateNextRound(scheduled, expectedRoundNumber: 1);
        final round1 = {
          for (final e in c.regularSeasonState!.gameResults.entries)
            e.key: jsonEncode(e.value.toJson()),
        };
        c = _market.enableCoaching(c);
        c = rounds.simulateNextRound(c, expectedRoundNumber: 2);
        for (final e in round1.entries) {
          expect(
            jsonEncode(c.regularSeasonState!.gameResults[e.key]!.toJson()),
            e.value,
            reason: 'completed game ${e.key} must not change',
          );
        }
        final round2 = c.regularSeasonState!.gameResults.values.where(
          (r) => !round1.containsKey(r.fixtureId),
        );
        expect(round2, isNotEmpty);
        for (final r in round2) {
          _expectDecisionUsed(c, r);
        }

        // Postseason (fabricated regular season, real Play-In and playoffs).
        final done = completeSeason(enabled);
        for (final r in done.playInState!.gameResults.values) {
          _expectDecisionUsed(done, r);
        }
        expect(done.playoffState!.gameResults, isNotEmpty);
        for (final r in done.playoffState!.gameResults.values.take(8)) {
          _expectDecisionUsed(done, r);
        }
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  });
}
