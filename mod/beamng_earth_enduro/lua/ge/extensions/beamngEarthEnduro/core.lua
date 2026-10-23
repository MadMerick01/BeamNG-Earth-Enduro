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
-- Part pricing: a part's jbeam value, or a flat price when it has none. Parts taken off in the same
-- change are traded in for a share of their value, which can lower the bill but never pays out.
local DEFAULT_PART_PRICE = 250
local PART_TRADE_IN_SHARE = 0.3
-- Driving this far from where the parts were changed, without paying, puts the paid parts back.
local UNPAID_PARTS_DRIVE_LIMIT = 25
-- A fresh start, with no save, puts the player in this car; they upgrade it from there.
local STARTER_MODEL = 'burnside'
local STARTER_CONFIG = 'vehicles/burnside/worldironmanenduro_starter.pc'
M.STARTER_MODEL, M.STARTER_CONFIG = STARTER_MODEL, STARTER_CONFIG

-- Whole-dollar price to repair a vehicle with this much damage; 0 means nothing to repair.
function M.repairCost(damage)
  if type(damage) ~= 'number' or damage ~= damage or damage < REPAIR_MIN_DAMAGE then return 0 end
  return math.min(MAX_REPAIR_COST, math.floor(REPAIR_CALLOUT_FEE + damage * REPAIR_COST_PER_DAMAGE + 0.5))
end

