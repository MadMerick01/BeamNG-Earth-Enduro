# CODEX TASK 001 — BeamngWorld RP investigation and architecture

Investigation date: 22 October 2026 (Australia/Sydney). **Investigation only; architecture awaits designer approval.** No gameplay code, upstream edits or commits were made.

**Recommendation:** an independent Lua mod and Angular UI app are feasible. Geographic resume has a source-confirmed request path, but reliable completion detection requires a version-specific adapter over Earth internals and in-game validation. Do not promise exact bridge/tunnel/altitude restoration or damage-preserving teleportation yet.

Evidence baseline:

- BeamNG.Earth [`bd9c764cb0aa47ae65f1d4998d00c9517988796e`][earth], `VERSION`: `1.5.4-beta`. Read-only investigation clone: `/tmp/beamng-earth-investigation`.
- Its README says testing targeted BeamNG.drive 0.39.4 on Linux/Vulkan; that is upstream's statement, not a runtime test performed here. Some code mentions 0.40 behavior. The initial supported game version must be explicitly selected and tested.
- Official BeamNGpy [`0c7009e2da87019bed5278f7f9e07f242b89469b`][beamngpy] was inspected as secondary evidence of engine capabilities. Its Python API is not the native Lua API and is **not a proposed runtime dependency**.
- “Source-confirmed” below means present in this revision, not guaranteed stable or verified in the game. “Proposed” describes our future code. Native APIs whose exact signatures are not evidenced are explicitly unverified. The official UI documentation URL returned HTTP 403 here; it was not used to assert native API contracts.

## 1. BeamNG.Earth Architecture

### Runtime components and dependencies

| Component | Actual source and responsibilities |
| --- | --- |
| Companion world server | [`server/earthd.py`][earthd], `Server` and `Connection`: downloads/builds geographic data, supplies anchor frames, physics heightmaps and render/road tiles. A localhost connection and shared BeamNG user-folder files are required. |
| Network client | [`mod/beamng_earth/lua/ge/extensions/beamngEarth/net.lua`][net], `update`, `send`, `state`, `isConnected`: nonblocking TCP, `127.0.0.1:47613`. Earth itself owns this connection. |
| Game Engine Lua coordinator | [`mod/beamng_earth/lua/ge/extensions/beamngEarth/core.lua`][core], `onUpdate`, `updateWorld`, `onMessage`: anchor lifecycle, streaming, rebase, player placement and UI. Extension name: `beamngEarth_core`. Protocol 4, accepted far-tile formats 3/4. |
| Coordinates | [`.../beamngEarth/geodesy.lua`][geodesy], `geodeticToEcef`, `ecefToGeodetic`, `newAnchor`, `Anchor:geodeticToEnu`, `Anchor:enuToGeodetic`, `Anchor:transformTo`: pure Lua WGS84 math. Python counterpart: [`server/geodesy.py`][pygeo], `EnuFrame`. |
| Near physics | [`.../beamngEarth/terrain.lua`][terrain], `load`, `swap`, `loadFlat`; [`.../beamngEarth/lattice.lua`][lattice], `configure`, `groundBox`; [`.../beamngEarth/follow.lua`][follow], `target`, `decide`: a moving TerrainBlock on a 2 m sample lattice, with 1024² or 512² samples. |
| Render tiles | [`server/farfield.py`][pyfar], `select`, `swap_groups`; [`.../beamngEarth/farfield.lua`][luafar]: distance-based LOD, hysteresis, optional horizon/screen-space selection and staged swaps. These are distinct from near collision coverage. |
| Roads and solid structures | [`.../beamngEarth/roads.lua`][roads], `update`, `readyAround`, `settledFor`: road, deck, tunnel, sidewalk and building tiles with separately created collision geometry and collision rebuilds. |
| Origin changes | [`.../beamngEarth/rebase.lua`][rebase], `decide`, `moveVehicles`, `updateResetState`; core `commitRebase`, `finishRebase`: rigid transforms of vehicles, terrain, scenery and camera. |
| Existing UI and saved places | [`.../beamngEarth/settings.lua`][settings], [`.../beamngEarth/places.lua`][places], [`.../beamngEarth/hudapps.lua`][hudapps]; Angular apps plus Vue pause/settings/map routes. Saved places are not a player progression save system. |

Paths abbreviated as `.../beamngEarth/` above mean `mod/beamng_earth/lua/ge/extensions/beamngEarth/` throughout this report.

Earth's server requirements are Python 3.10+, NumPy, Pillow >=11, DuckDB >=1.5, fsspec and certifi in `server/requirements.txt`; native acceleration and external data services vary by enabled world features. Earth uses the game engine's Lua environment, LuaSocket and UI facilities. BeamngWorld would need neither a second world server nor additional geographic download services; it consumes the installed Earth runtime.

