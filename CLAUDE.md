# LocoKit2 fork (MapMyWay) — operating manual

Read this before touching anything. It encodes the fork workflow, the codebase's sharp
edges, and the quality bar. When this file and your instincts disagree, this file wins.

**Remotes:** `upstream` = sobri909/LocoKit2 (read-only, never push, never PR).
`origin` = our fork wbonis/LocoKit2. **Work branch:** `MapMyWay` — the ONLY branch;
apps pin it via SwiftPM. Glossary: `CONTEXT.md`. Workflow rationale:
`docs/adr/0001-rebase-stack-with-sync-tags.md`.

**What this repo is:** a permanent linear patch stack (currently ~21 commits) rebased on
top of `upstream/main`. See it: `git log --oneline upstream/main..MapMyWay`. Every
change you make is a patch that must survive future rebases against an actively moving
upstream. That single fact drives most rules below.

## Build & test (there is no `swift build` here)

The package is iOS-only (imports UIKit/CoreMotion/BackgroundTasks/HealthKit).
`swift build` / `swift test` on macOS FAIL. Always:

```bash
# Build (this is also the sync script's green gate):
xcodebuild -scheme LocoKit2 -destination 'generic/platform=iOS Simulator' build -quiet

# Tests (needs a concrete simulator; list with: xcrun simctl list devices available):
xcodebuild -scheme LocoKit2 -destination 'platform=iOS Simulator,name=iPhone 17' test -quiet
```

`Package.swift` is authoritative: iOS 18, swift-tools 6.0 (= Swift 6 language mode,
strict concurrency ON). README.md says iOS 17/Xcode 15 — stale upstream text, ignore it.

## Git workflow

### Happy path
- Commit on `MapMyWay`, push normal: `git push origin MapMyWay`.
- Check upstream news: `git fetch upstream && git log --oneline MapMyWay..upstream/main`.
- Forecast sync pain before it happens: `/stack-audit` skill.

### Sync ritual (manual, on demand — upstream has something we want OR app release due)
One command: `scripts/sync-upstream.sh` — or better, the `/sync-upstream` skill, which
wraps it with conflict resolution and post-sync verification.

Script is state-driven: fetch → rebase (`--committer-date-is-author-date`) → build →
sync tag `mmw/YYYY-MM-DD` (same day: `-2` suffix) → force-with-lease push → main mirror.
Pushes ONLY on green build. Rollback point: `.git/locokit2-sync-pre-sha`.
On conflict: fix files → `git add -A && git rebase --continue` → run script again.

### Gone wrong — fix
- Rebase bad, want out: `git rebase --abort`.
- Finished rebase but wrong: `git reset --hard ORIG_HEAD` or `git reset --hard mmw/<last-date>`.
- Force-push regret: `git reset --hard mmw/<date>` → `git push --force-with-lease origin MapMyWay`.
- Sync tags are the built-in restore points. That's why they're immutable.

### Policies
- **No upstream PRs, no upstream pushes.** Full stack carried permanently (ADR 0001).
- **Never delete/move `mmw/*` tags** — old app `Package.resolved` pins die otherwise.
- **Never bare `--force`** — `--force-with-lease` only, and only in the sync context.
- `main` on fork = cosmetic upstream mirror, maintained by the sync script.
- `mapmyway-patches` branch: frozen. From ~2026-07-10: tag as `archive/mapmyway-patches`,
  push tag, delete branch on origin and locally.
- Repo artifacts (code, comments, commits, docs, scripts) in English. Chat in German.
- After every sync: update the app's package in Xcode, else it builds the old state.

## Codebase map

~110 Swift files, ~18k lines, under `Sources/LocoKit2/`:

- **Recording engine:** `Managers/LocomotionManager.swift` (`@Observable` singleton
  `.highlander`; CLLocationManager/CoreMotion, state machine, AsyncStreams) +
  `Managers/TimelineRecorder.swift` (`@TimelineActor enum`; samples → timeline items).
  `Samplers/` = Kalman filters + stationary/sleep/underground detectors.
- **Timeline processing:** `Managers/TimelineProcessor.swift` + 11 `+Concern` extensions
  (merges, extraction, edge healing, user actions…), `Merge.swift`/`MergeScores.swift`.
- **Models:** `Models/` — GRDB record structs (`TimelineItemBase/Visit/Trip`,
  `LocomotionSample`, `Place`, `DriftProfile`…), composite `TimelineItem`.
