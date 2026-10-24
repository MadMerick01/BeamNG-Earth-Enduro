local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local P = require('beamngEarthEnduro/persistence')
local CONFIG = '/settings/beamngEarthEnduro/config.json'
local A, B = P.DIRECTORY .. 'save-a.json', P.DIRECTORY .. 'save-b.json'

local c,io,adapter=F.controller()
T.eq(c.state,'EARTH_UNAVAILABLE','waits for the first vehicle position')
T.eq(c.profile,nil,'no profile initialized prematurely')
T.check(not c:manualSave(),'save before any position rejected'); T.eq(io.writes,0,'rejected save performs no writes')
T.eq(c:view().resume.latitude,0,'start coordinates shown before a vehicle position')
adapter.pose=F.position(1,1); c:tick(0.1)
T.eq(c.state,'READY','any valid position starts the session, away from base')
T.eq(c:view().stateLabel,'GO TO THE START','player told to go to the start')
T.check(c:view().sessionStatus:find('teleport'),'player told how to get there')
T.eq(c:view().resume.latitude,0,'start coordinates shown'); T.check(c:view().resumeDistanceMetres>100000,'distance to the start shown')
T.check(not c:view().saveAllowed,'save locked until the player arrives')
T.check(not c:manualSave(),'save before arriving rejected'); T.eq(io.writes,0,'rejected save performs no writes')
T.check(c:view().saveFeedback:find('coordinates above'),'player told to go there first')
T.check(c.profile~=nil,'profile created at first position'); T.eq(c.profile.generation,0,'new profile in memory')
T.eq(c.profile.base.latitude,0,'new profile uses configured base')
T.eq(io.writes,0,'starting a session has no disk writes'); T.eq(c.profile.progression.balance,0,'new profile starts with no money')
local initialTarget=F.copy(c.startupTarget)
adapter.pose=F.position(0.0003,0); c:tick(0.1)
T.check(c:view().arrived,'within the radius of the start counts as arrived'); T.eq(c:view().resume,nil,'coordinates hidden once arrived')
T.eq(c:view().stateLabel,'READY','ready once arrived'); T.check(c:view().sessionStatus:find("You're at the start"),'player told they are in the right place')
T.check(c:view().saveAllowed,'save unlocked once arrived')
adapter.pose=F.position(2,3); c:tick(0.1)
T.check(c:view().arrived,'leaving the start keeps the session going')
T.eq(c.state,'READY','travel anywhere stays ready')
T.eq(c.profile.progression.totalDistanceKm,0,'teleport-sized jump adds no mileage')
T.check(c:manualSave(),'manual save succeeds')
T.eq(io.writes,1,'one write per manual click'); T.eq(c.profile.resume.latitude,2,'new position saved')
T.eq(c.profile.base.latitude,0,'save leaves original base fixed')
T.eq(c.profile.vehicle.model,'pickup','available vehicle identity saved')
T.check(P.equal(c.startupTarget,initialTarget),'save does not mutate arrival target')
local disk=F.copy(io.files[A])
F.advance(c,10); T.eq(io.writes,1,'no periodic or per-frame saves')
T.eq(c.profile.progression.balance,0,'standing still earns no money')

-- A separate controller represents a real restart: the target is the saved location.
c,io,adapter=F.controller({io=io})
T.eq(c.mode,'resume','restart loads the save'); T.eq(c.startupTarget.latitude,2,'saved location loaded')
F.advance(c,5); T.eq(c.state,'READY','session starts away from the saved location')
T.eq(c:view().stateLabel,'GO TO YOUR LAST SAVE','player told to go to the last save')
T.eq(c:view().resume.latitude,2,'last saved coordinates shown'); T.eq(c:view().resume.longitude,3,'last saved longitude shown')
T.check(not c:manualSave(),'save locked away from the saved location')
T.eq(io.writes,1,'loading and driving leave disk untouched'); T.check(P.equal(io.files[A],disk),'save survives restart')
adapter.pose=F.position(2,3); c:tick(0.1); T.check(c:view().arrived,'teleporting to the saved location arrives')
T.check(c:view().sessionStatus:find("You're in the right place"),'player told to continue their trek')
adapter.valid=false; adapter.reason='vehicle_required'; c:tick(0.1)
T.eq(c.state,'EARTH_UNAVAILABLE','no vehicle position pauses session')
T.check(not c:manualSave(),'save locked without vehicle position'); T.eq(io.writes,1,'no position cannot write')
adapter.valid=true; adapter.pose=F.position(2.1,3.1); c:tick(0.1)
T.eq(c.state,'READY','arrived session resumes wherever the vehicle is')
T.eq(c.startupTarget.latitude,2,'recovery never mutates saved target')
T.eq(c.profile.base.latitude,0,'recovery never mutates base')
adapter.pose=F.position(4,5); c:tick(0.1); T.check(c:manualSave(),'second location saved')
T.eq(io.files[B].base.latitude,0,'base fixed across generations')
T.eq(io.files[B].resume.latitude,4,'second resume saved')

-- Configuration changes never move an existing profile's original base.
io.files[CONFIG].base=F.position(10,10); c:reload()
T.eq(c.state,'EARTH_UNAVAILABLE','reload waits for a fresh position')
T.eq(c:view().base.latitude,0,'profile keeps original base despite config change')
T.eq(c.startupTarget.latitude,4,'resume remains independent of new config')

-- Save reads the vehicle position at click time.
adapter.pose=F.position(4,5); c:tick(0.1); local writes=io.writes
adapter.valid=false
T.check(not c:manualSave(),'save rechecks vehicle at click'); T.eq(io.writes,writes,'click without position writes nothing')
adapter.valid=true; c:tick(0.1); adapter.pose=F.position(6,7)
T.check(c:manualSave(),'click saves the current position'); T.eq(c.profile.resume.latitude,6,'click-time position saved')
io.writeFails=true
T.check(not c:manualSave(),'write failure visible'); T.eq(c.state,'READY','a failed save does not pause the session')
T.check(c:view().saveFeedback:find('try again'),'failure message says to try again')
T.eq(io.files[A].resume.latitude,6,'latest valid generation retained on failure')
T.check(c:view().saveAllowed,'save stays available after a failure')
io.writeFails=false; T.check(c:manualSave(),'retrying save works without a reload')

