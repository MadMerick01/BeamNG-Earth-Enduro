local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local P = require('beamngEarthEnduro/persistence')
local G = require('beamngEarthEnduro/garage')
local roadEvents = require('beamngEarthEnduro/roadEvents')
local Core = require('beamngEarthEnduro/core')
local A = P.DIRECTORY .. 'save-a.json'
local north = 1 / 111195.0802 -- degrees latitude per metre
T.eq(roadEvents.EVERY_KM, 20, 'a check every 20 km'); T.near(roadEvents.CHANCE, 1 / 3, 1e-12, '1 in 3 chance')
T.eq(roadEvents.BANDITS_MIN, 100, 'bandits take at least $100'); T.eq(roadEvents.BANDITS_MAX, 1000, 'and at most $1,000')
T.eq(roadEvents.SAFE_FINISH_METRES, 1000, 'none in the last km')

-- The checks fall halfway between perk offers.
T.eq(roadEvents.due(0), 0, 'none at the start'); T.eq(roadEvents.due(22.4), 0, 'none before 22.5 km')
T.eq(roadEvents.due(22.5), 1, 'first at 22.5 km'); T.eq(roadEvents.due(42.5), 2, 'next at 42.5 km')
for km = 22.5, 202.5, 20 do T.check(km % 5 ~= 0, 'never on a perk offer (' .. km .. ' km)') end
T.eq(roadEvents.banditAmount(function() return 0 end), 100, 'least taken')
T.eq(roadEvents.banditAmount(function() return 0.999999 end), 1000, 'most taken')
T.eq(roadEvents.category('tire_F_15x7'), 'Tyres', 'tyres'); T.eq(roadEvents.category('brake_F'), 'Brakes', 'brakes')
T.eq(roadEvents.category('pickup_coilover_F'), 'Suspension', 'suspension'); T.eq(roadEvents.category('pickup_engine'), 'Engine', 'engine')
T.eq(roadEvents.category('pickup_bumper_F'), nil, 'bumpers are not offered'); T.eq(roadEvents.category(nil), nil, 'no slot type')

