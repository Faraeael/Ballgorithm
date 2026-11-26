import 'package:basketball_manager/features/career/career_controller.dart';
import 'package:basketball_manager/features/career/career_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simulation_core/simulation_core.dart';

const _user = TeamId('team-1');

int _pickValue(int slot) => switch (slot) {
  <= 5 => 96,
  <= 14 => 64,
  <= 30 => 36,
  <= 45 => 14,
  _ => 5,
};

class _Storage extends InMemoryGmCareerStorage {
  _Storage(String initial) : super({'default': initial});

  int writes = 0;
  bool fail = false;
  bool persistBeforeFailure = false;

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    writes++;
    if (!fail || persistBeforeFailure) await super.write(data, slot: slot);
    if (fail) throw StateError('write failed');
  }
}

PlayerTradeProposal _offer(GmCareer career) {
  final offered = career.draftOrder.picks
      .where((pick) => pick.currentOwnerTeamId == _user)
      .toList();
  final requested =
      career.draftOrder.picks
          .where((pick) => pick.currentOwnerTeamId != _user)
          .toList()
        ..sort(
          (a, b) =>
              _pickValue(a.overallPick).compareTo(_pickValue(b.overallPick)),
        );
  final pick = requested.first;
  return PlayerTradeProposal(
    careerId: career.id,
    seasonYear: career.currentYear,
    expectedTradeCount: career.tradeHistory.length,
    firstTeam: _user,
    secondTeam: pick.currentOwnerTeamId,
    picksFromFirst: [
      for (final item in offered)
        (
          draftYear: career.currentYear,
          overallPick: item.overallPick,
          expectedOwner: _user,
        ),
    ],
    picksFromSecond: [
      (
        draftYear: career.currentYear,
        overallPick: pick.overallPick,
        expectedOwner: pick.currentOwnerTeamId,
      ),
    ],
  );
}

void main() {
  late String initial;
  setUpAll(() {
    final career = GmCareer.fromSetupResult(
      const CareerSetupService().generate(
        const CareerSetupRequest(
          selectedTeamId: _user,
          selectedSituation: FranchiseSituation.tanking,
          seed: 20261028,
        ),
      ),
    );
    initial = GmCareerCodec.encode(career);
  });

  Future<(GmCareerController, _Storage)> open() async {
    final storage = _Storage(initial);
    final controller = GmCareerController(storage: storage);
    await controller.loadCareer();
    addTearDown(controller.dispose);
    return (controller, storage);
  }

  test(
    'preview is read-only; accepted trade saves once and rejects reuse',
    () async {
      final (controller, storage) = await open();
      final proposal = _offer(controller.career!);
      final before = controller.career;
      final quote = controller.evaluateTrade(proposal);
      expect(quote.status, TradeOfferStatus.legalAccepted);
      expect(identical(controller.career, before), isTrue);
      expect(storage.writes, 0);
      await controller.executeTrade(proposal, quote);
      expect(controller.career!.tradeHistory, hasLength(1));
      expect(
        GmCareerCodec.decode((await storage.read())!).tradeHistory,
        hasLength(1),
      );
      final reversed = PlayerTradeProposal(
        careerId: proposal.careerId,
        seasonYear: proposal.seasonYear,
        expectedTradeCount: 1,
        firstTeam: proposal.firstTeam,
        secondTeam: proposal.secondTeam,
        picksFromFirst: [
          for (final pick in proposal.picksFromSecond)
            (
              draftYear: pick.draftYear,
              overallPick: pick.overallPick,
              expectedOwner: proposal.firstTeam,
            ),
        ],
        picksFromSecond: [
          for (final pick in proposal.picksFromFirst)
            (
              draftYear: pick.draftYear,
              overallPick: pick.overallPick,
              expectedOwner: proposal.secondTeam,
            ),
        ],
      );
      final reverseQuote = controller.evaluateTrade(reversed);
      expect(reverseQuote.status, TradeOfferStatus.illegal);
      expect(reverseQuote.legalReason, PlayerTradeRejection.alreadyTraded);
      await expectLater(
        controller.executeTrade(proposal, quote),
        throwsA(isA<TradeQuoteRejected>()),
      );
      expect(storage.writes, 1);
    },
  );

  test('reload makes a quote stale and busy execution is rejected', () async {
    final (controller, storage) = await open();
    final proposal = _offer(controller.career!);
    final quote = controller.evaluateTrade(proposal);
    await controller.loadCareer();
    await expectLater(
      controller.executeTrade(proposal, quote),
      throwsA(isA<TradeQuoteRejected>()),
    );
    final fresh = controller.evaluateTrade(proposal);
    final loading = controller.loadCareer();
    await expectLater(
      controller.executeTrade(proposal, fresh),
      throwsA(isA<StateError>()),
    );
    await loading;
    expect(storage.writes, 0);
  });

  for (final uncertain in [false, true]) {
    test(
      'failed save locks trade until reload (uncertain: $uncertain)',
      () async {
        final (controller, storage) = await open();
        final proposal = _offer(controller.career!);
        final quote = controller.evaluateTrade(proposal);
        final before = controller.career;
        storage.fail = true;
        storage.persistBeforeFailure = uncertain;
        await expectLater(
          controller.executeTrade(proposal, quote),
          throwsA(isA<StateError>()),
        );
        expect(identical(controller.career, before), isTrue);
        expect(controller.draftRecoveryRequired, isTrue);
        await expectLater(
          controller.executeTrade(proposal, quote),
          throwsA(isA<StateError>()),
        );
        expect(storage.writes, 1);
        storage.fail = false;
        await controller.loadCareer();
        expect(controller.draftRecoveryRequired, isFalse);
        expect(controller.career!.tradeHistory, hasLength(uncertain ? 1 : 0));
        await expectLater(
          controller.executeTrade(proposal, quote),
          throwsA(isA<TradeQuoteRejected>()),
        );
        expect(storage.writes, 1);
      },
    );
  }
}
