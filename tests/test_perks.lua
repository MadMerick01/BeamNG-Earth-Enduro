local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local P = require('beamngEarthEnduro/persistence')
local perks = require('beamngEarthEnduro/perks')
local stages = require('beamngEarthEnduro/stages')
local A = P.DIRECTORY .. 'save-a.json'
local north = 1 / 111195.0802 -- degrees latitude per metre
local BONUS = stages.first().sponsorBonus

-- Drives north from the current odometer reading, in 100 m steps at 100 m/s.
local function drive(c, a, fromMetres, metres)
  for step = 1, math.floor(metres / 100) do a.pose = F.position((fromMetres + step * 100) * north); c:tick(1) end
  return fromMetres + metres
end
-- A random() that always offers the first perk in the list other than the one held.
local function first() return 0 end
local function give(c, id) c.profile.progression.perk = id end

T.eq(#perks.list(), 9, 'nine perks'); T.eq(perks.get('freeRepair'), nil, 'no Free Repair perk')
T.eq(perks.pick(function() return 0 end), 'doubleCash', 'pick takes from the list')
T.eq(perks.pick(function() return 0 end, 'doubleCash'), 'sponsorBoost', 'pick never offers the perk held')
T.eq(perks.pick(function() return 0.9999 end), 'luckyMile', 'pick reaches the last perk')
for _, perk in ipairs(perks.list()) do T.check(#perk.description > 0, perk.id .. ' described') end

-- Offers: every 5 km of real driving; Keep turns it down, Swap takes it.
do
  local c, io, a = F.controller({ random = first })
  c:tick(0.1)
  local v = c:view().perk
  T.eq(v.held, nil, 'no perk to start with'); T.near(v.nextKm, 5, 1e-9, 'first offer in 5 km'); T.eq(v.offer, nil, 'no offer yet')
  T.eq(#v.list, 9, 'Tips list sent to the HUD')
  local at = drive(c, a, 0, 4900); T.eq(c:view().perk.offer, nil, 'no offer before 5 km')
  at = drive(c, a, at, 100); T.eq(c:view().perk.offer.id, 'doubleCash', 'offer at 5 km'); T.check(c:view().perk.offerAllowed, 'offer can be answered')
  T.check(c:answerPerkOffer(false), 'kept'); T.eq(c:view().perk.held, nil, 'Keep with an empty slot takes nothing'); T.eq(c:view().perk.offer, nil, 'offer gone')
  a.pose = F.position((at + 50000) * north); c:tick(0.1); at = at + 50000
  T.eq(c:view().perk.offer, nil, 'teleports bring no offer')
  at = drive(c, a, at, 5000); T.eq(c:view().perk.offer.id, 'doubleCash', 'offer at 10 km')
  T.check(c:answerPerkOffer(true), 'swapped'); T.eq(c:view().perk.held.id, 'doubleCash', 'perk taken'); T.eq(c:view().perk.held.activate, false, 'Double Cash is passive')
  T.check(not c:answerPerkOffer(true), 'nothing left to answer')
  -- Double Cash doubles driving pay while held.
  local balance = c:view().balance
  at = drive(c, a, at, 1000); T.eq(c:view().balance, balance + 100 * perks.DOUBLE_CASH_MULTIPLIER, 'Double Cash pays $200 per km')
  -- An unanswered offer is replaced by the next one; Swap puts the new perk in the slot.
  at = drive(c, a, at, 4000); T.eq(c:view().perk.offer.id, 'sponsorBoost', 'next offer is never the perk held')
  T.check(c:manualSave(), 'saved'); T.eq(io.files[A].progression.perk, 'doubleCash', 'perk saved'); T.eq(io.files[A].progression.perkOffer, 'sponsorBoost', 'offer saved')
  T.eq(io.files[A].progression.perkOffers, 3, 'offer count saved')
  c:reload(); a.pose = F.position(at * north); c:tick(0.1)
  T.eq(c:view().perk.held.id, 'doubleCash', 'reload keeps the perk'); T.eq(c:view().perk.offer.id, 'sponsorBoost', 'reload keeps the offer')
  T.check(c:answerPerkOffer(true), 'swapped'); T.eq(c:view().perk.held.id, 'sponsorBoost', 'Swap replaces the perk held')
  -- Sponsor Boost: the next sponsor bonus pays double, then it is used up.
  balance = c:view().balance
  at = drive(c, a, at, 5000)
  T.eq(c:view().balance, balance + 500 + BONUS * perks.SPONSOR_BOOST_MULTIPLIER, 'boosted sponsor bonus')
  T.eq(c:view().sponsor.flash.amount, BONUS * 2, 'flash shows the boosted bonus'); T.eq(c:view().perk.held, nil, 'Sponsor Boost used up')
  -- Restart clears the perk and the offers.
  give(c, 'insurance')
  c:restartStage(); T.check(c:restartStage(), 'restarted')
  T.eq(c:view().perk.held, nil, 'restart clears the perk'); T.eq(c:view().perk.offer, nil, 'restart clears the offer')
  T.near(c:view().perk.nextKm, 5, 1e-9, 'offers start again from the start')
end

-- Activate perks: Time Freeze, Pace Gift and Lucky Mile; activated perks keep running after a repair.
do
  local c, io, a, _, _, g = F.controller()
  c:tick(0.1); c:vehicleSpawned(); c:tick(0.1)
  give(c, 'paceGift'); T.check(c:view().perk.activateAllowed, 'Pace Gift can be activated')
  local left = c:view().timer.remainingSeconds
  T.check(c:activatePerk(), 'Pace Gift activated'); T.eq(c:view().perk.held, nil, 'slot empty after activating')
  T.eq(c:view().timer.remainingSeconds, left + perks.PACE_GIFT_SECONDS, 'two minutes back on the clock')
  T.eq(c:view().timer.creditSeconds, perks.PACE_GIFT_SECONDS, 'credit shown'); T.eq(c:view().perk.flash.title, 'PACE GIFT', 'flash')
  T.check(not c:activatePerk(), 'nothing left to activate')
  give(c, 'doubleCash'); T.check(not c:view().perk.activateAllowed and not c:activatePerk(), 'passive perks are not activated')
  -- Time Freeze stops the clock for 3 minutes of driving, then it runs again.
  give(c, 'timeFreeze'); T.check(c:activatePerk(), 'Time Freeze activated')
  local driving = c.profile.progression.drivingSeconds
  F.advance(c, 60); T.near(c.profile.progression.drivingSeconds, driving, 1e-6, 'clock frozen'); T.near(c:view().timer.freezeSeconds, 120, 1, 'freeze counts down')
  -- A repair while it runs loses the perk held but not the freeze.
  give(c, 'carDeal')
  c:addTestMoney(); g.damage = 1000; c:tick(0.1); T.check(c:requestRepairQuote(), 'quoted')
  T.eq(c:view().perk.repairNote, 'Repairing loses your Car Dealer Deal perk.', 'Garage warns the perk will go')
  T.check(c:repairVehicle(), 'repaired'); T.eq(c:view().perk.held, nil, 'repair loses the perk held')
  T.eq(c:view().perk.flash.title, 'PERK LOST', 'player told the perk was lost'); T.eq(c:view().timer.penaltySeconds, 300, 'repair still costs time')
  F.advance(c, 119); T.near(c.profile.progression.drivingSeconds, driving, 1e-6, 'freeze outlives the repair')
  F.advance(c, 11); T.near(c.profile.progression.drivingSeconds, driving + 10, 0.2, 'clock runs again after 3 minutes')
  T.eq(c:view().timer.freezeSeconds, nil, 'freeze over')
  -- Lucky Mile: the next 5 km pay triple.
  give(c, 'luckyMile'); T.check(c:activatePerk(), 'Lucky Mile activated')
  local balance = c:view().balance
  T.near(c:view().perk.luckyKm, 5, 1e-9, 'lucky distance shown')
  local at = drive(c, a, 0, 5000)
  T.eq(c:view().balance, balance + 500 * perks.LUCKY_MILE_MULTIPLIER, 'five lucky km pay triple'); T.eq(c:view().perk.luckyKm, nil, 'Lucky Mile over')
  balance = c:view().balance; drive(c, a, at, 1000); T.eq(c:view().balance, balance + 100, 'normal pay after')
  T.check(c:manualSave(), 'saved'); T.eq(io.files[A].progression.timeCreditSeconds, perks.PACE_GIFT_SECONDS, 'credit saved')
end

-- No Penalty, Parts Discount, Car Dealer Deal.
do
  local c, _, _, _, _, g = F.controller()
  c:tick(0.1); c:vehicleSpawned(); c:tick(0.1); c:addTestMoney()
  give(c, 'noPenalty'); g.damage = 1000; c:tick(0.1); c:requestRepairQuote()
  T.eq(c:view().perk.repairNote, 'Your No Penalty perk covers the 5 minutes of the next repair.', 'Garage says No Penalty covers it')
  T.check(c:repairVehicle(), 'repaired'); T.eq(c:view().timer.penaltySeconds, 0, 'No Penalty: no time lost')
  T.eq(c:view().perk.held, nil, 'No Penalty used up'); T.eq(c:view().perk.flash.title, 'NO PENALTY USED', 'player told')
  T.check(not c:view().repairFeedback:find('5 minutes'), 'feedback does not claim a penalty')
  c:tick(0.1)
  -- Parts Discount halves the parts, not the repair, and an open bill re-prices when the perk changes.
  g:fit('turbo', 'pickup_turbo'); c:vehicleSpawned(); c:tick(0.1)
  T.eq(c:view().partsChange.cost, 2400, 'full price without the perk')
  give(c, 'partsDiscount'); c:perkChanged(); c:tick(0.1)
  T.eq(c:view().partsChange.discount, 1200, 'discount shown'); T.eq(c:view().partsChange.cost, 1200, 'half price')
  local balance = c:view().balance
  T.check(c:buyParts(), 'bought'); T.eq(c:view().balance, balance - 1200, 'charged half'); T.eq(c:view().perk.held, nil, 'Parts Discount used up')
  -- Car Dealer Deal takes 30% off the car, and No Penalty also covers a new car.
  give(c, 'carDeal')
  g.model, g.fitted, g.damage = 'sport', { engine = 'sport_v12' }, 0; c:vehicleSpawned(); c:tick(0.1)
  local bill = c:view().carChange
  T.eq(bill.discount, 12000, '30% off a $40,000 car'); T.eq(bill.cost, 40000 - 12000 - bill.tradeIn, 'bill includes the deal')
  c:addTestMoney(); c:addTestMoney(); c:addTestMoney()
  T.check(c:buyCar(), 'car bought'); T.eq(c:view().perk.held, nil, 'Car Dealer Deal used up'); T.eq(c:view().timer.penaltySeconds, 300, 'new car costs time')
  give(c, 'noPenalty')
  g.model, g.fitted = 'pickup', { engine = 'pickup_engine_v8' }; c:vehicleSpawned(); c:tick(0.1)
  T.check(c:buyCar(), 'second car bought'); T.eq(c:view().timer.penaltySeconds, 300, 'No Penalty covers the new car'); T.eq(c:view().perk.held, nil, 'and is used up')
end

-- Insurance: keeps the player in the rally once instead of game over, and survives repairs.
do
  local Core = require('beamngEarthEnduro/core')
  local c, io, _, _, _, g = F.controller()
  c:tick(0.1); c:vehicleSpawned(); c:tick(0.1)
  give(c, 'insurance'); c:addTestMoney(); g.damage = 1000; c:tick(0.1); c:requestRepairQuote()
  T.eq(c:view().perk.repairNote, 'Repairs keep your Insurance perk.', 'Garage says repairs keep Insurance')
  T.check(c:repairVehicle(), 'repaired'); T.eq(c:view().perk.held.id, 'insurance', 'repair keeps Insurance')
  c.profile.progression.balance = 0
  g.damage = 40000; c:tick(0.1); T.check(c:view().wreck.insured, 'wreck notice says Insurance will pay')
  F.advance(c, Core.GAME_OVER_DELAY + 0.5)
  T.eq(c:view().gameOver, false, 'Insurance prevents game over'); T.eq(g.damage, 0, 'car repaired'); T.eq(c:view().balance, 0, 'for free')
  T.eq(c:view().perk.held, nil, 'Insurance used up'); T.eq(c:view().perk.flash.title, 'INSURANCE PAID', 'player told')
  T.eq(c:view().wreck, nil, 'wreck cleared')
  g.damage = 40000; c:tick(0.1); F.advance(c, Core.GAME_OVER_DELAY + 0.5)
  T.check(c:view().gameOver, 'only once: the next wreck is game over')
  T.eq(io.files[A].gameOver, true, 'game over saved')
end

-- Stage 2: the perk held comes along; a running perk and an offer stay behind. Restart goes back to it.
do
  local c, io, a = F.controller({ random = first })
  c:tick(0.1); c:vehicleSpawned(); c:tick(0.1)
  give(c, 'luckyMile'); c:activatePerk(); give(c, 'insurance')
  c.profile.progression.perkOffer = 'paceGift'
  local first = stages.get('stage_1')
  a.pose = F.position(first.finish.latitude, first.finish.longitude); c:tick(0.1)
  T.check(c:view().stageFinished, 'finished'); T.eq(c:view().perk.offer, nil, 'no offer once finished')
  T.check(not c:activatePerk() and not c:answerPerkOffer(true), 'no perk actions once finished')
  T.check(c:startNextStage(), 'Stage 2 started')
  T.eq(c.profile.progression.perk, 'insurance', 'perk carried to Stage 2'); T.eq(c.profile.progression.luckyUntilKm, nil, 'running perk left behind')
  T.eq(c.profile.progression.perkOffer, nil, 'offer left behind'); T.eq(c.profile.entry.perk, 'insurance', 'arrival perk saved for a restart')
  local second = stages.get('stage_2')
  a.pose = F.position(second.start.latitude, second.start.longitude); c:tick(0.1)
  give(c, 'doubleCash')
  c:restartStage(); T.check(c:restartStage(), 'Stage 2 restarted'); T.eq(c.profile.progression.perk, 'insurance', 'restart brings back the arrival perk')
end

-- Older saves: offers start at the next 5 km stretch; bad perk fields are rejected.
do
  local io = F.io({ ['/settings/beamngEarthEnduro/config.json'] = F.config(), [A] = F.save(1, 0, 0) })
  io.files[A].progression.totalDistanceKm = 12
  local c = F.controller({ io = io })
  T.eq(c.profile.progression.perkOffers, 2, 'older save counts 10 km of offers as made')
  local s = F.save(); s.progression.perk = 'unknownPerk'
  T.check(P.validate(s) ~= nil, 'an unknown perk id loads')
  local u = F.controller({ io = F.io({ ['/settings/beamngEarthEnduro/config.json'] = F.config(), [A] = s }) })
  T.eq(u:heldPerk(), nil, 'and is ignored')
end
for _, bad in ipairs({ { perkOffers = -1 }, { perkOffers = 1.5 }, { perk = 5 }, { freezeSeconds = -1 }, { luckyUntilKm = 'x' }, { timeCreditSeconds = 0 / 0 } }) do
  local s = F.save()
  for k, v in pairs(bad) do s.progression[k] = v end
  T.eq(P.validate(s), nil, 'invalid perk field rejected')
end
T.done('service perks')
