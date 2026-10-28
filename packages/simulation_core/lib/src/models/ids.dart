/// Typed identifiers. Extension types are erased at runtime and compare as
/// the underlying string, so they cost nothing.
extension type const LeagueId(String value) {}

extension type const TeamId(String value) {}

extension type const PlayerId(String value) {}
