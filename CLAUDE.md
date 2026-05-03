# LocoKit2 — fork git (caveman)

**Remotes:** `upstream` = sobri909/LocoKit2 (`git@github.com:sobri909/LocoKit2.git`). `origin` = our fork. **Work branch:** `mapmyway-patches`.

## Happy path

- Commit on `mapmyway-patches`. Push normal: `git push origin mapmyway-patches`.
- Pull sobri909 main under us (linear stack, no merge bubble):

```bash
git fetch upstream
git checkout mapmyway-patches
git rebase upstream/main
git push --force-with-lease origin mapmyway-patches
```

- Rebase stop on conflict: fix files → `git add -A` → `git rebase --continue`. Repeat til done.

## Gone wrong — fix

- **Rebase bad / want abort:** `git rebase --abort` → back to pre-rebase branch state.
- **Already finished rebase but wrong:** `git reflog` → find SHA before rebase (often `HEAD@{1}` or label `ORIG_HEAD` right after rebase) → `git reset --hard <that-sha>`.
- **Conflict botched mid-rebase:** same `git rebase --abort` OR fix + `git add` + `git rebase --continue`.
- **Force-push regret (remote overwrote):** `git reflog` on local → reset hard to good SHA → `git push --force-with-lease origin mapmyway-patches` (only if sure nobody else need old remote tip).
- **`main` sync upstream (optional):** `git checkout main && git fetch upstream && git reset --hard upstream/main && git push --force-with-lease origin main`.

## Rules thumb

- Prefer **rebase** onto `upstream/main` for sync — keeps MapMyWay commits on top.
- Never `--force` without `--force-with-lease` if remote shared.
- Multi-person branch: coordinate before force-push.
