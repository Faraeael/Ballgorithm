import 'dart:convert';

import 'package:simulation_core/simulation_core.dart';
import 'package:simulation_core/src/career/trade_record.dart';
import 'package:simulation_core/src/career/trade_service.dart';
import 'package:test/test.dart';

import '../support/career_season_fixtures.dart';

const user = TeamId('team-1');
const opponent = TeamId('team-2');

void main() {
  late GmCareer beforeDraft;
  late GmCareer afterDraft;

  setUpAll(() {
    beforeDraft = GmCareer.fromSetupResult(
      const CareerSetupService().generate(
        const CareerSetupRequest(
          selectedTeamId: user,
          selectedSituation: FranchiseSituation.tanking,
          seed: 20261028,
        ),
      ),
    );
    afterDraft = preFreeAgencyOffseason();
  });

  test('materialized pick exchange persists and new owner selects', () {
    final userPick = beforeDraft.draftOrder.picks.firstWhere(
      (pick) => pick.currentOwnerTeamId == user,
    );
    final opponentPick = beforeDraft.draftOrder.picks.firstWhere(
      (pick) => pick.currentOwnerTeamId == opponent,
    );
    final proposal = PlayerTradeProposal(
      careerId: beforeDraft.id,
      seasonYear: beforeDraft.currentYear,
      expectedTradeCount: 0,
      firstTeam: user,
      secondTeam: opponent,
      picksFromFirst: [
        (
          draftYear: beforeDraft.currentYear,
          overallPick: userPick.overallPick,
          expectedOwner: user,
        ),
      ],
      picksFromSecond: [
        (
          draftYear: beforeDraft.currentYear,
          overallPick: opponentPick.overallPick,
          expectedOwner: opponent,
        ),
      ],
    );
    final traded = PlayerTradeService.buildCandidate(beforeDraft, proposal);
    expect(
      traded.draftOrder.pickAt(userPick.overallPick).currentOwnerTeamId,
      opponent,
    );
    expect(
      traded.draftOrder.pickAt(opponentPick.overallPick).currentOwnerTeamId,
      user,
    );
    final reloaded = GmCareerCodec.decode(GmCareerCodec.encode(traded));
    expect(reloaded.tradeHistory.single.assets, hasLength(2));
    expect(
      reloaded.draftOrder.pickAt(opponentPick.overallPick).currentOwnerTeamId,
      user,
    );

    const draftService = DraftExecutionService();
    var running = draftService.startDraft(reloaded);
    while (running.draftExecutionState.currentOverallPick! <=
        opponentPick.overallPick) {
      if (running.draftExecutionState.isHumanTurn(
        order: running.draftOrder,
        userTeamId: user,
      )) {
        final prospect = running.draftExecutionState
            .availableProspects(running.draftClass)
            .first;
        running = draftService.makeHumanSelection(
          career: running,
          prospectId: prospect.id,
        );
      } else {
        running = draftService.executeAiSelection(running);
      }
    }
    expect(
      running
          .draftExecutionState
          .selections[opponentPick.overallPick - 1]
          .selectingTeamId,
      user,
    );
    expect(
      running
          .draftExecutionState
          .selections[opponentPick.overallPick - 1]
          .originalOwnerTeamId,
      opponentPick.originalOwnerTeamId,
    );
  });

  test('mixed player and pick packages settle together', () {
    PlayerTradeProposal? found;
    GmCareer? settled;
    for (final other in beforeDraft.league.teams.where((t) => t.id != user)) {
      final userPick = beforeDraft.draftOrder.picks.firstWhere(
        (pick) => pick.currentOwnerTeamId == user,
      );
      final otherPick = beforeDraft.draftOrder.picks.firstWhere(
        (pick) => pick.currentOwnerTeamId == other.id,
      );
      for (final outgoing in beforeDraft.userTeam.roster.standardPlayers) {
        for (final incoming in other.roster.standardPlayers) {
          final proposal = PlayerTradeProposal(
            careerId: beforeDraft.id,
            seasonYear: beforeDraft.currentYear,
            expectedTradeCount: 0,
            firstTeam: user,
            secondTeam: other.id,
            fromFirst: [
              (
                playerId: outgoing.id,
                contractId: beforeDraft.finances
                    .contractForPlayer(outgoing.id)!
                    .id,
              ),
            ],
            fromSecond: [
              (
                playerId: incoming.id,
                contractId: beforeDraft.finances
                    .contractForPlayer(incoming.id)!
                    .id,
              ),
            ],
            picksFromFirst: [
              (
                draftYear: beforeDraft.currentYear,
                overallPick: userPick.overallPick,
                expectedOwner: user,
              ),
            ],
            picksFromSecond: [
              (
                draftYear: beforeDraft.currentYear,
                overallPick: otherPick.overallPick,
                expectedOwner: other.id,
              ),
            ],
          );
          try {
            settled = PlayerTradeService.buildCandidate(beforeDraft, proposal);
            found = proposal;
            break;
          } on PlayerTradeRejected {
            continue;
          }
        }
        if (found != null) break;
      }
      if (found != null) break;
    }
    expect(found, isNotNull);
    final receipt = settled!.tradeHistory.single;
    expect(receipt.assets.map((asset) => asset.kind.name), [
      'player',
      'player',
      'pick',
      'pick',
    ]);
    expect(
      receipt.assets.where((asset) => asset.kind.name == 'pick'),
      hasLength(2),
    );
    expect(
      receipt.assets.where((asset) => asset.kind.name == 'player'),
      hasLength(2),
    );
    expect(
      GmCareerCodec.decode(
        GmCareerCodec.encode(settled),
      ).tradeHistory.single.assets.map((asset) => asset.toJson()),
      receipt.assets.map((asset) => asset.toJson()),
    );
  });

  test('invalid, consumed, and stale pick proposals reject before lookup', () {
    final firstPick = beforeDraft.draftOrder.picks.firstWhere(
      (pick) => pick.currentOwnerTeamId == user,
    );
    final secondPick = beforeDraft.draftOrder.picks.firstWhere(
      (pick) => pick.currentOwnerTeamId == opponent,
    );
    PlayerTradeProposal picks({
      required GmCareer career,
      required int overall,
      required TeamId expectedOwner,
    }) => PlayerTradeProposal(
      careerId: career.id,
      seasonYear: career.currentYear,
      expectedTradeCount: career.tradeHistory.length,
      firstTeam: user,
      secondTeam: opponent,
      picksFromFirst: [
        (
          draftYear: career.currentYear,
          overallPick: overall,
          expectedOwner: expectedOwner,
        ),
      ],
      picksFromSecond: [
        (
          draftYear: career.currentYear,
          overallPick: secondPick.overallPick,
          expectedOwner: opponent,
        ),
      ],
    );

    expect(
      () => PlayerTradeService.buildCandidate(
        beforeDraft,
        picks(career: beforeDraft, overall: 61, expectedOwner: user),
      ),
      throwsA(
        isA<PlayerTradeRejected>().having(
          (error) => error.reason,
          'reason',
          PlayerTradeRejection.unavailableAsset,
        ),
      ),
    );
    expect(
      () => PlayerTradeService.buildCandidate(
        beforeDraft,
        picks(
          career: beforeDraft,
          overall: firstPick.overallPick,
          expectedOwner: opponent,
        ),
      ),
      throwsA(
        isA<PlayerTradeRejected>().having(
          (error) => error.reason,
          'reason',
          PlayerTradeRejection.staleOwnership,
        ),
      ),
    );
    expect(
      () => PlayerTradeService.buildCandidate(
        afterDraft,
        picks(
          career: afterDraft,
          overall: firstPick.overallPick,
          expectedOwner: user,
        ),
      ),
      throwsA(
        isA<PlayerTradeRejected>().having(
          (error) => error.reason,
          'reason',
          PlayerTradeRejection.unavailableAsset,
        ),
      ),
    );
  });

  test(
    'unsigned rights transfer signing authority without changing selection',
    () {
      final rights = afterDraft.unsignedDraftRights.firstWhere(
        (r) => r.owningTeamId == opponent,
      );
      final player = afterDraft.userTeam.roster.standardPlayers.first;
      final contract = afterDraft.finances.contractForPlayer(player.id)!;
      final proposal = PlayerTradeProposal(
        careerId: afterDraft.id,
        seasonYear: afterDraft.currentYear,
        expectedTradeCount: 0,
        firstTeam: user,
        secondTeam: opponent,
        fromFirst: [(playerId: player.id, contractId: contract.id)],
        rightsFromSecond: [
          (
            prospectId: rights.prospectId,
            draftYear: rights.seasonYear,
            overallPick: rights.overallPick,
            expectedOwner: opponent,
          ),
        ],
      );
      final traded = PlayerTradeService.buildCandidate(afterDraft, proposal);
      final originalSelection = afterDraft.draftExecutionState.selections
          .firstWhere((s) => s.prospectId == rights.prospectId);
      final selectionJson = originalSelection.toJson();
      expect(
        traded
            .draftExecutionState
            .draftRights[rights.prospectId.value]!
            .owningTeamId,
        user,
      );
      expect(
        traded.draftExecutionState.selections
            .firstWhere((s) => s.prospectId == rights.prospectId)
            .toJson(),
        selectionJson,
      );
      final reloaded = GmCareerCodec.decode(GmCareerCodec.encode(traded));
      final originalDecision =
          afterDraft.aiRookieSigning.decisions[rights.prospectId.value]!;
      expect(originalDecision.teamId, opponent);
      expect(
        reloaded.aiRookieSigning.decisions[rights.prospectId.value]!.toJson(),
        originalDecision.toJson(),
      );
      final forged =
          jsonDecode(GmCareerCodec.encode(reloaded)) as Map<String, dynamic>;
      final decisions =
          (forged['aiRookieSigning'] as Map<String, dynamic>)['decisions']
              as Map<String, dynamic>;
      (decisions[rights.prospectId.value] as Map<String, dynamic>)['teamId'] =
          'team-3';
      expect(
        () => GmCareerCodec.decode(jsonEncode(forged)),
        throwsFormatException,
      );
      final signed = const RookieSigningService().signDraftedRookie(
        career: reloaded,
        teamId: user,
        prospectId: rights.prospectId,
        category: RosterCategory.standard,
        durationYears: 2,
      );
      expect(
        signed.finances.contractForPlayer(rights.prospectId)!.teamId,
        user,
      );
      expect(
        signed.draftExecutionState.selections
            .firstWhere((s) => s.prospectId == rights.prospectId)
            .toJson(),
        selectionJson,
      );
      expect(signed.tradeHistory, hasLength(1));
    },
  );
  test('traded pick rights remain unsigned for AI and can return later', () {
    const recipient = TeamId('team-3');
    final originalPick = beforeDraft.draftOrder.picks.firstWhere(
      (pick) => pick.originalOwnerTeamId == opponent,
    );
    final userPick = beforeDraft.draftOrder.picks.firstWhere(
      (pick) => pick.originalOwnerTeamId == user,
    );
    final pickTrade = PlayerTradeService.buildCandidate(
      beforeDraft,
      PlayerTradeProposal(
        careerId: beforeDraft.id,
        seasonYear: beforeDraft.currentYear,
        expectedTradeCount: 0,
        firstTeam: user,
        secondTeam: opponent,
        picksFromFirst: [
          (
            draftYear: beforeDraft.currentYear,
            overallPick: userPick.overallPick,
            expectedOwner: user,
          ),
        ],
        picksFromSecond: [
          (
            draftYear: beforeDraft.currentYear,
            overallPick: originalPick.overallPick,
            expectedOwner: opponent,
          ),
        ],
      ),
    );
    expect(
      pickTrade.draftOrder.pickAt(originalPick.overallPick).currentOwnerTeamId,
      user,
    );

    const draft = DraftExecutionService();
    var career = draft.startDraft(pickTrade);
    while (!career.draftExecutionState.isCompleted) {
      if (career.draftExecutionState.isHumanTurn(
        order: career.draftOrder,
        userTeamId: user,
      )) {
        career = draft.makeHumanSelection(
          career: career,
          prospectId: career.draftExecutionState
              .availableProspects(career.draftClass)
              .first
              .id,
        );
      } else {
        career = draft.executeAiSelection(career);
      }
    }
    final selection = career.draftExecutionState.selections.firstWhere(
      (s) => s.overallPick == originalPick.overallPick,
    );
    expect(selection.originalOwnerTeamId, opponent);
    expect(selection.selectingTeamId, user);
    final selectionJson = selection.toJson();
    const aiSigning = RookieAiSigningService();
    career = aiSigning.initialize(career);
    while (aiSigning.pendingRights(career).isNotEmpty) {
      career = aiSigning.applyNextDecision(career);
    }
    expect(
      career
          .draftExecutionState
          .draftRights[selection.prospectId.value]!
          .owningTeamId,
      user,
    );
    final recipientTeam = career.league.teams.firstWhere(
      (team) => team.id == recipient,
    );
    final player = recipientTeam.roster.standardPlayers.first;
    final contract = career.finances.contractForPlayer(player.id)!;
    final traded = PlayerTradeService.buildCandidate(
      career,
      PlayerTradeProposal(
        careerId: career.id,
        seasonYear: career.currentYear,
        expectedTradeCount: 1,
        firstTeam: user,
        secondTeam: recipient,
        rightsFromFirst: [
          (
            prospectId: selection.prospectId,
            draftYear: career.currentYear,
            overallPick: originalPick.overallPick,
            expectedOwner: user,
          ),
        ],
        fromSecond: [(playerId: player.id, contractId: contract.id)],
      ),
    );
    final reloaded = GmCareerCodec.decode(GmCareerCodec.encode(traded));
    expect(reloaded.tradeHistory, hasLength(2));
    final pickReceipt = reloaded.tradeHistory.first.assets.firstWhere(
      (asset) =>
          asset.kind == TradeAssetKind.pick &&
          asset.overallPick == originalPick.overallPick,
    );
    expect(pickReceipt.originalOwner, opponent);
    expect(pickReceipt.from, opponent);
    expect(pickReceipt.to, user);
    final rightsReceipt = reloaded.tradeHistory.last.assets.firstWhere(
      (asset) =>
          asset.kind == TradeAssetKind.rights &&
          asset.playerId == selection.prospectId,
    );
    expect(rightsReceipt.originalOwner, user);
    expect(rightsReceipt.from, user);
    expect(rightsReceipt.to, recipient);
    expect(
      reloaded
          .draftExecutionState
          .draftRights[selection.prospectId.value]!
          .owningTeamId,
      recipient,
    );
    expect(
      reloaded.draftExecutionState.selections
          .firstWhere((s) => s.prospectId == selection.prospectId)
          .toJson(),
      selectionJson,
    );
    expect(aiSigning.pendingRights(reloaded), isEmpty);
    final afterAiPass = aiSigning.advanceAll(reloaded);
    expect(
      afterAiPass.aiRookieSigning.decisions[selection.prospectId.value],
      isNull,
    );
    expect(
      afterAiPass.rookieSigningLedger.forPlayer(selection.prospectId),
      isNull,
    );
    expect(
      afterAiPass.finances.contractForPlayer(selection.prospectId),
      isNull,
    );
    expect(
      () => const RookieSigningService().signDraftedRookie(
        career: afterAiPass,
        teamId: user,
        prospectId: selection.prospectId,
        category: RosterCategory.standard,
        durationYears: 2,
      ),
      throwsStateError,
    );
    final signedReloaded = GmCareerCodec.decode(
      GmCareerCodec.encode(afterAiPass),
    );
    expect(signedReloaded.tradeHistory, hasLength(2));
    expect(
      signedReloaded.draftExecutionState.selections
          .firstWhere((s) => s.prospectId == selection.prospectId)
          .toJson(),
      selectionJson,
    );
    var humanReady = signedReloaded;
    for (final owned in humanReady.unsignedDraftRights.toList()) {
      if (owned.owningTeamId != user) continue;
      humanReady = const RookieSigningService().signDraftedRookie(
        career: humanReady,
        teamId: user,
        prospectId: owned.prospectId,
        category: RosterCategory.standard,
        durationYears: 2,
      );
    }
    final completed = completeSeason(
      scheduledSeason(clearOffseason(humanReady)),
    );
    final rolled = const SeasonRolloverService()
        .prepareArchiveAndRollover(current: completed)
        .rolloverResult
        .nextCareer;
    final rolledReloaded = GmCareerCodec.decode(GmCareerCodec.encode(rolled));
    expect(rolledReloaded.tradeHistory, hasLength(2));
    for (final forgedOwner in ['team-4', 'unknown-team']) {
      final forged =
          jsonDecode(GmCareerCodec.encode(afterAiPass)) as Map<String, dynamic>;
      final rights =
          ((forged['draftExecutionState']
                      as Map<String, dynamic>)['draftRights']
                  as Map<String, dynamic>)[selection.prospectId.value]
              as Map<String, dynamic>;
      rights['owningTeamId'] = forgedOwner;
      expect(
        () => GmCareerCodec.decode(jsonEncode(forged)),
        throwsFormatException,
      );
    }
    expect(
      rolledReloaded
          .careerDraftRights[selection.prospectId.value]!
          .owningTeamId,
      recipient,
    );
    final pick = rolledReloaded.draftOrder.picks.firstWhere(
      (pick) => pick.currentOwnerTeamId == user,
    );
    final returned = PlayerTradeService.buildCandidate(
      rolledReloaded,
      PlayerTradeProposal(
        careerId: rolledReloaded.id,
        seasonYear: rolledReloaded.currentYear,
        expectedTradeCount: 2,
        firstTeam: user,
        secondTeam: recipient,
        picksFromFirst: [
          (
            draftYear: rolledReloaded.currentYear,
            overallPick: pick.overallPick,
            expectedOwner: user,
          ),
        ],
        rightsFromSecond: [
          (
            prospectId: selection.prospectId,
            draftYear: selection.seasonYear,
            overallPick: selection.overallPick,
            expectedOwner: recipient,
          ),
        ],
      ),
    );
    final latest = GmCareerCodec.decode(GmCareerCodec.encode(returned));
    expect(
      latest.careerDraftRights[selection.prospectId.value]!.owningTeamId,
      user,
    );
    final lastTransfer = latest.tradeHistory.last.assets.firstWhere(
      (asset) => asset.kind == TradeAssetKind.rights,
    );
    expect(lastTransfer.originalOwner, user);
    expect(lastTransfer.from, recipient);
    expect(lastTransfer.to, user);
    for (final forgedOwner in [recipient.value, opponent.value]) {
      final forged =
          jsonDecode(GmCareerCodec.encode(latest)) as Map<String, dynamic>;
      final rights =
          (forged['careerDraftRights']
                  as Map<String, dynamic>)[selection.prospectId.value]
              as Map<String, dynamic>;
      rights['owningTeamId'] = forgedOwner;
      expect(
        () => GmCareerCodec.decode(jsonEncode(forged)),
        throwsFormatException,
      );
    }
    final forged =
        jsonDecode(GmCareerCodec.encode(latest)) as Map<String, dynamic>;
    final history = forged['tradeHistory'] as List<dynamic>;
    final assets =
        (history.last as Map<String, dynamic>)['assets'] as List<dynamic>;
    final receipt = assets.cast<Map<String, dynamic>>().firstWhere(
      (asset) => asset['kind'] == 'rights',
    );
    receipt['overallPick'] = selection.overallPick == 60
        ? 59
        : selection.overallPick + 1;
    expect(
      () => GmCareerCodec.decode(jsonEncode(forged)),
      throwsFormatException,
    );
  });
}
