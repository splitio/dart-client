final class EngineEvaluationResult {
  final String treatment;
  final String label;
  final bool impressionDisabled;
  final int changeNumber;
  final String? config;

  const EngineEvaluationResult({
    required this.treatment,
    required this.label,
    required this.impressionDisabled,
    required this.changeNumber,
    this.config,
  });
}

final class EvaluationResult {
  final String treatment;
  final String? config;

  const EvaluationResult({
    required this.treatment,
    this.config,
  });
}
