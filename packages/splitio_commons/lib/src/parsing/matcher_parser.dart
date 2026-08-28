import 'package:splitio_commons/src/models/models.dart';

/// Builds a concrete [Matcher] from a matcher DTO.
///
/// Owns the matcher-construction concern extracted from `RuleParser`: the
/// large `matcherType` switch and all helpers used only by it.
class MatcherParser {
  Matcher? parseMatcherType(String? type, Map<String, dynamic> dto) {
    return switch (type) {
      'ALL_KEYS' => const AllKeysMatcher(),
      'IN_SEGMENT' => UserDefinedSegmentMatcher(
          segmentName: _getField<String>(
                  dto['userDefinedSegmentMatcherData'], 'segmentName') ??
              '',
        ),
      'IN_RULE_BASED_SEGMENT' => RuleBasedSegmentMatcher(
          segmentName: _getField<String>(
                  dto['userDefinedSegmentMatcherData'], 'segmentName') ??
              '',
        ),
      'WHITELIST' => WhitelistMatcher(
          whitelist: _getField<List>(dto['whitelistMatcherData'], 'whitelist')
                  ?.cast<String>()
                  .toSet() ??
              {},
        ),
      'EQUAL_TO' => _parseUnaryNumeric(
          dto, (v, dt) => EqualToMatcher(value: v, dataType: dt)),
      'GREATER_THAN_OR_EQUAL_TO' => _parseUnaryNumeric(
          dto, (v, dt) => GreaterThanOrEqualToMatcher(value: v, dataType: dt)),
      'LESS_THAN_OR_EQUAL_TO' => _parseUnaryNumeric(
          dto, (v, dt) => LessThanOrEqualToMatcher(value: v, dataType: dt)),
      'BETWEEN' => _parseBetween(dto),
      'EQUAL_TO_SET' => EqualToSetMatcher(
          compareTo: _parseStringList(dto['whitelistMatcherData']).toSet(),
        ),
      'CONTAINS_ANY_OF_SET' => ContainsAnyOfSetMatcher(
          compareTo: _parseStringList(dto['whitelistMatcherData']).toSet(),
        ),
      'CONTAINS_ALL_OF_SET' => ContainsAllOfSetMatcher(
          compareTo: _parseStringList(dto['whitelistMatcherData']).toSet(),
        ),
      'PART_OF_SET' => PartOfSetMatcher(
          compareTo: _parseStringList(dto['whitelistMatcherData']).toSet(),
        ),
      'STARTS_WITH' => StartsWithAnyOfMatcher(
          values: _parseStringList(dto['whitelistMatcherData']),
        ),
      'ENDS_WITH' => EndsWithAnyOfMatcher(
          values: _parseStringList(dto['whitelistMatcherData']),
        ),
      'CONTAINS_STRING' => ContainsAnyOfMatcher(
          values: _parseStringList(dto['whitelistMatcherData']),
        ),
      'MATCHES_STRING' => RegularExpressionMatcher(
          pattern: _stringMatcherValue(dto['stringMatcherData']) ?? '',
        ),
      'EQUAL_TO_BOOLEAN' => BooleanMatcher(
          value: dto['booleanMatcherData'] as bool? ?? false,
        ),
      'IN_SPLIT_TREATMENT' => _parseDependency(dto),
      'EQUAL_TO_SEMVER' => EqualToSemverMatcher(
          version: _stringMatcherValue(dto['stringMatcherData']) ?? '',
        ),
      'GREATER_THAN_OR_EQUAL_TO_SEMVER' => GreaterThanOrEqualToSemverMatcher(
          version: _stringMatcherValue(dto['stringMatcherData']) ?? '',
        ),
      'LESS_THAN_OR_EQUAL_TO_SEMVER' => LessThanOrEqualToSemverMatcher(
          version: _stringMatcherValue(dto['stringMatcherData']) ?? '',
        ),
      'BETWEEN_SEMVER' => _parseBetweenSemver(dto),
      'IN_LIST_SEMVER' => InListSemverMatcher(
          versions: _parseStringList(dto['whitelistMatcherData']),
        ),
      _ => null,
    };
  }

  T? _getField<T>(Object? data, String field) {
    if (data is Map<String, dynamic>) return data[field] as T?;
    return null;
  }

  String? _stringMatcherValue(Object? data) {
    if (data is String) return data;
    if (data is Map<String, dynamic>) return data['value'] as String?;
    return null;
  }

  Map<String, dynamic>? _safeMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    return null;
  }

  Matcher? _parseUnaryNumeric(
    Map<String, dynamic> dto,
    Matcher Function(int value, DataType dataType) factory,
  ) {
    final data = _safeMap(dto['unaryNumericMatcherData']);
    if (data == null) return null;
    final value = data['value'] as int? ?? 0;
    final dataType = _parseDataType(data['dataType'] as String?);
    return factory(value, dataType);
  }

  Matcher? _parseBetween(Map<String, dynamic> dto) {
    final data = _safeMap(dto['betweenMatcherData']);
    if (data == null) return null;
    final start = data['start'] as int? ?? 0;
    final end = data['end'] as int? ?? 0;
    final dataType = _parseDataType(data['dataType'] as String?);
    return BetweenMatcher(start: start, end: end, dataType: dataType);
  }

  Matcher? _parseBetweenSemver(Map<String, dynamic> dto) {
    final data = _safeMap(dto['betweenStringMatcherData']);
    if (data == null) return null;
    return BetweenSemverMatcher(
      start: data['start'] as String? ?? '',
      end: data['end'] as String? ?? '',
    );
  }

  Matcher? _parseDependency(Map<String, dynamic> dto) {
    final data = _safeMap(dto['dependencyMatcherData']);
    if (data == null) return null;
    return DependencyMatcher(
      split: data['split'] as String? ?? '',
      treatments: (data['treatments'] as List?)?.cast<String>() ?? [],
    );
  }

  DataType _parseDataType(String? value) {
    if (value == 'DATETIME') return DataType.datetime;
    return DataType.number;
  }

  List<String> _parseStringList(Object? data) {
    if (data is Map<String, dynamic>) {
      return (data['whitelist'] as List?)?.cast<String>() ?? [];
    }
    return [];
  }
}
