// Read-only T08C audit. Regenerate:
//   cd packages/simulation_core && dart run tool/t08c_financial_audit.dart
// Writes ../../specs/008-30-team-league/t08c-financial-audit.md.
import 'dart:io';
import 'dart:math' as math;

import 'package:simulation_core/simulation_core.dart';

const List<int> seeds = [20261028, 1604126146, 987654321];
const List<FranchiseSituation> situations = [
  FranchiseSituation.tanking,
  FranchiseSituation.playIn,
  FranchiseSituation.playoff,
  FranchiseSituation.contender,
];
const List<String> identities = ['team-1', 'team-16'];

String stats(List<int> values) {
  final sorted = [...values]..sort();
  final sum = sorted.fold<int>(0, (a, b) => a + b);
  return '${sorted.first}/${sorted[sorted.length ~/ 2]}/'
      '${(sum / sorted.length).round()}/${sorted.last}';
}

GmCareer _allAiSignings(GmCareer career) {
  const service = RookieAiSigningService();
  var current = service.initialize(career);
  var guard = 0;
  while (service.pendingRights(current).isNotEmpty) {
    current = service.applyNextDecision(current);
    if (++guard > 200) throw StateError('AI signing loop');
  }
  return current;
}

final class RunResult {
  final preCap = <String, List<int>>{};
  final postCap = <String, List<int>>{};
  final postCash = <String, List<int>>{};
  final postRoom = <String, List<int>>{};
  final year2 = <String, List<int>>{};
  final year3 = <String, List<int>>{};
  final humanPrePayroll = <int>[];
  final humanPostPayroll = <int>[];
  final humanRoom = <int>[];
  final humanCash3 = <int>[];
  final overCap = <String>[];
  final cantOneMinimum = <String>[];
  final cantTwoMinimum = <String>[];
  final contractScenarios = <String, String>{};
  final referenceTable = StringBuffer();
  int validations = 0;
}

RunResult runAudit({required bool humanUsesStrategy}) {
  final result = RunResult();
  const strategy = AiDraftStrategy();
  for (final seed in seeds) {
    for (final situation in situations) {
      for (final identity in identities) {
        final setup = const CareerSetupService().generate(
          CareerSetupRequest(
            selectedTeamId: TeamId(identity),
            selectedSituation: situation,
            seed: seed,
          ),
        );
        var career = GmCareer.fromSetupResult(
          setup,
          id: 'audit-$seed-${situation.jsonValue}-$identity',
        );
        career.validate();
        result.validations++;
        final initialContracts = career.finances.contracts.length;
        final initialRookieContracts = career.finances.contracts.values
            .where((c) => c.source == ContractSource.rookie)
            .length;

        for (final team in career.league.teams) {
          (result.preCap[team.situation!.jsonValue] ??= []).add(
            career.finances.capPayrollFor(team.id, career.currentYear),
          );
        }
        final humanPre = career.finances.capPayrollFor(
          career.userFranchiseId,
          career.currentYear,
        );
        result.humanPrePayroll.add(humanPre);

        if (seed == 20261028 &&
            identity == 'team-1' &&
            situation == FranchiseSituation.playIn) {
          for (final team in career.league.teams) {
            final finances = career.finances;
            final cap = finances.capPayrollFor(team.id, career.currentYear);
            final twoWay = finances.twoWayPayrollFor(
              team.id,
              career.currentYear,
            );
            result.referenceTable.writeln(
              '| ${team.id.value} | ${team.abbreviation} | '
              '${team.situation!.displayName} | '
              '${team.roster.standardPlayers.length} | '
              '${team.roster.twoWayPlayers.length} | $cap | $twoWay | '
              '${cap + twoWay} | ${FinancialRules.salaryCap - cap} | '
              '${finances.financesFor(team.id).revenueBaseline} | '
              '${finances.projectedEndOfSeasonCash(team.id, career.currentYear)} |',
            );
          }
        }

        // Draft, with the human pick either first-available or AI strategy.
        const draft = DraftExecutionService();
        career = draft.startDraft(career);
        while (!career.draftExecutionState.isCompleted) {
          final isHuman = career.draftExecutionState.isHumanTurn(
            order: career.draftOrder,
            userTeamId: career.userFranchiseId,
          );
          if (!isHuman) {
            career = draft.executeAiSelection(career);
            continue;
          }
          final available = career.draftExecutionState.availableProspects(
            career.draftClass,
          );
          final prospectId = humanUsesStrategy
              ? strategy
                    .selectBestProspect(
                      availableProspects: available
                          .map((prospect) => prospect.toPublicView())
                          .toList(),
                      team: career.userTeam,
                      situation: career.originalSituation,
                      overallPick: career.draftExecutionState
                          .currentPick(career.draftOrder)!
                          .overallPick,
                      seed: career.generationSeed,
                    )
                    .id
              : available.first.id;
          career = draft.makeHumanSelection(
            career: career,
            prospectId: prospectId,
          );
        }
        final draftedContracts = career.finances.contracts.length;
        career = _allAiSignings(career);
        career.validate();
        result.validations++;

        final signedRookies = career.finances.contracts.values
            .where((c) => c.source == ContractSource.rookie)
            .length;
        if (result.contractScenarios.isEmpty) {
          result.contractScenarios['initialContracts/rookie'] =
              '$initialContracts/$initialRookieContracts';
          result.contractScenarios['draftOnlyContracts'] =
              '$draftedContracts/0';
          result.contractScenarios['afterAiContracts/rookie'] =
              '${career.finances.contracts.length}/$signedRookies';
          result.contractScenarios['rosterPlayers'] = career.league.teams
              .expand((team) => team.players)
              .length
              .toString();
        }

        for (final team in career.league.teams) {
          final situationKey = team.situation!.jsonValue;
          final cap = career.finances.capPayrollFor(
            team.id,
            career.currentYear,
          );
          final twoWay = career.finances.twoWayPayrollFor(
            team.id,
            career.currentYear,
          );
          final room = FinancialRules.salaryCap - cap;
          (result.postCap[situationKey] ??= []).add(cap);
          (result.postCash[situationKey] ??= []).add(cap + twoWay);
          (result.postRoom[situationKey] ??= []).add(room);
          (result.year2[situationKey] ??= []).add(
            career.finances.capPayrollFor(team.id, career.currentYear + 1),
          );
          (result.year3[situationKey] ??= []).add(
            career.finances.capPayrollFor(team.id, career.currentYear + 2),
          );
          if (cap > FinancialRules.salaryCap) {
            result.overCap.add('${team.id.value}=$cap');
          }
          if (room < FinancialRules.minimumSalary) {
            result.cantOneMinimum.add('${team.id.value}=$room');
          }
          if (room < 2 * FinancialRules.minimumSalary) {
            result.cantTwoMinimum.add('${team.id.value}=$room');
          }
        }

        final humanAudit = career.finances;
        final humanId = career.userFranchiseId;
        result.humanPostPayroll.add(
          humanAudit.capPayrollFor(humanId, career.currentYear),
        );
        result.humanRoom.add(
          FinancialRules.salaryCap -
              humanAudit.capPayrollFor(humanId, career.currentYear),
        );
        final finances = humanAudit.financesFor(humanId);
        result.humanCash3.add(
          finances.cash +
              finances.revenueBaseline * 3 -
              humanAudit.capPayrollFor(humanId, career.currentYear) -
              humanAudit.capPayrollFor(humanId, career.currentYear + 1) -
              humanAudit.capPayrollFor(humanId, career.currentYear + 2) -
              humanAudit.operatingCommitmentsFor(humanId) * 3,
        );
      }
    }
  }
  return result;
}

