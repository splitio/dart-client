/// Narrow, read-only view over segment membership.
///
/// Client-side and server-side SDKs store segment membership in
/// fundamentally different shapes:
///
/// * Client-side keeps a per-key `MembershipStore` populated from the
///   `/memberships/{key}` endpoint.
/// * Server-side will keep a per-segment `SegmentStore` populated from the
///   `/segmentChanges/{name}` endpoint.
///
/// Both answer the same evaluation-time question: "is this key in this
/// segment?" — this interface is that question, and only that question.
/// Consumers (matchers, evaluator) depend on this interface, not on the
/// underlying storage shape.
abstract interface class SegmentMembershipResolver {
  /// True when [key] is a member of the standard segment named
  /// [segmentName]. False for unknown keys or unknown segments. MUST NOT
  /// throw.
  bool isInSegment(String segmentName, String key);
}
