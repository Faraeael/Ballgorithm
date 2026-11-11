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

  GmCareer? get career => _career;
  bool get hasCareer => _career != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Loads the saved career from [storage].
  Future<void> loadCareer({String slot = 'default'}) async {
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
              return;
            }
          }
          rethrow;
        }
      }
    } catch (e) {
      _errorMessage =
          'Failed to load saved GM Career: $e. Save file preserved without deletion.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Initializes and persists a new [GmCareer] from a verified [CareerSetupResult].
  Future<void> startCareer(
    CareerSetupResult setupResult, {
    String slot = 'default',
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final newCareer = GmCareer.fromSetupResult(setupResult);
      final jsonString = GmCareerCodec.encode(newCareer);
      await storage.write(jsonString, slot: slot);
      _career = newCareer;
    } catch (e) {
      _errorMessage = 'Failed to save new GM Career: $e';
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clears active career and deletes storage file for the given [slot].
  Future<void> clearCareer({String slot = 'default'}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await storage.clear(slot: slot);
      _career = null;
    } catch (e) {
      _errorMessage = 'Failed to clear GM Career: $e';
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Returns true if a save file exists for the given [slot].
  Future<bool> hasSavedCareer({String slot = 'default'}) async {
    return await storage.hasSave(slot: slot);
  }
}
