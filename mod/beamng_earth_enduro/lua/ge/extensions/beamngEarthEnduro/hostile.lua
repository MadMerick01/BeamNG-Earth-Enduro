-- CarKov hostile: once per run, at a random distance driven, a hostile car is spawned a few hundred
-- metres behind the player and its AI is set to chase and ram them. Disabling it pays a bounty. The
-- core controller runs the encounter; this file holds its settings and the game calls that spawn,
-- read and remove the hostile car. Every game call is guarded, so a missing or changed function
-- makes the spawn fail and the run carries on without a hostile.
local M = {}

-- One-line settings. Tune these after testing in game.
M.REWARD = 5000
M.SPAWN_FROM_KM, M.SPAWN_TO_KM = 3, 10 -- driven on the run before the hostile comes
M.SAFE_EXTRACTION_METRES = 1000 -- never spawns this close to the extraction point
M.WARNING_SECONDS = 5 -- HOSTILE INBOUND shows this long before the spawn
-- BeamNG.Earth only has ground with collision near the player: its terrain block follows the
-- player's car and, on its smaller 512 x 512 block, keeps the car at least 250 m inside its edge
-- (follow.lua), with road and bridge collision 320 m around it (roads.lua COLLIDE_M). A car spawned
-- beyond that falls through the world, so the hostile comes SPAWN_BEHIND_METRES behind, well inside
-- both. It only spawns where a ray finds ground; with none there it tries SPAWN_STEP_METRES closer,
-- down to SPAWN_MIN_METRES, and failing that waits and tries again for up to SPAWN_WAIT_SECONDS.
M.SPAWN_BEHIND_METRES = 150
M.SPAWN_MIN_METRES = 60
M.SPAWN_STEP_METRES = 30
M.SPAWN_WAIT_SECONDS = 10
-- A hostile with no ground under it for FALL_SECONDS has fallen through the world (left behind
-- off the terrain block, or spawned before the ground was in): it is respawned behind the player,
-- up to RESPAWN_TRIES times a run, then removed.
M.FALL_SECONDS = 1.5
M.RESPAWN_TRIES = 2
-- Disabled: stopped (no faster than STILL_SPEED m/s) for STILL_SECONDS, with at least
-- DISABLED_DAMAGE damage, so an AI car that is merely stuck pays nothing. BeamNG's own traffic
-- code calls about 1000 moderate damage. The player claims it by getting within CLAIM_METRES.
M.STILL_SECONDS = 10
M.STILL_SPEED = 1
M.DISABLED_DAMAGE = 1000
M.CLAIM_METRES = 10
-- A hostile left this far behind is removed, to save frame rate.
M.LOST_METRES = 3000
-- The brain: the hostile switches between ways of driving as the chase goes. Far off it drives
-- straight at the player, steered from here, since BeamNG's chase AI needs roads and Earth often
-- has none; close in it hands over to the chase AI. Stuck, it reverses out and tries again, and
-- after it rams the player (or is pinned against them) it backs off to ram again. After
-- UNSTICK_TRIES failed tries in a row it gives up and sits still. Time spent reversing or backing
-- off never counts towards the STILL_SECONDS that disable it.
M.BRAIN = {
  CHASE_WITHIN_METRES = 120, -- hands over to the chase AI this close
  DIRECT_BEYOND_METRES = 180, -- and back to driving straight at the player beyond this
  STUCK_SECONDS = 4, -- no faster than STILL_SPEED this long means stuck
  UNSTICK_SECONDS = 2.5, UNSTICK_THROTTLE = 0.6, -- reverses out this long, this hard
  UNSTICK_TRIES = 3, -- tries in a row before it gives up
  UNSTICK_TRIES_DAMAGED = 1, -- the same, once it has DISABLED_DAMAGE
  FREED_SPEED = 4, -- moving this fast (m/s) counts as free again and resets the tries
  RAM_METRES = 8, -- this close counts as ramming
  HIT_DAMAGE = 300, -- its damage jumping this much while ramming is a hit
  BACKOFF_SECONDS = 1.5, BACKOFF_THROTTLE = 0.7, -- after a hit it reverses this long, this hard
  DIRECT_THROTTLE = 0.8, TURN_THROTTLE = 0.4, -- driving straight at the player; slower when turning round
  STEER_FULL_DEGREES = 35, -- full lock when the player is this far off its nose
  -- Steering input +1 is taken to be right. Not yet checked in game; if the hostile steers away
  -- from the player, set this to -1.
  STEER_SIGN = 1,
  DRIVE_EVERY_SECONDS = 0.2, -- how often its steering is updated while steered from here
}
-- The hostile's car: the Robber Light, a black off-road Roamer shipped in vehicles/roamer. Set
-- both to nil to send a copy of the player's current car instead.
M.MODEL, M.CONFIG = 'roamer', 'vehicles/roamer/robber_light.pc'

