import 'dart:io';

abstract interface class SeasonStorage {
  Future<String?> read();
  Future<void> write(String data);
  Future<void> clear();
}

class InMemorySeasonStorage implements SeasonStorage {
  InMemorySeasonStorage([this._data]);

  String? _data;

  @override
  Future<String?> read() async => _data;

  @override
  Future<void> write(String data) async {
    _data = data;
  }

  @override
  Future<void> clear() async {
    _data = null;
  }
}

class FileSeasonStorage implements SeasonStorage {
  FileSeasonStorage({required this.filePath});

  final String filePath;

  File get _file => File(filePath);

  @override
  Future<String?> read() async {
    try {
      final file = _file;
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String data) async {
    final file = _file;
    await file.parent.create(recursive: true);
    await file.writeAsString(data, flush: true);
  }

  @override
  Future<void> clear() async {
    try {
      final file = _file;
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
