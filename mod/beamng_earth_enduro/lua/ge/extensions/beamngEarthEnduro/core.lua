local location = require('beamngEarthEnduro/location')
local config = require('beamngEarthEnduro/config')
local persistence = require('beamngEarthEnduro/persistence')
local diagnostics = require('beamngEarthEnduro/diagnostics')
local hud = require('beamngEarthEnduro/hud')
local earthAdapter = require('beamngEarthEnduro/earthAdapter')
local M = {}

local labels = {
  CONFIG_REQUIRED = 'BASE CONFIGURATION REQUIRED', EARTH_UNAVAILABLE = 'EARTH UNAVAILABLE',
  START_LOCATION_REQUIRED = 'START LOCATION REQUIRED', RESUME_REQUIRED = 'RESUME REQUIRED',
  VERIFYING_LOCATION = 'VERIFYING LOCATION', READY = 'LOCATION VERIFIED — READY TO CONTINUE', ERROR = 'SAVE UNAVAILABLE',
}
local messages = {
  earth_missing = 'Enable the supported BeamNG.Earth mod to continue.',
  earth_incompatible = 'This Earth installation is not supported by this Enduro prototype.',
  earth_disconnected = 'Start or reconnect the BeamNG.Earth companion server.',
  earth_starting = 'Waiting for BeamNG.Earth to finish starting.',
  earth_level_required = 'Load the BeamNG.Earth Freeroam level to continue.',
  earth_transition = 'Waiting for geographic movement to settle.',
  earth_loading = 'Waiting for the world near your vehicle to settle.',
  earth_stale = 'Waiting for fresh geographic readings.',
  earth_interface_error = 'Earth information is unavailable. Reload Enduro when Earth is ready.',
  vehicle_required = 'Enter an active vehicle to continue.',
  position_invalid = 'Waiting for a valid geographic position.',
  simulation_paused = 'Resume the simulation to verify your location.',
  sample_gap = 'Waiting for continuous geographic readings.',
  vehicle_reset = 'Waiting for your vehicle position to settle.',
}