-- The distance into the run at which the hostile comes. random() returns a number in [0, 1).
function M.pickKm(random)
  return M.SPAWN_FROM_KM + random() * (M.SPAWN_TO_KM - M.SPAWN_FROM_KM)
end

local function clamp(x, low, high) return math.max(low, math.min(high, x)) end

-- Steering towards a player angle degrees to the left of the nose (negative is to the right).
local function steerTowards(angle)
  local B = M.BRAIN
  if not angle then return 0 end
  return clamp(-angle / B.STEER_FULL_DEGREES, -1, 1) * B.STEER_SIGN
end

-- Straight at the player when far off, the chase AI when close, with a gap between the two so it
-- does not flip back and forth.
local function approach(mode, reading)
  local B = M.BRAIN
  if not reading.distance then return 'chase' end
  if mode == 'chase' then return reading.distance > B.DIRECT_BEYOND_METRES and 'direct' or 'chase' end
  return reading.distance > B.CHASE_WITHIN_METRES and 'direct' or 'chase'
end

-- What the hostile is told to do in each mode. A drive order is steered from here: gear 1 forward,
-- -1 reverse. Reversing with the wheel turned away from the player swings its nose towards them.
local function order(mode, reading)
  local B = M.BRAIN
  if mode == 'chase' then return { kind = 'chase' } end
  if mode == 'beaten' then return { kind = 'rest' } end
  local steer = steerTowards(reading.angle)
  if mode == 'direct' then
    local behind = reading.angle and math.abs(reading.angle) > 90
    return { kind = 'drive', gear = 1, throttle = behind and B.TURN_THROTTLE or B.DIRECT_THROTTLE, steer = steer }
  end
  return { kind = 'drive', gear = -1, steer = -steer,
    throttle = mode == 'backoff' and B.BACKOFF_THROTTLE or B.UNSTICK_THROTTLE }
end

-- One step of the brain. brain is a table kept between steps (start with {}); reading is the
-- hostile's status: { speed, damage, distance, angle }. Returns the order to send, or nil when
-- nothing needs sending. brain.mode is 'direct', 'chase', 'unstick', 'backoff' or 'beaten'.
function M.think(brain, reading, dt)
  local B = M.BRAIN
  brain.timer = (brain.timer or 0) + dt
  brain.since = (brain.since or math.huge) + dt
  brain.tries = brain.tries or 0
  local hit = brain.lastDamage ~= nil and reading.damage - brain.lastDamage >= B.HIT_DAMAGE
  brain.lastDamage = reading.damage
  if reading.speed >= B.FREED_SPEED then brain.tries = 0 end
  brain.slow = reading.speed <= M.STILL_SPEED and (brain.slow or 0) + dt or 0
  local near = reading.distance ~= nil and reading.distance <= B.RAM_METRES
  local mode, nextMode = brain.mode, brain.mode
  if mode == 'unstick' or mode == 'backoff' then
    local lasts = mode == 'unstick' and B.UNSTICK_SECONDS or B.BACKOFF_SECONDS
    if brain.timer >= lasts then nextMode = approach(nil, reading) end
  elseif mode ~= 'beaten' then
    if hit and near then nextMode = 'backoff'
    elseif brain.slow >= B.STUCK_SECONDS then
      local allowed = reading.damage >= M.DISABLED_DAMAGE and B.UNSTICK_TRIES_DAMAGED or B.UNSTICK_TRIES
      -- Stopped against the player is pushing, not stuck: back off and ram again.
      if near then nextMode = 'backoff'
      elseif brain.tries < allowed then nextMode, brain.tries = 'unstick', brain.tries + 1
      else nextMode = 'beaten' end
    else
      nextMode = approach(mode, reading)
    end
  end
  if nextMode ~= mode then
    brain.mode, brain.timer, brain.slow, brain.since = nextMode, 0, 0, 0
    return order(nextMode, reading)
  end
  -- Steering from here needs updating as the player moves.
  if (mode == 'direct' or mode == 'unstick' or mode == 'backoff') and brain.since >= B.DRIVE_EVERY_SECONDS then
    brain.since = 0
    return order(mode, reading)
  end
  return nil
