final RegExp _eventTypeRegex = RegExp(r'^[a-zA-Z0-9][-_.:a-zA-Z0-9]{0,79}$');

bool validateEventType(String eventType) {
  if (eventType.isEmpty) return false;
  return _eventTypeRegex.hasMatch(eventType);
}