- **Persistence:** `Database/` — `Database.highlander` (GRDB `DatabasePool`, WAL,
  app-group container, `LocoKit2.sqlite`), schema in `Database+Schema.swift`,
  triggers in `Database+*Triggers.swift`, `Database+DelayedMigrations.swift`.
- **Classification:** `ActivityTypes/` — CoreML, `ActivityClassifier`
  (`@ActivityTypesActor enum`), geo-keyed models cached at runtime (models come from
  the consuming app, none bundled here).
- **Import/Export:** `ImportExport/` — `ImportManager`, `ExportManager`,
  `OldLocoKitImporter`, resumable `ImportState`.
- **Infra:** `AppGroup.swift` (multi-app coordination, recorder election),
  `BackgroundTasksManager` (`@MainActor`), `Utilities/BackgroundTaskGuard.swift`
  (0xdead10cc protection), `DebugLogger.swift` (`Log` enum).

**Concurrency model:** five global actors (`TimelineActor`, `PlacesActor`,
`ActivityTypesActor`, `HealthActor`, `ImportExportActor`), each owning a subsystem.
Stateful subsystems are `enum` namespaces of `static` members pinned to their actor.
Singletons are named `highlander`. `@unchecked Sendable` types (`Database`,
`LocomotionManager`, `AppGroup`) guard state with `Mutex`/`NSLock` manually.

**Logic lives in SQL triggers**, not only Swift: edge linking (`nextItemId`/
`previousItemId`), `lastSaved` bumps, disabled-state cascade, R-tree maintenance,
sample→item attachment on insert. Read `Database+*Triggers.swift` before writing to
`TimelineItemBase`, `LocomotionSample`, or `Place`.

## Conventions

Established (follow exactly):
- Commits: `<type>: <subject>` — feat/fix/perf/chore/docs/test/refactor. English,
  imperative, subject ≤72 chars. Body = the WHY: mechanism, failure mode, measured
  effect (read `git log upstream/main..MapMyWay` for the house style). No Co-Authored-By.
- One concern per commit. The stack stays small and thematically ordered.
- Fork divergence inside upstream-owned code gets a `// mapmyway:` comment explaining
  the divergence (greppable; protects the intent through rebases and upstream syncs).
- `BIG-###` in comments = app-side ticket references. Keep them.
- Large types split into `Type+Concern.swift` extension files, not one big file.
- Errors: `throws` + typed error enums. On the recording path: log and continue
  (`Log.error(error, subsystem: .x)`), never crash recording.
- Logging: `Log.info/error/debug(..., subsystem:)` — never `print()`.
- New tests: Swift Testing (`@Test`/`#expect`). Existing XCTest stays as is.

Added (follow these too):
- **Additive over invasive:** prefer new files, new `+Concern` extensions, and opt-in
  runtime flags (default = upstream behavior) over editing upstream lines. Pattern
  precedent: `setKeepsAppAliveInBackground`, `setAllowsBackgroundClassification`.
- **Ownership check before editing:** `git ls-tree upstream/main -- <path>` — if the
  file exists upstream, every line you touch is future rebase-conflict surface.
- **Hot path is sacred:** the per-sample recording path is tuned (single WAL commit per
  sample, no MainActor hops, detector feeds throttled to 1Hz at speed). No extra DB
  commits, actor hops, or per-location allocations there without a perf argument in
  the commit body.
- Migration identifiers are append-only and immutable. Never call `addMigrations()`/
  `doMigrations()` twice per process (GRDB traps). App-registered schema changes go in
  `addDelayedMigrations(to:)`.
