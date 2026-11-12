import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _seed = 20261028;

Future<GmCareerController> _loadedController(
  InMemoryGmCareerStorage storage,
) async {
  final setup = const CareerSetupService().generate(
    const CareerSetupRequest(
      selectedTeamId: TeamId('team-1'),
      selectedSituation: FranchiseSituation.playIn,
      seed: _seed,
    ),
  );
  final controller = GmCareerController(storage: storage);
  await controller.startCareer(setup);
  return controller;
}

void main() {
  test('controller persists acquisition and reload preserves it', () async {
    final storage = InMemoryGmCareerStorage();
    final controller = await _loadedController(storage);
    addTearDown(controller.dispose);
    final freeAgentId = controller.career!.freeAgentPool.entries.first.id;

    await controller.acquireFreeAgent(
      freeAgentId: freeAgentId,
      category: RosterCategory.standard,
      durationYears: 2,
      agreedFirstYearSalary: 1000,
    );
    expect(controller.career!.freeAgentPool.length, 89);
    expect(controller.career!.freeAgentPool.acquisitions.length, 1);

    final reloaded = GmCareerController(storage: storage);
    addTearDown(reloaded.dispose);
    await reloaded.loadCareer();
    expect(reloaded.career!.freeAgentPool.length, 89);
    expect(
      reloaded.career!.freeAgentPool.acquisitions.forPlayer(freeAgentId),
      isNotNull,
    );
    expect(
      reloaded.career!.userTeam.players.any(
        (player) => player.id == freeAgentId,
      ),
      isTrue,
    );
  });

  test('duplicate queued submissions acquire only once', () async {
    final storage = InMemoryGmCareerStorage();
    final controller = await _loadedController(storage);
    addTearDown(controller.dispose);
    final freeAgentId = controller.career!.freeAgentPool.entries.first.id;

    final first = controller.acquireFreeAgent(
      freeAgentId: freeAgentId,
      category: RosterCategory.standard,
      durationYears: 1,
      agreedFirstYearSalary: 400,
    );
    final second = controller.acquireFreeAgent(
      freeAgentId: freeAgentId,
      category: RosterCategory.standard,
      durationYears: 1,
      agreedFirstYearSalary: 400,
    );
    await first;
    await expectLater(second, throwsStateError);
    expect(controller.career!.freeAgentPool.length, 89);
    expect(controller.career!.freeAgentPool.acquisitions.length, 1);
  });

  test('failed write keeps prior career and blocks further commands', () async {
    final storage = InMemoryGmCareerStorage();
    final controller = await _loadedController(storage);
    addTearDown(controller.dispose);
    final freeAgentId = controller.career!.freeAgentPool.entries.first.id;
    storage.shouldThrowOnWrite = true;

    await expectLater(
      controller.acquireFreeAgent(
        freeAgentId: freeAgentId,
        category: RosterCategory.standard,
        durationYears: 1,
        agreedFirstYearSalary: 400,
      ),
      throwsA(isA<GmCareerStorageException>()),
    );
    expect(controller.career!.freeAgentPool.length, 90);
    expect(controller.career!.freeAgentPool.acquisitions.length, 0);
    expect(controller.draftRecoveryRequired, isTrue);
    await expectLater(
      controller.acquireFreeAgent(
        freeAgentId: freeAgentId,
        category: RosterCategory.standard,
        durationYears: 1,
        agreedFirstYearSalary: 400,
      ),
      throwsStateError,
    );

    storage.shouldThrowOnWrite = false;
    await controller.loadCareer();
    expect(controller.draftRecoveryRequired, isFalse);
    expect(controller.career!.freeAgentPool.length, 90);
  });
}
