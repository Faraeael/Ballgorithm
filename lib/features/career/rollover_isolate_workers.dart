import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
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

/// Signature for spawning an isolate in [ArchiveWorkerSession.start].
typedef ArchiveWorkerSpawnFn =
    Future<Isolate> Function(
      void Function(SendPort) entryPoint,
      SendPort message, {
      SendPort? onExit,
      SendPort? onError,
      bool errorsAreFatal,
      String? debugName,
    });

enum _WorkerSessionState { starting, ready, failed, closing, closed }

/// Scoped single-operation background [Isolate] session used by
/// `FileGmCareerStorage.writeArchive` to avoid spawning 4 separate `compute`
/// isolates during one archive write.
///
/// Always closed in `finally` at the end of `writeArchive` (no global pool).
final class ArchiveWorkerSession {
  ArchiveWorkerSession._({
    required this._initPort,
    required this._responses,
    required this._exitPort,
    required this._errorPort,
  });

  final ReceivePort _initPort;
  final ReceivePort _responses;
  final ReceivePort _exitPort;
  final ReceivePort _errorPort;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  final Completer<SendPort> _initCompleter = Completer<SendPort>();

  Isolate? _isolate;
  SendPort? _sendPort;
  StreamSubscription<Object?>? _initSub;
  StreamSubscription<Object?>? _responseSub;
  StreamSubscription<Object?>? _exitSub;
  StreamSubscription<Object?>? _errorSub;
  Future<void>? _closeFuture;
  Object? _failureError;
  _WorkerSessionState _state = _WorkerSessionState.starting;
  int _nextId = 0;

  /// Starts a short-lived worker isolate with deterministic startup and
  /// unexpected-termination handling.
  static Future<ArchiveWorkerSession> start({
    @visibleForTesting ArchiveWorkerSpawnFn? spawn,
    @visibleForTesting void Function(SendPort)? entryPoint,
  }) async {
    final initPort = ReceivePort();
    final responses = ReceivePort();
    final exitPort = ReceivePort();
    final errorPort = ReceivePort();

    final session = ArchiveWorkerSession._(
      initPort: initPort,
      responses: responses,
      exitPort: exitPort,
      errorPort: errorPort,
    );

    session._initSub = initPort.listen((Object? message) {
      if (message is SendPort && !session._initCompleter.isCompleted) {
        session._initCompleter.complete(message);
      }
    });
    session._exitSub = exitPort.listen((Object? _) {
      session._failFromWorker(
        StateError('ArchiveWorkerSession isolate exited unexpectedly'),
      );
    });
    session._errorSub = errorPort.listen((Object? message) {
      session._failFromWorker(
        StateError('ArchiveWorkerSession uncaught isolate error: $message'),
      );
    });

    try {
      final spawner = spawn ?? _defaultSpawn;
      final entry = entryPoint ?? _archiveWorkerEntry;
      session._isolate = await spawner(
        entry,
        initPort.sendPort,
        onExit: exitPort.sendPort,
        onError: errorPort.sendPort,
        errorsAreFatal: true,
        debugName: 'ArchiveWorkerSession',
      );

      final sendPort = await session._initCompleter.future;
      if (session._state != _WorkerSessionState.starting) {
        throw session._failureError ??
            StateError('ArchiveWorkerSession failed during startup');
      }

      session._sendPort = sendPort;
      await session._initSub?.cancel();
      session._initSub = null;
      initPort.close();

      session._responseSub = responses.listen(session._handleResponse);
      session._state = _WorkerSessionState.ready;
      return session;
    } catch (e) {
      session._initCompleter.future.ignore();
      await session.close();
      rethrow;
    }
  }

  static Future<Isolate> _defaultSpawn(
    void Function(SendPort) entryPoint,
    SendPort message, {
    SendPort? onExit,
    SendPort? onError,
    bool errorsAreFatal = true,
    String? debugName,
  }) => Isolate.spawn(
    entryPoint,
    message,
    onExit: onExit,
    onError: onError,
    errorsAreFatal: errorsAreFatal,
    debugName: debugName,
  );

  void _failFromWorker(Object error) {
    if (_state == _WorkerSessionState.closing ||
        _state == _WorkerSessionState.closed ||
        _state == _WorkerSessionState.failed) {
      return;
    }
    _failureError = error;
    final previousState = _state;
    _state = _WorkerSessionState.failed;

    if (previousState == _WorkerSessionState.starting) {
      if (!_initCompleter.isCompleted) {
        _initCompleter.completeError(error);
      }
      return;
    }

    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();
    _disposePortsAndKill();
  }