-- Controller dependencies permit deterministic headless tests. No game globals below this factory.
function M.new(deps)
  local c = {
    state = 'CONFIG_REQUIRED', clock = 0, sessionVerified = false,
    diag = diagnostics.new(deps.log), adapter = deps.adapter,
    store = persistence.new(deps.io), ui = hud.new(deps.trigger),
    feedback = 'Not saved this session.', quietRemaining = 0,
  }

  function c:transition(nextState, reason)
    if self.state == nextState and self.reason == reason then return end
    if self.state == 'VERIFYING_LOCATION' and nextState ~= 'VERIFYING_LOCATION' and nextState ~= 'READY' then
      self.diag:clear('verification_interrupted')
      self.diag:event('verification_interrupted', reason or nextState)
    end
    if nextState == 'VERIFYING_LOCATION' and self.state ~= nextState then
      self.diag:clear('verification_started'); self.diag:event('verification_started', self.mode)
    elseif nextState == 'READY' and self.state ~= nextState then
      self.diag:clear('verification_completed'); self.diag:event('verification_completed', self.mode)
    end
    self.state, self.reason = nextState, reason
    self.diag:event('state', nextState .. ':' .. tostring(reason or ''))
  end

  function c:reload()
    self.adapter:invalidate()
    self.sessionVerified, self.recoveryTarget, self.baseline, self.lastSample, self.sampleEpoch = false, nil, nil, nil, nil
    self.quietRemaining, self.lastRunning, self.error = 0, false, nil
    self.configuration, self.configError = config.load(deps.io)
    self.diag:event('configuration', self.configuration and 'loaded' or self.configError, self.configuration and 'I' or 'W')
    self.profile, self.loadStatus = self.store:load()
    self.diag:event('save_loaded_or_rejected', self.loadStatus, self.profile and 'I' or 'W')
    self.feedback = self.loadStatus == 'recovered' and 'Recovered the last readable save.' or 'Not saved this session.'
    if self.loadStatus ~= 'missing' and not self.profile then self.error = self.loadStatus end
    self.mode = self.profile and 'resume' or 'start'
    self.creationBase = location.copy(self.profile and self.profile.base or self.unsavedBase
      or (self.configuration and self.configuration.base))
    self.startupTarget = location.copy(self.profile and self.profile.resume or self.creationBase)
    if self.configuration then
      self.verifier = location.verifier(self.configuration.resumeRadiusMetres, self.configuration.stabilitySeconds)
    else self.verifier = nil end
    if self.startupTarget then
      self.diag:event('target', self.mode .. ':' .. string.format('%.8f,%.8f', self.startupTarget.latitude, self.startupTarget.longitude))
    end
    if not self.configuration then self:transition('CONFIG_REQUIRED', 'configuration')
    elseif self.error then self:transition('ERROR', self.error)
    else self:transition(self.profile and 'RESUME_REQUIRED' or 'START_LOCATION_REQUIRED', 'arrival') end
  end

  function c:interrupt(reason)
    if self.verifier then self.verifier:reset() end
    self.baseline, self.recoveryTarget = nil, nil
    if self.configuration and not self.error then self:transition('EARTH_UNAVAILABLE', reason) end
  end

  function c:endMission()
    self.sessionVerified, self.sampleEpoch, self.lastSample = false, nil, nil
    self:interrupt('earth_level_required')
    self.adapter:invalidate()
  end

  function c:observe(dt, sample)
    self.lastSample = sample
    self.diag:event('earth', tostring(sample.compatible) .. ':' .. tostring(sample.version) .. ':'
      .. tostring(sample.reason or 'available') .. ':' .. tostring(sample.detail or ''))
    if not self.configuration then self:transition('CONFIG_REQUIRED', 'configuration'); return end
    if self.error then self:transition('ERROR', self.error); return end
    if not location.finite(dt) or dt <= 0 or dt > 1 then
      self:interrupt('sample_gap'); return
    end
    if not sample.valid or not location.valid(sample) or sample.epoch == nil or not sample.vehicle then
      self:interrupt(sample.reason or 'position_invalid'); return
    end
    if self.sampleEpoch and self.sampleEpoch ~= sample.epoch then self:interrupt('earth_transition') end
    self.sampleEpoch = sample.epoch
    if self.state == 'READY' and self.baseline then
      -- Driving away from the verified target is allowed. There is no mileage/economy here.
      self.baseline = { latitude = sample.latitude, longitude = sample.longitude, epoch = sample.epoch }
      return
    end
    local target = self.startupTarget
    if self.sessionVerified then
      -- After initial arrival, recover an interrupted session at a newly stable live position.
      -- This transient target never changes startupTarget, profile.base, or the saved resume.
      self.recoveryTarget = self.recoveryTarget or location.copy(sample)
      if location.distance(sample, self.recoveryTarget) > self.configuration.resumeRadiusMetres then
        self.recoveryTarget = location.copy(sample)
        self.verifier:reset()
      end
      target = self.recoveryTarget
    end
    local verified, distance = self.verifier:step(sample, target, dt, sample.epoch)
    if not distance or distance > self.configuration.resumeRadiusMetres then
      self:transition(self.mode == 'resume' and 'RESUME_REQUIRED' or 'START_LOCATION_REQUIRED', 'arrival')
      return
    end
    if not verified then self:transition('VERIFYING_LOCATION', 'arrival'); return end
    if not self.profile then
      self.profile = persistence.newProfile(self.creationBase, sample, sample.vehicle)
      self.unsavedBase = location.copy(self.profile.base)
      self.diag:event('profile_initialised', 'default (in memory, not yet saved)')
    end
    self.sessionVerified = true
    self.baseline = { latitude = sample.latitude, longitude = sample.longitude, epoch = sample.epoch }
    self:transition('READY', 'verified')
  end

  function c:view()
    local current = self.lastSample and self.lastSample.valid and location.copy(self.lastSample) or nil
    local target = self.startupTarget
    local base = location.copy(self.profile and self.profile.base or self.creationBase)
    local status = messages[self.reason]
    if self.state == 'CONFIG_REQUIRED' then
      status = 'Set valid base coordinates in the Enduro configuration, then choose Reload Enduro.'
    elseif self.state == 'ERROR' then
      status = 'Your saved progress has been protected. Check your save files, then choose Reload Enduro.'
    elseif self.state == 'READY' then status = 'Session active. Save manually to keep your current location.'
    elseif not status then status = 'Remain within the arrival radius while location verification completes.' end
    local instruction
    if not self.sessionVerified and self.startupTarget then
      instruction = self.mode == 'resume' and 'Use BeamNG.Earth to teleport to your saved location.'
        or 'Use BeamNG.Earth to teleport to the displayed base coordinates.'
    elseif self.sessionVerified and self.state ~= 'READY' then
      instruction = 'Wait at a stable location while verification restarts.'
    end
    return {
      state = self.state, stateLabel = labels[self.state], mode = self.mode, arrivalVerified = self.sessionVerified,
      sessionStatus = status, instruction = instruction,
      base = base,
      target = location.copy(target), current = current,
      distanceMetres = current and target and location.distance(current, target) or nil,
      baseDistanceMetres = current and location.distance(current, base) or nil,
      radiusMetres = self.configuration and self.configuration.resumeRadiusMetres or nil,
      stabilitySeconds = self.configuration and self.configuration.stabilitySeconds or nil,
      stableForSeconds = self.state == 'VERIFYING_LOCATION' and self.verifier and self.verifier.elapsed or 0,
      vehicle = current and self.lastSample.vehicle and {
        model = self.lastSample.vehicle.model, id = self.lastSample.vehicle.id,
      } or nil,
      balance = self.profile and self.profile.progression.balance or 0,
      totalDistanceKm = self.profile and self.profile.progression.totalDistanceKm or 0,
      saveAllowed = self.state == 'READY' and self.baseline ~= nil,
      saveFeedback = self.feedback,
    }
  end

  function c:tick(dtReal, dtSim)
    local real = location.finite(dtReal) and math.max(0, dtReal) or 0
    self.clock = self.clock + real
    self.lastRunning = location.finite(dtSim) and dtSim > 0
    self.quietRemaining = math.max(0, self.quietRemaining - real)
    local sample = self.adapter:sample(real, self.lastRunning)
    if self.quietRemaining > 0 then sample = { valid = false, reason = 'vehicle_reset' } end
    self:observe(real, sample)
    self.ui:publish(self:view(), self.clock)
  end

  function c:manualSave()
    if self.state ~= 'READY' or not self.baseline or not self.profile or self.error then
      self.feedback = 'Save is locked until your location is verified.'
      self.diag:event('manual_save_rejected', 'location_not_verified', 'W')
      return false
    end
    -- UI authorization is never trusted; re-read Earth at click time before any write.
    local fresh = self.adapter:sample(0, self.lastRunning)
    if not fresh.valid or not location.valid(fresh) or fresh.epoch ~= self.baseline.epoch
        or not fresh.vehicle or location.distance(fresh, self.baseline) > 25 then
      self.lastSample = fresh
      self:interrupt(fresh.reason or 'earth_transition')
      self.feedback = 'Save paused. Verify your location again.'
      self.diag:event('manual_save_rejected', fresh.reason or 'changed_position', 'W')
      return false
    end
    local candidate = {
      schemaVersion = 1, profileId = self.profile.profileId, base = self.profile.base,
      resume = location.copy(fresh), progression = self.profile.progression,
      vehicle = { model = fresh.vehicle.model, configuration = fresh.vehicle.configuration },
    }
    local saved, why = self.store:save(candidate)
    if not saved then
      self.feedback = 'Save failed. Your previous save is retained. Reload Enduro before trying again.'
      self.error = why
      self:transition('ERROR', why)
      self.diag:clear('manual_save_failed'); self.diag:event('manual_save_failed', why, 'E')
      return false
    end
    self.profile, self.lastSample, self.unsavedBase = saved, fresh, nil
    self.feedback = 'Saved successfully.'
    self.diag:clear('manual_save_succeeded'); self.diag:event('manual_save_succeeded', 'generation ' .. saved.generation)
    return true
  end

  function c:mount(on)
    if self.ui:mount(on, self.clock) then
      self.diag:clear('ui_initialised'); self.diag:event('ui_initialised', 'Enduro HUD')
    end
  end

  c:reload()
  return c
