import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import '../support/career_season_fixtures.dart';

const _market = StaffMarketService();

Map<String, dynamic> _json(GmCareer c) =>
    jsonDecode(GmCareerCodec.encode(c)) as Map<String, dynamic>;

int _staffCostFor(GmCareer c, TeamId team) => [
  for (final s in c.finances.staffCommitments.values)
    if (s.teamId == team) s.annualCost,
].fold(0, (a, b) => a + b);

GmCareer _withOperatingBudget(GmCareer c, TeamId team, int budget) {
  final finances = c.finances;
  return c.copyWith(
    finances: CareerFinances(
      contracts: finances.contracts.values,
      schedules: finances.schedules.values,
      teamFinances: [
        for (final tf in finances.teamFinances.values)
          tf.teamId == team
              ? TeamFinances(
                  teamId: tf.teamId,
                  operatingBudget: budget,
                  cash: tf.cash,
                  revenueBaseline: tf.revenueBaseline,
                  season: tf.season,
                  capGrandfathered: tf.capGrandfathered,
                  grandfatheredPayroll: tf.grandfatheredPayroll,
                  capException: tf.capException,
                )
              : tf,
      ],
      staffCommitments: finances.staffCommitments.values,
      facilities: finances.facilities.values,
      guaranteedLiabilities: finances.guaranteedLiabilities.values,
      debtByTeam: finances.debtByTeam,
    ),
  );
}