end

-- Whether standing still now counts towards the hostile being disabled: not while it is
-- reversing out or backing off.
function M.counts(brain)
  return brain.mode ~= 'unstick' and brain.mode ~= 'backoff'
end

local function defaults()
  return {
    player = function() return getPlayerVehicle(0) end,
    -- GE keeps each vehicle's position, velocity and beamstate damage in map.objects[id].
    objects = function() local m = rawget(_G, 'map'); return type(m) == 'table' and m.objects or nil end,
    vehicles = function() return rawget(_G, 'core_vehicles') or (extensions and extensions.core_vehicles) end,
    objectById = function(id) return getObjectByID(id) end,
    point = function(x, y, z) return vec3(x, y, z) end,
    -- Faces the car along the flat direction (x, y). Not yet checked in game; if hostiles spawn
    -- facing away from the player, negate the direction here.
    rotation = function(x, y) return quatFromDir(vec3(x, y, 0), vec3(0, 0, 1)) end,
    -- Height of the ground below (x, y), looking down from z; nil when unknown.
    ground = function(x, y, z)
      if type(castRayStatic) == 'function' then
        local hit = castRayStatic(vec3(x, y, z), vec3(0, 0, -1), 1000)
        if type(hit) == 'number' and hit < 1000 then return z - hit end
      end
      if be and be.getSurfaceHeightBelow then
        local height = be:getSurfaceHeightBelow(vec3(x, y, z))
        if type(height) == 'number' and height > -1e6 then return height end
      end
      return nil
    end,
  }
end

local function copy(value)
  if type(value) ~= 'table' then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

local function length(x, y, z) return math.sqrt(x * x + y * y + (z or 0) * (z or 0)) end

