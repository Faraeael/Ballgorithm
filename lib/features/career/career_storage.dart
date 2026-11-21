import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:simulation_core/simulation_core.dart';

import 'rollover_isolate_workers.dart';

class GmCareerStorageException implements Exception {
  const GmCareerStorageException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => cause != null
      ? 'GmCareerStorageException: $message (Caused by: $cause)'
      : 'GmCareerStorageException: $message';
}

/// Abstract storage interface for persistent GM Career data.
///
/// Designed to support multiple save slots via the optional [slot] parameter
/// while maintaining a single authoritative career slot by default.
abstract interface class GmCareerStorage {
  Future<String?> read({String slot = 'default'});
  Future<void> write(String data, {String slot = 'default'});
  Future<void> clear({String slot = 'default'});
  Future<bool> hasSave({String slot = 'default'});
}

/// Abstract archive storage interface for immutable per-season archives.
abstract interface class GmCareerArchiveStorage {
  Future<void> writeArchive({
    required int seasonYear,
    required String archiveJson,
    required String expectedDigest,
    String slot = 'default',
  });

  Future<String?> readArchive({
    required int seasonYear,
    String slot = 'default',
  });

  Future<bool> hasArchive({required int seasonYear, String slot = 'default'});

  Future<void> clearArchives({String slot = 'default'});
}

/// In-memory storage implementation for tests and web preview demonstrations.
class InMemoryGmCareerStorage
    implements GmCareerStorage, GmCareerArchiveStorage {
  InMemoryGmCareerStorage([Map<String, String?>? initialSlots])
    : _slots = initialSlots ?? {};

  final Map<String, String?> _slots;
  final Map<(String, int), String> _archives = {};
  bool shouldThrowOnRead = false;
  bool shouldThrowOnWrite = false;
  bool shouldThrowOnClear = false;
  bool shouldThrowOnWriteArchive = false;
  bool shouldThrowOnReadArchive = false;

  @override
  Future<String?> read({String slot = 'default'}) async {
    if (shouldThrowOnRead) {
      throw const GmCareerStorageException('Injected in-memory read error');
    }
    return _slots[slot];
  }

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    if (shouldThrowOnWrite) {
      throw const GmCareerStorageException('Injected in-memory write error');
    }
    _slots[slot] = data;
  }

  @override
  Future<void> clear({String slot = 'default'}) async {
    if (shouldThrowOnClear) {
      throw const GmCareerStorageException('Injected in-memory clear error');
    }
    _slots.remove(slot);
    await clearArchives(slot: slot);
  }

  @override
  Future<bool> hasSave({String slot = 'default'}) async {
    final data = _slots[slot];
    return data != null && data.trim().isNotEmpty;
  }

  @override
  Future<void> writeArchive({
    required int seasonYear,
    required String archiveJson,
    required String expectedDigest,
    String slot = 'default',
  }) async {
    if (shouldThrowOnWriteArchive) {
      throw const GmCareerStorageException(
        'Injected in-memory archive write error',
      );
    }
    if (SeasonArchiveCodec.digestOf(archiveJson) != expectedDigest) {
      throw const GmCareerStorageException(
        'Archive payload digest does not match expectedDigest',
      );
    }
    final existing = _archives[(slot, seasonYear)];
    if (existing != null) {
      if (SeasonArchiveCodec.digestOf(existing) == expectedDigest) {
        return;
      }
      throw GmCareerStorageException(
        'Conflicting historical archive already exists for slot "$slot" year $seasonYear',
      );
    }
    _archives[(slot, seasonYear)] = archiveJson;
  }

  @override
  Future<String?> readArchive({
    required int seasonYear,
    String slot = 'default',
  }) async {
    if (shouldThrowOnReadArchive) {
      throw const GmCareerStorageException(
        'Injected in-memory archive read error',
      );
    }
    return _archives[(slot, seasonYear)];
  }

  @override
  Future<bool> hasArchive({
    required int seasonYear,
    String slot = 'default',
  }) async {
    final data = _archives[(slot, seasonYear)];
    return data != null && data.trim().isNotEmpty;
  }

  @override
  Future<void> clearArchives({String slot = 'default'}) async {
    if (shouldThrowOnClear) {
      throw const GmCareerStorageException('Injected in-memory clear error');
    }
    _archives.removeWhere((key, _) => key.$1 == slot);
  }
}