### Geographic frame and floating origin

Latitude and longitude are degrees; local coordinates are metres. Conversion is **WGS84 geodetic → ECEF → the committed anchor's East-North-Up frame**, with +X east, +Y north, +Z up. The anchor is defined at ellipsoidal height zero. A local Z value is not interchangeable with height above ground or sea level. Earth's `updatePlayer` (`core.lua:869`) calls `st.anchor:enuToGeodetic(veh:getPosition())`, retains latitude/longitude and speed, and discards the returned height.

There are two different world movements:

1. **Terrain-follow:** a new physics block is prepared ahead of the car using position, velocity and measured latency, then committed in the same anchor. Vehicles do not change frame. The collidable widths are 2046 m / 1022 m, rather than the full nominal block extents; use `lattice.groundBox`, not guessed bounds.
2. **Rebase:** the current default threshold is **15,000 m**, with a 300 m prefetch margin (`rebase.lua:20–23`). `Anchor:transformTo` computes `p_new = R*p_old + t`, including rotation. `commitRebase` requests vehicle moves; `finishRebase` changes the rest of the world according to measured physics lag. A transition can temporarily leave sampled state inconsistent. Skip those samples.

The old architecture document describes a cube-sphere tile index and an approximately 8 km threshold. Current executable code instead selects a quadtree in the **anchor's ENU plane** (`server/farfield.py:344`) and defaults to 15 km. Source takes precedence over those older descriptions. Several inline comments and the exported `MOD_VERSION = '0.4.0'` are also stale.

## 2. Confirmed Integration Points (with source file and function references)

| Interface | Evidence | Status and intended use |
| --- | --- | --- |
| `beamngEarth_core.teleport(lat, lon, name, opts)` | [`core.lua:1661`][teleport], `teleportTo` at 1638, `requestAnchor` at 219; advertised in core's console API comments | Source-confirmed, repository-described console interface. `true` means a request was sent, **not that terrain or placement is ready**. `opts.record=false` suppresses recent-place recording; the UI lat/lon and other teleport state still change. No height, heading, vehicle choice or completion callback is accepted. |
| `require('beamngEarth/places').here()` | [`places.lua:435`][here] | Source-confirmed latitude/longitude getter, nil when unavailable. Internally uses core `_state()`. Suitable low-frequency display accessor, with our own freshness/transition checks. Not advertised as a stable cross-mod contract. |
| `beamngEarth_settings.uiMapState()` | [`settings.lua:483`][mapstate] | Source-confirmed structured UI getter: connection, player lat/lon/heading/speed and other map state. UI-specific, includes more work than a mileage sampler needs. |
| `beamngEarth_core.serverHello()`, `banner()`, `serverHealthy()` | [`core.lua:1735`][status], `banner` at 1761, `serverHealthy` at 1141 | Source-confirmed diagnostic capabilities. Server connection/health is not destination collision readiness. `serverHello()` copies the server's last scalar metadata, which can outlive a disconnect. |
| `beamngEarth_core._state()` | [`core.lua:1840`][state] | Explicitly exposed read-only for tools/settings. Returns the actual mutable internal table, not a copy. Snapshot only the fields needed; never modify them or retain mutable state as historical samples. Version-sensitive access. |
| `require('beamngEarth/geodesy')` | [`geodesy.lua:15`][geodesy] | Source-confirmed conversion functions; use the current committed anchor, not a home/base anchor. Internal helper module, so capability checks and version tests are needed. |
| `require('beamngEarth/roads').readyAround(aid,x,y,r)` / `settledFor(aid,x,y)` | [`roads.lua:868`][ready], [`roads.lua:576`][settled] | Source-confirmed internal collision checks, already used by Earth. `readyAround` returns true when roads are disabled; neither function alone proves the correct road layer under the saved vehicle. |
| Mission, extension and frame hooks | [`core.lua:1516`][lifecycle], exports at 1849 | Earth uses `onExtensionLoaded`, `onClientStartMission`, `onClientPostStartMission`, `onClientEndMission`, `onUpdate`, `onPreRender`. These are game lifecycle hooks, **not custom Earth completion events**. Cross-extension order must be tested. |
| Lua → HUD events | [`hudapps.lua:54`][hudapps] `update`, `guihooks.trigger('BeamNGEarthHud', payload)`; [`BeamNGEarthStatus/app.js`][appjs] | Source-confirmed UI bridge. That payload contains display texts, not a structured geographic/streaming contract. BeamngWorld should emit its own event. |

**No dedicated Earth-ready, teleport-completed or rebase-start/end broadcast was found in the inspected core.** `anchor_ready` / `terrain_ready` are messages on Earth's private socket, handled by local `onMessage`; other extensions do not automatically receive them. `status()` returns a `dumps(...)` string, not a table; do not parse it or execute it with `loadstring` as a production data API.

