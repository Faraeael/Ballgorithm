import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _seed = 20261028;
const _marketService = FreeAgentMarketService();
const _value = FreeAgentMarketValueService();

GmCareer _career({FranchiseSituation situation = FranchiseSituation.playIn}) =>
    GmCareer.fromSetupResult(
      const CareerSetupService().generate(
        CareerSetupRequest(
          selectedTeamId: const TeamId('team-1'),
          selectedSituation: situation,
          seed: _seed,
        ),
      ),
      id: 't08g-market',
    );

GmCareer _resolveAll(GmCareer career) {
  var current = career;
  while (current.freeAgentMarket.isResolvable &&
      current.freeAgentMarket.nextResolutionIndex <
          current.freeAgentMarket.resolutionOrder.length) {
    current = _marketService.resolveNext(current);
  }
  if (current.freeAgentMarket.status == FreeAgentMarketStatus.resolving) {
    current = _marketService.resolveNext(current);
  }
  return current;
}

FreeAgentMarketState _preparedState({
  required GmCareer career,
  required PlayerId playerId,
  required List<FreeAgentMarketOffer> humanOffers,
  required List<FreeAgentMarketOffer> aiOffers,
}) => FreeAgentMarketState(
  status: FreeAgentMarketStatus.preparedForResolution,
  roundNumber: 1,
  seasonYear: career.currentYear,
  humanOffers: humanOffers,
  aiOffers: aiOffers,
  resolutionOrder: [playerId],
  nextResolutionIndex: 0,
  outcomes: const [],
  completedRounds: 0,
);

FreeAgentMarketOffer _offer({
  required TeamId teamId,
  required PlayerId playerId,
  required int salary,
  required FreeAgentMarketOfferSource source,
  int round = 1,
}) => FreeAgentMarketOffer(
  offerId: FreeAgentMarketOffer.idFor(
    teamId: teamId,
    playerId: playerId,
    roundNumber: round,
    seasonYear: 1,
  ),
  playerId: playerId,
  teamId: teamId,
  roundNumber: round,
  seasonYear: 1,
  category: RosterCategory.standard,
  durationYears: 1,
  firstYearSalary: salary,
  source: source,
);

