---
name: new-patch
description: Author a new patch for the LocoKit2 fork stack — plan for minimal rebase-conflict surface, respect the concurrency/trigger/hot-path rules, verify with an iOS Simulator build, and commit in the house style. Use for any feature, fix, or perf change in this repo ("add X", "fix Y", "expose Z to the app").
---

# Author a patch for the stack

Every change here is a patch that must survive rebases against a moving upstream,
forever. Optimize for two things: minimal collision surface with upstream, and a
commit that documents its own intent well enough that a future conflict can be
resolved from the commit body alone.

## Step 1 — Ownership scan (before writing any code)

For every file you expect to touch:

```bash
git ls-tree upstream/main -- <path>
```

- **Exists upstream** → upstream-owned. Every line you edit there is future conflict
  surface. Budget it consciously.
- **Empty output** → fork-owned (ours alone: e.g. `Utilities/BackgroundTaskGuard.swift`,
  `TimelineProcessor+UserActions.swift`, `scripts/`). Edit freely.

Then pick the least invasive shape that works, in this order of preference:
1. **New file** (new utility, new `Type+Concern.swift` extension). Zero conflict surface.
2. **Additive edit** to an upstream file: new method, new opt-in runtime flag whose
   default preserves upstream behavior. Precedents: `setKeepsAppAliveInBackground`,
   `setAllowsBackgroundClassification`, `startImport(skipExistingDays:)`.
3. **Inline edit of upstream logic** — only when the behavior itself must change.
   Mark every such divergence with a `// mapmyway:` comment stating WHY (these markers
   are greppable and are how future syncs detect silently reverted behavior).

Never restyle, reorder, or "clean up" upstream code you aren't changing behaviorally.

## Step 2 — Danger-zone checklist (consult what applies)

- **Writes to `TimelineItemBase` / `LocomotionSample` / `Place`**: read the relevant
  `Database+*Triggers.swift` first. Edge linking, `lastSaved`, disabled cascade,
  R-tree, and sample→item attachment are trigger-driven. Don't duplicate a trigger in
  Swift; don't bypass one with raw SQL. State in the commit body which triggers fire.
- **Schema changes**: append-only migrations, immutable identifiers. App-registered
  changes go in `addDelayedMigrations(to:)`. Never call `addMigrations()` twice/process.
- **Concurrency**: put code on the owning global actor (`@TimelineActor`,
  `@ActivityTypesActor`, `PlacesActor`, `HealthActor`, `ImportExportActor`).
  A Swift 6 isolation error means wrong actor, not missing `@unchecked Sendable`.
  `nonisolated(unsafe)` / `@unchecked Sendable` require user sign-off.
- **Recording hot path** (`LocomotionManager` location handling, `TimelineRecorder`
  sample persistence): tuned to one WAL commit per sample, no MainActor hops, detector
  feeds throttled at speed. Any extra commit/hop/allocation needs a perf argument in
  the commit body.
- **Background execution**: DB writes that can run backgrounded need
  `BackgroundTaskGuard` (0xdead10cc). Background CoreML stays opt-in and off the GPU.
- **Multi-app** (`AppGroup`): only the elected recorder processes; viewers notify via
  `notifyObjectChanges` (pending-set semantics, not last-write-wins).

## Step 3 — Implement

House style: `Log.info/error/debug(..., subsystem:)` never `print()`; `throws` + typed
error enums; recording path logs-and-continues instead of propagating; extensions split
by concern; English comments; keep `BIG-###` refs intact.

## Step 4 — Verify

```bash
xcodebuild -scheme LocoKit2 -destination 'generic/platform=iOS Simulator' build -quiet
```

- Must exit 0 with no new warnings. On failure, quote the first error and fix — never
  weaken the change to get green.
- If the change is simulator-testable logic (import/parsing/pure functions): add a
  regression test in `Tests/LocoKit2Tests/` using Swift Testing (`@Test`/`#expect`),
  then run:
  ```bash
  xcodebuild -scheme LocoKit2 -destination 'platform=iOS Simulator,name=iPhone 17' test -quiet
  ```
- If the behavior is device-only (background tasks, CoreML background, app-group IPC):
  say so explicitly and list a device test plan. Do not claim "works".

## Step 5 — Commit

Format (read `git log upstream/main..MapMyWay` for the house voice):

```
<type>: <subject ≤72 chars, imperative>

<Body: the WHY — failure mode, mechanism, measured effect. Written so a
future rebase conflict can be resolved from this text alone. Trivial
chores may omit the body.>
```

- Types: feat / fix / perf / chore / docs / test / refactor. One concern per commit.
- No Co-Authored-By, no emoji, English.
- Self-check before committing:
  - [ ] Diff contains only files the change needs.
  - [ ] Every edited upstream-owned file has a `// mapmyway:` marker at the divergence.
  - [ ] New public API has a doc comment stating what the consuming app uses it for.
  - [ ] Build green; tests green where they exist.

## Step 6 — Push & report

`git push origin MapMyWay` (plain push — no force outside the sync ritual).

Report: what changed, conflict surface added (which upstream-owned files/lines now
carry fork divergence), verification status, and whether the MapMyWay apps need a
package update + call-site changes (name the symbols).
