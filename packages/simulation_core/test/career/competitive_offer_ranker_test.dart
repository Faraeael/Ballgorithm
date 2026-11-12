import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

const _ranker = CompetitiveOfferRanker();

GmCareer _career() => GmCareer.fromSetupResult(
  const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.playIn,
      seed: 20261028,
    ),
  ),
  id: 't08g-p1-ranker',
);

FreeAgentMarketOffer _offer({
  required TeamId teamId,
  required PlayerId playerId,
  required int salary,
  int duration = 2,
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
  durationYears: duration,
  firstYearSalary: salary,
  source: teamId == const TeamId('team-1')
      ? FreeAgentMarketOfferSource.human
      : FreeAgentMarketOfferSource.ai,
);

List<String> _rank(
  GmCareer career,
  PlayerId playerId,
  List<FreeAgentMarketOffer> offers,
) => _ranker
    .rank(career: career, playerId: playerId, offers: offers)
    .map((offer) => offer.offerId)
    .toList();

void main() {
  group('T08G-P1 competitive offer ranker', () {
    test('three-offer cycle regression is order-independent', () {
      final career = _career();
      final player = career.freeAgentPool.entries.first.id;
      final offers = [
        _offer(teamId: const TeamId('team-1'), playerId: player, salary: 1100),
        _offer(teamId: const TeamId('team-2'), playerId: player, salary: 1000),
        _offer(teamId: const TeamId('team-3'), playerId: player, salary: 900),
      ];
      final baseline = _rank(career, player, offers);
      expect(baseline.length, 3);
      for (final permutation in [
        [offers[0], offers[2], offers[1]],
        [offers[1], offers[0], offers[2]],
        [offers[1], offers[2], offers[0]],
        [offers[2], offers[0], offers[1]],
        [offers[2], offers[1], offers[0]],
      ]) {
        expect(_rank(career, player, permutation), baseline);
      }
    });

    test('comparator is antisymmetric and transitive for a larger set', () {
      final career = _career();
      final player = career.freeAgentPool.entries.first.id;
      final offers = <FreeAgentMarketOffer>[];
      for (var i = 0; i < 6; i++) {
        offers.add(
          _offer(
            teamId: TeamId('team-${i + 1}'),
            playerId: player,
            salary: 800 + i * 137,
            duration: 1 + (i % 4),
          ),
        );
      }
      final rankedIds = _rank(career, player, offers);
      expect(rankedIds.length, offers.length);
      for (var i = 0; i < rankedIds.length; i++) {
        for (var j = i + 1; j < rankedIds.length; j++) {
          final left = offers.firstWhere((o) => o.offerId == rankedIds[i]);
          final right = offers.firstWhere((o) => o.offerId == rankedIds[j]);
          expect(_rank(career, player, [left, right]).first, left.offerId);
          expect(_rank(career, player, [right, left]).first, left.offerId);
        }
      }
    });

    test('ranking is deterministic across repeated calls', () {
      final career = _career();
      final player = career.freeAgentPool.entries.first.id;
      final offers = [
        _offer(teamId: const TeamId('team-1'), playerId: player, salary: 2000),
        _offer(teamId: const TeamId('team-2'), playerId: player, salary: 2000),
        _offer(teamId: const TeamId('team-3'), playerId: player, salary: 2000),
      ];
      expect(_rank(career, player, offers), _rank(career, player, offers));
      expect(
        _rank(career, player, offers.reversed.toList()),
        _rank(career, player, offers),
      );
    });
  });
}
