bool validateEventValue(double? value) {
  if (value == null) return true;
  return value.isFinite;
}
