# Phase A status (checkpoint log — update after every checkpoint)

| # | Status | Commit | Verified | Open issues |
|---|---|---|---|---|
| 1 | done | 903bc67 + fix commit | swift test 29/29, build.sh ok. Dev channel: empty launch shows centred palette + empty address (snapshot), type+return opens tab, cmd+t opens palette and return makes a new tab, cmd+w twice closes window, session restore keeps order (3 tabs), launch with URL arg has no palette flash | strip + still at left until cp 3 |
| 2 | done | e4d7bbf | swift test 33/33, build.sh ok. Clean LEAN_CONFIG_DIR run: cmd+, from an empty window opens lean://settings (General + Add-ons); page set message wrote search.template and tabstrip.position to settings.json (undeclared key rejected), strip moved to bottom, palette push list shows check on current; palette finds Tab Position and Turn On Import (enabling wrote addons.enabled, page refreshed); cmd+shift+a opens #addons. Not driven: Downloads Choose... panel, Edit... button, JS declare in the live app (unit-tested) | none known |
| 3 | todo | | | |
| 4 | todo | | | |

## Next step

Checkpoint 3 (docs/phase-a/03-top-bar-tabs-glass.md). Test with LEAN_CONFIG_DIR=/tmp/lean-home/config.
