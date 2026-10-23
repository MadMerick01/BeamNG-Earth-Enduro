local location = require('beamngEarthEnduro/location')
local config = require('beamngEarthEnduro/config')
local persistence = require('beamngEarthEnduro/persistence')
local diagnostics = require('beamngEarthEnduro/diagnostics')
local hud = require('beamngEarthEnduro/hud')
local earthAdapter = require('beamngEarthEnduro/earthAdapter')
local garage = require('beamngEarthEnduro/garage')
local stages = require('beamngEarthEnduro/stages')
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
-- Car pricing: a car config's game Value, or a flat price when it has none. The car you leave is
-- traded in for a share of its Value, less the repair it needs; a trade-in is never below $0.
local DEFAULT_CAR_PRICE = 10000
local CAR_TRADE_IN_SHARE = 0.5
-- A fresh start, with no save, puts the player in this car; they upgrade it from there.
local STARTER_MODEL = 'burnside'
local STARTER_CONFIG = 'vehicles/burnside/worldironmanenduro_starter.pc'
M.STARTER_MODEL, M.STARTER_CONFIG = STARTER_MODEL, STARTER_CONFIG
-- Ironman: a car with this much damage counts as wrecked (a third of what BeamNG calls major
-- damage). When a wrecked car's repair costs more than the balance, the run is over unless the
-- player can pay within GAME_OVER_DELAY seconds; then the only way on is to restart the stage.
local WRECKED_DAMAGE = 10000
local GAME_OVER_DELAY = 10
M.WRECKED_DAMAGE, M.GAME_OVER_DELAY = WRECKED_DAMAGE, GAME_OVER_DELAY
-- Stage clock: a repair or a new car costs the player this many seconds. One frame never adds more
-- than MAX_CLOCK_STEP, so a loading stall or a teleport hitch does not eat into the time limit.
local PENALTY_SECONDS = 300
local MAX_CLOCK_STEP = 0.5
local PENALTY_SHOWN_FOR = 8
M.PENALTY_SECONDS = PENALTY_SECONDS

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
  READY = 'READY', ERROR = 'RALLY PAUSED',
}
-- What the HUD asks of the player until they reach the resume point.
local goLabels = { resume = 'GO TO YOUR LAST SAVE', start = 'GO TO THE START' }
local goMessages = {
  resume = 'Copy these coordinates, paste them into the BeamNG.Earth map and teleport there to carry on your enduro.',
  start = 'Copy these coordinates, paste them into the BeamNG.Earth map and teleport there to start your enduro. You get your starter car when you arrive.',
}
local arrivedMessages = {
  resume = "You're in the right place. Continue your trek, and press Save to keep your progress.",
  start = "You're at the start. Begin your trek, and press Save to keep your progress.",
}
local messages = {
  earth_missing = 'Enable BeamNG.Earth to continue.',
  earth_starting = 'Waiting for BeamNG.Earth to finish starting.',
  earth_level_required = 'Load the BeamNG.Earth Freeroam level to continue.',
  earth_interface_error = 'Earth information is unavailable. Reload rally when Earth is ready.',
  vehicle_required = 'Enter an active vehicle to continue.',
  position_invalid = 'Waiting for a valid geographic position.',
}
-- What the player sees for each problem that pauses Enduro.
local errorMessages = {
  newer_version = 'Your save was made by a newer version of the rally mod. Update the mod to keep playing.',
  storage_unavailable = 'The rally could not open its save folder. Press Reload rally to try again.',
  internal_error = 'The rally hit a problem and paused. Press Reload rally to carry on from your last save.',
  unknown_stage = 'Your save is for a stage this version does not have. Update the mod to keep playing.',
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
    paused = deps.paused or function() return false end,
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
    self.partsFeedback, self.carFeedback = nil, nil
    self.vehicleProvided, self.arrivingModel, self.arrivingValue, self.arrived = false, nil, nil, false
    self.wreck, self.restartArmed, self.penalty = nil, false, nil
    self.configuration, self.configError = config.load(deps.io)
    self.diag:event('configuration', self.configuration and 'loaded' or self.configError, self.configuration and 'I' or 'W')
    self.profile, self.loadStatus = self.store:load()
    self.diag:event('save_loaded_or_rejected', self.loadStatus, self.profile and 'I' or 'W')
    self.feedback = loadMessages[self.loadStatus] or ''
    if not self.profile and not loadMessages[self.loadStatus] then self.error = self.loadStatus end
    -- Saves from before stages belong to the first stage.
    local stageId = self.profile and self.profile.stage
    self.stage = stageId and stages.get(stageId) or (not stageId and stages.first()) or nil
    if not self.stage and not self.error then self.error = 'unknown_stage' end
    self.stageFinished = self.profile ~= nil and self.profile.finished == true
    self.gameOver = self.profile ~= nil and self.profile.gameOver == true
    self.savedDistanceKm = self.profile and self.profile.progression.totalDistanceKm or 0
    -- Before the first save the stage's starting money counts as saved, since it was not earned.
    self.savedBalance = self.profile and self.profile.progression.balance
      or (self.stage and self.stage.startingMoney) or 0
    -- A restored car looks new, but the repair it needed when saved is still owed.
    self.owedDamage = self.profile and self.profile.vehicle and self.profile.vehicle.damage or 0
    -- A restarted stage sends the player back to its start for a new starter car.
    self.mode = (self.profile and not self.profile.atStart) and 'resume' or 'start'
    self.creationBase = location.copy(self.profile and self.profile.base or self.unsavedBase
      or (self.configuration and self.configuration.base))
    self.startupTarget = location.copy(self.profile and self.profile.resume or self.creationBase)
    -- A restarted save goes to where the stage starts now, even if an update moved it.
    if self.profile and self.mode == 'start' and self.configuration and self.stage then self.startupTarget = self:stageStart() end
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
    return self.profile ~= nil and not self.error and not self.gameOver and type(amount) == 'number' and amount >= 0
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

  -- Puts the player PENALTY_SECONDS further behind on the stage clock. Like money, it is kept by Save.
  function c:addPenalty(reason)
    local progression = self.profile.progression
    progression.penaltySeconds = (progression.penaltySeconds or 0) + PENALTY_SECONDS
    self.penalty = { reason = reason, at = self.clock }
    self.diag:event('time_penalty', reason .. ':' .. PENALTY_SECONDS)
  end

  -- The stage clock runs while the player is on the stage, the game is not paused and the stage
  -- is neither finished nor over.
  function c:clockRunning()
    return self.profile ~= nil and self.state == 'READY' and self.arrived and not self.stageFinished
      and not self.gameOver and not self.error and self.stage ~= nil and self.stage.targetSeconds ~= nil
      and not self.paused()
  end

  function c:runClock(dt)
    if not self:clockRunning() then return end
    local progression = self.profile.progression
    progression.drivingSeconds = (progression.drivingSeconds or 0) + math.min(dt, MAX_CLOCK_STEP)
  end

  -- Seconds ahead of (positive) or behind (negative) the stage's pace. The pace assumes the time
  -- limit is spread evenly over the straight-line distance from start to finish, so a player a
  -- third of the way there in a straight line is expected to have used a third of the time.
  function c:paceSeconds(current, elapsed)
    local target = self.stage.targetSeconds
    local progress = 1
    if not self.stageFinished then
      local total = location.distance(self:stageStart(), self.stage.finish)
      local left = location.distance(current, self.stage.finish)
      if not total or not left or total <= self.stage.finishRadiusMetres then return nil end
      progress = math.max(0, math.min(1, 1 - left / total))
    end
    return math.floor(progress * target - elapsed + 0.5)
  end

  -- The vehicle's damage now, plus the damage still owed from the last save.
  function c:inspectDamage()
    local vehicle, why = self.garage:inspect()
    if not vehicle then return nil, why end
    return { id = vehicle.id, damage = vehicle.damage + self.owedDamage }
  end

  -- Reads the player vehicle's damage now and prices it. Returns the inspection and cost, or nil and a reason.
  function c:priceRepair()
    if not self.profile or self.error or self.gameOver then return nil, 'unavailable' end
    if not self.garage then return nil, 'repair_unavailable' end
    local vehicle, why = self:inspectDamage()
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
    if self.pendingCar then
      self.repairFeedback = 'Buy or revert the new car first.'
      return false
    end
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
    self:addPenalty('repair')
    self.quote, self.owedDamage = nil, 0
    self.repairFeedback = 'Repaired for ' .. dollars(cost) .. '. The repair cost you 5 minutes. Save to keep the new balance.'
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
    self.ownedParts, self.pendingParts, self.pendingCar = snapshot, nil, nil
    self.diag:event('parts_owned', tostring(snapshot.model) .. ' #' .. tostring(snapshot.id))
  end

  function c:checkParts()
    local snapshot = self.garage:parts()
    if not snapshot then return false end
    self.fittedParts = snapshot
    local owned = self.ownedParts
    -- The starter or saved car comes as paid for, even when it replaced a car of the same model.
    if self.arrivingModel and snapshot.model == self.arrivingModel then
      snapshot.value = snapshot.value or self.arrivingValue
      self.arrivingModel, self.arrivingValue = nil, nil
      self:adoptParts(snapshot)
      return true
    end
    if not self.profile or self.error or not owned then
      self:adoptParts(snapshot)
      return true
    end
    -- A different vehicle, or a different model in place of this one, is a car the player is buying.
    if owned.id ~= snapshot.id or owned.model ~= snapshot.model then return self:quoteCar(snapshot) end
    if self.pendingCar then
      self.pendingCar = nil
      self.carFeedback = 'Back in your own car. Nothing to pay.'
    end
    local diff = M.partsDiff(owned, snapshot)
    if not diff then
      if self.pendingParts then self.partsFeedback = 'Part changes undone. Nothing to pay.' end
      self.pendingParts = nil
      return true
    end
    local previous = self.pendingParts
    local damage = previous and previous.damage
      or (self.lastDamage and self.lastDamage.id == snapshot.id and self.lastDamage.damage) or self.owedDamage
    local repair = M.repairCost(damage)
    local position = previous and previous.position
      or (self.lastSample and self.lastSample.valid and location.copy(self.lastSample)) or nil
    self.pendingParts = {
      id = snapshot.id, added = diff.added, removed = diff.removed, partsCost = diff.cost,
      repair = repair, damage = damage, cost = diff.cost + repair, position = position,
    }
    self.quote = nil
    self.partsFeedback = self:canAfford(self.pendingParts.cost) and 'Press Buy to keep these parts, or Revert.'
      or ('Not enough money. You need ' .. dollars(self.pendingParts.cost - self.profile.progression.balance)
        .. ' more. Revert, or the parts go back when you drive off.')
    self.diag:event('parts_quote', string.format('%d parts, %d repair', diff.cost, repair))
    return true
  end

  -- Cars. Picking a car in the game's vehicle selector, or getting into any car that is not the
  -- player's, opens a bill: the car's price, plus parts changed on it since, less the trade-in of
  -- the player's car. The swap mends the old car, so its damage is frozen into the bill.
  function c:quoteCar(snapshot)
    local owned, previous = self.ownedParts, self.pendingCar
    local sameCar = previous and previous.id == snapshot.id and previous.model == snapshot.model
    local oldDamage = previous and previous.oldDamage
      or (self.pendingParts and self.pendingParts.damage)
      or (self.lastDamage and self.lastDamage.id == owned.id and self.lastDamage.damage) or self.owedDamage
    local base = sameCar and previous.base or snapshot
    local extras = M.partsDiff(base, snapshot)
    local price = math.floor((base.value or DEFAULT_CAR_PRICE) + 0.5)
    local repair = M.repairCost(oldDamage)
    local tradeIn = math.max(0, math.floor((owned.value or DEFAULT_CAR_PRICE) * CAR_TRADE_IN_SHARE + 0.5) - repair)
    local extrasCost = extras and extras.cost or 0
    self.pendingParts, self.quote = nil, nil
    self.pendingCar = {
      id = snapshot.id, model = snapshot.model, name = base.name or snapshot.model, base = base,
      price = price, extras = extrasCost, tradeIn = tradeIn, repair = repair, oldDamage = oldDamage,
      cost = math.max(0, price + extrasCost - tradeIn), fromId = owned.id,
      position = previous and previous.position
        or (self.lastSample and self.lastSample.valid and location.copy(self.lastSample)) or nil,
    }
    local cost = self.pendingCar.cost
    self.carFeedback = self:canAfford(cost) and 'Press Buy car to keep it, or Revert to get your car back.'
      or ('Not enough money. You need ' .. dollars(cost - self.profile.progression.balance)
        .. ' more. Revert, or your car comes back when you drive off.')
    self.diag:event('car_quote', string.format('%s %d, trade-in %d', tostring(snapshot.model), cost, tradeIn))
    return true
  end

  function c:buyCar()
    if not self.profile or self.error or self.gameOver then
      self.carFeedback = 'Buying cars is unavailable right now. Check the status above.'
      return false
    end
    local pending = self.pendingCar
    if not pending then
      self.carFeedback = 'No car to pay for.'
      return false
    end
    if not self:checkParts() then
      self.carFeedback = 'Could not read the car. Try again in a moment.'
      return false
    end
    if not self.pendingCar then return false end
    if self.pendingCar.cost ~= pending.cost or self.pendingCar.id ~= pending.id then
      self.carFeedback = 'The car changed, so the bill was updated. Press Buy car again to accept it.'
      return false
    end
    if not self:spend(pending.cost, 'car') then
      self.carFeedback = 'Not enough money. You need ' .. dollars(pending.cost - self.profile.progression.balance) .. ' more.'
      return false
    end
    -- Later part changes are priced against what was paid for, so the car keeps its own Value.
    local snapshot = self.fittedParts
    snapshot.value = pending.base.value
    self:adoptParts(snapshot)
    self:addPenalty('car')
    self.owedDamage = 0
    self.carFeedback = 'Bought ' .. tostring(pending.name) .. ' for ' .. dollars(pending.cost)
      .. '. The car change cost you 5 minutes. Save to keep it.'
    return true
  end

  -- Puts the player back in their own car: the one they left, if it is still there, or else their
  -- car respawned in place. A respawned car looks new, but the repair it needed is still owed.
  function c:revertCar(droveOff)
    local pending, owned = self.pendingCar, self.ownedParts
    if not pending or not owned then
      self.carFeedback = 'No car to revert.'
      return false
    end
    local ok, why, detail
    local respawned = pending.id == pending.fromId
    if not respawned then
      ok = self.garage:enter(pending.fromId)
      respawned = not ok
    end
    if respawned then
      self.arrivingModel, self.arrivingValue = owned.model, owned.value
      ok, why, detail = self.garage:spawnConfig(owned.model, owned.config)
      if not ok then
        self.arrivingModel, self.arrivingValue = nil, nil
        self.carFeedback = 'Could not bring your car back. Try again in a moment.'
        self.diag:event('car_revert_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
        return false
      end
      self.owedDamage = pending.oldDamage
    end
    self.pendingCar = nil
    self.carFeedback = droveOff and 'You drove off without paying, so your own car is back.' or 'Your own car is back.'
    return true
  end

  -- Called every tick: checks parts after a spawn or vehicle switch, notes the damage the vehicle has
  -- before a change, and puts the paid parts back if the player drives off without paying.
  function c:watchParts()
    if not self.garage or self.gameOver then return end
    local vehicleId = self.lastSample and self.lastSample.valid and self.lastSample.vehicle and self.lastSample.vehicle.id
    local expected = self.pendingCar and self.pendingCar.id or (self.ownedParts and self.ownedParts.id)
    if vehicleId ~= nil and expected ~= nil and vehicleId ~= expected then self.partsCheckDue = true end
    if not self.ownedParts then self.partsCheckDue = true end
    if self.partsCheckDue then
      -- Damage is frozen until the check: the respawn has already reset it.
      if self:checkParts() then self.partsCheckDue = false end
      return
    end
    local inspected = self:inspectDamage()
    if inspected then self.lastDamage = inspected end
    local pending = self.pendingCar or self.pendingParts
    if pending and self.lastSample and self.lastSample.valid then
      if not pending.position then pending.position = location.copy(self.lastSample)
      else
        local moved = location.distance(pending.position, self.lastSample)
        local revert = self.pendingCar and self.revertCar or self.revertParts
        -- A failed revert is retried after another stretch of driving, not every frame.
        if moved and moved > UNPAID_PARTS_DRIVE_LIMIT and not revert(self, true) then
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
    self.owedDamage = 0
    -- Parts alone cost no time, but a bill that includes a repair is a repair.
    if pending.repair > 0 then self:addPenalty('repair') end
    self.partsFeedback = 'Bought for ' .. dollars(pending.cost) .. '.'
      .. (pending.repair > 0 and ' The repair cost you 5 minutes.' or '') .. ' Save to keep the new balance.'
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
    -- Ironman: a part change, which mends the car, cannot be used to fix a wreck the player cannot pay for.
    if pending.damage >= WRECKED_DAMAGE and not self:canAfford(pending.repair) then
      self.partsFeedback = 'Your car is wrecked and you cannot pay for its repair, so the paid parts cannot go back.'
      return false
    end
    local ok, why, detail = self.garage:repair(self.ownedParts.config)
    if not ok then
      self.partsFeedback = 'Could not put the paid parts back. Try again in a moment.'
      self.diag:event('parts_revert_failed', tostring(why) .. (detail and (': ' .. detail) or ''), 'E')
      return false
    end
    self.pendingParts, self.owedDamage = nil, 0
    local charged = self.profile and math.min(pending.repair, self.profile.progression.balance) or 0
    if charged > 0 then self:spend(charged, 'repair') end
    -- Putting the parts back mended the car, so it counts as a repair on the clock.
    if self.profile and pending.repair > 0 then self:addPenalty('repair') end
    self.partsFeedback = (droveOff and 'You drove off without paying, so the paid parts were put back.'
      or 'The paid parts were put back.') .. (charged > 0 and (' The repair cost ' .. dollars(charged) .. '.') or '')
      .. (pending.repair > 0 and ' The repair cost you 5 minutes.' or '')
    return true
  end

  -- Once per load, when the player reaches the resume point, their vehicle is swapped, where it
  -- stands, for the car of the last save, or the starter car on a fresh start. Like money, part
  -- changes since the last Save are undone by a reload. A save without a car config leaves the vehicle alone.
  function c:provideVehicle()
    if self.vehicleProvided or self.gameOver or not self.garage or self.state ~= 'READY' or not self.arrived then return end
    self.vehicleProvided = true
    local model, config, label
    local configFile
    if self.mode == 'start' then
      model, config, label, configFile = STARTER_MODEL, STARTER_CONFIG, 'starter_car', STARTER_CONFIG
    else
      config = self.profile and self.profile.vehicle and self.profile.vehicle.config
      if not config then return end
      model, label, configFile = config.model, 'saved_car', config.partConfigFilename
    end
    self.arrivingModel = model
    -- A car respawned from a saved config may not know its .pc file, so its price is looked up here.
    self.arrivingValue = self.garage.carValue and (self.garage:carValue(model, configFile)) or nil
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
      partsTree = source.partsTree, partConfigFilename = source.partConfigFilename or owned.configFile, vars = look.vars, paints = look.paints, licenseName = look.licenseName })
    if not config then self.diag:event('vehicle_config_unsaved', tostring(owned.model), 'W') end
    return config
  end

  -- The damage Save keeps with the car: what it has now plus what is still owed, or, with a parts
  -- bill open, what it had before the change mended it. A restored car owes its repair.
  function c:savedVehicleDamage()
    local damage = self.owedDamage
    if self.pendingCar then damage = self.pendingCar.oldDamage
    elseif self.pendingParts then damage = self.pendingParts.damage
    elseif self.garage and self.ownedParts then
      local inspected = self:inspectDamage()
      if inspected and inspected.id == self.ownedParts.id then damage = inspected.damage end
    end
    return damage > 0 and math.min(MAX_BALANCE, damage) or nil
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
      self.profile = persistence.newProfile(self.creationBase, sample, sample.vehicle, self.stage.id,
        self.stage.startingMoney)
      self.unsavedBase = location.copy(self.profile.base)
      self.diag:event('profile_initialised', 'default (in memory, not yet saved)')
    end
    self.sessionVerified = true
    -- Arriving within the radius of the resume point, usually by teleporting there from the map,
    -- confirms the player is back on their trek.
    if not self.arrived and self.startupTarget then
      local away = location.distance(sample, self.startupTarget)
      if away and away <= self.configuration.resumeRadiusMetres then
        self.arrived = true
        self.diag:event('arrived', string.format('%.1f m', away))
      end
    end
    -- Driving before then is not part of the trek.
    if self.arrived and not self.gameOver then self:addMileage(sample, dt) else self.odometer = nil end
    self:transition('READY', 'verified')
    -- Reaching the finish completes the stage, and the finish is saved straight away.
    if self.arrived and not self.stageFinished and not self.gameOver then
      local left = location.distance(sample, self.stage.finish)
      if left and left <= self.stage.finishRadiusMetres then
        self.stageFinished, self.wreck = true, nil
        self.diag:event('stage_finished', self.stage.id .. string.format(' %.1f km', self.profile.progression.totalDistanceKm))
        self:manualSave()
      end
    end
  end

  -- Ironman: watches for a wrecked car the player cannot pay to repair, and ends the run when the
  -- player still cannot pay after GAME_OVER_DELAY seconds. With a parts bill open, the damage the
  -- part change mended counts.
  function c:watchIronman(dt)
    if self.gameOver or self.stageFinished or not self.garage or self.state ~= 'READY' or not self.arrived then
      self.wreck = nil
      return
    end
    local damage = (self.pendingCar and self.pendingCar.oldDamage) or (self.pendingParts and self.pendingParts.damage)
    if not damage then
      local inspected = self:inspectDamage()
      damage = inspected and inspected.damage
    end
    local cost = damage and damage >= WRECKED_DAMAGE and M.repairCost(damage) or 0
    if cost == 0 or self:canAfford(cost) then
      if self.wreck then self.diag:event('wreck_cleared', tostring(cost)) end
      self.wreck = nil
      return
    end
    if not self.wreck then
      self.wreck = { left = GAME_OVER_DELAY }
      self.diag:event('wrecked', string.format('%.1f damage, %d', damage, cost), 'W')
    end
    self.wreck.cost = cost
    self.wreck.left = self.wreck.left - dt
    if self.wreck.left <= 0 then self:endRun(cost) end
  end

  -- Writes a save of this profile and makes it the loaded one. Returns it, or nil and why.
  function c:record(candidate)
    candidate.schemaVersion, candidate.profileId = 1, 'default'
    local saved, why = self.store:save(candidate)
    if not saved then return nil, why end
    self.profile, self.unsavedBase = saved, nil
    self.savedDistanceKm = saved.progression.totalDistanceKm
    self.savedBalance = saved.progression.balance
    return saved
  end

  -- Game over. It is saved straight away, so reloading the last save does not undo it.
  function c:endRun(cost)
    self.gameOver, self.wreck, self.quote, self.restartArmed = true, nil, nil, false
    self.diag:event('game_over', tostring(cost), 'W')
    local saved, why = self:record({ base = self.profile.base, resume = self.profile.resume,
      progression = self.profile.progression, stage = self.stage.id, vehicle = {}, gameOver = true })
    if not saved then self.diag:event('game_over_unsaved', tostring(why), 'E') end
  end

  -- Where the stage starts. config.json's base, when set, moves the first stage's start.
  function c:stageStart()
    if self.stage.id == stages.first().id then return location.copy(self.configuration.base) end
    return location.copy(self.stage.start)
  end

  -- Starts the stage again: money, mileage and car go back to the start, and the save is replaced.
  -- After game over one press does it; otherwise a second press confirms, since progress is lost.
  function c:restartStage()
    if self.error or not self.configuration or not self.stage then
      self.feedback = 'Restart is unavailable right now. Check the status above.'
      return false
    end
    if not self.gameOver and not self.restartArmed then
      self.restartArmed = true
      self.feedback = 'Press Confirm restart to start ' .. self.stage.name
        .. ' again. Your car, money, mileage and clock go back to the start.'
      return false
    end
    local start = self:stageStart()
    local saved, why = self:record({ base = start, resume = start, progression = { balance = self.stage.startingMoney, totalDistanceKm = 0,
      drivingSeconds = 0, penaltySeconds = 0 },
      stage = self.stage.id, vehicle = {}, atStart = true })
    if not saved then
      self.restartArmed = false
      self.feedback = 'Could not restart just now. Press Restart stage to try again.'
      self.diag:event('stage_restart_failed', tostring(why), 'E')
      return false
    end
    self.diag:event('stage_restarted', self.stage.id)
    self:reload()
    self.feedback = 'Stage restarted. Go to the start to get your starter car.'
    return true
  end

  function c:view()
    local current = self.lastSample and self.lastSample.valid and location.copy(self.lastSample) or nil
    -- Where the player goes to carry on: the last save, or the start before the first save.
    local resume = not self.arrived and not self.error and not self.gameOver and location.copy(self.startupTarget) or nil
    local stageName = self.stage and self.stage.name or ''
    local base = location.copy(self.profile and self.profile.base or self.creationBase)
    local status = messages[self.reason]
    -- A quote only stands for the vehicle it was made for.
    local quote = self.quote
    local vehicleId = self.lastSample and self.lastSample.valid and self.lastSample.vehicle and self.lastSample.vehicle.id
    if quote and (self.error or vehicleId ~= quote.vehicleId) then quote = nil end
    if self.state == 'CONFIG_REQUIRED' then
      status = 'Set valid base coordinates in the rally configuration, then choose Reload rally.'
    elseif self.state == 'ERROR' then
      status = errorMessages[self.error] or errorMessages.internal_error
    elseif self.gameOver then
      status = 'Ironman rule: your car was wrecked and you could not pay for the repair, so this run is over. '
        .. 'Press Restart stage to start ' .. stageName .. ' again in the starter car with ' .. dollars(self.stage and self.stage.startingMoney or 0) .. '.'
    elseif self.state == 'READY' and self.stageFinished then
      status = 'You conquered ' .. stageName .. '! More stages are coming. Press Restart stage to run it again.'
    elseif self.state == 'READY' and self.wreck then
      status = 'Your car is wrecked. The repair costs ' .. dollars(self.wreck.cost) .. ' and you have '
        .. dollars(self.profile.progression.balance) .. '. Unless you can pay, it is game over in '
        .. math.max(0, math.ceil(self.wreck.left)) .. ' s.'
    elseif self.state == 'READY' then
      status = self.arrived and arrivedMessages[self.mode] or goMessages[self.mode]
    elseif not status then status = messages.position_invalid end
    local label = labels[self.state]
    if self.state == 'CONFIG_REQUIRED' or self.state == 'ERROR' then -- keep the label
    elseif self.gameOver then label = 'GAME OVER'
    elseif self.state == 'READY' and self.stageFinished then label = 'STAGE COMPLETE'
    elseif self.state == 'READY' and self.wreck then label = 'WRECKED'
    elseif self.state == 'READY' and not self.arrived then label = goLabels[self.mode] end
    local active = self.profile ~= nil and not self.error and not self.gameOver
    local timer
    if self.stage and self.stage.targetSeconds then
      local progression = self.profile and self.profile.progression or {}
      local driving, penalties = progression.drivingSeconds or 0, progression.penaltySeconds or 0
      local elapsed = driving + penalties
      local shown = self.penalty and self.clock - self.penalty.at < PENALTY_SHOWN_FOR
      timer = {
        targetSeconds = self.stage.targetSeconds, estimate = self.stage.targetIsEstimate,
        -- Whole seconds left; negative once the limit has passed and the player is in overtime.
        remainingSeconds = math.ceil(self.stage.targetSeconds - elapsed),
        drivingSeconds = math.floor(driving), penaltySeconds = penalties,
        running = self:clockRunning(), started = self.arrived or elapsed > 0,
        aheadSeconds = (self.arrived and current and not self.gameOver and self.configuration)
          and self:paceSeconds(current, elapsed) or nil,
        penalty = shown and { reason = self.penalty.reason, seconds = PENALTY_SECONDS } or nil,
      }
    end
    local onStage = current ~= nil and self.arrived and self.stage ~= nil and not self.gameOver
    return {
      state = self.state, stateLabel = label, mode = self.mode,
      sessionStatus = status, arrived = self.arrived,
      -- The base is not shown; it stays in the state for tools and tests.
      base = base,
      resume = resume,
      resumeDistanceMetres = current and resume and location.distance(current, resume) or nil,
      stage = self.stage and {
        name = self.stage.name, finish = location.copy(self.stage.finish),
        startTown = self.stage.startTown, finishTown = self.stage.finishTown, briefing = self.stage.briefing,
      } or nil,
      -- Straight-line distance and compass direction, shown once the player is on the stage.
      finishDistanceMetres = onStage and location.distance(current, self.stage.finish) or nil,
      finishDirection = onStage and location.compassPoint(location.bearing(current, self.stage.finish)) or nil,
      stageFinished = self.stageFinished, gameOver = self.gameOver, timer = timer,
      wreck = self.wreck and { cost = self.wreck.cost, seconds = math.max(0, math.ceil(self.wreck.left)) } or nil,
      restartAllowed = self.stage ~= nil and self.configuration ~= nil and not self.error,
      restartArmed = self.restartArmed,
      vehicle = current and self.lastSample.vehicle and {
        model = self.lastSample.vehicle.model, id = self.lastSample.vehicle.id,
      } or nil,
      balance = self.profile and self.profile.progression.balance or (self.stage and self.stage.startingMoney) or 0,
      totalDistanceKm = self.profile and self.profile.progression.totalDistanceKm or 0,
      unsavedDistanceKm = self.profile and math.max(0, self.profile.progression.totalDistanceKm - self.savedDistanceKm) or 0,
      unsavedBalance = self.profile and math.max(0, self.profile.progression.balance - self.savedBalance) or 0,
      unsavedSpending = self.profile and math.max(0, self.savedBalance - self.profile.progression.balance) or 0,
      testMoneyAllowed = active,
      repairQuoteAllowed = active and self.garage ~= nil,
      repairQuote = quote and quote.cost or nil,
      repairOwed = self.owedDamage > 0 and M.repairCost(self.owedDamage) or nil,
      repairAllowed = quote ~= nil and not self.pendingParts and not self.pendingCar and not self.gameOver,
      repairFeedback = self.repairFeedback,
      partsChange = self.pendingParts and {
        added = self.pendingParts.added, removed = self.pendingParts.removed,
        partsCost = self.pendingParts.partsCost, repair = self.pendingParts.repair, cost = self.pendingParts.cost,
      } or nil,
      buyPartsAllowed = self.pendingParts ~= nil and self:canAfford(self.pendingParts.cost),
      revertPartsAllowed = self.pendingParts ~= nil and not self.gameOver,
      partsFeedback = self.partsFeedback,
      carChange = self.pendingCar and {
        name = self.pendingCar.name, price = self.pendingCar.price, extras = self.pendingCar.extras,
        tradeIn = self.pendingCar.tradeIn, cost = self.pendingCar.cost,
      } or nil,
      buyCarAllowed = self.pendingCar ~= nil and self:canAfford(self.pendingCar.cost),
      revertCarAllowed = self.pendingCar ~= nil and not self.gameOver,
      carFeedback = self.carFeedback,
      saveAllowed = self.state == 'READY' and self.arrived and not self.gameOver,
      saveFeedback = self.feedback,
    }
  end

  function c:tick(dtReal)
    local dt = location.finite(dtReal) and math.max(0, dtReal) or 0
    self.clock = self.clock + dt
    self:observe(self.adapter:sample(), dt)
    self:provideVehicle()
    self:watchParts()
    self:watchIronman(dt)
    self:runClock(dt)
    self.ui:publish(self:view(), self.clock)
  end

  function c:manualSave()
    if self.state ~= 'READY' or not self.profile or self.error or self.gameOver then
      self.feedback = 'Save is unavailable right now. Check the status above.'
      self.diag:event('manual_save_rejected', tostring(self.state), 'W')
      return false
    end
    -- Until the player reaches the resume point they are not in their own car, so a Save would
    -- replace the saved car and location with the stand-in vehicle and wherever it is.
    if not self.arrived then
      self.feedback = 'Go to the coordinates above before saving.'
      self.diag:event('manual_save_rejected', 'not_arrived', 'W')
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
    local saved, why = self:record({
      base = self.profile.base, resume = location.copy(fresh), progression = self.profile.progression,
      vehicle = { model = fresh.vehicle and fresh.vehicle.model, config = self:savedVehicleConfig(),
        damage = self:savedVehicleDamage() },
      stage = self.stage.id, finished = self.stageFinished or nil,
    })
    if not saved then
      -- Nothing is lost: the last save is untouched and the session carries on, so Save can be tried again.
      self.feedback = 'Could not save just now. Your last save is still safe. Press Save to try again.'
      self.diag:clear('manual_save_failed'); self.diag:event('manual_save_failed', why, 'E')
      return false
    end
    self.lastSample = fresh
    self.feedback = self.stageFinished and 'Your finish is saved.' or 'Saved successfully.'
    self.diag:clear('manual_save_succeeded'); self.diag:event('manual_save_succeeded', 'generation ' .. saved.generation)
    return true
  end

  -- Testing aid: adds money to the in-memory balance. Like driving earnings, it is kept by Save.
  function c:addTestMoney()
    if not self.profile or self.error or self.gameOver then
      self.diag:event('test_money_rejected', tostring(self.state), 'W')
      return false
    end
    self:addMoney(TEST_MONEY)
    self.diag:event('test_money_added', tostring(TEST_MONEY))
    return true
  end

  function c:mount(on)
    if self.ui:mount(on, self.clock) then
      self.diag:clear('ui_initialised'); self.diag:event('ui_initialised', 'World Ironman Enduro Rally HUD')
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
-- Whether the game is paused; the stage clock stops while it is.
local function gamePaused()
  for _, name in ipairs({ 'bullettime', 'simTimeAuthority' }) do
    local timing = rawget(_G, name)
    if type(timing) == 'table' and type(timing.getPause) == 'function' then return timing.getPause() == true end
  end
  return false
end
local function ensure()
  if not active then
    active = M.new({ io = gameIO(), adapter = earthAdapter.new(), garage = garage.new(), log = rawget(_G, 'log'),
      paused = gamePaused, trigger = function(event, payload) if guihooks then guihooks.trigger(event, payload) end end })
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
  return safely(function() local c = ensure(); c.diag:event('extension_loaded', 'World Ironman Enduro Rally') end)
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
function M.buyCar() return safely(function() return ensure():buyCar() end) end
function M.revertCar() return safely(function() return ensure():revertCar(false) end) end
function M.restartStage() return safely(function() return ensure():restartStage() end) end
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
