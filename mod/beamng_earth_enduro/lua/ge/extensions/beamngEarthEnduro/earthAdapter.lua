-- The only Enduro module permitted to inspect BeamNG.Earth. Never writes its state,
-- calls teleport, loads/enables Earth, or replaces any upstream function.
-- Task 003: the only question asked is where the player vehicle is geographically.
local location = require('beamngEarthEnduro/location')
local M = {}

local function defaults()
  return {
    core = function() return rawget(_G, 'beamngEarth_core') end,
    vehicle = function() return getPlayerVehicle(0) end,
  }
end

local function failed(reason, detail)
  return { valid = false, available = false, reason = reason, detail = detail }
end

function M.new(environment)
  local env = environment or defaults()
  local a = {}
  function a:invalidate() end
  function a:filesChanged() return false end
  local function sample()
    local core = env.core()
    if type(core) ~= 'table' or type(core._state) ~= 'function' then return failed('earth_missing') end
    local st = core._state()
    if type(st) ~= 'table' or type(st.anchor) ~= 'table' or type(st.anchor.enuToGeodetic) ~= 'function' then
      return failed('earth_starting')
    end
    local vehicle = env.vehicle()
    if not vehicle then return failed('vehicle_required') end
    local pos = vehicle:getPosition()
    if not pos then return failed('position_invalid') end
    local lat, lon = st.anchor:enuToGeodetic(pos.x, pos.y, pos.z)
    local current = { latitude = lat, longitude = lon }
    if not location.valid(current) then return failed('position_invalid') end
    local model
    local pathOK, path = pcall(function() return vehicle:getPath() end)
    if pathOK and type(path) == 'string' then model = path:match('^/?vehicles/([^/\\]+)/?') end
    local idOK, id = pcall(function() return vehicle:getID() end)
    return {
      valid = true, available = true, latitude = current.latitude, longitude = current.longitude,
      vehicle = { id = idOK and id or nil, model = model },
    }
  end

  function a:sample()
    local ok, result = pcall(sample)
    if not ok then return failed('earth_interface_error', tostring(result)) end
    return result
  end
  return a
end

return M