void main() {
  late GmCareer preFa;
  late GmCareer cleared;

  setUpAll(() {
    preFa = preFreeAgencyOffseason();
    cleared = clearOffseason(preFa);
  });

  group('M011-T02 named staff and migration', () {
    test('incumbents name every commitment deterministically at no cost', () {
      final staff = preFa.staff;
      expect(staff.coachingEnabled, isFalse);
      expect(preFa.finances.staffCommitments, hasLength(180));
      expect(staff.members, hasLength(180));
      for (final commitment in preFa.finances.staffCommitments.values) {
        final member = staff.memberForCommitment(commitment.id)!;
        expect(member.id, 'person-${commitment.id}');
        expect(member.isEmployed, isTrue);
        expect(member.teamId, commitment.teamId);
        expect(member.role, commitment.category);
        expect(member.tier, commitment.tier);
        expect(
          member.philosophy != null,
          commitment.category == StaffCategory.headCoach,
        );
      }
      for (final team in preFa.league.teams) {
        expect(_staffCostFor(preFa, team.id), FinancialRules.initialStaffCost);
        expect(staff.employedHeadCoach(team.id), isNotNull);
      }
      final again = StaffState.incumbentsFor(
        finances: preFa.finances,
        generationSeed: preFa.generationSeed,
      );
      expect(again.toJson(), staff.toJson(), reason: 'deterministic');
    });

    test('v26 saves migrate to v27 with identical money and no hires', () {
      final current = _json(cleared);
      final v26 = Map<String, dynamic>.of(current)
        ..['schemaVersion'] = 26
        ..remove('staff');
      final migrated = GmCareerCodec.decode(jsonEncode(v26));
      expect(migrated.schemaVersion, 27);
      expect(migrated.staff.coachingEnabled, isFalse);
      expect(
        jsonEncode(migrated.finances.toJson()),
        jsonEncode(cleared.finances.toJson()),
      );
      expect(GmCareerCodec.encode(migrated), GmCareerCodec.encode(cleared));

      // Misplaced or missing keys are rejected.
      final v26WithStaff = Map<String, dynamic>.of(current)
        ..['schemaVersion'] = 26;
      expect(
        () => GmCareerCodec.decode(jsonEncode(v26WithStaff)),
        throwsFormatException,
      );
      final v27Missing = Map<String, dynamic>.of(current)..remove('staff');
      expect(
        () => GmCareerCodec.decode(jsonEncode(v27Missing)),
        throwsFormatException,
      );
    });

    test('corrupt employment or contract links fail validation', () {
      final current = _json(cleared);
      List<dynamic> members() =>
          ((jsonDecode(jsonEncode(current)) as Map)['staff'] as Map)['members']
              as List;
      String withMembers(List<dynamic> m) => jsonEncode({
        ...current,
        'staff': {'coachingEnabled': false, 'members': m},
      });

      final duplicate = members()..add(members().first);
      final missingLink = members()..removeAt(0);
      final badCommitment = members();
      (badCommitment.first as Map)['commitmentId'] = 'staff-ghost';
      final secondCoach = members();
      final coach =
          (secondCoach.firstWhere((m) => (m as Map)['role'] == 'headCoach')
              as Map);
      final assistant =
          (secondCoach.firstWhere(
                (m) =>
                    (m as Map)['role'] == 'assistant' &&
                    m['teamId'] == coach['teamId'],
              )
              as Map);
      assistant['role'] = 'headCoach';
      assistant['philosophy'] = 'balanced';
      final available = members();
      (available.first as Map)['status'] = 'available';
      for (final bad in [
        duplicate,
        missingLink,
        badCommitment,
        secondCoach,
        available,
      ]) {
        expect(
          () => GmCareerCodec.decode(withMembers(bad)),
          throwsFormatException,
        );
      }
      expect(
        () => StaffMember.fromJson({'id': 'x', 'unknown': 1}),
        throwsFormatException,
      );
    });

    test('retained manual plan round-trips and never drives inputs', () {
      final team = RegularSeasonGameAdapter.standardTeamFor(cleared.userTeam);
      final lineup = CourtLineup.defaultFor(team);
      final manual = CareerRotationSettings.manual(
        starters: [for (final id in lineup.playerIds.reversed) PlayerId(id)],
        preset: RotationPreset.starterHeavy,
      );
      final retaining = CareerRotationSettings.autoRetaining(manual);
      final withRetained = cleared.copyWith(userRotation: retaining);
      final decoded = GmCareerCodec.decode(GmCareerCodec.encode(withRetained));
      expect(decoded.userRotation, retaining);
      expect(decoded.userRotation.retainedManual, manual);
      expect(decoded.userRotation.isManual, isFalse);

      final scheduled = scheduledSeason(withRetained);
      final plain = scheduled.copyWith(
        userRotation: CareerRotationSettings.auto,
      );
      const adapter = RegularSeasonGameAdapter();
      final f = scheduled.regularSeasonState!.schedule!.allFixtures.firstWhere(
        (f) =>
            f.homeTeamId == scheduled.userFranchiseId ||
            f.awayTeamId == scheduled.userFranchiseId,
      );
      expect(
        GameFingerprint.of(adapter.createInput(scheduled, f)),
        GameFingerprint.of(adapter.createInput(plain, f)),
      );
    });
  });

  group('M011-T02 market and transactions', () {
    test('coaching is off by default; activation is explicit and one-way', () {
      expect(
        () => _market.hireHeadCoach(
          cleared,
          teamId: cleared.userFranchiseId,
          candidateId: _market.headCoachCandidates(cleared).first.id,
          durationYears: 2,
        ),
        throwsA(
          isA<StaffTransactionRejected>().having(
            (e) => e.code,
            'code',
            StaffRejectionCode.coachingDisabled,
          ),
        ),
      );
      final enabled = _market.enableCoaching(cleared);
      expect(enabled.staff.coachingEnabled, isTrue);
      expect(
        jsonEncode(enabled.finances.toJson()),
        jsonEncode(cleared.finances.toJson()),
        reason: 'activation hires nobody and moves no money',
      );
      expect(
        () => _market.enableCoaching(enabled),
        throwsA(isA<StaffTransactionRejected>()),
      );
    });

    test('candidates are deterministic, unique, standard tier at 2,500', () {
      final a = _market.headCoachCandidates(cleared);
      final b = _market.headCoachCandidates(cleared);
      expect(a.map((c) => c.toJson()), b.map((c) => c.toJson()));
      expect(a, hasLength(StaffMarketService.headCoachCandidatesPerOffseason));
      expect(a.map((c) => c.id).toSet(), hasLength(a.length));
      for (final c in a) {
        expect(c.role, StaffCategory.headCoach);
        expect(c.tier, StaffTier.standard);
        expect(c.isAvailable, isTrue);
        expect(c.philosophy, isNotNull);
        expect(cleared.staff.members.containsKey(c.id), isFalse);
      }
      expect(StaffMarketService.headCoachAnnualSalary, 2500);
    });

    test(
      'replace: dismissed salary stays payable, cap untouched, budget enforced',
      () {
        var c = _market.enableCoaching(cleared);
        final team = c.userFranchiseId;
        final incumbent = c.staff.employedHeadCoach(team)!;
        final capBefore = c.finances.capPayrollFor(team, c.currentYear);
        final operatingBefore = c.finances.operatingCommitmentsFor(team);
        final projectedBefore = c.finances.projectedEndOfSeasonCash(
          team,
          c.currentYear,
        );
        final candidate = _market.headCoachCandidates(c).first;

        expect(
          () => _market.hireHeadCoach(
            c,
            teamId: team,
            candidateId: candidate.id,
            durationYears: 2,
          ),
          throwsA(
            isA<StaffTransactionRejected>().having(
              (e) => e.code,
              'code',
              StaffRejectionCode.teamHasHeadCoach,
            ),
          ),
        );
        c = _market.replaceHeadCoach(
          c,
          teamId: team,
          candidateId: candidate.id,
          durationYears: 3,
        );
        final dismissed = c.staff.members[incumbent.id]!;
        expect(dismissed.status, StaffEmploymentStatus.dismissed);
        expect(
          c.finances.staffCommitments.containsKey(dismissed.commitmentId),
          isTrue,
          reason: 'dismissal does not cancel the obligation',
        );
        final hired = c.staff.employedHeadCoach(team)!;
        expect(hired.id, candidate.id);
        final commitment = c.finances.staffCommitments[hired.commitmentId]!;
        expect(commitment.annualCost, 2500);
        expect(commitment.startYear, c.currentYear);
        expect(commitment.durationYears, 3);
        expect(
          c.finances.operatingCommitmentsFor(team),
          operatingBefore + 2500,
        );
        expect(
          c.finances.projectedEndOfSeasonCash(team, c.currentYear),
          projectedBefore - 2500,
        );
        expect(
          c.finances.capPayrollFor(team, c.currentYear),
          capBefore,
          reason: 'staff are operating expenses, never cap salary',
        );
        // Round trip keeps everything.
        expect(
          GmCareerCodec.encode(GmCareerCodec.decode(GmCareerCodec.encode(c))),
          GmCareerCodec.encode(c),
        );

        // A hired candidate cannot be hired again by another team.
        final other = c.league.teams.firstWhere((t) => t.id != team).id;
        expect(
          () => _market.replaceHeadCoach(
            c,
            teamId: other,
            candidateId: candidate.id,
            durationYears: 1,
          ),
          throwsA(
            isA<StaffTransactionRejected>().having(
              (e) => e.code,
              'code',
              StaffRejectionCode.candidateUnavailable,
            ),
          ),
        );

        // Repeated replacement cannot escape the operating budget.
        final budget = c.finances.financesFor(team).operatingBudget;
        var rejected = false;
        for (var i = 0; i < 10 && !rejected; i++) {
          final next = _market.headCoachCandidates(c).first;
          try {
            c = _market.replaceHeadCoach(
              c,
              teamId: team,
              candidateId: next.id,
              durationYears: 1,
            );
          } on StaffTransactionRejected catch (e) {
            expect(e.code, StaffRejectionCode.overOperatingBudget);
            rejected = true;
          }
          expect(
            c.finances.operatingCommitmentsFor(team),
            lessThanOrEqualTo(budget),
          );
        }
        expect(rejected, isTrue);
      },
    );

    test('renewal extends in place and respects the 5-year maximum', () {
      var c = _market.enableCoaching(cleared);
      final team = c.userFranchiseId;
      final coach = c.staff.employedHeadCoach(team)!;
      final before = c.finances.staffCommitments[coach.commitmentId]!;
      c = _market.renewHeadCoach(c, teamId: team, additionalYears: 4);
      final after = c.finances.staffCommitments[coach.commitmentId]!;
      expect(after.id, before.id);
      expect(after.startYear, before.startYear);
      expect(after.annualCost, before.annualCost);
      expect(after.durationYears, before.durationYears + 4);
      expect(
        () => _market.renewHeadCoach(c, teamId: team, additionalYears: 1),
        throwsA(
          isA<StaffTransactionRejected>().having(
            (e) => e.code,
            'code',
            StaffRejectionCode.renewalExceedsMaximum,
          ),
        ),
      );
    });

    test('staff changes are offseason-only', () {
      final scheduled = scheduledSeason(_market.enableCoaching(cleared));
      expect(
        () => _market.dismissHeadCoach(
          scheduled,
          teamId: scheduled.userFranchiseId,
        ),
        throwsA(
          isA<StaffTransactionRejected>().having(
            (e) => e.code,
            'code',
            StaffRejectionCode.wrongPhase,
          ),
        ),
      );
    });
  });

  group('M011-T02 AI head-coach recruitment', () {
    test('disabled coaching leaves free agency opening unchanged', () {
      const fa = FreeAgentMarketService();
      final opened = fa.startRound(preFa);
      expect(opened.staff.toJson(), preFa.staff.toJson());
      expect(
        jsonEncode(opened.finances.toJson()),
        jsonEncode(preFa.finances.toJson()),
      );
      expect(identical(_market.aiRecruitHeadCoaches(preFa), preFa), isTrue);
    });

    test(
      'enabled: deterministic, affordable, idempotent; unaffordable stays vacant',
      () {
        var c = _market.enableCoaching(preFa);
        final aiTeams = [
          for (final t in c.league.teams)
            if (t.id != c.userFranchiseId) t.id,
        ]..sort((a, b) => a.value.compareTo(b.value));
        final vacated = aiTeams.take(3).toList();
        for (final team in vacated) {
          c = _market.dismissHeadCoach(c, teamId: team);
        }
        // Third vacated team cannot afford another 2,500.
        final poor = vacated[2];
        c = _withOperatingBudget(
          c,
          poor,
          c.finances.operatingCommitmentsFor(poor) + 2499,
        );

        const fa = FreeAgentMarketService();
        final opened = fa.startRound(c);
        final again = fa.startRound(c);
        expect(GmCareerCodec.encode(opened), GmCareerCodec.encode(again));
        for (final team in vacated.take(2)) {
          final coach = opened.staff.employedHeadCoach(team)!;
          final commitment =
              opened.finances.staffCommitments[coach.commitmentId]!;
          expect(commitment.durationYears, StaffMarketService.aiContractYears);
          expect(
            opened.finances.operatingCommitmentsFor(team),
            lessThanOrEqualTo(
              opened.finances.financesFor(team).operatingBudget,
            ),
          );
        }
        expect(opened.staff.employedHeadCoach(poor), isNull);
        expect(
          GmCareerCodec.encode(_market.aiRecruitHeadCoaches(opened)),
          GmCareerCodec.encode(opened),
          reason: 'idempotent: no duplicate appointments',
        );
        expect(
          opened.staff.employedHeadCoach(opened.userFranchiseId),
          isNotNull,
        );
      },
    );

    test('a head-coach vacancy does not block season entry', () {
      var c = _market.enableCoaching(cleared);
      c = _market.dismissHeadCoach(c, teamId: c.userFranchiseId);
      final entered = const RegularSeasonEntryService().start(c);
      expect(entered.phase, CareerPhase.regularSeason);
      expect(entered.staff.employedHeadCoach(c.userFranchiseId), isNull);
    });
  });

  group('M011-T02 rollover', () {
    test(
      'contracts carry, expiries end employment, dismissed stay payable, D1 kept',
      () {
        // Disabled baseline: incumbents expire after Year 1 (D1).
        final baseline = completeSeason(scheduledSeason(cleared));
        final y2 = const SeasonRolloverService()
            .prepareArchiveAndRollover(current: baseline)
            .rolloverResult
            .nextCareer;
        expect(y2.finances.staffCommitments, isEmpty);
        expect(y2.staff.members, hasLength(180));
        expect(y2.staff.members.values.every((m) => m.isAvailable), isTrue);
        final settlement = y2.seasonSettlements.single;
        for (final entry in settlement.teamEntries) {
          expect(entry.staffExpense, FinancialRules.initialStaffCost);
        }

        // Enabled: a 3-year hire continues; the dismissed 1-year incumbent is
        // charged once in Year 1 and then expires.
        var c = _market.enableCoaching(cleared);
        final team = c.userFranchiseId;
        final incumbent = c.staff.employedHeadCoach(team)!;
        final candidate = _market.headCoachCandidates(c).first;
        c = _market.replaceHeadCoach(
          c,
          teamId: team,
          candidateId: candidate.id,
          durationYears: 3,
        );
        final completed = completeSeason(scheduledSeason(c));
        final next = const SeasonRolloverService()
            .prepareArchiveAndRollover(current: completed)
            .rolloverResult
            .nextCareer;
        final teamEntry = next.seasonSettlements.single.teamEntries.firstWhere(
          (e) => e.teamId == team,
        );
        expect(
          teamEntry.staffExpense,
          FinancialRules.initialStaffCost + 2500,
          reason: 'both salaries paid in Year 1, each exactly once',
        );
        final coach = next.staff.employedHeadCoach(team)!;
        expect(coach.id, candidate.id);
        expect(next.finances.staffCommitments.keys, [coach.commitmentId]);
        expect(next.staff.members[incumbent.id]!.isAvailable, isTrue);
        expect(next.finances.operatingCommitmentsFor(team), greaterThan(0));
        expect(next.staff.coachingEnabled, isTrue);
        final ids = next.staff.members.keys.toList();
        expect(ids.toSet(), hasLength(ids.length));
        // Year 2 AI teams are vacant and may recruit when free agency opens.
        final aiTeam = next.league.teams.firstWhere((t) => t.id != team).id;
        expect(next.staff.employedHeadCoach(aiTeam), isNull);
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  });
}
