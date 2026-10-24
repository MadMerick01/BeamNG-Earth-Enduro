local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local P = require('beamngEarthEnduro/persistence')
local location = require('beamngEarthEnduro/location')
local punctures = require('beamngEarthEnduro/punctures')
local Core = require('beamngEarthEnduro/core')
local A = P.DIRECTORY .. 'save-a.json'
local north = 1 / 111195.0802 -- degrees latitude per metre
T.eq(punctures.AVERAGE_KM, 40, 'about one every 40 km'); T.eq(punctures.GAP_KM, 5, 'none within 5 km of the last')
T.eq(punctures.SAFE_FINISH_METRES, 1000, 'none in the last km'); T.eq(punctures.OFF_ROAD_MULTIPLIER, 2, 'double off road')

-- The chance: one per AVERAGE_KM at the reference speed, more at speed, double off road.
T.near(punctures.chance(1000, 70, false), 1 / 40, 1e-12, '1 in 40 per km at 70 km/h')
T.near(punctures.chance(1000, 140, false), 2 / 40, 1e-12, 'twice as likely at 140 km/h')
T.near(punctures.chance(1000, 70, true), 2 / 40, 1e-12, 'twice as likely off road')
T.near(punctures.chance(1000, 1000, true), 2.5 * 2 / 40, 1e-12, 'speed factor capped')
T.near(punctures.chance(1000, 1, false), 0.25 / 40, 1e-12, 'crawling still has a small chance')
T.eq(punctures.chance(0, 70, false), 0, 'no distance, no chance')
-- Over a 15 km CarKov run off road at 70 km/h, about a 1 in 2 chance; on road about 1 in 3.
T.near(1 - math.exp(-15 * punctures.chance(1000, 70, false)), 0.31, 0.01, 'about 1 in 3 over 15 km on road')

