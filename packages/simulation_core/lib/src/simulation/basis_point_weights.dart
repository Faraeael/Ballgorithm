/// The model's canonical proportional normalisation to 10000 basis points.
///
/// Integer shares are floored and the rounding remainder goes to the last
/// positive slot, so an excluded (zero-weight) player can never be picked and
/// the vector always sums to exactly 10000.
///
/// Shared by the probability model and the M006 role/zone policies so one
/// convention covers every weighted draw.
List<int> normalizeBasisPointWeights(List<int> raw) {
  const int maxBasisPoints = 10000;
  final total = raw.fold(0, (a, b) => a + b);
  if (total <= 0) {
    throw ArgumentError.value(raw, 'weights', 'need a positive weight');
  }
  var lastPositive = raw.length - 1;
  while (lastPositive > 0 && raw[lastPositive] == 0) {
    lastPositive--;
  }
  final normalized = List<int>.filled(raw.length, 0);
  var assigned = 0;
  for (var i = 0; i < raw.length; i++) {
    if (i == lastPositive) {
      normalized[i] = maxBasisPoints - assigned;
    } else if (raw[i] > 0) {
      final share = raw[i] * maxBasisPoints ~/ total;
      normalized[i] = share;
      assigned += share;
    }
  }
  return normalized;
}