function M.new(environment)
  local env = environment or defaults()
  local h = {}
  local targets = {}

  local function player()
    local ok, vehicle = pcall(env.player)
    if not ok or not vehicle then return nil end
    local idOK, id = pcall(function() return vehicle:getID() end)
    if not idOK or id == nil then return nil end
    return vehicle, id
  end

  -- What each hostile was last told: { kind, gear }, so the AI and gearbox are only switched on a change.
  local last = {}

  -- Sends a brain order to the hostile: 'chase' hands it to BeamNG's chase AI aimed at the player
  -- (it rams), 'drive' turns the AI off and steers it from here ({ gear, throttle, steer }), and
  -- 'rest' turns the AI off and holds the brakes. Vehicle-side calls are not yet checked in game.
  function h:drive(id, command)
    local target = targets[id]
    local ok, vehicle = pcall(env.objectById, id)
    if not ok or not vehicle or not target then return false, 'vehicle_gone' end
    local was = last[id] or {}
    local parts = {}
    local function gear(index)
      if was.gear == index then return end
      parts[#parts + 1] = string.format('local mc = controller and controller.mainController '
        .. 'if mc and mc.shiftToGearIndex then mc.shiftToGearIndex(%d) end', index)
    end
    if command.kind == 'chase' then
      if was.kind and was.kind ~= 'chase' then
        parts[#parts + 1] = 'input.event("throttle", 0, 2) input.event("brake", 0, 2) input.event("steering", 0, 2)'
      end
      gear(1)
      parts[#parts + 1] = string.format(
        'ai.setTargetObjectID(%d) ai.setMode("chase") ai.setAggression(1) ai.driveInLane("off")', target)
      last[id] = { kind = 'chase', gear = 1 }
    else
      if was.kind ~= 'drive' and was.kind ~= 'rest' then parts[#parts + 1] = 'ai.setMode("disabled")' end
      if command.kind == 'rest' then
        parts[#parts + 1] = 'input.event("throttle", 0, 2) input.event("brake", 1, 2) input.event("steering", 0, 2)'
        last[id] = { kind = 'rest', gear = was.gear }
      else
        gear(command.gear)
        parts[#parts + 1] = string.format('input.event("throttle", %.2f, 2) input.event("brake", 0, 2) '
          .. 'input.event("steering", %.2f, 2)', command.throttle, command.steer)
        last[id] = { kind = 'drive', gear = command.gear }
      end
    end
    local sent, why = pcall(function() vehicle:queueLuaCommand(table.concat(parts, ' ')) end)
    if not sent then return false, 'drive_failed', tostring(why) end
    return true
  end

  -- Tells the hostile's AI to chase the player and ram them.
  function h:chase(id) return h:drive(id, { kind = 'chase' }) end

  -- Spawns the hostile behind the player vehicle, facing the way it faces, and sets it chasing.
  -- config is a .pc path or a config table. Returns the new vehicle's id, or nil and a reason
  -- ('no_ground' when no ground with collision was found behind the player).
  function h:spawn(model, config, behindMetres)
    local vehicle, playerId = player()
    if not vehicle then return nil, 'vehicle_required' end
    local ok, pos, dir = pcall(function() return vehicle:getPosition(), vehicle:getDirectionVector() end)
    if not ok or not pos or not dir then return nil, 'position_unavailable' end
    local fx, fy = dir.x, dir.y
    local flat = length(fx, fy)
    if not flat or flat ~= flat or flat < 1e-3 then fx, fy, flat = 0, 1, 1 end
    fx, fy = fx / flat, fy / flat
    -- Only where there is ground with collision: from behindMetres back, then closer in.
    local x, y, z
    local back = behindMetres
    while back >= M.SPAWN_MIN_METRES do
      local px, py = pos.x - fx * back, pos.y - fy * back
      local groundOK, height = pcall(env.ground, px, py, pos.z + 200)
      if groundOK and type(height) == 'number' and height == height then x, y, z = px, py, height; break end
      back = back - M.SPAWN_STEP_METRES
    end
    if not x then return nil, 'no_ground' end
    local vehicles = env.vehicles()
    if type(vehicles) ~= 'table' or type(vehicles.spawnNewVehicle) ~= 'function' then return nil, 'spawn_unavailable' end
    local spawned, hostile = pcall(function()
      return vehicles.spawnNewVehicle(model, { config = copy(config), pos = env.point(x, y, z + 0.5),
        rot = env.rotation(fx, fy), autoEnterVehicle = false, cling = true })
    end)
    if not spawned or not hostile then return nil, 'spawn_failed', tostring(hostile) end
    local idOK, id = pcall(function() return hostile:getID() end)
    if not idOK or id == nil then return nil, 'spawn_failed', 'no id' end
    targets[id] = playerId
    h:chase(id)
    return id
  end

  -- Returns { speed (m/s), damage, distance (m to the player), angle (degrees the player is to the
  -- left of its nose, negative to the right; nil when unknown), grounded (whether a ray down from it
  -- finds ground; nil when that cannot be read) } for the hostile, or nil and
  -- 'vehicle_gone' when it no longer exists, or 'not_ready' while the game has no reading yet.
  function h:status(id)
    local ok, vehicle = pcall(env.objectById, id)
    if not ok or not vehicle then return nil, 'vehicle_gone' end
    local objectsOK, objects = pcall(env.objects)
    local entry = objectsOK and type(objects) == 'table' and objects[id] or nil
    local own = objectsOK and type(objects) == 'table' and objects[targets[id]] or nil
    if type(entry) ~= 'table' or entry.vel == nil or entry.pos == nil then return nil, 'not_ready' end
    local damage = tonumber(entry.damage) or 0
    local speed = length(entry.vel.x, entry.vel.y, entry.vel.z)
    local distance = type(own) == 'table' and own.pos
      and length(entry.pos.x - own.pos.x, entry.pos.y - own.pos.y, entry.pos.z - own.pos.z) or nil
    if speed ~= speed or damage ~= damage then return nil, 'not_ready' end
    local angle
    if distance and entry.dirVec then
      local dx, dy = entry.dirVec.x, entry.dirVec.y
      local tx, ty = own.pos.x - entry.pos.x, own.pos.y - entry.pos.y
      if length(dx, dy) > 1e-3 and length(tx, ty) > 1e-3 then
        angle = math.deg(math.atan2(dx * ty - dy * tx, dx * tx + dy * ty))
      end
    end
    -- Fallen through the world: below the ground, a ray down meets nothing (collision is one-sided).
    local groundOK, height = pcall(env.ground, entry.pos.x, entry.pos.y, entry.pos.z + 2)
    local grounded = nil
    if groundOK then grounded = type(height) == 'number' and height == height end
    return { speed = speed, damage = damage, distance = distance, angle = angle, grounded = grounded }
  end

  -- Removes the hostile from the world, if it still exists.
  function h:remove(id)
    targets[id], last[id] = nil, nil
    local ok, vehicle = pcall(env.objectById, id)
    if not ok or not vehicle then return true end
    local removed, why = pcall(function() vehicle:delete() end)
    if not removed then return false, 'remove_failed', tostring(why) end
    return true
  end

  return h
end

return M
