# LocoKit2 Fork (MapMyWay)

Fork of sobri909/LocoKit2 carrying our own patch stack for the MapMyWay apps. This document is the glossary of the fork context.

## Language

**Upstream**:
The repo sobri909/LocoKit2 — the source we track. Strictly read-only for us.
_Avoid_: original, parent repo, sobri repo

**Fork**:
Our repo wbonis/LocoKit2 (remote `origin`). Carries the patch stack and is what the apps consume.
_Avoid_: copy, our LocoKit

**Patch Stack**:
The set of our own commits, always linear on top of the upstream state. Visible as `upstream/main..MapMyWay`.
_Avoid_: our changes, patches (unspecific), diff

**Work Branch**:
The branch `MapMyWay` — the only branch development and commits happen on. Carries the patch stack.
_Avoid_: mapmyway-patches (frozen, scheduled for deletion)

**Sync**:
Rebasing the patch stack onto a newer upstream state, concluded by a sync tag. Happens manually and on demand, never automatically.
_Avoid_: update, merge, pull

**Sync Tag**:
Immutable tag `mmw/YYYY-MM-DD` on the stack state after a sync. Keeps old states permanently reachable so app pins never point at dead commits.
_Avoid_: release, version

**Archive Tag**:
Tag `archive/<name>` on an obsolete branch immediately before its deletion. Preserves the history without a visible branch.
_Avoid_: backup branch
