# Rebase stack with sync tags for the fork workflow

We carry our patches as a linear rebase stack on top of `upstream/main` (sobri909/LocoKit2) and force-push the work branch `MapMyWay` after every sync. Because the MapMyWay apps pin the branch via SwiftPM and a force-push makes old SHAs unreachable, every sync state is secured with an immutable tag `mmw/YYYY-MM-DD` — old `Package.resolved` states stay buildable forever.

## Considered Options

- **Rebase stack (chosen)**: patch set always visible (`upstream/main..MapMyWay`), small and thematically ordered. Cost: routine force-push, tags required as pin protection.
- **Merge-based**: no force-push, stable SHAs — but merge bubbles dilute the patch set; after months it is no longer clear what is our own patch.
- **Patch queue (.patch files, quilt style)**: maximally explicit, but too much overhead while the patches themselves are under active development.

## Consequences

- Force-pushing `MapMyWay` is normal and intended — always `--force-with-lease`, never bare `--force`.
- Sync tags must never be deleted or moved; they accumulate by design.
- Syncs happen manually and on demand (upstream has something we want, or an app release is due), never automated — our patches live in files upstream actively changes; conflicts need review and the app needs a test afterwards.
- We do not offer patches upstream (deliberate policy, no public engagement); the full stack is carried by us permanently.
