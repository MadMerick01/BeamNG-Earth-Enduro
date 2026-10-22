# Future plan — section loading (load while paused, drive with no streaming)

Status: **planning only.** Wait until BeamNG.Earth is more mature; it currently changes almost daily
(886 commits between 10 and 22 October 2026), so anything built against it now would need redoing.

## Idea

While the game is paused, load a fixed square section of the world completely. The player drives that
section with nothing loading in. At the section's edge the game pauses again while the next section
loads. In Enduro the pause becomes the break between sections: repair or upgrade the car, plan the next
route, save.

Target size: **2 km × 2 km**, the same as the West Coast USA map, which is already big to drive across.

## Why BeamNG.Earth stutters today

Findings from the BeamNG.Earth source and its own measurements (`docs/ARCHITECTURE.md`,
`docs/research/2026-10-12-engine-limits-and-worldgen.md`, `CHANGELOG.md`, release 1.5.5-beta):

1. **The solid ground is re-loaded as you drive.** The drivable ground is one small TerrainBlock (1 km
   by default, 2 km in the older 1024 mode). Every ~130–190 m it is re-imported around the car: one
   frame of ~20–65 ms.
2. **Collision rebuilds.** Each new road, bridge or building needs `be:reloadCollision()`, which
   rebuilds collision for everything solid (~0.15–0.3 ms per 1,000 triangles) and holds up the frame.
   Earth allows one every 0.5 s while objects come and go.
3. **Constant background streaming.** Distant tiles and road pieces get ~2 ms of every frame, all the
   time. Rendering the tiles costs only ~0.6 ms; the rest is streaming.
4. **The physics clock speeds up and slows down** around runs of slow frames. This is why it *appears* to
   fluctuate even at a locked 60 fps. Earth's frame governor (`governor.lua`) tries to keep heavy work to
   single isolated frames.
5. **Shadow redraws for every new tile**, fixed in 1.5.5 (slow frames at 80 mph: ~17/s → ~2/s).
6. **Long sessions:** each distinct 3D model ever loaded adds ~0.3 ms per 1,000 models to every frame
   until the game restarts. This is a known issue in Earth.

## Why a 2 km section is feasible

- **Loading the ground is quick.** A 1024² block at 2 m (2 km) imports in ~40 ms; a 2048² block at
  1 m (West Coast's detail) in ~0.2 s. Making it solid takes ~2–7 ms. This is far too slow mid-drive,
  but trivial while paused.
- **Earth already has this size.** The 1024 mode already uses a 2 km block. Section mode is close to that
  mode with terrain-follow switched off.
- **Solid roads and buildings stay manageable.** A 2 km area holds about as much as an official map
  (West Coast: ~1,500 solid objects), so one collision rebuild per section is fine.
- **Pausing is already supported.** Earth already uses `simTimeAuthority.pause` during its post-teleport
  drop hold.
- **No precision problem.** Earth re-centres the world every 15 km; a 2 km section fits easily, and
  re-centring can happen at the pause.
- **The world server can build the next section in the background.** It runs as a separate process,
  and Earth measured no effect on frame times while it runs. Only the client-side import needs the pause.

## Risks and open questions

- **First visits.** The server's build time is the slowest part: in October measurements it took
  0.3–0.6 s per 256 m road tile when warm, and 8–21 s when it met new map data. A 2 km section is 64
  tiles. Building ahead in the background should hide most of this; revisits come from the cache.
- **The distant view stays fixed** between pauses. This is probably acceptable for an enduro.
- **Aerial photo size** on the terrain is fixed by the level's texture set when the map loads; a larger,
  sharper photo per section may need changes to Earth's level files.
- **Section edges:** what happens at the boundary (a soft wall, a slowdown, or the pause trigger
  itself), and whether the next section overlaps the last for a seamless handover.

## Approach when the time comes

- **Contribute upstream rather than keep a fork.** Earth is MIT-licensed, so a fork is allowed, but
  keeping it current would be a constant merge battle. Propose a "section mode" setting as a pull
  request to BeamNG.Earth (it accepts outside PRs, e.g. #71 in 1.5.5). Enduro would then only switch it
  on and trigger the pause.
- **Prototype in steps, measuring each one in-game:**
  1. Ground only: a 2 km block loaded while paused, with terrain-follow off.
  2. Add the section's roads and buildings, with one collision rebuild.
  3. Build the next section in the background, plus the pause at the edge.

  If step 2 is too slow or physics struggles, stop there and rethink.
- **Enduro side:** use the pause as the break screen (repairs, upgrades, route planning, save), and
  show the next section's loading progress.