-- Missing configuration selects the built-in base; invalid overrides/saves stay locked.
for _, scenario in ipairs({
  { files={[CONFIG]={base={}}}, state='CONFIG_REQUIRED' },
  { files={[CONFIG]=F.config(),[A]={schemaVersion=2}}, state='ERROR' },
}) do
  local localIO=F.io(scenario.files)
  local controller=F.controller({io=localIO})
  F.advance(controller,5)
  T.eq(controller.state,scenario.state,'invalid configuration/save stays locked')
  T.check(not controller:manualSave(),'invalid configuration/save cannot write')
  T.eq(localIO.writes,0,'invalid inputs perform zero writes')
  T.check(controller:view()~=nil,'HUD renders safely even with missing config')
end

for _, reason in ipairs({'earth_missing','earth_starting','position_invalid','vehicle_required'}) do
  local controller,localIO,a=F.controller()
  a.valid=false; a.reason=reason; F.advance(controller,5)
  T.eq(controller.state,'EARTH_UNAVAILABLE','no vehicle position cannot unlock')
  T.eq(controller.profile,nil,'no profile without vehicle position')
  T.eq(localIO.writes,0,'no vehicle position never writes')
end
local controller,localIO,a=F.controller()
controller:tick(0.1); controller:endMission(); a.valid=false; a.reason='earth_level_required'; controller:tick(0.1)
T.eq(controller.state,'EARTH_UNAVAILABLE','mission end pauses the session')
T.check(not controller:manualSave(),'mission end locks saving')
T.eq(localIO.writes,0,'mission end has no implicit save')

-- An unreadable save file means a fresh start that saving replaces, not a locked game.
do
  local localIO=F.io({[CONFIG]=F.config(),[A]='truncated'}); local controller=F.controller({io=localIO})
  T.check(controller:view().saveFeedback:find('fresh start'),'unreadable save explained')
  F.advance(controller,5); T.eq(controller.state,'READY','unreadable save does not pause the game')
  T.check(controller:manualSave(),'saving replaces the unreadable file'); T.eq(localIO.files[A].generation,1,'new save written')
end
do
  local controller=F.controller({io=F.io({[CONFIG]=F.config(),[A]={schemaVersion=2}})})
  T.check(controller:view().sessionStatus:find('newer version'),'newer save explained in plain words')
end

-- Missing configuration selects the built-in base and saving works straight away.
do
  local localIO=F.io({}); local controller,_,a=F.controller({io=localIO})
  a.pose=F.position(34.271288,75.163671); F.advance(controller,5); T.eq(controller.state,'READY','built-in base session is ready')
  T.check(controller:manualSave(),'save works without configuration'); T.eq(localIO.writes,1,'one write')
end

local unsaved,unsavedIO=F.controller(); unsaved:tick(0.1)
unsavedIO.files[CONFIG].base=F.position(10,10); unsaved:reload()
T.eq(unsaved.startupTarget.latitude,0,'unsaved created profile also keeps original base on config reload')
unsaved:reload(); T.eq(unsaved:view().base.latitude,0,'repeated reloads keep pending original base')
unsaved:tick(0.1); T.eq(unsaved.profile.base.latitude,0,'new session does not rewrite original unsaved base')

-- Mileage: distance between consecutive readings while READY, saved by manual Save.
do
  local m,mio,ma=F.controller()
  local north = 1 / 111195.0802 -- degrees latitude per metre
  m:tick(0.1); T.eq(m.state,'READY','mileage controller ready')
  T.eq(m:view().totalDistanceKm,0,'session starts at zero mileage')
  for i=1,100 do ma.pose=F.position(i*2*north); m:tick(0.1) end -- 200 m at 20 m/s
  T.near(m:view().totalDistanceKm,0.2,1e-6,'driving 200 m adds 0.2 km')
  T.near(m:view().unsavedDistanceKm,0.2,1e-6,'driven distance shown as unsaved')
  ma.pose=F.position(5000*north); m:tick(0.1)
  T.near(m:view().totalDistanceKm,0.2,1e-6,'teleport jump (50 km/s) is not counted')
  ma.pose=F.position(5010*north); m:tick(0.1)
  T.near(m:view().totalDistanceKm,0.21,1e-6,'driving resumes from the teleport destination')
  ma.valid=false; m:tick(0.1); ma.valid=true; ma.pose=F.position(5020*north); m:tick(0.1)
  T.near(m:view().totalDistanceKm,0.21,1e-6,'movement while position unavailable is not counted')
  ma.pose=F.position(5030*north); m:tick(0)
  T.near(m:view().totalDistanceKm,0.21,1e-6,'zero-time step is not counted')
  T.check(m:manualSave(),'mileage saved')
  T.near(mio.files[A].progression.totalDistanceKm,0.21,1e-6,'save file holds mileage')
  T.eq(m:view().unsavedDistanceKm,0,'nothing unsaved after save')
  ma.pose=F.position(5040*north); m:tick(0.1)
  T.near(m:view().unsavedDistanceKm,0.01,1e-6,'odometer continued from 5030 m after save')
  local r,_,ra=F.controller({io=mio})
  T.near(r:view().totalDistanceKm,0.21,1e-6,'restart loads saved mileage, unsaved distance discarded')
  ra.pose=F.position(5030*north); r:tick(0.1); ra.pose=F.position(5040*north); r:tick(0.1)
  T.near(r:view().totalDistanceKm,0.22,1e-6,'mileage keeps accumulating after resume')
  local before=r:view().totalDistanceKm; ra.pose=F.position(); r:reload(); r:tick(0.1)
  T.eq(r.state,'READY','reload restarts the session at the current position')
  T.near(r:view().totalDistanceKm,0.21,1e-6,'reload discards unsaved mileage'); T.check(before>0.21,'had unsaved mileage')
end

-- Driving before reaching the resume point is not part of the trek.
do
  local m,_,ma=F.controller()
  local north = 1 / 111195.0802
  for i=1,100 do ma.pose=F.position(1+i*2*north,1); m:tick(0.1) end
  T.eq(m:view().totalDistanceKm,0,'no mileage before arriving'); T.eq(m:view().balance,0,'no money before arriving')
  ma.pose=F.position(); m:tick(0.1); ma.pose=F.position(10*north); m:tick(0.1)
  T.near(m:view().totalDistanceKm,0.01,1e-6,'mileage counts from arrival, not from the teleport')
end