/// Narrow filesystem operations seam for deterministic durability fault injection.
@visibleForTesting
abstract interface class CareerStorageFileOps {
  Future<bool> exists(File file);
  Future<int> length(File file);
  Future<String> readAsString(File file);
  Future<void> writeAsString(File file, String contents, {bool flush = false});
  Future<void> rename(File source, String newPath);
  Future<void> copy(File source, String newPath);
  Future<void> delete(File file);
  Future<void> createParentDir(File file);
}

final class _DartCareerStorageFileOps implements CareerStorageFileOps {
  const _DartCareerStorageFileOps();

  @override
  Future<bool> exists(File file) => file.exists();

  @override
  Future<int> length(File file) => file.length();

  @override
  Future<String> readAsString(File file) => file.readAsString();

  @override
  Future<void> writeAsString(
    File file,
    String contents, {
    bool flush = false,
  }) => file.writeAsString(contents, flush: flush);

  @override
  Future<void> rename(File source, String newPath) => source.rename(newPath);

  @override
  Future<void> copy(File source, String newPath) => source.copy(newPath);

  @override
  Future<void> delete(File file) => file.delete();

  @override
  Future<void> createParentDir(File file) =>
      file.parent.create(recursive: true);
}

/// File-backed persistent storage for GM Career saves with validated recovery,
/// staged promotion, and strict isolation from M007 season saves.
class FileGmCareerStorage implements GmCareerStorage, GmCareerArchiveStorage {
  FileGmCareerStorage({
    this.filePath,
    this.directoryPath,
    @visibleForTesting CareerStorageFileOps? fileOps,
    @visibleForTesting
    Future<void> Function(ArchiveVerifyRequest)? verifyArchiveWorker,
    @visibleForTesting
    Future<ExistingArchiveClassification> Function(
      ExistingArchiveClassifyRequest,
    )?
    classifyArchiveWorker,
    @visibleForTesting Future<String> Function(String)? digestArchiveWorker,
    @visibleForTesting
    Future<List<ActiveCareerArchiveRef>?> Function(String)?
    extractActiveRefsWorker,
  }) : assert(
         filePath != null || directoryPath != null,
         'Either filePath or directoryPath must be provided',
       ),
       _fileOps = fileOps ?? const _DartCareerStorageFileOps(),
       _hasCustomWorkers =
           verifyArchiveWorker != null ||
           classifyArchiveWorker != null ||
           digestArchiveWorker != null ||
           extractActiveRefsWorker != null,
       _verifyArchiveWorker =
           verifyArchiveWorker ?? _defaultVerifyArchiveWorker,
       _classifyArchiveWorker =
           classifyArchiveWorker ?? _defaultClassifyArchiveWorker,
       _digestArchiveWorker =
           digestArchiveWorker ?? _defaultDigestArchiveWorker,
       _extractActiveRefsWorker =
           extractActiveRefsWorker ?? _defaultExtractActiveRefsWorker;

  final String? filePath;
  final String? directoryPath;
  final CareerStorageFileOps _fileOps;
  final bool _hasCustomWorkers;
  final Future<void> Function(ArchiveVerifyRequest) _verifyArchiveWorker;
  final Future<ExistingArchiveClassification> Function(
    ExistingArchiveClassifyRequest,
  )
  _classifyArchiveWorker;
  final Future<String> Function(String) _digestArchiveWorker;
  final Future<List<ActiveCareerArchiveRef>?> Function(String)
  _extractActiveRefsWorker;

  static Future<void> _defaultVerifyArchiveWorker(
    ArchiveVerifyRequest request,
  ) => compute(verifySeasonArchiveWorker, request);

  static Future<ExistingArchiveClassification> _defaultClassifyArchiveWorker(
    ExistingArchiveClassifyRequest request,
  ) => compute(classifyExistingArchiveWorker, request);

  static Future<String> _defaultDigestArchiveWorker(String archiveJson) =>
      compute(digestSeasonArchiveWorker, archiveJson);

  static Future<List<ActiveCareerArchiveRef>?> _defaultExtractActiveRefsWorker(
    String rawCareerJson,
  ) => compute(extractActiveCareerArchiveRefsWorker, rawCareerJson);

