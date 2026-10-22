# BeamNG-Earth Enduro

Independent single-player mod alongside [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth).
**Task 004 prototype:** Enduro HUD, a simple coordinate arrival check, recoverable manual save/resume and mileage tracking.
Economy, vehicle ownership/condition, repairs and upgrades are deferred.

This prototype has passed automated logic, filesystem/JSON and HUD lifecycle tests with mocked game APIs.
**Windows BeamNG.drive acceptance is not yet tested.** The only arrival check is that the player vehicle is within the radius of the target coordinates; Enduro does not wait for Earth's terrain, roads or streaming to finish.

## Requirements

- A licensed Windows BeamNG.drive installation. The mod follows the 0.39.x conventions inspected in Task 001; use 0.39.4 as the initial acceptance target and record the actual game version tested.
- Any BeamNG.Earth version, with its companion server running. Enduro is not tied to an Earth version: it reads the vehicle position from the first of these that works — Earth's anchor `enuToGeodetic()` on the live vehicle position, Earth's recorded player position, or `places.here()` — so an Earth update only breaks Enduro if all three change. Every Earth release from `v1.4.5-preview` to `v1.5.5-beta` has been checked with `tools/check_earth_versions.py`.
- No extra Python server or runtime dependencies are required by **Enduro** inside the game. Development tests use Python, Lupa and Node.js.

## Install on Windows

