import 'package:flutter/foundation.dart';
import 'package:simulation_core/simulation_core.dart';

import 'career_storage.dart';
import 'rollover_isolate_workers.dart';

/// Observable operation-boundary stage during a player-initiated season
/// transition from completed playoffs to the next season's opening offseason.
enum SeasonTransitionStage {
  preparing(
    label: 'Preparing next season',
    description:
        'Building next season rosters, contracts, and financial plans.',
  ),
  archiving(
    label: 'Verifying and archiving completed season',
    description: 'Validating and saving the immutable season archive.',
  ),
  savingNextSeason(
    label: 'Saving your next season',
    description: 'Writing your next season career save.',
  );

  const SeasonTransitionStage({required this.label, required this.description});

  final String label;
  final String description;
}

/// Live progress snapshot while a multi-round regular-season batch runs.
@immutable
final class BatchSimulationProgress {
  const BatchSimulationProgress({
    required this.startRound,
    required this.currentRound,
    required this.targetRound,
    required this.roundsCompleted,
    required this.totalRounds,
    required this.isCancelling,
    this.latestUserGameSummary,
  });

  final int startRound;
  final int currentRound;
  final int targetRound;
  final int roundsCompleted;
  final int totalRounds;
  final bool isCancelling;
  final String? latestUserGameSummary;

  int get roundsRemaining =>
      (totalRounds - roundsCompleted).clamp(0, totalRounds);

  double get fraction =>
      totalRounds <= 0 ? 1.0 : (roundsCompleted / totalRounds).clamp(0.0, 1.0);
}

/// Manages loading, saving, and active runtime state for a persistent [GmCareer].
class GmCareerController extends ChangeNotifier {
  GmCareerController({
    required this.storage,
    @visibleForTesting
    Future<RolloverPrepareOutput> Function(RolloverPrepareRequest)?
    prepareRolloverWorker,
  }) : _prepareRolloverWorker =
           prepareRolloverWorker ?? _defaultPrepareRolloverWorker;

  final GmCareerStorage storage;
  final Future<RolloverPrepareOutput> Function(RolloverPrepareRequest)
  _prepareRolloverWorker;

  GmCareer? _career;
  bool _isLoading = false;
  String? _errorMessage;
  Future<void> _pendingCommand = Future<void>.value();
  int _inFlightCommands = 0;
  bool _draftRecoveryRequired = false;
  bool _disposed = false;
  SeasonTransitionStage? _seasonTransitionStage;
  BatchSimulationProgress? _batchProgress;
  bool _batchCancelRequested = false;
  static const _draftService = DraftExecutionService();
  static const _signingService = RookieSigningService();
  static const _marketService = FreeAgentMarketService();
  static const _clearanceService = OffseasonClearanceService();
  static const _aiSigningService = RookieAiSigningService();
  static const _hardshipService = HardshipSettlementService();
  static const _regularSeasonEntryService = RegularSeasonEntryService();
  static const _regularSeasonScheduleService = RegularSeasonScheduleService();
  static const _playInEntryService = PlayInEntryService();
  static const _playoffEntryService = PlayoffEntryService();

  GmCareer? get career => _career;
  bool get hasCareer => _career != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Draft and signing commands remain blocked until a successful reload
  /// reconciles a failed or uncertain write.
  bool get draftRecoveryRequired => _draftRecoveryRequired;

  /// Current operation-boundary stage while archiving a completed season and
  /// saving the next season, or `null` when idle.
  SeasonTransitionStage? get seasonTransitionStage => _seasonTransitionStage;

  /// Active regular-season batch simulation progress, or `null` when idle.
  BatchSimulationProgress? get batchProgress => _batchProgress;

  /// Whether a multi-round regular-season batch is currently executing.
  bool get isBatchSimulating => _batchProgress != null;

