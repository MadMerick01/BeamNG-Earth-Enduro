local location = require('beamngEarthEnduro/location')
local config = require('beamngEarthEnduro/config')
local persistence = require('beamngEarthEnduro/persistence')
local diagnostics = require('beamngEarthEnduro/diagnostics')
local hud = require('beamngEarthEnduro/hud')
local earthAdapter = require('beamngEarthEnduro/earthAdapter')
local garage = require('beamngEarthEnduro/garage')
local M = {}
-- Faster movement between two readings is treated as a teleport, not driving (150 m/s = 540 km/h).
local MAX_DRIVING_SPEED = 150
-- Money earned per kilometre of counted driving, and the amount the HUD test button adds.
local EARNINGS_PER_KM = 50
local TEST_MONEY = 10000
local MAX_BALANCE = 9007199254740991
-- Repair pricing from the vehicle's overall damage (BeamNG's own traffic code treats about 50 as a
-- scratch, 1000 as moderate and 30000 as major). Tune these after testing in game.
local REPAIR_MIN_DAMAGE = 50
local REPAIR_CALLOUT_FEE = 100
local REPAIR_COST_PER_DAMAGE = 0.5
local MAX_REPAIR_COST = 20000

-- Whole-dollar price to repair a vehicle with this much damage; 0 means nothing to repair.
function M.repairCost(damage)
  if type(damage) ~= 'number' or damage ~= damage or damage < REPAIR_MIN_DAMAGE then return 0 end
  return math.min(MAX_REPAIR_COST, math.floor(REPAIR_CALLOUT_FEE + damage * REPAIR_COST_PER_DAMAGE + 0.5))
end

local function dollars(amount)
  local text = tostring(math.floor(amount))
  repeat
    local n
    text, n = text:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
  until n == 0
  return '$' .. text
end

local labels = {
  CONFIG_REQUIRED = 'BASE CONFIGURATION REQUIRED', EARTH_UNAVAILABLE = 'EARTH UNAVAILABLE',
  READY = 'READY', ERROR = 'SAVE UNAVAILABLE',
}
local messages = {
  earth_missing = 'Enable BeamNG.Earth to continue.',
  earth_starting = 'Waiting for BeamNG.Earth to finish starting.',
  earth_level_required = 'Load the BeamNG.Earth Freeroam level to continue.',
  earth_interface_error = 'Earth information is unavailable. Reload Enduro when Earth is ready.',
  vehicle_required = 'Enter an active vehicle to continue.',
  position_invalid = 'Waiting for a valid geographic position.',
}

