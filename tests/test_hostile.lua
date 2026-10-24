local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local location = require('beamngEarthEnduro/location')
local hostile = require('beamngEarthEnduro/hostile')
local north = 1 / 111195.0802 -- degrees latitude per metre
T.eq(hostile.REWARD, 5000, 'bounty is $5,000'); T.eq(hostile.STILL_SECONDS, 10, 'stopped for 10 s'); T.eq(hostile.CLAIM_METRES, 10, 'claimed within 10 m')
T.eq(hostile.MODEL, 'roamer', 'the hostile is a Roamer'); T.eq(hostile.CONFIG, 'vehicles/roamer/robber_light.pc', 'the Robber Light config')

-- The distance into the run is between 3 and 10 km.
T.eq(hostile.pickKm(function() return 0 end), 3, 'earliest at 3 km'); T.near(hostile.pickKm(function() return 0.999999 end), 10, 1e-4, 'latest at 10 km')

-- Game side: spawns behind the player, facing the same way, never entering it, and sets it chasing.
do
  local commands, deleted, spawned = {}, {}, nil
  local function point(x, y, z) return { x = x, y = y, z = z } end
  local objects = {
    [7] = { pos = point(1000, 2000, 50), vel = point(20, 0, 0), damage = 0 },
    [8] = { pos = point(1003, 2004, 50), vel = point(0.3, 0.4, 0), damage = 2500 },
  }
  local world = { [7] = true }
  local function car(id)
    return { getID = function() return id end, getPosition = function() return point(1000, 2000, 50) end,
      getDirectionVector = function() return point(0, 2, 0.1) end,
      queueLuaCommand = function(_, command) commands[#commands + 1] = { id = id, command = command } end,
      delete = function() deleted[#deleted + 1] = id; world[id] = nil end }
  end
  local env = {
    player = function() return car(7) end,
    objects = function() return objects end,
    vehicles = function() return { spawnNewVehicle = function(model, options)
      spawned = { model = model, options = options }; world[8] = true; return car(8) end } end,
    objectById = function(id) return world[id] and car(id) or nil end,
    point = point,
    rotation = function(x, y) return { x = x, y = y } end,
    ground = function() return 42 end,
  }
  local h = hostile.new(env)
  local config = { model = 'pickup', parts = { engine = 'v8' } }
  local id = h:spawn('pickup', config, 300)
  T.eq(id, 8, 'returns the hostile id'); T.eq(spawned.model, 'pickup', 'spawns the model given')
  T.eq(spawned.options.config.parts.engine, 'v8', 'with the config given'); T.check(spawned.options.config ~= config, 'a copy of it')
  T.eq(spawned.options.autoEnterVehicle, false, 'the player stays in their own car')
  T.near(spawned.options.pos.x, 1000, 1e-9, 'directly behind'); T.near(spawned.options.pos.y, 1700, 1e-9, '300 m behind')
  T.near(spawned.options.pos.z, 42.5, 1e-9, 'just above the ground'); T.near(spawned.options.rot.y, 1, 1e-9, 'facing the way the player faces')
  T.eq(#commands, 1, 'chase order sent'); T.check(commands[1].command:find('ai.setTargetObjectID%(7%)'), 'chases the player')
  T.check(commands[1].command:find('ai.setMode%("chase"%)'), 'in chase mode')
  local status = h:status(8)
  T.near(status.speed, 0.5, 1e-9, 'reads its speed'); T.eq(status.damage, 2500, 'reads its damage'); T.near(status.distance, 5, 1e-9, 'distance to the player')
  T.check(h:chase(8), 'chase order sent again'); T.eq(#commands, 2, 'second order')
  T.check(h:remove(8), 'removed'); T.eq(deleted[1], 8, 'deleted from the world')
  local _, why = h:status(8)
  T.eq(why, 'vehicle_gone', 'gone once removed'); T.check(h:remove(8), 'removing twice is harmless')
  objects[9] = nil; world[9] = true
  _, why = h:status(9)
  T.eq(why, 'not_ready', 'no reading yet just after a spawn')
  -- Failures are contained.
  T.eq(select(2, hostile.new({ player = function() return nil end }):spawn('pickup', config, 300)), 'vehicle_required', 'needs a player car')
  env.vehicles = function() return {} end
  T.eq(select(2, hostile.new(env):spawn('pickup', config, 300)), 'spawn_unavailable', 'missing spawner reported')
  env.vehicles = function() return { spawnNewVehicle = function() error('boom') end } end
  T.eq(select(2, hostile.new(env):spawn('pickup', config, 300)), 'spawn_failed', 'spawn errors contained')
end

-- The run, with a hostile set to come 4 km in.
local function onRun(options)
  local h = F.hostiles()
  local c, io, a, _, _, g = F.controller({ hostiles = h, random = options and options.random })
  c:tick(0.1)
  c:addTestMoney()
  T.check(c:enterCarKov(), 'entered CarKov')
  T.check(c.carkov.hostileAtKm >= 3 and c.carkov.hostileAtKm < 10, 'hostile distance picked on entry')
  T.eq(c.profile.carkov.hostileAtKm, c.carkov.hostileAtKm, 'and saved with the run')
  c.carkov.hostileAtKm = 4
  a.pose = location.copy(c:view().resume); c:tick(0.1)
  T.eq(c:view().arrived, true, 'at the drop')
  return c, a, h, g, io
end
-- Drives straight towards the extraction in 50 m steps at 50 m/s.
local function drive(c, a, metres)
  for _ = 1, math.floor(metres / 50) do
    a.pose = location.destination(a.pose, location.bearing(a.pose, c.carkov.extraction), 50); c:tick(1)
  end
end

-- Inbound, then the spawn behind the player in a copy of their car; a stuck AI pays nothing.
do
  local c, a, h, g = onRun()
  drive(c, a, 3900)
  T.eq(c:view().carkov.hostile, nil, 'no hostile before 4 km'); T.eq(#h.spawns, 0, 'nothing spawned')
  drive(c, a, 150)
  local v = c:view()
  T.eq(v.carkov.hostile.phase, 'inbound', 'HOSTILE INBOUND'); T.eq(v.carkov.hostile.seconds, 5, 'counts down from 5')
  T.eq(#h.spawns, 0, 'warning comes first')
  F.advance(c, 3.05)
  T.eq(c:view().carkov.hostile.seconds, 2, 'counting down')
  F.advance(c, 2.5)
  v = c:view()
  T.eq(#h.spawns, 1, 'hostile spawned'); T.eq(h.spawns[1].behind, 300, '300 m behind')
  T.eq(h.spawns[1].model, 'roamer', 'a Roamer'); T.eq(h.spawns[1].config, 'vehicles/roamer/robber_light.pc', 'in the Robber Light config')
  T.eq(v.carkov.hostile.phase, 'chasing', 'chasing'); T.eq(v.carkov.hostile.distanceMetres, 300, 'distance shown')
  F.advance(c, 2.1)
  T.eq(h.chases, 1, 'chase order sent again after the spawn')
  -- Stuck with no damage, beside the player, for longer than 10 s: not disabled, no bounty.
  local id = h:current()
  local balance = c:view().balance
  h.alive[id] = { speed = 0, damage = 50, distance = 5 }
  F.advance(c, 15)
  T.eq(c:view().carkov.hostile.phase, 'chasing', 'a stuck AI is not disabled'); T.eq(c:view().balance, balance, 'and pays nothing')
  -- Rammed: it moves, then stops damaged, but the player is not close enough yet.
  h.alive[id] = { speed = 8, damage = 4000, distance = 40 }; c:tick(0.1)
  h.alive[id].speed = 0.2
  F.advance(c, 9)
  T.eq(c:view().carkov.hostile.phase, 'chasing', 'not disabled before 10 s')
  F.advance(c, 1.2)
  T.eq(c:view().carkov.hostile.phase, 'disabled', 'disabled after 10 s stopped and damaged'); T.eq(c:view().balance, balance, 'not paid until claimed')
  -- Moving again starts the 10 s again.
  h.alive[id].speed = 5; c:tick(0.1); h.alive[id].speed = 0; c:tick(0.1)
  T.eq(c:view().carkov.hostile.phase, 'chasing', 'moving again resets it')
  F.advance(c, 10.2)
  h.alive[id].distance = 9; c:tick(0.1)
  v = c:view()
  T.eq(v.balance, balance + 5000, 'bounty paid within 10 m'); T.eq(v.carkov.hostile, nil, 'hostile gone')
  T.eq(h.removed[1], id, 'removed from the world'); T.eq(v.carkov.flash.title, 'HOSTILE DISABLED', 'HUD says so')
  T.eq(v.unsavedBalance >= 5000, true, 'kept by Save like driving pay')
  -- Once per run.
  drive(c, a, 3000)
  T.eq(#h.spawns, 1, 'only one hostile per run')
  T.check(c:manualSave(), 'saved'); T.eq(c.profile.carkov.hostileDone, true, 'save records the hostile came')
  c:reload(); c:tick(0.1); drive(c, a, 500)
  T.eq(#h.spawns, 1, 'no second hostile after a reload')
end

-- With no hostile config set, the hostile is a copy of the player's car.
do
  local model, config = hostile.MODEL, hostile.CONFIG
  hostile.MODEL, hostile.CONFIG = nil, nil
  local c, a, h, g = onRun()
  drive(c, a, 4050); F.advance(c, 5.1)
  T.eq(h.spawns[1].model, g.model, 'in the player car model'); T.eq(h.spawns[1].config.parts.engine, g.fitted.engine, 'with its parts')
  hostile.MODEL, hostile.CONFIG = model, config
end

-- The run ending removes the hostile.
do
  local c, a, h = onRun()
  drive(c, a, 4050); F.advance(c, 5.1)
  local id = h:current()
  T.check(id ~= nil, 'hostile out')
  c.quitArmed = true
  T.check(c:quitCarKov(), 'quit the run')
  T.eq(h.removed[#h.removed], id, 'hostile removed when the run ends'); T.eq(h:current(), nil, 'none left')
  T.eq(c:view().carkov.hostile, nil, 'HUD clear')
end

-- Leaving the level removes it, and a hostile left far behind is removed too.
do
  local c, a, h = onRun()
  drive(c, a, 4050); F.advance(c, 5.1)
  local id = h:current()
  c:endMission()
  T.eq(h.removed[#h.removed], id, 'removed when the level ends')
  c, a, h = onRun()
  drive(c, a, 4050); F.advance(c, 5.1)
  id = h:current()
  h.alive[id].distance = 3500; c:tick(0.1)
  T.eq(h.removed[#h.removed], id, 'removed when left far behind'); T.eq(c:view().carkov.flash.title, 'HOSTILE LOST', 'HUD says so')
end

-- Never inside the last kilometre before extraction, and a failed spawn just leaves the run alone.
do
  local c, a, h = onRun()
  c.carkov.hostileAtKm = 14.5
  for _ = 1, 400 do
    if location.distance(a.pose, c.carkov.extraction) < 900 then break end
    a.pose = location.destination(a.pose, location.bearing(a.pose, c.carkov.extraction), 50); c:tick(1)
  end
  c.profile.progression.totalDistanceKm = 15; c:tick(0.1); F.advance(c, 6)
  T.eq(#h.spawns, 0, 'no hostile within 1 km of extraction'); T.eq(c.carkov.hostileDone, true, 'and none later')
  c, a, h = onRun()
  h.fails = true
  drive(c, a, 4050); F.advance(c, 6)
  T.eq(c:view().carkov.hostile, nil, 'failed spawn clears the warning'); T.eq(c:view().carkov.active, true, 'run carries on')
end

-- No hostile spawner (or off a run), nothing happens.
do
  local c, a = F.controller()
  c:tick(0.1)
  T.eq(c:view().carkov.hostile, nil, 'no hostile on the stage'); T.eq(c:view().carkov.hostileReward, nil, 'not offered without a spawner')
end

T.done('CarKov hostile')
