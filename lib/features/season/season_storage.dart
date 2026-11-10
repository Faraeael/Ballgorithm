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

  @override
  Future<String?> read() async {
    try {
      final file = _file;
      final exists = await file.exists();

      if (!exists) {
        // Recovery check: Did an interrupted atomic promotion leave a backup?
        final backup = _backupFile;
        if (await backup.exists()) {
          try {
            await _replaceFile(backup, file);
            return await file.readAsString();
          } catch (e) {
            throw SeasonStorageException(
              'Failed to restore backup save file',
              e,
            );
          }
        }

        // Recovery check: Did an interrupted save leave a valid temp file?
        final temp = _tempFile;
        if (await temp.exists()) {
          try {
            await _replaceFile(temp, file);
            return await file.readAsString();
          } catch (e) {
            throw SeasonStorageException('Failed to restore temp save file', e);
          }
        }

        // Neither active, backup, nor temp exists: genuinely missing save
        return null;
      }

      return await file.readAsString();
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

      // 3. Atomic promotion with backup
      final fileExists = await file.exists();
      if (fileExists) {
        // Move current to backup
        if (await backup.exists()) {
          await backup.delete();
        }
        await _replaceFile(file, backup);

        try {
          // Promote temp to active
          await _replaceFile(temp, file);
          // Promotion succeeded, remove backup
          if (await backup.exists()) {
            await backup.delete();
          }
        } catch (promoteError) {
          // Promotion failed: restore backup to active file
          if (!await file.exists() && await backup.exists()) {
            await _replaceFile(backup, file);
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

  Future<void> _replaceFile(File source, File target) async {
    if (await target.exists()) {
      await target.delete();
    }
    try {
      await source.rename(target.path);
    } on FileSystemException {
      await source.copy(target.path);
      await source.delete();
    }
  }
}
