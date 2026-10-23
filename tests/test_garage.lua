local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local G = require('beamngEarthEnduro/garage')

local function vehicle(id)
  return { getID = function() return id end, getJBeamFilename = function() return 'pickup' end }
end
local replaced
local function env(overrides)
  local e = {
    vehicle = function() return vehicle(7) end,
    objects = function() return { [7] = { damage = 1234 } } end,
    manager = function() return { getVehicleData = function(id) return id == 7 and { config = { model = 'pickup', parts = {} } } or nil end } end,
    vehicles = function() return { replaceVehicle = function(model, options, veh) replaced = { model = model, options = options, veh = veh } end } end,
  }
  for k, v in pairs(overrides or {}) do e[k] = v end
  return e
end

local g = G.new(env())
local info = g:inspect()
T.eq(info.id, 7, 'reads the player vehicle id'); T.eq(info.damage, 1234, 'reads damage from map.objects')
T.check(g:repair(), 'repair accepted'); T.eq(replaced.model, 'pickup', 'respawns the same model')
T.eq(replaced.options.config.model, 'pickup', 'respawns with the current parts config'); T.eq(replaced.veh:getID(), 7, 'replaces the player vehicle in place')

local _, why = G.new(env({ vehicle = function() return nil end })):inspect()
T.eq(why, 'vehicle_required', 'no vehicle, no quote')
_, why = G.new(env({ objects = function() return {} end })):inspect()
T.eq(why, 'damage_unavailable', 'missing damage reported')
_, why = G.new(env({ objects = function() error('changed') end })):inspect()
T.eq(why, 'damage_unavailable', 'damage read errors contained')
_, why = G.new(env({ objects = function() return { [7] = { damage = 0/0 } } end })):inspect()
T.eq(why, 'damage_unavailable', 'invalid damage rejected')
local ok
ok, why = G.new(env({ vehicles = function() return {} end })):repair()
T.check(not ok, 'missing replaceVehicle fails'); T.eq(why, 'repair_unavailable', 'reason given')
ok, why = G.new(env({ manager = function() return { getVehicleData = function() return nil end } end })):repair()
T.eq(why, 'config_unavailable', 'no config, no repair')
ok, why = G.new(env({ vehicles = function() return { replaceVehicle = function() error('boom') end } end })):repair()
T.check(not ok, 'respawn error contained'); T.eq(why, 'repair_failed', 'respawn error reported')
T.done('garage')