end

local active
local function gameIO()
  return {
    read = function(path) return jsonReadFile(path) end,
    exists = function(path) return FS:fileExists(path) end,
    mkdir = function(path)
      if not FS:directoryExists(path) then FS:directoryCreate(path, true) end
      return FS:directoryExists(path)
    end,
    write = function(path, data) return jsonWriteFile(path, data, true) end,
  }
end
local function ensure()
  if not active then
    active = M.new({ io = gameIO(), adapter = earthAdapter.new(), log = rawget(_G, 'log'),
      trigger = function(event, payload) if guihooks then guihooks.trigger(event, payload) end end })
  end
  return active
end
local function safely(f)
  local ok, result = pcall(f)
  if not ok then
    if active then
      active.error, active.feedback = 'internal_error', 'Enduro paused safely. Choose Reload Enduro.'
      active:transition('ERROR', 'internal_error')
      active.diag:event('internal_error', tostring(result), 'E')
    elseif log then log('E', 'beamngEarthEnduro', tostring(result)) end
    return false
  end
  return result
end

function M.onExtensionLoaded()
  return safely(function() local c = ensure(); c.diag:event('extension_loaded', 'BeamNG-Earth Enduro Task 002') end)
end
function M.onPreRender(dtReal, dtSim)
  return safely(function() ensure():tick(dtReal, dtSim) end)
end
function M.save() return safely(function() return ensure():manualSave() end) end
function M.reload() return safely(function() ensure():reload() end) end
function M.uiMounted(on) return safely(function() ensure():mount(on == true) end) end
function M.getState() return safely(function() return ensure():view() end) end
function M.onClientStartMission() return M.reload() end
function M.onClientEndMission()
  return safely(function() if active then active:endMission() end end)
end
function M.onVehicleResetted(id)
  return safely(function()
    if active and active.lastSample and active.lastSample.vehicle and active.lastSample.vehicle.id == id then
      active.quietRemaining = 0.5
      active:interrupt('vehicle_reset')
    end
  end)
end
function M.onFilesChanged(files)
  return safely(function()
    if not active then return end
    for _, f in pairs(type(files) == 'table' and files or {}) do
      if type(f) == 'table' and type(f.filename) == 'string' and f.filename:lower() == config.FILE:lower() then
        active:reload(); return
      end
    end
    if active.adapter:filesChanged(files) then active:interrupt('earth_transition') end
  end)
end
function M.onExtensionUnloaded() active = nil end -- no implicit save on shutdown

return M