void main() {
  group('T08G competitive free agency', () {
    test('staging a human offer does not acquire or consume an attempt', () {
      var career = _marketService.startRound(_career());
      final player = career.freeAgentPool.entries.first;
      final valuation = _value.estimate(player.toPublicView());
      career = _marketService.stageHumanOffer(
        career: career,
        teamId: career.userFranchiseId,
        playerId: player.id,
        category: RosterCategory.standard,
        durationYears: valuation.preferredDurationYears,
        firstYearSalary: valuation.acceptableMinimum,
      );
      expect(career.freeAgentMarket.humanOffers.length, 1);
      expect(career.freeAgentPool.length, 90);
      expect(career.freeAgentPool.acquisitions.length, 0);
      expect(career.freeAgentOffers.length, 0);
      expect(
        career.freeAgentMarket.humanOffers.single.source,
        FreeAgentMarketOfferSource.human,
      );
    });

    test('pending offers can be cancelled before locking', () {
      var career = _marketService.startRound(_career());
      final player = career.freeAgentPool.entries.first;
      career = _marketService.stageHumanOffer(
        career: career,
        teamId: career.userFranchiseId,
        playerId: player.id,
        category: RosterCategory.standard,
        durationYears: 1,
        firstYearSalary: 1000,
      );
      career = _marketService.cancelHumanOffer(
        career: career,
        playerId: player.id,
      );
      expect(career.freeAgentMarket.humanOffers, isEmpty);
      expect(career.freeAgentOffers.length, 0);
    });

    test('locking seals deterministic AI offers without acquisitions', () {
      var career = _marketService.startRound(_career());
      final humanPlayer = career.freeAgentPool.entries.first;
      career = _marketService.stageHumanOffer(
        career: career,
        teamId: career.userFranchiseId,
        playerId: humanPlayer.id,
        category: RosterCategory.standard,
        durationYears: 1,
        firstYearSalary: 1000,
      );
      career = _marketService.prepareResolution(career);
      expect(
        career.freeAgentMarket.status,
        FreeAgentMarketStatus.preparedForResolution,
      );
      expect(career.freeAgentMarket.aiOffers, isNotEmpty);
      expect(
        career.freeAgentMarket.aiOffers.every(
          (offer) => offer.source == FreeAgentMarketOfferSource.ai,
        ),
        isTrue,
      );
      final targets = career.freeAgentMarket.aiOffers
          .map((offer) => offer.playerId.value)
          .toSet();
      final perTarget = <String, int>{};
      for (final offer in career.freeAgentMarket.aiOffers) {
        perTarget[offer.playerId.value] =
            (perTarget[offer.playerId.value] ?? 0) + 1;
      }
      expect(targets.length, greaterThan(50));
      expect(
        perTarget.values.fold<int>(
          0,
          (max, value) => value > max ? value : max,
        ),
        lessThanOrEqualTo(10),
      );
      expect(career.freeAgentPool.acquisitions, isEmpty);
      final encoded = GmCareerCodec.encode(career);
      final decoded = GmCareerCodec.decode(encoded);
      expect(
        jsonEncode(
          decoded.freeAgentMarket.aiOffers.map((o) => o.toJson()).toList(),
        ),
        jsonEncode(
          career.freeAgentMarket.aiOffers.map((o) => o.toJson()).toList(),
        ),
      );
    });

    test('human and AI can compete; higher salary wins', () {
      final base = _career();
      final player = base.freeAgentPool.entries.firstWhere(
        (entry) => entry.player.attributes.overallRating >= 60,
      );
      final aiTeam = base.league.teams.firstWhere(
        (team) => team.id != base.userFranchiseId,
      );
      final human = _offer(
        teamId: base.userFranchiseId,
        playerId: player.id,
        salary: 3500,
        source: FreeAgentMarketOfferSource.human,
      );
      final ai = _offer(
        teamId: aiTeam.id,
        playerId: player.id,
        salary: 3000,
        source: FreeAgentMarketOfferSource.ai,
      );
      final career = base.copyWith(
        freeAgentMarket: _preparedState(
          career: base,
          playerId: player.id,
          humanOffers: [human],
          aiOffers: [ai],
        ),
      );
      final resolved = _resolveAll(career);
      final outcome = resolved.freeAgentMarket.outcomes.single;
      expect(outcome.winningTeamId, base.userFranchiseId);
      expect(resolved.freeAgentPool.length, 89);
      expect(
        resolved.freeAgentOffers
            .attemptsFor(
              teamId: base.userFranchiseId,
              playerId: player.id,
              seasonYear: 1,
            )
            .single
            .outcome,
        FreeAgentOfferOutcome.accepted,
      );
      expect(
        outcome.results
            .where(
              (result) =>
                  result.teamId == aiTeam.id &&
                  result.outcome == FreeAgentMarketOfferOutcome.outbid,
            )
            .length,
        1,
      );
      expect(
        resolved.freeAgentOffers.attemptsFor(
          teamId: aiTeam.id,
          playerId: player.id,
          seasonYear: 1,
        ),
        isEmpty,
      );
    });

    test('AI can beat the human; human loser is outbid, not rejected', () {
      final base = _career();
      final player = base.freeAgentPool.entries.firstWhere(
        (entry) => entry.player.attributes.overallRating >= 60,
      );
      final aiTeam = base.league.teams.firstWhere(
        (team) => team.id != base.userFranchiseId,
      );
      final career = base.copyWith(
        freeAgentMarket: _preparedState(
          career: base,
          playerId: player.id,
          humanOffers: [
            _offer(
              teamId: base.userFranchiseId,
              playerId: player.id,
              salary: 3000,
              source: FreeAgentMarketOfferSource.human,
            ),
          ],
          aiOffers: [
            _offer(
              teamId: aiTeam.id,
              playerId: player.id,
              salary: 4000,
              source: FreeAgentMarketOfferSource.ai,
            ),
          ],
        ),
      );
      final resolved = _resolveAll(career);
      expect(resolved.freeAgentMarket.outcomes.single.winningTeamId, aiTeam.id);
      expect(
        resolved.freeAgentOffers.attemptsFor(
          teamId: base.userFranchiseId,
          playerId: player.id,
          seasonYear: 1,
        ),
        isEmpty,
      );
      expect(
        resolved.freeAgentMarket.outcomes.single.results
            .where(
              (result) =>
                  result.teamId == base.userFranchiseId &&
                  result.outcome == FreeAgentMarketOfferOutcome.outbid,
            )
            .length,
        1,
      );
    });

    test('better fit can beat a near-equal higher salary', () {
      final base = _career(situation: FranchiseSituation.tanking);
      final player = base.freeAgentPool.entries.firstWhere(
        (entry) =>
            entry.player.attributes.overallRating >= 60 &&
            entry.profile.age <= 24,
      );
      final aiTeam = base.league.teams.firstWhere(
        (team) =>
            team.id != base.userFranchiseId &&
            team.situation == FranchiseSituation.contender,
      );
      final career = base.copyWith(
        freeAgentMarket: _preparedState(
          career: base,
          playerId: player.id,
          humanOffers: [
            _offer(
              teamId: base.userFranchiseId,
              playerId: player.id,
              salary: 3400,
              source: FreeAgentMarketOfferSource.human,
            ),
          ],
          aiOffers: [
            _offer(
              teamId: aiTeam.id,
              playerId: player.id,
              salary: 3500,
              source: FreeAgentMarketOfferSource.ai,
            ),
          ],
        ),
      );
      final resolved = _resolveAll(career);
      expect(
        resolved.freeAgentMarket.outcomes.single.winningTeamId,
        base.userFranchiseId,
      );
    });

    test('equal offers use a stable team-order-independent tie-break', () {
      final base = _career();
      final player = base.freeAgentPool.entries.firstWhere(
        (entry) => entry.player.attributes.overallRating >= 60,
      );
      final aiTeam = base.league.teams.firstWhere(
        (team) => team.id != base.userFranchiseId,
      );
      final human = _offer(
        teamId: base.userFranchiseId,
        playerId: player.id,
        salary: 3500,
        source: FreeAgentMarketOfferSource.human,
      );
      final ai = _offer(
        teamId: aiTeam.id,
        playerId: player.id,
        salary: 3500,
        source: FreeAgentMarketOfferSource.ai,
      );
      final first = _resolveAll(
        base.copyWith(
          freeAgentMarket: _preparedState(
            career: base,
            playerId: player.id,
            humanOffers: [human],
            aiOffers: [ai],
          ),
        ),
      );
      final second = _resolveAll(
        base.copyWith(
          freeAgentMarket: _preparedState(
            career: base,
            playerId: player.id,
            humanOffers: [human],
            aiOffers: [ai],
          ),
        ),
      );
      expect(
        first.freeAgentMarket.outcomes.single.winningTeamId,
        second.freeAgentMarket.outcomes.single.winningTeamId,
      );
    });

    test('two rounds complete and do not advance the season', () {
      var career = _marketService.startRound(_career());
      career = _marketService.stageHumanOffer(
        career: career,
        teamId: career.userFranchiseId,
        playerId: career.freeAgentPool.entries.first.id,
        category: RosterCategory.standard,
        durationYears: 1,
        firstYearSalary: 1000,
      );
      career = _marketService.prepareResolution(career);
      career = _resolveAll(career);
      expect(
        career.freeAgentMarket.status,
        FreeAgentMarketStatus.roundComplete,
      );
      expect(career.freeAgentMarket.completedRounds, 1);
      expect(career.freeAgentMarket.roundHistory.length, 1);
      final firstRoundOffers =
          career.freeAgentMarket.roundHistory.single.humanOffers.length;
      expect(firstRoundOffers, 1);
      expect(
        career.freeAgentMarket.roundHistory.single.outcomes.length,
        career.freeAgentMarket.roundHistory.single.resolutionOrder.length,
      );

      career = _marketService.startRound(career);
      expect(career.freeAgentMarket.roundNumber, 2);
      expect(
        career.freeAgentMarket.status,
        FreeAgentMarketStatus.collectingHumanOffers,
      );
      career = _marketService.prepareResolution(career);
      career = _resolveAll(career);
      expect(
        career.freeAgentMarket.status,
        FreeAgentMarketStatus.marketComplete,
      );
      expect(career.freeAgentMarket.completedRounds, 2);
      expect(career.freeAgentMarket.roundHistory.length, 2);
      expect(career.currentYear, 1);
      final encoded = GmCareerCodec.encode(career);
      final roundTrip = GmCareerCodec.decode(encoded);
      expect(
        jsonEncode(
          roundTrip.freeAgentMarket.roundHistory
              .map((r) => r.toJson())
              .toList(),
        ),
        jsonEncode(
          career.freeAgentMarket.roundHistory.map((r) => r.toJson()).toList(),
        ),
      );
      final acquiredIds = career.freeAgentPool.acquisitions.entries.values
          .map((record) => record.playerId.value)
          .toList();
      expect(acquiredIds.toSet().length, acquiredIds.length);
    });

    test('round progress survives save/load and resumes deterministically', () {
      var career = _marketService.startRound(_career());
      career = _marketService.prepareResolution(career);
      if (career.freeAgentMarket.resolutionOrder.isEmpty) return;
      career = _marketService.resolveNext(career);
      final encoded = GmCareerCodec.encode(career);
      final decoded = GmCareerCodec.decode(encoded);
      expect(
        decoded.freeAgentMarket.nextResolutionIndex,
        career.freeAgentMarket.nextResolutionIndex,
      );
      final completed = _resolveAll(decoded);
      expect(
        completed.freeAgentMarket.status,
        FreeAgentMarketStatus.roundComplete,
      );
      final finalRoundTrip = GmCareerCodec.decode(
        GmCareerCodec.encode(completed),
      );
      expect(
        jsonEncode(finalRoundTrip.freeAgentMarket.toJson()),
        jsonEncode(completed.freeAgentMarket.toJson()),
      );
    });

    test('identical rejected offer is blocked in a later round', () {
      final base = _career();
      final player = base.freeAgentPool.entries.firstWhere(
        (entry) => entry.player.attributes.overallRating >= 75,
      );
      var career = base.copyWith(
        freeAgentMarket: _preparedState(
          career: base,
          playerId: player.id,
          humanOffers: [
            _offer(
              teamId: base.userFranchiseId,
              playerId: player.id,
              salary: 400,
              source: FreeAgentMarketOfferSource.human,
            ),
          ],
          aiOffers: const [],
        ),
      );
      career = _resolveAll(career);
      expect(
        career.freeAgentOffers.attemptsFor(
          teamId: career.userFranchiseId,
          playerId: player.id,
          seasonYear: 1,
        ),
        isNotEmpty,
      );
      career = _marketService.startRound(career);
      expect(
        () => _marketService.stageHumanOffer(
          career: career,
          teamId: career.userFranchiseId,
          playerId: player.id,
          category: RosterCategory.standard,
          durationYears: 1,
          firstYearSalary: 400,
        ),
        throwsA(
          isA<DomainValidationException>().having(
            (error) => error.codes,
            'codes',
            contains(ValidationCode.freeAgentOfferDuplicate),
          ),
        ),
      );
    });

    test('player rejection is durable and consumes an attempt', () {
      final base = _career();
      final player = base.freeAgentPool.entries.firstWhere(
        (entry) => entry.player.attributes.overallRating >= 75,
      );
      final career = base.copyWith(
        freeAgentMarket: _preparedState(
          career: base,
          playerId: player.id,
          humanOffers: [
            _offer(
              teamId: base.userFranchiseId,
              playerId: player.id,
              salary: 400,
              source: FreeAgentMarketOfferSource.human,
            ),
          ],
          aiOffers: const [],
        ),
      );
      final resolved = _resolveAll(career);
      final outcome = resolved.freeAgentMarket.outcomes.single;
      expect(outcome.winningTeamId, isNull);
      expect(
        outcome.results.single.outcome,
        FreeAgentMarketOfferOutcome.rejected,
      );
      expect(
        resolved.freeAgentOffers
            .attemptsFor(
              teamId: base.userFranchiseId,
              playerId: player.id,
              seasonYear: 1,
            )
            .single
            .outcome,
        isNot(FreeAgentOfferOutcome.accepted),
      );
      expect(resolved.freeAgentPool.length, 90);
    });

    test('financially illegal offer is unavailable, not a rejection', () {
      final base = _career(situation: FranchiseSituation.contender);
      final player = base.freeAgentPool.entries.first;
      final financialCareer = GmCareer.fromSetupResult(
        const CareerSetupService().generate(
          CareerSetupRequest(
            selectedTeamId: TeamId('team-19'),
            selectedSituation: FranchiseSituation.contender,
            seed: _seed,
          ),
        ),
        id: 't08g-financial',
      );
      final o = _offer(
        teamId: financialCareer.userFranchiseId,
        playerId: player.id,
        salary: 2000,
        source: FreeAgentMarketOfferSource.human,
      );
      final career = financialCareer.copyWith(
        freeAgentMarket: FreeAgentMarketState(
          status: FreeAgentMarketStatus.preparedForResolution,
          roundNumber: 1,
          seasonYear: 1,
          humanOffers: [o],
          aiOffers: const [],
          resolutionOrder: [player.id],
          nextResolutionIndex: 0,
          outcomes: const [],
          completedRounds: 0,
        ),
      );
      final resolved = _resolveAll(career);
      expect(
        resolved.freeAgentMarket.outcomes.single.results.single.outcome,
        FreeAgentMarketOfferOutcome.financiallyUnavailable,
      );
      expect(
        resolved.freeAgentOffers.attemptsFor(
          teamId: financialCareer.userFranchiseId,
          playerId: player.id,
          seasonYear: 1,
        ),
        isEmpty,
      );
    });

    test('hidden potential/trajectory cannot change AI offers', () {
      final base = _career();
      final first = _marketService.startRound(base);
      final sealedA = _marketService.prepareResolution(first);
      final target = base.freeAgentPool.entries.first;
      final alteredPool = FreeAgentPool(
        entries: [
          for (final entry in base.freeAgentPool.entries)
            entry.id == target.id
                ? FreeAgentEntry(
                    player: entry.player,
                    profile: PlayerCareerProfile(
                      playerId: entry.id,
                      age: entry.profile.age,
                      potential: 99,
                      trajectory: DevelopmentTrajectory.volatile,
                    ),
                  )
                : entry,
        ],
        initialPlayerIds: base.freeAgentPool.initialPlayerIds,
        acquisitions: base.freeAgentPool.acquisitions,
      );
      final alteredCareer = base.copyWith(freeAgentPool: alteredPool);
      final seededAltered = _marketService.startRound(alteredCareer);
      final sealedB = _marketService.prepareResolution(seededAltered);
      expect(
        jsonEncode(
          sealedB.freeAgentMarket.aiOffers.map((o) => o.toJson()).toList(),
        ),
        jsonEncode(
          sealedA.freeAgentMarket.aiOffers.map((o) => o.toJson()).toList(),
        ),
      );
    });

    test('malformed outcome sets are rejected', () {
      final base = _career();
      final player = base.freeAgentPool.entries.first;
      final human = _offer(
        teamId: base.userFranchiseId,
        playerId: player.id,
        salary: 1000,
        source: FreeAgentMarketOfferSource.human,
      );
      final aiTeam = base.league.teams.firstWhere(
        (team) => team.id != base.userFranchiseId,
      );
      final ai = _offer(
        teamId: aiTeam.id,
        playerId: player.id,
        salary: 1000,
        source: FreeAgentMarketOfferSource.ai,
      );
      FreeAgentMarketOutcome outcome(
        List<FreeAgentMarketOfferResult> results,
      ) => FreeAgentMarketOutcome(
        playerId: player.id,
        winningTeamId: null,
        winningOfferId: null,
        results: results,
      );
      final missing = outcome([
        FreeAgentMarketOfferResult(
          offerId: human.offerId,
          teamId: human.teamId,
          outcome: FreeAgentMarketOfferOutcome.outbid,
          reasonCode: 'outbid',
        ),
      ]);
      final duplicate = outcome([
        FreeAgentMarketOfferResult(
          offerId: human.offerId,
          teamId: human.teamId,
          outcome: FreeAgentMarketOfferOutcome.outbid,
          reasonCode: 'outbid',
        ),
        FreeAgentMarketOfferResult(
          offerId: human.offerId,
          teamId: human.teamId,
          outcome: FreeAgentMarketOfferOutcome.outbid,
          reasonCode: 'outbid',
        ),
        FreeAgentMarketOfferResult(
          offerId: ai.offerId,
          teamId: ai.teamId,
          outcome: FreeAgentMarketOfferOutcome.outbid,
          reasonCode: 'outbid',
        ),
      ]);
      final wrongTeam = outcome([
        FreeAgentMarketOfferResult(
          offerId: human.offerId,
          teamId: ai.teamId,
          outcome: FreeAgentMarketOfferOutcome.outbid,
          reasonCode: 'outbid',
        ),
        FreeAgentMarketOfferResult(
          offerId: ai.offerId,
          teamId: ai.teamId,
          outcome: FreeAgentMarketOfferOutcome.outbid,
          reasonCode: 'outbid',
        ),
      ]);
      for (final malformed in [missing, duplicate, wrongTeam]) {
        expect(
          () => FreeAgentMarketState(
            status: FreeAgentMarketStatus.roundComplete,
            roundNumber: 1,
            seasonYear: 1,
            humanOffers: [human],
            aiOffers: [ai],
            resolutionOrder: [player.id],
            nextResolutionIndex: 1,
            outcomes: [malformed],
            completedRounds: 1,
          ),
          throwsA(isA<DomainValidationException>()),
        );
      }
    });

    test('v10 historical signings survive market initialization', () {
      final base = _career();
      final player = base.freeAgentPool.entries.firstWhere(
        (entry) => entry.player.attributes.overallRating >= 60,
      );
      final valuation = _value.estimate(player.toPublicView());
      final signed = const FreeAgentOfferSubmissionService().submit(
        career: base,
        teamId: base.userFranchiseId,
        freeAgentId: player.id,
        category: RosterCategory.standard,
        durationYears: valuation.preferredDurationYears,
        agreedFirstYearSalary: valuation.acceptableMaximum,
      );
      final json =
          jsonDecode(GmCareerCodec.encode(signed.career))
                as Map<String, dynamic>
            ..['schemaVersion'] = 10
            ..remove('freeAgentMarket');
      final migrated = GmCareerCodec.decode(jsonEncode(json));
      expect(migrated.schemaVersion, 13);
      expect(migrated.freeAgentMarket.status, FreeAgentMarketStatus.notStarted);
      expect(migrated.freeAgentPool.acquisitions.length, 1);
      expect(migrated.freeAgentOffers.length, 1);
      expect(migrated.freeAgentPool.length, 89);
    });

    test('v1-v11 migrate to an empty market; v13 requires it', () {
      final base =
          jsonDecode(GmCareerCodec.encode(_career())) as Map<String, dynamic>;
      for (var version = 1; version <= 10; version++) {
        final older = Map<String, dynamic>.from(base)
          ..['schemaVersion'] = version
          ..remove('freeAgentMarket');
        final migrated = GmCareerCodec.decode(jsonEncode(older));
        expect(migrated.schemaVersion, 13);
        expect(
          migrated.freeAgentMarket.status,
          FreeAgentMarketStatus.notStarted,
        );
      }
      final legacyV11 = jsonDecode(jsonEncode(base)) as Map<String, dynamic>
        ..['schemaVersion'] = 11;
      ((legacyV11['freeAgentMarket'] as Map<String, dynamic>)).remove(
        'roundHistory',
      );
      final legacy = GmCareerCodec.decode(jsonEncode(legacyV11));
      expect(legacy.schemaVersion, 13);
      expect(legacy.freeAgentMarket.roundHistory, isEmpty);

      final missing = Map<String, dynamic>.from(base)
        ..remove('freeAgentMarket');
      expect(
        () => GmCareerCodec.decode(jsonEncode(missing)),
        throwsFormatException,
      );
      final missingHistory = Map<String, dynamic>.from(base);
      ((missingHistory['freeAgentMarket'] as Map<String, dynamic>)).remove(
        'roundHistory',
      );
      expect(
        () => GmCareerCodec.decode(jsonEncode(missingHistory)),
        throwsFormatException,
      );
    });
  });
}