  void _handleResponse(Object? message) {
    if (_state != _WorkerSessionState.ready) return;
    if (message is! List<Object?> || message.length != 3) return;
    final id = message[0] as int;
    final ok = message[1] as bool;
    final payload = message[2];
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    if (ok) {
      completer.complete(payload);
    } else {
      completer.completeError(
        StateError(payload?.toString() ?? 'ArchiveWorkerSession error'),
      );
    }
  }

  Future<T> _call<T>(String op, Object? arg) {
    if (_state != _WorkerSessionState.ready) {
      final error = _state == _WorkerSessionState.failed
          ? (_failureError ?? StateError('ArchiveWorkerSession failed'))
          : StateError('ArchiveWorkerSession is ${_state.name}');
      return Future<T>.error(error);
    }
    final sendPort = _sendPort;
    if (sendPort == null) {
      return Future<T>.error(StateError('ArchiveWorkerSession not ready'));
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    try {
      sendPort.send([id, op, arg, _responses.sendPort]);
    } catch (e) {
      _pending.remove(id);
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }
    return completer.future.then((value) => value as T);
  }

  Future<void> verifyArchive(ArchiveVerifyRequest request) =>
      _call<void>('verify', request);

  Future<List<ActiveCareerArchiveRef>?> extractActiveRefs(String rawJson) =>
      _call<List<ActiveCareerArchiveRef>?>('extractRefs', rawJson);

  Future<ExistingArchiveClassification> classifyExisting(
    ExistingArchiveClassifyRequest request,
  ) => _call<ExistingArchiveClassification>('classify', request);

  Future<String> digestArchive(String archiveJson) =>
      _call<String>('digest', archiveJson);

  Future<void> _disposePortsAndKill() async {
    try {
      _sendPort?.send(null);
    } catch (_) {}
    await _initSub?.cancel();
    _initSub = null;
    await _responseSub?.cancel();
    _responseSub = null;
    await _exitSub?.cancel();
    _exitSub = null;
    await _errorSub?.cancel();
    _errorSub = null;
    _initPort.close();
    _responses.close();
    _exitPort.close();
    _errorPort.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  /// Terminates the scoped worker isolate and fails any pending callers.
  /// Idempotent and safe to call in any state (including after startup failure).
  Future<void> close() {
    if (_state == _WorkerSessionState.closed) {
      return Future<void>.value();
    }
    if (_closeFuture != null) {
      return _closeFuture!;
    }
    _state = _WorkerSessionState.closing;
    final closeErr = StateError('ArchiveWorkerSession closed');
    if (!_initCompleter.isCompleted) {
      _initCompleter.completeError(closeErr);
    }
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(closeErr);
      }
    }
    _pending.clear();
    _closeFuture = _disposePortsAndKill().whenComplete(() {
      _state = _WorkerSessionState.closed;
    });
    return _closeFuture!;
  }
}

void _archiveWorkerEntry(SendPort initReplyPort) {
  final commands = ReceivePort();
  initReplyPort.send(commands.sendPort);
  commands.listen((Object? message) {
    if (message == null) {
      commands.close();
      return;
    }
    final list = message as List<Object?>;
    final id = list[0] as int;
    final op = list[1] as String;
    final arg = list[2];
    final replyTo = list[3] as SendPort;
    try {
      switch (op) {
        case 'verify':
          verifySeasonArchiveWorker(arg as ArchiveVerifyRequest);
          replyTo.send([id, true, null]);
        case 'extractRefs':
          final refs = extractActiveCareerArchiveRefsWorker(arg as String);
          replyTo.send([id, true, refs]);
        case 'classify':
          final res = classifyExistingArchiveWorker(
            arg as ExistingArchiveClassifyRequest,
          );
          replyTo.send([id, true, res]);
        case 'digest':
          final d = digestSeasonArchiveWorker(arg as String);
          replyTo.send([id, true, d]);
        default:
          replyTo.send([id, false, 'Unknown archive worker op: $op']);
      }
    } catch (e) {
      replyTo.send([id, false, e.toString()]);
    }
  });
}

/// Runs [fn] using `compute` (used on web where `Isolate.spawn` is unsupported).
Future<R> runArchiveComputeFallback<Q, R>(
  ComputeCallback<Q, R> fn,
  Q message,
) => compute(fn, message);
