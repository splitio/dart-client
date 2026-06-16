---
name: dart-scaffold-package
description: Use when adding a new package to the dart-client Melos monorepo — scaffolding pubspec.yaml, lib/, test/, and README for a single named package.
---

# dart-scaffold-package

## Overview

Scaffold one new Dart package in `packages/<name>/` from the SDK spec. Structure only — no implementation code. Ask before creating anything the spec doesn't clearly define.

## Inputs

- Package name (required, passed as arg or stated in prompt)
- `publish: false` flag (optional) — marks the package as never-to-publish (e.g. `e2e`, internal test harnesses)
- `docs/SDK-Specification-v1-RFC2119.md` — source of truth for responsibility, exports, deps
- `docs/PACKAGE-STRUCTURE-v1-design.md` — layer/dep table reference

## Step 1 — Read the spec

Read `docs/SDK-Specification-v1-RFC2119.md`. Find the sections relevant to `<name>`. Extract:

| Field | Where to find it |
|---|---|
| Responsibility (1–2 sentences) | Package's primary spec section |
| Key exports (interfaces, classes) | Types defined or owned by this package |
| Internal deps | Dep table in `docs/PACKAGE-STRUCTURE-v1-design.md` |
| External deps | Same dep table — leaf packages only |
| RFC section refs | Section numbers that define this package's contracts |

**If any field is ambiguous or missing from the spec:** invoke `grill-me` to ask the user before proceeding.

## Step 2 — Create exactly these four artifacts

```
packages/<name>/
  pubspec.yaml
  lib/<name>.dart
  lib/src/             ← empty directory (create with .gitkeep)
  test/<name>_test.dart
  README.md
```

**Nothing else.** No `analysis_options.yaml`, no `CHANGELOG.md`, no implementation files.

### pubspec.yaml

```yaml
name: <name>
description: <one-sentence responsibility from spec>
version: 0.0.1

environment:
  sdk: ^3.0.0

dependencies:
  # internal — path refs only, one per line
  models:
    path: ../models

dev_dependencies:
  test: ^1.24.0
  lints: ^3.0.0
```

Rules:
- No `workspace:` field
- No `publish_to: none` unless caller explicitly passed `publish: false`
- External deps only for leaf packages (`http_client`, `auth`) — see dep table
- Omit `dependencies:` block entirely if package has no deps (e.g. `models`, `observer`)

### lib/\<name\>.dart — commented export stub

```dart
library <name>;

// Exports — uncomment as src files are created:
// export 'src/foo.dart';
// export 'src/bar.dart';
```

Derive export names from the spec's key types. Do NOT write live `export` lines.

### lib/src/ — empty

Create `lib/src/.gitkeep`. No source files.

### test/\<name\>_test.dart — spec-derived placeholder

```dart
import 'package:test/test.dart';

void main() {
  group('<PrimaryClassName>', () {
    test('<primary responsibility verb phrase from spec>', () {
      // TODO: implement
    });
  });
}
```

Derive `<PrimaryClassName>` and the test description from the spec's primary type for this package.

### README.md

```markdown
# <name>

<One-sentence responsibility.>

## Key exports

| Type | Description |
|---|---|
| `Foo` | ... |

## Dependencies

**Internal:** models, engine (path refs)  
**External:** none

## Spec reference

SDK Specification v1 §<N.N> — <section title>
```

## Step 3 — Verify the build

Run `dart run melos bootstrap` to ensure all packages resolve correctly. The monorepo must remain buildable after each new package is added. If bootstrap fails, fix dependency declarations or SDK constraints before reporting completion.

## Step 4 — Report what was created

List every file path created and one line explaining what was derived from the spec vs. left as a placeholder.

## Common mistakes

| Mistake | Fix |
|---|---|
| Adding implementation code | Scaffolding phase is structure only. Delete any logic. |
| Live `export` lines in barrel | All exports must be commented out |
| `publish_to: none` added without `publish: false` flag | Remove it. Melos substitutes path→version at publish time. The Dart analyzer warns about path deps pre-bootstrap — that is expected, not a real error. Only add `publish_to: none` when the caller explicitly marks the package as non-publishable (e.g. `e2e`). |
| `analysis_options.yaml` | Not part of the scaffold spec, do not create |
| Skipping `test/` | Always create the test file with a placeholder group+test |
| Guessing ambiguous deps | Invoke `grill-me` instead |