-- Garage side: finds the cheapest better part of the same slot type, and fits it.
do
  local replaced
  local tree = { chosenPartName = 'pickup', path = '/', children = {
    pickup_engine = { chosenPartName = 'pickup_engine_v6', path = '/pickup_engine/', children = {
      pickup_intake = { chosenPartName = 'pickup_intake_stock', path = '/pickup_engine/pickup_intake/' } } },
    pickup_bumper = { chosenPartName = 'pickup_bumper_stock', path = '/pickup_bumper/' } } }
  local jparts = {
    pickup = { slotType = 'main' },
    pickup_engine_v6 = { slotType = 'pickup_engine', information = { value = 3000, name = 'V6' } },
    pickup_engine_v8 = { slotType = 'pickup_engine', information = { value = 4000, name = 'V8' } },
    pickup_engine_v10 = { slotType = { 'pickup_engine' }, information = { value = 9000, name = 'V10' } },
    pickup_engine_i4 = { slotType = 'pickup_engine', information = { value = 1500, name = 'I4' } },
    pickup_intake_stock = { slotType = 'pickup_intake', information = { value = 100 } },
    pickup_bumper_stock = { slotType = 'pickup_bumper_F', information = { value = 100 } },
    pickup_bumper_race = { slotType = 'pickup_bumper_F', information = { value = 900 } },
  }
  local slotMap = { pickup_engine = { 'pickup_engine_v6', 'pickup_engine_v8', 'pickup_engine_v10', 'pickup_engine_i4' },
    pickup_bumper_F = { 'pickup_bumper_stock', 'pickup_bumper_race' } }
  local data = { ioCtx = {}, config = { model = 'pickup', partsTree = tree, parts = { pickup_engine = 'pickup_engine_v6' },
    vars = { a = 1 }, paints = { 'red' } } }
  local g = G.new({
    vehicle = function() return { getID = function() return 7 end, getJBeamFilename = function() return 'pickup' end } end,
    manager = function() return { getVehicleData = function() return data end } end,
    vehicles = function() return { replaceVehicle = function(model, options) replaced = { model = model, config = options.config } end } end,
    jbeam = function() return { getPart = function(_, name) return jparts[name] end,
      getAvailableSlotNameMap = function() return slotMap end } end,
  })
  local list = g:upgrades(roadEvents.category)
  T.eq(#list, 1, 'one slot with an upgrade (bumpers are not offered)')
  T.eq(list[1].path, '/pickup_engine/', 'the engine slot'); T.eq(list[1].part, 'pickup_engine_v8', 'the cheapest better engine')
  T.eq(list[1].name, 'V8', 'named'); T.eq(list[1].label, 'Engine', 'labelled')
  T.check(g:fitPart('/pickup_engine/', 'pickup_engine_v8'), 'fitted')
  local engine = replaced.config.partsTree.children.pickup_engine
  T.eq(engine.chosenPartName, 'pickup_engine_v8', 'the new part is in the tree'); T.eq(engine.children, nil, 'its slots are left to the game')
  T.eq(replaced.config.parts.pickup_engine, 'pickup_engine_v8', 'and in the flat parts list')
  T.eq(replaced.config.paints[1], 'red', 'paint kept'); T.eq(tree.children.pickup_engine.chosenPartName, 'pickup_engine_v6', 'the game data is not changed')
  T.eq(select(2, g:fitPart('/nowhere/', 'x')), 'slot_not_found', 'unknown slot refused')
  -- No slot map: the per-slot list is asked instead.
  slotMap = nil
  local g2 = G.new({
    vehicle = function() return { getID = function() return 7 end } end,
    manager = function() return { getVehicleData = function() return data end } end,
    jbeam = function() return { getPart = function(_, name) return jparts[name] end,
      getAvailablePartNamesForSlot = function(_, slotType) return slotType == 'pickup_engine' and { pickup_engine_v10 = true } or {} end } end,
  })
  T.eq(g2:upgrades(roadEvents.category)[1].part, 'pickup_engine_v10', 'per-slot list used')
  T.eq(select(2, G.new({ vehicle = function() return nil end }):upgrades(roadEvents.category)), 'vehicle_required', 'needs a car')
end

-- Controller: a garage stand-in that has one upgrade to offer and fits it by respawning.
local function giftGarage()
  local g = F.garage()
  g.damage = 2000
  g.values.pickup_engine_v10 = 9000
  function g:upgrades() return { { path = 'engine', label = 'Engine', current = self.fitted.engine, part = 'pickup_engine_v10', name = 'V10' } } end
  g.fits = 0
  function g:fitPart(path, part)
    if not self.accepts then return false, 'repair_failed', 'rejected' end
    self.fits = self.fits + 1
    self.fitted[path], self.damage = part, 0
    return true
  end
  return g
end
local function drive(c, a, fromMetres, metres)
  for step = 1, math.floor(metres / 100) do a.pose = F.position((fromMetres + step * 100) * north); c:tick(1) end
  return fromMetres + metres
end
local function stage(random, garage, money)
  local c, io, a, _, _, g = F.controller({ random = random, garage = garage or giftGarage(), startingMoney = money })
  c:tick(0.1)
  return c, io, a, g
end

-- No luck: nothing happens, but the checks are counted and saved.
do
  local c, io, a = stage(function() return 0.9 end, nil, 5000)
  drive(c, a, 0, 45000)
  T.eq(c.profile.progression.roadEvents, 2, 'two checks made'); T.eq(c:view().road, nil, 'nothing shown')
  T.check(c:manualSave(), 'saved'); T.eq(io.files[A].progression.roadEvents, 2, 'checks saved')
end

-- Bandits: the money taken, the message, and never below $0.
do
  -- With a fixed roll under 1 in 3 the event is a village, so the bandits use a roll sequence.
  local rolls, i = { 0.1, 0.9, 0.5 }, 0
  local active = false
  local function random()
    if not active then return 0.9 end
    i = i + 1
    return rolls[i] or 0.9
  end
  local c, _, a = stage(random, nil, 5000)
  local at = drive(c, a, 0, 22400)
  local before = c.profile.progression.balance
  active = true
  at = drive(c, a, at, 100)
  local taken = 100 + math.floor(0.5 * 901)
  T.eq(c.profile.progression.balance, before + 25 - taken, 'bandits took $' .. taken)
  local v = c:view()
  T.eq(v.road.flash.title, 'BANDITS!', 'BANDITS! shown'); T.check(v.road.flash.text:find('$550', 1, true), 'amount shown')
  F.advance(c, roadEvents.SHOWN_FOR + 1); T.eq(c:view().road, nil, 'message fades')
  -- Out of money: they cannot take it below $0.
  active = false
  at = drive(c, a, at, 19900)
  c.profile.progression.balance = 40
  rolls, i, active = { 0.1, 0.9, 0.999 }, 0, true
  at = drive(c, a, at, 100)
  T.eq(c.profile.progression.balance, 0, 'never below $0: the $65 they found was taken')
  T.check(c:view().road.flash.text:find('$65', 1, true) ~= nil, 'what was taken shown')
end

-- Friendly village: the offer, Install mends the car for free with no time penalty and keeps the perk.
do
  local c, io, a, g = stage(function() return 0 end, nil, 5000)
  c.profile.progression.perk = 'doubleCash'
  local at = drive(c, a, 0, 22400)
  T.eq(c:view().road, nil, 'no offer yet')
  g.damage = 2000
  at = drive(c, a, at, 100)
  local v = c:view()
  T.eq(v.road.offer.name, 'V10', 'the part is named'); T.eq(v.road.offer.label, 'Engine', 'and its slot')
  T.eq(v.road.installAllowed, true, 'Install allowed'); T.eq(v.road.declineAllowed, true, 'Decline allowed')
  local balance, penalty = c.profile.progression.balance, c.profile.progression.penaltySeconds
  T.check(c:answerRoadOffer(true), 'installed')
  c:vehicleSpawned(); c:tick(0.1)
  T.eq(g.fits, 1, 'the part was fitted'); T.eq(g.fitted.engine, 'pickup_engine_v10', 'on the car')
  T.eq(g.damage, 0, 'and the car repaired')
  T.eq(c.profile.progression.balance, balance, 'free'); T.eq(c.profile.progression.penaltySeconds, penalty, 'no time penalty')
  T.eq(c.profile.progression.perk, 'doubleCash', 'perk kept')
  v = c:view()
  T.eq(v.partsChange, nil, 'no parts bill for the gift'); T.eq(v.road.offer, nil, 'offer gone')
  T.eq(v.road.flash.title, 'FREE PART FITTED', 'message shown')
  T.eq(c.ownedParts.parts.engine, 'pickup_engine_v10', 'the gift counts as paid for')
  T.check(c:manualSave(), 'saved'); T.eq(io.files[A].vehicle.damage, nil, 'no repair owed')
end

-- Decline, a bill blocking Install, a failed fit, and no offer in the last km.
do
  local c, _, a, g = stage(function() return 0 end, nil, 5000)
  local at = drive(c, a, 0, 22500)
  T.check(c:view().road.offer ~= nil, 'offered')
  g:fit('intake', 'pickup_intake_race'); c:vehicleSpawned(); c:tick(0.1)
  T.check(c:view().partsChange ~= nil, 'a parts bill is open')
  T.eq(c:view().road.installAllowed, false, 'Install waits for the bill'); T.eq(c:answerRoadOffer(true), false, 'refused')
  T.check(c:revertParts(), 'bill reverted'); c:vehicleSpawned(); c:tick(0.1)
  g.accepts = false
  T.eq(c:answerRoadOffer(true), false, 'fit failed'); T.check(c:view().road.offer ~= nil, 'offer kept to try again')
  g.accepts = true
  T.check(c:view().road.flash.text:find('could not be fitted', 1, true), 'the failure shown')
  T.check(c:answerRoadOffer(false), 'declined'); T.eq(g.fits, 0, 'nothing fitted')
  T.eq(c:view().road.offer, nil, 'offer gone')
end
do
  local finish = require('beamngEarthEnduro/stages').first().finish
  local c, _, a = stage(function() return 0 end, nil, 5000)
  -- Put the finish 900 m north of the 22.5 km check.
  local stageDef = c.stage
  local saved = stageDef.finish
  stageDef.finish = F.position(23400 * north)
  drive(c, a, 0, 22500)
  T.eq(c:view().road, nil, 'none within 1 km of the finish'); T.eq(c.profile.progression.roadEvents, 1, 'the check is used up')
  stageDef.finish = saved
  T.check(finish ~= nil, 'stage has a finish')
end

-- An old save without the counter starts counting from where it is, so nothing is back-rolled.
do
  local c, _, a = stage(function() return 0 end, nil, 5000)
  c.profile.progression.totalDistanceKm = 100
  c.profile.progression.roadEvents = nil
  drive(c, a, 0, 100)
  T.eq(c.profile.progression.roadEvents, roadEvents.due(100.1), 'caught up'); T.eq(c:view().road, nil, 'no event for the past')
end

-- Persistence: the counter is validated.
for _, bad in ipairs({ -1, 1.5, 'x' }) do
  local save = F.save(1)
  save.progression.roadEvents = bad
  T.eq(P.validate(save), nil, 'bad road event count rejected: ' .. tostring(bad))
end
local good = F.save(1); good.progression.roadEvents = 3
T.eq(P.validate(good).progression.roadEvents, 3, 'road event count kept')
T.done('road events')
