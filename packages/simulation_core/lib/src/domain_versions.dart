/// Identifies the generation rules shipped with this package.
///
/// Bump when generation output changes for the same seed and config.
const String coreEngineVersion = '1.0.0';

/// Version of the JSON snapshot layout produced by [League.toJson].
const int snapshotSchemaVersion = 1;

/// Identifies the PRNG algorithm. Output stability is only promised per id.
const String prngImplementationId = 'xorshift32-v1';
