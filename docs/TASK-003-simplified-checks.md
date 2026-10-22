# Task 003 — simplified arrival check

Scope: make the checks before Save much less strict. The HUD only needs to know that the player vehicle is at the correct coordinates; nothing else matters.

## What is checked now

1. BeamNG.Earth's `beamngEarth_core` exists and `_state()` returns an anchor with `enuToGeodetic()`.
2. There is a player vehicle with a position.
3. That position, converted to latitude/longitude through the anchor, is within `resumeRadiusMetres` (default 50 m) of the target: the base for a new profile, or the saved location when resuming.

When all three hold, the HUD enters READY straight away and Save is enabled. After arrival you can drive anywhere. Save reads the vehicle position again at click time and stores that position.

## Removed

- Source fingerprinting of nine Earth Lua files (`compatibility.lua`) and `tools/check_earth_compatibility.py`.
- Server hello/version/protocol, network connection and server health checks.
- Session/anchor identity ("epoch") tracking and the anchor/places cross-check.
- Earth transition flags (pending, rebasing, drop hold, edge guard, loading windows), stale-clock detection, current block margin and road readiness/settling.
- Paused-simulation and frame-gap checks, the post-reset quiet period and `onVehicleResetted`.
- The 3-second stability interval, the `VERIFYING_LOCATION` state and the `stabilitySeconds` setting (ignored if still present in a user config).
- Save-time rejection for vehicle/anchor changes or position jumps.

## Unchanged

Configuration loading and validation, the fixed default base, the two-slot save files with read-back verification, ERROR/CONFIG_REQUIRED protection of save data, manual-only saving and the HUD.

## Known trade-off

Because Enduro no longer waits for Earth to settle, a Save made during a teleport or origin rebase could, in principle, record a position converted with a mismatched anchor. This was accepted in exchange for the simpler flow. Windows in-game acceptance is still untested.
