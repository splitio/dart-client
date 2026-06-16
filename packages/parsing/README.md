# parsing

Wire DTO → ParsedSplit, wire rules → TargetingRule, unsupported-matcher detection. Parse-on-write (not on evaluation).

## Key exports

| Type | Description |
|---|---|
| `RuleParser` | Parses wire Split DTO to ParsedSplit for engine consumption |
| `SplitChangeProcessor` | Processes SplitChange feed and detects unsupported matchers |
| `NotificationParser` | Parses data notification wire format |

## Dependencies

**Internal:** models  
**External:** none

## Spec reference

SDK Specification v1 §3.1 — Module Catalog (Shared core)  
SDK Specification v1 §5 — Evaluation Boundary & Flow (parse-on-write contract)