void emit(StringBuffer out, String label, RunResult r) {
  out.writeln('\n### $label');
  out.writeln(
    'Pre-draft cap payroll: ${r.preCap.entries.map((e) => '${e.key} ${stats(e.value)}').join('; ')}',
  );
  out.writeln(
    'Post-draft cap payroll: ${r.postCap.entries.map((e) => '${e.key} ${stats(e.value)}').join('; ')}',
  );
  out.writeln(
    'Post-draft cash payroll: ${r.postCash.entries.map((e) => '${e.key} ${stats(e.value)}').join('; ')}',
  );
  out.writeln(
    'Post-draft cap room: ${r.postRoom.entries.map((e) => '${e.key} ${stats(e.value)}').join('; ')}',
  );
  out.writeln(
    'Year 2 cap payroll: ${r.year2.entries.map((e) => '${e.key} ${stats(e.value)}').join('; ')}',
  );
  out.writeln(
    'Year 3 cap payroll: ${r.year3.entries.map((e) => '${e.key} ${stats(e.value)}').join('; ')}',
  );
  out.writeln('cap over: ${r.overCap.length} ${r.overCap}');
  out.writeln(
    'cannot add one minimum: ${r.cantOneMinimum.length} ${r.cantOneMinimum}',
  );
  out.writeln(
    'cannot add two minimum: ${r.cantTwoMinimum.length} ${r.cantTwoMinimum}',
  );
  out.writeln(
    'human pre/post payroll: '
    '${r.humanPrePayroll.reduce(math.min)}..${r.humanPrePayroll.reduce(math.max)} / '
    '${r.humanPostPayroll.reduce(math.min)}..${r.humanPostPayroll.reduce(math.max)}',
  );
  out.writeln(
    'human cap room: ${r.humanRoom.reduce(math.min)}..${r.humanRoom.reduce(math.max)}',
  );
  out.writeln(
    'human 3-year cash: ${r.humanCash3.reduce(math.min)}..${r.humanCash3.reduce(math.max)}',
  );
  out.writeln('career validations: ${r.validations}');
  out.writeln('contract scenarios (contracts/rookie): ${r.contractScenarios}');
  out.writeln('\nReference table (pre-draft, seed 20261028 team-1 Play-In)');
  out.write(r.referenceTable);
}

void main() {
  final out = StringBuffer();
  out.writeln('# T08C financial audit (generated)');
  out.writeln();
  out.writeln(
    'Read-only reproduction of the T08B-R1 24-league payroll audit using the '
    'implemented T08C financial domain. Regenerate with '
    '`dart run tool/t08c_financial_audit.dart` from `packages/simulation_core`. '
    'No production source is modified by the run.',
  );
  emit(
    out,
    'Variant A: human picks first available',
    runAudit(humanUsesStrategy: false),
  );
  emit(
    out,
    'Variant B: human picks AI strategy',
    runAudit(humanUsesStrategy: true),
  );
  File('../../specs/008-30-team-league/t08c-financial-audit.md')
    ..createSync(recursive: true)
    ..writeAsStringSync(out.toString());
  stdout.writeln(out);
}
