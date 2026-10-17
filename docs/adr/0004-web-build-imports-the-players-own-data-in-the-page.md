# The web build imports the player's own data in the page, and only the web shell touches the network

The game also ships as a web build: a single-threaded Godot web export on GitHub Pages, deployed from `main`, from
the same project as the desktop build (decided by the owner on 2026-10-17). Anyone can open the page, but nothing
from WZ is ever shipped, hosted or named: the player supplies one import source per import, either a local folder
of v83 `.wz` files, a local `.zip` of them, or a URL they paste themselves (a folder base URL or a `.zip` URL). The
Rust importer, compiled to wasm32, decodes it inside the page and writes the asset cache into the browser storage
behind Godot's `user://`. Nothing proprietary reaches a server we run.

All browser glue lives in a **web shell** (the export's HTML/JS, outside `game/`): the import screen, a Web Worker
running the importer, persistent-storage requests, save backup and the boot-time manifest check. `game/` keeps zero
networking and zero JavaScript: `test_offline.gd` is unchanged, including its `JavaScriptBridge` ban. The web shell
is the only code allowed to make requests, and only for the game bundle itself and the import source the player
named. The importer keeps no network code either: its Rust side reads through a `ReadAt` trait and ships only the
native-file implementation; the browser implementations (`Blob` slices via `FileReaderSync`, HTTP `Range` via
synchronous XHR in the worker) are written in the web shell and injected as host callbacks, so `no_network_deps` and
`no_network_src` still hold. A `.zip` source sits on the same `ReadAt` (central directory, then seek to an entry and
inflate forward), so a zip on a host that serves ranges needs no full download.

The shell and the game talk through files and quitting only. The shell writes into `user://` (the cache, an imported
`save.json`) before starting the engine; the game asks the shell for something (re-import, save export or import) by
writing a request marker into `user://` and quitting, and the shell handles it and restarts the engine.

## Considered options

- **A hard-coded mirror fetched automatically:** rejected. The page would become a public MapleStory asset client
  pointing at infringing copies, the known mirrors are edited (Cosmic's HeavenMS files, no Sound or Effect) or sit
  behind unofficial Google Drive bypasses, and their bandwidth belongs to someone else.
- **Only the desktop `wzimport.exe`, then uploading the cache:** kept for development only; players would need a
  native tool.
- **Glue inside `game/` through `JavaScriptBridge`:** rejected; it would put browser and network-capable code in the
  game and need an exemption in the offline test.
- **A threaded export:** rejected; GitHub Pages can't send the COOP/COEP headers, and the game uses no threads.

## Consequences

- The repo, the site and the docs never name a WZ mirror or source.
- One source per import. Any PKG1 archive with the v83 GMS version hash is accepted, edited or not, as on desktop;
  a missing archive fails with a message naming it. Sources are not mixed.
- When an update grows the manifest, a URL source re-imports incrementally on boot; a folder or zip source asks the
  player to pick it again.
- Web-only behaviour in `game/` sits behind `OS.has_feature("web")`: the import handoff, a bundled fallback font (no
  system fonts in a browser), tab-fitting instead of window settings, no Quit, and save backup through the shell.
  Desktop behaviour doesn't change.
- Browser performance never changes the simulation or balance; shortfalls are fixed in presentation or engine code.