-- Compares the paid-for parts with the fitted ones. Returns { added, removed, cost } or nil when
-- they match; added and removed list { name, price }.
function M.partsDiff(owned, fitted)
  local added, removed, seen = {}, {}, {}
  local function price(snapshot, part)
    local value = snapshot.values and snapshot.values[part]
    return math.floor((value or DEFAULT_PART_PRICE) + 0.5)
  end
  local function name(snapshot, part) return snapshot.names and snapshot.names[part] or part end
  local function compare(slot)
    if seen[slot] then return end
    seen[slot] = true
    local before, after = owned.parts[slot] or '', fitted.parts[slot] or ''
    if before == after then return end
    if after ~= '' then added[#added + 1] = { name = name(fitted, after), price = price(fitted, after) } end
    if before ~= '' then removed[#removed + 1] = { name = name(owned, before), price = price(owned, before) } end
  end
  for slot in pairs(owned.parts) do compare(slot) end
  for slot in pairs(fitted.parts) do compare(slot) end
  if #added == 0 and #removed == 0 then return nil end
  local byName = function(a, b) return a.name < b.name end
  table.sort(added, byName); table.sort(removed, byName)
  local total = 0
  for _, part in ipairs(added) do total = total + part.price end
  for _, part in ipairs(removed) do total = total - part.price * PART_TRADE_IN_SHARE end
  return { added = added, removed = removed, cost = math.max(0, math.floor(total + 0.5)) }
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
  READY = 'READY', ERROR = 'ENDURO PAUSED',
}
local messages = {
  earth_missing = 'Enable BeamNG.Earth to continue.',
  earth_starting = 'Waiting for BeamNG.Earth to finish starting.',
  earth_level_required = 'Load the BeamNG.Earth Freeroam level to continue.',
  earth_interface_error = 'Earth information is unavailable. Reload Enduro when Earth is ready.',
  vehicle_required = 'Enter an active vehicle to continue.',
  position_invalid = 'Waiting for a valid geographic position.',
}
-- What the player sees for each problem that pauses Enduro.
local errorMessages = {
  newer_version = 'Your save was made by a newer version of Enduro. Update the mod to keep playing.',
  storage_unavailable = 'Enduro could not open its save folder. Press Reload Enduro to try again.',
  internal_error = 'Enduro hit a problem and paused. Press Reload Enduro to carry on from your last save.',
}
local loadMessages = {
  loaded = 'Loaded your last save.',
  missing = 'No save yet. Press Save to keep your progress.',
  unreadable = 'Your save file could not be read, so this is a fresh start. Saving will replace it.',
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
    self.partsFeedback = nil
    self.vehicleProvided, self.arrivingModel = false, nil
    self.configuration, self.configError = config.load(deps.io)
    self.diag:event('configuration', self.configuration and 'loaded' or self.configError, self.configuration and 'I' or 'W')
    self.profile, self.loadStatus = self.store:load()
    self.diag:event('save_loaded_or_rejected', self.loadStatus, self.profile and 'I' or 'W')
    self.feedback = loadMessages[self.loadStatus] or ''
    if not self.profile and not loadMessages[self.loadStatus] then self.error = self.loadStatus end
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
    if self.pendingParts then
      self.repairFeedback = 'Buy or revert your part changes first. Their bill includes the repair.'
      return false
    end
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

  -- Parts. The parts menu is BeamNG's own and changes parts for free; every change respawns the
  -- vehicle, so the HUD compares the fitted parts with the ones paid for after each spawn. The
  -- difference is billed on Buy, or the paid parts are put back on Revert. The respawn also mends
  -- all damage, so the bill includes the repair the car needed just before its first change.
  function c:vehicleSpawned()
    self.partsCheckDue = true
  end

  -- Adopts the fitted parts as paid for, when there is nothing to charge against.
  function c:adoptParts(snapshot)
    self.ownedParts, self.pendingParts = snapshot, nil
    self.diag:event('parts_owned', tostring(snapshot.model) .. ' #' .. tostring(snapshot.id))
  end

  function c:checkParts()
    local snapshot = self.garage:parts()
    if not snapshot then return false end
    self.fittedParts = snapshot
    local owned = self.ownedParts
    -- The starter or saved car comes as paid for, even when it replaced a car of the same model.
    if self.arrivingModel and snapshot.model == self.arrivingModel then
      self.arrivingModel = nil
      self:adoptParts(snapshot)
      return true
    end
    -- Buying vehicles is not part of Enduro yet, so a different vehicle or model is simply taken as owned.
    if not self.profile or self.error or not owned or owned.id ~= snapshot.id or owned.model ~= snapshot.model then
      self:adoptParts(snapshot)
      return true
    end
    local diff = M.partsDiff(owned, snapshot)
    if not diff then
      if self.pendingParts then self.partsFeedback = 'Part changes undone. Nothing to pay.' end
      self.pendingParts = nil
      return true
    end
    local previous = self.pendingParts
    local repair = previous and previous.repair
      or (self.lastDamage and self.lastDamage.id == snapshot.id and M.repairCost(self.lastDamage.damage)) or 0
    local position = previous and previous.position
      or (self.lastSample and self.lastSample.valid and location.copy(self.lastSample)) or nil
    self.pendingParts = {
      id = snapshot.id, added = diff.added, removed = diff.removed, partsCost = diff.cost,
      repair = repair, cost = diff.cost + repair, position = position,
    }
    self.quote = nil
    self.partsFeedback = self:canAfford(self.pendingParts.cost) and 'Press Buy to keep these parts, or Revert.'
      or ('Not enough money. You need ' .. dollars(self.pendingParts.cost - self.profile.progression.balance)
        .. ' more. Revert, or the parts go back when you drive off.')
    self.diag:event('parts_quote', string.format('%d parts, %d repair', diff.cost, repair))
    return true
  end

  -- Called every tick: checks parts after a spawn or vehicle switch, notes the damage the vehicle has
  -- before a change, and puts the paid parts back if the player drives off without paying.
  function c:watchParts()
    if not self.garage then return end
    local vehicleId = self.lastSample and self.lastSample.valid and self.lastSample.vehicle and self.lastSample.vehicle.id
    if vehicleId ~= nil and self.ownedParts and vehicleId ~= self.ownedParts.id then self.partsCheckDue = true end
    if not self.ownedParts then self.partsCheckDue = true end
    if self.partsCheckDue then
      -- Damage is frozen until the check: the respawn has already reset it.
      if self:checkParts() then self.partsCheckDue = false end
      return
    end
    local inspected = self.garage:inspect()
    if inspected then self.lastDamage = inspected end
    local pending = self.pendingParts
    if pending and self.lastSample and self.lastSample.valid then
      if not pending.position then pending.position = location.copy(self.lastSample)
      else
        local moved = location.distance(pending.position, self.lastSample)
        -- A failed revert is retried after another stretch of driving, not every frame.
        if moved and moved > UNPAID_PARTS_DRIVE_LIMIT and not self:revertParts(true) then
          pending.position = location.copy(self.lastSample)
        end
      end
    end
  end

  -- Confirms the bill still matches what is fitted. Returns the pending change, or nil after re-quoting.
  local function currentBill(self)
    local pending = self.pendingParts
    if not pending then
      self.partsFeedback = 'No part changes to pay for.'
      return nil
    end
    local before = pending.cost
    if not self:checkParts() then
      self.partsFeedback = 'Could not read the fitted parts. Try again in a moment.'
      return nil
    end
    if not self.pendingParts then return nil end
    if self.pendingParts.cost ~= before then
      self.partsFeedback = 'The parts changed, so the bill was updated. Press Buy again to accept it.'
      return nil
    end
    return self.pendingParts
  end

  function c:buyParts()
    if not self.profile or self.error then
      self.partsFeedback = 'Buying parts is unavailable right now. Check the status above.'
      return false
    end
    local pending = currentBill(self)
    if not pending then return false end
    if not self:spend(pending.cost, 'parts') then
      self.partsFeedback = 'Not enough money. You need ' .. dollars(pending.cost - self.profile.progression.balance) .. ' more.'
      return false
    end
    self:adoptParts(self.fittedParts)
    self.partsFeedback = 'Bought for ' .. dollars(pending.cost) .. '. Save to keep the new balance.'
    return true
  end

  -- Respawns the vehicle with the paid parts. The change already mended the damage, so the repair
  -- part of the bill is still charged, as far as the balance allows.
  function c:revertParts(droveOff)
    local pending = self.pendingParts
    if not pending or not self.ownedParts then
      self.partsFeedback = 'No part changes to revert.'
      return false
    end
    local ok, why, detail = self.garage:repair(self.ownedParts.config)
    if not ok then
      self.partsFeedback = 'Could not put the paid parts back. Try again in a moment.'
      self.diag:event('parts_revert_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return false
    end
    self.pendingParts = nil
    local charged = self.profile and math.min(pending.repair, self.profile.progression.balance) or 0
    if charged > 0 then self:spend(charged, 'repair') end
    self.partsFeedback = (droveOff and 'You drove off without paying, so the paid parts were put back.'
      or 'The paid parts were put back.') .. (charged > 0 and (' The repair cost ' .. dollars(charged) .. '.') or '')
    return true
  end

  -- Once per load, the first vehicle Enduro sees is swapped, where it stands, for the car of the
  -- last save, or the starter car on a fresh start. Like money, part changes since the last Save
  -- are undone by a reload. A save without a car config leaves the vehicle alone.
  function c:provideVehicle()
    if self.vehicleProvided or not self.garage or self.state ~= 'READY' then return end
    self.vehicleProvided = true
    local model, config, label
    if self.mode == 'start' then
      model, config, label = STARTER_MODEL, STARTER_CONFIG, 'starter_car'
    else
      config = self.profile and self.profile.vehicle and self.profile.vehicle.config
      if not config then return end
      model, label = config.model, 'saved_car'
    end
    self.arrivingModel = model
    local ok, why, detail = self.garage:spawnConfig(model, config)
    if not ok then
      self.arrivingModel = nil
      self.diag:event(label .. '_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return
    end
    if why == 'already_fitted' then self.arrivingModel = nil end
    self.diag:event(label, why or 'spawned')
  end

  -- The car Save keeps: the paid-for parts, with the paint and tuning fitted now. Only the fields
  -- a respawn needs are kept; nil when the game's config cannot be stored as plain data.
  function c:savedVehicleConfig()
    local owned = self.ownedParts
    if not owned or type(owned.config) ~= 'table' then return nil end
    local source, look = owned.config, owned.config
    local fitted = self.fittedParts
    if fitted and fitted.id == owned.id and type(fitted.config) == 'table' then look = fitted.config end
    local config = persistence.plainConfig({ model = source.model or owned.model, parts = source.parts,
      partsTree = source.partsTree, vars = look.vars, paints = look.paints, licenseName = look.licenseName })
    if not config then self.diag:event('vehicle_config_unsaved', tostring(owned.model), 'W') end
    return config
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
      status = errorMessages[self.error] or errorMessages.internal_error
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
      repairAllowed = quote ~= nil and not self.pendingParts,
      repairFeedback = self.repairFeedback,
      partsChange = self.pendingParts and {
        added = self.pendingParts.added, removed = self.pendingParts.removed,
        partsCost = self.pendingParts.partsCost, repair = self.pendingParts.repair, cost = self.pendingParts.cost,
      } or nil,
      buyPartsAllowed = self.pendingParts ~= nil and self:canAfford(self.pendingParts.cost),
      revertPartsAllowed = self.pendingParts ~= nil,
      partsFeedback = self.partsFeedback,
      saveAllowed = self.state == 'READY',
      saveFeedback = self.feedback,
    }
  end

  function c:tick(dtReal)
    local dt = location.finite(dtReal) and math.max(0, dtReal) or 0
    self.clock = self.clock + dt
    self:observe(self.adapter:sample(), dt)
    self:provideVehicle()
    self:watchParts()
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
      vehicle = { model = fresh.vehicle and fresh.vehicle.model, config = self:savedVehicleConfig() },
    }
    local saved, why = self.store:save(candidate)
    if not saved then
      -- Nothing is lost: the last save is untouched and the session carries on, so Save can be tried again.
      self.feedback = 'Could not save just now. Your last save is still safe. Press Save to try again.'
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
    -- Compact JSON: the pretty writer may round coordinates.
    write = function(path, data) return jsonWriteFile(path, data, false) end,
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
      active.error, active.feedback = 'internal_error', 'Anything since your last save is lost when you reload.'
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
function M.buyParts() return safely(function() return ensure():buyParts() end) end
function M.revertParts() return safely(function() return ensure():revertParts(false) end) end
function M.onVehicleSpawned() return safely(function() if active then active:vehicleSpawned() end end) end
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
