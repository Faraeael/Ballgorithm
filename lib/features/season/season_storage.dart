import 'dart:io';

class SeasonStorageException implements Exception {
  const SeasonStorageException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => cause != null
      ? 'SeasonStorageException: $message (Caused by: $cause)'
      : 'SeasonStorageException: $message';
}

abstract interface class SeasonStorage {
  Future<String?> read();
  Future<void> write(String data);
  Future<void> clear();
}

class InMemorySeasonStorage implements SeasonStorage {
  InMemorySeasonStorage([this._data]);

  String? _data;
  bool shouldThrowOnRead = false;
  bool shouldThrowOnWrite = false;
  bool shouldThrowOnClear = false;

  @override
  Future<String?> read() async {
    if (shouldThrowOnRead) {
      throw const SeasonStorageException('Injected in-memory read error');
    }
    return _data;
  }

  @override
  Future<void> write(String data) async {
    if (shouldThrowOnWrite) {
      throw const SeasonStorageException('Injected in-memory write error');
    }
    _data = data;
  }

  @override
  Future<void> clear() async {
    if (shouldThrowOnClear) {
      throw const SeasonStorageException('Injected in-memory clear error');
    }
    _data = null;
  }
}

class FileSeasonStorage implements SeasonStorage {
  FileSeasonStorage({required this.filePath});

  final String filePath;

  File get _file => File(filePath);
  File get _tempFile => File('$filePath.tmp');
  File get _backupFile => File('$filePath.bak');

  /// Attempts to restore the previous verified save from backup if present and non-empty.
  Future<String?> recoverBackup() async {
    final file = _file;
    final backup = _backupFile;
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
  Future<String?> read() async {
    try {
      final file = _file;
      final temp = _tempFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          return content;
        }

        // Active file exists but is empty/whitespace.
        // Attempt recovery from valid backup before returning unreadable content.
        final recovered = await recoverBackup();
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
        // Return raw content so controller handles it as corrupted/empty save, NOT missing.
        return content;
      }

      // Active file does NOT exist.
      // Recovery check 1: backup exists
      final recovered = await recoverBackup();
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
      throw SeasonStorageException(
        'File system error reading save: ${e.message}',
        e,
      );
    } catch (e) {
      if (e is SeasonStorageException) rethrow;
      throw SeasonStorageException('Unexpected error reading save: $e', e);
    }
  }

  @override
  Future<void> write(String data) async {
    final file = _file;
    final temp = _tempFile;
    final backup = _backupFile;

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
          throw SeasonStorageException(
            'Failed to promote temp save file: $promoteError',
            promoteError,
          );
        }
      } else {
        // No existing active file: promote temp directly
        await _replaceFile(temp, file);
      }
    } on FileSystemException catch (e) {
      throw SeasonStorageException(
        'File system error writing save: ${e.message}',
        e,
      );
    } catch (e) {
      if (e is SeasonStorageException) rethrow;
      throw SeasonStorageException('Unexpected error writing save: $e', e);
    }
  }

  @override
  Future<void> clear() async {
    try {
      final file = _file;
      final temp = _tempFile;
      final backup = _backupFile;

      if (await file.exists()) {
        await file.delete();
      }
      if (await backup.exists()) {
        await backup.delete();
      }
      if (await temp.exists()) {
        await temp.delete();
      }
    } on FileSystemException catch (e) {
      throw SeasonStorageException(
        'File system error clearing save: ${e.message}',
        e,
      );
    } catch (e) {
      if (e is SeasonStorageException) rethrow;
      throw SeasonStorageException('Unexpected error clearing save: $e', e);
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
        // If copy fails halfway, clean up partial target to prevent corrupt active save
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
