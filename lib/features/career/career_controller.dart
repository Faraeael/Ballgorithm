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
  static const _offerService = FreeAgentOfferSubmissionService();
  static const _marketService = FreeAgentMarketService();
  static const _aiSigningService = RookieAiSigningService();

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

  /// Submits one formal free-agent offer for the human franchise.
  ///
  /// The player decision and any acquisition are persisted before publication.
  /// Rejected offers are durable; invalid/financially illegal offers consume no
  /// attempt and are not saved. A failed write blocks further commands until
  /// an explicit reload.
  @Deprecated(
    'Use stageFreeAgentOffer and the shared market round; retained for '
    'historical T08F domain workflows and tests.',
  )
  Future<FreeAgentOfferSubmissionResult> submitFreeAgentOffer({
    required PlayerId freeAgentId,
    required RosterCategory category,
    required int durationYears,
    required int agreedFirstYearSalary,
    String slot = 'default',
  }) {
    final submittedCareer = _career;
    FreeAgentOfferSubmissionResult? result;
    final command = _runCareerCommand(
      action: 'submit free-agent offer',
      () async {
        final current = _requireCareer();
        if (!identical(current, submittedCareer)) {
          throw StateError('Career changed before the offer executed');
        }
        final submission = _offerService.submit(
          career: current,
          teamId: current.userFranchiseId,
          freeAgentId: freeAgentId,
          category: category,
          durationYears: durationYears,
          agreedFirstYearSalary: agreedFirstYearSalary,
        );
        result = submission;
        if (submission.recorded) {
          await _saveCareerState(submission.career, slot);
        }
      },
    );
    return command.then((_) => result!);
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