-- Game side: the burst runs the car's own deflate call; off road is read from the road map.
do
  local commands = {}
  local car = { queueLuaCommand = function(_, command) commands[#commands + 1] = command end,
    getPosition = function() return { x = 1, y = 2, z = 3 } end }
  local road = { distance = 30 }
  local roads = { findClosestRoad = function() return 'n1', 'n2', road.distance end,
    getMap = function() return { nodes = { n1 = { radius = 4 } } } end }
  local p = punctures.new({ player = function() return car end, map = function() return roads end })
  T.check(p:burst(), 'burst sent'); T.check(commands[1]:find('beamstate.deflateRandomTire()', 1, true), 'deflates a random tyre')
  T.check(load(commands[1]) ~= nil, 'the command is valid Lua')
  T.eq(p:offRoad(), true, '30 m from a 4 m road is off road')
  road.distance = 12; T.eq(p:offRoad(), false, 'within 10 m of the road edge is on road')
  roads.findClosestRoad = function() return nil end; T.eq(p:offRoad(), nil, 'no road map, unknown')
  T.eq(punctures.new({ player = function() return car end, map = function() return nil end }):offRoad(), nil, 'no map module, unknown')
  T.eq(select(2, punctures.new({ player = function() return nil end, map = function() return roads end }):burst()), 'vehicle_required', 'needs a car')
  car.queueLuaCommand = function() error('boom') end
  T.eq(select(2, p:burst()), 'burst_failed', 'errors contained')
end

-- Drives north in 100 m steps at 100 m/s (360 km/h, so the speed factor is capped at 2.5).
local function drive(c, a, fromMetres, metres)
  for step = 1, math.floor(metres / 100) do a.pose = F.position((fromMetres + step * 100) * north); c:tick(1) end
  return fromMetres + metres
end
local function stage(random)
  local p = F.punctures()
  local c, io, a, _, _, g = F.controller({ punctures = p, random = random })
  c:tick(0.1)
  return c, io, a, p, g
end

-- With no luck (random always 0.999...), nothing ever bursts; the road map is asked about once a second.
do
  local c, _, a, p = stage(function() return 0.999999 end)
  drive(c, a, 0, 20000)
  T.eq(p.bursts, 0, 'no puncture without the bad luck'); T.eq(c:view().puncture, nil, 'nothing shown')
  T.check(p.checks >= 190 and p.checks <= 201, 'off road checked once a second (got ' .. p.checks .. ')')
end

-- Bad luck: a puncture, the HUD message, the tyre in the repair, and the 5 km gap.
do
  local roll = 0
  local c, io, a, p, g = stage(function() return roll end)
  local at = drive(c, a, 0, 100)
  T.eq(p.bursts, 1, 'tyre burst'); T.near(c.profile.progression.lastPunctureKm, 0.1, 1e-6, 'where it happened')
  local v = c:view()
  T.eq(v.puncture.flash, true, 'Puncture! shown'); T.eq(v.puncture.owed, true, 'tyre repair owed')
  T.eq(v.puncture.tyreCost, punctures.TYRE_REPAIR_COST * 20000 / 25000, 'tyre repair priced by the car Value')
  T.eq(v.repairOwed, nil, 'not counted as repair owed from a save')
  -- No second one within 5 km, then another after it.
  at = drive(c, a, at, 4800); T.eq(p.bursts, 1, 'none within 5 km')
  at = drive(c, a, at, 200); T.eq(p.bursts, 2, 'another once 5 km on')
  T.eq(c:view().puncture.tyreCost, 2 * punctures.TYRE_REPAIR_COST * 20000 / 25000, 'two tyres to repair')
  F.advance(c, punctures.SHOWN_FOR + 1); T.eq(c:view().puncture.flash, false, 'message fades'); T.eq(c:view().puncture.owed, true, 'tyres still owed')
  -- The repair quote includes the tyres, and repairing clears them.
  roll = 0.999999
  c:addTestMoney()
  T.check(c:requestRepairQuote(), 'quoted')
  T.eq(c:view().repairQuote, Core.repairCost(0) + 0 + (Core.repairCost(2 * punctures.TYRE_REPAIR_COST / 0.5, 20000)), 'quote includes both tyres')
  T.check(c:repairVehicle(), 'repaired'); T.eq(g.repairs, 1, 'car respawned, tyres put right')
  T.eq(c:view().puncture, nil, 'no puncture after the repair')
  -- Saved with the run: a reload keeps where the last one was.
  T.check(c:manualSave(), 'saved'); T.near(io.files[A].progression.lastPunctureKm, 5.1, 1e-6, 'last puncture saved')
end

-- A puncture not repaired by Save is owed with the car, like other damage.
do
  local c, io, a, p = stage(function() return 0 end)
  drive(c, a, 0, 100)
  T.check(c:manualSave(), 'saved'); T.eq(io.files[A].vehicle.damage, punctures.TYRE_REPAIR_COST / 0.5, 'tyre owed in the save')
  c:reload(); a.pose = F.position(100 * north); c:tick(0.1)
  T.eq(c:view().repairOwed, Core.repairCost(punctures.TYRE_REPAIR_COST / 0.5, 20000), 'owed after a reload')
end

-- Off road doubles the chance: a roll that misses on road hits off road.
do
  local c, _, a, p = stage(function() return 0.004 end) -- chance per 100 m at the cap: 0.00625 on, 0.0125 off
  p.off = false
  drive(c, a, 0, 100)
  T.eq(p.bursts, 1, 'hits on road at 0.004')
  local c2, _, a2, p2 = stage(function() return 0.01 end)
  drive(c2, a2, 0, 1000)
  T.eq(p2.bursts, 0, 'misses on road at 0.01')
  p2.off = true; F.advance(c2, 1.1)
  drive(c2, a2, 1000, 100)
  T.eq(p2.bursts, 1, 'hits off road at 0.01')
end

-- Never in the last km before the finish.
do
  local c, _, a, p = stage(function() return 0 end)
  c.stage = { id = c.stage.id, finish = F.position(1150 * north), finishRadiusMetres = 100, name = 'Test',
    sponsorEveryKm = 10, sponsorBonus = 0 }
  local at = drive(c, a, 0, 100)
  T.eq(p.bursts, 1, 'puncture 1,050 m out')
  c.profile.progression.lastPunctureKm = nil
  drive(c, a, at, 900)
  T.eq(p.bursts, 1, 'none inside the last km')
end

-- A failed burst is logged and costs nothing.
do
  local c, _, a, p = stage(function() return 0 end)
  p.fails = true
  drive(c, a, 0, 200)
  T.eq(c:view().puncture, nil, 'nothing owed'); T.eq(c.profile.progression.lastPunctureKm, nil, 'nothing recorded')
end

-- On a CarKov run too, and never in the last km before the extraction.
do
  local p = F.punctures()
  local c, _, a = F.controller({ punctures = p })
  c:tick(0.1); c:addTestMoney()
  T.check(c:enterCarKov(), 'entered CarKov')
  c.random = function() return 0 end
  c.carkov.hostileAtKm = nil
  a.pose = location.copy(c:view().resume); c:tick(0.1)
  local function towards(metres)
    for _ = 1, math.floor(metres / 100) do
      a.pose = location.destination(a.pose, location.bearing(a.pose, c.carkov.extraction), 100); c:tick(1)
    end
  end
  towards(100)
  T.eq(p.bursts, 1, 'puncture on the run')
  towards(13500)
  T.eq(p.bursts, 3, 'one every 5 km at most')
  towards(500)
  c.profile.progression.lastPunctureKm = nil
  towards(300)
  T.eq(p.bursts, 3, 'none in the last km before extraction')
end

-- Without the puncture maker (older callers and other tests), nothing happens.
do
  local c, _, a = F.controller({ random = function() return 0 end })
  c:tick(0.1); drive(c, a, 0, 1000)
  T.eq(c:view().puncture, nil, 'no punctures without it')
end

T.done('punctures')