### Proposed communication contract — without modifying Earth

Implement a single adapter module in **our** mod. All Earth access goes through it:

- Resolve the already loaded `beamngEarth_core` safely; do not forcibly load/enable Earth when the player has disabled it. Check the Earth level and player vehicle before requesting movement.
- Check required functions and expected state shapes. For the first prototype support the inspected Earth revision or an explicitly tested release; do not use stale `MOD_VERSION` alone as compatibility evidence. Protocol 4 compatibility does not imply Lua API compatibility.
- Expose our own proposed methods such as `probe()`, `readPose()`, `requestResume(target)` and `pollResume()`. **These are proposed BeamngWorld methods, not existing Earth APIs.**
- Use Earth's exported `teleport` for geographic requests. Read `_state()` and `dropHoldState()` only inside the compatibility adapter for lifecycle/collision gating; use geodesy and road helpers where needed. No wrapper replacement, monkey patch, private socket interception or writes to Earth state.
- Emit **our own** `BeamngWorldState` UI event and internal discontinuity notifications. Never suggest Earth emits these.
- Missing/disabled/incompatible Earth puts BeamngWorld in a visible waiting/unavailable state. Suspend earnings and geographic save updates, preserve the last good save, and leave ordinary Freeroam usable. A present Earth extension with an absent/unhealthy companion is a separate waiting/error state. Avoid request loops.

**Alternative if the designers reject internal access:** retain read-only HUD display through exported UI/places getters, but defer automated reliable resume. Ask upstream for a maintained read-only pose/readiness interface and tokenized teleport lifecycle hooks. That is a proposed upstream collaboration, not an authorized patch in this task. No messages were sent.

## 3. Geographic Save/Resume Feasibility

### What the source establishes

`Connection.prepare_anchor` (`server/earthd.py:2647`) constructs an anchor and its initial physics terrain, then sends `anchor_ready` with `groundZ`, possible tunnel `floorZ`, and terrain files. Client `commitTeleport` (`core.lua:370`) loads that terrain, lifts/stops the active car, reloads collision, commits the new anchor and starts a **two-update placement delay**. `placePlayer` (`core.lua:554`) calls `spawn.safeTeleport` with reset enabled, upright while retaining horizontal heading. If no active vehicle exists, it returns without spawning one.

Road/deck/building collision arrives separately. Tunnel `floorCheck` (`core.lua:565`) waits for `roads.settledFor` and a static-collision ray matching the expected tunnel floor. It can time out after 60 seconds and leave the vehicle above the tunnel. `updateDropHold` (`core.lua:914`) uses block bounds, static rays, road readiness and settling logic for cars dropped away from loaded ground; its timeout paths release the hold. Therefore “hold no longer active” is not by itself success.

A far-away restart is a fresh anchor request, not reuse of the old local XYZ. Earth initially loads flat terrain and automatically requests its selected/default start (`onLevelStart`, `startTeleport`). Our later request can supersede Earth's pending request; its matching request-ID checks discard stale responses. The adapter should first let Earth's automatic startup/random-place selection finish, then issue one resume request. A random-place start may take up to 15 seconds before fallback. Handle reload/reconnect without repeatedly teleporting an already resumed profile.

### Proposed resume state machine

`WAIT_EARTH → WAIT_INITIAL_START → REQUEST_DESTINATION → WAIT_ANCHOR → WAIT_PLACEMENT → VERIFY_SURFACE → ACTIVE`, with explicit failure/retry states. These are our design states, not upstream events.

1. Validate and retain the entire selected save before loading the world. Suppress mileage and geographic autosave during restoration; never overwrite its destination with Earth's temporary default start.
2. Require the Earth level, an active player vehicle, healthy connection/session and a compatible adapter. Let Earth complete its own startup, including pending random selection and placement. In a user-triggered competing teleport, cancel our attempt rather than fighting it.
3. Call `teleport` once; record our target, current session, prior anchor and the request identity observed through the version adapter. A successful return is only acceptance. Scope identities by session/level generation because anchor/request numbers can be reused after restarts.
4. Observe a newly committed target anchor, not merely `st.active`. Require expected session/anchor, no pending teleport, no resync/rebasing/lag probe, completed placement and no pending tunnel placement/drop hold. Detect mismatched or superseded requests. Add a tested settling interval; sampling order relative to physics matters.
5. Validate the actual vehicle's coordinate against the target within a tested metre-scale tolerance, collidable block containment using `lattice.groundBox`, road collision readiness where enabled, and downward `castRayStatic` hits under the vehicle footprint over consecutive physics steps. A ray that hits an old anchor's collider, bridge deck over a tunnel or unrelated surface is insufficient; use anchor/road-settling checks and saved surface context. Visual tiles or zero backlog are not readiness proof. No need to wait for the entire horizon to render.
6. Start mileage from a new baseline only after success. Save the confirmed settled pose; keep the fixed base untouched. On timeout retain the last good save and report the stage/diagnostic reason; do not silently substitute the base or declare success.

