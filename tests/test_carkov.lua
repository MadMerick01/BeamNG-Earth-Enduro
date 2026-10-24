local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local P = require('beamngEarthEnduro/persistence')
local location = require('beamngEarthEnduro/location')
local carkov = require('beamngEarthEnduro/carkov')
local perks = require('beamngEarthEnduro/perks')
local north = 1 / 111195.0802 -- degrees latitude per metre
local FEE, REWARD = carkov.ENTRY_FEE, carkov.REWARD
T.eq(FEE, 2000, 'entry costs $2,000'); T.eq(REWARD, 15000, 'extraction pays $15,000'); T.eq(carkov.EXTRACTION_KM, 15, '15 km')

-- A repeatable random() in [0, 1).
local function seeded(seed)
  local state = seed
  return function()
    state = (state * 1103515245 + 12345) % 2147483648
    return state / 2147483648
  end
end

-- The land map: land, less water, Antarctica, Greenland and the big deserts.
local function at(lat, lon) return { latitude = lat, longitude = lon } end
T.check(carkov.land(at(48.85, 2.35)), 'Paris is land'); T.check(carkov.land(at(-33.6, 150.8)), 'Windsor, NSW is land')
T.check(carkov.land(at(39.0, -98.0)), 'Kansas is land'); T.check(carkov.land(at(-15.0, -55.0)), 'Mato Grosso is land')
T.check(not carkov.land(at(30.0, -40.0)), 'the Atlantic is not'); T.check(not carkov.land(at(0.0, -150.0)), 'the Pacific is not')
T.check(not carkov.land(at(-1.0, 33.0)), 'Lake Victoria is not'); T.check(not carkov.land(at(45.0, 51.0)), 'the Caspian Sea is not')
T.check(not carkov.land(at(-80.0, 30.0)), 'Antarctica is left out'); T.check(not carkov.land(at(72.0, -40.0)), 'Greenland is left out')
T.check(not carkov.land(at(23.0, 10.0)), 'the Sahara is left out'); T.check(not carkov.land(at(43.0, 105.0)), 'the Gobi is left out')
T.check(not carkov.land(at(-25.0, 125.0)), 'the Gibson Desert is left out')
T.check(not carkov.land(at(91, 0)) and not carkov.land(nil), 'invalid points are not land')
T.check(not carkov.land(at(90, 180)) and not carkov.land(at(-90, -180)), 'the edges of the map are safe to ask')

-- Destination: a point the given distance away along the bearing.
local d = location.destination(at(10, 20), 45, 15000)
T.near(location.distance(at(10, 20), d), 15000, 0.5, 'destination is 15 km away'); T.near(location.bearing(at(10, 20), d), 45, 0.01, 'on the bearing')
T.near(location.destination(at(0, 179.95), 90, 15000).longitude, -179.915, 0.01, 'destination wraps the date line')

-- Picking: both points on land and exactly 15 km apart, spread over the world.
do
  local random = seeded(7)
  local hemispheres = {}
  for i = 1, 40 do
    local drop, extraction = carkov.pick(random)
    T.check(drop and carkov.land(drop) and carkov.land(extraction), 'pick ' .. i .. ' lands both points on land')
    T.near(location.distance(drop, extraction), 15000, 1, 'pick ' .. i .. ' extraction is 15 km from the drop')
    hemispheres[(drop.latitude >= 0 and 'N' or 'S') .. (drop.longitude >= 0 and 'E' or 'W')] = true
  end
  T.check(hemispheres.NE and hemispheres.NW and hemispheres.SE and hemispheres.SW, 'drops come from every quarter of the world')
  T.eq(carkov.pick(function() return 0 end), nil, 'gives up when nothing is on land')
end

-- Drives from the odometer reading towards a point in 100 m steps at 100 m/s.
local function driveTo(c, a, target, stopShort)
  for _ = 1, 1000 do
    local left = location.distance(a.pose, target)
    if left <= (stopShort or 0) + 100 then
      if not stopShort then a.pose = location.copy(target); c:tick(1) end
      return
    end
    a.pose = location.destination(a.pose, location.bearing(a.pose, target), 100); c:tick(1)
  end
end
local function onStage(c, a, metres)
  for step = 1, math.floor(metres / 100) do a.pose = F.position(step * 100 * north); c:tick(1) end
end

