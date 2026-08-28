final class SplitView {
  final String name;
  final String trafficType;
  final bool killed;
  final List<String> treatments;
  final int changeNumber;
  final Map<String, String> configs;
  final String defaultTreatment;
  final List<String> sets;
  final bool impressionsDisabled;

  const SplitView({
    required this.name,
    required this.trafficType,
    required this.killed,
    required this.treatments,
    required this.changeNumber,
    this.configs = const {},
    required this.defaultTreatment,
    this.sets = const [],
    this.impressionsDisabled = false,
  });
}
