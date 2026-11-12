// T08G deterministic competitive market evidence. Run from packages/simulation_core:
//   dart run tool/t08g_competitive_evidence.dart
import 'dart:io';

import 'package:simulation_core/simulation_core.dart';

const _seeds = [20261028, 1604126146, 987654321];
const _service = FreeAgentMarketService();
const _value = FreeAgentMarketValueService();

GmCareer _career(int seed, FranchiseSituation situation) =>
    GmCareer.fromSetupResult(
      CareerSetupService().generate(
        CareerSetupRequest(
          selectedTeamId: const TeamId('team-1'),
          selectedSituation: situation,
          seed: seed,
        ),
      ),
      id: 't08g-$seed-${situation.jsonValue}',
    );

GmCareer _resolve(GmCareer career) {
  var current = career;
  while (current.freeAgentMarket.isResolvable) {
    current = _service.resolveNext(current);
  }
  return current;
}

({int ready, int below, int shortage}) _readiness(GmCareer career) {
  final report = LeagueReadinessReport.fromCareer(career);
  return (
    ready: report.teams.where((team) => team.isReady).length,
    below: report.teams.where((team) => team.standardCount < 14).length,
    shortage: report.totalStandardShortage,
  );
}

void main() {
  final out = StringBuffer();
  out.writeln('# T08G competitive free-agency evidence (generated)');
  out.writeln();
  out.writeln(
    'Three seeds × four human situations. Two explicit market rounds. '
    'Human offers use the T08E estimate; AI offers use the shared policy. '
    'No acquisition is forced.',
  );
  out.writeln();
  out.writeln(
    '| Seed | Situation | Pool start | Human offers | AI offers | Rejections | Outbids | Human buys | AI buys | Remaining | Ready before→after | Below 14 before→after |',
  );
  out.writeln('|---|---|---|---|---|---|---|---|---|---|---|---|');
  for (final seed in _seeds) {
    for (final situation in FranchiseSituation.values) {
      var career = _career(seed, situation);
      final before = _readiness(career);
      final poolStart = career.freeAgentPool.length;
      career = _service.startRound(career);
      final target = career.freeAgentPool.entries.firstWhere(
        (entry) => entry.player.attributes.overallRating >= 60,
      );
      final value = _value.estimate(target.toPublicView());
      career = _service.stageHumanOffer(
        career: career,
        teamId: career.userFranchiseId,
        playerId: target.id,
        category: RosterCategory.standard,
        durationYears: value.preferredDurationYears,
        firstYearSalary: value.acceptableMaximum,
      );
      career = _service.prepareResolution(career);
      career = _resolve(career);
      final roundOne = career.freeAgentMarket;
      var humanOffers = roundOne.humanOffers.length;
      var aiOffers = roundOne.aiOffers.length;
      var rejectionResults = 0;
      var outbidResults = 0;
      for (final outcome in roundOne.outcomes) {
        rejectionResults += outcome.results
            .where(
              (result) =>
                  result.outcome == FreeAgentMarketOfferOutcome.rejected,
            )
            .length;
        outbidResults += outcome.results
            .where(
              (result) => result.outcome == FreeAgentMarketOfferOutcome.outbid,
            )
            .length;
      }

      career = _service.startRound(career);
      final secondTarget = career.freeAgentPool.entries.firstWhere(
        (entry) => entry.player.attributes.overallRating >= 55,
      );
      final secondValue = _value.estimate(secondTarget.toPublicView());
      try {
        career = _service.stageHumanOffer(
          career: career,
          teamId: career.userFranchiseId,
          playerId: secondTarget.id,
          category: RosterCategory.standard,
          durationYears: secondValue.preferredDurationYears,
          firstYearSalary: secondValue.acceptableMinimum,
        );
      } on DomainValidationException {
        // The human franchise may already be committed after Round 1.
      }
      career = _service.prepareResolution(career);
      career = _resolve(career);
      final roundTwo = career.freeAgentMarket;
      humanOffers += roundTwo.humanOffers.length;
      aiOffers += roundTwo.aiOffers.length;
      for (final outcome in roundTwo.outcomes) {
        rejectionResults += outcome.results
            .where(
              (result) =>
                  result.outcome == FreeAgentMarketOfferOutcome.rejected,
            )
            .length;
        outbidResults += outcome.results
            .where(
              (result) => result.outcome == FreeAgentMarketOfferOutcome.outbid,
            )
            .length;
      }

      final humanBuys = career.freeAgentPool.acquisitions.entries.values
          .where((record) => record.teamId == career.userFranchiseId)
          .length;
      final aiBuys = career.freeAgentPool.acquisitions.length - humanBuys;
      final after = _readiness(career);
      if (!career.freeAgentMarket.isRoundComplete) {
        throw StateError('Market did not complete');
      }
      out.writeln(
        '| $seed | ${situation.displayName} | $poolStart | $humanOffers | '
        '$aiOffers | $rejectionResults | $outbidResults | $humanBuys | '
        '$aiBuys | ${career.freeAgentPool.length} | '
        '${before.ready}→${after.ready} | '
        '${before.below}→${after.below} |',
      );
    }
  }
  out.writeln();
  out.writeln(
    'Each row reports two completed rounds. Outbids are competitive losses, '
    'not player-side rejections.',
  );
  final file = File('../../specs/008-30-team-league/t08g-market-evidence.md')
    ..createSync(recursive: true)
    ..writeAsStringSync(out.toString());
  stdout.writeln(out);
  stdout.writeln('wrote ${file.path}');
}