-- Entering: refused without the fee, then saves the stage, takes the fee and sends the player to the drop.
do
  local c, io, a, _, _, g = F.controller({ random = seeded(11) })
  c:tick(0.1)
  T.check(c:view().carkov ~= nil, 'HUD gets CarKov'); T.eq(c:view().carkov.fee, FEE, 'HUD shows the fee'); T.eq(c:view().carkov.active, false, 'not on a run')
  T.eq(c:view().carkov.enterAllowed, false, 'cannot enter without the fee'); T.check(not c:enterCarKov(), 'entry refused')
  T.check(c.feedback:find('need %$2,000 more'), 'says how much more is needed')
  onStage(c, a, 3000)
  local stageAt = location.copy(a.pose)
  c:addTestMoney()
  c.profile.progression.perk = 'luckyMile'
  local stageKm, stageDriving = c.profile.progression.totalDistanceKm, c.profile.progression.drivingSeconds
  local balance = c:view().balance
  local stageBalance = balance
  T.check(c:view().carkov.enterAllowed, 'can enter with the fee'); T.check(c:view().timer.running, 'stage clock running')
  g.damage = 400
  T.check(c:enterCarKov(), 'entered CarKov')
  c:tick(0.1)
  local v = c:view()
  T.eq(v.carkov.active, true, 'on a run'); T.eq(v.balance, balance - FEE, 'fee taken'); T.eq(v.mode, 'drop', 'goes to the drop')
  T.eq(v.stateLabel, 'GO TO THE CARKOV DROP', 'label says where to go'); T.check(v.sessionStatus:find('CarKov'), 'status explains the drop')
  T.check(v.resume and carkov.land(v.resume), 'drop shown, on land'); T.near(location.distance(v.resume, v.carkov.extraction), 15000, 1, 'extraction 15 km from the drop')
  T.eq(v.timer, nil, 'no stage clock on the run'); T.eq(v.sponsor, nil, 'no sponsor bonus on the run'); T.eq(v.finishDistanceMetres, nil, 'no stage finish')
  T.eq(v.restartAllowed, false, 'no restart on the run'); T.check(not c:restartStage(), 'restart refused')
  T.eq(v.carkov.enterAllowed, false, 'cannot enter twice'); T.check(not c:enterCarKov(), 'second entry refused')
  local saved = c.profile
  T.check(saved.carkov ~= nil and saved.generation >= 1, 'run saved straight away')
  T.near(location.distance(saved.carkov.stage.resume, stageAt), 0, 0.01, 'stage saved where the player was')
  T.near(saved.carkov.stage.progression.totalDistanceKm, stageKm, 1e-9, 'stage mileage kept'); T.near(saved.carkov.stage.progression.drivingSeconds, stageDriving, 1e-9, 'stage clock kept')
  T.eq(saved.progression.perk, 'luckyMile', 'perk held goes on the run'); T.eq(saved.progression.totalDistanceKm, 0, 'run mileage starts at zero')
  T.eq(saved.vehicle.damage, 400, 'car damage goes on the run'); T.check(saved.vehicle.config ~= nil, 'car goes on the run')
  -- The drop zone reaches 500 m from the drop point: just outside does not count.
  T.eq(c:view().carkov.dropRadiusMetres, 500, 'HUD shows the drop zone')
  a.pose = location.destination(v.resume, 90, 520); c:tick(0.1); T.eq(c:view().arrived, false, '520 m off is outside the drop zone')
  -- Reaching the drop brings the player's car; driving pays, and perks keep coming.
  local spawns = #g.spawns
  a.pose = location.copy(v.resume); c:tick(0.1)
  v = c:view()
  T.eq(v.arrived, true, 'arrived at the drop'); T.eq(#g.spawns, spawns + 1, 'car brought to the drop'); T.eq(g.spawns[#g.spawns].config.model, 'pickup', 'it is the player car')
  T.eq(v.stateLabel, 'CARKOV', 'label shows the run'); T.near(v.carkov.extractionDistanceMetres, 15000, 1, 'distance to extraction shown')
  T.check(v.carkov.extractionDirection ~= nil, 'direction shown')
  T.check(v.repairOwed and v.repairOwed > 0, 'damage still owed on the run')
  balance = v.balance
  driveTo(c, a, v.carkov.extraction, 9000)
  v = c:view()
  T.near(v.carkov.distanceKm, 6, 0.11, 'run mileage counted'); T.check(v.balance >= balance + 580, 'driving pays on the run')
  T.check(v.perk.offer ~= nil, 'perks offered on the run'); T.eq(v.timer, nil, 'still no clock')
  T.check(c:manualSave(), 'can save on the run'); T.check(c.profile.carkov ~= nil, 'save keeps the run')
  -- Reloading carries on from the run's save.
  c:reload(); c:tick(0.1)
  T.eq(c:view().carkov.active, true, 'run survives a reload'); T.eq(c:view().mode, 'resume', 'back to the last save'); T.eq(c:view().arrived, true, 'already there')
  -- Closing in: the HUD counts down in metres from 1 km out.
  balance = c:view().balance
  local perk = c:heldPerk()
  local runKm = c.profile.progression.totalDistanceKm
  driveTo(c, a, c.profile.carkov.extraction, 900)
  T.check(c:view().carkov.extractionDistanceMetres < c:view().carkov.closingInMetres, 'closing in shown inside 1 km')
  -- Extraction needs 5 seconds held in the zone; leaving it starts the hold again.
  local target = c.profile.carkov.extraction
  a.pose = location.destination(target, 0, 50); F.advance(c, 3)
  v = c:view()
  T.eq(v.carkov.active, true, 'not extracted at once'); T.eq(v.carkov.hold.seconds, 2, 'countdown shown'); T.near(v.carkov.hold.progress, 0.6, 1e-9, 'hold bar fills')
  a.pose = location.destination(target, 0, 150); c:tick(0.1)
  T.eq(c:view().carkov.hold, nil, 'leaving the zone stops the hold')
  a.pose = location.destination(target, 0, 50); F.advance(c, 4)
  T.eq(c:view().carkov.active, true, 'hold started again from zero'); T.eq(c:view().carkov.hold.seconds, 1, 'one second to go')
  local runSeconds = c.profile.progression.drivingSeconds
  T.check(runSeconds > 30, 'the run is timed')
  -- Extraction pays the reward and goes back to the stage with the car and money.
  F.advance(c, 1.1)
  v = c:view()
  T.eq(v.carkov.active, false, 'run over')
  T.check(v.balance >= balance + REWARD + 780 and v.balance <= balance + REWARD + 820, 'reward and the last 8 km paid')
  local done = v.carkov.complete
  T.check(done ~= nil, 'EXTRACTION COMPLETE shown'); T.eq(done.reward, REWARD, 'shows the reward'); T.eq(done.balance, v.balance, 'shows the balance')
  T.check(done.distanceKm > runKm + 7, 'shows the run distance'); T.check(done.seconds >= runSeconds, 'shows the run time')
  T.eq(done.net, v.balance - stageBalance, 'shows what the run made after the fee')
  T.eq(v.carkov.flash, nil, 'no small flash as well')
  T.eq(v.mode, 'resume', 'back to the stage save'); T.near(location.distance(v.resume, stageAt), 0, 0.01, 'to where the stage was saved')
  T.eq(c.profile.carkov, nil, 'save no longer on a run'); T.near(c.profile.progression.totalDistanceKm, stageKm, 1e-9, 'stage mileage back')
  T.near(c.profile.progression.drivingSeconds, stageDriving, 1e-9, 'stage clock back'); T.eq(c.profile.progression.perk, perk, 'perk held comes back')
  T.eq(c.profile.progression.balance, v.balance, 'money saved straight away')
  F.advance(c, 30); T.check(c:view().carkov.complete ~= nil, 'the screen stays up')
  T.check(c:dismissExtraction(), 'dismissed'); T.eq(c:view().carkov.complete, nil, 'Back to my stage closes it'); T.check(not c:dismissExtraction(), 'nothing to close')
  -- Back at the stage the car comes back and the stage carries on.
  a.pose = location.copy(stageAt); c:tick(0.1)
  T.eq(c:view().arrived, true, 'back on the stage'); T.check(c:view().timer ~= nil, 'stage clock back'); T.check(c:view().sponsor ~= nil, 'sponsor bonus back')
end

-- Quitting: needs a second press, keeps the money earned and the car, and loses the fee.
do
  local c, io, a = F.controller({ random = seeded(3), startingMoney = 5000 })
  c:tick(0.1)
  T.check(c:enterCarKov(), 'entered')
  T.check(c:view().carkov.quitAllowed, 'quit allowed before reaching the drop')
  a.pose = location.copy(c:view().resume); c:tick(0.1)
  driveTo(c, a, c.profile.carkov.extraction, 13000)
  local balance = c:view().balance
  T.check(not c:quitCarKov(), 'first press asks to confirm'); T.eq(c:view().carkov.quitArmed, true, 'Confirm quit shown')
  T.check(c:quitCarKov(), 'quit'); T.eq(c:view().carkov.active, false, 'run over')
  T.eq(c:view().balance, balance, 'money earned on the run kept'); T.check(balance < 5000 - FEE + 300, 'fee not refunded')
  T.eq(c:view().carkov.flash.result, 'quit', 'quit shown'); T.eq(c:view().mode, 'resume', 'back to the stage')
  T.check(not c:quitCarKov(), 'nothing left to quit')
end

-- Teleporting a little way off the drop point, inside the zone, starts the run.
do
  local c, io, a = F.controller({ random = seeded(21), startingMoney = 2000 })
  c:tick(0.1); T.check(c:enterCarKov(), 'entered'); c:tick(0.1)
  local drop = c:view().resume
  a.pose = location.destination(drop, 200, 450); c:tick(0.1)
  T.eq(c:view().arrived, true, '450 m off the drop point counts'); T.eq(c:view().stateLabel, 'CARKOV', 'run under way')
  T.check(c:manualSave(), 'saved'); c:reload(); a.pose = location.destination(c.profile.resume, 0, 100); c:tick(0.1)
  T.eq(c:view().arrived, false, 'a save on the run uses the normal 50 m')
end

-- Quitting before reaching the drop goes back with the car entered with.
do
  local c, io, a, _, _, g = F.controller({ random = seeded(5), startingMoney = 2500 })
  c:tick(0.1); g.damage = 600
  T.check(c:enterCarKov(), 'entered')
  c:quitCarKov(); T.check(c:quitCarKov(), 'quit before the drop')
  T.eq(c:view().balance, 500, 'fee lost'); T.eq(c.profile.vehicle.damage, 600, 'car comes back with its damage owed')
end

-- A totalled car the player cannot pay for ends the run, not the rally.
do
  local c, io, a, _, _, g = F.controller({ random = seeded(9), startingMoney = 3000 })
  c:tick(0.1)
  T.check(c:enterCarKov(), 'entered')
  a.pose = location.copy(c:view().resume); c:tick(0.1)
  T.eq(c:view().balance, 1000, '$1,000 left')
  g.damage = 20000; c:tick(0.1)
  T.eq(c:view().stateLabel, 'WRECKED', 'wreck shown'); T.check(c:view().sessionStatus:find('CarKov run is over'), 'says the run ends, not the rally')
  F.advance(c, 11)
  local v = c:view()
  T.eq(v.gameOver, false, 'not game over'); T.eq(v.carkov.active, false, 'run over'); T.eq(v.carkov.flash.result, 'wrecked', 'failure shown')
  T.eq(v.balance, 0, 'the repair took what money there was'); T.eq(c.profile.vehicle.damage, nil, 'car comes back repaired')
  T.eq(g.damage, 0, 'car mended'); T.eq(v.mode, 'resume', 'back to the stage')
  a.pose = F.position(); c:tick(0.1); F.advance(c, 11)
  T.eq(c:view().gameOver, false, 'the stage carries on')
end

-- Reverting a part change the player cannot afford on a damaged car leaves the money alone; the
-- repair the change mended is still owed.
do
  local c, _, a, _, _, g = F.controller({ random = seeded(11), startingMoney = 5000 })
  c:tick(0.1)
  T.check(c:enterCarKov(), 'entered')
  a.pose = location.copy(c:view().resume); c:tick(0.1); c:vehicleSpawned(); c:tick(0.1)
  g.damage = 8000; c:tick(0.1)
  g:fit('turbo', 'pickup_turbo'); c:vehicleSpawned(); c:tick(0.1)
  local bill = c:view().partsChange
  T.eq(bill.repair, 4100, 'repair on the bill'); T.check(not c:view().buyPartsAllowed, 'cannot afford the part')
  T.check(c:revertParts(false), 'revert accepted'); c:vehicleSpawned(); c:tick(0.1)
  T.eq(c:view().balance, 3000, 'revert leaves the money unchanged'); T.eq(c:view().partsChange, nil, 'no bill after reverting')
  T.eq(c:view().repairOwed, 4100, 'the repair is still owed'); T.eq(g.fitted.turbo, nil, 'paid parts put back')
  T.check(c:requestRepairQuote(), 'repair quoted'); T.eq(c.quote.cost, 4100, 'quote includes the owed repair')
end

-- The Garage works on the run: a part change and a new car each get a bill, and the car costs no time.
do
  local c, _, a, _, _, g = F.controller({ random = seeded(12), startingMoney = 60000 })
  c:tick(0.1)
  T.check(c:enterCarKov(), 'entered')
  a.pose = location.copy(c:view().resume); c:tick(0.1); c:vehicleSpawned(); c:tick(0.1)
  g:fit('turbo', 'pickup_turbo'); c:vehicleSpawned(); c:tick(0.1)
  T.check(c:view().partsChange ~= nil, 'parts bill on the run'); T.check(c:view().buyPartsAllowed, 'parts can be bought')
  T.check(c:buyParts(), 'parts bought on the run')
  g.model, g.fitted = 'sport', { engine = 'sport_v12' }; c:vehicleSpawned(); c:tick(0.1)
  T.check(c:view().carChange ~= nil, 'car bill on the run'); T.check(c:buyCar(), 'car bought on the run')
  T.eq(c.profile.progression.penaltySeconds, 0, 'no time penalty for a car on the run')
  T.eq(c:view().carkov.active, true, 'still on the run')
end

-- Insurance still pays for a wreck on the run; repairs on the run cost no time and keep No Penalty.
do
  local c, io, a, _, _, g = F.controller({ random = seeded(13), startingMoney = 2000 })
  c:tick(0.1)
  c.profile.progression.perk = 'insurance'
  T.check(c:enterCarKov(), 'entered')
  a.pose = location.copy(c:view().resume); c:tick(0.1)
  g.damage = 20000; F.advance(c, 11)
  T.eq(c:view().carkov.active, true, 'Insurance kept the run going'); T.eq(c.profile.progression.penaltySeconds, 0, 'no time penalty on the run')
  c.profile.progression.perk = 'noPenalty'; c:addTestMoney(); g.damage = 500
  T.check(c:requestRepairQuote() and c:repairVehicle(), 'repaired on the run')
  T.eq(c:heldPerk(), 'noPenalty', 'No Penalty kept for the stage'); T.eq(c.profile.progression.penaltySeconds, 0, 'still no penalty')
  c.profile.progression.perk = 'timeFreeze'; c:tick(0.1)
  T.eq(c:view().perk.activateAllowed, false, 'Time Freeze waits for the stage'); T.check(not c:activatePerk(), 'cannot activate it')
  c.profile.progression.perk = 'luckyMile'; c:tick(0.1)
  T.check(c:view().perk.activateAllowed, 'Lucky Mile works on the run')
end

-- Entry needs the player on their stage with no open bill or wreck.
do
  local c, io, a, _, _, g = F.controller({ random = seeded(17), startingMoney = 50000 })
  T.check(not c:enterCarKov(), 'not before the stage has started')
  c:tick(0.1)
  g:fit('engine', 'pickup_turbo'); c:vehicleSpawned(); c:tick(0.1)
  T.eq(c:view().carkov.enterAllowed, false, 'not with a parts bill open'); T.check(not c:enterCarKov(), 'refused with a bill')
  c:revertParts(false); c:tick(0.1)
  T.check(c:view().carkov.enterAllowed, 'allowed once the bill is settled')
  local io2 = io
  io2.writeFails = true
  T.check(not c:enterCarKov(), 'a failed save does not enter'); T.eq(c:view().balance, 50000, 'and charges nothing'); T.eq(c:view().carkov.active, false, 'still on the stage')
end

-- Saves: a run's fields are checked like the rest of the save.
do
  local s = F.save(1)
  s.carkov = { drop = at(10, 20), extraction = at(10.1, 20), stage = { resume = at(1, 2), progression = { balance = 5, totalDistanceKm = 3 } } }
  local clean = P.validate(s)
  T.check(clean and clean.carkov.stage.progression.totalDistanceKm == 3, 'a run loads')
  for name, change in pairs({
    drop = function(k) k.drop = at(100, 0) end, extraction = function(k) k.extraction = nil end,
    stage = function(k) k.stage = nil end, resume = function(k) k.stage.resume = at(0, 200) end,
    progression = function(k) k.stage.progression.balance = -1 end, finished = function(k) k.stage.finished = false end,
  }) do
    local bad = F.copy(s); change(bad.carkov)
    local ok, why = P.validate(bad)
    T.check(ok == nil and why == 'invalid_carkov', 'a bad ' .. name .. ' is refused')
  end
  T.eq(P.validate(F.save(1)).carkov, nil, 'older saves have no run')
end

T.done('CarKov')