-- Money: $100 per counted kilometre, plus a +$10000 test button; both kept by manual Save.
do
  local m,mio,ma=F.controller()
  local north = 1 / 111195.0802
  T.check(not m:addTestMoney(),'test money needs an active profile'); T.eq(m:view().testMoneyAllowed,false,'test button disabled before a position')
  m:tick(0.1)
  for i=1,100 do ma.pose=F.position(i*10*north); m:tick(0.5) end -- 1 km at 20 m/s
  T.eq(m:view().balance,100,'driving 1 km earns $100')
  T.eq(m:view().unsavedBalance,100,'earned money shown as unsaved')
  ma.pose=F.position(1005*north); m:tick(0.5)
  T.eq(m:view().balance,100,'5 m earns 50 cents, not yet a whole dollar')
  ma.pose=F.position(1010*north); m:tick(0.5)
  T.eq(m:view().balance,101,'fractions of a dollar carry over')
  ma.pose=F.position(60000*north); m:tick(0.1)
  T.eq(m:view().balance,101,'teleports earn no money')
  T.check(m:view().testMoneyAllowed,'test button enabled while active')
  T.check(m:addTestMoney(),'test money added'); T.eq(m:view().balance,10101,'test button adds $10000')
  T.eq(mio.writes,0,'earning money never writes to disk')
  T.check(m:manualSave(),'money saved'); T.eq(mio.files[A].progression.balance,10101,'save file holds balance')
  T.eq(m:view().unsavedBalance,0,'nothing unsaved after save')
  m:addTestMoney()
  local r=F.controller({io=mio})
  T.eq(r:view().balance,10101,'restart loads saved balance, unsaved money discarded')
  m:reload(); T.eq(m:view().balance,10101,'reload discards unsaved money')
  mio.writeFails=true; m:tick(0.1); m:manualSave()
  T.check(m:addTestMoney(),'a failed save leaves money and spending available')
end

-- Repair: quote from overall damage, pay through spend(), refuse when short, never charge a failed repair.
do
  local Core = require('beamngEarthEnduro/core')
  T.eq(Core.repairCost(0),0,'undamaged vehicle costs nothing'); T.eq(Core.repairCost(49),0,'below a scratch costs nothing')
  T.eq(Core.repairCost(1000),600,'moderate damage priced from the damage'); T.eq(Core.repairCost(1e9),20000,'repair price capped')
  T.eq(Core.repairCost(0/0),0,'unreadable damage costs nothing')
  local m,mio,ma,_,_,g=F.controller()
  T.check(not m:spend(1,'x'),'spending needs an active profile'); T.check(not m:requestRepairQuote(),'no quote before a position')
  m:tick(0.1)
  T.check(m:view().repairQuoteAllowed,'quote button enabled while active'); T.check(not m:view().repairAllowed,'repair button needs a quote')
  T.check(not m:canAfford(1),'cannot afford anything with $0'); T.check(not m:spend(1,'x'),'spend refused when short')
  T.check(not m:spend(-5,'x'),'negative spend refused'); T.check(not m:spend(0.5,'x'),'part-dollar spend refused')
  T.check(m:requestRepairQuote(),'undamaged quote succeeds'); T.eq(m:view().repairFeedback,'No damage to repair.','no damage message')
  T.eq(m:view().repairAllowed,false,'nothing to repair')
  g.damage=1000; T.check(m:requestRepairQuote(),'damaged quote'); T.eq(m:view().repairQuote,600,'HUD shows the quote')
  T.check(m:view().repairAllowed,'repair button enabled with a quote')
  T.eq(m:view().repairFeedback,'Not enough money yet. You need $600 more.','quote warns when short')
  T.check(not m:repairVehicle(),'repair refused when short'); T.eq(g.repairs,0,'no repair when short')
  T.eq(m:view().balance,0,'balance untouched when short')
  m:addTestMoney()
  g.damage=2000; T.check(not m:repairVehicle(),'new damage needs a new quote'); T.eq(g.repairs,0,'no repair on a stale quote')
  T.eq(m:view().repairQuote,1100,'quote updated to the new damage')
  g.accepts=false; T.check(not m:repairVehicle(),'failed repair reported'); T.eq(m:view().balance,10000,'failed repair is not charged')
  g.accepts=true; T.check(m:repairVehicle(),'repair succeeds'); T.eq(g.repairs,1,'game repair called once')
  T.eq(m:view().balance,8900,'repair charged the quote'); T.eq(m:view().repairQuote,nil,'quote used up')
  T.eq(m:view().repairFeedback,'Repaired for $1,100. The repair cost you 5 minutes. Save to keep the new balance.','repair confirmed')
  T.eq(m:view().unsavedSpending,0,'nothing spent from the saved balance yet')
  T.check(not m:repairVehicle(),'repair needs a new quote after repairing')
  m:manualSave(); g.damage=3000; m:requestRepairQuote(); m:repairVehicle()
  T.eq(m:view().unsavedSpending,1600,'spending since the last save shown'); T.eq(mio.files[A].progression.balance,8900,'spending is not saved without Save')
  g.damage=500; m:requestRepairQuote(); ma.vehicle.id=2; m:tick(0.1)
  T.eq(m:view().repairQuote,nil,'quote hidden after switching vehicle'); T.check(not m:view().repairAllowed,'repair locked after switching vehicle')
  g.vehicleId=2; T.check(not m:repairVehicle(),'old quote does not repair a different vehicle'); T.eq(m:view().repairQuote,350,'requoted for the new vehicle')
  g.unreadable=true; T.check(not m:requestRepairQuote(),'unreadable damage reported')
  T.eq(m:view().repairQuote,nil,'no quote when damage unreadable')
  m:reload(); T.eq(m.quote,nil,'reload clears the quote')
end

