# BeamNG-Earth Enduro

Independent single-player mod alongside [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth).
**Task 002 prototype:** Enduro HUD, manual geographic arrival verification, and recoverable manual save/resume.
Economy, mileage earning, vehicle ownership/condition, repairs and upgrades are deferred.

This prototype has passed automated logic, filesystem/JSON and HUD lifecycle tests with mocked game APIs.
**Windows BeamNG.drive acceptance is not yet tested.** Location verification is not proof that all terrain/collision geometry is ready.

## Requirements

- A licensed Windows BeamNG.drive installation. The mod follows the 0.39.x conventions inspected in Task 001; use 0.39.4 as the initial acceptance target and record the actual game version tested.
- BeamNG.Earth `1.5.4-beta` at revision `bd9c764cb0aa47ae65f1d4998d00c9517988796e`, with its companion server running and normal road streaming enabled.
- Enduro checks nine relevant Earth Lua source files (including CRLF normalization), required interfaces, and the baseline protocol/hello. Other Earth revisions are blocked pending explicit compatibility work.
- No extra Python server or runtime dependencies are required by **Enduro** inside the game. Development tests use Python, Lupa and Node.js.

## Install on Windows

1. Find the active **BeamNG user folder** using the game launcher's user-folder tools. Use that folder's `current` directory where present; do not assume a fixed AppData path or install into Steam's game binaries.
2. Install and launch the supported Earth version normally, including its companion server. Enduro never enables or teleports Earth for you.
3. Install **one** Enduro copy:
   - ZIP: copy `beamng_earth_enduro-task002.zip` from the generated `dist` directory to `<user folder>/mods/`.
   - Unpacked: copy this repository's `mod/beamng_earth_enduro/` directory to `<user folder>/mods/unpacked/beamng_earth_enduro/`.
4. Create `<user folder>/settings/beamngEarthEnduro/`. Copy `config.example.json` from the Enduro mod/ZIP into that directory and rename it `config.json`.
5. Set `base.latitude` and `base.longitude` to your designers' approved WGS84 coordinates. The shipped values are intentionally null. No permanent base has been selected.
6. Enable Enduro in the Mod Manager, load Earth Freeroam, and use **UI Apps → Add App → Enduro HUD**. Move/resize it as desired and keep it in your Earth layout. Enduro never replaces the layout.
7. Choose **Reload Enduro** after editing configuration, or reload the extension/restart the game. Automatic file-change handling is included but the button is the explicit refresh path.

The ZIP has `scripts/`, `lua/` and `ui/` directly at its root. Do not put the ZIP in an extra wrapper folder. Do not install both ZIP and unpacked copies.

## Configure

`<user folder>/settings/beamngEarthEnduro/config.json` corresponds to the game's VFS path `/settings/beamngEarthEnduro/config.json`:

```json
{
  "base": { "latitude": null, "longitude": null },
  "resumeRadiusMetres": 50,
  "stabilitySeconds": 3
}
```

Replace both null values with numeric approved coordinates before playing. Latitude must be -90..90 and longitude -180..180. The radius supports 1..1000 metres; stability supports 1..60 seconds. Omitted radius/interval values default to 50 m / 3 s. Invalid values block activation and saving. Configuration is not generated or overwritten automatically.

An existing profile retains its original base even when the configuration changes. For a new profile, the base becomes fixed after the first successful arrival verification, including across configuration reloads in that running instance. An unsaved profile does not survive exiting the game. Back up existing profile files before intentionally starting a different profile; there is no reset/delete button in this prototype.

## Start, save and resume

1. With no save, the HUD shows **START LOCATION REQUIRED**, the base coordinates and geographic distance when available.
2. Copy the latitude and longitude fields individually and use **Earth's own teleport interface** to go there. Enduro never submits the teleport.
3. Enter an active vehicle, let Earth settle, and remain within the configured radius for the full stability interval. Only then does the HUD show **LOCATION VERIFIED — READY TO CONTINUE**.
4. Drive elsewhere. The initial radius is an arrival gate, not a boundary restricting subsequent travel. Click **Save** to keep the current valid geographic position. No periodic or shutdown autosave occurs, and no money or mileage is generated.
5. Restart the game. The HUD shows **RESUME REQUIRED**, the saved coordinates and distance. Manually teleport using Earth, then complete the same verification before Save unlocks again.

The Save button also rechecks live data at click time. It cannot save during a known transition or with missing/invalid coordinates. Vehicle model is saved when available. Configuration, altitude and heading are omitted because a reliable native retrieval contract for those values has not been established for this task. Enduro does not spawn or restore vehicles.

Temporary loss of Earth data, reset/recovery, vehicle/anchor change or pausing suspends an already verified session. When data returns, remain at a stable live location for the interval again; you do not have to return to the original base/save after every routine streaming interruption. This recovery verification never changes the saved target or base. Every return to READY establishes a fresh baseline. A mission start, extension reload or **Reload Enduro** starts the required base/resume gate again.

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

The archive is generated at `dist/beamng_earth_enduro-task002.zip`. Packaging is deterministic and includes installation, architecture and acceptance documentation; it does not package user settings or saves. To check source identity against a separate read-only Earth checkout:

```sh
.venv\Scripts\python.exe tools/check_earth_compatibility.py C:\path\to\BeamNG.Earth
```

See [architecture and state transitions](docs/TASK-002-architecture.md) and the [test results and Windows checklist](docs/TASK-002-testing.md). Task 001 remains an unchanged historical investigation record. Task 003 requires designer review and separate authorization.
