# LocoKit2 — fork git (caveman)

**Remotes:** `upstream` = sobri909/LocoKit2 (`git@github.com:sobri909/LocoKit2.git`, read-only). `origin` = our fork wbonis/LocoKit2. **Work branch:** `MapMyWay` (single source of truth; apps pin this branch via SwiftPM).

Glossar: `CONTEXT.md`. Workflow-Entscheidung + Begründung: `docs/adr/0001-rebase-stack-mit-sync-tags.md`.

## Happy path

- Commit on `MapMyWay`. Push normal: `git push origin MapMyWay`.
- Check what upstream got: `git fetch upstream && git log --oneline MapMyWay..upstream/main`.

## Sync ritual (manual, anlassbezogen — upstream hat was Gewolltes ODER App-Release steht an)

```bash
git fetch upstream
git checkout MapMyWay
git rebase upstream/main
# Konflikte: fix files → git add -A → git rebase --continue. Repeat til done.
# DANN: bauen + App-Smoke-Test. Erst wenn grün:
git tag mmw/$(date +%Y-%m-%d)
git push --force-with-lease origin MapMyWay
git push origin mmw/$(date +%Y-%m-%d)
# App: Xcode → Update to Latest Package Versions
```

- Zweiter Sync am selben Tag: Tag-Suffix `-2`.
- **Sync-Tags nie löschen/verschieben** — sie halten alte SHAs am Leben, sonst zeigen alte `Package.resolved` der Apps auf tote Commits.

## Policies

- **No upstream PRs.** Voller Patch-Stack wird dauerhaft selbst getragen (bewusste Entscheidung, siehe ADR 0001).
- `mapmyway-patches`: eingefroren (alter, unsauberer Stack — tree-identisch zu `MapMyWay`). Ab ~2026-07-10: `git tag archive/mapmyway-patches mapmyway-patches && git push origin archive/mapmyway-patches && git push origin --delete mapmyway-patches && git branch -D mapmyway-patches`.
- `main` auf Fork: reiner Upstream-Mirror, optional nachziehen: `git checkout main && git fetch upstream && git reset --hard upstream/main && git push --force-with-lease origin main`.

## Gone wrong — fix

- **Rebase bad / want abort:** `git rebase --abort` → back to pre-rebase branch state.
- **Already finished rebase but wrong:** `git reflog` → find SHA before rebase (often `ORIG_HEAD`) → `git reset --hard <that-sha>`. Oder einfach: `git reset --hard mmw/<letztes-datum>`.
- **Conflict botched mid-rebase:** `git rebase --abort` OR fix + `git add` + `git rebase --continue`.
- **Force-push regret:** `git reset --hard mmw/<datum>` (Sync-Tags = eingebaute Restore-Punkte) → `git push --force-with-lease origin MapMyWay`.

## Rules thumb

- Prefer **rebase** onto `upstream/main` — keeps Patch-Stack on top, sichtbar via `git log upstream/main..MapMyWay`.
- Never `--force` without `--force-with-lease`.
- Nach jedem Sync: App-Package updaten, sonst baut sie alten Stand.