-- Controller dependencies permit deterministic headless tests. No game globals below this factory.
function M.new(deps)
  local c = {
    state = 'CONFIG_REQUIRED', clock = 0, sessionVerified = false,
    diag = diagnostics.new(deps.log), adapter = deps.adapter,
    store = persistence.new(deps.io), ui = hud.new(deps.trigger),
    feedback = 'Not saved this session.', garage = deps.garage,
  }

  function c:transition(nextState, reason)
    if self.state == nextState and self.reason == reason then return end
    self.state, self.reason = nextState, reason
    self.diag:event('state', nextState .. ':' .. tostring(reason or ''))
  end

  function c:reload()
    self.adapter:invalidate()
    self.sessionVerified, self.lastSample, self.error, self.odometer = false, nil, nil, nil
    self.earningsCarry = 0
    self.quote, self.repairFeedback = nil, nil
    self.configuration, self.configError = config.load(deps.io)
    self.diag:event('configuration', self.configuration and 'loaded' or self.configError, self.configuration and 'I' or 'W')
    self.profile, self.loadStatus = self.store:load()
    self.diag:event('save_loaded_or_rejected', self.loadStatus, self.profile and 'I' or 'W')
    self.feedback = self.loadStatus == 'recovered' and 'Recovered the last readable save.' or 'Not saved this session.'
    if self.loadStatus ~= 'missing' and not self.profile then self.error = self.loadStatus end
    self.savedDistanceKm = self.profile and self.profile.progression.totalDistanceKm or 0
    self.savedBalance = self.profile and self.profile.progression.balance or 0
    self.mode = self.profile and 'resume' or 'start'
    self.creationBase = location.copy(self.profile and self.profile.base or self.unsavedBase
      or (self.configuration and self.configuration.base))
    self.startupTarget = location.copy(self.profile and self.profile.resume or self.creationBase)
    if self.startupTarget then
      self.diag:event('target', self.mode .. ':' .. string.format('%.8f,%.8f', self.startupTarget.latitude, self.startupTarget.longitude))
    end
    if not self.configuration then self:transition('CONFIG_REQUIRED', 'configuration')
    elseif self.error then self:transition('ERROR', self.error)
    else self:transition('EARTH_UNAVAILABLE', 'position_invalid') end
  end

  function c:interrupt(reason)
    self.odometer = nil
    if self.configuration and not self.error then self:transition('EARTH_UNAVAILABLE', reason) end
  end

  function c:endMission()
    self.sessionVerified, self.lastSample = false, nil
    self:interrupt('earth_level_required')
    self.adapter:invalidate()
  end

  -- The balance is whole dollars; fractions of a dollar carry over in memory until they add up.
  function c:addMoney(amount)
    local progression = self.profile.progression
    local total = self.earningsCarry + amount
    local whole = math.floor(total)
    self.earningsCarry = total - whole
    progression.balance = math.min(MAX_BALANCE, progression.balance + whole)
  end

  function c:canAfford(amount)
    return self.profile ~= nil and not self.error and type(amount) == 'number' and amount >= 0
      and amount == math.floor(amount) and amount <= self.profile.progression.balance
  end

  -- Every purchase pays through here: refuses when the balance is short, never goes below zero.
  -- Like earnings, the new balance is only kept on disk by Save.
  function c:spend(amount, label)
    if not self:canAfford(amount) then
      self.diag:event('spend_rejected', tostring(label) .. ':' .. tostring(amount), 'W')
      return false
    end
    self.profile.progression.balance = self.profile.progression.balance - amount
    self.diag:event('spend', tostring(label) .. ':' .. tostring(amount))
    return true
  end

  -- Reads the player vehicle's damage now and prices it. Returns the inspection and cost, or nil and a reason.
  function c:priceRepair()
    if not self.profile or self.error then return nil, 'unavailable' end
    if not self.garage then return nil, 'repair_unavailable' end
    local vehicle, why = self.garage:inspect()
    if not vehicle then return nil, why end
    return vehicle, M.repairCost(vehicle.damage)
  end

  local repairMessages = {
    unavailable = 'Repairs are unavailable right now. Check the status above.',
    vehicle_required = 'Enter a vehicle to get a repair quote.',
  }
  local function repairProblem(why)
    return repairMessages[why] or 'Could not read the vehicle damage. Try again in a moment.'
  end

  function c:requestRepairQuote()
    local vehicle, cost = self:priceRepair()
    if not vehicle then
      self.quote, self.repairFeedback = nil, repairProblem(cost)
      self.diag:event('repair_quote_failed', tostring(cost), 'W')
      return false
    end
    self.diag:event('repair_quote', string.format('%.1f damage, %d', vehicle.damage, cost))
    if cost == 0 then
      self.quote, self.repairFeedback = nil, 'No damage to repair.'
      return true
    end
    self.quote = { vehicleId = vehicle.id, cost = cost }
    self.repairFeedback = self:canAfford(cost) and 'Press Repair to fix every damaged part.'
      or ('Not enough money yet. You need ' .. dollars(cost - self.profile.progression.balance) .. ' more.')
    return true
  end

  -- Charges the quoted price and repairs. A changed vehicle or new damage needs a fresh quote first,
  -- and the player is only charged once the game has accepted the repair.
  function c:repairVehicle()
    if not self.quote then
      self.repairFeedback = 'Get a repair quote first.'
      return false
    end
    local vehicle, cost = self:priceRepair()
    if not vehicle then
      self.quote, self.repairFeedback = nil, repairProblem(cost)
      self.diag:event('repair_rejected', tostring(cost), 'W')
      return false
    end
    if vehicle.id ~= self.quote.vehicleId or cost ~= self.quote.cost then
      self.quote = nil
      self:requestRepairQuote()
      if self.quote then
        self.repairFeedback = 'The damage changed, so the quote was updated. Press Repair again to accept it.'
      end
      return false
    end
    if not self:canAfford(cost) then
      self.repairFeedback = 'Not enough money. You need ' .. dollars(cost - self.profile.progression.balance) .. ' more.'
      self.diag:event('repair_rejected', 'insufficient_funds', 'W')
      return false
    end
    local ok, why, detail = self.garage:repair()
    if not ok then
      self.repairFeedback = 'Repair failed. You have not been charged.'
      self.diag:event('repair_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return false
    end
    self:spend(cost, 'repair')
    self.quote = nil
    self.repairFeedback = 'Repaired for ' .. dollars(cost) .. '. Save to keep the new balance.'
    return true
  end

  -- Adds the distance driven since the previous reading. Teleport-sized jumps only move the odometer.
  function c:addMileage(sample, dt)
    if self.odometer and location.finite(dt) and dt > 0 then
      local metres = location.distance(self.odometer, sample)
      if metres and metres <= MAX_DRIVING_SPEED * dt then
        self.profile.progression.totalDistanceKm = self.profile.progression.totalDistanceKm + metres / 1000
        self:addMoney(metres / 1000 * EARNINGS_PER_KM)
      end
    end
    self.odometer = location.copy(sample)
  end

  function c:observe(sample, dt)
    self.lastSample = sample
    self.diag:event('earth', tostring(sample.reason or 'available') .. ':' .. tostring(sample.detail or sample.source or ''))
    if not self.configuration then self:transition('CONFIG_REQUIRED', 'configuration'); return end
    if self.error then self:transition('ERROR', self.error); return end
    if not sample.valid or not location.valid(sample) then
      self:interrupt(sample.reason or 'position_invalid'); return
    end
    -- Any valid vehicle position starts the session: saving and mileage work wherever the vehicle is.
    if not self.profile then
      self.profile = persistence.newProfile(self.creationBase, sample, sample.vehicle)
      self.unsavedBase = location.copy(self.profile.base)
      self.diag:event('profile_initialised', 'default (in memory, not yet saved)')
    end
    self.sessionVerified = true
    self:addMileage(sample, dt)
    self:transition('READY', 'verified')
  end

  function c:view()
    local current = self.lastSample and self.lastSample.valid and location.copy(self.lastSample) or nil
    -- The last location written to disk, shown for reference only.
    local target = self.profile and self.profile.generation > 0 and self.profile.resume or nil
    local base = location.copy(self.profile and self.profile.base or self.creationBase)
    local status = messages[self.reason]
    -- A quote only stands for the vehicle it was made for.
    local quote = self.quote
    local vehicleId = self.lastSample and self.lastSample.valid and self.lastSample.vehicle and self.lastSample.vehicle.id
    if quote and (self.error or vehicleId ~= quote.vehicleId) then quote = nil end
    if self.state == 'CONFIG_REQUIRED' then
      status = 'Set valid base coordinates in the Enduro configuration, then choose Reload Enduro.'
    elseif self.state == 'ERROR' then
      status = 'Your saved progress has been protected. Check your save files, then choose Reload Enduro.'
    elseif self.state == 'READY' then status = 'Session active. Save manually to keep your current location.'
    elseif not status then status = messages.position_invalid end
    return {
      state = self.state, stateLabel = labels[self.state], mode = self.mode,
      sessionStatus = status,
      base = base,
      target = location.copy(target), current = current,
      distanceMetres = current and target and location.distance(current, target) or nil,
      baseDistanceMetres = current and location.distance(current, base) or nil,
      vehicle = current and self.lastSample.vehicle and {
        model = self.lastSample.vehicle.model, id = self.lastSample.vehicle.id,
      } or nil,
      balance = self.profile and self.profile.progression.balance or 0,
      totalDistanceKm = self.profile and self.profile.progression.totalDistanceKm or 0,
      unsavedDistanceKm = self.profile and math.max(0, self.profile.progression.totalDistanceKm - self.savedDistanceKm) or 0,
      unsavedBalance = self.profile and math.max(0, self.profile.progression.balance - self.savedBalance) or 0,
      unsavedSpending = self.profile and math.max(0, self.savedBalance - self.profile.progression.balance) or 0,
      testMoneyAllowed = self.profile ~= nil and not self.error,
      repairQuoteAllowed = self.profile ~= nil and not self.error and self.garage ~= nil,
      repairQuote = quote and quote.cost or nil,
      repairAllowed = quote ~= nil,
      repairFeedback = self.repairFeedback,
      saveAllowed = self.state == 'READY',
      saveFeedback = self.feedback,
    }
  end

  function c:tick(dtReal)
    local dt = location.finite(dtReal) and math.max(0, dtReal) or 0
    self.clock = self.clock + dt
    self:observe(self.adapter:sample(), dt)
    self.ui:publish(self:view(), self.clock)
  end

  function c:manualSave()
    if self.state ~= 'READY' or not self.profile or self.error then
      self.feedback = 'Save is unavailable right now. Check the status above.'
      self.diag:event('manual_save_rejected', tostring(self.state), 'W')
      return false
    end
    -- Read the vehicle position at click time so the saved location is current.
    local fresh = self.adapter:sample()
    if not fresh.valid or not location.valid(fresh) then
      self.lastSample = fresh
      self:interrupt(fresh.reason or 'position_invalid')
      self.feedback = 'Save paused. Waiting for a valid vehicle position.'
      self.diag:event('manual_save_rejected', fresh.reason or 'position_invalid', 'W')
      return false
    end
    local candidate = {
      schemaVersion = 1, profileId = self.profile.profileId, base = self.profile.base,
      resume = location.copy(fresh), progression = self.profile.progression,
      vehicle = { model = fresh.vehicle and fresh.vehicle.model },
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
    self.savedDistanceKm = saved.progression.totalDistanceKm
    self.savedBalance = saved.progression.balance
    self.feedback = 'Saved successfully.'
    self.diag:clear('manual_save_succeeded'); self.diag:event('manual_save_succeeded', 'generation ' .. saved.generation)
    return true
  end

  -- Testing aid: adds money to the in-memory balance. Like driving earnings, it is kept by Save.
  function c:addTestMoney()
    if not self.profile or self.error then
      self.diag:event('test_money_rejected', tostring(self.state), 'W')
      return false
    end
    self:addMoney(TEST_MONEY)
    self.diag:event('test_money_added', tostring(TEST_MONEY))
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
    active = M.new({ io = gameIO(), adapter = earthAdapter.new(), garage = garage.new(), log = rawget(_G, 'log'),
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
  return safely(function() local c = ensure(); c.diag:event('extension_loaded', 'BeamNG-Earth Enduro Task 004') end)
end
function M.onPreRender(dtReal)
  return safely(function() ensure():tick(dtReal) end)
end
function M.save() return safely(function() return ensure():manualSave() end) end
function M.addTestMoney() return safely(function() return ensure():addTestMoney() end) end
function M.requestRepairQuote() return safely(function() return ensure():requestRepairQuote() end) end
function M.repairVehicle() return safely(function() return ensure():repairVehicle() end) end
function M.reload() return safely(function() ensure():reload() end) end
function M.uiMounted(on) return safely(function() ensure():mount(on == true) end) end
function M.getState() return safely(function() return ensure():view() end) end
function M.onClientStartMission() return M.reload() end
function M.onClientEndMission()
  return safely(function() if active then active:endMission() end end)
end
function M.onFilesChanged(files)
  return safely(function()
    if not active then return end
    for _, f in pairs(type(files) == 'table' and files or {}) do
      if type(f) == 'table' and type(f.filename) == 'string' and f.filename:lower() == config.FILE:lower() then
        active:reload(); return
      end
    end
  end)
end
function M.onExtensionUnloaded() active = nil end -- no implicit save on shutdown

return M
