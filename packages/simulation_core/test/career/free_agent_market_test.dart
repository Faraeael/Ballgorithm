import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import '../support/financial_fixtures.dart';

const _seed = 20261028;
const _market = FreeAgentMarketValueService();
const _evaluator = FreeAgentOfferEvaluator();

GmCareer _career({
  FranchiseSituation situation = FranchiseSituation.tanking,
  String team = 'team-1',
}) => GmCareer.fromSetupResult(
  const CareerSetupService().generate(
    CareerSetupRequest(
      selectedTeamId: TeamId(team),
      selectedSituation: situation,
      seed: _seed,
    ),
  ),
  id: 't08e-market',
);

PublicFreeAgentView _view({
  required int overall,
  required int age,
  Position position = Position.pg,
}) => PublicFreeAgentView(
  id: PlayerId('test-$overall-$age-${position.shortName}'),
  firstName: 'Test',
  lastName: 'Player',
  position: position,
  age: age,
  attributes: PlayerAttributes(
    insideScoring: overall,
    midrange: overall,
    threePoint: overall,
    freeThrow: overall,
    passing: overall,
    ballHandling: overall,
    perimeterDefense: overall,
    interiorDefense: overall,
    rebounding: overall,
    athleticism: overall,
    stamina: overall,
    basketballIQ: overall,
  ),
  overallRating: overall,
);

FreeAgentOfferDecision _offer(
  GmCareer career,
  PlayerId id, {
  RosterCategory category = RosterCategory.standard,
  required int duration,
  required int salary,
  TeamId? teamId,
}) => _evaluator.evaluate(
  career: career,
  teamId: teamId ?? career.userFranchiseId,
  freeAgentId: id,
  category: category,
  durationYears: duration,
  agreedFirstYearSalary: salary,
);

String _reason(FreeAgentOfferDecision decision) =>
    '${decision.status.jsonValue}:${decision.reasonCode}';

