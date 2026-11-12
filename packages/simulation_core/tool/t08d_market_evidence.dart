// T08D deterministic evidence. Run from packages/simulation_core:
//   dart run tool/t08d_market_evidence.dart
import 'dart:convert';
import 'dart:io';

import 'package:simulation_core/simulation_core.dart';

const _seed = 20261028;
const _service = FreeAgentAcquisitionService();

GmCareer _career(FranchiseSituation situation, {String team = 'team-1'}) =>
    GmCareer.fromSetupResult(
      const CareerSetupService().generate(
        CareerSetupRequest(
          selectedTeamId: TeamId(team),
          selectedSituation: situation,
          seed: _seed,
        ),
      ),
      id: 't08d-evidence',
    );

String _cash(int value) => value > 0 ? '+$value' : '$value';

void main() {
  final out = StringBuffer();
  out.writeln('# T08D market evidence (generated)');
  out.writeln();
  out.writeln(
    'Seed $_seed, human team-1, explicit terms: standard 400 CU / 1 year. '
    'Terms are test inputs, not market prices.',
  );
  out.writeln();
  out.writeln(
    '| Situation | Pool before | Initial IDs | Acquired | Pool after 1 | '
    'Pool after 2 | Cap delta | Cash delta | Shortage before → after |',
  );
  out.writeln('|---|---|---|---|---|---|---|---|---|');
  for (final situation in FranchiseSituation.values) {
    var career = _career(situation);
    final teamId = career.userFranchiseId;
    final initialIds = career.freeAgentPool.initialPlayerIds.length;
    final beforePool = career.freeAgentPool.length;
    final capBefore = career.finances.capPayrollFor(teamId, 1);
    final cashBefore = career.finances.projectedEndOfSeasonCash(teamId, 1);
    final shortageBefore = LeagueReadinessReport.fromCareer(
      career,
    ).teams.firstWhere((team) => team.teamId == teamId).standardShortage;
    final first = career.freeAgentPool.entries.first.id;
    final firstEntry = career.freeAgentPool.byId(first)!;

    career = _service.acquire(
      career: career,
      teamId: teamId,
      freeAgentId: first,
      category: RosterCategory.standard,
      durationYears: 1,
      agreedFirstYearSalary: 400,
    );
    final afterOne = career.freeAgentPool.length;
    final second = career.freeAgentPool.entries.first.id;
    career = _service.acquire(
      career: career,
      teamId: teamId,
      freeAgentId: second,
      category: RosterCategory.standard,
      durationYears: 1,
      agreedFirstYearSalary: 400,
    );
    final afterTwo = career.freeAgentPool.length;
    final shortageAfter = LeagueReadinessReport.fromCareer(
      career,
    ).teams.firstWhere((team) => team.teamId == teamId).standardShortage;
    final capAfter = career.finances.capPayrollFor(teamId, 1);
    final cashAfter = career.finances.projectedEndOfSeasonCash(teamId, 1);

    final player = career.userTeam.players.firstWhere(
      (candidate) => candidate.id == first,
    );
    if (player.firstName != firstEntry.player.firstName ||
        player.attributes.asMap.toString() !=
            firstEntry.player.attributes.asMap.toString()) {
      throw StateError('Player identity changed for ${first.value}');
    }
    final roundTrip = GmCareerCodec.decode(GmCareerCodec.encode(career));
    if (jsonEncode(roundTrip.freeAgentPool.toJson()) !=
        jsonEncode(career.freeAgentPool.toJson())) {
      throw StateError('Pool round-trip mismatch');
    }
    out.writeln(
      '| ${situation.displayName} | $beforePool | $initialIds | '
      '${career.freeAgentPool.acquisitions.length} | $afterOne | $afterTwo | '
      '+${capAfter - capBefore} | ${_cash(cashAfter - cashBefore)} | '
      '$shortageBefore → $shortageAfter |',
    );
  }

  // Rejected examples.
  final capRejected = _career(FranchiseSituation.contender, team: 'team-19');
  final capId = capRejected.freeAgentPool.entries.first.id;
  String capOutcome;
  try {
    _service.acquire(
      career: capRejected,
      teamId: capRejected.userFranchiseId,
      freeAgentId: capId,
      category: RosterCategory.standard,
      durationYears: 1,
      agreedFirstYearSalary: 2000,
    );
    capOutcome = 'unexpected success';
  } on DomainValidationException catch (error) {
    capOutcome = error.codes.map((code) => code.name).join(',');
  }

  final doubleWayRejected = _career(FranchiseSituation.playIn);
  final doubleWayId = doubleWayRejected.freeAgentPool.entries.first.id;
  String doubleWayOutcome;
  try {
    _service.acquire(
      career: doubleWayRejected,
      teamId: doubleWayRejected.userFranchiseId,
      freeAgentId: doubleWayId,
      category: RosterCategory.twoWay,
      durationYears: 1,
      agreedFirstYearSalary: 251,
    );
    doubleWayOutcome = 'unexpected success';
  } on DomainValidationException catch (error) {
    doubleWayOutcome = error.codes.map((code) => code.name).join(',');
  }

  out.writeln();
  out.writeln('## Rejected examples');
  out.writeln();
  out.writeln('- Cap: contender team-19, 2,000 CU offer → `$capOutcome`.');
  out.writeln('- Two-way salary: 251 CU offer → `$doubleWayOutcome`.');
  out.writeln();
  out.writeln(
    'All four situations preserve identity, ledger, snapshot and '
    'round-trip. Existing contracts are not rewritten.',
  );

  final file = File('../../specs/008-30-team-league/t08d-market-evidence.md')
    ..createSync(recursive: true)
    ..writeAsStringSync(out.toString());
  stdout.writeln(out);
  stdout.writeln('wrote ${file.path}');
}