**Delayed spawning:** Earth's first-block construction can proceed without a vehicle, but Earth does not queue a later spawn and some ordinary world update paths require `st.player`. Fully withholding the player vehicle until *all* roads/collision are ready is unproven and could stall follow-on streaming. For v0.1 use the existing Freeroam car and Earth's placement system, with progression gated until verification. For later owned-vehicle restoration, validate a staged spawn/freeze approach separately; do not implement repeated manual position holding, which Earth's own notes associate with damage. If a requirement is to prevent the car moving before every target collider is ready, that remains an in-game experiment/blocker, not a confirmed capability.

### Save representation and persistence

Use a proposed user-writable VFS location such as `/settings/beamngWorld/profiles/default/`, separate from mods, Earth's settings and Earth caches. VFS absolute paths are game user-folder paths, not host `/settings`. Earth uses `jsonReadFile`, `jsonWriteFile` in `places.lua:210–319`; `readFile`/`writeFile` preserve bad data before overwrites. `report.lua:173–180` demonstrates `FS:directoryCreate` and `FS:getUserPath`. These establish practical engine usage, not an atomic-write guarantee.

A version-1 save should hold:

- `schemaVersion`, profile ID, monotonically increasing save generation and producer/compatibility metadata.
- `base = {lat, lon}` fixed once per new profile from designer configuration; `resume = {lat, lon, ...}` updated separately. Saving, rebasing and teleporting must never change `base`.
- Balance in integer currency minor units, cumulative legitimate metres, and fractional earning carry so restarts or rounding do not lose/duplicate income. Version the economy configuration separately from the save schema.
- Resume metadata only where validated: ellipsoidal altitude from `enuToGeodetic`, local-surface clearance and geographic heading/surface layer. These are distinguishable values; do not store raw XYZ/quaternion as a portable pose. Keep sufficient numeric precision rather than adopting Earth's rounded bookmark coordinates.

**Latitude/longitude resume is supported by the request interface. Exact full pose is not.** Saved altitude/clearance may help distinguish bridges/tunnels, but Earth can change terrain data and its teleport API accepts only lat/lon. Heading and full pose restoration would require our own post-readiness placement and additional testing. Do not promise reliable “any geographic location” restoration in caves/tunnels, stacked roads, air, deep water, polar data gaps or unsafe terrain before that is resolved.

Proposed write policy: keep dirty state in memory, autosave no more frequently than a configurable interval (initial recommendation 30 seconds), and save explicitly/on best-effort lifecycle exit. Capture balance, mileage, carry and resume as **one** logical snapshot, only when geographic state is trusted. Quit/crash hooks cannot guarantee a final write.

Prefer two alternating generation slots (`save-a.json`, `save-b.json`) with complete schema/range/integrity validation and read-back verification. Write the older/inactive slot while retaining the latest valid one; on load choose the highest complete valid generation. This avoids inventing an atomic rename API. A partial or corrupt slot falls back to the last good slot. Preserve corrupt evidence before starting a new writable profile; missing saves may initialize normally, unsupported future schemas stay untouched/read-only. No automatic downgrade or destructive reset. Explicit migrations produce a new generation and retain the old valid file. Disk-full and permission failures must be visible. Power-loss durability, filesystem flush and any native atomic-rename contract remain unverified; two slots limit damage but cannot guarantee survival of all storage failures.

Use one default profile in v0.1, with a profile-aware schema and sanitized file IDs for future expansion; a profile-management UI would be additional scope.

## 4. Independent HUD Feasibility

**Source-supported and suitable for v0.1.** Earth already packages normal Angular `beamng.apps` directives under `ui/modules/apps/BeamNGEarthStatus/` with `app.json`, `app.js` and `app.png` ([manifest][appjson], [directive][appjs]). `hudapps.update` sends `guihooks.trigger` events every 0.25 seconds when needed; JavaScript listens with `scope.$on` and unsubscribes/cleans timers on destruction. Its periodic mount handshake handles Lua reloads.

Create our own `ui/modules/apps/BeamngWorldHUD/` with unique directive/app names. Show latitude/longitude, legitimate mileage, balance and connection/resume/save-error state from a read-only `BeamngWorldState` payload. Lua remains authoritative; HUD messages must never supply earned distance or balance. Cache a full snapshot so app remount/Lua reload resynchronizes it; throttle to about 4 Hz and never write a save from the HUD update loop.

