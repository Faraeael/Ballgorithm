import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _seed = 20261028;
const _submission = FreeAgentOfferSubmissionService();
const _evaluator = FreeAgentOfferEvaluator();
const _market = FreeAgentMarketValueService();

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
  id: 't08f-offers',
);

FreeAgentOfferSubmissionResult _submit(
  GmCareer career,
  PlayerId id, {
  RosterCategory category = RosterCategory.standard,
  required int duration,
  required int salary,
}) => _submission.submit(
  career: career,
  teamId: career.userFranchiseId,
  freeAgentId: id,
  category: category,
  durationYears: duration,
  agreedFirstYearSalary: salary,
);

Matcher _codesContain(ValidationCode code) => throwsA(
  isA<DomainValidationException>().having(
    (error) => error.codes,
    'codes',
    contains(code),
  ),
);

FreeAgentOfferAttempt _attempt({
  required FreeAgentOfferOutcome outcome,
  String? acquisitionTransactionId,
  int attemptNumber = 1,
}) => FreeAgentOfferAttempt(
  offerId: 'offer-$attemptNumber',
  playerId: const PlayerId('free-agent-1'),
  teamId: const TeamId('team-1'),
  seasonYear: 1,
  category: RosterCategory.standard,
  durationYears: 1,
  firstYearSalary: 400,
  outcome: outcome,
  reasonCode: outcome.jsonValue,
  attemptNumber: attemptNumber,
  acquisitionTransactionId: acquisitionTransactionId,
);