  static const List<Duration> _transientRetryDelays = [
    Duration(milliseconds: 15),
    Duration(milliseconds: 30),
    Duration(milliseconds: 60),
  ];

  static bool _isTransientLockError(FileSystemException e) {
    final code = e.osError?.errorCode;
    // Windows ERROR_SHARING_VIOLATION (32) and ERROR_LOCK_VIOLATION (33).
    return code == 32 || code == 33;
  }

  Future<T> _withTransientRetry<T>(Future<T> Function() operation) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await operation();
      } on FileSystemException catch (e) {
        if (!_isTransientLockError(e) ||
            attempt >= _transientRetryDelays.length) {
          rethrow;
        }
        await Future<void>.delayed(_transientRetryDelays[attempt]);
      }
    }
  }

  String resolvePath([String slot = 'default']) {
    _validateSlot(slot);
    if (filePath != null && slot == 'default') {
      return filePath!;
    }
    final base =
        directoryPath ?? (filePath != null ? File(filePath!).parent.path : '.');
    final fileName = slot == 'default'
        ? 'ballgorithm_gm_career.json'
        : 'ballgorithm_gm_career_$slot.json';
    return '$base/$fileName';
  }

  File _file(String slot) => File(resolvePath(slot));
  File _tempFile(String slot) => File('${resolvePath(slot)}.tmp');
  File _backupFile(String slot) => File('${resolvePath(slot)}.bak');
  File _corruptFile(String slot, int stamp) =>
      File('${resolvePath(slot)}.corrupt.$stamp');

  bool _isValidCareerJson(String content) {
    if (content.trim().isEmpty) return false;
    try {
      GmCareerCodec.decode(content);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _quarantineIfPresent(File file, String slot) async {
    if (!await _fileOps.exists(file)) return;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final quarantine = _corruptFile(slot, stamp);
    try {
      await _withTransientRetry(() => _fileOps.rename(file, quarantine.path));
    } catch (_) {
      try {
        await _withTransientRetry(() => _fileOps.copy(file, quarantine.path));
        await _withTransientRetry(() => _fileOps.delete(file));
      } catch (_) {}
    }
  }

  /// Attempts to restore a [GmCareerCodec]-validated backup if the active save
  /// is missing, empty, or invalid. Never overwrites a valid active career.
  Future<String?> recoverBackup({String slot = 'default'}) async {
    final file = _file(slot);
    final backup = _backupFile(slot);
    if (await _fileOps.exists(file)) {
      try {
        final activeContent = await _fileOps.readAsString(file);
        if (_isValidCareerJson(activeContent)) {
          return null;
        }
      } catch (_) {}
    }
    if (await _fileOps.exists(backup)) {
      try {
        final backupContent = await _fileOps.readAsString(backup);
        if (_isValidCareerJson(backupContent)) {
          if (await _fileOps.exists(file)) {
            final activeContent = await _fileOps.readAsString(file);
            if (activeContent.trim().isNotEmpty) {
              await _quarantineIfPresent(file, slot);
            } else {
              await _withTransientRetry(() => _fileOps.delete(file));
            }
          }
          await _promoteActiveFile(backup, file);
          return backupContent;
        }
      } catch (_) {}
    }
    return null;
  }

  @override
  Future<bool> hasSave({String slot = 'default'}) async {
    _validateSlot(slot);
    try {
      final file = _file(slot);
      if (await _fileOps.exists(file)) {
        return true;
      }
      final backup = _backupFile(slot);
      if (await _fileOps.exists(backup)) {
        return true;
      }
      final temp = _tempFile(slot);
      if (await _fileOps.exists(temp)) {
        return true;
      }
      return false;
    } on FileSystemException catch (e) {
      throw GmCareerStorageException(
        'File system error checking career save: ${e.message}',
        e,
      );
    } catch (e) {
      if (e is GmCareerStorageException) rethrow;
      throw GmCareerStorageException(
        'Unexpected error checking career save: $e',
        e,
      );
    }
  }

  @override
  Future<String?> read({String slot = 'default'}) async {
    try {
      final file = _file(slot);
      final temp = _tempFile(slot);

      if (await _fileOps.exists(file)) {
        final content = await _fileOps.readAsString(file);
        if (_isValidCareerJson(content)) {
          return content;
        }

        // Active file is empty or fails career validation:
        // 1. Prefer validated backup (last known-good committed save).
        final recovered = await recoverBackup(slot: slot);
        if (recovered != null) {
          return recovered;
        }

        // 2. Fall back to validated temp only if no valid backup exists.
        if (await _fileOps.exists(temp)) {
          try {
            final tempContent = await _fileOps.readAsString(temp);
            if (_isValidCareerJson(tempContent)) {
              if (content.trim().isNotEmpty) {
                await _quarantineIfPresent(file, slot);
              } else {
                await _withTransientRetry(() => _fileOps.delete(file));
              }
              await _promoteActiveFile(temp, file);
              return tempContent;
            }
          } catch (_) {}
        }

        // 3. Preserve non-empty active bytes (including legacy/corrupt fixtures)
        // or return empty string so caller treats it as corrupt/empty, not missing.
        return content;
      }

      // Active file does NOT exist.
      // Recovery check 1: validated backup exists.
      final recovered = await recoverBackup(slot: slot);
      if (recovered != null) {
        return recovered;
      }

      // Recovery check 2: validated temp exists.
      if (await _fileOps.exists(temp)) {
        try {
          final tempContent = await _fileOps.readAsString(temp);
          if (_isValidCareerJson(tempContent)) {
            await _promoteActiveFile(temp, file);
            return tempContent;
          }
        } catch (_) {}
      }

      // If any save artifacts remain on disk when active is missing and none
      // are valid, surface an explicit storage error instead of presenting the
      // slot as genuinely empty.
      if (await _fileOps.exists(_backupFile(slot)) ||
          await _fileOps.exists(temp)) {
        throw GmCareerStorageException(
          'Save artifacts exist for slot "$slot" but no valid career could be recovered',
        );
      }

      // Genuinely missing save (active, backup, and temp are all absent).
      return null;
    } on FileSystemException catch (e) {
      throw GmCareerStorageException(
        'File system error reading career save: ${e.message}',
        e,
      );
    } catch (e) {
      if (e is GmCareerStorageException) rethrow;
      throw GmCareerStorageException(
        'Unexpected error reading career save: $e',
        e,
      );
    }
  }

  @override
  Future<void> write(String data, {String slot = 'default'}) async {
    final file = _file(slot);
    final temp = _tempFile(slot);
    final backup = _backupFile(slot);

    try {
      // 1. Ensure directory exists.
      await _fileOps.createParentDir(file);

      // 2. Write completely to temp file in same directory, flush, and verify.
      await _fileOps.writeAsString(temp, data, flush: true);
      if (!await _fileOps.exists(temp) || await _fileOps.length(temp) <= 0) {
        throw const GmCareerStorageException(
          'Staged career temp file is missing or empty after flush',
        );
      }

      // 3. Promote staged temp with backup preservation.
      final fileExists = await _fileOps.exists(file);
      if (fileExists) {
        var movedActiveToBackup = false;
        var preserveExistingValidBackup = false;
        if (await _fileOps.exists(backup)) {
          try {
            final backupContent = await _fileOps.readAsString(backup);
            final activeContent = await _fileOps.readAsString(file);
            if (_isValidCareerJson(backupContent) &&
                !_isValidCareerJson(activeContent)) {
              preserveExistingValidBackup = true;
            }
          } catch (_) {}
        }

        if (preserveExistingValidBackup) {
          await _withTransientRetry(() => _fileOps.delete(file));
        } else {
          await _promoteActiveFile(file, backup);
          movedActiveToBackup = true;
        }

        try {
          await _promoteActiveFile(temp, file);
          if (!await _fileOps.exists(file) ||
              await _fileOps.length(file) <= 0) {
            throw const GmCareerStorageException(
              'Promoted career save file is missing or empty',
            );
          }
          if (await _fileOps.exists(backup)) {
            try {
              await _withTransientRetry(() => _fileOps.delete(backup));
            } catch (_) {}
          }
        } catch (promoteError) {
          if (await _fileOps.exists(file)) {
            try {
              await _withTransientRetry(() => _fileOps.delete(file));
            } catch (_) {}
          }
          if ((movedActiveToBackup || preserveExistingValidBackup) &&
              await _fileOps.exists(backup)) {
            try {
              await _promoteActiveFile(backup, file);
            } catch (_) {}
          }
          throw GmCareerStorageException(
            'Failed to promote temp career save file: $promoteError',
            promoteError,
          );
        }
      } else {
        await _promoteActiveFile(temp, file);
        if (!await _fileOps.exists(file) || await _fileOps.length(file) <= 0) {
          throw const GmCareerStorageException(
            'Promoted career save file is missing or empty',
          );
        }
        if (await _fileOps.exists(backup)) {
          try {
            await _withTransientRetry(() => _fileOps.delete(backup));
          } catch (_) {}
        }
      }
    } on FileSystemException catch (e) {
      throw GmCareerStorageException(
        'File system error writing career save: ${e.message}',
        e,
      );
    } catch (e) {
      if (e is GmCareerStorageException) rethrow;
      throw GmCareerStorageException(
        'Unexpected error writing career save: $e',
        e,
      );
    }
  }

  /// Promotes [source] to [target] using bounded transient-lock retries.
  ///
  /// Deletes any existing [target] before rename on Windows; if rename fails,
  /// falls back to copy-then-delete and cleans up partial [target] on error.
  Future<void> _promoteActiveFile(File source, File target) async {
    if (await _fileOps.exists(target)) {
      await _withTransientRetry(() => _fileOps.delete(target));
    }
    try {
      await _withTransientRetry(() => _fileOps.rename(source, target.path));
    } on FileSystemException {
      try {
        await _withTransientRetry(() => _fileOps.copy(source, target.path));
        try {
          await _withTransientRetry(() => _fileOps.delete(source));
        } catch (_) {}
      } catch (copyError) {
        if (await _fileOps.exists(target)) {
          try {
            await _withTransientRetry(() => _fileOps.delete(target));
          } catch (_) {}
        }
        rethrow;
      }
    }
  }

  String _baseDirectory() =>
      directoryPath ?? (filePath != null ? File(filePath!).parent.path : '.');

  static final RegExp _validSlotPattern = RegExp(r'^[a-z0-9_-]+$');

  void _validateSlot(String slot) {
    if (!_validSlotPattern.hasMatch(slot)) {
      throw GmCareerStorageException('Invalid career save slot: "$slot"');
    }
  }

  String resolveArchivePath(int seasonYear, [String slot = 'default']) {
    _validateSlot(slot);
    if (seasonYear < 1) {
      throw GmCareerStorageException('Invalid archive seasonYear: $seasonYear');
    }
    final base = _baseDirectory();
    final fileName = slot == 'default'
        ? 'ballgorithm_gm_career_archive_y$seasonYear.json'
        : 'ballgorithm_gm_career_${slot}_archive_y$seasonYear.json';
    return '$base/$fileName';
  }

  File _archiveFile(int seasonYear, String slot) =>
      File(resolveArchivePath(seasonYear, slot));

  File _archiveTempFile(int seasonYear, String slot) =>
      File('${resolveArchivePath(seasonYear, slot)}.tmp');

  Future<File> _nextArchiveQuarantineFile(int seasonYear, String slot) async {
    final basePath = resolveArchivePath(seasonYear, slot);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    var candidate = File('$basePath.corrupt.$stamp');
    var counter = 0;
    while (await _fileOps.exists(candidate)) {
      counter++;
      candidate = File('$basePath.corrupt.$stamp.$counter');
    }
    return candidate;
  }

  Future<List<ActiveCareerArchiveRef>?>
  _readValidActiveCareerArchiveRefsForSlot(
    String slot, {
    Future<List<ActiveCareerArchiveRef>?> Function(String)? extractRefs,
  }) async {
    final extractor = extractRefs ?? _extractActiveRefsWorker;
    final file = _file(slot);
    if (await _fileOps.exists(file)) {
      final raw = await _fileOps.readAsString(file);
      if (raw.trim().isNotEmpty) {
        final refs = await extractor(raw);
        if (refs != null) return refs;
      }
    }
    final backup = _backupFile(slot);
    if (await _fileOps.exists(backup)) {
      final raw = await _fileOps.readAsString(backup);
      if (raw.trim().isNotEmpty) {
        final refs = await extractor(raw);
        if (refs != null) return refs;
      }
    }
    return null;
  }

  Future<void> _quarantineArchiveFile(
    File file, {
    required int seasonYear,
    required String slot,
  }) async {
    final quarantine = await _nextArchiveQuarantineFile(seasonYear, slot);
    try {
      await _withTransientRetry(() => _fileOps.rename(file, quarantine.path));
    } on FileSystemException {
      await _withTransientRetry(() => _fileOps.copy(file, quarantine.path));
      await _withTransientRetry(() => _fileOps.delete(file));
    }
    if (await _fileOps.exists(file) || !await _fileOps.exists(quarantine)) {
      throw GmCareerStorageException(
        'Failed to quarantine corrupt archive for slot "$slot" year $seasonYear',
      );
    }
  }

  Future<void> _promoteArchiveFile(File source, File target) async {
    if (await _fileOps.exists(target)) {
      throw GmCareerStorageException(
        'Refusing to overwrite existing archive destination: ${target.path}',
      );
    }
    try {
      await _withTransientRetry(() => _fileOps.rename(source, target.path));
    } on FileSystemException {
      try {
        await _withTransientRetry(() => _fileOps.copy(source, target.path));
        try {
          await _withTransientRetry(() => _fileOps.delete(source));
        } catch (_) {}
      } catch (copyError) {
        if (await _fileOps.exists(target)) {
          try {
            await _withTransientRetry(() => _fileOps.delete(target));
          } catch (_) {}
        }
        rethrow;
      }
    }
  }

  @override
  Future<void> writeArchive({
    required int seasonYear,
    required String archiveJson,
    required String expectedDigest,
    String slot = 'default',
  }) async {
    ArchiveWorkerSession? session;
    try {
      resolveArchivePath(seasonYear, slot);

      if (!_hasCustomWorkers && !kIsWeb) {
        session = await ArchiveWorkerSession.start();
      }
      final verifyFn = session != null
          ? session.verifyArchive
          : _verifyArchiveWorker;
      final extractRefsFn = session != null
          ? session.extractActiveRefs
          : _extractActiveRefsWorker;
      final classifyFn = session != null
          ? session.classifyExisting
          : _classifyArchiveWorker;
      final digestFn = session != null
          ? session.digestArchive
          : _digestArchiveWorker;

      // 1. Validate full incoming SeasonArchive (including SHA-256 digest) off main isolate before touching disk.
      try {
        await verifyFn(
          ArchiveVerifyRequest(
            archiveJson: archiveJson,
            expectedDigest: expectedDigest,
            expectedSeasonYear: seasonYear,
          ),
        );
      } catch (e) {
        throw GmCareerStorageException(
          'Invalid incoming season archive for slot "$slot" year $seasonYear: $e',
          e,
        );
      }

      // 2. Verify active career history digest if present in slot.
      final activeRefs = await _readValidActiveCareerArchiveRefsForSlot(
        slot,
        extractRefs: extractRefsFn,
      );
      if (activeRefs != null) {
        for (final record in activeRefs) {
          if (record.seasonYear == seasonYear &&
              record.archiveDigest != expectedDigest) {
            throw GmCareerStorageException(
              'Active career in slot "$slot" references a different archive '
              'digest for year $seasonYear',
            );
          }
        }
      }

      final file = _archiveFile(seasonYear, slot);
      final temp = _archiveTempFile(seasonYear, slot);
      await _fileOps.createParentDir(file);

      // 3. Classify existing destination archive off main isolate.
      if (await _fileOps.exists(file)) {
        final existing = await _fileOps.readAsString(file);
        final classification = await classifyFn(
          ExistingArchiveClassifyRequest(
            existingJson: existing,
            expectedDigest: expectedDigest,
            expectedSeasonYear: seasonYear,
          ),
        );
        if (classification.matchesExpected) {
          if (await _fileOps.exists(temp)) {
            await _withTransientRetry(() => _fileOps.delete(temp));
          }
          return;
        }

        if (classification.isStructurallyValid) {
          throw GmCareerStorageException(
            'Conflicting historical archive already exists for slot "$slot" '
            'year $seasonYear (career "${classification.careerId}")',
          );
        }

        // Corrupt/partial archive: quarantine with evidence preservation.
        await _quarantineArchiveFile(file, seasonYear: seasonYear, slot: slot);
      }

      // 4. Stage, flush, verify, and promote without deleting a valid target.
      if (await _fileOps.exists(temp)) {
        await _withTransientRetry(() => _fileOps.delete(temp));
      }
      try {
        await _fileOps.writeAsString(temp, archiveJson, flush: true);
        if (!await _fileOps.exists(temp) || await _fileOps.length(temp) <= 0) {
          throw const GmCareerStorageException(
            'Staged archive temp file is missing or empty after flush',
          );
        }
        final stagedContent = await _fileOps.readAsString(temp);
        if (await digestFn(stagedContent) != expectedDigest) {
          throw const GmCareerStorageException(
            'Staged archive temp file digest mismatch after flush',
          );
        }

        await _promoteArchiveFile(temp, file);

        if (!await _fileOps.exists(file)) {
          throw const GmCareerStorageException(
            'Promoted season archive file is missing',
          );
        }
        final promotedContent = await _fileOps.readAsString(file);
        if (await digestFn(promotedContent) != expectedDigest) {
          throw const GmCareerStorageException(
            'Promoted season archive digest verification failed',
          );
        }
      } finally {
        if (await _fileOps.exists(temp)) {
          try {
            await _withTransientRetry(() => _fileOps.delete(temp));
          } catch (_) {}
        }
      }
    } on FileSystemException catch (e) {
      throw GmCareerStorageException(
        'File system error writing season archive: ${e.message}',
        e,
      );
    } catch (e) {
      if (e is GmCareerStorageException) rethrow;
      throw GmCareerStorageException(
        'Unexpected error writing season archive: $e',
        e,
      );
    } finally {
      await session?.close();
    }
  }

  @override
  Future<String?> readArchive({
    required int seasonYear,
    String slot = 'default',
  }) async {
    try {
      final file = _archiveFile(seasonYear, slot);
      if (await _fileOps.exists(file)) {
        return await _fileOps.readAsString(file);
      }
      return null;
    } on FileSystemException catch (e) {
      throw GmCareerStorageException(
        'File system error reading season archive: ${e.message}',
        e,
      );
    } catch (e) {
      if (e is GmCareerStorageException) rethrow;
      throw GmCareerStorageException(
        'Unexpected error reading season archive: $e',
        e,
      );
    }
  }

  @override
  Future<bool> hasArchive({
    required int seasonYear,
    String slot = 'default',
  }) async {
    resolveArchivePath(seasonYear, slot);
    try {
      final file = _archiveFile(seasonYear, slot);
      return await _fileOps.exists(file);
    } on FileSystemException catch (e) {
      throw GmCareerStorageException(
        'File system error checking season archive: ${e.message}',
        e,
      );
    } catch (e) {
      if (e is GmCareerStorageException) rethrow;
      throw GmCareerStorageException(
        'Unexpected error checking season archive: $e',
        e,
      );
    }
  }

  @override
  Future<void> clearArchives({String slot = 'default'}) async {
    try {
      _validateSlot(slot);
      final dir = Directory(_baseDirectory());
      if (!await dir.exists()) return;
      final pattern = slot == 'default'
          ? RegExp(r'^ballgorithm_gm_career_archive_y\d+\.json(\.tmp)?$')
          : RegExp(
              '^ballgorithm_gm_career_${RegExp.escape(slot)}_archive_y\\d+\\.json(\\.tmp)?\$',
            );
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (pattern.hasMatch(name)) {
            await entity.delete();
          }
        }
      }
    } on FileSystemException catch (e) {
      throw GmCareerStorageException(
        'File system error clearing season archives: ${e.message}',
        e,
      );
    } catch (e) {
      if (e is GmCareerStorageException) rethrow;
      throw GmCareerStorageException(
        'Unexpected error clearing season archives: $e',
        e,
      );
    }
  }

  @override
  Future<void> clear({String slot = 'default'}) async {
    try {
      final file = _file(slot);
      final temp = _tempFile(slot);
      final backup = _backupFile(slot);

      if (await file.exists()) {
        await file.delete();
      }
      if (await backup.exists()) {
        await backup.delete();
      }
      if (await temp.exists()) {
        await temp.delete();
      }
      await clearArchives(slot: slot);
    } on FileSystemException catch (e) {
      throw GmCareerStorageException(
        'File system error clearing career save: ${e.message}',
        e,
      );
    } catch (e) {
      if (e is GmCareerStorageException) rethrow;
      throw GmCareerStorageException(
        'Unexpected error clearing career save: $e',
        e,
      );
    }
  }
}
