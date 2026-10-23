local location = require('beamngEarthEnduro/location')
local stages = require('beamngEarthEnduro/stages')
local M = { FILE = '/settings/beamngEarthEnduro/config.json' }

function M.defaults()
  -- A new profile starts at the first stage's start. Each caller receives a fresh table.
  -- A base in config.json replaces it, which is handy for testing a start somewhere else.
  return {
    base = stages.first().start,
    resumeRadiusMetres = 50,
  }
end

function M.validate(data)
  if type(data) ~= 'table' or not location.valid(data.base) then return nil, 'base_coordinates' end
  local radius = data.resumeRadiusMetres == nil and 50 or data.resumeRadiusMetres
  if not location.finite(radius) or radius < 1 or radius > 1000 then return nil, 'verification_radius' end
  return { base = location.copy(data.base), resumeRadiusMetres = radius }
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
