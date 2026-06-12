# Rebase-Stack mit Sync-Tags für den Fork-Workflow

Wir tragen unsere Patches als linearen Rebase-Stack oben auf `upstream/main` (sobri909/LocoKit2) und force-pushen den Work-Branch `MapMyWay` nach jedem Sync. Weil die MapMyWay-Apps den Branch per SwiftPM pinnen und Force-Push alte SHAs unerreichbar macht, wird jeder Sync-Stand mit einem unveränderlichen Tag `mmw/YYYY-MM-DD` gesichert — alte `Package.resolved`-Stände bleiben dadurch dauerhaft baubar.

## Considered Options

- **Rebase-Stack (gewählt)**: Patch-Set jederzeit sichtbar (`upstream/main..MapMyWay`), klein und thematisch geordnet. Kosten: routinemäßiger Force-Push, Tags nötig als Pin-Schutz.
- **Merge-basiert**: kein Force-Push, stabile SHAs — aber Merge-Bubbles verwässern das Patch-Set; nach Monaten ist nicht mehr erkennbar, was eigener Patch ist.
- **Patch-Queue (.patch-Dateien, quilt-Stil)**: maximal explizit, aber zu viel Overhead bei aktiver Eigenentwicklung an den Patches.

## Consequences

- Force-Push auf `MapMyWay` ist normal und beabsichtigt — immer `--force-with-lease`, nie blankes `--force`.
- Sync-Tags dürfen nie gelöscht oder verschoben werden; sie akkumulieren bewusst.
- Syncs passieren manuell und anlassbezogen (Upstream hat etwas Gewolltes, oder App-Release steht an), nie automatisiert — unsere Patches sitzen in Dateien, die Upstream aktiv ändert; Konflikte brauchen Review und die App danach einen Test.
- Wir bieten keine Patches upstream an (bewusste Policy, kein öffentliches Engagement); der volle Stack wird dauerhaft selbst getragen.
