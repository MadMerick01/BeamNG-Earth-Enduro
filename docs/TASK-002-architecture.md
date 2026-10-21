# Task 002 architecture — BeamNG-Earth Enduro

Scope: independent mod, HUD, fixed base, geographic verification and manual save/resume only. No teleport command, mileage accumulator, currency payout, vehicle shop/repair/upgrade, vehicle condition persistence or multiplayer was added.

## Files and loading

Distributable root: `mod/beamng_earth_enduro/`. Its `scripts/beamngEarthEnduro/modScript.lua` registers `beamngEarthEnduro_core` with manual unload lifetime, matching the inspected game/Earth mod-manager convention. No direct `extensions.load` is needed in the script. Game mission/frame/reset/file-change hooks are exported by `lua/ge/extensions/beamngEarthEnduro/core.lua`.

| File in `lua/ge/extensions/beamngEarthEnduro/` | Responsibility |
| --- | --- |
| `core.lua` | Explicit state controller, session authorization, profile creation, manual-save gate, lifecycle entry points and native JSON/filesystem bindings. |
| `earthAdapter.lua` | All Earth discovery, capability checking, read-only snapshots and transient/loading checks. No socket or state mutation; no teleport call. |
| `compatibility.lua` | Fingerprints and metadata for the inspected upstream revision; Windows CRLF normalization. |
| `location.lua` | Finite coordinate validation, haversine metres and uninterrupted proximity timer. No local-world distance is used for arrival. |
| `persistence.lua` | Profile schema, validation, detached snapshots, alternating generations and read-back verification. |
| `config.lua` | Built-in permanent default base and optional user override with bounds. A present invalid override fails closed. |
| `hud.lua` | Mount heartbeat, changed snapshots, 4 Hz ceiling and periodic UI resynchronization. |
| `diagnostics.lua` | Namespaced, change-driven logging. No per-frame repeated status logs. |

Additional files: the Angular app at `ui/modules/apps/BeamNGEarthEnduroHUD/{app.json,app.js,app.html,app.png}` and `config.example.json`. The extra `compatibility.lua` and `app.html` keep source identity and UI markup separate from orchestration. User configuration/save files are outside the mod. Tests/tools are outside the game package.

## Compatibility and Earth interfaces

Initial source baseline: upstream `1.5.4-beta`, commit `bd9c764cb0aa47ae65f1d4998d00c9517988796e`. Target initial acceptance platform: Windows, using the inspected 0.39.x loading/UI conventions (initial candidate 0.39.4). No Windows game build has been executed here.

Both the core's `MOD_VERSION` and the server's reported version are stale **`0.4.0`** at this revision. The server value is defined in `server/netfetch.py:57` and sent by `Connection.dispatch` in `server/earthd.py`. Enduro therefore does not treat that string as proof of `1.5.4-beta` compatibility.

On initial detection/reload it reads the VFS source text of `core`, `places`, `geodesy`, `net`, `lattice`, `roads`, `drophold`, `edgeguard` and `rebase`, normalizes CRLF, and checks byte lengths/Adler-32 values captured from the inspected revision. This is a conservative source-identity check, not a cryptographic/security signature or a fingerprint of the whole upstream repository. It deliberately rejects modifications to those files; approved future support requires inspecting/testing and updating the manifest, not disabling the check. The server is checked for the baseline protocol 4 / reported `0.4.0` hello; the exact companion revision cannot be proved from those metadata alone.

Only `earthAdapter.lua` touches Earth at runtime:

- Existing `beamngEarth_core` global; never loads/enables it.
- `core._state()` for narrowly selected read-only session/anchor/block/player/clock and transition fields.
- `core.serverHello()`, `core.serverHealthy()`, `core.dropHoldState()`.
- Already-loaded `places.here()` as a geographic reference.
- The committed anchor's `enuToGeodetic()` on the live active-vehicle position. The last pose from `places.here()` must agree within 25 m; an inconsistent/stale frame is rejected. This avoids saving the cached pre-physics position.
- Already-loaded `net.isConnected()`, `lattice.groundBox()`, `roads.readyAround()` and `roads.settledFor()`.
- Native `getPlayerVehicle(0)`, `getID()`, `getPosition()` and optional `getPath()` for active vehicle identity/pose. These are engine calls, not geographic substitutes.

No calls to Earth's `teleport`, no reads/parsing of `status()`'s dump string, no `net.send`, no monkey patches and no changes to Earth source/state. Helper tables and `_state()` are not stored as mutable historical samples. Filesystem changes under Earth's extension directory invalidate the compatibility cache; Reload Enduro also rechecks it.

Trust checks reject missing/mismatched sessions, missing anchor/block/vehicle, invalid coordinates, stale Earth clocks, pending geographic requests/random starts, rebase/physics lag, delayed placement, tunnel placement, drop holds, active guard holds, known teleport-loading windows, unhealthy world follow, paused simulation and insufficient current-block margin. Nearby road readiness/settling is checked conservatively. Ordinary safe terrain-follow prefetch is not itself an origin transition; the current block must still cover the car, the server must remain healthy and nearby road checks must pass. A frozen clock is rejected after 0.5 seconds. Normal guard modes `off`, `clear`, `air` are accepted; this prototype does not prove vehicle ground contact.

**These checks do not prove full collision readiness.** No invented completion event is used, no downwards collision ray is presented as an arrival guarantee, and no full horizon backlog is awaited. Road helpers can be conservative/global, and a server with roads disabled without matching client settings may remain waiting. Default Earth road streaming is the initial supported configuration. There is no timeout that unlocks on untrusted coordinates.

## Location verification and explicit states

