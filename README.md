# World Ironman Enduro Rally

Independent single-player mod alongside [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth).
An enduro rally of very long, treacherous stages across the real world. You start each stage in a humble starter car at the start coordinates and try to reach the finish coordinates, earning money as you drive and spending it on repairs and upgrades. It is **ironman**: wreck your car when you cannot afford to fix it and it is game over, and you start the stage again from the beginning.

The mod (folder, ZIP and code names) is still called `beamng_earth_enduro` so existing installs, saves and HUD layouts keep working.

## The rally

**Stages.** The first stage is **Stage 1: Zoji La Pass**, from `34.271288, 75.163671` on the Sind River, Kashmir, to `34.43223, 75.80991` near Dras, Ladakh. The second is **Stage 2: Colo River**, from the Windsor Bridge roundabout, Windsor, NSW (`-33.601664, 150.82265`) to the bush tracks at Colo Heights, NSW (`-33.366081, 150.790919`), with a 30-minute limit. More stages are added by adding an entry to `lua/ge/extensions/beamngEarthEnduro/stages.lua` (an id, a name, start and finish towns, start and finish coordinates and a finish radius). The HUD shows the stage name, a briefing when the stage starts, and the finish town and coordinates with a Copy button. **Navigation tip:** paste the finish coordinates into the map search and click the finish point; the map plots a route from where you are and shows arrows and road markers in game. Once you are on the stage the HUD also shows the straight-line distance and compass direction to the finish.

**Starting a stage.** A fresh start (no save yet) or a restarted stage gives you the start coordinates to teleport to, the stage's starting money ($3,000 on Stage 1) and no mileage. When you arrive you are put in the starter car.

**Finishing.** Get within 100 m of the finish coordinates and the HUD celebrates with **STAGE COMPLETE**, showing your mileage, money and sponsor bonuses earned. The finish is saved straight away.

**Next stage.** When a stage after it exists, the finish screen offers **Start Stage 2: Colo River** (and so on). It takes your car, with its parts and any unpaid repair, and your money on to the next stage, and gives you its start coordinates to teleport to; mileage, the clock and sponsor bonuses start again. Pay for or put back any open parts or car bill first. The save records the stages you have completed, and the car and money you started the stage with.

**Stage clock.** Each stage has a time limit (2:00:00 for Stage 1). The top of the HUD shows it counting down in h:mm:ss. The clock starts when you reach the start and runs only while the game is not paused, you are in a vehicle with a valid position and the stage is not finished. Each **Repair**, each parts bill that includes a repair (Buy or Revert) and each **Buy car** adds a 5-minute penalty; buying parts on an undamaged car costs no time. When the limit runs out the clock turns red and counts up as **OVERTIME**; it is not game over. Next to it, **Pace** shows how many seconds you are ahead (green) or behind (red): the time limit spread evenly over the straight-line distance from start to finish, compared with your time used including penalties. Winding roads can show you behind early and ahead later. Like money, the clock is kept by **Save**, and **Restart stage** resets it.

