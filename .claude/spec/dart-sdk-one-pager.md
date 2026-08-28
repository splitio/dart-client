---
source: https://harness.atlassian.net/wiki/spaces/SPLITFME/pages/23769645149
title: One-pager: Dart SDK Support
space: SPLIT-FME
confluence_version: 7
fetched: 2026-07-03
page_id: 23769645149
---

# One-pager: Dart SDK Support

*A 5-minute introduction to work Product wants to prioritize. Meant to facilitate initial alignment between Product, Engineering, and Design. It is explicitly NOT a comprehensive list of requirements.*

## What we're doing

Ship a native Dart SDK for Harness FME that supports both client-side and server-side Dart applications from a single codebase. It matches the surface of our existing standalone SDKs (Python, .NET, Java, Node.js, Android, iOS) and unblocks Dart workloads the Flutter SDK was never intended for: Dart backend services (Dart Frog, Shelf, Serverpod), Dart CLIs, and full-stack Dart codebases.

The two modes share the same Dart core. Differences:

| 
Aspect
 | 
Server-side
 | 
Client-side
 
| 
Segment sync
 | 
`segmentChanges` (greedy full-segment fetch)
 | 
`mysegments` (per-user lookup)
 
| 
Local dedupe cache or queues
 | 
Larger
 | 
Smaller
 
| 
Other settings
 | 
A few defaults differ
 | 
A few defaults differ
 
| 
Everything else
 | 
SSE streaming, local evaluation, impression batching, `track`, readiness
 | 
Same
 

Packaging is open: one package with a mode setting, or two packages on `pub.dev` built on the same shared core. Implementation decision, not scope.

The existing Flutter SDK stays as the surface for Flutter multi-platform apps (mobile, web, desktop). This new Dart SDK is additive.

The long-term goal is a full standalone Dart SDK at parity with our other standalone SDKs. The list below is part of the target surface and not an exhaustive list; the MVP cut will be defined as implementation progresses, with anything outside MVP landing in follow-ups.

**In scope:** full standalone SDK implementation, including:

Native Dart package(s) on `pub.dev`, supporting current Dart 3 LTS.

Both sync modes: server-side `segmentChanges` (greedy full-segment fetch) and client-side `mysegments` (per-user segment lookup). We give the choice.

Feature flag evaluation: local evaluation, targeting rules, traffic types, impressions, fallback treatments.

`track` API for events feeding experimentation.

SSE streaming with polling fallback, local caching (on client-side), impression batching.

Manager API (`split`, `splits`, `splitNames`).

**Out of scope:**

Configs and AI Configs SDK surface.

OpenFeature provider for Dart. Future iteration once the SDK is stable.

RUM Agent or Suite packaging for Dart.

Replacing or modifying the existing Flutter SDK.

## Why we're doing it

Comcast has raised Dart SDK support as a high-priority need ahead of their renewal. Comcast is a shared account with LaunchDarkly, and keeping internal adoption momentum on the FME side is key to defending and expanding our footprint there. Closing this language gap is the highest-leverage SDK move we can make to protect that account. Comcast also has a Rust SDK ask landing in Q3, tracked separately.

Secondary upside: ConfigCat already ships a native Dart SDK and Statsig and Datadog/Eppo cover Dart/Flutter. We close a coverage gap that comes up in Flutter-shop conversations, turning a Comcast-specific ask into a broader win.

## How we'll know we're successful

Comcast renews with the Dart SDK in production, evaluating flags locally on their Dart workloads with no SDK-driven incidents post-GA. Minor errors and missing optimizations are acceptable; stability is required.

Two additional orgs send traffic through the SDK within 90 days of launch.

Feature flags MVP scope ships at the level Comcast needs to integrate, with enough surface for full testing-app coverage.

## Risks and expectations

**No in-house Dart expertise today.** Shipping a Dart SDK signals to customers that Harness has an opinion on Dart best practices. They will expect strong performance and ecosystem fluency from us during integration and debugging conversations. At the time of writing, no SDK engineer on the team has Dart production experience. This does not block a V1, but it does mean we are going to learn in public.

**Stalling after MVP.** Ecosystem drift (Dart 4, Flutter, pub.dev policies) requires ongoing maintenance, and an SDK falling behind the rest of the lineup becomes another inconsistency to manage in support, docs, and sales. Comcast amplifies this: their use case will shape V1 by default, so every Comcast-requested change must go through PM to mitigate drift. Without continued investment the SDK becomes a liability and the trust we built with them erodes the moment the next thing is not supported.

**Performance baseline (nice to have).** Defining and publishing internal latency, memory, and bundle-size targets before GA gives support and sales something concrete to speak to when customers benchmark us against competitor Dart SDKs (notably ConfigCat) or their prior tooling. Not a launch blocker, but a force multiplier for the people fielding those conversations.
