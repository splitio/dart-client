import '../enums.dart';
import 'attribute_matcher.dart';

/// A condition's matcher group: a set of matcher delegates combined with a
/// logical combiner (AND). Mirrors the .NET SDK's `CombiningMatcher`
/// (`combiner` + `List<AttributeMatcher> delegates`); here each delegate is an
/// [AttributeMatcher] (attribute selector + negate + underlying matcher).
///
/// Evaluation lives in the engine (`matchCombining`) so the model stays free of
/// evaluation-context dependencies.
final class CombiningMatcher {
  final CombinerEnum combiner;
  final List<AttributeMatcher> delegates;

  const CombiningMatcher({
    this.combiner = CombinerEnum.and,
    required this.delegates,
  });
}
