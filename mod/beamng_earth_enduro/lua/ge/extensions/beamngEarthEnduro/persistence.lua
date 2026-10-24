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

-- Copies a saved vehicle config (the game's own config table: model, partsTree, vars, paints),
-- keeping only plain JSON data and refusing anything oversized. Returns nil when unusable.
local MAX_CONFIG_DEPTH, MAX_CONFIG_VALUES = 64, 50000
local function plainConfig(config)
  local count = 0
  local function copy(value, depth)
    count = count + 1
    if count > MAX_CONFIG_VALUES or depth > MAX_CONFIG_DEPTH then return nil, false end
    local kind = type(value)
    if kind == 'string' then return value, #value <= 4096 end
    if kind == 'boolean' then return value, true end
    if kind == 'number' then return value, location.finite(value) end
    if kind ~= 'table' then return nil, false end
    local out = {}
    for k, v in pairs(value) do
      if type(k) ~= 'string' and not (type(k) == 'number' and integer(k, 1)) then return nil, false end
      local item, ok = copy(v, depth + 1)
      if not ok then return nil, false end
      out[k] = item
    end
    return out, true
  end
  if type(config) ~= 'table' or type(config.model) ~= 'string' or config.model == '' then return nil end
  local out, ok = copy(config, 1)
  return ok and out or nil
end
M.plainConfig = plainConfig

function M.validate(s)
  if type(s) ~= 'table' then return nil, 'invalid_document' end
  if s.schemaVersion ~= M.SCHEMA then return nil, 'unsupported_schema' end
  if s.profileId ~= 'default' or not integer(s.generation, 1) then return nil, 'invalid_identity' end
  if not location.valid(s.base) or not location.valid(s.resume) then return nil, 'invalid_coordinates' end
  local p = s.progression
  if type(p) ~= 'table' or not integer(p.balance, 0) or not location.finite(p.totalDistanceKm)
      or p.totalDistanceKm < 0 or p.totalDistanceKm > MAX_INTEGER then return nil, 'invalid_progression' end
  -- Stage clock: seconds driven and penalty seconds; optional, so older saves start at zero.
  for _, field in ipairs({ 'drivingSeconds', 'penaltySeconds' }) do
    local seconds = p[field]
    if seconds ~= nil and (not location.finite(seconds) or seconds < 0 or seconds > MAX_INTEGER) then
      return nil, 'invalid_progression'
    end
  end
  -- Sponsor bonuses paid on this stage; optional, so older saves load (the controller fills it in).
  if p.sponsorBonuses ~= nil and not integer(p.sponsorBonuses, 0) then return nil, 'invalid_progression' end
  if type(s.vehicle) ~= 'table' or not optionalString(s.vehicle.model)
      or not optionalString(s.vehicle.configuration) then return nil, 'invalid_vehicle' end
  local vehicleConfig = nil
  if s.vehicle.config ~= nil then
    vehicleConfig = plainConfig(s.vehicle.config)
    if not vehicleConfig then return nil, 'invalid_vehicle' end
  end
  -- Damage the saved car had and nobody has paid to repair; optional, so older saves load.
  local damage = s.vehicle.damage
  if damage ~= nil and (not location.finite(damage) or damage < 0 or damage > MAX_INTEGER) then
    return nil, 'invalid_vehicle'
  end
  -- The stage the save belongs to, and how that stage stands; all optional, so older saves load.
  -- atStart marks a restarted stage the player has not reached the start of yet.
  if not optionalString(s.stage) then return nil, 'invalid_stage' end
  for _, flag in ipairs({ 'finished', 'gameOver', 'atStart' }) do
    if s[flag] ~= nil and s[flag] ~= true then return nil, 'invalid_stage' end
  end
  -- Stages completed before this one, and the money and car this stage was started with, which
  -- Restart goes back to; all optional, so older saves load. A first stage has no entry.
  local completed = nil
  if s.completedStages ~= nil then
    if type(s.completedStages) ~= 'table' or #s.completedStages > 256 then return nil, 'invalid_stage' end
    completed = {}
    for i, id in ipairs(s.completedStages) do
      if type(id) ~= 'string' or not optionalString(id) then return nil, 'invalid_stage' end
      completed[i] = id
    end
  end
  local entry = nil
  if s.entry ~= nil then
    local e = s.entry
    if type(e) ~= 'table' or not integer(e.balance, 0) or type(e.vehicle) ~= 'table'
        or not optionalString(e.vehicle.model) then return nil, 'invalid_stage' end
    local entryDamage = e.vehicle.damage
    if entryDamage ~= nil and (not location.finite(entryDamage) or entryDamage < 0 or entryDamage > MAX_INTEGER) then
      return nil, 'invalid_stage'
    end
    local entryConfig = nil
    if e.vehicle.config ~= nil then
      entryConfig = plainConfig(e.vehicle.config)
      if not entryConfig then return nil, 'invalid_stage' end
    end
    entry = { balance = e.balance, vehicle = { model = e.vehicle.model, config = entryConfig, damage = entryDamage } }
  end
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
    progression = { balance = p.balance, totalDistanceKm = p.totalDistanceKm,
      drivingSeconds = p.drivingSeconds or 0, penaltySeconds = p.penaltySeconds or 0,
      sponsorBonuses = p.sponsorBonuses },
    vehicle = { model = s.vehicle.model, configuration = s.vehicle.configuration, config = vehicleConfig,
      damage = damage },
    stage = s.stage, finished = s.finished, gameOver = s.gameOver, atStart = s.atStart,
    completedStages = completed, entry = entry,
  }
end

function M.equal(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= 'table' then return a == b end
  for k, v in pairs(a) do if not M.equal(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

function M.newProfile(base, pose, vehicle, stage, balance)
  return {
    schemaVersion = 1, profileId = 'default', generation = 0, stage = stage,
    base = location.copy(base), resume = location.copy(pose),
    progression = { balance = balance or 0, totalDistanceKm = 0, drivingSeconds = 0, penaltySeconds = 0,
      sponsorBonuses = 0 },
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
      stage = candidate.stage, finished = candidate.finished, gameOver = candidate.gameOver, atStart = candidate.atStart,
      completedStages = candidate.completedStages, entry = candidate.entry,
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
