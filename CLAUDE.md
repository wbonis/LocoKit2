# LocoKit2 — fork git (caveman)

**Remotes:** `upstream` = sobri909/LocoKit2 (`git@github.com:sobri909/LocoKit2.git`, read-only). `origin` = our fork wbonis/LocoKit2. **Work branch:** `MapMyWay` (single source of truth; apps pin this branch via SwiftPM).

Glossary: `CONTEXT.md`. Workflow decision + rationale: `docs/adr/0001-rebase-stack-with-sync-tags.md`.

## Happy path

- Commit on `MapMyWay`. Push normal: `git push origin MapMyWay`.
- Check what upstream got: `git fetch upstream && git log --oneline MapMyWay..upstream/main`.

## Sync ritual (manual, on demand — upstream has something we want OR app release is due)

**One command, does everything right:**

```bash
scripts/sync-upstream.sh
```

State-driven: fetch → rebase (`--committer-date-is-author-date`, patches keep their original dates) → build (iOS Simulator) → sync tag `mmw/YYYY-MM-DD` (same day: suffix `-2`) → force-with-lease push → main mirror. Pushes ONLY on green build. On rebase conflict: fix files → `git add -A && git rebase --continue` → run script again. Abort: `git rebase --abort`. Rollback point lives in `.git/locokit2-sync-pre-sha`.

Manual steps (reference, if script unusable): fetch upstream → rebase as above → build → tag → force-with-lease push branch+tag → `git branch -f main upstream/main` + push.

- **Never delete/move sync tags** — they keep old SHAs alive; otherwise old `Package.resolved` in the apps point at dead commits.

## Policies

- **No upstream PRs.** Full patch stack carried by us permanently (deliberate decision, see ADR 0001).
- **Scripts and docs in English.** Chat with user in German.
- `mapmyway-patches`: frozen (old, messy stack — tree-identical to `MapMyWay`). From ~2026-07-10: `git tag archive/mapmyway-patches mapmyway-patches && git push origin archive/mapmyway-patches && git push origin --delete mapmyway-patches && git branch -D mapmyway-patches`.
- `main` on fork: pure upstream mirror (decoration, not part of the sync path). Updated by the sync script; works solo anytime: `git branch -f main upstream/main && git push --force-with-lease origin main`.

## Gone wrong — fix

- **Rebase bad / want abort:** `git rebase --abort` → back to pre-rebase branch state.
- **Already finished rebase but wrong:** `git reflog` → find SHA before rebase (often `ORIG_HEAD`) → `git reset --hard <that-sha>`. Or simply: `git reset --hard mmw/<last-date>`.
- **Conflict botched mid-rebase:** `git rebase --abort` OR fix + `git add` + `git rebase --continue`.
- **Force-push regret:** `git reset --hard mmw/<date>` (sync tags = built-in restore points) → `git push --force-with-lease origin MapMyWay`.

## Rules thumb

- Prefer **rebase** onto `upstream/main` — keeps patch stack on top, visible via `git log upstream/main..MapMyWay`.
- Never `--force` without `--force-with-lease`.
- After every sync: update app package in Xcode, otherwise it builds the old state.
