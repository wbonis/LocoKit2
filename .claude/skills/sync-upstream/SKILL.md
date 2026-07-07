---
name: sync-upstream
description: Run the LocoKit2 fork sync ritual — rebase the MapMyWay patch stack onto upstream/main with intelligent conflict resolution, post-sync verification, and rollback safety. Use when the user says "sync", "sync upstream", "rebase onto upstream", or when /stack-audit recommended a sync.
---

# Sync the patch stack onto upstream

You are rebasing a permanent, curated patch stack (`upstream/main..MapMyWay`) onto a
moving upstream. The script does the mechanics; your job is the judgment: conflict
resolution that preserves BOTH intents, and verification that no patch silently died.

## Phase 0 — Preflight

1. `git status --porcelain` must be empty and branch must be `MapMyWay`. If not, stop
   and tell the user what's in the way (never stash or commit on their behalf).
2. Record the baseline for later verification:
   ```bash
   PRE_SHA=$(git rev-parse HEAD)
   PRE_COUNT=$(git rev-list --count upstream/main..MapMyWay)
   PRE_MARKERS=$(grep -rc "mapmyway:" Sources | awk -F: '{s+=$2} END {print s}')
   ```
3. Preview what's coming: `git fetch upstream && git log --oneline HEAD..upstream/main`.
   Summarize for the user in one or two sentences what upstream brings BEFORE rebasing.

## Phase 1 — Run the script

```bash
scripts/sync-upstream.sh
```

Three outcomes:
- **Clean run** (rebase + green build + tag + push): go to Phase 3.
- **Nothing to do / plain push**: report and stop.
- **Exit 1 with rebase conflict**: go to Phase 2.
- **Exit 1 with BUILD RED**: go to Phase 4.

## Phase 2 — Conflict resolution (the part that needs a brain)

For EACH stop of the rebase:

1. Identify which of our patches is being replayed:
   ```bash
   git log -1 --format='%h %s%n%n%b' REBASE_HEAD
   ```
   The commit body states the patch's intent. That intent is non-negotiable.
2. Identify what upstream did to the conflicted file(s) since our old base:
   ```bash
   git log --oneline $(cat .git/locokit2-sync-pre-sha)..upstream/main -- <file>
   ```
   Read the relevant upstream commits if the conflict isn't textually obvious.
3. Resolve so that BOTH survive: upstream's new code shape + our patch's behavior.
   Typical shapes:
   - Upstream moved/renamed the code: re-apply our hunk at the new location, keep the
     `// mapmyway:` marker with it.
   - Upstream changed adjacent lines: merge textually, keep both.
   - Upstream implemented something similar to our patch: STOP. This is escalation
     rule 2 in CLAUDE.md — present patch vs upstream commit side by side, let the
     user decide (drop ours / keep ours / hybrid). Do not decide alone.
   - Genuinely incompatible intents: STOP mid-rebase, present both intents and a
     proposed resolution, wait for the user (escalation rule 1).
4. After resolving: `git add -A && git rebase --continue`, then **run the script
   again** — it detects the finished rebase and continues (build, tag, push).
5. Abort hatch at any point: `git rebase --abort` restores the pre-sync state exactly.

Never resolve a conflict by deleting our hunk or upstream's hunk just to move on.

## Phase 3 — Post-sync verification

All four checks, every time:

1. **Patch count**: `git rev-list --count upstream/main..MapMyWay` == `$PRE_COUNT`.
   A lower count means a patch was dropped (rebase may silently skip patches that
   became empty). Find it with the Phase 0 baseline:
   ```bash
   git range-diff $(git merge-base $PRE_SHA upstream/main)..$PRE_SHA upstream/main..HEAD
   ```
   (If `$PRE_SHA` is lost, `ORIG_HEAD` usually still points at it after the rebase.)
   A dropped-because-upstreamed patch is GOOD news but needs user confirmation.
2. **Marker count**: recompute `PRE_MARKERS` grep — unchanged, or every delta explained.
3. **Stack readable**: `git log --oneline upstream/main..MapMyWay` — same patches, same
   order, no fixup/conflict-artifact subjects.
4. **Tag + push landed**: `git tag --contains HEAD | grep mmw/` shows today's tag;
   `git rev-parse origin/MapMyWay` == `git rev-parse HEAD`.

## Phase 4 — Build red

The script already refused to push (that's the design — nothing published is broken).

1. Quote the FIRST compiler error verbatim.
2. Diagnose: is it a semantic conflict (upstream renamed/retyped something a patch
   uses)? Fix the patch commit itself:
   ```bash
   # fix the file(s), then fold the fix into the owning patch:
   git add -A && git commit --fixup <patch-sha>
   ```
   Then tell the user the stack needs an autosquash pass — interactive rebase is not
   available to you, so either (a) leave the fixup commit on top and note it, or
   (b) if the broken patch is the tip, use `git commit --amend` instead.
3. If the error is NOT caused by our patches (upstream itself is broken): report,
   propose waiting for upstream to fix, offer `git reset --hard $(cat .git/locokit2-sync-pre-sha)`.
4. Rerun the script after fixing — it is idempotent and picks up where it left off.

## Phase 5 — Report

End with, in this order:
- Upstream commits absorbed (count + one-line theme).
- Conflicts hit and how each was resolved (one line each).
- Verification results (four checks).
- New sync tag name.
- The standing reminder: **update the app's package in Xcode** (File → Packages →
  Update to Latest Package Versions), then smoke-test recording.
