---
name: stack-audit
description: Forecast the next LocoKit2 upstream sync — what upstream changed, which patches will conflict, which patches may be obsolete, and whether syncing now is worth it. Read-only, touches nothing. Use when the user asks "what did upstream get", "should we sync", "will the sync hurt", or before planning a sync.
---

# Stack audit — upstream drift forecast

Answer three questions without touching the worktree or history:
1. What does upstream have that we don't?
2. What will the rebase cost (which patches conflict where)?
3. Did upstream obsolete or undermine any of our patches?

This is read-only. `git fetch` is the only network operation; no checkout, no rebase.

## Step 1 — Gather

```bash
git fetch upstream
BASE=$(git merge-base MapMyWay upstream/main)
git log --oneline $BASE..upstream/main          # upstream news
git rev-list --count $BASE..upstream/main       # how much news
git log --oneline upstream/main..MapMyWay       # our stack (for reference)
```

If upstream has nothing new: say so, report last sync tag (`git tag -l 'mmw/*' | sort | tail -1`)
and stop. No sync needed.

## Step 2 — Collision forecast (mechanical conflicts)

Intersect the files our stack touches with the files upstream changed:

```bash
git diff --name-only $BASE MapMyWay -- Sources Tests > /tmp/ours.txt
git diff --name-only $BASE upstream/main -- Sources Tests > /tmp/theirs.txt
comm -12 <(sort /tmp/ours.txt) <(sort /tmp/theirs.txt)
```

For each overlapping file, go one level deeper — do the HUNKS overlap?

```bash
# our hunks in that file:
git diff $BASE MapMyWay -- <file> | grep '^@@'
# upstream's hunks:
git diff $BASE upstream/main -- <file> | grep '^@@'
```

Classify each overlapping file:
- **RED** — hunk ranges overlap or are within ~10 lines: conflict near-certain.
  Name the patch that owns our hunk: `git log --format='%h %s' upstream/main..MapMyWay -- <file>`.
- **YELLOW** — same file, distant hunks: rebase will likely auto-merge, but the patch
  deserves a post-sync review.
- Everything else: GREEN, ignore.

## Step 3 — Obsolescence & semantic drift (the expensive-to-miss part)

Mechanical conflicts are cheap; semantic ones are not. For each patch in the stack
(subjects from `git log upstream/main..MapMyWay`):

1. **Obsolescence**: does an upstream commit subject/diff implement the same thing?
   Search: `git log $BASE..upstream/main --grep=<keyword> -i` and
   `git log -S<key-symbol> $BASE..upstream/main` for the patch's central symbol
   (e.g. `setAllowsBackgroundClassification`, `BackgroundTaskGuard`, `skipExistingDays`).
2. **Undermining**: did upstream change code our patch DEPENDS on but doesn't touch?
   Check the symbols each patch calls into. High-risk zones from past experience:
   - SQL triggers (`Database+*Triggers.swift`) — our hot-path commit relies on
     `LocomotionSample_AFTER_INSERT_timelineItemId_SET` firing on insert.
   - Background/classification guards — upstream once silently re-disabled a fork
     behavior (that's why c8d4241 exists as a flag-gate).
   - `TimelineProcessor.process(_ list:)` funnel — our BackgroundTaskGuard hangs off it.
   - Actor/isolation changes on `TimelineActor`/`ActivityTypesActor` types.
3. **Schema drift**: `git diff $BASE upstream/main -- Sources/LocoKit2/Database/ | grep '^[+-]'`
   — any new migrations, renamed triggers, or changed CHECK constraints? These can
   break silently (triggers don't produce compile errors).

## Step 4 — Report

Deliver a verdict, then the evidence:

**Verdict** (one of):
- "Sync now, will be clean" — no RED, no obsolescence hits.
- "Sync will conflict: <n> patches in <files>" — list RED pairs (patch ↔ upstream commit).
- "Hold: upstream in flux / nothing we need" — when news is churn we don't consume.

**Evidence table** (only non-GREEN rows):

| Our patch | File | Upstream commit | Class | What to do during sync |
|---|---|---|---|---|

**Obsolescence candidates**: patch SHA + upstream commit SHA side by side, with a
one-line comparison. Recommend keep/drop/hybrid but mark it as the user's decision.

**Trigger/schema drift**: name any trigger or migration upstream touched, and which of
our code paths assume the old behavior.

Do NOT start a sync from this skill. Recommend `/sync-upstream` when the verdict says go.
