-- Reads and repairs the player vehicle. Base-game calls only, so it works outside career mode
-- (career's repair modules are not loaded in Earth Freeroam). Every call is guarded: a missing
-- or changed game function makes the quote or repair fail without touching the balance.
local M = {}

local function defaults()
  return {
    vehicle = function() return getPlayerVehicle(0) end,
    -- GE keeps each vehicle's beamstate damage in map.objects[id].damage.
    objects = function() local m = rawget(_G, 'map'); return type(m) == 'table' and m.objects or nil end,
    manager = function() return rawget(_G, 'core_vehicle_manager') or (extensions and extensions.core_vehicle_manager) end,
    vehicles = function() return rawget(_G, 'core_vehicles') or (extensions and extensions.core_vehicles) end,
  }
end

function M.new(environment)
  local env = environment or defaults()
  local g = {}

  local function current()
    local ok, vehicle = pcall(env.vehicle)
    if not ok or not vehicle then return nil end
    local idOK, id = pcall(function() return vehicle:getID() end)
    if not idOK or id == nil then return nil end
    return vehicle, id
  end

  -- Returns { id, damage } for the player vehicle, or nil and a reason.
  function g:inspect()
    local vehicle, id = current()
    if not vehicle then return nil, 'vehicle_required' end
    local ok, objects = pcall(env.objects)
    local entry = ok and type(objects) == 'table' and objects[id] or nil
    local damage = type(entry) == 'table' and tonumber(entry.damage) or nil
    if not damage or damage ~= damage or damage == math.huge or damage < 0 then return nil, 'damage_unavailable' end
    return { id = id, damage = damage }
  end

  -- Respawns the vehicle where it stands with its current parts, tuning and paint, which
  -- leaves every part new. Returns true once the game accepted the respawn.
  function g:repair()
    local vehicle, id = current()
    if not vehicle then return false, 'vehicle_required' end
    local manager, vehicles = env.manager(), env.vehicles()
    if type(manager) ~= 'table' or type(manager.getVehicleData) ~= 'function'
        or type(vehicles) ~= 'table' or type(vehicles.replaceVehicle) ~= 'function' then
      return false, 'repair_unavailable'
    end
    local dataOK, data = pcall(manager.getVehicleData, id)
    local config = dataOK and type(data) == 'table' and data.config or nil
    if type(config) ~= 'table' then return false, 'config_unavailable' end
    local modelOK, model = pcall(function() return vehicle:getJBeamFilename() end)
    if not modelOK or type(model) ~= 'string' or model == '' then model = config.model end
    if type(model) ~= 'string' or model == '' then return false, 'config_unavailable' end
    local ok, why = pcall(vehicles.replaceVehicle, model, { config = config, keepOtherVehRotation = true }, vehicle)
    if not ok then return false, 'repair_failed', tostring(why) end
    return true
  end

  return g
end

return M
