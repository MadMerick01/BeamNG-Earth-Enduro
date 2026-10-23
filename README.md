# BeamNG-Earth Enduro

Independent single-player mod alongside [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth).
**Task 004 prototype:** Enduro HUD, simple manual save of the vehicle's current location anywhere, mileage tracking, money earned by driving, paid vehicle repairs and paid part changes.
Vehicle ownership and buying vehicles are deferred.

This prototype has passed automated logic, filesystem/JSON and HUD lifecycle tests with mocked game APIs.
**Windows BeamNG.drive acceptance is not yet tested.** Enduro only needs a valid vehicle position from Earth; it does not wait for Earth's terrain, roads or streaming to finish.

## Requirements

- A licensed Windows BeamNG.drive installation. The mod follows the 0.39.x conventions inspected in Task 001; use 0.39.4 as the initial acceptance target and record the actual game version tested.
- Any BeamNG.Earth version, with its companion server running. Enduro is not tied to an Earth version: it reads the vehicle position from the first of these that works — Earth's anchor `enuToGeodetic()` on the live vehicle position, Earth's recorded player position, or `places.here()` — so an Earth update only breaks Enduro if all three change. Every Earth release from `v1.4.5-preview` to `v1.5.5-beta` has been checked with `tools/check_earth_versions.py`.
- No extra Python server or runtime dependencies are required by **Enduro** inside the game. Development tests use Python, Lupa and Node.js.

## Install on Windows

