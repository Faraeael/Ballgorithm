import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _seed = 20261028;
const _market = FreeAgentMarketValueService();

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

Future<FreeAgentOfferSubmissionResult> _acceptedOffer(
  GmCareerController controller,
  PlayerId id,
) {
  final view = controller.career!.freeAgentPool.byId(id)!.toPublicView();
  final valuation = _market.estimate(view);
  return controller.submitFreeAgentOffer(
    freeAgentId: id,
    category: RosterCategory.standard,
    durationYears: valuation.preferredDurationYears,
    agreedFirstYearSalary: valuation.acceptableMaximum,
  );
}

void main() {
  test('controller persists accepted offer and reload preserves it', () async {
    final storage = InMemoryGmCareerStorage();
    final controller = await _loadedController(storage);
    addTearDown(controller.dispose);
    final freeAgentId = controller.career!.freeAgentPool.entries.first.id;

    final result = await _acceptedOffer(controller, freeAgentId);
    expect(result.status, FreeAgentOfferSubmissionStatus.accepted);
    expect(result.recorded, isTrue);
    expect(controller.career!.freeAgentPool.length, 89);
    expect(controller.career!.freeAgentPool.acquisitions.length, 1);
    expect(controller.career!.freeAgentOffers.length, 1);

    final reloaded = GmCareerController(storage: storage);
    addTearDown(reloaded.dispose);
    await reloaded.loadCareer();
    expect(reloaded.career!.freeAgentPool.length, 89);
    expect(
      reloaded.career!.freeAgentPool.acquisitions.forPlayer(freeAgentId),
      isNotNull,
    );
    expect(
      reloaded.career!.freeAgentOffers
          .attemptsFor(
            teamId: reloaded.career!.userFranchiseId,
            playerId: freeAgentId,
            seasonYear: 1,
          )
          .single
          .outcome,
      FreeAgentOfferOutcome.accepted,
    );
  });

  test('duplicate queued submissions acquire only once', () async {
    final storage = InMemoryGmCareerStorage();
    final controller = await _loadedController(storage);
    addTearDown(controller.dispose);
    final freeAgentId = controller.career!.freeAgentPool.entries.first.id;
    final view = controller.career!.freeAgentPool
        .byId(freeAgentId)!
        .toPublicView();
    final valuation = _market.estimate(view);

    final first = controller.submitFreeAgentOffer(
      freeAgentId: freeAgentId,
      category: RosterCategory.standard,
      durationYears: valuation.preferredDurationYears,
      agreedFirstYearSalary: valuation.acceptableMaximum,
    );
    final second = controller.submitFreeAgentOffer(
      freeAgentId: freeAgentId,
      category: RosterCategory.standard,
      durationYears: valuation.preferredDurationYears,
      agreedFirstYearSalary: valuation.acceptableMaximum,
    );
    await first;
    await expectLater(second, throwsStateError);
    expect(controller.career!.freeAgentPool.length, 89);
    expect(controller.career!.freeAgentPool.acquisitions.length, 1);
    expect(controller.career!.freeAgentOffers.length, 1);
  });

  test('failed write keeps prior career and blocks further commands', () async {
    final storage = InMemoryGmCareerStorage();
    final controller = await _loadedController(storage);
    addTearDown(controller.dispose);
    final freeAgentId = controller.career!.freeAgentPool.entries.first.id;
    final view = controller.career!.freeAgentPool
        .byId(freeAgentId)!
        .toPublicView();
    final valuation = _market.estimate(view);
    storage.shouldThrowOnWrite = true;

    await expectLater(
      _acceptedOffer(controller, freeAgentId),
      throwsA(isA<GmCareerStorageException>()),
    );
    expect(controller.career!.freeAgentPool.length, 90);
    expect(controller.career!.freeAgentPool.acquisitions.length, 0);
    expect(controller.career!.freeAgentOffers.length, 0);
    expect(controller.draftRecoveryRequired, isTrue);
    await expectLater(
      controller.submitFreeAgentOffer(
        freeAgentId: freeAgentId,
        category: RosterCategory.standard,
        durationYears: valuation.preferredDurationYears,
        agreedFirstYearSalary: valuation.acceptableMaximum,
      ),
      throwsStateError,
    );

    storage.shouldThrowOnWrite = false;
    await controller.loadCareer();
    expect(controller.draftRecoveryRequired, isFalse);
    expect(controller.career!.freeAgentPool.length, 90);
    expect(controller.career!.freeAgentOffers.length, 0);
  });
}
