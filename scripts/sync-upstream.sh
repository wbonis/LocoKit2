#!/usr/bin/env bash
# LocoKit2 fork sync ritual — see CLAUDE.md + docs/adr/0001-rebase-stack-with-sync-tags.md
#
# One command, state-driven and idempotent:
#   - upstream has news     -> rebase + build + sync tag + force-push + mirror
#   - rebase finished local -> build + sync tag + force-push + mirror (e.g. after conflict fix)
#   - only own commits      -> plain push + mirror
#   - everything current    -> mirror only
#
# On rebase conflict: fix files, `git add -A && git rebase --continue`,
# then run this script again.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

WORK_BRANCH="MapMyWay"
PRE_SHA_FILE=".git/locokit2-sync-pre-sha"

die() { echo "ABORT: $*" >&2; exit 1; }

# --- Preflight checks ---------------------------------------------------------
git remote get-url upstream 2>/dev/null | grep -q "sobri909/LocoKit2" \
    || die "Remote 'upstream' missing or not pointing at sobri909/LocoKit2"
git remote get-url origin >/dev/null 2>&1 || die "Remote 'origin' missing"

[ -d .git/rebase-merge ] || [ -d .git/rebase-apply ] \
    && die "Rebase in progress — first 'git add -A && git rebase --continue' (or --abort)"

current_branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$current_branch" = "$WORK_BRANCH" ] \
    || die "Not on $WORK_BRANCH (current: $current_branch)"

[ -z "$(git status --porcelain)" ] \
    || die "Worktree not clean — commit or stash first"

# --- Determine state -----------------------------------------------------------
echo "==> fetch upstream + origin"
git fetch upstream
git fetch origin

upstream_is_base=false
git merge-base --is-ancestor upstream/main HEAD && upstream_is_base=true

origin_sha="$(git rev-parse "origin/$WORK_BRANCH" 2>/dev/null || echo none)"
head_sha="$(git rev-parse HEAD)"

# --- Case 1: upstream has news -> rebase ----------------------------------------
if [ "$upstream_is_base" = false ]; then
    echo "==> Upstream brings $(git rev-list --count HEAD..upstream/main) new commits:"
    git log --oneline HEAD..upstream/main
    echo "$head_sha" > "$PRE_SHA_FILE"
    echo "==> Rollback point saved: $head_sha"
    if ! git rebase upstream/main --committer-date-is-author-date; then
        cat >&2 <<'EOM'
Rebase conflict. Now:
  1. Fix the files
  2. git add -A && git rebase --continue   (repeat until done)
  3. Run scripts/sync-upstream.sh again
Or roll everything back: git rebase --abort
EOM
        exit 1
    fi
    head_sha="$(git rev-parse HEAD)"
fi

# --- Case 2: nothing to do? -----------------------------------------------------
if [ "$head_sha" = "$origin_sha" ]; then
    echo "==> Branch up to date, nothing to push."
else
    # --- Case 3: only own new commits (origin is ancestor) -> plain push --------
    if [ "$origin_sha" != none ] && git merge-base --is-ancestor "$origin_sha" HEAD; then
        echo "==> Only new own commits — plain push."
        git push origin "$WORK_BRANCH"
    else
        # --- Case 4: history rewritten (sync) -> build, tag, force-push ---------
        echo "==> Building LocoKit2 (iOS Simulator)..."
        if ! xcodebuild -scheme LocoKit2 -destination 'generic/platform=iOS Simulator' build -quiet; then
            echo "BUILD RED — nothing pushed." >&2
            [ -f "$PRE_SHA_FILE" ] && echo "Rollback: git reset --hard $(cat "$PRE_SHA_FILE")" >&2
            exit 1
        fi
        echo "==> BUILD GREEN"

        tag="mmw/$(date +%F)"
        n=2
        while git rev-parse -q --verify "refs/tags/$tag" >/dev/null; do
            tag="mmw/$(date +%F)-$n"
            n=$((n + 1))
        done
        git tag "$tag"
        echo "==> Sync tag: $tag"

        # Protect the old origin tip before orphaning it: the app may pin an
        # untagged SHA from a plain push between syncs. Skip if already
        # reachable from some tag.
        if [ "$origin_sha" != none ] && [ -z "$(git tag --contains "$origin_sha" 2>/dev/null)" ]; then
            pre_tag="mmw/$(date +%F)-pre"
            n=2
            while git rev-parse -q --verify "refs/tags/$pre_tag" >/dev/null; do
                pre_tag="mmw/$(date +%F)-pre$n"
                n=$((n + 1))
            done
            git tag "$pre_tag" "$origin_sha"
            git push origin "$pre_tag"
            echo "==> Pre-sync tag on old origin tip: $pre_tag"
        fi

        git push --force-with-lease origin "$WORK_BRANCH"
        git push origin "$tag"
        rm -f "$PRE_SHA_FILE"
    fi
fi

# --- Mirror: keep main cosmetically on upstream ----------------------------------
echo "==> Updating main mirror"
git branch -f main upstream/main
git push --force-with-lease origin main

# --- Summary ---------------------------------------------------------------------
echo
echo "DONE. Patch stack: $(git rev-list --count upstream/main..HEAD) commits on $(git rev-parse --short upstream/main)."
echo "Don't forget: app in Xcode -> Update to Latest Package Versions + smoke test."