**Ironman rule: when is it game over?** Your car is **wrecked** when its damage reaches 10,000 points (BeamNG calls about 30,000 major damage; a wreck's repair costs at least $5,100). If your car is wrecked and the repair costs more than your balance, the HUD shows **WRECKED** with a 10-second countdown. If you still cannot pay when it runs out, it is **GAME OVER**. Damage below the wreck level never ends the run, however broke you are, because the car can still be driven to earn money. A part change, which mends the car, cannot be used to dodge the bill: Revert is refused for an unpaid wreck. Game over is saved at once, so loading the level again does not undo it; everything but **Restart stage** is locked.

**Restart stage.** Starts the stage again from its start, in the starter car with the starting money on Stage 1, or on a later stage with the car and money you started it with, no mileage and a fresh clock, and replaces your save. After game over one press does it. At any other time (for example when your car is stuck, or after finishing) the first press asks you to confirm, because your progress is lost.

These numbers are constants at the top of `core.lua` (`WRECKED_DAMAGE`, `GAME_OVER_DELAY`) and in `stages.lua` (`finishRadiusMetres`, `startingMoney` per stage), so they are easy to tune after testing in game.

This prototype has passed automated logic, filesystem/JSON and HUD lifecycle tests with mocked game APIs.
**Windows BeamNG.drive acceptance is not yet tested.** The mod only needs a valid vehicle position from Earth; it does not wait for Earth's terrain, roads or streaming to finish.

## Requirements

- A licensed Windows BeamNG.drive installation. The mod follows the 0.39.x conventions inspected in Task 001; use 0.39.4 as the initial acceptance target and record the actual game version tested.
- Any BeamNG.Earth version, with its companion server running. The mod is not tied to an Earth version: it reads the vehicle position from the first of these that works — Earth's anchor `enuToGeodetic()` on the live vehicle position, Earth's recorded player position, or `places.here()` — so an Earth update only breaks Enduro if all three change. Every Earth release from `v1.4.5-preview` to `v1.5.5-beta` has been checked with `tools/check_earth_versions.py`.
- No extra Python server or runtime dependencies are required by **the mod** inside the game. Development tests use Python, Lupa and Node.js.

## Install on Windows

1. [Download the latest `beamng_earth_enduro.zip`](https://github.com/MadMerick01/BeamNG-Earth-Enduro/releases/latest/download/beamng_earth_enduro.zip). Older builds are listed on the [Releases page](https://github.com/MadMerick01/BeamNG-Earth-Enduro/releases).
2. Copy that single ZIP into your active **BeamNG user folder's `mods` directory**. Use the game launcher's user-folder tools to locate it; do not put the ZIP in Steam's game binaries. **Do not extract it.** Remove/disable an older copy of this mod to avoid duplicate extensions; keep your user settings and save files.
3. With the supported Earth mod and its companion running separately, enable the mod, load Earth Freeroam, and use **UI Apps → Add App → World Ironman Enduro Rally**. Move/resize it as desired. The mod never replaces the layout.

   The HUD keeps the stage, the stage clock and pace, status, any STAGE COMPLETE, WRECKED or GAME OVER banner, your money and **Save** always in view, and puts everything else on tabs: **Stage** (briefing, finish distance, vehicle, mileage, Restart stage), **Navigation** (start or resume and finish coordinates with Copy buttons, and the navigation tip), **Parts**, **New Car**, **Repair** and **Tips** (the briefing and tips). A dot marks a tab with something waiting, such as an open bill or repair owed, and a new parts or car bill, a wreck or coordinates to go to open their tab.
4. The HUD shows the start coordinates, the Stage 1 start on the Sind River, Kashmir **`34.271288, 75.163671`** for a new profile. Copy them, paste them into the BeamNG.Earth map and teleport there. Once you arrive, the HUD says you are in the right place and Save is available.

No JSON edits, extraction, Python, Node.js or command-line commands are needed to install or play the rally. The ZIP has `scripts/`, `lua/` and `ui/` directly at its root. The mod remains independent of Earth. ZIPs are published as GitHub Releases, not committed to the implementation source tree.

## Default base and optional advanced configuration

The built-in base (where a new profile starts) is the first stage's start, on the Sind River, Kashmir: **latitude `34.271288`, longitude `75.163671`**. It is used automatically when no user configuration exists. A `base` in the configuration moves the first stage's start, which is mainly useful for testing; the finish stays where the stage puts it. No settings files are created on load, and no existing configuration or saved profile is overwritten.

Optional overrides remain available at `<user folder>/settings/beamngEarthEnduro/config.json` (VFS `/settings/beamngEarthEnduro/config.json`). Only users who want an override need to copy/edit the included `config.example.json`:

```json
{
  "base": { "latitude": 34.271288, "longitude": 75.163671 },
  "resumeRadiusMetres": 50
}
```

Latitude must be -90..90 and longitude -180..180. `resumeRadiusMetres` (1..1000, default 50) is how close the vehicle must get to the start or last save coordinates to count as arrived. A legacy `stabilitySeconds` value is ignored. A present but invalid/unreadable override blocks activation and saving rather than being silently replaced by defaults. The rally reloads by itself when the file changes, or load the level again.

An existing profile retains its original base even when the configuration changes. For a new profile, the base becomes fixed when the session first gets a valid vehicle position, including across configuration reloads in that running instance. An unsaved profile does not survive exiting the game. Back up existing profile files before intentionally starting a different profile; there is no reset/delete button in this prototype.

## Start, save and resume

1. Load Earth Freeroam and enter an active vehicle. The HUD shows one set of coordinates: your last save, or the start (the base) if you have not saved yet. Press **Copy**, paste them into the BeamNG.Earth map and teleport there; The mod never submits the teleport itself. When the vehicle is within `resumeRadiusMetres` (50 m) of them, the HUD says *You're in the right place* and you carry on from there. Until then, Save is locked and driving earns no mileage or money, so a Save cannot overwrite your trek with wherever the game happened to spawn you.

   **Starter car:** on a fresh start (no save yet, or both save files unreadable) or after **Restart stage** the mod swaps your vehicle, when you arrive at the start, for the **WorldIronManEnduro Starter**, a 1950s Burnside coupe with a stock inline-six. Its parts count as paid for; upgrade it from there with **Parts** and keep it running with **Repair**. The config also appears under Burnside in the game's vehicle selector.

   **Your car is saved:** **Save** also keeps your car: its paid-for parts (an open parts bill is left out), paint and tuning. Each time a save loads (game start or level load) your vehicle is swapped for that car when you arrive at the last save coordinates, so you carry on in the car you saved. Like money, part changes made since the last Save are undone by a reload; before the first Save, a reload puts you back in the starter car. Saves made before this version have no car stored, and Enduro leaves your vehicle alone until your next Save.

   **Damage is owed, not forgiven:** Save also records how damaged the car is. The restored car comes back looking undamaged, but that repair is still owed: the HUD shows *Owed from your last save*, every repair quote and parts bill includes it, and it is carried through later saves until you pay it with **Repair** or a parts bill. Restarting the game therefore never gives a free repair. Dents are not put back on the restored car.
2. Drive anywhere. Saving is not locked to the spot you arrived at. Click **Save** to keep the vehicle's current valid geographic position. No periodic or shutdown autosave occurs.

   While READY, the HUD's **Mileage** counts the distance your vehicle covers between readings. Jumps faster than 150 m/s (540 km/h), such as teleports, are not counted, and nothing is counted while the vehicle position is unavailable. Mileage driven since the last Save is shown as *unsaved*; it is stored by **Save** and lost if you exit or load the level again without saving.

   The HUD's **Money** goes up by **$100 for every kilometre** counted as mileage, so teleports earn nothing. The balance is whole dollars; part-dollars carry over while you keep driving. For testing, the **+$10000 (test)** button adds $10,000 straight away. Like mileage, money earned since the last Save is shown as *unsaved*, kept by **Save** and lost on exit or when the level loads again without saving.

   **Sponsor bonus:** every **10 km** of counted mileage also pays a **$2,000 sponsor bonus**, and teleports never count toward it. A bar under the money shows how far it is to the next one ("Sponsor bonus in 3.2 km"), and the message box flashes a gold **+$2,000 SPONSOR BONUS** when it pays. The number of bonuses paid is saved with the balance, so a bonus is never paid twice, and unsaved bonuses go with a reload like any other money. **Restart stage** resets it, and the finish screen shows how many you earned. Bonuses stop once the stage is finished. A stage can set its own `sponsorBonus` and `sponsorEveryKm` in `stages.lua`; the defaults are one-line settings at the top of that file.
   **Service Perks:** you hold one perk at a time, shown as a purple badge next to your money. Every **5 km** of counted mileage (teleports never count) a random perk is offered in the message box: **Swap** takes it in place of yours, **Keep** turns it down. Any repair loses the perk you hold, except Insurance. Passive perks work by themselves the next time they apply: **Double Cash** (driving pays $200/km while held), **Sponsor Boost** (next sponsor bonus pays double), **No Penalty** (next repair or new car costs no time; a repair uses it instead of losing it), **Parts Discount** (half off the parts on the next parts bill), **Car Dealer Deal** (next new car 30% off) and **Insurance** (pays for a wreck that would end your run, once). Three need **Activate**: **Time Freeze** (the clock stops for 3 minutes of driving), **Pace Gift** (2 minutes off the clock) and **Lucky Mile** (the next 5 km pay triple). An activated perk leaves the slot and keeps running, even through a repair. The perk, the offer and anything running are saved with your progress. **Restart stage** goes back to the perk you started the stage with, and **Start Stage 2** takes your held perk with you (a running perk or an open offer stays behind). All perk values are one-line settings at the top of `perks.lua`.

   **Repair:** press **Get repair quote** to price the damage to the vehicle you are in. The price comes from the vehicle's overall damage: $100 call-out plus $0.50 per damage point, nothing under 50 points (a scratch), capped at $20,000. Press **Repair** to pay it; the vehicle is respawned where it stands with its current parts, tuning and paint, so every part is new. If you cannot afford it, nothing is charged or repaired and the HUD says how much more you need. If the damage changes or you switch vehicle after the quote, Repair re-quotes instead of charging. Money spent is shown as *spent, unsaved* until you **Save**.

   **Parts:** change parts in BeamNG's own parts menu as usual. The parts the vehicle had when you got in count as paid for. After each change the HUD's **Parts** section lists the parts added and taken off and the bill. A part costs its value from the game's part files, or $250 if it has none; parts taken off in the same change are traded in for 30% of their value, which lowers the bill but never pays out. Press **Buy** to pay and keep the parts (it is disabled when you cannot afford it), or **Revert** to put the paid parts back; tuning and paint are free and kept either way. Trying parts on and swapping back costs nothing. If you drive more than 25 m without paying, the paid parts are put back automatically. A part change respawns the vehicle and mends all damage, so when the vehicle was damaged the repair price is added to the bill, and it is still charged on Revert or driving off, as far as your balance allows. Repair is locked while a parts bill is open. Repair is also locked while a car bill is open.

   **Cars:** pick a car in BeamNG's own vehicle selector, or get into any car that is not yours, and the HUD's **Car** section shows a bill: the car's price from the game (the Value in its config's info file, or $10,000 if it has none), plus any parts you change on it, less the trade-in of your car. The trade-in is half your car's Value less the repair it needs, and never below $0, so a cheaper car can cost nothing but never pays out. Press **Buy car** to pay and keep it, or **Revert** to get your car back; driving more than 25 m without paying does the same. If the new car replaced yours, yours is respawned where you stand looking new, but its repair is still owed. If it was spawned as an extra car, you are put back in your own car, damage and all, and the extra car is left parked. While a car bill is open, your old car's damage still counts for the Ironman rule, and Save keeps your old car. The starter car and the saved car you get on arrival are yours and never billed; the starter car's Value is $3,500.
3. Restart the game. The HUD shows your last saved coordinates and your distance from them; go there as in step 1 to continue.

The Save button reads the vehicle position again at click time and saves that. It cannot save with no vehicle or invalid coordinates. Vehicle model and the paid-for car config are saved when available. Altitude and heading are omitted because a reliable native retrieval contract for those values has not been established for this task. Loading a save does not move you to the saved location; the saved car is respawned where you stand once you arrive.

If the vehicle position is temporarily unavailable (no vehicle, Earth not running), the HUD shows EARTH UNAVAILABLE and returns to READY wherever the vehicle is as soon as a position is available again; once you have arrived, you do not have to go back. This never changes the saved location or base. A mission start or extension reload reloads the save and discards unsaved mileage and money.

## Save files and recovery

The mod stores schema-1 profile `default` in `/settings/beamngEarthEnduro/save-a.json` and `save-b.json`. Each Save writes the file that does not hold your newest save, then reads it back to check it, so a failed save never damages the last good one. On load, the newest readable file is used. New profiles exist in memory until the first manual Save.

- **Save failed:** the HUD says *Could not save just now. Your last save is still safe. Press Save to try again.* Nothing is locked; keep playing and press Save again.
- **One file damaged:** the other one is loaded, with no action needed. The next Save replaces the damaged file.
- **Both files unreadable:** you get a fresh start, and the HUD says so. Saving replaces the unreadable files, so if you want them back, copy them somewhere else before you press Save.
- **RALLY PAUSED:** only for a save made by a newer version (update the mod), a save folder the game cannot open, or an internal problem. The HUD says which. Loading the level again loads your last save; anything since then is lost.

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

The archive is generated at `dist/beamng_earth_enduro.zip`. Packaging is deterministic and includes installation, architecture and acceptance documentation; it does not package user settings, saves or development dependencies. Every push to `main` runs the tests, builds the ZIP and publishes it as a new release tagged `build-<number>` (see `.github/workflows/release.yml`); if the tests fail, no release is made. The Python/Node commands above are for developers rebuilding/testing the mod, not for players installing the supplied ZIP. Developers can alternatively copy `mod/beamng_earth_enduro/` into the user's `mods/unpacked/beamng_earth_enduro/`; do not install both copies.

After a BeamNG.Earth update, check that the mod can still read positions from it (reads a local git clone of Earth; changes nothing):

```sh
git clone https://github.com/TecnaGamer/BeamNG.Earth.git
.venv\Scripts\python.exe tools/check_earth_versions.py BeamNG.Earth
```

See [Task 004 mileage tracking](docs/TASK-004-mileage.md) and the [Task 003 simplified arrival check](docs/TASK-003-simplified-checks.md) (that arrival check was removed, and a simpler one returned with the resume coordinates: arrive once per load, then Save works anywhere). The [Task 002 architecture](docs/TASK-002-architecture.md) and [Task 002 testing](docs/TASK-002-testing.md) documents describe the earlier, stricter checks and are kept as historical records, as is Task 001.