A persistent **UI app** survives through the player's saved app layout; that is distinct from save persistence. Earth switches the level to app-layout type `beamngEarth` in `onClientPostStartMission` (`core.lua:1557`). Simply shipping an app does not force it into that layout. First prototype recommendation: users add it once through the app editor to their Earth layout. Test restart, level re-entry, cockpit visibility and Lua/UI reload. If designers require automatic initial placement, validate a supported additive app-layout operation first; do not replace Earth's bundled layout or overwrite the player's customization. Vue pause-menu routes are demonstrated by `ui/ui-vue/mods/beamngEarth/index.js`, but are unnecessary for this minimal HUD.

## 5. Vehicle and Mileage APIs

### Evidence and limitations

| Need | Native Lua evidence / candidate | Confidence and limits |
| --- | --- | --- |
| Active player car | `getPlayerVehicle(0)`, `veh:getID()` in `core.updatePlayer`, `rebase.moveVehicles` | Confirmed Earth usage. Nil while switching/loading must be handled. Runtime ID is not a persistent ownership ID. |
| Model identity | `veh:getPath()` in official BeamNGpy [`examples/modInterface/gameEngineCode.lua:11`][pymod] | Official Lua example. Normalization yields the model directory, not the installed configuration. |
| Actual configuration | Candidates `core_vehicle_manager.getVehicleData(id)`, vehicle part-management APIs | Exact native data shape/signatures **not established** by the inspected Earth source. Validate against the installed game. Public BeamNGpy `Vehicle.get_part_config()` and `set_part_config()` document configuration capability; they do not establish those native Lua signatures. |
| Speed and displacement | `veh:getPosition()`, `veh:getVelocity()`, `v:length()` in `core.lua:869` | Confirmed Earth usage; use physical velocity rather than wheel speed. A built-in odometer with the required semantics was not confirmed. |
| Parts and compatible upgrades | Official BeamNGpy [`Vehicle.get_part_config()`][pyparts]: part tree, chosen/suitable/unsuitable names and child slots | Documented **Python** API; native mod access and game-version differences need probing. Compatibility is more than matching arbitrary part filenames; defer shop/upgrade rules. |
| Damage summary | `map.objects[veh:getId()].damage` in [`gps.lua:530`][damage]; official BeamNGpy `Damage` sensor | Confirmed Earth usage of a coarse summary, not a per-component repair price or complete physical damage snapshot. Detailed condition/wear/deformation serialization is unverified. |
| Repair/reset | `spawn.safeTeleport` call in `core.placePlayer` and source comments describing reset; official [`Vehicle.recover()`][pyrecover] documents repair | Reset can repair physical damage; it is not a generic paid-repair transaction. Preserve-money/damage semantics need later tests. An arbitrary `veh:repair()` API has **not** been established. |
| Spawn vehicle | `core_vehicles.spawnNewVehicle(model,{pos,rot,config,autoEnterVehicle})` in [`tools/drive.py:356`][spawn] | Confirmed native callsite in upstream's developer harness; lifecycle/async behavior still needs in-game verification. |
| Replace vehicle | Official BeamNGpy [`VehiclesApi.replace()`][pyreplace]; candidate native `core_vehicles.replaceVehicle` | Replacement capability is publicly documented in Python. Native Lua signature is unverified here. |
| Reset/discontinuity notification | `onVehicleResetted(vid)` in [`tools/drive_driver.lua:432`][reset] | Confirmed event-sink usage. Note spelling: **Resetted**. Normal extension export/order plus other switch/spawn/despawn hooks require target-game checks. Do not assume this catches every external teleport. |

### Proposed legitimate-distance policy

Keep sampling and validation independent of the economy. Sample physical pose and simulation delta after physics, with a tested hook order. Use a consistent `(levelGeneration, sessionId, anchorId, vehicleId)` identity plus a transient sampling epoch. On any transition, pause, time gap, invalid/nonfinite sample, reset/recovery, vehicle change, pending placement or lost readiness: discard the interval and establish a fresh baseline; do not extrapolate missing time.

Compute travelled metres from successive trusted positions, preferably transformed to ECEF through the **matching committed anchor**, so persistent coordinates have a stable meaning. Three-dimensional short ECEF segments preserve grade/bridge height; latitude/longitude-only chords miss vertical travel and sparse samples undercount curves. For v0.1 deliberately discard rebase-boundary intervals even with ECEF conversion; the small undercount is preferable to false rewards from mixed physics/anchor frames. Discarding must span the lag/settling window, not just the frame where `anchorId` changes.

