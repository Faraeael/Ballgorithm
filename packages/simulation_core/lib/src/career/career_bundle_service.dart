import 'dart:convert';

import 'gm_career.dart';
import 'gm_career_codec.dart';
import 'season_archive.dart';

/// Verified result of importing a multi-season career bundle.
typedef CareerBundleImport = ({
  GmCareer career,
  String activeCareerJson,
  Map<int, String> verifiedArchivesByYear,
});

/// Canonical export/import packaging for a [GmCareer] and its season archives.
final class CareerBundleService {
  const CareerBundleService();

  static const int currentBundleSchemaVersion = 1;

  /// Packages [activeCareerJson] with all referenced [archivesByYear].
  ///
  /// Verifies the active career and every referenced archive's SHA-256 digest
  /// and domain invariants before producing the bundle.
  String exportBundle({
    required String activeCareerJson,
    required Map<int, String> archivesByYear,
  }) {
    final career = GmCareerCodec.decode(activeCareerJson);
    final expectedYears = {
      for (final record in career.seasonHistory) record.seasonYear,
    };
    if (archivesByYear.length != expectedYears.length ||
        !archivesByYear.keys.toSet().containsAll(expectedYears)) {
      throw const FormatException(
        'Career bundle archive set does not match seasonHistory',
      );
    }
    for (final record in career.seasonHistory) {
      final archiveJson = archivesByYear[record.seasonYear];
      if (archiveJson == null) {
        throw FormatException(
          'Missing historical archive for season ${record.seasonYear}',
        );
      }
      SeasonArchiveCodec.decodeAndVerify(
        archiveJson,
        expectedDigest: record.archiveDigest,
        expectedCareerId: career.id,
        expectedSeasonYear: record.seasonYear,
        expectedRecord: record,
      );
    }
    final sortedYears = archivesByYear.keys.toList()..sort();
    return jsonEncode({
      'bundleSchemaVersion': currentBundleSchemaVersion,
      'activeCareerJson': activeCareerJson,
      'archivesByYear': {
        for (final year in sortedYears) '$year': archivesByYear[year]!,
      },
    });
  }

  /// Verifies and unpacks a [bundleJson] into active career + verified archives.
  CareerBundleImport importBundle(String bundleJson) {
    final Object? raw;
    try {
      raw = jsonDecode(bundleJson);
    } catch (e) {
      throw FormatException('Malformed career bundle JSON: $e');
    }
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid career bundle JSON: expected Map');
    }
    final version = raw['bundleSchemaVersion'];
    final activeCareerJson = raw['activeCareerJson'];
    final rawArchives = raw['archivesByYear'];
    if (version is! int ||
        version != currentBundleSchemaVersion ||
        activeCareerJson is! String ||
        rawArchives is! Map<String, dynamic>) {
      throw const FormatException('Malformed or unsupported career bundle');
    }
    final career = GmCareerCodec.decode(activeCareerJson);
    final archivesByYear = <int, String>{};
    for (final entry in rawArchives.entries) {
      final year = int.tryParse(entry.key);
      if (year == null || year < 1 || entry.value is! String) {
        throw const FormatException('Malformed archive entry in career bundle');
      }
      archivesByYear[year] = entry.value as String;
    }
    final expectedYears = {
      for (final record in career.seasonHistory) record.seasonYear,
    };
    if (archivesByYear.length != expectedYears.length ||
        !archivesByYear.keys.toSet().containsAll(expectedYears)) {
      throw const FormatException(
        'Imported career bundle archive set does not match seasonHistory',
      );
    }
    for (final record in career.seasonHistory) {
      final archiveJson = archivesByYear[record.seasonYear];
      if (archiveJson == null) {
        throw FormatException(
          'Missing historical archive for season ${record.seasonYear}',
        );
      }
      SeasonArchiveCodec.decodeAndVerify(
        archiveJson,
        expectedDigest: record.archiveDigest,
        expectedCareerId: career.id,
        expectedSeasonYear: record.seasonYear,
        expectedRecord: record,
      );
    }
    return (
      career: career,
      activeCareerJson: activeCareerJson,
      verifiedArchivesByYear: Map<int, String>.unmodifiable(archivesByYear),
    );
  }
}
