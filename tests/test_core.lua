local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local P = require('beamngEarthEnduro/persistence')
local CONFIG = '/settings/beamngEarthEnduro/config.json'
local A, B = P.DIRECTORY .. 'save-a.json', P.DIRECTORY .. 'save-b.json'

local c,io,adapter=F.controller()
T.eq(c.state,'EARTH_UNAVAILABLE','waits for the first vehicle position')
T.eq(c.profile,nil,'no profile initialized prematurely')
T.check(not c:manualSave(),'save before any position rejected'); T.eq(io.writes,0,'rejected save performs no writes')
adapter.pose=F.position(1,1); c:tick(0.1)
T.eq(c.state,'READY','any valid position unlocks save, away from base')
T.check(c:view().saveAllowed,'save button enabled away from base')
T.check(c:view().baseDistanceMetres>100000,'HUD has geographic base distance')
T.check(c.profile~=nil,'profile created at first position'); T.eq(c.profile.generation,0,'new profile in memory')
T.eq(c:view().target,nil,'no saved location shown before the first save')
T.eq(c.profile.base.latitude,0,'new profile uses configured base')
T.eq(io.writes,0,'starting a session has no disk writes'); T.eq(c.profile.progression.balance,0,'new profile starts with no money')
local initialTarget=F.copy(c.startupTarget)
adapter.pose=F.position(2,3); c:tick(0.1)
T.eq(c.state,'READY','travel anywhere stays ready')
T.eq(c.profile.progression.totalDistanceKm,0,'teleport-sized jump adds no mileage')
T.check(c:manualSave(),'manual save succeeds')
T.eq(io.writes,1,'one write per manual click'); T.eq(c.profile.resume.latitude,2,'new position saved')
T.eq(c:view().target.latitude,2,'HUD shows the location just saved')
T.eq(c.profile.base.latitude,0,'save leaves original base fixed')
T.eq(c.profile.vehicle.model,'pickup','available vehicle identity saved')
T.check(P.equal(c.startupTarget,initialTarget),'save does not mutate arrival target')
local disk=F.copy(io.files[A])
F.advance(c,10); T.eq(io.writes,1,'no periodic or per-frame saves')
T.eq(c.profile.progression.balance,0,'standing still earns no money')

-- A separate controller represents a real restart: the target is the saved location.
c,io,adapter=F.controller({io=io})
T.eq(c.mode,'resume','restart loads the save'); T.eq(c.startupTarget.latitude,2,'saved location loaded')
F.advance(c,5); T.eq(c.state,'READY','save unlocks away from the saved location')
T.eq(io.writes,1,'loading and driving leave disk untouched'); T.check(P.equal(io.files[A],disk),'save survives restart')
adapter.pose=F.position(2,3); c:tick(0.1); T.eq(c.state,'READY','driving to the saved location stays ready')
adapter.valid=false; adapter.reason='vehicle_required'; c:tick(0.1)
T.eq(c.state,'EARTH_UNAVAILABLE','no vehicle position pauses session')
T.check(not c:manualSave(),'save locked without vehicle position'); T.eq(io.writes,1,'no position cannot write')
adapter.valid=true; adapter.pose=F.position(2.1,3.1); c:tick(0.1)
T.eq(c.state,'READY','arrived session resumes wherever the vehicle is')
T.eq(c.startupTarget.latitude,2,'recovery never mutates saved target')
T.eq(c:view().target.latitude,2,'HUD saved target remains saved target')
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
T.check(not c:manualSave(),'write failure visible'); T.eq(c.state,'ERROR','uncertain write locks session')
T.eq(io.files[A].resume.latitude,6,'latest valid generation retained on failure')
T.check(not c:manualSave(),'error does not retry unsafe write')

-- Missing configuration selects the built-in base; invalid overrides/saves stay locked.
for _, scenario in ipairs({
  { files={[CONFIG]={base={}}}, state='CONFIG_REQUIRED' },
  { files={[CONFIG]=F.config(),[A]='truncated'}, state='ERROR' },
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

-- Missing configuration selects the built-in base and saving works straight away.
do
  local localIO=F.io({}); local controller=F.controller({io=localIO})
  F.advance(controller,5); T.eq(controller.state,'READY','built-in base session is ready')
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

-- Money: $50 per counted kilometre, plus a +$10000 test button; both kept by manual Save.
do
  local m,mio,ma=F.controller()
  local north = 1 / 111195.0802
  T.check(not m:addTestMoney(),'test money needs an active profile'); T.eq(m:view().testMoneyAllowed,false,'test button disabled before a position')
  m:tick(0.1)
  for i=1,100 do ma.pose=F.position(i*10*north); m:tick(0.5) end -- 1 km at 20 m/s
  T.eq(m:view().balance,50,'driving 1 km earns $50')
  T.eq(m:view().unsavedBalance,50,'earned money shown as unsaved')
  ma.pose=F.position(1010*north); m:tick(0.5)
  T.eq(m:view().balance,50,'10 m earns 50 cents, not yet a whole dollar')
  ma.pose=F.position(1020*north); m:tick(0.5)
  T.eq(m:view().balance,51,'fractions of a dollar carry over')
  ma.pose=F.position(60000*north); m:tick(0.1)
  T.eq(m:view().balance,51,'teleports earn no money')
  T.check(m:view().testMoneyAllowed,'test button enabled while active')
  T.check(m:addTestMoney(),'test money added'); T.eq(m:view().balance,10051,'test button adds $10000')
  T.eq(mio.writes,0,'earning money never writes to disk')
  T.check(m:manualSave(),'money saved'); T.eq(mio.files[A].progression.balance,10051,'save file holds balance')
  T.eq(m:view().unsavedBalance,0,'nothing unsaved after save')
  m:addTestMoney()
  local r=F.controller({io=mio})
  T.eq(r:view().balance,10051,'restart loads saved balance, unsaved money discarded')
  m:reload(); T.eq(m:view().balance,10051,'reload discards unsaved money')
  mio.writeFails=true; m:tick(0.1); m:manualSave()
  T.check(not m:addTestMoney(),'test money locked after a save error')
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