Compare displacement with measured physical velocity and elapsed **simulation** time using configurable noise/acceleration tolerance; reject the whole implausible interval instead of capping and rewarding part of a teleport. Avoid wheel-speed integration, which pays for wheelspin. Add a stationary jitter deadband. Ground/contact telemetry and player-control/AI state are unverified native inputs; if “legitimate driving” requires grounded, manually driven motion, those must be validated before claiming that behavior. Use `dtSim`, not wall time, to avoid pause/time-scale earnings bugs.

Credit only accepted distance once; economy converts metres to configured currency/km and retains fractional carry. Balance and lifetime mileage cannot be trusted to the UI. Rejected intervals log a reason at a bounded rate. Test instant teleports, short relocations, resets, recovery/rewind, restarts, rebase lag, vehicle switches, spins, stationary vibration and frame stalls.

**Limit:** no observation-only distance filter can identify every small external teleport whose displacement/velocity resembles ordinary motion. A strict zero-false-mileage guarantee requires reliable movement/reset events or restricting supported movement tools. Also, Earth includes GPS Autodrive: whether AI driving, towing, falling or airborne motion earns money is a designer policy decision, not something to silently define in code.

## 6. Proposed BeamngWorld Mod Structure

Proposed names and files below do not exist yet. The mod archive should contain `scripts/`, `lua/` and `ui/` at its root; an unpacked install would use the named folder:

```text
beamng_world_rp/
  scripts/beamng_world_rp/modScript.lua
  lua/ge/extensions/beamngWorld/core.lua
  lua/ge/extensions/beamngWorld/earthAdapter.lua
  lua/ge/extensions/beamngWorld/mileage.lua
  lua/ge/extensions/beamngWorld/economy.lua
  lua/ge/extensions/beamngWorld/persistence.lua
  lua/ge/extensions/beamngWorld/config.lua
  lua/ge/extensions/beamngWorld/hud.lua
  lua/ge/extensions/beamngWorld/diagnostics.lua
  ui/modules/apps/BeamngWorldHUD/app.json
  ui/modules/apps/BeamngWorldHUD/app.js
  ui/modules/apps/BeamngWorldHUD/app.png
```

- `modScript.lua`: register only our manual-lifetime extension, following Earth's loader pattern. No modification of Earth startup scripts.
- `core`: lifecycle, active profile and resume state machine; resets sampling epochs and coordinates modules. Keep economy/math separate from engine calls.
- `earthAdapter`: all dependency discovery, capability/version checks, readonly state snapshots, conversions, teleport requests and target-specific readiness checks. The only module aware of Earth internals.
- `mileage`: pure acceptance policy, physical-distance totals and discontinuity handling; no money or filesystem calls.
- `economy`: pure configurable currency/km calculations with integer minor units and fractional carry; no shops in v0.1.
- `persistence`: schema validation/migration, default-profile loading, alternating generation slots, backup/recovery and throttled dirty snapshots. This owns fixed `base` versus mutable `resume` separation.
- `config`: validated defaults/overrides, units, payout and thresholds. User overrides belong under `/settings/beamngWorld/`, not in the installed mod.
- `hud`: publishes/caches read-only UI state and handles mount/reload handshakes; it does not authorize currency changes.
- `diagnostics`: dependency/resume/save errors and rate-limited rejection logs.

Future development checkout additions: `tests/` for pure Lua fixtures and adapter simulations, `docs/` for installation/compatibility/in-game acceptance. Tests and user saves stay outside the distributable mod. No vehicle shop, repair or upgrade module is needed in v0.1. The existing repository name need not change to give the mod its own namespace.

## 7. Step-by-Step v0.1 Implementation Plan

All steps are **proposed and blocked on architecture approval**. Each has an independent acceptance target.

| Step | Work after approval | Acceptance |
| --- | --- | --- |
| 1. Compatibility spike | Select a specific BeamNG/Earth pair; inspect installed native Lua interfaces, probe lifecycle order, telemetry, collision rays and file behavior. No economy yet. | Record actual signatures, missing/disabled/disconnected behavior and reproducible startup traces. Confirm Earth helper sharing is read-only. |
| 2. Independent mod shell | Unique namespace, manual extension lifetime, lifecycle logging and unavailable state. | Installs/uninstalls independently; other levels remain usable; missing Earth causes no exception and no save loss. |
| 3. Pure save/economy foundation | Default-profile schema, fixed base, resume record, validation, payout carry and dual-slot persistence. | Missing/corrupt/newer-version/disk-error/interrupted-slot fixtures; a resume change never changes base; balance/mileage/carry recover as one generation. Verify VFS behavior in-game. |
| 4. Read-only Earth adapter | Safe pose snapshots and explicit transitioning/ready/error statuses. | Rebase/teleport/disconnect/reconnect/level reload fixtures; no direct Earth-state mutations. In-game samples remain coherent around origin shifts. |
| 5. Independent HUD | App manifest/directive, cached payload, mount handshake, 4 Hz update budget. | Coordinates and status match Lua; app survives restart and reload; user layout remains intact. No economy controlled by JavaScript. |
| 6. Mileage and payout | Discontinuity rejection, trusted simulation-time motion, accepted-distance payout and rate config. | Known-distance drives plus no earnings from tested resets/teleports/rebases/wheelspin; agreed error budget and AI/airborne policy. Short-teleport limitations documented. |
| 7. Save/resume orchestration | One-shot destination request and verified completion state machine; startup race/timeout recovery. | Restart near and far away, cold/warm caches, slow data, Earth restart and user superseding a restore. Retain old save on failure; no default-start autosave; no free kilometre reward. |
| 8. Package/acceptance | Zip/unpacked installs, compatibility notes and a repeatable manual test matrix. | Clean game-profile install, save → exit → restart → restore, HUD visible, no upstream changes; record runtime/OS/version and unsupported surfaces. |