void main() {
  group('T08E market valuation and offer policy', () {
    test('valuation is deterministic and OVR-driven', () {
      final low = _market.estimate(_view(overall: 60, age: 26));
      final high = _market.estimate(_view(overall: 80, age: 26));
      expect(low.estimatedAnnualSalary, lessThan(high.estimatedAnnualSalary));
      expect(low.preferredDurationYears, 3);
      expect(high.expectedRole, ExpectedPlayerRole.starter);
      expect(
        low.estimatedAnnualSalary,
        _market.estimate(_view(overall: 60, age: 26)).estimatedAnnualSalary,
      );
      expect(
        low.acceptableMinimum,
        lessThanOrEqualTo(low.estimatedAnnualSalary),
      );
      expect(
        low.acceptableMaximum,
        greaterThanOrEqualTo(low.estimatedAnnualSalary),
      );
    });

    test('age changes value, role preference and duration', () {
      final young = _market.estimate(_view(overall: 75, age: 22));
      final prime = _market.estimate(_view(overall: 75, age: 27));
      final veteran = _market.estimate(_view(overall: 75, age: 36));
      expect(young.preferredDurationYears, 2);
      expect(prime.preferredDurationYears, 3);
      expect(veteran.preferredDurationYears, 1);
      expect(
        veteran.estimatedAnnualSalary,
        lessThan(prime.estimatedAnnualSalary),
      );
      expect(
        _market.annualValue(_view(overall: 75, age: 27), 1),
        greaterThan(_market.annualValue(_view(overall: 75, age: 27), 4)),
      );
    });

    test(
      'hidden potential and trajectory cannot change valuation or decision',
      () {
        final career = _career();
        final entry = career.freeAgentPool.entries.firstWhere(
          (candidate) => candidate.player.attributes.overallRating >= 65,
        );
        final view = entry.toPublicView();
        final valuation = _market.estimate(view);
        final before = _offer(
          career,
          entry.id,
          duration: valuation.preferredDurationYears,
          salary: valuation.acceptableMinimum,
        );
        final alteredProfile = PlayerCareerProfile(
          playerId: entry.id,
          age: entry.profile.age,
          potential: 99,
          trajectory: DevelopmentTrajectory.volatile,
        );
        final alteredPool = FreeAgentPool(
          entries: [
            for (final candidate in career.freeAgentPool.entries)
              candidate.id == entry.id
                  ? FreeAgentEntry(
                      player: candidate.player,
                      profile: alteredProfile,
                    )
                  : candidate,
          ],
          initialPlayerIds: career.freeAgentPool.initialPlayerIds,
          acquisitions: career.freeAgentPool.acquisitions,
        );
        final altered = career.copyWith(freeAgentPool: alteredPool);
        final after = _offer(
          altered,
          entry.id,
          duration: valuation.preferredDurationYears,
          salary: valuation.acceptableMinimum,
        );
        expect(_reason(after), _reason(before));
        expect(
          after.valuation.estimatedAnnualSalary,
          valuation.estimatedAnnualSalary,
        );
      },
    );

    test('high-value players reject minimum offers', () {
      final career = _career();
      final entry = career.freeAgentPool.entries.firstWhere(
        (candidate) => candidate.player.attributes.overallRating >= 75,
      );
      final valuation = _market.estimate(entry.toPublicView());
      final decision = _offer(
        career,
        entry.id,
        duration: valuation.preferredDurationYears,
        salary: 400,
      );
      expect(decision.isAcceptable, isFalse);
      expect(decision.status, isNot(FreeAgentOfferStatus.financiallyIllegal));
      expect(decision.isFinanciallyLegal, isTrue);
    });

    test('lower-tier players accept a reasonable top-of-range offer', () {
      final career = _career();
      final entry = career.freeAgentPool.entries.firstWhere(
        (candidate) =>
            candidate.player.attributes.overallRating >= 56 &&
            candidate.player.attributes.overallRating < 62,
      );
      final valuation = _market.estimate(entry.toPublicView());
      final decision = _offer(
        career,
        entry.id,
        duration: valuation.preferredDurationYears,
        salary: valuation.acceptableMaximum,
      );
      expect(decision.status, FreeAgentOfferStatus.acceptable);
    });

    test('offering more money never worsens acceptance', () {
      final career = _career();
      final entry = career.freeAgentPool.entries.firstWhere(
        (candidate) =>
            candidate.player.attributes.overallRating >= 58 &&
            candidate.player.attributes.overallRating < 68,
      );
      final valuation = _market.estimate(entry.toPublicView());
      var accepted = false;
      for (var salary = 400; salary <= 8000; salary += 100) {
        final decision = _offer(
          career,
          entry.id,
          duration: valuation.preferredDurationYears,
          salary: salary,
        );
        if (decision.isAcceptable) accepted = true;
        if (accepted) {
          expect(
            decision.isAcceptable ||
                decision.status == FreeAgentOfferStatus.invalidTerms ||
                decision.status == FreeAgentOfferStatus.financiallyIllegal,
            isTrue,
            reason: 'salary $salary produced a player-side regression',
          );
        }
      }
      expect(accepted, isTrue);
    });

    test('franchise situation changes acceptance for the same player', () {
      final tanking = _career(situation: FranchiseSituation.tanking);
      final contender = _career(situation: FranchiseSituation.contender);
      final entry = tanking.freeAgentPool.entries.firstWhere(
        (candidate) =>
            candidate.player.attributes.overallRating >= 60 &&
            candidate.player.attributes.overallRating < 72 &&
            candidate.profile.age <= 24,
      );
      final valuation = _market.estimate(entry.toPublicView());
      final tankingDecision = _offer(
        tanking,
        entry.id,
        duration: valuation.preferredDurationYears,
        salary: valuation.acceptableMinimum,
      );
      final contenderDecision = _offer(
        contender,
        entry.id,
        duration: valuation.preferredDurationYears,
        salary: valuation.acceptableMinimum,
      );
      expect(tankingDecision.status, FreeAgentOfferStatus.acceptable);
      expect(contenderDecision.isAcceptable, isFalse);
    });

    test('position depth can produce a poor-fit rejection', () {
      final base = _career(situation: FranchiseSituation.playoff);
      final entry = base.freeAgentPool.entries.firstWhere(
        (candidate) =>
            candidate.player.position == Position.pg &&
            candidate.profile.age < 30 &&
            candidate.player.attributes.overallRating < 72,
      );
      final team = base.userTeam;
      var roster = team.roster;
      final added = <Player>[];
      for (var i = 0; i < 2; i++) {
        final player = Player(
          id: PlayerId('depth-pg-$i'),
          firstName: 'Depth',
          lastName: 'Guard$i',
          position: Position.pg,
          attributes: _view(overall: 82, age: 27).attributes,
        );
        added.add(player);
        roster = roster.withPlayer(player);
      }
      final deep = withBootstrappedTeam(
        base,
        team.copyWith(roster: roster),
        careerProfiles: LeagueCareerProfiles(
          leagueSeed: base.careerProfiles.leagueSeed,
          profiles: {
            ...base.careerProfiles.profiles,
            for (final player in added)
              player.id.value: PlayerCareerProfile(
                playerId: player.id,
                age: 27,
                potential: 90,
                trajectory: DevelopmentTrajectory.steady,
              ),
          },
        ),
      );
      final decision = _offer(
        deep,
        entry.id,
        duration: _market.estimate(entry.toPublicView()).preferredDurationYears,
        salary: 400,
      );
      expect(decision.status, FreeAgentOfferStatus.poorFit);
      expect(decision.reasonCode, 'roleOrFranchiseFit');
    });

    test('two-way category is unavailable to established players', () {
      final career = _career();
      final entry = career.freeAgentPool.entries.firstWhere(
        (candidate) => candidate.player.attributes.overallRating >= 70,
      );
      final decision = _offer(
        career,
        entry.id,
        category: RosterCategory.twoWay,
        duration: 1,
        salary: 250,
      );
      expect(decision.status, FreeAgentOfferStatus.inappropriateCategory);
      expect(decision.isFinanciallyLegal, isTrue);
    });

    test('duration rules are category-specific', () {
      final career = _career();
      final entry = career.freeAgentPool.entries.first;
      expect(
        _offer(
          career,
          entry.id,
          category: RosterCategory.twoWay,
          duration: 3,
          salary: 250,
        ).status,
        FreeAgentOfferStatus.invalidTerms,
      );
      expect(
        _offer(
          career,
          entry.id,
          category: RosterCategory.standard,
          duration: 5,
          salary: 1000,
        ).status,
        FreeAgentOfferStatus.invalidTerms,
      );
      expect(
        _offer(
          career,
          entry.id,
          category: RosterCategory.standard,
          duration: 4,
          salary: 1000,
        ).status,
        isNot(FreeAgentOfferStatus.invalidTerms),
      );
      expect(FinancialRules.maxDurationForCategory(RosterCategory.twoWay), 2);
      expect(FinancialRules.maxDurationForCategory(RosterCategory.standard), 4);
      expect(FinancialRules.standardSchedule(1000, 3), [1000, 1050, 1102]);
    });

    test('later-year maximum is rejected as invalid terms', () {
      final career = _career();
      final entry = career.freeAgentPool.entries.first;
      expect(
        _offer(career, entry.id, duration: 2, salary: 8000).status,
        FreeAgentOfferStatus.invalidTerms,
      );
    });

    test('cap failure is distinct from player rejection', () {
      final career = _career(
        situation: FranchiseSituation.contender,
        team: 'team-19',
      );
      final entry = career.freeAgentPool.entries.first;
      final decision = _offer(career, entry.id, duration: 1, salary: 2000);
      expect(decision.status, FreeAgentOfferStatus.financiallyIllegal);
      expect(decision.reasonCode, 'capBreach');
      expect(decision.isFinanciallyLegal, isFalse);
    });

    test('evaluation is read-only and does not acquire the player', () {
      final career = _career();
      final entry = career.freeAgentPool.entries.first;
      final before = GmCareerCodec.encode(career);
      _offer(career, entry.id, duration: 2, salary: 1000);
      _offer(
        career,
        entry.id,
        category: RosterCategory.twoWay,
        duration: 1,
        salary: 250,
      );
      expect(GmCareerCodec.encode(career), before);
      expect(career.freeAgentPool.length, 90);
      expect(career.freeAgentPool.acquisitions.length, 0);
    });

    test(
      'identical state and evaluation order produce identical decisions',
      () {
        final career = _career();
        final first = career.freeAgentPool.entries[0].id;
        final second = career.freeAgentPool.entries[1].id;
        final a1 = _offer(career, first, duration: 2, salary: 1200);
        final b = _offer(career, second, duration: 1, salary: 900);
        final a2 = _offer(career, first, duration: 2, salary: 1200);
        expect(_reason(a2), _reason(a1));
        expect(
          a2.valuation.estimatedAnnualSalary,
          a1.valuation.estimatedAnnualSalary,
        );
        expect(b.status, isNotNull);
      },
    );

    test('save/load does not change valuation or decision', () {
      final career = _career();
      final entry = career.freeAgentPool.entries.first;
      final before = _offer(career, entry.id, duration: 3, salary: 1500);
      final decoded = GmCareerCodec.decode(GmCareerCodec.encode(career));
      final after = _offer(decoded, entry.id, duration: 3, salary: 1500);
      expect(_reason(after), _reason(before));
      expect(
        after.valuation.estimatedAnnualSalary,
        before.valuation.estimatedAnnualSalary,
      );
    });

    test('all 30 franchises can be evaluated without mutation', () {
      final career = _career();
      final entry = career.freeAgentPool.entries.first;
      for (final team in career.league.teams) {
        final decision = _offer(
          career,
          entry.id,
          teamId: team.id,
          duration: 1,
          salary: 400,
        );
        expect(decision.status, isNotNull);
      }
      expect(career.freeAgentPool.acquisitions.length, 0);
    });

    test('evaluation does not alter valuation after an acquisition', () {
      final career = _career();
      final acquireId = career.freeAgentPool.entries.first.id;
      final target = career.freeAgentPool.entries[1].id;
      final before = _offer(career, target, duration: 2, salary: 1000);
      final acquired = const FreeAgentAcquisitionService().acquire(
        career: career,
        teamId: career.userFranchiseId,
        freeAgentId: acquireId,
        category: RosterCategory.standard,
        durationYears: 1,
        agreedFirstYearSalary: 400,
      );
      final after = _offer(acquired, target, duration: 2, salary: 1000);
      expect(_reason(after), _reason(before));
      expect(
        jsonEncode(acquired.freeAgentPool.acquisitions.toJson()),
        isNot(jsonEncode(career.freeAgentPool.acquisitions.toJson())),
      );
    });
  });
}
