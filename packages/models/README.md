# models

Domain objects, enums, DTOs, and data transfer types for the Split SDK. Zero external dependencies — consumed by all other packages.

## Key exports

| Type | Description |
|---|---|
| `Key` | Matching key + optional bucketing key |
| `Target` | Key + attributes + optional traffic type |
| `Attributes` | Map of attribute values (String, num, bool, List<String>, DateTime) |
| `EvaluationResult` | Public result: flag, treatment, config, changeNumber, label |
| `EvaluationOptions` | Evaluation metadata (properties) |
| `SplitEvent` | Lifecycle event (READY, READY_TIMEOUT, UPDATE) |
| `ParsedSplit` | Parsed flag definition with rule and metadata |
| `TargetingRule` | Engine input: seed, killed, defaultTreatment, conditions, prerequisites |
| `Partition` | Treatment + size (percentage 0–100) |
| `Condition` | Condition type, matcher, partitions, label |
| `Matcher` | Matcher types and matchers registry |

## Dependencies

**Internal:** none  
**External:** none

## Spec reference

SDK Specification v1 §3.1 (Shared core), §4 (Data Model)
