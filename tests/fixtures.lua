local F = {}
function F.copy(value)
  if type(value) ~= 'table' then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = F.copy(v) end
  return out
end
function F.position(lat, lon) return { latitude = lat == nil and 0 or lat, longitude = lon == nil and 0 or lon } end
function F.config() return { base = F.position(), resumeRadiusMetres = 50 } end
function F.save(generation, lat, lon)
  return {
    schemaVersion = 1, generation = generation or 1, profileId = 'default', base = F.position(),
    resume = F.position(lat, lon), progression = { balance = 0, totalDistanceKm = 0 }, vehicle = { model = 'pickup' },
  }
end
function F.io(files)
  local io = { files = files or {}, writes = 0, directories = 0 }
  io.exists = function(path)
    if io.existsFails then error('permission denied') end
    return io.files[path] ~= nil
  end
  io.read = function(path)
    if io.readFails == path then error('unreadable') end
    return F.copy(io.files[path])
  end
  io.mkdir = function() io.directories = io.directories + 1; return not io.mkdirFails end
  io.write = function(path, data)
    io.writes = io.writes + 1
    if io.writeFails then io.files[path] = 'partial JSON'; return false end
    io.files[path] = F.copy(data)
    if io.writeMismatch then io.files[path].generation = 99 end
    if io.writeRounds then io.files[path].resume.latitude = io.files[path].resume.latitude + 1e-9 end
    if io.readbackFails then io.readFails = path end
    if io.writeReturnsNil then return nil end
    return true
  end
  return io
end
function F.adapter(pose)
  local a = { pose = pose or F.position(), valid = true, vehicle = { id = 1, model = 'pickup' } }
  function a:invalidate() end
  function a:sample()
    if not self.valid then return { valid = false, reason = self.reason or 'vehicle_required' } end
    return {
      valid = true, latitude = self.pose.latitude, longitude = self.pose.longitude, vehicle = F.copy(self.vehicle),
    }
  end
  return a
end
-- Stand-in for the garage: damage to report, fitted parts and whether the game accepts a respawn.
function F.garage()
  local g = { damage = 0, vehicleId = 1, model = 'pickup', repairs = 0, accepts = true,
    fitted = { engine = 'pickup_engine_v8', intake = 'pickup_intake_stock' },
    values = { pickup_engine_v8 = 4000, pickup_intake_stock = 100, pickup_turbo = 2400, pickup_intake_race = 800 } }
  function g:inspect()
    if self.unreadable then return nil, 'damage_unavailable' end
    return { id = self.vehicleId, damage = self.damage }
  end
  function g:parts()
    if self.partsUnreadable then return nil, 'parts_unavailable' end
    local names = {}
    for _, part in pairs(self.fitted) do names[part] = part end
    return { id = self.vehicleId, model = self.model, config = { model = self.model, parts = F.copy(self.fitted) },
      parts = F.copy(self.fitted), values = F.copy(self.values), names = names }
  end
  -- Parts menu stand-in: fits parts for free and respawns, which mends the damage.
  function g:fit(slot, part)
    self.fitted[slot], self.damage = part, 0
  end
  function g:repair(config)
    if not self.accepts then return false, 'repair_failed', 'rejected' end
    self.repairs, self.damage = self.repairs + 1, 0
    if config then self.fitted = F.copy(config.parts) end
    return true
  end
  return g
end
function F.controller(options)
  local Core = require('beamngEarthEnduro/core')
  options = options or {}
  local io = options.io or F.io({ ['/settings/beamngEarthEnduro/config.json'] = F.config() })
  local adapter = options.adapter or F.adapter()
  local garage = options.garage or F.garage()
  local events, logs = {}, {}
  local c = Core.new({ io = io, adapter = adapter, garage = garage,
    trigger = function(name, view) events[#events + 1] = { name = name, data = F.copy(view) } end,
    log = function(level, tag, message) logs[#logs + 1] = message end })
  return c, io, adapter, events, logs, garage
end
function F.advance(c, seconds)
  for _ = 1, math.ceil(seconds * 10) do c:tick(0.1) end
end
return F
