import 'dart:io';

import 'package:test/test.dart';

/// Guards constitution rule 2: the domain stays independent of Flutter,
/// Flame, persistence and network packages.
void main() {
  test('domain library has no framework or persistence imports', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'run from the package root');

    const forbidden = [
      'package:flutter',
      'dart:ui',
      'package:flame',
      'package:sqflite',
      'package:path_provider',
      'package:shared_preferences',
      'package:http',
      'dart:io',
    ];

    final sources = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    expect(sources, isNotEmpty);
    for (final file in sources) {
      final source = file.readAsStringSync();
      for (final dependency in forbidden) {
        expect(
          source.contains(dependency),
          isFalse,
          reason: '${file.path} references $dependency',
        );
      }
    }
  });
}
