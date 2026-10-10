# Phase A status (checkpoint log — update after every checkpoint)

| # | Status | Commit | Verified | Open issues |
|---|---|---|---|---|
| 1 | done | 903bc67 + fix commit | swift test 29/29, build.sh ok. Dev channel: empty launch shows centred palette + empty address (snapshot), type+return opens tab, cmd+t opens palette and return makes a new tab, cmd+w twice closes window, session restore keeps order (3 tabs), launch with URL arg has no palette flash | strip + still at left until cp 3 |
| 2 | done | 7afb682 | swift test 33/33, build.sh ok. Clean LEAN_CONFIG_DIR run: cmd+, from an empty window opens lean://settings (General + Add-ons); page set message wrote search.template and tabstrip.position to settings.json (undeclared key rejected), strip moved to bottom, palette push list shows check on current; palette finds Tab Position and Turn On Import (enabling wrote addons.enabled, page refreshed); cmd+shift+a opens #addons. Not driven: Downloads Choose... panel, Edit... button, JS declare in the live app (unit-tested) | none known |
| 3 | done | 3d80d55 | swift test 35/35, build.sh ok. LEAN_CONFIG_DIR run with 4 restored tabs: snapshot layout in points matches spec (nav capsule x 80-171 = zoom right 69 + 12; focused capsule 360 wide, unfocused 150; + at x 1244-1272 = window right - 8; row centre y 16); favicons for github and wikipedia visible in snapshot; synthesized clicks (new dev click x y) confirmed via dev-state: tab select, x closes tab, + opens palette, reload reloads page, back/forward navigate; zero tabs shows only + | Glass renders blank white in snapshots (capsule text/favicon and palette contents not visible there), so focused-tab host text and glass look need the real-pixel check; width animation skipped; dev click hovers the tab by hand because tracking areas do not fire for synthetic events |
| 4 | todo | | | |

## Next step

Checkpoint 4 (docs/phase-a/04-address-in-tab.md). Test with LEAN_CONFIG_DIR=/tmp/lean-home/config.
