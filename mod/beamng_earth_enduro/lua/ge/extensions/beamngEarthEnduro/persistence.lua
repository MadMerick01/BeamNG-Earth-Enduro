-- Two alternating JSON save slots; the newest readable one is loaded. Loading never writes files.
local location = require('beamngEarthEnduro/location')
local M = { DIRECTORY = '/settings/beamngEarthEnduro/', SCHEMA = 1 }
local MAX_INTEGER = 9007199254740991

local function integer(n, minimum)
  return location.finite(n) and n >= minimum and n <= MAX_INTEGER and n == math.floor(n)
end
local function optionalString(s)
  return s == nil or (type(s) == 'string' and #s > 0 and #s <= 512 and not s:find('%c'))
end

function M.validate(s)
  if type(s) ~= 'table' then return nil, 'invalid_document' end
  if s.schemaVersion ~= M.SCHEMA then return nil, 'unsupported_schema' end
  if s.profileId ~= 'default' or not integer(s.generation, 1) then return nil, 'invalid_identity' end
  if not location.valid(s.base) or not location.valid(s.resume) then return nil, 'invalid_coordinates' end
  local p = s.progression
  if type(p) ~= 'table' or not integer(p.balance, 0) or not location.finite(p.totalDistanceKm)
      or p.totalDistanceKm < 0 or p.totalDistanceKm > MAX_INTEGER then return nil, 'invalid_progression' end
  if type(s.vehicle) ~= 'table' or not optionalString(s.vehicle.model)
      or not optionalString(s.vehicle.configuration) then return nil, 'invalid_vehicle' end
  local resume = location.copy(s.resume)
  if s.resume.altitude ~= nil then
    if not location.finite(s.resume.altitude) or s.resume.altitude < -20000
        or s.resume.altitude > 1000000 then return nil, 'invalid_altitude' end
    resume.altitude = s.resume.altitude
  end
  if s.resume.heading ~= nil then
    if not location.finite(s.resume.heading) or s.resume.heading < 0
        or s.resume.heading >= 360 then return nil, 'invalid_heading' end
    resume.heading = s.resume.heading
  end
  return {
    schemaVersion = M.SCHEMA, profileId = 'default', generation = s.generation,
    base = location.copy(s.base), resume = resume,
    progression = { balance = p.balance, totalDistanceKm = p.totalDistanceKm },
    vehicle = { model = s.vehicle.model, configuration = s.vehicle.configuration },
  }
end

function M.equal(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= 'table' then return a == b end
  for k, v in pairs(a) do if not M.equal(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

function M.newProfile(base, pose, vehicle)
  return {
    schemaVersion = 1, profileId = 'default', generation = 0,
    base = location.copy(base), resume = location.copy(pose),
    progression = { balance = 0, totalDistanceKm = 0 },
    vehicle = { model = vehicle and vehicle.model, configuration = vehicle and vehicle.configuration },
  }
end

function M.new(io)
  local store = { generation = 0, slot = nil, blocked = true }
  local paths = { a = M.DIRECTORY .. 'save-a.json', b = M.DIRECTORY .. 'save-b.json' }

  -- Returns the newest readable save, or nil and why: 'missing' (no save files), 'unreadable'
  -- (files exist but none can be read; saving replaces them), 'newer_version' or 'storage_unavailable'.
  function store:load()
    self.generation, self.slot, self.blocked = 0, nil, true
    local valid, unreadable = {}, false
    for _, slot in ipairs({ 'a', 'b' }) do
      local ok, present = pcall(io.exists, paths[slot])
      if not ok or type(present) ~= 'boolean' then return nil, 'storage_unavailable' end
      if present then
        local readOK, data = pcall(io.read, paths[slot])
        -- A save from a newer Enduro is never overwritten, even if the other slot is readable.
        if readOK and type(data) == 'table' and data.schemaVersion ~= nil and data.schemaVersion ~= M.SCHEMA then
          return nil, 'newer_version'
        end
        local save = readOK and M.validate(data) or nil
        if save then valid[#valid + 1] = { slot = slot, data = save } else unreadable = true end
      end
    end
    self.blocked = false
    if #valid == 0 then return nil, unreadable and 'unreadable' or 'missing' end
    table.sort(valid, function(a, b)
      if a.data.generation ~= b.data.generation then return a.data.generation > b.data.generation end
      return a.slot < b.slot
    end)
    local best = valid[1]
    self.generation, self.slot = best.data.generation, best.slot
    return best.data, 'loaded'
  end

  -- Writes the slot not holding the newest save, so a failed write never touches it. A failure
  -- changes nothing here, so Save can simply be tried again.
  function store:save(candidate)
    if self.blocked then return nil, 'storage_locked' end
    if self.generation >= MAX_INTEGER then return nil, 'generation_limit' end
    -- Build a new value: never change the caller's profile.
    local prepared = {
      schemaVersion = candidate.schemaVersion, profileId = candidate.profileId,
      generation = self.generation + 1, base = candidate.base, resume = candidate.resume,
      progression = candidate.progression, vehicle = candidate.vehicle,
    }
    local clean, why = M.validate(prepared)
    if not clean then return nil, why end
    local dirOK, made = pcall(io.mkdir, M.DIRECTORY)
    if not dirOK or made == false then return nil, 'directory_failed' end
    local slot = self.slot == 'a' and 'b' or 'a'
    local ok, result = pcall(io.write, paths[slot], clean)
    if not ok or result == false then return nil, 'write_failed' end
    -- The file must read back as a valid save of this generation. Decimals are not compared
    -- exactly, because the game's JSON writer may round them.
    local readOK, readback = pcall(io.read, paths[slot])
    local checked = readOK and M.validate(readback) or nil
    if not checked or checked.generation ~= clean.generation
        or checked.progression.balance ~= clean.progression.balance then
      return nil, 'verification_failed'
    end
    self.slot, self.generation = slot, clean.generation
    return clean, 'saved'
  end
  return store
end

return M
