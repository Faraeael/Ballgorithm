import 'package:simulation_core/simulation_core.dart';

/// Pure CPU payload for preparing a Year N archive and Year N+1 rollover
/// inside a background isolate.
final class RolloverPrepareRequest {
  const RolloverPrepareRequest(this.career);

  final GmCareer career;
}

/// Canonical rollover preparation output returned from the background isolate.
///
/// Omits the full [SeasonArchive] object graph to avoid redundant deep-copy
/// transfer of ~12 MB of Dart objects alongside [archiveJson].
final class RolloverPrepareOutput {
  const RolloverPrepareOutput({
    required this.archiveJson,
    required this.archiveDigest,
    required this.archiveRecord,
    required this.nextCareer,
    required this.encodedNextCareer,
  });

  final String archiveJson;
  final String archiveDigest;
  final SeasonHistoryRecord archiveRecord;
  final GmCareer nextCareer;
  final String encodedNextCareer;
}

/// Pure CPU payload for verifying an incoming [SeasonArchive] JSON string.
final class ArchiveVerifyRequest {
  const ArchiveVerifyRequest({
    required this.archiveJson,
    required this.expectedDigest,
    required this.expectedSeasonYear,
  });

  final String archiveJson;
  final String expectedDigest;
  final int expectedSeasonYear;
}

/// Pure CPU payload for classifying an existing archive file on disk.
final class ExistingArchiveClassifyRequest {
  const ExistingArchiveClassifyRequest({
    required this.existingJson,
    required this.expectedDigest,
    required this.expectedSeasonYear,
  });

  final String existingJson;
  final String expectedDigest;
  final int expectedSeasonYear;
}

/// Compact classification result for an existing archive on disk.
final class ExistingArchiveClassification {
  const ExistingArchiveClassification({
    required this.matchesExpected,
    required this.isStructurallyValid,
    this.careerId,
  });

  final bool matchesExpected;
  final bool isStructurallyValid;
  final String? careerId;
}

/// Compact `(seasonYear, archiveDigest)` pair extracted from an active save.
typedef ActiveCareerArchiveRef = ({int seasonYear, String archiveDigest});

/// Top-level isolate worker: validates [request.career] once, builds the
/// canonical archive JSON + SHA-256 digest + [SeasonHistoryRecord], computes
/// the Year N+1 rollover, and encodes the next [GmCareer] JSON.
RolloverPrepareOutput prepareSeasonRolloverWorker(
  RolloverPrepareRequest request,
) {
  final prepared = const SeasonRolloverService().prepareArchiveAndRollover(
    current: request.career,
  );
  final nextCareer = prepared.rolloverResult.nextCareer;
  final encodedNextCareer = GmCareerCodec.encode(nextCareer);
  return RolloverPrepareOutput(
    archiveJson: prepared.archiveJson,
    archiveDigest: prepared.archiveDigest,
    archiveRecord: prepared.archiveRecord,
    nextCareer: nextCareer,
    encodedNextCareer: encodedNextCareer,
  );
}

/// Top-level isolate worker: performs full [SeasonArchiveCodec.decodeAndVerify]
/// including SHA-256 verification, JSON syntax, schema, identity, 1,230-game
/// evidence, Play-In, Playoff, and champion checks.
void verifySeasonArchiveWorker(ArchiveVerifyRequest request) {
  SeasonArchiveCodec.decodeAndVerify(
    request.archiveJson,
    expectedDigest: request.expectedDigest,
    expectedSeasonYear: request.expectedSeasonYear,
  );
}

/// Top-level isolate worker: computes the digest of an existing archive file
/// and, when it differs from [request.expectedDigest], performs full
/// structural verification to distinguish a valid conflict from corruption.
ExistingArchiveClassification classifyExistingArchiveWorker(
  ExistingArchiveClassifyRequest request,
) {
  final existingDigest = SeasonArchiveCodec.digestOf(request.existingJson);
  if (existingDigest == request.expectedDigest) {
    return const ExistingArchiveClassification(
      matchesExpected: true,
      isStructurallyValid: true,
    );
  }
  try {
    final existingArchive = SeasonArchiveCodec.decodeAndVerify(
      request.existingJson,
      expectedDigest: existingDigest,
      expectedSeasonYear: request.expectedSeasonYear,
    );
    return ExistingArchiveClassification(
      matchesExpected: false,
      isStructurallyValid: true,
      careerId: existingArchive.careerId,
    );
  } catch (_) {
    return const ExistingArchiveClassification(
      matchesExpected: false,
      isStructurallyValid: false,
    );
  }
}

/// Top-level isolate worker: computes canonical SHA-256 digest of archive JSON.
String digestSeasonArchiveWorker(String archiveJson) =>
    SeasonArchiveCodec.digestOf(archiveJson);

/// Top-level isolate worker: decodes an active career JSON string and returns
/// its `seasonHistory` digest references, or `null` if decoding fails.
List<ActiveCareerArchiveRef>? extractActiveCareerArchiveRefsWorker(
  String rawCareerJson,
) {
  try {
    final career = GmCareerCodec.decode(rawCareerJson);
    return [
      for (final record in career.seasonHistory)
        (seasonYear: record.seasonYear, archiveDigest: record.archiveDigest),
    ];
  } catch (_) {
    return null;
  }
}
