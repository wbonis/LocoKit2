# LocoKit2-Fork (MapMyWay)

Fork von sobri909/LocoKit2, der einen eigenen Patch-Stack für die MapMyWay-Apps trägt. Dieses Dokument ist das Glossar des Fork-Kontexts.

## Language

**Upstream**:
Das Repo sobri909/LocoKit2 — die Quelle, der wir folgen. Für uns strikt read-only.
_Avoid_: Original, Haupt-Repo, sobri-Repo

**Fork**:
Unser Repo wbonis/LocoKit2 (Remote `origin`). Trägt den Patch-Stack und ist das, was die Apps konsumieren.
_Avoid_: Kopie, unser LocoKit

**Patch-Stack**:
Die Menge unserer eigenen Commits, immer linear oben auf dem Upstream-Stand. Sichtbar als `upstream/main..MapMyWay`.
_Avoid_: unsere Änderungen, Patches (unspezifisch), Diff

**Work-Branch**:
Der Branch `MapMyWay` — der einzige Branch, auf dem entwickelt und committet wird. Trägt den Patch-Stack.
_Avoid_: mapmyway-patches (eingefroren, wird gelöscht)

**Sync**:
Das Rebase des Patch-Stacks auf einen neueren Upstream-Stand, abgeschlossen durch ein Sync-Tag. Passiert manuell und anlassbezogen, nie automatisch.
_Avoid_: Update, Merge, Pull

**Sync-Tag**:
Unveränderliches Tag `mmw/YYYY-MM-DD` auf dem Stack-Stand nach einem Sync. Hält alte Stände dauerhaft erreichbar, damit App-Pins nie auf tote Commits zeigen.
_Avoid_: Release, Version

**Archiv-Tag**:
Tag `archive/<name>` auf einem obsoleten Branch unmittelbar vor dessen Löschung. Konserviert die Historie ohne sichtbaren Branch.
_Avoid_: Backup-Branch