For v0.1 use the current Freeroam vehicle unless designers explicitly extend this milestone. The worn starter vehicle, ownership, shops, paid repairs and upgrades remain later milestones. Prototype approval does not silently authorize those features.

### Checks executed during this investigation

Existing upstream tests were run without editing their contents. Native `luajit` was not installed; an isolated `/tmp/beamng-investigation-venv` used **Lupa 2.8's LuaJIT 2.1 runtime**, with `arg[0]` and `dofile` to execute each existing test as its own process. Suite exits were preserved, including the tests' `os.exit` results.

| Existing Lua suite | Passed assertions | Failed |
| --- | ---: | ---: |
| `mod/tests/test_geodesy.lua` | 480 | 0 |
| `mod/tests/test_rebase.lua` | 33 | 0 |
| `mod/tests/test_core_stubbed.lua` | 266 | 0 |
| `mod/tests/test_core_robustness.lua` | 61 | 0 |
| `mod/tests/test_drophold.lua` | 35 | 0 |
| `mod/tests/test_hudapps.lua` | 11 | 0 |
| `mod/tests/test_places.lua` | 152 | 0 |
| `mod/tests/test_roads.lua` | 76 | 0 |
| **Total** | **1,114** | **0** |

Command semantics: from `mod/tests`, use `lupa.luajit21.LuaRuntime()`, set `arg[0]` to the selected upstream test path, and execute `dofile(arg[0])`. Per-suite logs are `/tmp/test_<name>.lua.log` in this investigation instance. Python: from `server`, `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p test_geodesy.py -v`: **4 tests passed**.

These are upstream math/control-flow checks, including engine stubs. They do not exercise a new BeamngWorld adapter, a running Earth server with real geographic downloads, BeamNG's real UI/physics, or an installed mod. No game runtime was supplied or launched here. In-game validation remains required after approval; no claim of gameplay readiness is made. Both reference checkouts remained clean.

## 8. Technical Risks and Open Questions

| Risk | Consequence / response |
| --- | --- |
| No maintained cross-mod readiness contract | `_state`, road helpers and placement fields can change without protocol/version changes. Isolate/pin the adapter and fail visibly on unknown shapes; ask upstream for formal interfaces if internal access is unacceptable. |
| Vehicle reset during teleport | `placePlayer` resets/repairs and zeroes motion. Later damage persistence and paid repairs cannot safely assume Earth teleports preserve damage. Resolve before those milestones. |
| Latitude/longitude lacks surface identity | A bridge, road below it and tunnel can share lat/lon. Earth may choose a different layer and its tunnel logic can time out. Arbitrary-location exact restoration remains unproven. |
| Asynchronous frame/collision transitions | Server “ready,” geometry visible and collision usable occur at different times. Validate current session/anchor, proper surface and multiple physics steps, not a generic loading flag or fixed delay alone. |
| Startup/supersession races | Earth auto-start, random spawn, UI teleport, Lua reload or reconnect can conflict with restore. One attempt identity per profile/level and explicit cancellation are needed. |
| Cold cache/offline data | Earth may be unable to build an unvisited location, or may have terrain while road data is unavailable. Keep the last good save; bounded waits and explicit retry, not silent relocation. |
| Floating-origin/reset artifacts | Raw XYZ distance can turn a 15 km rebase into income; origin rotation also invalidates saved local headings. Use geographic frames and discard transition windows. |
| Incomplete movement events | Small teleports, recovery rewind, towing or AI can resemble legitimate travel. Define policy and supported tools; don't promise tamper-proof mileage in a local single-player mod. |
| User-profile storage failures | Native JSON helpers do not prove atomic/durable commits. Dual-slot recovery, read-back, schema validation and visible write failures are required. |
| HUD layout coexistence | Earth selects its layout; auto-inserting our HUD without replacing user/Earth data needs a supported path. Manual app placement is the conservative v0.1 proposal. |
| Version drift and documentation | `VERSION`, `MOD_VERSION`, comments and architecture docs disagree; official native UI docs were inaccessible here. Pin source and test actual game builds. Official BeamNGpy APIs must not be misrepresented as native Lua APIs. |
| No in-game evidence in this task | Successful stubs cannot prove terrain placement, damage behavior, native filesystem durability, UI persistence or mileage accuracy. A licensed local BeamNG installation with Earth/companion is needed for those checks. |

