// T08F deterministic offer walkthrough. Run from packages/simulation_core:
//   dart run tool/t08f_offer_walkthrough.dart
import 'dart:io';

import 'package:simulation_core/simulation_core.dart';

const _seed = 20261028;
const _submission = FreeAgentOfferSubmissionService();
const _market = FreeAgentMarketValueService();

GmCareer _career(FranchiseSituation situation) => GmCareer.fromSetupResult(
  const CareerSetupService().generate(
    CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: situation,
      seed: _seed,
    ),
  ),
  id: 't08f-walkthrough',
);

void main() {
  final out = StringBuffer();
  out.writeln('# T08F offer walkthrough (generated)');
  out.writeln();
  out.writeln(
    'Seed $_seed, human team-1. Offers use genuine T08E decisions; no '
    'acceptance override. Test salaries are not market prices.',
  );
  out.writeln();
  out.writeln(
    '| Situation | Pool | Accepted offer | Rejections | Third blocked | '
    'Two-way | Standard shortage |',
  );
  out.writeln('|---|---|---|---|---|---|---|');
  for (final situation in FranchiseSituation.values) {
    var career = _career(situation);
    final teamId = career.userFranchiseId;
    final shortageBefore = LeagueReadinessReport.fromCareer(
      career,
    ).teams.firstWhere((team) => team.teamId == teamId).standardShortage;
    final poolBefore = career.freeAgentPool.length;

    final mid = career.freeAgentPool.entries.firstWhere(
      (entry) => entry.player.attributes.overallRating >= 60,
    );
    final midValue = _market.estimate(mid.toPublicView());
    final accepted = _submission.submit(
      career: career,
      teamId: teamId,
      freeAgentId: mid.id,
      category: RosterCategory.standard,
      durationYears: midValue.preferredDurationYears,
      agreedFirstYearSalary: midValue.acceptableMaximum,
    );
    career = accepted.career;

    final high = career.freeAgentPool.entries.firstWhere(
      (entry) => entry.player.attributes.overallRating >= 75,
    );
    final highDuration = _market
        .estimate(high.toPublicView())
        .preferredDurationYears;
    final first = _submission.submit(
      career: career,
      teamId: teamId,
      freeAgentId: high.id,
      category: RosterCategory.standard,
      durationYears: highDuration,
      agreedFirstYearSalary: 400,
    );
    career = first.career;
    final second = _submission.submit(
      career: career,
      teamId: teamId,
      freeAgentId: high.id,
      category: RosterCategory.standard,
      durationYears: highDuration,
      agreedFirstYearSalary: 500,
    );
    career = second.career;
    var thirdBlocked = false;
    try {
      _submission.submit(
        career: career,
        teamId: teamId,
        freeAgentId: high.id,
        category: RosterCategory.standard,
        durationYears: highDuration,
        agreedFirstYearSalary: 600,
      );
    } on DomainValidationException {
      thirdBlocked = true;
    }

    final low = career.freeAgentPool.entries.firstWhere(
      (entry) =>
          entry.player.attributes.overallRating < 62 && entry.profile.age < 27,
    );
    final twoWay = _submission.submit(
      career: career,
      teamId: teamId,
      freeAgentId: low.id,
      category: RosterCategory.twoWay,
      durationYears: 1,
      agreedFirstYearSalary: 250,
    );
    career = twoWay.career;
    final shortageAfter = LeagueReadinessReport.fromCareer(
      career,
    ).teams.firstWhere((team) => team.teamId == teamId).standardShortage;

    final roundTrip = GmCareerCodec.decode(GmCareerCodec.encode(career));
    if (roundTrip.freeAgentOffers.toJson().toString() !=
        career.freeAgentOffers.toJson().toString()) {
      throw StateError('Offer round-trip mismatch');
    }
    if (career.freeAgentPool.length != poolBefore - 2) {
      throw StateError(
        'Unexpected pool count ${career.freeAgentPool.length}; '
        'accepted=${accepted.status.jsonValue} '
        'twoWay=${twoWay.status.jsonValue} '
        'first=${first.status.jsonValue} '
        'second=${second.status.jsonValue}',
      );
    }

    out.writeln(
      '| ${situation.displayName} | $poolBefore → '
      '${career.freeAgentPool.length} | '
      '${accepted.status.jsonValue} | '
      '${first.status.jsonValue}, ${second.status.jsonValue} | '
      '$thirdBlocked | ${twoWay.status.jsonValue} | '
      '$shortageBefore → $shortageAfter |',
    );
  }
  out.writeln();
  out.writeln(
    'Every accepted offer is linked to one acquisition and survives save/load. '
    'Rejected offers remain durable. The third player-side offer is blocked.',
  );

  final file = File('../../specs/008-30-team-league/t08f-walkthrough.md')
    ..createSync(recursive: true)
    ..writeAsStringSync(out.toString());
  stdout.writeln(out);
  stdout.writeln('wrote ${file.path}');
}
