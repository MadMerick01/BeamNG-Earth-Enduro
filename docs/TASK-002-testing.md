# Task 002 testing — BeamNG-Earth Enduro

Status: automated tests passed in the Linux cloud instance; **all Windows in-game acceptance steps below are untested**. This is an installable prototype for designer review, not a claim of in-game acceptance. No BeamNG.drive installation/runtime was provided here. No Task 003 features or commits/merge were made.

## Automated validation

From repository root:

```sh
python -m pip install -r tests/requirements.txt
python tests/run.py
python tools/package.py
```

Use an isolated venv as described in the README. Python 3.10+, Lupa 2.8 (LuaJIT 2.1) and Node.js are required for the full test command. These are developer dependencies only.

Recorded cloud results:

| Suite | Result | What it establishes |
| --- | --- | --- |
| `test_location.lua` | 41 assertions passed | Finite/range validation, geography, antimeridian/poles, radius boundaries, timer reset, epoch/gap handling and config bounds. |
| `test_adapter.lua` | 54 assertions passed | Mock Earth compatibility/capabilities, fresh frame consistency, stale/disconnected data, vehicle absence, loading/rebase/reset states, normal guard mode, error isolation and source cache invalidation. |
| `test_persistence.lua` | 58 assertions passed | Valid/invalid schema, optional fields, generation selection, backup recovery, unknown schema protection, partial-write/read-back/directory failures, no writes during load. |
| `test_core.lua` | 105 assertions passed | First arrival/resume locking, profile creation, immutable base/target, revalidation, click-time checks, zero writes while locked, no periodic saves/payouts, failed writes and HUD limits. |
| `test_hud.lua` | 13 assertions passed | Change/throttle/heartbeat/resync behavior and bridge failure isolation. |
| `test_hud.mjs` | 5 Node tests passed | Angular directive lifecycle in a VM stub, commands, copyable coordinates, stale Save disabling and cleanup. |
| `test_installable.py` | 4 Python tests passed | Exported loader/game hooks with engine stubs, actual temporary-file JSON round trips, restart/manual resume, fixed base, partial disk writes and recovery. |
| `test_package.py` | 4 Python tests passed | Standalone archive paths, absence of user saves, manifest/assets, PNG checksums and deterministic packaging. |

Total: **271 Lua assertions, 5 JavaScript tests and 8 Python tests passed**. Mock/JSON tests are not real game tests. In particular they do not establish native VFS behavior, real physics ordering, complete collision readiness, Windows layout persistence or visual rendering.

Additional packaging/source checks: the generated archive has the loader, Lua and app at its root; no user settings, save files, test runtime or upstream source is included. Archive entries/JSON manifests and icon are checked during package validation. The source manifest was checked against the read-only Earth baseline checkout and with simulated Windows CRLF line endings using `tools/check_earth_compatibility.py`.

## Windows test record

Fill this out during designer testing; do not infer results from the mock tests:

- Date / tester: **not run**
- Windows version: **not recorded**
- BeamNG.drive version / renderer: **not recorded** (initial candidate 0.39.4)
- Earth version / exact revision: **not validated in-game**
- ZIP or unpacked install: **not tested in-game**
- Approved base coordinates: **unset; designers must provide them**

## Session A — first launch

- [ ] Install supported Earth and exactly one Enduro copy; start the Earth companion normally.
- [ ] Without configuration, confirm BASE CONFIGURATION REQUIRED; Save must remain disabled.
- [ ] Copy/edit `config.example.json` into the user settings directory with approved numeric coordinates.
- [ ] Load Earth Freeroam, add Enduro HUD in UI Apps, and save the layout through the game's editor as needed.
- [ ] Confirm START LOCATION REQUIRED, correct base fields and geographic distance when available.
- [ ] Confirm the coordinate inputs can be selected/copied individually without game input interference.
- [ ] Use Earth's existing interface to teleport manually to the base; confirm Enduro never moves the vehicle itself.
- [ ] While Earth is transitioning/loading, confirm Save stays locked and verification resets.
- [ ] Remain within 50 m for at least three continuous valid seconds after Earth settles (or configured values).
- [ ] Confirm LOCATION VERIFIED — READY TO CONTINUE, current coordinates, vehicle model if available and Save enabled.
- [ ] Drive elsewhere. Confirm READY allows movement away from the base; temporary streaming interruptions may require restabilization.
- [ ] Stop/settle if necessary; click Save. Confirm Saved successfully and one valid generation file under the user settings directory.
- [ ] Confirm balance/mileage placeholders do not change while driving.
- [ ] Exit BeamNG.drive. Preserve the files for Session B.

