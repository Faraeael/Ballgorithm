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

  GmCareer? get career => _career;
  bool get hasCareer => _career != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Draft commands remain blocked until a successful reload reconciles a failed write.
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
  Future<void> startDraft({String slot = 'default'}) =>
      _runDraftCommand(() async {
        await _saveDraftState(_draftService.startDraft(_requireCareer()), slot);
        await _advanceAiSelections(slot);
      });

  /// Saves one human selection, then saves each following AI selection.
  Future<void> makeHumanSelection({
    required PlayerId prospectId,
    String slot = 'default',
  }) {
    final submittedCareer = _career;
    return _runDraftCommand(() async {
      final current = _requireCareer();
      if (!identical(current, submittedCareer)) {
        throw StateError('Career changed before the human selection executed');
      }
      final next = _draftService.makeHumanSelection(
        career: current,
        prospectId: prospectId,
      );
      await _saveDraftState(next, slot);
      await _advanceAiSelections(slot);
    });
  }

  /// Resumes AI picks from the last committed state without crossing a human turn.
  Future<void> advanceDraft({String slot = 'default'}) =>
      _runDraftCommand(() async {
        if (_requireCareer().draftExecutionState.isNotStarted) {
          throw StateError('Cannot advance a draft before it starts');
        }
        await _advanceAiSelections(slot);
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
      await _saveDraftState(_draftService.executeAiSelection(current), slot);
    }
  }

  Future<void> _saveDraftState(GmCareer next, String slot) async {
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

  Future<void> _runDraftCommand(
    Future<void> Function() command,
  ) => _serialize(() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      if (_draftRecoveryRequired) {
        throw StateError(
          'Reload saved GM Career before continuing after a failed draft save',
        );
      }
      await command();
    } catch (e) {
      _errorMessage = 'Failed to execute rookie draft: $e';
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
