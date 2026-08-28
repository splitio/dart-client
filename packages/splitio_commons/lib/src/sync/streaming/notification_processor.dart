import 'event_source_client.dart';
import 'streaming_event.dart';

/// A categorized data notification (spec §11.4) wrapping the wire `type` and
/// its full payload map, to be acted on by the Axis-2 strategy handlers
/// (tasks 4.4/4.6). This layer does NOT apply strategies, fetch, or mutate any
/// store — it only categorizes and carries the payload forward.
class FeedUpdate {
  /// The wire notification `type` (e.g. `SPLIT_UPDATE`, `MEMBERSHIPS_MS_UPDATE`).
  final String type;

  /// The full decoded inner notification payload (`changeNumber`, `pcn`, `c`,
  /// `d`, ...). Passed through verbatim.
  final Map<String, dynamic> payload;

  const FeedUpdate({required this.type, required this.payload});
}

/// The result of categorizing a single [RawNotification] (spec §11.4).
///
/// Exactly one of three outcomes: data [feedUpdates] for strategy handlers, a
/// single FSM [fsmEvent] to reduce through the streaming policy, or nothing
/// (ignored). [isEmpty] is `true` only for the ignored case.
class NotificationResult {
  final List<FeedUpdate> feedUpdates;
  final StreamingEvent? fsmEvent;

  const NotificationResult({
    this.feedUpdates = const [],
    this.fsmEvent,
  });

  static const NotificationResult ignored = NotificationResult();

  bool get isEmpty => feedUpdates.isEmpty && fsmEvent == null;
}

/// Pure categorization of a [RawNotification] into either data [FeedUpdate]s or
/// a single FSM [StreamingEvent] (spec §11.4). LOCAL (v1) eval locus.
///
/// No fetching, no store mutation, no I/O — just inspection of the notification
/// `type`/`controlType`/`metrics`/error `code`. Missing or misshaped fields
/// cause the notification to be ignored (empty result) rather than throw.
class NotificationProcessor {
  /// LOCAL v1 data notification types handled as [FeedUpdate]s (§11.4).
  static const Set<String> _localDataTypes = {
    'SPLIT_UPDATE',
    'SPLIT_KILL',
    'MEMBERSHIPS_MS_UPDATE',
    'MEMBERSHIPS_LS_UPDATE',
    'RB_SEGMENT_UPDATE',
  };

  const NotificationProcessor();

  /// Categorizes [n]. Pure — safe to call on any frame.
  NotificationResult process(RawNotification n) {
    final data = n.data;
    if (data == null) return NotificationResult.ignored;

    final type = data['type'];

    // CONTROL notifications → FSM control events (§11.3 mapping table).
    if (type == 'CONTROL') {
      return _control(data);
    }

    // OCCUPANCY notifications → OccupancyChanged (Ably [meta]occupancy shape).
    if (type == 'OCCUPANCY') {
      return _occupancy(data);
    }

    // DATA notifications → FeedUpdate (LOCAL v1 handled types only). This MUST
    // be ruled out BEFORE the generic `code`-based error heuristic below: a data
    // frame like `{type: 'SPLIT_UPDATE', code: 12345, ...}` can carry an
    // incidental `code`, and routing on `code is int` first would hijack it into
    // an ErrorFrame and silently drop the update (stale treatments until next
    // poll). Known data types are unambiguous, so they win.
    if (type is String && _localDataTypes.contains(type)) {
      return NotificationResult(
          feedUpdates: [FeedUpdate(type: type, payload: data)]);
    }

    // ERROR notifications: an Ably `event: error` frame, or an untyped inner
    // error that carries an int `code`. Only reached once known CONTROL/
    // OCCUPANCY/DATA categories are excluded, so the `code` heuristic is safe.
    final code = data['code'];
    if (n.event == 'error' || code is int) {
      return _error(code);
    }

    // EVALUATION_UPDATE (remote reserved) + any unknown type → ignore.
    return NotificationResult.ignored;
  }

  NotificationResult _control(Map<String, dynamic> data) {
    final controlType = data['controlType'];
    if (controlType is! String) return NotificationResult.ignored;

    final ts = _timestamp(data);
    final StreamingEvent? event;
    switch (controlType) {
      case 'STREAMING_PAUSED':
        event = ControlPaused(ts);
      case 'STREAMING_RESUMED':
        event = ControlResumed(ts);
      case 'STREAMING_DISABLED':
        event = ControlDisabled(ts);
      case 'STREAMING_RESET':
        event = ControlReset(ts);
      default:
        event = null;
    }
    if (event == null) return NotificationResult.ignored;
    return NotificationResult(fsmEvent: event);
  }

  NotificationResult _occupancy(Map<String, dynamic> data) {
    final metrics = data['metrics'];
    if (metrics is! Map) return NotificationResult.ignored;
    final publishers = metrics['publishers'];
    if (publishers is! int) return NotificationResult.ignored;
    return NotificationResult(
        fsmEvent: OccupancyChanged(isZero: publishers == 0));
  }

  NotificationResult _error(Object? code) {
    if (code is! int) return NotificationResult.ignored;
    final isTokenError = code == 401 || (code >= 40140 && code <= 40149);
    return NotificationResult(fsmEvent: ErrorFrame(isTokenError: isTokenError));
  }

  /// Reads the control notification timestamp defensively; defaults to `0`.
  ///
  /// Real Ably control notifications always carry a timestamp, so `0` is only
  /// reached for malformed/timestamp-less frames. `0` is the conservative
  /// choice: the FSM stale guard drops events with `timestamp <=
  /// lastControlTimestamp` (initial `0`), so such frames are treated as
  /// stale/ignorable rather than acted on.
  int _timestamp(Map<String, dynamic> data) {
    final ts = data['timestamp'] ?? data['ts'] ?? data['lastControlTimestamp'];
    return ts is int ? ts : 0;
  }
}