## Session B — resume

- [ ] Restart the game, companion and Earth level; retain the HUD in the normal Earth layout.
- [ ] Confirm RESUME REQUIRED and the previous saved coordinates; Save is locked even if the vehicle starts at the base.
- [ ] Manually teleport through Earth's interface to the saved coordinates.
- [ ] Confirm distance from Saved Location behaves geographically and decreases on arrival.
- [ ] After uninterrupted valid proximity, confirm READY and a fresh session baseline.
- [ ] Drive to another location, settle if necessary and Save again.
- [ ] Inspect both generations: increasing generations, distinct resume position, identical original base.
- [ ] Edit the configured base to another valid value, Reload Enduro and verify the profile still displays its original base and saved target.
- [ ] Restore the designers' intended configuration afterward; do not edit save coordinates to fake acceptance.

## Failure matrix

Perform destructive file corruption only on backed-up test-profile copies with the game stopped.

| Scenario | Expected result | In-game result |
| --- | --- | --- |
| Earth missing/disabled | EARTH UNAVAILABLE, no writes/profile creation. Ordinary game remains usable. | Untested |
| Unsupported Earth source or server metadata | Clear unsupported status; log details; no internal-access fallback or writes. | Untested |
| Unset/out-of-range/nonfinite base | CONFIG_REQUIRED; no gameplay initialization/save. | Untested |
| Outside arrival radius | START/RESUME REQUIRED; moving outside during verification resets timer. | Untested |
| Teleport/rebase/drop hold/tunnel placement | Progression/save suspended during detectable transitions; no false immediate READY. | Untested |
| Invalid/stale geographic readings | Verification resets, last save unchanged. | Untested |
| Companion disconnect during verification | EARTH UNAVAILABLE and timer reset. Reconnection requires stable readings again. | Untested |
| Vehicle unavailable or switched/reset | Save suspended; fresh vehicle/position verification required. | Untested |
| Pause or long frame gap | No stability time credited through invalid interval. | Untested |
| One damaged generation | Load valid generation with recovery feedback; file scanning does not write. | Untested |
| Both generations damaged / unsupported schema | ERROR, no new-profile overwrite; recover manually from backups. | Untested |
| Disk write fails or read-back fails | Failure feedback, ERROR, prior active generation retained; explicit reload/reverification required. | Untested |
| UI reload/remount | Current Lua state resynchronizes; no duplicate events/timer leak or layout replacement. | Untested |
| Lua/extension reload | Existing saves return to RESUME REQUIRED; no automatic teleport/save. | Untested |
| Another level/mission | Enduro pauses; returning to Earth starts the arrival gate again. | Untested |

## Known limitations and next review

- The adapter uses pinned internal read-only interfaces, not a maintained Earth public integration contract. Different revisions or unreadable VFS source files fail closed.
- Both Earth version strings are stale `0.4.0`; source fingerprints provide the client baseline check. Protocol/hello cannot prove an exact companion-server revision.
- Conservative road settling can delay or prevent verification in unusual server configurations (notably roads disabled only on the server). Do not bypass gates to make an acceptance test pass.
- Horizontal proximity and stable readings are not proof of full collision readiness, safe ground contact or correct bridge/tunnel layer. No altitude/heading/vehicle/damage restoration occurs.
- Live Earth/physics hook ordering, VFS source/JSON access, HTML/CSS, coordinate selection and app layout retention remain unverified in-game.
- There is one profile, no profile/reset UI, no autosave, and no economy/mileage earning. Unsaved changes can be lost on exit/reload by design.
- Two generations limit damage from interrupted writes but cannot guarantee power-loss durability or synchronize external writers.
- Task 002 ends at this prototype and test checklist. Designers should run the Windows acceptance sessions, record actual results and review the implementation before authorizing Task 003.
