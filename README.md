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

1. [Download `beamng_earth_enduro-task002-ready.zip`](https://github.com/MadMerick01/BeamNG-Earth-Enduro/raw/refs/heads/task002-ready-download/beamng_earth_enduro-task002-ready.zip).
2. Copy that single ZIP into your active **BeamNG user folder's `mods` directory**. Use the game launcher's user-folder tools to locate it; do not put the ZIP in Steam's game binaries. **Do not extract it.** Remove/disable an older Enduro mod copy to avoid duplicate extensions; keep your user settings and save files.
3. With the supported Earth mod and its companion running separately, enable Enduro, load Earth Freeroam, and use **UI Apps → Add App → Enduro HUD**. Move/resize it as desired. Enduro never replaces the layout.
4. The HUD shows **START LOCATION REQUIRED** and the default base **`-33.60147222, 150.82288889`** for a new profile. Use Earth's teleport interface to go there manually. After 50 m / three continuous valid seconds, Enduro enters READY. An existing profile instead follows its unchanged manual-resume flow.

No JSON edits, extraction, Python, Node.js or command-line commands are needed to install or play Enduro. The ZIP has `scripts/`, `lua/` and `ui/` directly at its root. Enduro remains independent of Earth. ZIPs are hosted on a separate download-only branch, not committed to the implementation source tree.

## Default base and optional advanced configuration

The permanent built-in default is **33°36'05.3"S 150°49'22.4"E**, decimal **latitude `-33.60147222`, longitude `150.82288889`**. It is used automatically when no user configuration exists. No settings files are created on load, and no existing configuration or saved profile is overwritten.

Optional overrides remain available at `<user folder>/settings/beamngEarthEnduro/config.json` (VFS `/settings/beamngEarthEnduro/config.json`). Only users who want an override need to copy/edit the included `config.example.json`:

```json
{
  "base": { "latitude": -33.60147222, "longitude": 150.82288889 },
  "resumeRadiusMetres": 50,
  "stabilitySeconds": 3
}
```

Latitude must be -90..90 and longitude -180..180. The radius supports 1..1000 metres; stability supports 1..60 seconds. Omitted radius/interval values default to 50 m / 3 s. A present but invalid/unreadable override blocks activation and saving rather than being silently replaced by defaults. Choose **Reload Enduro** after changing an override; file-change handling is also included.

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

The archive is generated at `dist/beamng_earth_enduro-task002-ready.zip`. Packaging is deterministic and includes installation, architecture and acceptance documentation; it does not package user settings, saves or development dependencies. The Python/Node commands above are for developers rebuilding/testing the mod, not for players installing the supplied ZIP. Developers can alternatively copy `mod/beamng_earth_enduro/` into the user's `mods/unpacked/beamng_earth_enduro/`; do not install both copies. To check source identity against a separate read-only Earth checkout:

```sh
.venv\Scripts\python.exe tools/check_earth_compatibility.py C:\path\to\BeamNG.Earth
```

See [architecture and state transitions](docs/TASK-002-architecture.md) and the [test results and Windows checklist](docs/TASK-002-testing.md). Task 001 remains an unchanged historical investigation record. Task 003 requires designer review and separate authorization.