1. [Download `beamng_earth_enduro-task002-ready.zip`](https://github.com/MadMerick01/BeamNG-Earth-Enduro/raw/refs/heads/task002-ready-download/beamng_earth_enduro-task002-ready.zip).
2. Copy that single ZIP into your active **BeamNG user folder's `mods` directory**. Use the game launcher's user-folder tools to locate it; do not put the ZIP in Steam's game binaries. **Do not extract it.** Remove/disable an older Enduro mod copy to avoid duplicate extensions; keep your user settings and save files.
3. With the supported Earth mod and its companion running separately, enable Enduro, load Earth Freeroam, and use **UI Apps → Add App → Enduro HUD**. Move/resize it as desired. Enduro never replaces the layout.
4. The HUD shows **START LOCATION REQUIRED** and the default base **`-33.60147222, 150.82288889`** for a new profile. Use Earth's teleport interface to go there manually. As soon as your vehicle is within 50 m, Enduro enters READY. An existing profile instead follows its unchanged manual-resume flow.

No JSON edits, extraction, Python, Node.js or command-line commands are needed to install or play Enduro. The ZIP has `scripts/`, `lua/` and `ui/` directly at its root. Enduro remains independent of Earth. ZIPs are hosted on a separate download-only branch, not committed to the implementation source tree.

## Default base and optional advanced configuration

The permanent built-in default is **33°36'05.3"S 150°49'22.4"E**, decimal **latitude `-33.60147222`, longitude `150.82288889`**. It is used automatically when no user configuration exists. No settings files are created on load, and no existing configuration or saved profile is overwritten.

Optional overrides remain available at `<user folder>/settings/beamngEarthEnduro/config.json` (VFS `/settings/beamngEarthEnduro/config.json`). Only users who want an override need to copy/edit the included `config.example.json`:

```json
{
  "base": { "latitude": -33.60147222, "longitude": 150.82288889 },
  "resumeRadiusMetres": 50
}
```

Latitude must be -90..90 and longitude -180..180. The radius supports 1..1000 metres and defaults to 50 m when omitted. A legacy `stabilitySeconds` value is ignored. A present but invalid/unreadable override blocks activation and saving rather than being silently replaced by defaults. Choose **Reload Enduro** after changing an override; file-change handling is also included.

An existing profile retains its original base even when the configuration changes. For a new profile, the base becomes fixed after the first successful arrival verification, including across configuration reloads in that running instance. An unsaved profile does not survive exiting the game. Back up existing profile files before intentionally starting a different profile; there is no reset/delete button in this prototype.

## Start, save and resume

1. With no save, the HUD shows **START LOCATION REQUIRED**, the base coordinates and geographic distance when available.
2. Copy the latitude and longitude fields individually and use **Earth's own teleport interface** to go there. Enduro never submits the teleport.
3. Enter an active vehicle. As soon as it is within the configured radius of the target coordinates, the HUD shows **LOCATION VERIFIED — READY TO CONTINUE**.
4. Drive elsewhere. The initial radius is an arrival gate, not a boundary restricting subsequent travel. Click **Save** to keep the current valid geographic position. No periodic or shutdown autosave occurs, and no money is generated.

   While READY, the HUD's **Mileage** counts the distance your vehicle covers between readings. Jumps faster than 150 m/s (540 km/h), such as teleports, are not counted, and nothing is counted while the vehicle position is unavailable. Mileage driven since the last Save is shown as *unsaved*; it is stored by **Save** and lost if you exit or choose **Reload Enduro** without saving.
5. Restart the game. The HUD shows **RESUME REQUIRED**, the saved coordinates and distance. Manually teleport using Earth; Save unlocks again once the vehicle is within the radius.

The Save button reads the vehicle position again at click time and saves that. It cannot save with no vehicle or invalid coordinates. Vehicle model is saved when available. Configuration, altitude and heading are omitted because a reliable native retrieval contract for those values has not been established for this task. Enduro does not spawn or restore vehicles.

If the vehicle position is temporarily unavailable (no vehicle, Earth not running), an arrived session shows EARTH UNAVAILABLE and returns to READY wherever the vehicle is as soon as a position is available again. This never changes the saved target or base. A mission start, extension reload or **Reload Enduro** starts the required base/resume gate again.

## Save files and recovery

Enduro stores schema-1 profile `default` in `/settings/beamngEarthEnduro/save-a.json` and `save-b.json`. It alternates increasing generations, preserving the previously active slot, and reports success only after read-back validation. New profiles exist in memory until the first manual Save.

- One damaged slot: the highest remaining valid generation is loaded, with recovery feedback.
- Both slots invalid, conflicting equal generations, unknown schema or storage access failure: saving stays locked; files are not silently replaced with a new profile.
- A failed or uncertain write enters ERROR. The previous active slot remains intact. Fix the storage issue, then choose **Reload Enduro** to rescan both slots and reverify arrival before retrying.
- To recover manually, exit the game and back up the entire Enduro settings directory first. Restore a known-good pair of files, or move both invalid save files aside if deliberately starting over. Keep `config.json`. Reload/restart afterward.

Two generations are recoverable storage, not a guarantee against power loss, external simultaneous edits, disk failure or malicious tampering. Save files contain geographic locations; treat them as your user data. Uninstalling the mod does not require deleting settings/saves.

## Development and packaging

From the repository root, with Python 3.10+ and Node.js installed:

```sh
python -m venv .venv
# Windows PowerShell:
.venv\Scripts\python.exe -m pip install -r tests/requirements.txt
.venv\Scripts\python.exe tests/run.py
.venv\Scripts\python.exe tools/package.py
```

On Linux/macOS use `.venv/bin/python` in place of `.venv\Scripts\python.exe`. Lupa is pinned and supplies LuaJIT 2.1 for tests; an installed native `luajit` can run the Lua suites instead, but the Python bridge tests still require Lupa. Python/Lupa/Node are not shipped in the mod.

The archive is generated at `dist/beamng_earth_enduro-task002-ready.zip`. Packaging is deterministic and includes installation, architecture and acceptance documentation; it does not package user settings, saves or development dependencies. The Python/Node commands above are for developers rebuilding/testing the mod, not for players installing the supplied ZIP. Developers can alternatively copy `mod/beamng_earth_enduro/` into the user's `mods/unpacked/beamng_earth_enduro/`; do not install both copies.

After a BeamNG.Earth update, check that Enduro can still read positions from it (reads a local git clone of Earth; changes nothing):

```sh
git clone https://github.com/TecnaGamer/BeamNG.Earth.git
.venv\Scripts\python.exe tools/check_earth_versions.py BeamNG.Earth
```

See [Task 004 mileage tracking](docs/TASK-004-mileage.md) and the [Task 003 simplified arrival check](docs/TASK-003-simplified-checks.md). The [Task 002 architecture](docs/TASK-002-architecture.md) and [Task 002 testing](docs/TASK-002-testing.md) documents describe the earlier, stricter checks and are kept as historical records, as is Task 001.
