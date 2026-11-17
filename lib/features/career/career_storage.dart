import 'dart:io';

import 'package:simulation_core/simulation_core.dart';

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

/// File-backed persistent storage for GM Career saves with atomic promotion,
/// backup recovery, and strict isolation from M007 season saves.
class FileGmCareerStorage implements GmCareerStorage, GmCareerArchiveStorage {
  FileGmCareerStorage({this.filePath, this.directoryPath})
    : assert(
        filePath != null || directoryPath != null,
        'Either filePath or directoryPath must be provided',
      );

  final String? filePath;
  final String? directoryPath;

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

  /// Attempts to restore the previous verified save from backup if present and non-empty.
  Future<String?> recoverBackup({String slot = 'default'}) async {
    final file = _file(slot);
    final backup = _backupFile(slot);
    if (await backup.exists()) {
      try {
        final backupContent = await backup.readAsString();
        if (backupContent.trim().isNotEmpty) {
          await _replaceFile(backup, file);
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
      if (await file.exists()) {
        final len = await file.length();
        if (len > 0) return true;
      }
      final backup = _backupFile(slot);
      if (await backup.exists() && await backup.length() > 0) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> read({String slot = 'default'}) async {
    try {
      final file = _file(slot);
      final temp = _tempFile(slot);

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          return content;
        }

        // Active file exists but is empty/whitespace.
        // Attempt recovery from valid backup before returning unreadable content.
        final recovered = await recoverBackup(slot: slot);
        if (recovered != null) {
          return recovered;
        }

        // Recovery check: did an interrupted save leave a valid temp file?
        if (await temp.exists()) {
          try {
            final tempContent = await temp.readAsString();
            if (tempContent.trim().isNotEmpty) {
              await _replaceFile(temp, file);
              return tempContent;
            }
          } catch (_) {}
        }

        // Active file exists but is empty, and no backup was recoverable.
        // Return raw content so caller handles it as corrupted/empty save, NOT missing.
        return content;
      }

      // Active file does NOT exist.
      // Recovery check 1: backup exists
      final recovered = await recoverBackup(slot: slot);
      if (recovered != null) {
        return recovered;
      }

      // Recovery check 2: temp exists
      if (await temp.exists()) {
        try {
          final tempContent = await temp.readAsString();
          if (tempContent.trim().isNotEmpty) {
            await _replaceFile(temp, file);
            return tempContent;
          }
        } catch (_) {}
      }

      // Genuinely missing save
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
      // 1. Ensure directory exists
      await file.parent.create(recursive: true);

      // 2. Write completely to temp file in same directory and flush
      await temp.writeAsString(data, flush: true);

      // 3. Atomic promotion with backup preservation
      final fileExists = await file.exists();
      if (fileExists) {
        // Move current verified save to backup
        await _replaceFile(file, backup);

        try {
          // Promote temp to active file
          await _replaceFile(temp, file);

          // Verify destination is non-empty before deleting backup
          if (await file.exists() && await file.length() > 0) {
            if (await backup.exists()) {
              try {
                await backup.delete();
              } catch (_) {}
            }
          }
        } catch (promoteError) {
          // Promotion failed: clean up partial destination and restore backup
          if (await file.exists()) {
            try {
              await file.delete();
            } catch (_) {}
          }
          if (await backup.exists()) {
            try {
              await _replaceFile(backup, file);
            } catch (_) {}
          }
          throw GmCareerStorageException(
            'Failed to promote temp career save file: $promoteError',
            promoteError,
          );
        }
      } else {
        // No existing active file: promote temp directly
        await _replaceFile(temp, file);
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

  @override
  Future<void> writeArchive({
    required int seasonYear,
    required String archiveJson,
    required String expectedDigest,
    String slot = 'default',
  }) async {
    try {
      _validateSlot(slot);
      if (SeasonArchiveCodec.digestOf(archiveJson) != expectedDigest) {
        throw const GmCareerStorageException(
          'Archive payload digest does not match expectedDigest',
        );
      }
      final file = _archiveFile(seasonYear, slot);
      final temp = _archiveTempFile(seasonYear, slot);
      await file.parent.create(recursive: true);
      if (await file.exists()) {
        final existing = await file.readAsString();
        if (SeasonArchiveCodec.digestOf(existing) == expectedDigest) {
          if (await temp.exists()) {
            await temp.delete();
          }
          return;
        }
        throw GmCareerStorageException(
          'Conflicting historical archive already exists for slot "$slot" year $seasonYear',
        );
      }
      if (await temp.exists()) {
        await temp.delete();
      }
      try {
        await temp.writeAsString(archiveJson, flush: true);
        await _replaceFile(temp, file);
      } finally {
        if (await temp.exists()) {
          try {
            await temp.delete();
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
    }
  }

  @override
  Future<String?> readArchive({
    required int seasonYear,
    String slot = 'default',
  }) async {
    try {
      final file = _archiveFile(seasonYear, slot);
      if (await file.exists()) {
        return await file.readAsString();
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
    _validateSlot(slot);
    try {
      final file = _archiveFile(seasonYear, slot);
      return await file.exists() && await file.length() > 0;
    } catch (_) {
      return false;
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

  /// Platform-safe file replace: handles Windows replace semantics where
  /// File.rename throws when target exists.
  Future<void> _replaceFile(File source, File target) async {
    if (await target.exists()) {
      await target.delete();
    }
    try {
      await source.rename(target.path);
    } on FileSystemException {
      // Non-atomic copy fallback (handles cross-mount or rename locks)
      try {
        await source.copy(target.path);
        await source.delete();
      } catch (copyError) {
        if (await target.exists()) {
          try {
            await target.delete();
          } catch (_) {}
        }
        rethrow;
      }
    }
  }
}
