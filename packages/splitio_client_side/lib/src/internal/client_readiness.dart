import 'dart:async';

import 'package:splitio_commons/src/events/events_manager.dart';
import 'package:splitio_commons/src/logger/logger.dart';

/// Per-client readiness and update routing for the client-side flavor
/// (spec §8.2).
///
/// Every client owns its own [EventsManager]. Global state (rules + rule-based
/// segments) is latched once; memberships are tracked per matching key. A
/// client is READY when `globalRulesReady && thisKeyMembershipsReady`, so a
/// client never becomes READY on another key's memberships and a client
/// created after the global sync only waits for its own memberships.
class ClientReadiness {
  final SplitLogger _log;
  final int _readyTimeoutSeconds;
  final DateTime _deadline;
  final Set<String> _membershipsReady = {};
  final List<_Entry> _entries = [];
  bool _rulesReady = false;
  bool _disposed = false;

  /// [readyTimeoutSeconds] is measured from construction (factory creation).
  /// A client registered after that deadline gets its own full window,
  /// measured from its registration.
  ClientReadiness({
    required SplitLogger log,
    required int readyTimeoutSeconds,
  })  : _log = log,
        _readyTimeoutSeconds = readyTimeoutSeconds,
        _deadline = DateTime.now().add(Duration(seconds: readyTimeoutSeconds));

  /// Registers a client bound to [matchingKey] whose events go to [events].
  /// Fires READY immediately when the readiness condition already holds.
  void register(String matchingKey, EventsManager events) {
    if (_disposed) return;
    final entry = _Entry(matchingKey, events);
    _entries.add(entry);
    if (_isReady(matchingKey)) {
      _fireReady(entry);
      return;
    }
    _armTimeout(entry);
  }

  /// Stops tracking a destroyed client and disposes its event manager, which
  /// completes its pending futures and closes its `whenUpdated()` stream.
  Future<void> unregister(EventsManager events) async {
    final index = _entries.indexWhere((e) => e.events == events);
    if (index != -1) _entries.removeAt(index).timer?.cancel();
    await events.dispose();
  }

  /// A rules fetch (initial, poll, retry or streaming) reported [success].
  void onRulesResult(bool success) {
    if (!success || _rulesReady) return;
    _rulesReady = true;
    for (final entry in List.of(_entries)) {
      if (_membershipsReady.contains(entry.matchingKey)) _fireReady(entry);
    }
  }

  /// A memberships fetch for [matchingKey] reported [success].
  void onMembershipsResult(String matchingKey, bool success) {
    if (!success) return;
    _membershipsReady.add(matchingKey);
    if (!_rulesReady) return;
    for (final entry in List.of(_entries)) {
      if (entry.matchingKey == matchingKey) _fireReady(entry);
    }
  }

  /// [matchingKey]'s membership set changed: UPDATE `[]` only on the READY
  /// clients bound to that key.
  void onMembershipsChanged(String matchingKey) {
    for (final entry in List.of(_entries)) {
      if (entry.matchingKey == matchingKey) _notifyUpdate(entry, const []);
    }
  }

  /// Flag, kill or rule-based segment change: UPDATE on every READY client.
  void onFlagsChanged(List<String> changedFlags) {
    for (final entry in List.of(_entries)) {
      _notifyUpdate(entry, changedFlags);
    }
  }

  /// Cancels every timeout timer and disposes every client's event manager.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final entries = List.of(_entries);
    _entries.clear();
    for (final entry in entries) {
      entry.timer?.cancel();
    }
    await Future.wait(entries.map((e) => e.events.dispose()));
  }

  bool _isReady(String matchingKey) =>
      _rulesReady && _membershipsReady.contains(matchingKey);

  void _notifyUpdate(_Entry entry, List<String> changed) {
    if (entry.events.isReady) entry.events.notifyUpdate(changed);
  }

  void _fireReady(_Entry entry) {
    if (entry.events.isReady) return;
    entry.timer?.cancel();
    // The matching key is an end-user identifier (PII): keep it out of INFO.
    _log.info('SDK client is ready');
    _log.debug('SDK client is ready for key: "${entry.matchingKey}"');
    entry.events.notifyReady();
  }

  void _armTimeout(_Entry entry) {
    if (_readyTimeoutSeconds <= 0) return;
    var remaining = _deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      remaining = Duration(seconds: _readyTimeoutSeconds);
    }
    entry.timer = Timer(remaining, () {
      if (entry.events.isReady) return;
      _log.warning('Ready timeout reached (${_readyTimeoutSeconds}s) '
          'for key: "${entry.matchingKey}"');
      entry.events.notifyTimeout();
    });
  }
}

class _Entry {
  final String matchingKey;
  final EventsManager events;
  Timer? timer;

  _Entry(this.matchingKey, this.events);
}