1. [Download the latest `beamng_earth_enduro.zip`](https://github.com/MadMerick01/BeamNG-Earth-Enduro/releases/latest/download/beamng_earth_enduro.zip). Older builds are listed on the [Releases page](https://github.com/MadMerick01/BeamNG-Earth-Enduro/releases).
2. Copy that single ZIP into your active **BeamNG user folder's `mods` directory**. Use the game launcher's user-folder tools to locate it; do not put the ZIP in Steam's game binaries. **Do not extract it.** Remove/disable an older Enduro mod copy to avoid duplicate extensions; keep your user settings and save files.
3. With the supported Earth mod and its companion running separately, enable Enduro, load Earth Freeroam, and use **UI Apps → Add App → Enduro HUD**. Move/resize it as desired. Enduro never replaces the layout.
4. The HUD shows the default base **`-33.60147222, 150.82288889`** for a new profile. As soon as Earth reports a valid position for your vehicle, wherever it is, Enduro enters READY and Save is available.

No JSON edits, extraction, Python, Node.js or command-line commands are needed to install or play Enduro. The ZIP has `scripts/`, `lua/` and `ui/` directly at its root. Enduro remains independent of Earth. ZIPs are published as GitHub Releases, not committed to the implementation source tree.

## Default base and optional advanced configuration

The permanent built-in default is **33°36'05.3"S 150°49'22.4"E**, decimal **latitude `-33.60147222`, longitude `150.82288889`**. It is used automatically when no user configuration exists. No settings files are created on load, and no existing configuration or saved profile is overwritten.

Optional overrides remain available at `<user folder>/settings/beamngEarthEnduro/config.json` (VFS `/settings/beamngEarthEnduro/config.json`). Only users who want an override need to copy/edit the included `config.example.json`:

```json
{
  "base": { "latitude": -33.60147222, "longitude": 150.82288889 },
  "resumeRadiusMetres": 50
}
```

Latitude must be -90..90 and longitude -180..180. `resumeRadiusMetres` (1..1000, default 50) is still validated but no longer used, since Save no longer requires arriving at a location first. A legacy `stabilitySeconds` value is ignored. A present but invalid/unreadable override blocks activation and saving rather than being silently replaced by defaults. Choose **Reload Enduro** after changing an override; file-change handling is also included.

An existing profile retains its original base even when the configuration changes. For a new profile, the base becomes fixed when the session first gets a valid vehicle position, including across configuration reloads in that running instance. An unsaved profile does not survive exiting the game. Back up existing profile files before intentionally starting a different profile; there is no reset/delete button in this prototype.

## Start, save and resume

1. Load Earth Freeroam and enter an active vehicle. As soon as Earth reports a valid position, the HUD shows **READY** and Save is available, wherever the vehicle is.

   **Starter car:** on a fresh start (no save yet, or both save files unreadable) Enduro swaps that first vehicle, where it stands, for the **WorldIronManEnduro Starter**, a 1950s Burnside coupe with a stock inline-six. Its parts count as paid for; upgrade it from there with **Parts** and keep it running with **Repair**. This happens once per game session, so **Reload Enduro** before your first Save does not swap the car again. When a save is loaded, Enduro leaves your vehicle alone. The config also appears under Burnside in the game's vehicle selector, so you can spawn it yourself.
2. Drive anywhere. Click **Save** to keep the vehicle's current valid geographic position. No periodic or shutdown autosave occurs.

   While READY, the HUD's **Mileage** counts the distance your vehicle covers between readings. Jumps faster than 150 m/s (540 km/h), such as teleports, are not counted, and nothing is counted while the vehicle position is unavailable. Mileage driven since the last Save is shown as *unsaved*; it is stored by **Save** and lost if you exit or choose **Reload Enduro** without saving.

   The HUD's **Money** goes up by **$50 for every kilometre** counted as mileage, so teleports earn nothing. The balance is whole dollars; part-dollars carry over while you keep driving. For testing, the **+$10000 (test)** button adds $10,000 straight away. Like mileage, money earned since the last Save is shown as *unsaved*, kept by **Save** and lost on exit or **Reload Enduro** without saving.

   **Repair:** press **Get repair quote** to price the damage to the vehicle you are in. The price comes from the vehicle's overall damage: $100 call-out plus $0.50 per damage point, nothing under 50 points (a scratch), capped at $20,000. Press **Repair** to pay it; the vehicle is respawned where it stands with its current parts, tuning and paint, so every part is new. If you cannot afford it, nothing is charged or repaired and the HUD says how much more you need. If the damage changes or you switch vehicle after the quote, Repair re-quotes instead of charging. Money spent is shown as *spent, unsaved* until you **Save**.

   **Parts:** change parts in BeamNG's own parts menu as usual. The parts the vehicle had when you got in count as paid for. After each change the HUD's **Parts** section lists the parts added and taken off and the bill. A part costs its value from the game's part files, or $250 if it has none; parts taken off in the same change are traded in for 30% of their value, which lowers the bill but never pays out. Press **Buy** to pay and keep the parts (it is disabled when you cannot afford it), or **Revert** to put the paid parts back; tuning and paint are free and kept either way. Trying parts on and swapping back costs nothing. If you drive more than 25 m without paying, the paid parts are put back automatically. A part change respawns the vehicle and mends all damage, so when the vehicle was damaged the repair price is added to the bill, and it is still charged on Revert or driving off, as far as your balance allows. Repair is locked while a parts bill is open. Switching to a different vehicle takes its parts as paid for, since buying vehicles is not part of Enduro yet.
3. Restart the game. The HUD shows your last saved coordinates and your distance from them. To continue from there, copy them and use **Earth's own teleport interface**; Enduro never submits the teleport. Saving is not locked to that spot, so the next Save records wherever the vehicle is.

The Save button reads the vehicle position again at click time and saves that. It cannot save with no vehicle or invalid coordinates. Vehicle model is saved when available. Configuration, altitude and heading are omitted because a reliable native retrieval contract for those values has not been established for this task. Enduro does not spawn or restore vehicles when loading a save; the only respawns are the starter car on a fresh start and the in-place ones that repairs and part changes do.

If the vehicle position is temporarily unavailable (no vehicle, Earth not running), the HUD shows EARTH UNAVAILABLE and returns to READY wherever the vehicle is as soon as a position is available again. This never changes the saved location or base. A mission start, extension reload or **Reload Enduro** reloads the save and discards unsaved mileage and money.

## Save files and recovery

Enduro stores schema-1 profile `default` in `/settings/beamngEarthEnduro/save-a.json` and `save-b.json`. Each Save writes the file that does not hold your newest save, then reads it back to check it, so a failed save never damages the last good one. On load, the newest readable file is used. New profiles exist in memory until the first manual Save.

- **Save failed:** the HUD says *Could not save just now. Your last save is still safe. Press Save to try again.* Nothing is locked; keep playing and press Save again.
- **One file damaged:** the other one is loaded, with no action needed. The next Save replaces the damaged file.
- **Both files unreadable:** you get a fresh start, and the HUD says so. Saving replaces the unreadable files, so if you want them back, copy them somewhere else before you press Save.
- **ENDURO PAUSED:** only for a save made by a newer version of Enduro (update the mod), a save folder the game cannot open, or an internal problem. The HUD says which. **Reload Enduro** loads your last save again; anything since then is lost.

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

The archive is generated at `dist/beamng_earth_enduro-task002-ready.zip`. Packaging is deterministic and includes installation, architecture and acceptance documentation; it does not package user settings, saves or development dependencies. Every push to `main` runs the tests, builds the ZIP and publishes it as a new release tagged `build-<number>` (see `.github/workflows/release.yml`); if the tests fail, no release is made. The Python/Node commands above are for developers rebuilding/testing the mod, not for players installing the supplied ZIP. Developers can alternatively copy `mod/beamng_earth_enduro/` into the user's `mods/unpacked/beamng_earth_enduro/`; do not install both copies.

After a BeamNG.Earth update, check that Enduro can still read positions from it (reads a local git clone of Earth; changes nothing):

```sh
git clone https://github.com/TecnaGamer/BeamNG.Earth.git
.venv\Scripts\python.exe tools/check_earth_versions.py BeamNG.Earth
```

See [Task 004 mileage tracking](docs/TASK-004-mileage.md) and the [Task 003 simplified arrival check](docs/TASK-003-simplified-checks.md) (that arrival check has since been removed; Save now works wherever the vehicle is). The [Task 002 architecture](docs/TASK-002-architecture.md) and [Task 002 testing](docs/TASK-002-testing.md) documents describe the earlier, stricter checks and are kept as historical records, as is Task 001.