void main() {
  group('T08F formal free-agent offers', () {
    test('accepted offer records and acquires atomically', () {
      final career = _career();
      final entry = career.freeAgentPool.entries.firstWhere(
        (candidate) => candidate.player.attributes.overallRating >= 60,
      );
      final valuation = _market.estimate(entry.toPublicView());
      final result = _submit(
        career,
        entry.id,
        duration: valuation.preferredDurationYears,
        salary: valuation.acceptableMaximum,
      );
      expect(result.status, FreeAgentOfferSubmissionStatus.accepted);
      expect(result.recorded, isTrue);
      expect(result.career.freeAgentPool.length, 89);
      expect(result.career.freeAgentPool.acquisitions.length, 1);
      final offer = result.career.freeAgentOffers
          .attemptsFor(
            teamId: result.career.userFranchiseId,
            playerId: entry.id,
            seasonYear: 1,
          )
          .single;
      expect(offer.outcome, FreeAgentOfferOutcome.accepted);
      expect(offer.attemptNumber, 1);
      expect(offer.acquisitionTransactionId, isNotNull);
      expect(
        result
            .career
            .freeAgentPool
            .acquisitions
            .entries[offer.acquisitionTransactionId]!
            .playerId,
        entry.id,
      );
      expect(
        result.career.finances.contractForPlayer(entry.id)!.source,
        ContractSource.freeAgent,
      );
      expect(
        result.career.userTeam.players.any((player) => player.id == entry.id),
        isTrue,
      );
      expect(
        result.career.userTeam.players
            .firstWhere((player) => player.id == entry.id)
            .attributes
            .asMap,
        entry.player.attributes.asMap,
      );
    });

    test('salary rejection is durable and does not acquire', () {
      final career = _career();
      final entry = career.freeAgentPool.entries.firstWhere((candidate) {
        final decision = _evaluator.evaluate(
          career: career,
          teamId: career.userFranchiseId,
          freeAgentId: candidate.id,
          category: RosterCategory.standard,
          durationYears: _market
              .estimate(candidate.toPublicView())
              .preferredDurationYears,
          agreedFirstYearSalary: 400,
        );
        return decision.status == FreeAgentOfferStatus.salaryTooLow;
      });
      final valuation = _market.estimate(entry.toPublicView());
      final result = _submit(
        career,
        entry.id,
        duration: valuation.preferredDurationYears,
        salary: 400,
      );
      expect(result.status, FreeAgentOfferSubmissionStatus.rejected);
      expect(result.recorded, isTrue);
      expect(result.career.freeAgentPool.length, 90);
      expect(result.career.freeAgentPool.acquisitions.length, 0);
      final offer = result.career.freeAgentOffers
          .attemptsFor(
            teamId: result.career.userFranchiseId,
            playerId: entry.id,
            seasonYear: 1,
          )
          .single;
      expect(offer.outcome, FreeAgentOfferOutcome.salaryTooLow);
      expect(offer.acquisitionTransactionId, isNull);
      expect(result.career.finances.contractForPlayer(entry.id), isNull);
    });

    test('improved second offer can be accepted', () {
      var career = _career();
      final entry = career.freeAgentPool.entries.firstWhere(
        (candidate) => candidate.player.attributes.overallRating >= 62,
      );
      final valuation = _market.estimate(entry.toPublicView());
      final first = _submit(
        career,
        entry.id,
        duration: valuation.preferredDurationYears,
        salary: 400,
      );
      expect(first.status, FreeAgentOfferSubmissionStatus.rejected);
      career = first.career;
      final second = _submit(
        career,
        entry.id,
        duration: valuation.preferredDurationYears,
        salary: valuation.acceptableMaximum,
      );
      expect(second.status, FreeAgentOfferSubmissionStatus.accepted);
      expect(second.career.freeAgentOffers.length, 2);
      expect(second.career.freeAgentPool.length, 89);
      expect(
        second.career.freeAgentOffers
            .attemptsFor(
              teamId: second.career.userFranchiseId,
              playerId: entry.id,
              seasonYear: 1,
            )
            .map((attempt) => attempt.attemptNumber),
        [1, 2],
      );
    });

    test('two player-side rejections block a third offer', () {
      var career = _career();
      final entry = career.freeAgentPool.entries.firstWhere(
        (candidate) => candidate.player.attributes.overallRating >= 75,
      );
      final duration = _market
          .estimate(entry.toPublicView())
          .preferredDurationYears;
      final first = _submit(career, entry.id, duration: duration, salary: 400);
      expect(first.status, FreeAgentOfferSubmissionStatus.rejected);
      career = first.career;
      final second = _submit(career, entry.id, duration: duration, salary: 500);
      expect(second.status, FreeAgentOfferSubmissionStatus.rejected);
      career = second.career;
      expect(
        () => _submit(career, entry.id, duration: duration, salary: 600),
        _codesContain(ValidationCode.freeAgentOfferLimitReached),
      );
      expect(career.freeAgentOffers.length, 2);
    });

    test(
      'identical repeated offer is rejected without consuming an attempt',
      () {
        final career = _career();
        final entry = career.freeAgentPool.entries.first;
        final duration = _market
            .estimate(entry.toPublicView())
            .preferredDurationYears;
        final first = _submit(
          career,
          entry.id,
          duration: duration,
          salary: 400,
        );
        expect(first.recorded, isTrue);
        expect(
          () =>
              _submit(first.career, entry.id, duration: duration, salary: 400),
          _codesContain(ValidationCode.freeAgentOfferDuplicate),
        );
        expect(first.career.freeAgentOffers.length, 1);
      },
    );

    test('invalid and financially illegal offers consume no attempt', () {
      final career = _career();
      final entry = career.freeAgentPool.entries.first;
      final invalid = _submit(career, entry.id, duration: 1, salary: 399);
      expect(invalid.status, FreeAgentOfferSubmissionStatus.invalidTerms);
      expect(invalid.recorded, isFalse);
      expect(invalid.career.freeAgentOffers.length, 0);

      final nearCap = _career(
        situation: FranchiseSituation.contender,
        team: 'team-19',
      );
      final illegal = _submit(
        nearCap,
        nearCap.freeAgentPool.entries.first.id,
        duration: 1,
        salary: 2000,
      );
      expect(illegal.status, FreeAgentOfferSubmissionStatus.financiallyIllegal);
      expect(illegal.recorded, isFalse);
      expect(illegal.career.freeAgentOffers.length, 0);
    });

    test('acquired player cannot receive another offer', () {
      final career = _career();
      final entry = career.freeAgentPool.entries.first;
      final valuation = _market.estimate(entry.toPublicView());
      final accepted = _submit(
        career,
        entry.id,
        duration: valuation.preferredDurationYears,
        salary: valuation.acceptableMaximum,
      );
      expect(accepted.status, FreeAgentOfferSubmissionStatus.accepted);
      final again = _submit(
        accepted.career,
        entry.id,
        duration: valuation.preferredDurationYears,
        salary: valuation.acceptableMaximum,
      );
      expect(again.status, FreeAgentOfferSubmissionStatus.invalidTerms);
      expect(again.recorded, isFalse);
      expect(accepted.career.freeAgentOffers.length, 1);
    });

    test('two-way offer is accepted only for eligible players', () {
      final career = _career();
      final low = career.freeAgentPool.entries.firstWhere(
        (candidate) =>
            candidate.player.attributes.overallRating < 62 &&
            candidate.profile.age < 27,
      );
      final accepted = _submit(
        career,
        low.id,
        category: RosterCategory.twoWay,
        duration: 1,
        salary: 250,
      );
      expect(accepted.status, FreeAgentOfferSubmissionStatus.accepted);
      final contract = accepted.career.finances.contractForPlayer(low.id)!;
      expect(contract.category, RosterCategory.twoWay);
      expect(
        accepted.career.finances.cashPayrollFor(
          accepted.career.userFranchiseId,
          1,
        ),
        accepted.career.finances.capPayrollFor(
              accepted.career.userFranchiseId,
              1,
            ) +
            250,
      );

      final established = career.freeAgentPool.entries.firstWhere(
        (candidate) => candidate.player.attributes.overallRating >= 70,
      );
      final rejected = _submit(
        career,
        established.id,
        category: RosterCategory.twoWay,
        duration: 1,
        salary: 250,
      );
      expect(rejected.status, FreeAgentOfferSubmissionStatus.rejected);
      expect(
        rejected.career.freeAgentOffers
            .attemptsFor(
              teamId: rejected.career.userFranchiseId,
              playerId: established.id,
              seasonYear: 1,
            )
            .single
            .outcome,
        FreeAgentOfferOutcome.inappropriateCategory,
      );
    });

    test('offers persist through save/load and restart limits survive', () {
      var career = _career();
      final entry = career.freeAgentPool.entries.firstWhere(
        (candidate) => candidate.player.attributes.overallRating >= 75,
      );
      final duration = _market
          .estimate(entry.toPublicView())
          .preferredDurationYears;
      career = _submit(
        career,
        entry.id,
        duration: duration,
        salary: 400,
      ).career;
      career = _submit(
        career,
        entry.id,
        duration: duration,
        salary: 500,
      ).career;
      final encoded = GmCareerCodec.encode(career);
      final decoded = GmCareerCodec.decode(encoded);
      expect(GmCareerCodec.encode(decoded), encoded);
      expect(decoded.freeAgentOffers.length, 2);
      expect(
        decoded.freeAgentOffers.remainingAttempts(
          teamId: decoded.userFranchiseId,
          playerId: entry.id,
          seasonYear: 1,
        ),
        0,
      );
      expect(
        () => _submit(decoded, entry.id, duration: duration, salary: 600),
        _codesContain(ValidationCode.freeAgentOfferLimitReached),
      );
    });

    test('v1-v9 migrate with empty offers and v10 is strict', () {
      final base =
          jsonDecode(GmCareerCodec.encode(_career())) as Map<String, dynamic>;
      for (var version = 1; version <= 9; version++) {
        final older = Map<String, dynamic>.from(base)
          ..['schemaVersion'] = version
          ..remove('freeAgentOffers');
        final migrated = GmCareerCodec.decode(jsonEncode(older));
        expect(migrated.schemaVersion, 12);
        expect(migrated.freeAgentOffers.isEmpty, isTrue);
      }
      final missing = Map<String, dynamic>.from(base)
        ..remove('freeAgentOffers');
      expect(
        () => GmCareerCodec.decode(jsonEncode(missing)),
        throwsFormatException,
      );
    });

    test('offer ledger corruption is rejected', () {
      expect(
        () => FreeAgentOfferLedger(
          entries: [
            _attempt(outcome: FreeAgentOfferOutcome.salaryTooLow),
            _attempt(outcome: FreeAgentOfferOutcome.salaryTooLow),
          ],
        ),
        _codesContain(ValidationCode.freeAgentOfferDuplicate),
      );
      expect(
        () => _attempt(outcome: FreeAgentOfferOutcome.accepted),
        _codesContain(ValidationCode.freeAgentOfferInvalid),
      );
      expect(
        () => _attempt(
          outcome: FreeAgentOfferOutcome.salaryTooLow,
          acquisitionTransactionId: 'tx',
        ),
        _codesContain(ValidationCode.freeAgentOfferInvalid),
      );
      expect(
        () => _attempt(
          outcome: FreeAgentOfferOutcome.salaryTooLow,
          attemptNumber: 3,
        ),
        _codesContain(ValidationCode.freeAgentOfferInvalid),
      );
      final career = _career();
      final acceptedWithoutAcquisition = FreeAgentOfferAttempt(
        offerId: 'forged',
        playerId: career.freeAgentPool.entries.first.id,
        teamId: career.userFranchiseId,
        seasonYear: 1,
        category: RosterCategory.standard,
        durationYears: 1,
        firstYearSalary: 400,
        outcome: FreeAgentOfferOutcome.accepted,
        reasonCode: 'accepted',
        attemptNumber: 1,
        acquisitionTransactionId: 'missing-acquisition',
      );
      expect(
        () => career.copyWith(
          freeAgentOffers: FreeAgentOfferLedger(
            entries: [acceptedWithoutAcquisition],
          ),
        ),
        throwsFormatException,
      );
    });

    test('accepted offer preserves existing contracts and identity', () {
      final career = _career();
      final entry = career.freeAgentPool.entries.firstWhere(
        (candidate) => candidate.player.attributes.overallRating >= 60,
      );
      final before = jsonEncode({
        'contracts': [
          for (final contract in career.finances.contracts.values)
            contract.toJson(),
        ],
        'schedules': [
          for (final schedule in career.finances.schedules.values)
            schedule.toJson(),
        ],
      });
      final valuation = _market.estimate(entry.toPublicView());
      final accepted = _submit(
        career,
        entry.id,
        duration: valuation.preferredDurationYears,
        salary: valuation.acceptableMaximum,
      );
      final after = jsonEncode({
        'contracts': [
          for (final contract in accepted.career.finances.contracts.values)
            if (contract.playerId != entry.id) contract.toJson(),
        ],
        'schedules': [
          for (final schedule in accepted.career.finances.schedules.values)
            if (schedule.playerId != entry.id) schedule.toJson(),
        ],
      });
      expect(after, before);
      final acquiredPlayer = accepted.career.userTeam.players.firstWhere(
        (player) => player.id == entry.id,
      );
      expect(acquiredPlayer.firstName, entry.player.firstName);
      expect(acquiredPlayer.attributes.asMap, entry.player.attributes.asMap);
      final offerJson = accepted.career.freeAgentOffers.toJson();
      expect(jsonEncode(offerJson), isNot(contains('potential')));
      expect(jsonEncode(offerJson), isNot(contains('trajectory')));
    });
  });
}