## 9. Decisions Required from the Designers

1. **Approve the independent architecture and internal-access policy.** Recommendation: a read-only, version-pinned Earth adapter plus exported `teleport`; accept the maintenance burden. If internals are disallowed, defer reliable automatic resume pending upstream APIs.
2. **Select the initial supported game/Earth versions and test platform.** Recommendation: the inspected Earth revision with an explicitly selected BeamNG build; validate Windows/Linux separately rather than infer support from upstream's 0.39.4 Linux results.
3. **Set the fixed base and prototype economics.** Supply approved base latitude/longitude, starting balance, currency display and payout/km. No location, payout or gameplay reward has been chosen in code. Confirm base coordinates stay fixed per profile and how an intentional future base change would migrate old profiles.
4. **Define resume fidelity.** Is initial support for latitude/longitude on a verified safe drivable surface sufficient, or must v0.1 preserve exact bridge/tunnel layer, altitude and heading? The latter is an additional technical acceptance gate; it cannot currently be promised everywhere. Recommendation: fail safely and preserve the save rather than silently relocate.
5. **Define legitimate travel and error tolerance.** Decide AI/Autodrive, towing, airborne/falling motion and reverse travel. Recommendation: physically travelled ground-driving distance, no pay for teleports/resets/rebase intervals, accepting a small measured undercount at rejected intervals. Ground/control telemetry must be verified for the chosen policy.
6. **Confirm v0.1 vehicle scope and HUD onboarding.** Recommendation: current Freeroam vehicle, one default profile, no wear/ownership/shop/repair/upgrade implementation yet; user adds the HUD to the Earth layout once. Exact vehicle/damage restoration and automatic HUD insertion require separate validation/approval.

**Approval gate:** this report is the completed investigation. No prototype implementation or commits should begin until Rowan and ChatGPT review and approve the architecture and resolve the relevant decisions above.

[earth]: https://github.com/TecnaGamer/BeamNG.Earth/tree/bd9c764cb0aa47ae65f1d4998d00c9517988796e
[beamngpy]: https://github.com/BeamNG/BeamNGpy/tree/0c7009e2da87019bed5278f7f9e07f242b89469b
[earthd]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/server/earthd.py
[net]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/net.lua
[core]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/core.lua
[geodesy]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/geodesy.lua#L15
[pygeo]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/server/geodesy.py
[terrain]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/terrain.lua
[lattice]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/lattice.lua
[follow]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/follow.lua
[pyfar]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/server/farfield.py
[luafar]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/farfield.lua
[roads]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/roads.lua
[rebase]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/rebase.lua
[settings]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/settings.lua
[places]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/places.lua
[hudapps]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/hudapps.lua#L54
[teleport]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/core.lua#L1661
[here]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/places.lua#L435
[mapstate]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/settings.lua#L483
[status]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/core.lua#L1735
[state]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/core.lua#L1840
[ready]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/roads.lua#L868
[settled]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/roads.lua#L576
[lifecycle]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/core.lua#L1516
[appjson]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/ui/modules/apps/BeamNGEarthStatus/app.json
[appjs]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/ui/modules/apps/BeamNGEarthStatus/app.js
[pymod]: https://github.com/BeamNG/BeamNGpy/blob/0c7009e2da87019bed5278f7f9e07f242b89469b/examples/modInterface/gameEngineCode.lua#L11
[pyparts]: https://github.com/BeamNG/BeamNGpy/blob/0c7009e2da87019bed5278f7f9e07f242b89469b/src/beamngpy/vehicle/vehicle.py#L568
[damage]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/mod/beamng_earth/lua/ge/extensions/beamngEarth/gps.lua#L530
[pyrecover]: https://github.com/BeamNG/BeamNGpy/blob/0c7009e2da87019bed5278f7f9e07f242b89469b/src/beamngpy/vehicle/vehicle.py#L459
[spawn]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/tools/drive.py#L356
[pyreplace]: https://github.com/BeamNG/BeamNGpy/blob/0c7009e2da87019bed5278f7f9e07f242b89469b/src/beamngpy/api/beamng/vehicles.py#L95
[reset]: https://github.com/TecnaGamer/BeamNG.Earth/blob/bd9c764cb0aa47ae65f1d4998d00c9517988796e/tools/drive_driver.lua#L432
