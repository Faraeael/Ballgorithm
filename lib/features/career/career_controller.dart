import 'package:flutter/foundation.dart';
import 'package:simulation_core/simulation_core.dart';

import 'career_storage.dart';

/// Manages loading, saving, and active runtime state for a persistent [GmCareer].
class GmCareerController extends ChangeNotifier {
  GmCareerController({required this.storage});

  final GmCareerStorage storage;

  GmCareer? _career;
  bool _isLoading = false;
  String? _errorMessage;
  Future<void> _pendingCommand = Future<void>.value();
  bool _draftRecoveryRequired = false;
  static const _draftService = DraftExecutionService();
  static const _signingService = RookieSigningService();
  static const _marketService = FreeAgentMarketService();
  static const _clearanceService = OffseasonClearanceService();
  static const _aiSigningService = RookieAiSigningService();
  static const _hardshipService = HardshipSettlementService();
  static const _regularSeasonEntryService = RegularSeasonEntryService();
  static const _regularSeasonScheduleService = RegularSeasonScheduleService();

  GmCareer? get career => _career;
  bool get hasCareer => _career != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Draft and signing commands remain blocked until a successful reload
  /// reconciles a failed or uncertain write.
  bool get draftRecoveryRequired => _draftRecoveryRequired;

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
          _career = GmCareerCodec.decode(raw);
        } catch (decodeError) {
          if (storage is FileGmCareerStorage) {
            final recovered = await (storage as FileGmCareerStorage)
                .recoverBackup(slot: slot);
            if (recovered != null) {
              _career = GmCareerCodec.decode(recovered);
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
      _errorMessage = 'Failed to $action: $e';
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  });

  Future<void> _serialize(Future<void> Function() command) {
    final result = _pendingCommand.then((_) => command());
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

GmCareer _simulateRegularSeasonRound(_RoundSimulationRequest request) =>
    const RegularSeasonRoundService().simulateNextRound(
      request.career,
      expectedRoundNumber: request.expectedRoundNumber,
    );

final class _RoundSimulationRequest {
  const _RoundSimulationRequest(this.career, this.expectedRoundNumber);

  final GmCareer career;
  final int expectedRoundNumber;
}
