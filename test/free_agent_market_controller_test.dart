import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _seed = 20261028;
const _value = FreeAgentMarketValueService();

Future<GmCareerController> _loadedController(
  InMemoryGmCareerStorage storage,
) async {
  final controller = GmCareerController(storage: storage);
  await controller.startCareer(
    const CareerSetupService().generate(
      const CareerSetupRequest(
        selectedTeamId: TeamId('team-1'),
        selectedSituation: FranchiseSituation.playIn,
        seed: _seed,
      ),
    ),
  );
  return controller;
}

void main() {
  test('market round persists pending offers and resolution', () async {
    final storage = InMemoryGmCareerStorage();
    final controller = await _loadedController(storage);
    addTearDown(controller.dispose);
    await controller.startFreeAgencyRound();
    expect(
      controller.career!.freeAgentMarket.status,
      FreeAgentMarketStatus.collectingHumanOffers,
    );
    final player = controller.career!.freeAgentPool.entries.first;
    final valuation = _value.estimate(player.toPublicView());
    await controller.stageFreeAgentOffer(
      freeAgentId: player.id,
      category: RosterCategory.standard,
      durationYears: valuation.preferredDurationYears,
      firstYearSalary: valuation.acceptableMaximum,
    );
    expect(controller.career!.freeAgentMarket.humanOffers.length, 1);
    expect(controller.career!.freeAgentPool.length, 90);

    final reloaded = GmCareerController(storage: storage);
    addTearDown(reloaded.dispose);
    await reloaded.loadCareer();
    expect(reloaded.career!.freeAgentMarket.humanOffers.length, 1);
    await reloaded.prepareFreeAgencyResolution();
    expect(
      reloaded.career!.freeAgentMarket.status,
      FreeAgentMarketStatus.preparedForResolution,
    );
    await reloaded.resolveFreeAgencyRound();
    expect(reloaded.career!.freeAgentMarket.isRoundComplete, isTrue);

    final finalReload = GmCareerController(storage: storage);
    addTearDown(finalReload.dispose);
    await finalReload.loadCareer();
    expect(finalReload.career!.freeAgentMarket.isRoundComplete, isTrue);
    expect(
      finalReload.career!.freeAgentMarket.outcomes.length,
      finalReload.career!.freeAgentMarket.resolutionOrder.length,
    );
  });

  test('failed staging write does not publish a pending offer', () async {
    final storage = InMemoryGmCareerStorage();
    final controller = await _loadedController(storage);
    addTearDown(controller.dispose);
    await controller.startFreeAgencyRound();
    final player = controller.career!.freeAgentPool.entries.first;
    final valuation = _value.estimate(player.toPublicView());
    storage.shouldThrowOnWrite = true;
    await expectLater(
      controller.stageFreeAgentOffer(
        freeAgentId: player.id,
        category: RosterCategory.standard,
        durationYears: valuation.preferredDurationYears,
        firstYearSalary: valuation.acceptableMaximum,
      ),
      throwsA(isA<GmCareerStorageException>()),
    );
    expect(controller.career!.freeAgentMarket.humanOffers, isEmpty);
    expect(controller.draftRecoveryRequired, isTrue);

    storage.shouldThrowOnWrite = false;
    await controller.loadCareer();
    expect(controller.draftRecoveryRequired, isFalse);
    expect(controller.career!.freeAgentMarket.humanOffers, isEmpty);
  });

  test('duplicate resolution submissions cannot replay a round', () async {
    final storage = InMemoryGmCareerStorage();
    final controller = await _loadedController(storage);
    addTearDown(controller.dispose);
    await controller.startFreeAgencyRound();
    await controller.prepareFreeAgencyResolution();
    final first = controller.resolveFreeAgencyRound();
    final second = controller.resolveFreeAgencyRound();
    await first;
    await expectLater(second, throwsStateError);
    expect(controller.career!.freeAgentMarket.isRoundComplete, isTrue);
    final ids = controller.career!.freeAgentPool.acquisitions.entries.values
        .map((record) => record.playerId.value)
        .toList();
    expect(ids.toSet().length, ids.length);
  });

  test('failed resolution write blocks and reload resumes', () async {
    final storage = InMemoryGmCareerStorage();
    final controller = await _loadedController(storage);
    addTearDown(controller.dispose);
    await controller.startFreeAgencyRound();
    await controller.prepareFreeAgencyResolution();
    expect(
      controller.career!.freeAgentMarket.status,
      FreeAgentMarketStatus.preparedForResolution,
    );
    storage.shouldThrowOnWrite = true;
    await expectLater(
      controller.resolveFreeAgencyRound(),
      throwsA(isA<GmCareerStorageException>()),
    );
    expect(controller.draftRecoveryRequired, isTrue);
    expect(
      controller.career!.freeAgentMarket.status,
      FreeAgentMarketStatus.preparedForResolution,
    );

    storage.shouldThrowOnWrite = false;
    await controller.loadCareer();
    await controller.resolveFreeAgencyRound();
    expect(controller.career!.freeAgentMarket.isRoundComplete, isTrue);
  });
}
