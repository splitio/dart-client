class ValidationResult<T> {
  final T? value;
  final String? warning;
  final String? error;

  const ValidationResult._({this.value, this.warning, this.error});

  const ValidationResult.ok(T value, {String? warning})
      : this._(value: value, warning: warning);

  const ValidationResult.fail(String error) : this._(error: error);

  bool get isValid => error == null;
}
