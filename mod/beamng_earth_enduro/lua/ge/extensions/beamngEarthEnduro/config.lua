local location = require('beamngEarthEnduro/location')
local M = { FILE = '/settings/beamngEarthEnduro/config.json' }

function M.defaults()
  -- Permanent first-profile base. Each caller receives a fresh table.
  return {
    base = { latitude = -33.60147222, longitude = 150.82288889 },
    resumeRadiusMetres = 50, stabilitySeconds = 3,
  }
end

function M.validate(data)
  if type(data) ~= 'table' or not location.valid(data.base) then return nil, 'base_coordinates' end
  local radius = data.resumeRadiusMetres == nil and 50 or data.resumeRadiusMetres
  local seconds = data.stabilitySeconds == nil and 3 or data.stabilitySeconds
  if not location.finite(radius) or radius < 1 or radius > 1000 then return nil, 'verification_radius' end
  if not location.finite(seconds) or seconds < 1 or seconds > 60 then return nil, 'stability_interval' end
  return { base = location.copy(data.base), resumeRadiusMetres = radius, stabilitySeconds = seconds }
end

function M.load(io)
  local existsOK, exists = pcall(io.exists, M.FILE)
  if not existsOK or type(exists) ~= 'boolean' then return nil, 'configuration_unreadable' end
  if not exists then return M.defaults() end
  -- A present but invalid/unreadable override must never be ignored or replaced.
  local ok, data = pcall(io.read, M.FILE)
  if not ok or data == nil then return nil, 'configuration_unreadable' end
  return M.validate(data)
end

return M
