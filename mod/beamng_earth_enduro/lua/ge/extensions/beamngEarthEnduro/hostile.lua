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
M.SPAWN_BEHIND_METRES = 300
-- Disabled: stopped (no faster than STILL_SPEED m/s) for STILL_SECONDS, with at least
-- DISABLED_DAMAGE damage, so an AI car that is merely stuck pays nothing. BeamNG's own traffic
-- code calls about 1000 moderate damage. The player claims it by getting within CLAIM_METRES.
M.STILL_SECONDS = 10
M.STILL_SPEED = 1
M.DISABLED_DAMAGE = 1000
M.CLAIM_METRES = 10
-- A hostile left this far behind is removed, to save frame rate.
M.LOST_METRES = 3000
-- The chase order is sent again this long after the spawn, in case the car's Lua was not ready.
M.CHASE_RETRY_SECONDS = 2
-- The hostile's car. nil uses a copy of the player's current car. To give it its own car, set
-- MODEL to the model and CONFIG to a .pc path, e.g. 'vehicles/pickup/hostile.pc'.
M.MODEL, M.CONFIG = nil, nil

-- The distance into the run at which the hostile comes. random() returns a number in [0, 1).
function M.pickKm(random)
  return M.SPAWN_FROM_KM + random() * (M.SPAWN_TO_KM - M.SPAWN_FROM_KM)
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

  -- Tells the hostile's AI to chase the player and ram them.
  function h:chase(id)
    local target = targets[id]
    local ok, vehicle = pcall(env.objectById, id)
    if not ok or not vehicle or not target then return false, 'vehicle_gone' end
    local sent, why = pcall(function()
      vehicle:queueLuaCommand(string.format(
        'ai.setTargetObjectID(%d) ai.setMode("chase") ai.setAggression(1) ai.driveInLane("off")', target))
    end)
    if not sent then return false, 'chase_failed', tostring(why) end
    return true
  end

  -- Spawns the hostile behind the player vehicle, facing the way it faces, and sets it chasing.
  -- config is a .pc path or a config table. Returns the new vehicle's id, or nil and a reason.
  function h:spawn(model, config, behindMetres)
    local vehicle, playerId = player()
    if not vehicle then return nil, 'vehicle_required' end
    local ok, pos, dir = pcall(function() return vehicle:getPosition(), vehicle:getDirectionVector() end)
    if not ok or not pos or not dir then return nil, 'position_unavailable' end
    local fx, fy = dir.x, dir.y
    local flat = length(fx, fy)
    if not flat or flat ~= flat or flat < 1e-3 then fx, fy, flat = 0, 1, 1 end
    fx, fy = fx / flat, fy / flat
    local x, y = pos.x - fx * behindMetres, pos.y - fy * behindMetres
    local groundOK, z = pcall(env.ground, x, y, pos.z + 200)
    if not groundOK or type(z) ~= 'number' or z ~= z then z = pos.z end
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

  -- Returns { speed (m/s), damage, distance (m to the player) } for the hostile, or nil and
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
    return { speed = speed, damage = damage, distance = distance }
  end

  -- Removes the hostile from the world, if it still exists.
  function h:remove(id)
    targets[id] = nil
    local ok, vehicle = pcall(env.objectById, id)
    if not ok or not vehicle then return true end
    local removed, why = pcall(function() vehicle:delete() end)
    if not removed then return false, 'remove_failed', tostring(why) end
    return true
  end

  return h
end

return M