- `Package.resolved` stays gitignored (library consumers pin, the package doesn't).

## Known failure modes — named, with the rule that prevents each

1. **The macOS build reflex** — running `swift build`/`swift test`.
   Rule: xcodebuild + iOS Simulator only (commands above).
2. **The merge reflex** — `git pull upstream` / `git merge upstream/main` to "update".
   Rule: sync = rebase via `scripts/sync-upstream.sh` only. A merge bubble destroys
   the visible patch stack.
3. **The helpful refactor** — "improving" upstream code style, renaming, reordering
   imports in upstream files. Rule: minimal diff footprint; touch upstream lines only
   when the patch requires it, and mark with `// mapmyway:`.
4. **The silencing reflex** — Swift 6 isolation error, so slap on `@unchecked Sendable`
   or `nonisolated(unsafe)`. Rule: put the code on the subsystem's global actor
   instead; `@unchecked Sendable` only with an explicit lock AND user sign-off.
5. **Trigger blindness** — duplicating trigger behavior in Swift (double-fires) or raw
   SQL that bypasses it (corruption). Rule: read the relevant `Database+*Triggers.swift`
   before any write path change; state in the commit body which triggers fire.
6. **Conflict "resolution" by deletion** — dropping our hunk or upstream's hunk to make
   a rebase conflict go away. Rule: both intents must survive; if they genuinely can't,
   escalate (below). Precedent: c8d4241 exists because an upstream sync silently
   reverted a fork behavior once.
7. **Tag housekeeping** — deleting "old" `mmw/*` tags or retagging. Rule: never.
   They are load-bearing (app pins) by design.
8. **Branch creativity** — feature branches, committing to `main`. Rule: everything on
   `MapMyWay` unless the user explicitly says otherwise.
9. **The upstream PR itch** — "this fix would help upstream!" Rule: no upstream
   engagement, ever (ADR 0001).
10. **Hardcoded staleness** — trusting README platform claims or hardcoding stack
    counts/dates. Rule: derive from `Package.swift` and live git queries.
11. **Language drift** — German comments/commits because chat is German. Rule: repo
    artifacts English, always.
12. **Done-claiming without device caveats** — background/CoreML/CLBackgroundActivity
    behavior can't be verified in a simulator. Rule: say exactly what is and isn't
    verified (see quality bar).

## Quality bar — checkable, per deliverable

**Any code change is done when:**
- [ ] `xcodebuild … build -quiet` exits 0 (paste nothing on success; quote the first
      error on failure).
- [ ] Zero new compiler/concurrency warnings introduced.
- [ ] `git diff` touches only files the change needs; every edited upstream-owned file
      has a `// mapmyway:` marker at the divergence.
- [ ] No `print()`, no new force-unwraps on the recording path, no new singletons
      except by the `highlander` pattern.
- [ ] New public API has a doc comment stating what the consuming app uses it for.

**A bug fix additionally:**
- [ ] Root cause named in the commit body (mechanism, not symptom).
- [ ] Regression test added IF the logic is simulator-testable (import/parsing/pure
      logic — see `Tests/LocoKit2Tests/` for precedent). If not testable, the commit
      body says why and what to watch on device.

**A commit is done when:**
- [ ] `<type>: <subject>`, English, imperative, ≤72 chars, one concern.
- [ ] Body answers "why was it broken / why this way" — not a diff restatement.
      Trivial chores (gitignore etc.) may omit the body.
- [ ] No Co-Authored-By, no emoji.

**A sync is done when:**
- [ ] Ran via script/skill, build green, tag pushed.
- [ ] Patch count `git rev-list --count upstream/main..MapMyWay` matches pre-sync count
      (or every difference is explained and user-approved).
- [ ] `grep -rc "mapmyway:" Sources` count unchanged (or explained).
- [ ] User reminded: update app package in Xcode.

**Docs/ADR are done when:**
- [ ] English, uses CONTEXT.md glossary terms (upstream/fork/patch stack/sync tag —
      not "original repo"/"our changes").
- [ ] Workflow-changing decisions get an ADR in `docs/adr/` with considered options.

## When uncertain — escalation rules

1. **Rebase conflict, non-mechanical** (upstream rewrote code a patch modifies): STOP
   mid-rebase. Present the patch's intent (from its commit body), upstream's new
   approach, and a proposed resolution preserving both. Wait for the user. Never
   resolve by silently dropping either side.
2. **A patch looks obsolete** (upstream implemented the equivalent): do NOT drop it.
   Report patch SHA + upstream commit side by side; the user decides.
3. **Anything touching history or tags** beyond the script's own flow — tag deletion,
   force-push outside sync, stack reordering/squashing: ask first, always. These are
   the irreversible operations in this repo.
4. **Device-only behavior** (background tasks, 0xdead10cc, CoreML in background,
   CLBackgroundActivitySession, app-group IPC across apps): implement, build green,
   then explicitly list what remains unverified and a device test plan. Never claim
   "works" from a simulator build alone.
5. **Public API changes**: proceed when asked, but flag that the MapMyWay apps need a
   package update + call-site changes, and name the affected symbols.
6. **Build red for reasons unrelated to your change** (toolchain, simulator, upstream
   breakage): report the first error verbatim and stop. Do not weaken your change to
   get to green.
7. **Unclear if a behavior difference vs upstream is intentional**: grep for
   `mapmyway:` and search the stack (`git log upstream/main..MapMyWay --grep=<topic>`,
   `git log -S<symbol> upstream/main..MapMyWay`). If still unclear, ask — a "fix" that
   reverts a deliberate fork patch is the most expensive mistake available here.
