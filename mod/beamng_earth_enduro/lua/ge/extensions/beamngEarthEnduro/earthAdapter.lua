-- The only Enduro module permitted to inspect BeamNG.Earth. Never writes its state,
-- calls teleport, loads/enables Earth, or replaces any upstream function.
local location = require('beamngEarthEnduro/location')
local compatibility = require('beamngEarthEnduro/compatibility')
local M = {}

local function defaults()
  return {
    core = function() return rawget(_G, 'beamngEarth_core') end,
    module = function(name) return package.loaded['beamngEarth/' .. name] end,
    readSource = function(path) return readFile(path) end,
    vehicle = function() return getPlayerVehicle(0) end,
  }
end

local function failed(reason, compatible, version, detail)
  return { valid = false, available = false, reason = reason,
    compatible = compatible or false, version = version, detail = detail }
end
local function vector(p)
  return p and location.finite(p.x) and location.finite(p.y) and location.finite(p.z)
end

-- Dependencies are injectable for stub tests; production always uses the pinned source checker.
function M.new(environment, checkSource)
  local env, sourceCheck = environment or defaults(), checkSource or compatibility.check
  local a = { cachedCore = nil, sourceOK = false, stillClock = 0 }
  function a:invalidate()
    self.cachedCore, self.sourceOK, self.stillClock, self.lastClock = nil, false, 0, nil
  end
  function a:filesChanged(files)
    for _, f in pairs(type(files) == 'table' and files or {}) do
      if type(f) == 'table' and type(f.filename) == 'string'
          and f.filename:lower():find('/lua/ge/extensions/beamngearth/', 1, true) then
        self:invalidate(); return true
      end
    end
    return false
  end
  local function sample(self, dt, running)
    local core = env.core()
    if type(core) ~= 'table' then self:invalidate(); return failed('earth_missing') end
    if core ~= self.cachedCore then
      self.cachedCore = core
      self.sourceOK, self.sourceDetail = sourceCheck(env.readSource)
      self.lastClock, self.stillClock = nil, 0
    end
    if not self.sourceOK then return failed('earth_incompatible', false, nil, self.sourceDetail) end
    for _, name in ipairs({ '_state', 'serverHello', 'serverHealthy', 'dropHoldState' }) do
      if type(core[name]) ~= 'function' then return failed('earth_incompatible', false, nil, 'missing:' .. name) end
    end
    local net, places, lattice, roads = env.module('net'), env.module('places'), env.module('lattice'), env.module('roads')
    if type(net) ~= 'table' or type(net.isConnected) ~= 'function'
        or type(places) ~= 'table' or type(places.here) ~= 'function'
        or type(lattice) ~= 'table' or type(lattice.groundBox) ~= 'function'
        or type(roads) ~= 'table' or type(roads.readyAround) ~= 'function'
        or type(roads.settledFor) ~= 'function' then return failed('earth_incompatible', false) end
    if not net.isConnected() then return failed('earth_disconnected', true, compatibility.version) end
    local hello = core.serverHello()
    if type(hello) ~= 'table' then return failed('earth_starting', true) end
    if hello.serverVersion ~= compatibility.serverReportedVersion or hello.protocol ~= 4 then
      return failed('earth_incompatible', false, tostring(hello.serverVersion), 'server_hello')
    end
    local version = compatibility.version
    local st = core._state()
    if type(st) ~= 'table' or type(st.inOurLevel) ~= 'boolean' or type(st.active) ~= 'boolean' then
      return failed('earth_incompatible', false, version, 'state_shape')
    end
    if not st.inOurLevel then return failed('earth_level_required', true, version) end
    if not st.active or not st.anchor or not st.block or st.sessionId == nil or st.anchorId == nil then
      return failed('earth_starting', true, version)
    end
    if not location.finite(st.clock) or type(st.anchor) ~= 'table'
        or type(st.anchor.enuToGeodetic) ~= 'function' or type(st.block) ~= 'table'
        or not location.finite(st.block.cx) or not location.finite(st.block.cy) then
      return failed('earth_incompatible', false, version, 'anchor_shape')
    end
    if hello.sessionId ~= st.sessionId or st.anchorSession ~= st.sessionId then
      return failed('earth_transition', true, version)
    end
    if self.lastClock == st.clock then self.stillClock = self.stillClock + dt else self.stillClock = 0 end
    self.lastClock = st.clock
    if self.stillClock > 0.5 then return failed('earth_stale', true, version) end
    local hold = core.dropHoldState()
    if type(hold) ~= 'table' or type(hold.active) ~= 'boolean' then
      return failed('earth_incompatible', false, version, 'hold_shape')
    end
    if st.pending or st.randomStart or st.resync or st.rebasing or st.lagProbe or st.placeFrames ~= nil
        or st.floorZ ~= nil or hold.active
        or (st.guard and st.guard.mode ~= 'off' and st.guard.mode ~= 'clear' and st.guard.mode ~= 'air')
        or (location.finite(st.loadingUntil) and st.clock < st.loadingUntil) then
      return failed('earth_transition', true, version)
    end
    if not core.serverHealthy() then return failed('earth_loading', true, version) end
    if not running or st.paused then return failed('simulation_paused', true, version) end
    local vehicle = env.vehicle()
    if not vehicle then return failed('vehicle_required', true, version) end
    local id, pos = vehicle:getID(), vehicle:getPosition()
    if not location.finite(id) or id < 0 or id ~= math.floor(id) or not vector(pos) then
      return failed('position_invalid', true, version)
    end
    local lat, lon = places.here()
    local cached = { latitude = lat, longitude = lon }
    if not location.valid(cached) or type(st.player) ~= 'table'
        or not location.valid({ latitude = st.player.lat, longitude = st.player.lon }) then
      return failed('position_invalid', true, version)
    end
    -- Read the live vehicle through the same committed anchor, then check Earth's last pose.
    -- Do not save an onUpdate cache that still refers to the position before this physics step.
    local liveLat, liveLon = st.anchor:enuToGeodetic(pos.x, pos.y, pos.z)
    local current = { latitude = liveLat, longitude = liveLon }
    if not location.valid(current) or location.distance(cached, current) > 25
        or location.distance(cached, { latitude = st.player.lat, longitude = st.player.lon }) > 0.1 then
      return failed('position_invalid', true, version)
    end
    local x0, y0, x1, y1 = lattice.groundBox(st.block.cx, st.block.cy)
    if not location.finite(x0) or not location.finite(y0) or not location.finite(x1) or not location.finite(y1) then
      return failed('earth_incompatible', false, version, 'bounds_shape')
    end
    if pos.x < x0 + 40 or pos.x > x1 - 40 or pos.y < y0 + 40 or pos.y > y1 - 40
        or not roads.readyAround(st.anchorId, pos.x, pos.y, 50)
        or (roads.enabled ~= false and not roads.settledFor(st.anchorId, pos.x, pos.y)) then
      return failed('earth_loading', true, version)
    end
    local model
    local pathOK, path = pcall(function() return vehicle:getPath() end)
    if pathOK and type(path) == 'string' then model = path:match('^/?vehicles/([^/\\]+)/?') end
    return {
      valid = true, available = true, compatible = true, version = version,
      latitude = current.latitude, longitude = current.longitude,
      epoch = tostring(st.sessionId) .. ':' .. tostring(st.anchorId) .. ':' .. tostring(id),
      vehicle = { id = id, model = model },
    }
  end

  function a:sample(dt, running)
    if not location.finite(dt) or dt < 0 then return failed('position_invalid', self.sourceOK) end
    local ok, result = pcall(sample, self, dt, running)
    if not ok then return failed('earth_interface_error', self.sourceOK, nil, tostring(result)) end
    return result
  end
  return a
end

return M