-- Parts: changes made in the game's parts menu are billed against the paid parts, Buy charges,
-- Revert or driving off puts the paid parts back, and the damage a change mended is billed too.
do
  local Core = require('beamngEarthEnduro/core')
  local owned = { parts = { a = 'x', b = 'y' }, values = { x = 1000, y = 100 }, names = { x = 'X' } }
  T.eq(Core.partsDiff(owned, owned), nil, 'same parts, nothing to bill')
  local diff = Core.partsDiff(owned, { parts = { a = 'x', b = 'z', c = 'w' }, values = { z = 800 } })
  T.eq(#diff.added, 2, 'swapped and new parts billed'); T.eq(#diff.removed, 1, 'swapped part traded in')
  T.eq(diff.cost, 800 + 250 - 30, 'part values, flat price for unvalued parts, 30% trade-in')
  T.eq(Core.partsDiff(owned, { parts = { a = '', b = 'y' }, values = {} }).cost, 0, 'removing parts never pays out')

  local m,_,ma,_,_,g=F.controller()
  m:tick(0.1); T.eq(m.ownedParts.parts.intake, 'pickup_intake_stock', 'fitted parts taken as paid for')
  T.eq(m:view().partsChange, nil, 'no bill before a change')
  g:fit('intake', 'pickup_intake_race'); m:vehicleSpawned(); m:tick(0.1)
  local bill = m:view().partsChange
  T.eq(bill.partsCost, 770, 'live quote after a parts menu change'); T.eq(bill.repair, 0, 'undamaged car has no repair')
  T.eq(bill.added[1].name, 'pickup_intake_race', 'quote lists the new part'); T.eq(bill.removed[1].name, 'pickup_intake_stock', 'quote lists the old part')
  T.check(not m:view().buyPartsAllowed, 'Buy locked when short'); T.check(m:view().revertPartsAllowed, 'Revert offered')
  T.check(not m:buyParts(), 'buy refused when short'); T.eq(m:view().balance, 0, 'nothing charged when short')
  T.check(m:revertParts(false), 'revert accepted'); T.eq(g.fitted.intake, 'pickup_intake_stock', 'paid parts put back')
  m:vehicleSpawned(); m:tick(0.1); T.eq(m:view().partsChange, nil, 'no bill after reverting')

  -- Trying parts on and swapping back costs nothing.
  g:fit('intake', 'pickup_intake_race'); m:vehicleSpawned(); m:tick(0.1)
  g:fit('intake', 'pickup_intake_stock'); m:vehicleSpawned(); m:tick(0.1)
  T.eq(m:view().partsChange, nil, 'swapping back clears the bill'); T.eq(m:view().partsFeedback, 'Part changes undone. Nothing to pay.', 'told nothing is owed')

  -- A damaged car: the change mends it, so the repair joins the bill and stays after more changes.
  m:addTestMoney(); g.damage = 1000; m:tick(0.1)
  T.check(m:requestRepairQuote(), 'repair quoted before the change')
  g:fit('turbo', 'pickup_turbo'); m:vehicleSpawned(); m:tick(0.1)
  T.eq(m:view().partsChange.repair, 600, 'repair added to the parts bill'); T.eq(m:view().partsChange.cost, 3000, 'bill totals parts and repair')
  T.eq(m:view().repairQuote, nil, 'separate repair quote dropped'); T.check(not m:repairVehicle(), 'repair waits for the parts bill')
  g:fit('intake', 'pickup_intake_race'); m:vehicleSpawned(); m:tick(0.1)
  T.eq(m:view().partsChange.repair, 600, 'repair kept across changes'); T.eq(m:view().partsChange.cost, 3770, 'bill updated live')
  T.check(m:view().buyPartsAllowed, 'Buy enabled when affordable')
  g.fitted.turbo = nil
  T.check(not m:buyParts(), 'changed parts re-quote instead of charging'); T.eq(m:view().partsChange.cost, 1370, 're-quoted bill')
  T.check(m:buyParts(), 'buy succeeds'); T.eq(m:view().balance, 10000 - 1370, 'bill charged once')
  T.eq(m:view().partsChange, nil, 'bill cleared'); T.eq(m.ownedParts.parts.intake, 'pickup_intake_race', 'new parts now owned')
  T.check(not m:buyParts(), 'nothing left to buy')

  -- Driving off without paying puts the paid parts back and still charges the repair.
  ma.pose = F.position(0, 0); m:tick(0.1); g.damage = 200; m:tick(0.1)
  g:fit('turbo', 'pickup_turbo'); m:vehicleSpawned(); m:tick(0.1)
  ma.pose = F.position(0, 0.0001); m:tick(0.1); T.check(m:view().partsChange ~= nil, 'short move keeps the bill')
  g.accepts = false; ma.pose = F.position(0, 0.001); m:tick(0.1); m:tick(0.1)
  T.check(m:view().partsChange ~= nil, 'failed revert keeps the bill'); T.eq(g.fitted.turbo, 'pickup_turbo', 'parts unchanged on failed revert')
  g.accepts = true; ma.pose = F.position(0, 0.002); m:tick(0.1)
  T.eq(g.fitted.turbo, nil, 'driving off puts the paid parts back'); T.eq(m:view().partsChange, nil, 'bill cleared after driving off')
  T.eq(m:view().balance, 10000 - 1370 - 200 + 1, 'driving off still pays the repair (the first 11 m driven earned $1)')

  g.partsUnreadable = true; m:vehicleSpawned(); m:tick(0.1); T.check(m.partsCheckDue, 'unreadable parts retried')
end

-- A fresh start swaps the first vehicle for the starter car, once, and its parts come free.
do
  local Core = require('beamngEarthEnduro/core')
  local m,_,ma,_,_,g=F.controller()
  g.starter = { engine = 'burnside_engine_i6', intake = 'burnside_intake_i6' }
  ma.valid = false; m:tick(0.1); T.eq(#g.spawns, 0, 'no starter car before a vehicle position')
  ma.valid = true; ma.pose = F.position(1, 1); m:tick(0.1); m:tick(0.1)
  T.eq(#g.spawns, 0, 'starter car waits at the start')
  ma.pose = F.position(); m:tick(0.1); m:tick(0.1)
  T.eq(#g.spawns, 1, 'starter car spawned once on a fresh start')
  T.eq(g.spawns[1].model, Core.STARTER_MODEL, 'starter model'); T.eq(g.spawns[1].config, 'vehicles/burnside/worldironmanenduro_starter.pc', 'starter config file')
  m:vehicleSpawned(); m:tick(0.1)
  T.eq(m.ownedParts.parts.engine, 'burnside_engine_i6', 'starter parts taken as paid for'); T.eq(m:view().partsChange, nil, 'starter car is free')
  m:tick(0.1); T.eq(#g.spawns, 1, 'starter spawned only once per load')
  m:reload(); m:tick(0.1); T.eq(#g.spawns, 1, 'already in the starter car, so not respawned')
  g.spawnedFrom = nil; m:reload(); m:tick(0.1); T.eq(#g.spawns, 2, 'reload before saving goes back to the starter car')

  -- Replacing a car of the same model is still free.
  m,_,_,_,_,g=F.controller()
  g.model = Core.STARTER_MODEL; g.starter = { engine = 'burnside_engine_i6' }
  m:tick(0.1); m:vehicleSpawned(); m:tick(0.1)
  T.eq(m:view().partsChange, nil, 'same-model starter swap is not billed'); T.eq(m.ownedParts.parts.engine, 'burnside_engine_i6', 'starter adopted')
  g:fit('engine', 'pickup_engine_v8'); m:vehicleSpawned(); m:tick(0.1)
  T.check(m:view().partsChange ~= nil, 'later part changes are billed')

  -- A failed spawn is logged and not retried every frame.
  local logs
  m,_,_,_,logs,g=F.controller(); g.accepts = false
  m:tick(0.1); m:tick(0.1); m:tick(0.1)
  T.eq(#g.spawns, 0, 'nothing spawned'); T.check(m.vehicleProvided, 'not retried')
  local logged = false
  for _, line in ipairs(logs) do logged = logged or line:find('starter_car_failed', 1, true) ~= nil end
  T.check(logged, 'failure logged'); T.eq(m.state, 'READY', 'play carries on')

  -- Save keeps the paid-for car, and loading the save puts the player back in it.
  local io = F.io({ [CONFIG] = F.config() })
  m,_,_,_,_,g=F.controller({ io = io })
  g.starter = { engine = 'burnside_engine_i6', intake = 'burnside_intake_i6' }
  m:tick(0.1); m:vehicleSpawned(); m:tick(0.1); m:addTestMoney()
  g:fit('intake', 'burnside_intake_race'); m:vehicleSpawned(); m:tick(0.1)
  T.check(m:buyParts(), 'upgrade bought')
  g:fit('engine', 'burnside_engine_v8'); m:vehicleSpawned(); m:tick(0.1)
  T.check(m:view().partsChange ~= nil, 'unpaid change pending')
  T.check(m:manualSave(), 'saved with a parts bill open')
  local saved = io.files[A].vehicle.config
  T.eq(saved.model, Core.STARTER_MODEL, 'car model saved'); T.eq(saved.parts.intake, 'burnside_intake_race', 'bought part saved')
  T.eq(saved.parts.engine, 'burnside_engine_i6', 'unpaid part not saved')
  local balance = m:view().balance
  local r,_,ra,_,_,rg=F.controller({ io = io })
  ra.pose = F.position(5, 5); r:tick(0.1); r:tick(0.1)
  T.eq(#rg.spawns, 0, 'saved car waits at the last save')
  ra.pose = F.position(); r:tick(0.1)
  T.eq(#rg.spawns, 1, 'saved car spawned on arrival'); T.eq(rg.spawns[1].model, Core.STARTER_MODEL, 'saved model spawned')
  T.eq(rg.fitted.intake, 'burnside_intake_race', 'saved parts fitted')
  r:vehicleSpawned(); r:tick(0.1)
  T.eq(r:view().partsChange, nil, 'saved car is not billed'); T.eq(r.ownedParts.parts.intake, 'burnside_intake_race', 'saved parts owned')
  T.eq(r:view().balance, balance, 'balance restored')
  r:tick(0.1); T.eq(#rg.spawns, 1, 'saved car spawned once per load')

  -- Save keeps the car's damage. The restored car looks new, but its repair is still owed.
  io = F.io({ [CONFIG] = F.config() })
  m,_,_,_,_,g=F.controller({ io = io })
  m:tick(0.1); m:vehicleSpawned(); m:tick(0.1)
  g.damage = 1000; m:tick(0.1)
  T.check(m:manualSave(), 'saved a damaged car'); T.eq(io.files[A].vehicle.damage, 1000, 'damage saved with the car')
  r,_,_,_,_,rg=F.controller({ io = io })
  r:tick(0.1); r:vehicleSpawned(); r:tick(0.1)
  T.eq(rg.damage, 0, 'restored car looks new'); T.eq(r:view().repairOwed, 600, 'HUD shows the repair still owed')
  T.check(r:requestRepairQuote(), 'owed repair can be quoted'); T.eq(r:view().repairQuote, 600, 'quote includes the owed damage')
  rg.damage = 1000; r:requestRepairQuote(); T.eq(r:view().repairQuote, 1100, 'new damage adds to the owed damage')
  T.check(r:manualSave(), 'saved again unpaid'); T.eq(io.files[B].vehicle.damage, 2000, 'unpaid damage carried through saves')
  r:addTestMoney(); r:requestRepairQuote(); T.check(r:repairVehicle(), 'owed repair paid')
  T.eq(r:view().repairOwed, nil, 'nothing owed after paying'); T.eq(r:view().balance, 10000 - 1100, 'charged once')
  T.check(r:manualSave(), 'saved after paying'); T.eq(io.files[A].vehicle.damage, nil, 'no damage saved once repaired')

  -- Changing parts on a restored car bills the owed repair with the parts.
  io.files[A].vehicle.damage = 1000; io.files[A].progression.balance = 10000
  r,_,_,_,_,rg=F.controller({ io = io })
  r:tick(0.1); r:vehicleSpawned(); r:tick(0.1); r:tick(0.1)
  rg:fit('intake', 'pickup_intake_race'); r:vehicleSpawned(); r:tick(0.1)
  T.eq(r:view().partsChange.repair, 600, 'owed repair joins the parts bill')
  T.check(r:buyParts(), 'parts and owed repair bought'); T.eq(r:view().repairOwed, nil, 'owed repair settled by the parts bill')
  r:reload(); T.eq(r:view().repairOwed, 600, 'a reload without saving brings the debt back')

  -- An older save without a car config keeps the player's own vehicle.
  io = F.io({ [CONFIG] = F.config(), [A] = F.save(1) })
  m,_,_,_,_,g=F.controller({ io = io })
  m:tick(0.1); m:tick(0.1); T.eq(#g.spawns, 0, 'no spawn when resuming a save without a car')
end

-- Stages: the first stage is Stage 1: Zoji La Pass, the HUD shows the distance to its finish, and reaching the
-- finish completes the stage and saves it.
do
  local S = require('beamngEarthEnduro/stages')
  local first = S.get('stage_1')
  T.eq(first.name, 'Stage 1: Zoji La Pass', 'Stage 1 defined'); T.eq(S.first().id, 'stage_1', 'Stage 1 is the first stage')
  T.eq(first.start.latitude, 34.271288, 'Stage 1 start latitude'); T.eq(first.finish.longitude, 75.80991, 'Stage 1 finish longitude')
  T.eq(S.get('zoji_la').id, 'stage_1', 'the stage old id still finds the stage')
  T.eq(S.get('nowhere'), nil, 'unknown stage')
  local m,mio,ma=F.controller()
  T.eq(m:view().stage.name, 'Stage 1: Zoji La Pass', 'HUD names the stage')
  m:tick(0.1); T.eq(m.profile.stage, 'stage_1', 'new profile is on the first stage')
  T.check(m:view().finishDistanceMetres > 1000000, 'distance to the finish shown once on the stage')
  T.eq(m:view().stage.finishTown, 'Dras, Ladakh', 'HUD names the finish town'); T.eq(m:view().stage.startTown, 'Sind River, Kashmir', 'HUD names the start town')
  T.check(m:view().stage.briefing:find('Sind River, Kashmir'), 'HUD has the stage briefing')
  T.check(type(m:view().finishDirection) == 'string', 'HUD gives the direction to the finish')
  T.eq(m:view().stageFinished, false, 'stage not finished at the start')
  ma.pose = F.position(first.finish.latitude + 0.0005, first.finish.longitude); m:tick(0.1)
  T.check(m:view().stageFinished, 'reaching the finish completes the stage')
  T.eq(m:view().stateLabel, 'STAGE COMPLETE', 'celebration label'); T.check(m:view().sessionStatus:find('conquered'), 'celebration message')
  T.eq(mio.files[A].finished, true, 'finish saved straight away'); T.eq(mio.files[A].stage, 'stage_1', 'stage saved')
  local r = F.controller({ io = mio })
  T.check(r:view().stageFinished, 'a loaded save remembers the finish')
  -- Saves from before stages belong to the first stage; a stage this version lacks pauses Enduro.
  r = F.controller({ io = F.io({ [CONFIG] = F.config(), [A] = F.save(1) }) })
  T.eq(r:view().stage.name, 'Stage 1: Zoji La Pass', 'older save is on the first stage')
  local renamed = F.save(1); renamed.stage = 'zoji_la'
  r = F.controller({ io = F.io({ [CONFIG] = F.config(), [A] = renamed }) })
  T.eq(r.state ~= 'ERROR' and r:view().stage.name, 'Stage 1: Zoji La Pass', 'a save under the old stage id still loads')
  local unknown = F.save(1); unknown.stage = 'later'
  r = F.controller({ io = F.io({ [CONFIG] = F.config(), [A] = unknown }) })
  T.eq(r.state, 'ERROR', 'unknown stage pauses Enduro'); T.check(not r:view().restartAllowed, 'unknown stage cannot be restarted')
end

-- Stage 2: Colo River follows Stage 1. Finishing Stage 1 offers it; starting it carries the car and
-- money to Windsor, and Restart on Stage 2 goes back to how the player arrived there.
do
  local S = require('beamngEarthEnduro/stages')
  local second = S.get('stage_2')
  T.eq(second.name, 'Stage 2: Colo River', 'Stage 2 defined'); T.eq(S.after('stage_1').id, 'stage_2', 'Stage 2 follows Stage 1')
  T.eq(second.start.latitude, -33.601664, 'Stage 2 starts at Windsor'); T.eq(second.finish.longitude, 150.790919, 'Stage 2 finishes at Colo Heights')
  T.eq(second.targetSeconds, 30 * 60, 'Stage 2 limit is 30 min'); T.eq(S.after('stage_2'), nil, 'Stage 2 is the last stage')
  local m,mio,ma,_,_,g=F.controller()
  m:tick(0.1); m:vehicleSpawned(); m:tick(0.1)
  T.eq(m:view().stage.number, 1, 'HUD numbers the stage'); T.eq(m:view().stage.count, 2, 'HUD counts the stages')
  T.eq(m:view().upcomingStage.name, 'Stage 2: Colo River', 'Stage 2 shown as up next while driving Stage 1')
  T.eq(m:view().nextStage, nil, 'next stage not offered before the finish'); T.check(not m:startNextStage(), 'next stage refused before the finish')
  m:addTestMoney(); g.damage = 200
  local first = S.get('stage_1')
  ma.pose = F.position(first.finish.latitude, first.finish.longitude); m:tick(0.1)
  T.check(m:view().stageFinished, 'Stage 1 finished'); T.eq(m:view().nextStage.name, 'Stage 2: Colo River', 'Stage 2 offered')
  T.check(m:view().nextStageAllowed, 'Start Stage 2 allowed'); T.check(m:view().sessionStatus:find('Windsor, NSW'), 'status points to Windsor')
  g:fit('intake', 'pickup_intake_race'); m:vehicleSpawned(); m:tick(0.1)
  T.check(not m:view().nextStageAllowed, 'an open parts bill blocks the next stage'); T.check(not m:startNextStage(), 'next stage refused with a bill open')
  m:revertParts(false); m:tick(0.1); g.damage = 200
  local balance = m:view().balance
  T.check(m:startNextStage(), 'Stage 2 started')
  T.eq(m.stage.id, 'stage_2', 'now on Stage 2'); T.eq(m.mode, 'start', 'player sent to the Stage 2 start')
  T.eq(m:view().balance, balance, 'money carried over'); T.eq(m:view().totalDistanceKm, 0, 'mileage starts again')
  T.eq(m:view().timer.drivingSeconds, 0, 'clock starts again'); T.eq(m:view().stageFinished, false, 'Stage 2 not finished')
  T.eq(m:view().resume.latitude, second.start.latitude, 'Windsor coordinates shown'); T.check(m:view().carriedCar, 'car is carried')
  T.check(m:view().saveFeedback:find('to get your car'), 'player told the car comes with them')
  m:tick(0.1); T.check(m:view().sessionStatus:find('Your car is waiting'), 'go-to-start message says the car is waiting')
  local saved = mio.files[B]
  T.eq(saved.stage, 'stage_2', 'Stage 2 saved'); T.eq(saved.atStart, true, 'saved at the start'); T.eq(saved.completedStages[1], 'stage_1', 'Stage 1 recorded as completed')
  T.eq(saved.entry.balance, balance, 'arrival money saved'); T.eq(saved.entry.vehicle.config.model, 'pickup', 'arrival car saved')
  T.eq(saved.entry.vehicle.damage, 200, 'unpaid damage carried')
  local r = F.controller({ io = mio }); T.eq(r.stage.id, 'stage_2', 'reload stays on Stage 2'); T.eq(r.mode, 'start', 'reload still heads to Windsor')
  local spawns = #g.spawns
  ma.pose = F.position(second.start.latitude, second.start.longitude); m:tick(0.1)
  T.eq(#g.spawns, spawns + 1, 'car given at Windsor'); T.eq(g.spawns[#g.spawns].model, 'pickup', 'it is the Stage 1 car, not the starter')
  T.eq(type(g.spawns[#g.spawns].config), 'table', 'spawned from the carried config')
  m:vehicleSpawned(); m:tick(0.1)
  T.check(m:view().repairOwed > 0, 'the unpaid repair comes with the car')
  m:addTestMoney(); T.check(m:manualSave(), 'saved on Stage 2'); T.eq(mio.files[A].entry.balance, balance, 'Save keeps the arrival snapshot')
  T.eq(mio.files[A].completedStages[1], 'stage_1', 'Save keeps the completed stages')
  T.check(not m:restartStage() and m:restartStage(), 'Stage 2 restarted')
  T.eq(m:view().balance, balance, 'restart goes back to the arrival money'); T.eq(m.mode, 'start', 'restart sends the player to Windsor')
  T.check(m.carriedCar, 'restart brings the arrival car'); T.eq(m.stage.id, 'stage_2', 'restart stays on Stage 2')
  ma.pose = F.position(second.start.latitude, second.start.longitude); m:tick(0.1)
  T.eq(g.spawns[#g.spawns].model, 'pickup', 'arrival car given again after the restart')
  m:vehicleSpawned(); m:tick(0.1)
  ma.pose = F.position(second.finish.latitude, second.finish.longitude); m:tick(0.1)
  T.check(m:view().stageFinished, 'Stage 2 finished'); T.eq(m:view().nextStage, nil, 'nothing after Stage 2'); T.eq(m:view().upcomingStage, nil, 'nothing up next after Stage 2')
  T.check(m:view().sessionStatus:find('More stages are coming'), 'last stage says more are coming')
end

-- Ironman: a wrecked car the player cannot pay to repair ends the run after a short warning,
-- the game over is saved, and Restart stage starts again from the stage start.
do
  local Core = require('beamngEarthEnduro/core')
  local m,mio,ma,_,_,g=F.controller()
  g.starter = { engine = 'burnside_engine_i6' }
  m:tick(0.1); m:vehicleSpawned(); m:tick(0.1)
  g.damage = Core.WRECKED_DAMAGE - 1; m:tick(0.1)
  T.eq(m:view().wreck, nil, 'heavy but not wrecked damage is no game over')
  g.damage = Core.WRECKED_DAMAGE; m:tick(0.1)
  T.check(m:view().wreck ~= nil, 'wrecked car the player cannot pay for starts the countdown')
  T.eq(m:view().stateLabel, 'WRECKED', 'HUD warns of the wreck'); T.eq(m:view().wreck.cost, Core.repairCost(Core.WRECKED_DAMAGE), 'warning shows the repair')
  m:addTestMoney(); m:tick(0.1); T.eq(m:view().wreck, nil, 'being able to pay ends the warning')
  g.damage = 40000; m:tick(0.1); T.check(m:view().wreck ~= nil, 'a bigger wreck than the balance warns again')
  F.advance(m, Core.GAME_OVER_DELAY + 0.5)
  T.check(m:view().gameOver, 'still unable to pay after the warning: game over'); T.eq(m:view().stateLabel, 'GAME OVER', 'game over label')
  T.check(m:view().sessionStatus:find('Restart stage'), 'player told how to go on')
  T.eq(mio.files[A].gameOver, true, 'game over saved straight away')
  T.check(not m:view().saveAllowed and not m:view().testMoneyAllowed and not m:view().repairQuoteAllowed, 'everything but restart locked')
  T.check(not m:manualSave(), 'save refused after game over'); T.check(not m:addTestMoney(), 'no money after game over')
  local distance = m:view().totalDistanceKm
  ma.pose = F.position(0.0001, 0); m:tick(0.1); T.eq(m:view().totalDistanceKm, distance, 'no mileage after game over')
  m:reload(); T.check(m:view().gameOver, 'reloading does not undo game over')
  T.check(m:view().restartAllowed, 'restart offered')
  local spawns = #g.spawns
  T.check(m:restartStage(), 'game over restarts with one press')
  T.eq(m:view().gameOver, false, 'restart clears game over'); T.eq(m:view().balance, 0, 'money reset')
  T.eq(m:view().totalDistanceKm, 0, 'mileage reset'); T.eq(m.mode, 'start', 'player sent to the start')
  T.eq(m:view().resume.latitude, 0, 'start coordinates shown'); T.eq(mio.files[B].atStart, true, 'restart saved')
  g.spawnedFrom = nil; ma.pose = F.position(); m:tick(0.1)
  T.eq(#g.spawns, spawns + 1, 'starter car given at the start again')
  local r = F.controller({ io = mio }); T.eq(r.mode, 'start', 'a restarted save still sends the player to the start')
  T.check(r:view().resume ~= nil and not r:view().gameOver, 'restarted save loads at the start')
  local config = mio.files[CONFIG]; mio.files[CONFIG] = { base = F.position(0.5, 0.5), resumeRadiusMetres = 50 }
  r = F.controller({ io = mio }); T.eq(r:view().resume.latitude, 0.5, 'a restarted save goes to the stage start after it moves')
  mio.files[CONFIG] = config

  -- Restarting by choice needs a confirming second press.
  m:addTestMoney(); T.check(not m:restartStage(), 'first press only asks to confirm')
  T.check(m:view().restartArmed, 'button asks to confirm'); T.eq(m:view().balance, 10000, 'nothing lost on the first press')
  T.check(m:restartStage(), 'second press restarts'); T.eq(m:view().balance, 0, 'confirmed restart resets the money')
  mio.writeFails = true; m:restartStage(); T.check(not m:restartStage(), 'failed restart reported')
  T.check(m:view().saveFeedback:find('try again'), 'failed restart says to try again')

  -- A part change cannot be used to mend a wreck the player cannot pay for.
  m,_,_,_,_,g=F.controller()
  m:tick(0.1); m:vehicleSpawned(); m:tick(0.1)
  g.damage = 40000; m:tick(0.1)
  g:fit('intake', 'pickup_intake_race'); m:vehicleSpawned(); m:tick(0.1)
  T.check(not m:revertParts(false), 'revert refused for an unpaid wreck'); T.check(m:view().wreck ~= nil, 'wreck still counted after the change')
  F.advance(m, Core.GAME_OVER_DELAY + 0.5); T.check(m:view().gameOver, 'parts change does not escape game over')
end

-- Each stage sets its starting money: Stage 1 starts with $3000, on a fresh start and after a restart.
do
  T.eq(F.STARTING_MONEY, 3000, 'Stage 1 starts with $3000')
  local m,mio,ma=F.controller({ startingMoney = 3000 })
  T.eq(m:view().balance, 3000, 'starting money shown before the first position')
  m:tick(0.1); T.eq(m:view().balance, 3000, 'fresh start has the starting money')
  T.eq(m:view().unsavedBalance, 0, 'starting money is not shown as unsaved earnings')
  m:addTestMoney(); T.check(m:manualSave(), 'saved'); T.eq(mio.files[A].progression.balance, 13000, 'saved balance')
  m:restartStage(); T.check(m:restartStage(), 'restarted')
  T.eq(m:view().balance, 3000, 'restart resets to the starting money'); T.eq(mio.files[B].progression.balance, 3000, 'restart saved with the starting money')
end

-- Cars: a car picked in the vehicle selector is billed at its game Value less the trade-in of the
-- player's car; Buy keeps it, Revert or driving off brings the player's car back.
do
  local m,_,ma,_,_,g=F.controller()
  m:tick(0.1); m:addTestMoney()
  T.eq(m.ownedParts.value, 20000, 'own car priced from its game Value')
  g.damage = 2000; m:tick(0.1)
  -- Replaced in place: the swap mends the old car, so its repair comes off the trade-in.
  g.model, g.fitted, g.damage = 'sport', { engine = 'sport_v12' }, 0; m:vehicleSpawned(); m:tick(0.1)
  local bill = m:view().carChange
  T.eq(bill.price, 40000, 'new car priced from its game Value'); T.eq(bill.tradeIn, 10000 - 1100, 'half the old Value less its repair')
  T.eq(bill.cost, 40000 - 8900, 'bill is price less trade-in'); T.eq(m:view().partsChange, nil, 'no parts bill for a new car')
  T.check(not m:view().buyCarAllowed, 'Buy car locked when short'); T.check(m:view().revertCarAllowed, 'Revert offered')
  T.check(not m:buyCar(), 'buy refused when short'); T.eq(m:view().balance, 10000, 'nothing charged when short')
  T.check(not m:view().repairAllowed, 'repair locked during a car bill'); T.check(not m:repairVehicle(), 'repair waits for the car bill')
  T.eq(m:savedVehicleDamage(), 2000, 'Save keeps the old car and its damage')
  g:fit('turbo', 'pickup_turbo'); m:vehicleSpawned(); m:tick(0.1)
  T.eq(m:view().carChange.extras, 2400, 'parts fitted to the new car are billed'); T.eq(m:view().carChange.cost, 33500, 'bill updated live')
  T.check(m:revertCar(false), 'revert accepted'); T.eq(g.model, 'pickup', 'own car respawned in place')
  T.eq(g.fitted.intake, 'pickup_intake_stock', 'own car has its paid parts'); T.eq(m:view().repairOwed, 1100, 'respawned car still owes its repair')
  m:vehicleSpawned(); m:tick(0.1); T.eq(m:view().carChange, nil, 'no bill after reverting'); T.eq(m.ownedParts.value, 20000, 'own car keeps its Value')

  -- A cheap car: the trade-in covers it, and never pays out.
  g.model, g.fitted = 'burnside', { engine = 'burnside_i6' }; m:vehicleSpawned(); m:tick(0.1)
  T.eq(m:view().carChange.cost, 0, 'trade-in covers a cheaper car')
  T.check(m:buyCar(), 'buy succeeds'); T.eq(m:view().balance, 10000, 'trade-in never pays out')
  T.eq(m.ownedParts.model, 'burnside', 'new car is now owned'); T.eq(m:view().repairOwed, nil, 'old car repair settled by the trade-in')
  T.eq(m:view().carChange, nil, 'bill cleared'); T.check(not m:buyCar(), 'nothing left to buy')

  -- Spawned as an extra car: driving off puts the player back in their own car, damage and all.
  ma.pose = F.position(0, 0); g.damage = 300; m:tick(0.1)
  g.parked[1] = { model = g.model, fitted = F.copy(g.fitted), damage = g.damage }
  g.vehicleId, ma.vehicle.id, g.model, g.fitted, g.damage = 9, 9, 'sport', { engine = 'sport_v12' }, 0
  m:vehicleSpawned(); m:tick(0.1)
  T.eq(m:view().carChange.tradeIn, 1750 - 250, 'extra car trades in the car left behind')
  ma.pose = F.position(0, 0.001); m:tick(0.1)
  T.eq(g.vehicleId, 1, 'driving off puts the player back in their car'); T.eq(m:view().carChange, nil, 'bill cleared after driving off')
  T.eq(g.damage, 300, 'own car keeps its real damage'); T.eq(m:view().balance, 10000, 'nothing charged for driving off')
  ma.vehicle.id = 1; m:tick(0.1); T.eq(m:view().carChange, nil, 'back in own car, no bill')
end

-- Display throttling and duplicate mount notifications do not write or spam logs.
local events,logs
controller,localIO,a,events,logs=F.controller(); controller:mount(true)
F.advance(controller,1)
T.check(#events<=4,'HUD capped at four events per second')
T.eq(events[1].name,'BeamNGEarthEnduroState','namespaced UI event')
local before=#logs; controller:mount(true); controller:mount(true)
T.eq(#logs,before,'mount heartbeat is not logged repeatedly')
controller:mount(false); local count=#events; F.advance(controller,1)
T.eq(#events,count,'unmounted HUD receives no events')
T.done('controller')
