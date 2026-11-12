import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:test/test.dart';

import '../support/financial_fixtures.dart';

void main() {
  final initial = GmCareer.fromSetupResult(
    const CareerSetupService().generate(
      CareerSetupRequest(
        selectedTeamId: const TeamId('team-1'),
        selectedSituation: FranchiseSituation.tanking,
        seed: 20261028,
      ),
    ),
    id: 'migration-draft',
  );

  test('writer always emits v11 even for an explicitly older career model', () {
    const service = DraftExecutionService();
    final older = initial.copyWith(schemaVersion: 3);
    final selected = service.makeHumanSelection(
      career: service.startDraft(older),
      prospectId: older.draftClass.rankedFirst.id,
    );
    final encoded = GmCareerCodec.encode(selected);
    expect(jsonDecode(encoded)['schemaVersion'], 11);
    expect(
      GmCareerCodec.decode(
        encoded,
      ).draftExecutionState.selections.single.prospectId,
      older.draftClass.rankedFirst.id,
    );
  });

  test(
    'v3 migration preserves mixed roster categories and every saved field',
    () {
      final team = initial.userTeam;
      final mixed = withBootstrappedTeam(
        initial,
        team.copyWith(
          roster: team.roster
              .withCategory(team.players[0].id, RosterCategory.twoWay)
              .withCategory(team.players[1].id, RosterCategory.trainingCamp),
        ),
      );
      final legacy =
          jsonDecode(GmCareerCodec.encode(mixed)) as Map<String, dynamic>
            ..['schemaVersion'] = 3
            ..remove('draftExecutionState');
      final migrated = GmCareerCodec.decode(jsonEncode(legacy));
      final saved =
          jsonDecode(GmCareerCodec.encode(migrated)) as Map<String, dynamic>;
      for (final entry in legacy.entries) {
        if (entry.key != 'schemaVersion') {
          expect(saved[entry.key], entry.value, reason: entry.key);
        }
      }
      expect(migrated.userTeam.roster.twoWayCount, 1);
      expect(migrated.userTeam.roster.trainingCampCount, 1);
      expect(migrated.draftExecutionState.isNotStarted, isTrue);
    },
  );

  test('v4 requires execution metadata without modifying source data', () {
    final raw =
        jsonDecode(GmCareerCodec.encode(initial)) as Map<String, dynamic>;
    for (final invalid in [null, [], 'invalid']) {
      final corrupt = {...raw, 'draftExecutionState': invalid};
      final source = jsonEncode(corrupt);
      expect(() => GmCareerCodec.decode(source), throwsFormatException);
      expect(jsonEncode(corrupt), source);
    }
    raw.remove('draftExecutionState');
    expect(() => GmCareerCodec.decode(jsonEncode(raw)), throwsFormatException);
  });
}