Geographic distance uses haversine on valid WGS84 latitude/longitude with the IUGG mean Earth radius (6,371,008.8 m). This spherical approximation is appropriate for the default 50 m proximity gate; it is not an ellipsoidal survey-distance solver. Antimeridian and polar cases are covered. Latitudes/longitudes are never interpreted as BeamNG XYZ.

Every continuous valid post-physics sample must stay within the radius for the configured interval (50 m / 3 s by default). The first sample starts at zero elapsed time. Wall-clock frame deltas only count while simulation is running; invalid/paused samples, epoch changes or frame gaps over one second reset the timer. The epoch combines server session, anchor and active vehicle IDs. No single reading or request return value unlocks anything.

| State | Entry / exit |
| --- | --- |
| `CONFIG_REQUIRED` | A present override is unset/invalid/unreadable, or its existence cannot be checked. No profile initialization or writes. Valid configuration plus reload returns to the start/resume gate. Missing override files use built-in defaults. |
| `EARTH_UNAVAILABLE` | Missing/unsupported/disconnected Earth, stale/invalid/transitioning data, no vehicle or paused simulation. Timer/baseline reset. Fresh compatible data returns to the applicable verification flow. |
| `START_LOCATION_REQUIRED` | No saved profile. Immutable target is the configured base (or an already-created unsaved profile's original base in that running instance). No profile is created outside it. |
| `RESUME_REQUIRED` | Loaded valid profile. Immutable target is its saved resume coordinates; arriving at the base instead does not unlock it. |
| `VERIFYING_LOCATION` | Continuous trustworthy samples inside the radius. Any interruption resets timing. Completion initializes a new profile in memory if needed and enters READY. |
| `READY` | Only state permitting manual Save and reserving authorization for future progression. Driving away from the initial target is allowed. Data/identity loss suspends it immediately. |
| `ERROR` | Invalid/unsupported/ambiguous save or uncertain write/internal error. No new writes until explicit reload/recovery. No automatic fallback creation over existing bad files. |

After initial arrival, session authorization is remembered only for that running mission/controller. A temporary interruption clears the baseline and captures a **separate transient recovery target** at the first trustworthy live position. Remaining within its radius for the stability interval returns to READY. Leaving that recovery radius restarts at the new live position; stopping briefly may be necessary. This does not replace/mutate the original saved target, profile base or disk resume. A mission start, extension reload or Reload Enduro reselects the required start/resume target and drops authorization. Every READY entry establishes a new baseline; no distance is accumulated.

Reset hooks impose an additional 0.5-second quiet period. A Save click re-reads the adapter, requires the verified epoch and compares against the latest trusted baseline; a new transition, invalid pose or unobserved jump over 25 m blocks the write and restarts verification. The backend ignores the HUD's Save-enable value as authorization.

## Persistence

If `/settings/beamngEarthEnduro/config.json` does not exist, the built-in default is latitude **-33.60147222**, longitude **150.82288889**, radius 50 m and stability three seconds. A present override is validated and takes precedence; invalid/unreadable overrides fail closed without replacement. Loading defaults never creates a user configuration file. Existing profiles keep their original base even with no override file or a different built-in default. Manual resume and save storage are unchanged.

VFS directory: `/settings/beamngEarthEnduro/`. Profile: `default`; schema: 1. Two files: `save-a.json`, `save-b.json`. Saves contain schema/profile/generation, fixed base, mutable resume, placeholder progression and available vehicle model/configuration strings. New progression fields are zero and never incremented. Optional altitude/heading are validated on load but not produced from unverified APIs; old pose metadata is not carried to a newly saved position where it would be stale.

Configuration loads and save loads perform zero writes. A new verified profile is in memory until Save. The first save writes generation 1; later saves alternate slots and increase the generation. Before writing, coordinates and fields are validated into a detached known schema. After writing, Enduro reads and validates the file and checks the complete normalized record. The previously active slot is not overwritten. Save success updates in-memory persisted state only after read-back success; an uncertain write locks further saves until reload rescans the files.

Loading selects the highest valid generation. One corrupt slot yields recovery feedback and retains the good slot. Two bad slots, conflicting records with equal generations, unknown schemas or unreadable storage block profile creation/writes. An unknown schema in either slot prevents destructive rollback to the other. No native atomic rename/flush guarantee is assumed. Two slots do not provide indefinite history, external writer synchronization, tamper protection or guaranteed power-loss durability.

The original base is copied on first verified creation and is never derived from later vehicle/resume positions. A changed config does not rewrite a saved profile's base. A newly created but not yet saved base is also retained across config reloads in that instance; exiting without saving abandons that unsaved profile. Reload Enduro discards unsaved location changes and requires arrival again. No shutdown/periodic autosave exists.

## HUD and diagnostics

App ID `BeamNGEarthEnduroHUD`; UI name `Enduro HUD`; directive `beamngEarthEnduroHud`. Lua publishes `BeamNGEarthEnduroState`. The app sends fixed commands for `uiMounted`, `save` and `reload`, never dynamic coordinate/code or balance values. Coordinates use selectable read-only inputs. Angular interpolation is used for text, without HTML injection.

Mount heartbeats renew a five-second lease every three seconds; publisher updates are limited to 4 Hz and full snapshots repeat every two seconds. JS disables the displayed Save state when the Lua bridge has not responded for more than six seconds. Destruction clears the timer and notifies unmount. Lua remains authoritative. Layout persistence and UI styling in the real game still require acceptance testing; Enduro does not replace layouts.

Logs use tag `beamngEarthEnduro` and record extension/UI loading, config/save decisions, compatibility/status changes, target selection, verification and manual save outcomes. Exact source/schema/storage details remain in logs; HUD errors are player-facing explanations.