  /// Requests graceful cancellation after the in-flight round finishes saving.
  void requestCancelBatchSimulation() {
    final current = _batchProgress;
    if (current == null || _batchCancelRequested) return;
    _batchCancelRequested = true;
    _batchProgress = BatchSimulationProgress(
      startRound: current.startRound,
      currentRound: current.currentRound,
      targetRound: current.targetRound,
      roundsCompleted: current.roundsCompleted,
      totalRounds: current.totalRounds,
      isCancelling: true,
      latestUserGameSummary: current.latestUserGameSummary,
    );
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _setSeasonTransitionStage(SeasonTransitionStage? stage) {
    if (_seasonTransitionStage == stage) return;
    _seasonTransitionStage = stage;
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Completes after commands already queued by this controller have settled.
  Future<void> get commandsSettled => _pendingCommand;

  /// Loads the saved career from [storage].
  Future<void> loadCareer({String slot = 'default'}) => _serialize(() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final raw = await storage.read(slot: slot);
      if (raw == null) {
        _career = null;
      } else if (raw.trim().isEmpty) {
        throw const FormatException('Career save file exists but is empty.');
      } else {
        try {
          _career = shouldUseIsolateForLargeDecode(raw.length)
              ? await compute(decodeCareerJsonWorker, raw)
              : GmCareerCodec.decode(raw);
        } catch (decodeError) {
          if (storage is FileGmCareerStorage) {
            final recovered = await (storage as FileGmCareerStorage)
                .recoverBackup(slot: slot);
            if (recovered != null) {
              _career = shouldUseIsolateForLargeDecode(recovered.length)
                  ? await compute(decodeCareerJsonWorker, recovered)
                  : GmCareerCodec.decode(recovered);
              _draftRecoveryRequired = false;
              return;
            }
          }
          rethrow;
        }
      }
      _draftRecoveryRequired = false;
    } catch (e) {
      _errorMessage =
          'Failed to load saved GM Career: $e. Save file preserved without deletion.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  });

  /// Initializes and persists a new [GmCareer] from a verified [CareerSetupResult].
  Future<void> startCareer(
    CareerSetupResult setupResult, {
    String slot = 'default',
  }) => _serialize(() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final newCareer = GmCareer.fromSetupResult(setupResult);
      final jsonString = GmCareerCodec.encode(newCareer);
      await storage.write(jsonString, slot: slot);
      _career = newCareer;
      _draftRecoveryRequired = false;
    } catch (e) {
      _errorMessage = 'Failed to save new GM Career: $e';
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  });

  /// Clears active career and deletes storage file for the given [slot].
  Future<void> clearCareer({String slot = 'default'}) => _serialize(() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await storage.clear(slot: slot);
      _career = null;
      _draftRecoveryRequired = false;
    } catch (e) {
      _errorMessage = 'Failed to clear GM Career: $e';
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  });

  /// Starts the draft, saving each AI pick before stopping at a human turn.
  Future<void> startDraft({String slot = 'default'}) => _runCareerCommand(
    action: 'execute rookie draft',
    () async {
      await _saveCareerState(_draftService.startDraft(_requireCareer()), slot);
      await _advanceAiSelections(slot);
    },
  );

  /// Saves one human selection, then saves each following AI selection.
  Future<void> makeHumanSelection({
    required PlayerId prospectId,
    String slot = 'default',
  }) {
    final submittedCareer = _career;
    return _runCareerCommand(action: 'execute rookie draft', () async {
      final current = _requireCareer();
      if (!identical(current, submittedCareer)) {
        throw StateError('Career changed before the human selection executed');
      }
      final next = _draftService.makeHumanSelection(
        career: current,
        prospectId: prospectId,
      );
      await _saveCareerState(next, slot);
      await _advanceAiSelections(slot);
    });
  }

  /// Resumes AI picks from the last committed state without crossing a human turn.
  Future<void> advanceDraft({String slot = 'default'}) =>
      _runCareerCommand(action: 'execute rookie draft', () async {
        if (_requireCareer().draftExecutionState.isNotStarted) {
          throw StateError('Cannot advance a draft before it starts');
        }
        await _advanceAiSelections(slot);
      });

  /// Signs one drafted prospect owned by the user's franchise.
  ///
  /// The new career is persisted before it is published; a failed write keeps
  /// the previous in-memory state and requires a reload before further commands.
  Future<void> signDraftedRookie({
    required PlayerId prospectId,
    required RosterCategory category,
    required int durationYears,
    String slot = 'default',
  }) {
    final submittedCareer = _career;
    return _runCareerCommand(action: 'sign drafted rookie', () async {
      final current = _requireCareer();
      if (!identical(current, submittedCareer)) {
        throw StateError('Career changed before the rookie signing executed');
      }
      final next = _signingService.signDraftedRookie(
        career: current,
        teamId: current.userFranchiseId,
        prospectId: prospectId,
        category: category,
        durationYears: durationYears,
      );
      final encoded = GmCareerCodec.encode(next);
      try {
        await storage.write(encoded, slot: slot);
      } catch (_) {
        _draftRecoveryRequired = true;
        rethrow;
      }
      _career = next;
      notifyListeners();
    });
  }

  /// Starts or advances to the next free-agency market round.
  Future<void> startFreeAgencyRound({String slot = 'default'}) =>
      _runCareerCommand(action: 'start free-agency round', () async {
        await _saveCareerState(
          _marketService.startRound(_requireCareer()),
          slot,
        );
      });

  /// Stages one human offer for the current market round.
  Future<void> stageFreeAgentOffer({
    required PlayerId freeAgentId,
    required RosterCategory category,
    required int durationYears,
    required int firstYearSalary,
    String slot = 'default',
  }) => _runCareerCommand(action: 'stage free-agent offer', () async {
    final current = _requireCareer();
    final next = _marketService.stageHumanOffer(
      career: current,
      teamId: current.userFranchiseId,
      playerId: freeAgentId,
      category: category,
      durationYears: durationYears,
      firstYearSalary: firstYearSalary,
    );
    await _saveCareerState(next, slot);
  });

  Future<void> cancelFreeAgentOffer({
    required PlayerId freeAgentId,
    String slot = 'default',
  }) => _runCareerCommand(action: 'cancel free-agent offer', () async {
    final current = _requireCareer();
    await _saveCareerState(
      _marketService.cancelHumanOffer(career: current, playerId: freeAgentId),
      slot,
    );
  });

  /// Seals AI offers and freezes the round for resolution.
  Future<void> prepareFreeAgencyResolution({String slot = 'default'}) =>
      _runCareerCommand(action: 'prepare free-agency round', () async {
        await _saveCareerState(
          _marketService.prepareResolution(_requireCareer()),
          slot,
        );
      });

  /// Resolves the round one player at a time, saving each decision.
  Future<void> resolveFreeAgencyRound({String slot = 'default'}) =>
      _runCareerCommand(action: 'resolve free-agency round', () async {
        var current = _requireCareer();
        if (!current.freeAgentMarket.isResolvable) {
          throw StateError('Free-agent market is not ready for resolution');
        }
        while (current.freeAgentMarket.isResolvable) {
          final next = _marketService.resolveNext(current);
          await _saveCareerState(next, slot);
          current = next;
        }
      });

  /// M010: saves validated lineup/rotation preferences for the human team.
  ///
  /// Manual settings must resolve against the current standard roster, and a
  /// custom plan must list every standard player (an explicit 0 is allowed).
  /// Rejected, never queued, while a command, batch or season transition is
  /// running, so a batch always uses the settings committed before it began.
  Future<void> updateUserRotation(
    CareerRotationSettings settings, {
    String slot = 'default',
  }) => _rotationCommand('update rotation', slot, (current) {
    if (!settings.isManual) return settings;
    final team = RegularSeasonGameAdapter.standardTeamFor(current.userTeam);
    final resolution = CareerRotationService.resolve(settings, team);
    if (!resolution.isValid) {
      throw CareerRotationInvalidException(resolution.issues);
    }
    if (resolution.unassignedPlayerIds.isNotEmpty) {
      throw StateError(
        'Custom rotation must assign every standard player: '
        '${resolution.unassignedPlayerIds.map((id) => id.value).join(', ')}',
      );
    }
    return settings;
  });

  /// M010: explicit switch back to automatic lineup and rotation.
  Future<void> resetUserRotationToAuto({String slot = 'default'}) =>
      _rotationCommand(
        'reset rotation to auto',
        slot,
        (_) => CareerRotationSettings.auto,
      );

  /// M010: writes the deterministic repair proposal for an obsolete manual
  /// plan. Refuses when the proposal still has issues (for example a custom
  /// budget shortfall), because custom seconds are never redistributed.
  Future<void> applyUserRotationRepair({String slot = 'default'}) =>
      _rotationCommand('repair rotation', slot, (current) {
        final proposal = CareerRotationService.proposeRepair(
          current.userRotation,
          RegularSeasonGameAdapter.standardTeamFor(current.userTeam),
        );
        if (proposal == null) {
          throw StateError('Rotation has nothing to repair');
        }
        if (!proposal.isApplicable) {
          throw CareerRotationInvalidException(proposal.remainingIssues);
        }
        return proposal.settings;
      });

  /// M011: switch to AUTO while keeping the current manual plan for later
  /// restoration. Nothing is erased; plain AUTO stays an explicit reset.
  Future<void> delegateUserRotationKeepingManual({String slot = 'default'}) =>
      _rotationCommand('delegate rotation', slot, (current) {
        final settings = current.userRotation;
        if (!settings.isManual) return settings;
        return CareerRotationSettings.autoRetaining(settings);
      });

  /// M011: restores the retained manual plan after validating it against the
  /// current standard roster; an obsolete plan is refused with its issues.
  Future<void> restoreRetainedManualRotation({String slot = 'default'}) =>
      _rotationCommand('restore manual rotation', slot, (current) {
        final retained = current.userRotation.retainedManual;
        if (retained == null) {
          throw StateError('No retained manual rotation to restore');
        }
        final resolution = CareerRotationService.resolve(
          retained,
          RegularSeasonGameAdapter.standardTeamFor(current.userTeam),
        );
        if (!resolution.isValid) {
          throw CareerRotationInvalidException(resolution.issues);
        }
        return retained;
      });

  /// M011 (D2): permanent league-wide coaching activation.
  Future<void> enableCoaching({String slot = 'default'}) =>
      _staffCommand('enable coaching', slot, _staffMarket.enableCoaching);

  Future<void> hireHeadCoach({
    required String candidateId,
    required int durationYears,
    String slot = 'default',
  }) => _staffCommand(
    'hire head coach',
    slot,
    (current) => _staffMarket.hireHeadCoach(
      current,
      teamId: current.userFranchiseId,
      candidateId: candidateId,
      durationYears: durationYears,
    ),
  );

  Future<void> dismissHeadCoach({String slot = 'default'}) => _staffCommand(
    'dismiss head coach',
    slot,
    (current) =>
        _staffMarket.dismissHeadCoach(current, teamId: current.userFranchiseId),
  );

  Future<void> replaceHeadCoach({
    required String candidateId,
    required int durationYears,
    String slot = 'default',
  }) => _staffCommand(
    'replace head coach',
    slot,
    (current) => _staffMarket.replaceHeadCoach(
      current,
      teamId: current.userFranchiseId,
      candidateId: candidateId,
      durationYears: durationYears,
    ),
  );

  Future<void> renewHeadCoach({
    required int additionalYears,
    String slot = 'default',
  }) => _staffCommand(
    'renew head coach',
    slot,
    (current) => _staffMarket.renewHeadCoach(
      current,
      teamId: current.userFranchiseId,
      additionalYears: additionalYears,
    ),
  );

  static const StaffMarketService _staffMarket = StaffMarketService();

  StateError? _exclusiveCommandBlocker(String action) =>
      _inFlightCommands > 0 ||
          _isLoading ||
          isBatchSimulating ||
          _seasonTransitionStage != null
      ? StateError('Cannot $action while a simulation or save is in progress')
      : null;

  Future<void> _rotationCommand(
    String action,
    String slot,
    CareerRotationSettings Function(GmCareer current) next,
  ) {
    final blocked = _exclusiveCommandBlocker(action);
    if (blocked != null) return Future.error(blocked);
    return _runCareerCommand(action: action, () async {
      final current = _requireCareer();
      final settings = next(current);
      if (settings == current.userRotation) return;
      await _saveCareerState(current.copyWith(userRotation: settings), slot);
    });
  }

  /// Staff transactions: rejected (never queued) while anything else runs;
  /// the pure core transaction either fully succeeds or throws before any
  /// state is built, and a failed save keeps the previous career.
  Future<void> _staffCommand(
    String action,
    String slot,
    GmCareer Function(GmCareer current) transaction,
  ) {
    final blocked = _exclusiveCommandBlocker(action);
    if (blocked != null) return Future.error(blocked);
    return _runCareerCommand(action: action, () async {
      await _saveCareerState(transaction(_requireCareer()), slot);
    });
  }

  Future<void> startOffseasonClearance({String slot = 'default'}) =>
      _runCareerCommand(action: 'start clearance', () async {
        await _saveCareerState(_clearanceService.start(_requireCareer()), slot);
      });

  Future<void> stageClearanceOffer({
    required PlayerId freeAgentId,
    required int durationYears,
    required int firstYearSalary,
    String slot = 'default',
  }) => _runCareerCommand(action: 'stage clearance offer', () async {
    final current = _requireCareer();
    await _saveCareerState(
      _clearanceService.stageHumanOffer(
        career: current,
        teamId: current.userFranchiseId,
        playerId: freeAgentId,
        durationYears: durationYears,
        firstYearSalary: firstYearSalary,
      ),
      slot,
    );
  });

  Future<void> prepareOffseasonClearance({String slot = 'default'}) =>
      _runCareerCommand(action: 'prepare clearance', () async {
        await _saveCareerState(
          _clearanceService.prepare(_requireCareer()),
          slot,
        );
      });

  Future<void> resolveOffseasonClearance({String slot = 'default'}) =>
      _runCareerCommand(action: 'resolve clearance', () async {
        var current = _requireCareer();
        if (!current.offseasonClearance.isResolvable) {
          throw StateError('Clearance is not ready for resolution');
        }
        while (current.offseasonClearance.isResolvable) {
          final next = _clearanceService.resolveNext(current);
          await _saveCareerState(next, slot);
          current = next;
        }
      });
  Future<void> prepareHardshipSettlement({
    required bool humanParticipationConfirmed,
    String slot = 'default',
  }) => _runCareerCommand(action: 'prepare hardship settlement', () async {
    await _saveCareerState(
      _hardshipService.prepare(
        _requireCareer(),
        humanParticipationConfirmed: humanParticipationConfirmed,
      ),
      slot,
    );
  });

  Future<void> resolveHardshipSettlement({String slot = 'default'}) =>
      _runCareerCommand(action: 'resolve hardship settlement', () async {
        var current = _requireCareer();
        if (!current.hardshipSettlement.isResolvable) {
          throw StateError('Hardship settlement is not ready for resolution');
        }
        while (current.hardshipSettlement.isResolvable) {
          final next = _hardshipService.resolveNext(current);
          await _saveCareerState(next, slot);
          current = next;
        }
      });

  Future<void> markOffseasonCleared({String slot = 'default'}) =>
      _runCareerCommand(action: 'mark offseason cleared', () async {
        await _saveCareerState(
          _clearanceService.markCleared(_requireCareer()),
          slot,
        );
      });

  /// Starts regular season after explicit human confirmation and a fresh gate.
  Future<void> startRegularSeason({
    required bool confirmed,
    String slot = 'default',
  }) => _runCareerCommand(action: 'start regular season', () async {
    if (!confirmed) {
      throw StateError('Explicit human confirmation is required');
    }
    await _saveCareerState(
      _regularSeasonEntryService.start(_requireCareer()),
      slot,
    );
  });

  /// Simulates and persists exactly the confirmed next regular-season round.
  Future<void> simulateNextRegularSeasonRound({
    required int expectedRoundNumber,
    required bool confirmed,
    String slot = 'default',
  }) => _runCareerCommand(action: 'simulate regular-season round', () async {
    if (!confirmed) {
      throw StateError('Explicit human confirmation is required');
    }
    final current = _requireCareer();
    final state = current.regularSeasonState;
    if (state == null) throw StateError('Regular season is not active');
    final schedule = state.schedule;
    if (schedule == null) {
      throw StateError('Regular-season schedule is missing');
    }
    final unfinished = schedule.rounds.where(
      (round) => round.fixtures.any(
        (fixture) => !state.gameResults.containsKey(fixture.id),
      ),
    );
    final nextRound = unfinished.isEmpty ? null : unfinished.first.roundNumber;
    if (nextRound != expectedRoundNumber) {
      throw StateError(
        'Stale round: expected $expectedRoundNumber, current round is $nextRound',
      );
    }
    final next = await compute(
      _simulateRegularSeasonRound,
      _RoundSimulationRequest(current, expectedRoundNumber),
    );
    await _saveCareerState(next, slot);
  });

  /// Simulates and persists [roundCount] regular-season rounds sequentially
  /// starting at [expectedStartRound], stopping at Round 82, cancellation,
  /// or any simulation/persistence error without skipping or auto-advancing.
  Future<void> simulateRegularSeasonBatch({
    required int expectedStartRound,
    required int roundCount,
    required bool confirmed,
    String slot = 'default',
  }) => _runCareerCommand(action: 'simulate regular-season batch', () async {
    if (!confirmed) {
      throw StateError('Explicit human confirmation is required');
    }
    if (roundCount < 1) {
      throw ArgumentError.value(
        roundCount,
        'roundCount',
        'Batch roundCount must be at least 1',
      );
    }
    final initial = _requireCareer();
    final initialState = initial.regularSeasonState;
    if (initialState == null || initial.phase != CareerPhase.regularSeason) {
      throw StateError('Regular season is not active');
    }
    final initialSchedule = initialState.schedule;
    if (initialSchedule == null) {
      throw StateError('Regular-season schedule is missing');
    }
    final startRound = initialState.nextUnfinishedRoundNumber;
    if (startRound != expectedStartRound) {
      throw StateError(
        'Stale round: expected $expectedStartRound, current round is $startRound',
      );
    }
    final maxRound = initialSchedule.rounds.last.roundNumber;
    final targetRound = (expectedStartRound + roundCount - 1).clamp(
      expectedStartRound,
      maxRound,
    );
    final totalRounds = targetRound - expectedStartRound + 1;

    _batchCancelRequested = false;
    _batchProgress = BatchSimulationProgress(
      startRound: expectedStartRound,
      currentRound: expectedStartRound,
      targetRound: targetRound,
      roundsCompleted: 0,
      totalRounds: totalRounds,
      isCancelling: false,
    );
    notifyListeners();

    try {
      String? lastSummary;
      for (var round = expectedStartRound; round <= targetRound; round++) {
        if (_batchCancelRequested || _disposed) {
          break;
        }
        final current = _requireCareer();
        final currentState = current.regularSeasonState;
        if (currentState == null ||
            current.phase != CareerPhase.regularSeason) {
          throw StateError('Regular season is no longer active');
        }
        final nextRound = currentState.nextUnfinishedRoundNumber;
        if (nextRound != round) {
          throw StateError(
            'Stale round during batch: expected $round, got $nextRound',
          );
        }

        _batchProgress = BatchSimulationProgress(
          startRound: expectedStartRound,
          currentRound: round,
          targetRound: targetRound,
          roundsCompleted: round - expectedStartRound,
          totalRounds: totalRounds,
          isCancelling: _batchCancelRequested,
          latestUserGameSummary: lastSummary,
        );
        if (!_disposed) notifyListeners();

        final next = await compute(
          _simulateRegularSeasonRound,
          _RoundSimulationRequest(current, round),
        );
        await _saveCareerState(next, slot);
        lastSummary = _formatUserRoundResult(next, round) ?? lastSummary;

        final completed = round - expectedStartRound + 1;
        _batchProgress = BatchSimulationProgress(
          startRound: expectedStartRound,
          currentRound: round,
          targetRound: targetRound,
          roundsCompleted: completed,
          totalRounds: totalRounds,
          isCancelling: _batchCancelRequested,
          latestUserGameSummary: lastSummary,
        );
        if (!_disposed) notifyListeners();

        // Yield to keep frame rendering and cancel input responsive between rounds.
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _batchProgress = null;
      _batchCancelRequested = false;
    }
  });

  String? _formatUserRoundResult(GmCareer career, int roundNumber) {
    final state = career.regularSeasonState;
    final schedule = state?.schedule;
    if (state == null || schedule == null) return null;
    final round = schedule.rounds.cast<RegularSeasonRound?>().firstWhere(
      (r) => r?.roundNumber == roundNumber,
      orElse: () => null,
    );
    if (round == null) return null;
    for (final fixture in round.fixtures) {
      if (fixture.homeTeamId != career.userFranchiseId &&
          fixture.awayTeamId != career.userFranchiseId) {
        continue;
      }
      final result = state.gameResults[fixture.id];
      if (result == null) return null;
      final isHome = fixture.homeTeamId == career.userFranchiseId;
      final oppId = isHome ? fixture.awayTeamId : fixture.homeTeamId;
      final oppTeam = career.league.teams.firstWhere((t) => t.id == oppId);
      final userScore = isHome
          ? result.summary.homeScore
          : result.summary.awayScore;
      final oppScore = isHome
          ? result.summary.awayScore
          : result.summary.homeScore;
      final won = result.summary.winnerTeamId == career.userFranchiseId;
      return 'Rd $roundNumber: ${won ? 'W' : 'L'} $userScore–$oppScore '
          '${isHome ? 'vs' : '@'} ${oppTeam.abbreviation}';
    }
    return null;
  }

  /// Enters Play-In only after explicit confirmation and a fresh completion gate.
  Future<void> enterPlayIn({
    required bool confirmed,
    String slot = 'default',
  }) => _runCareerCommand(action: 'enter Play-In', () async {
    if (!confirmed) {
      throw StateError('Explicit human confirmation is required');
    }
    await _saveCareerState(_playInEntryService.enter(_requireCareer()), slot);
  });

  /// Simulates one explicitly confirmed and legally available Play-In game.
  Future<void> simulatePlayInGame({
    required String expectedGameId,
    required bool confirmed,
    String slot = 'default',
  }) => _runCareerCommand(action: 'simulate Play-In game', () async {
    if (!confirmed) {
      throw StateError('Explicit human confirmation is required');
    }
    final current = _requireCareer();
    final next = await compute(
      _simulatePlayInGame,
      _PlayInSimulationRequest(current, expectedGameId),
    );
    await _saveCareerState(next, slot);
  });

  /// Enters playoffs after explicit confirmation and successful T05A validation.
  Future<void> enterPlayoffs({
    required bool confirmed,
    String slot = 'default',
  }) {
    final submittedCareer = _career;
    return _runCareerCommand(action: 'enter playoffs', () async {
      if (!confirmed) {
        throw StateError('Explicit human confirmation is required');
      }
      final current = _requireCareer();
      if (!identical(current, submittedCareer)) {
        throw StateError('Career changed before playoff entry executed');
      }
      await _saveCareerState(_playoffEntryService.enter(current), slot);
    });
  }

  /// Simulates one next game for each active series in the current round.
  Future<void> simulateNextPlayoffSlate({
    required bool confirmed,
    String slot = 'default',
  }) {
    final submittedCareer = _career;
    return _runCareerCommand(action: 'simulate playoff slate', () async {
      if (!confirmed) {
        throw StateError('Explicit human confirmation is required');
      }
      final current = _requireCareer();
      if (!identical(current, submittedCareer)) {
        throw StateError('Career changed before playoff slate executed');
      }
      if (current.playoffState?.isComplete == true) {
        throw StateError('Playoffs are already complete');
      }
      const service = PlayoffSlateService();
      final order = service.prepareSlate(current);
      final output = await compute(_simulatePlayoffSlateWorkOrder, order);
      final next = service.applyPreparedSlate(
        current,
        order: order,
        output: output,
      );
      await _saveCareerState(next, slot);
    });
  }

  /// Persists the completed Year N archive before writing and publishing Year N+1
  /// via [SeasonRolloverService].
  Future<void> continueToNextSeason({
    required bool confirmed,
    String slot = 'default',
  }) {
    final submittedCareer = _career;
    final expectedCareerId = submittedCareer?.id;
    final expectedYear = submittedCareer?.currentYear;
    final expectedSlot = slot;
    return _runCareerCommand(action: 'archive completed season', () async {
      if (!confirmed) {
        throw StateError('Explicit human confirmation is required');
      }
      final current = _requireCareer();
      if (!identical(current, submittedCareer)) {
        throw StateError('Career changed before season archive executed');
      }
      final archiveStorage = _requireArchiveStorage();
      try {
        _setSeasonTransitionStage(SeasonTransitionStage.preparing);
        final prepared = await _prepareRolloverWorker(
          RolloverPrepareRequest(current),
        );
        if (_disposed) {
          throw StateError(
            'GmCareerController was disposed before season archive persisted',
          );
        }
        final postWorkerCareer = _career;
        if (!identical(postWorkerCareer, current) ||
            !identical(postWorkerCareer, submittedCareer) ||
            postWorkerCareer == null ||
            postWorkerCareer.id != expectedCareerId ||
            postWorkerCareer.currentYear != expectedYear ||
            slot != expectedSlot) {
          throw StateError(
            'Career or slot changed while season archive was preparing',
          );
        }
        if (prepared.archiveRecord.seasonYear != expectedYear ||
            prepared.nextCareer.id != expectedCareerId ||
            prepared.nextCareer.currentYear != expectedYear! + 1) {
          throw StateError(
            'Prepared rollover output does not match requested career or year',
          );
        }
        await _persistPreparedTransition(
          current: current,
          archiveStorage: archiveStorage,
          archiveJson: prepared.archiveJson,
          archiveDigest: prepared.archiveDigest,
          record: prepared.archiveRecord,
          next: prepared.nextCareer,
          preEncodedNext: prepared.encodedNextCareer,
          slot: slot,
        );
      } finally {
        _setSeasonTransitionStage(null);
      }
    });
  }

  /// Persists the completed Year N archive before writing and publishing Year N+1.
  Future<void> persistArchivedSeasonTransition({
    required GmCareer Function(
      GmCareer current,
      SeasonHistoryRecord archiveRecord,
    )
    buildNextCareer,
    required bool confirmed,
    String slot = 'default',
  }) {
    final submittedCareer = _career;
    return _runCareerCommand(action: 'archive completed season', () async {
      if (!confirmed) {
        throw StateError('Explicit human confirmation is required');
      }
      final current = _requireCareer();
      if (!identical(current, submittedCareer)) {
        throw StateError('Career changed before season archive executed');
      }
      final archiveStorage = _requireArchiveStorage();
      try {
        final archive = SeasonArchive.fromCareer(current);
        final encodedArchive = SeasonArchiveCodec.encodeWithDigest(archive);
        final record = archive.toHistoryRecord(encodedArchive.digest);
        final next = buildNextCareer(current, record);
        await _persistPreparedTransition(
          current: current,
          archiveStorage: archiveStorage,
          archiveJson: encodedArchive.json,
          archiveDigest: encodedArchive.digest,
          record: record,
          next: next,
          slot: slot,
        );
      } finally {
        _setSeasonTransitionStage(null);
      }
    });
  }

  Future<void> _persistPreparedTransition({
    required GmCareer current,
    required GmCareerArchiveStorage archiveStorage,
    required String archiveJson,
    required String archiveDigest,
    required SeasonHistoryRecord record,
    required GmCareer next,
    String? preEncodedNext,
    required String slot,
  }) async {
    if (next.id != current.id) {
      throw StateError('Archived transition must preserve career id');
    }
    if (next.currentYear != current.currentYear + 1) {
      throw StateError(
        'Archived transition must advance currentYear by exactly 1',
      );
    }
    if (next.seasonHistory.length != current.seasonHistory.length + 1) {
      throw StateError(
        'Archived transition must append exactly one SeasonHistoryRecord',
      );
    }
    for (var i = 0; i < current.seasonHistory.length; i++) {
      if (next.seasonHistory[i] != current.seasonHistory[i]) {
        throw StateError(
          'Archived transition must preserve prior seasonHistory records',
        );
      }
    }
    if (next.seasonHistory.last != record) {
      throw StateError(
        'Archived transition seasonHistory.last must match archived season',
      );
    }
    final encodedNext = preEncodedNext ?? GmCareerCodec.encode(next);
    try {
      _setSeasonTransitionStage(SeasonTransitionStage.archiving);
      await archiveStorage.writeArchive(
        seasonYear: current.currentYear,
        archiveJson: archiveJson,
        expectedDigest: archiveDigest,
        slot: slot,
      );
      _setSeasonTransitionStage(SeasonTransitionStage.savingNextSeason);
      await storage.write(encodedNext, slot: slot);
    } catch (_) {
      _draftRecoveryRequired = true;
      rethrow;
    }
    _career = next;
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Reads and cryptographically verifies an archived season for the active career.
  Future<SeasonArchive> loadSeasonArchive(
    int seasonYear, {
    String slot = 'default',
  }) async {
    final current = _requireCareer();
    final record = current.seasonHistory
        .cast<SeasonHistoryRecord?>()
        .firstWhere(
          (entry) => entry?.seasonYear == seasonYear,
          orElse: () => null,
        );
    if (record == null) {
      throw StateError('No archived season record exists for year $seasonYear');
    }
    final raw = await _requireArchiveStorage().readArchive(
      seasonYear: seasonYear,
      slot: slot,
    );
    if (raw == null || raw.trim().isEmpty) {
      throw GmCareerStorageException(
        'Missing or empty historical archive for slot "$slot" year $seasonYear',
      );
    }
    if (!shouldUseIsolateForLargeDecode(raw.length)) {
      return SeasonArchiveCodec.decodeAndVerify(
        raw,
        expectedDigest: record.archiveDigest,
        expectedCareerId: current.id,
        expectedSeasonYear: seasonYear,
        expectedRecord: record,
      );
    }
    return compute(
      decodeAndVerifyArchiveWorker,
      ArchiveDecodeVerifyRequest(
        archiveJson: raw,
        expectedDigest: record.archiveDigest,
        expectedCareerId: current.id,
        expectedSeasonYear: seasonYear,
        expectedRecord: record,
      ),
    );
  }

  /// Exports the persisted career in [slot] and all referenced historical archives as a bundle.
  Future<String> exportCareerBundle({String slot = 'default'}) async {
    final activeJson = await storage.read(slot: slot);
    if (activeJson == null || activeJson.trim().isEmpty) {
      throw GmCareerStorageException(
        'Cannot export bundle: no persisted career in slot "$slot"',
      );
    }
    final persistedCareer = GmCareerCodec.decode(activeJson);
    final archiveStorage = _requireArchiveStorage();
    final archivesByYear = <int, String>{};
    for (final record in persistedCareer.seasonHistory) {
      final raw = await archiveStorage.readArchive(
        seasonYear: record.seasonYear,
        slot: slot,
      );
      if (raw == null || raw.trim().isEmpty) {
        throw GmCareerStorageException(
          'Cannot export bundle: missing archive for year ${record.seasonYear}',
        );
      }
      archivesByYear[record.seasonYear] = raw;
    }
    return const CareerBundleService().exportBundle(
      activeCareerJson: activeJson,
      archivesByYear: archivesByYear,
    );
  }

  /// Verifies and imports a career bundle into [slot] before publishing.
  Future<void> importCareerBundle(
    String bundleJson, {
    String slot = 'default',
  }) => _serialize(() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    var wrotePersistentState = false;
    try {
      final imported = const CareerBundleService().importBundle(bundleJson);
      final archiveStorage = _requireArchiveStorage();

      // Preflight active career ownership and all archive conflicts before
      // mutating any persistent files in [slot].
      if (await storage.hasSave(slot: slot)) {
        final existingActiveRaw = await storage.read(slot: slot);
        if (existingActiveRaw != null && existingActiveRaw.trim().isNotEmpty) {
          final existingCareer = GmCareerCodec.decode(existingActiveRaw);
          if (existingCareer.id != imported.career.id) {
            throw GmCareerStorageException(
              'Cannot import bundle for career "${imported.career.id}" into '
              'slot "$slot" owned by "${existingCareer.id}"',
            );
          }
        }
      }
      for (final record in imported.career.seasonHistory) {
        if (await archiveStorage.hasArchive(
          seasonYear: record.seasonYear,
          slot: slot,
        )) {
          final existingRaw = await archiveStorage.readArchive(
            seasonYear: record.seasonYear,
            slot: slot,
          );
          if (existingRaw != null &&
              SeasonArchiveCodec.digestOf(existingRaw) !=
                  record.archiveDigest) {
            var existingValid = false;
            try {
              SeasonArchiveCodec.decodeAndVerify(
                existingRaw,
                expectedDigest: SeasonArchiveCodec.digestOf(existingRaw),
                expectedSeasonYear: record.seasonYear,
              );
              existingValid = true;
            } catch (_) {}
            if (existingValid) {
              throw GmCareerStorageException(
                'Conflicting historical archive already exists for slot "$slot" '
                'year ${record.seasonYear}',
              );
            }
          }
        }
      }

      for (final record in imported.career.seasonHistory) {
        final rawArchive = imported.verifiedArchivesByYear[record.seasonYear]!;
        wrotePersistentState = true;
        await archiveStorage.writeArchive(
          seasonYear: record.seasonYear,
          archiveJson: rawArchive,
          expectedDigest: record.archiveDigest,
          slot: slot,
        );
      }
      wrotePersistentState = true;
      await storage.write(imported.activeCareerJson, slot: slot);
      _career = imported.career;
      _draftRecoveryRequired = false;
    } catch (e) {
      if (wrotePersistentState) {
        _draftRecoveryRequired = true;
      }
      _errorMessage = 'Failed to import career bundle: $e';
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  });

  GmCareerArchiveStorage _requireArchiveStorage() {
    final s = storage;
    if (s is GmCareerArchiveStorage) {
      return s as GmCareerArchiveStorage;
    }
    throw StateError('Configured GmCareerStorage does not support archives');
  }

  Future<void> generateRegularSeasonSchedule({String slot = 'default'}) =>
      _runCareerCommand(action: 'generate regular-season schedule', () async {
        await _saveCareerState(
          _regularSeasonScheduleService.generate(_requireCareer()),
          slot,
        );
      });

  /// Applies deterministic AI rookie signing decisions for non-human franchises.
  ///
  /// Each decision is persisted before the next one is evaluated. The process
  /// never touches human-owned rights and is safe to resume after a restart.
  Future<void> advanceAiRookieSigning({String slot = 'default'}) =>
      _runCareerCommand(action: 'advance AI rookie signing', () async {
        var current = _requireCareer();
        if (!current.draftExecutionState.isCompleted) {
          throw StateError(
            'Cannot evaluate AI rookie signings before the draft completes',
          );
        }
        final initialized = _aiSigningService.initialize(current);
        if (!identical(initialized, current)) {
          await _saveCareerState(initialized, slot);
          current = initialized;
        }
        while (_aiSigningService.pendingRights(current).isNotEmpty) {
          final next = _aiSigningService.applyNextDecision(current);
          if (identical(next, current)) break;
          await _saveCareerState(next, slot);
          current = next;
        }
      });

  GmCareer _requireCareer() =>
      _career ?? (throw StateError('No active GM Career'));

  Future<void> _advanceAiSelections(String slot) async {
    while (true) {
      final current = _requireCareer();
      final state = current.draftExecutionState;
      if (state.isCompleted ||
          state.isHumanTurn(
            order: current.draftOrder,
            userTeamId: current.userFranchiseId,
          )) {
        return;
      }
      await _saveCareerState(_draftService.executeAiSelection(current), slot);
    }
  }

  Future<void> _saveCareerState(GmCareer next, String slot) async {
    if (identical(next, _career)) return;
    final encoded = GmCareerCodec.encode(next);
    try {
      await storage.write(encoded, slot: slot);
    } catch (_) {
      _draftRecoveryRequired = true;
      rethrow;
    }
    _career = next;
    notifyListeners();
  }

  Future<void> _runCareerCommand(
    Future<void> Function() command, {
    required String action,
  }) => _serialize(() async {
    if (_disposed) {
      throw StateError('GmCareerController was disposed');
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      if (_draftRecoveryRequired) {
        throw StateError(
          'Reload saved GM Career before continuing after a failed save',
        );
      }
      await command();
    } catch (e) {
      if (!_disposed) {
        _errorMessage = 'Failed to $action: $e';
      }
      rethrow;
    } finally {
      if (!_disposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _serialize(Future<void> Function() command) {
    _inFlightCommands++;
    final result = _pendingCommand
        .then((_) => command())
        .whenComplete(() => _inFlightCommands--);
    _pendingCommand = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  /// Returns true if a save file exists for the given [slot].
  Future<bool> hasSavedCareer({String slot = 'default'}) async {
    return await storage.hasSave(slot: slot);
  }
}

Future<RolloverPrepareOutput> _defaultPrepareRolloverWorker(
  RolloverPrepareRequest request,
) => compute(prepareSeasonRolloverWorker, request);

GmCareer _simulateRegularSeasonRound(_RoundSimulationRequest request) =>
    const RegularSeasonRoundService().simulateNextRound(
      request.career,
      expectedRoundNumber: request.expectedRoundNumber,
    );

GmCareer _simulatePlayInGame(_PlayInSimulationRequest request) =>
    const PlayInGameService().simulateGame(
      request.career,
      expectedGameId: request.expectedGameId,
    );

PlayoffSlateWorkerOutput _simulatePlayoffSlateWorkOrder(
  PlayoffSlateWorkOrder order,
) => const PlayoffSlateService().simulatePreparedSlate(order);

final class _RoundSimulationRequest {
  const _RoundSimulationRequest(this.career, this.expectedRoundNumber);

  final GmCareer career;
  final int expectedRoundNumber;
}

final class _PlayInSimulationRequest {
  const _PlayInSimulationRequest(this.career, this.expectedGameId);

  final GmCareer career;
  final String expectedGameId;
}
