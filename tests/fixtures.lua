local F = {}
function F.copy(value)
  if type(value) ~= 'table' then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = F.copy(v) end
  return out
end
function F.position(lat, lon) return { latitude = lat == nil and 0 or lat, longitude = lon == nil and 0 or lon } end
function F.config() return { base = F.position(), resumeRadiusMetres = 50, stabilitySeconds = 3 } end
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
    if io.writeMismatch then io.files[path].resume.latitude = 5 end
    if io.readbackFails then io.readFails = path end
    if io.writeReturnsNil then return nil end
    return true
  end
  return io
end
function F.adapter(pose)
  local a = { pose = pose or F.position(), epoch = 'session:anchor:car', valid = true, vehicle = { id = 1, model = 'pickup' } }
  function a:invalidate() end
  function a:filesChanged() return false end
  function a:sample(_, running)
    if not self.valid or not running then return { valid = false, reason = self.reason or 'earth_transition' } end
    return {
      valid = true, compatible = true, version = '1.5.4-beta', latitude = self.pose.latitude,
      longitude = self.pose.longitude, epoch = self.epoch, vehicle = F.copy(self.vehicle),
    }
  end
  return a
end
function F.controller(options)
  local Core = require('beamngEarthEnduro/core')
  options = options or {}
  local io = options.io or F.io({ ['/settings/beamngEarthEnduro/config.json'] = F.config() })
  local adapter = options.adapter or F.adapter()
  local events, logs = {}, {}
  local c = Core.new({ io = io, adapter = adapter,
    trigger = function(name, view) events[#events + 1] = { name = name, data = F.copy(view) } end,
    log = function(level, tag, message) logs[#logs + 1] = message end })
  return c, io, adapter, events, logs
end
function F.advance(c, seconds)
  for _ = 1, math.ceil(seconds * 10) do c:tick(0.1, 0.1) end
end
return F
