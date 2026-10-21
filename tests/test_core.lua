local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local P = require('beamngEarthEnduro/persistence')
local CONFIG = '/settings/beamngEarthEnduro/config.json'
local A, B = P.DIRECTORY .. 'save-a.json', P.DIRECTORY .. 'save-b.json'

local c,io,adapter=F.controller()
T.eq(c.state,'START_LOCATION_REQUIRED','first launch requires base arrival')
T.eq(c.profile,nil,'no profile initialized prematurely')
T.check(not c:manualSave(),'locked save rejected'); T.eq(io.writes,0,'locked save performs no writes')
adapter.pose=F.position(1,1); F.advance(c,5)
T.eq(c.state,'START_LOCATION_REQUIRED','arbitrary starting location never unlocks')
T.eq(c.profile,nil,'profile absent away from base'); T.check(c:view().baseDistanceMetres>100000,'HUD has geographic base distance')
adapter.pose=F.position(); F.advance(c,2)
T.eq(c.state,'VERIFYING_LOCATION','arrival needs stability')
T.eq(c.profile,nil,'verification does not initialize profile early')
adapter.valid=false; adapter.reason='earth_transition'; c:tick(0.1,0.1)
T.eq(c.state,'EARTH_UNAVAILABLE','transition suspends verification'); T.eq(c.verifier.elapsed,0,'transition resets interval')
adapter.valid=true; F.advance(c,3)
T.eq(c.state,'VERIFYING_LOCATION','first sample time not counted toward three seconds')
c:tick(0.1,0.1); T.eq(c.state,'READY','continuous valid arrival unlocks')
T.check(c.profile~=nil,'profile created after arrival'); T.eq(c.profile.generation,0,'new profile in memory')
T.eq(io.writes,0,'verification has no disk writes'); T.eq(c.profile.progression.balance,0,'placeholder balance')
local initialTarget=F.copy(c.startupTarget)
adapter.pose=F.position(2,3); c:tick(0.1,0.1)
T.eq(c.state,'READY','ordinary travel may leave base after verification')
T.check(c:manualSave(),'manual save succeeds with fresh pose')
T.eq(io.writes,1,'one write per manual click'); T.eq(c.profile.resume.latitude,2,'new position saved')
T.eq(c.profile.base.latitude,0,'save leaves original base fixed')
T.eq(c.profile.vehicle.model,'pickup','available vehicle identity saved')
T.check(P.equal(c.startupTarget,initialTarget),'save does not mutate arrival target')
local disk=F.copy(io.files[A])
F.advance(c,10); T.eq(io.writes,1,'no periodic or per-frame saves')
T.eq(c.profile.progression.totalDistanceKm,0,'no mileage tracked'); T.eq(c.profile.progression.balance,0,'no economy awarded')

-- A separate controller represents a real restart: the target is the saved location.
c,io,adapter=F.controller({io=io})
T.eq(c.state,'RESUME_REQUIRED','restart is locked'); T.eq(c.startupTarget.latitude,2,'saved target loaded')
F.advance(c,5); T.eq(c.state,'RESUME_REQUIRED','base is not accepted instead of saved position')
T.eq(io.writes,1,'failed resume leaves disk untouched'); T.check(P.equal(io.files[A],disk),'save survives failed arrival')
adapter.pose=F.position(2,3); F.advance(c,3.2); T.eq(c.state,'READY','resume location verified')
local baseline=c.baseline
adapter.valid=false; adapter.reason='earth_disconnected'; c:tick(0.1,0.1)
T.eq(c.state,'EARTH_UNAVAILABLE','disconnect pauses active session'); T.eq(c.baseline,nil,'old baseline cleared')
T.check(not c:manualSave(),'save locked during disconnect'); T.eq(io.writes,1,'disconnect cannot write')
adapter.valid=true; adapter.pose=F.position(2.1,3.1); adapter.epoch='new-session:anchor:car'
F.advance(c,3.2); T.eq(c.state,'READY','previously verified session restabilizes in place')
T.check(c.baseline~=baseline,'recovery establishes fresh baseline')
T.eq(c.startupTarget.latitude,2,'recovery never mutates saved target')
T.eq(c:view().target.latitude,2,'HUD saved target remains saved target')
T.eq(c.profile.base.latitude,0,'recovery never mutates base')
adapter.pose=F.position(4,5); c:tick(0.1,0.1); T.check(c:manualSave(),'second location saved')
T.eq(io.files[B].base.latitude,0,'base fixed across generations')
T.eq(io.files[B].resume.latitude,4,'second resume saved')

-- Configuration changes never move an existing profile's original base.
io.files[CONFIG].base=F.position(10,10); c:reload()
T.eq(c.state,'RESUME_REQUIRED','reload relocks arrival')
T.eq(c:view().base.latitude,0,'profile keeps original base despite config change')
T.eq(c.startupTarget.latitude,4,'resume remains independent of new config')

-- Changed data at click time cannot use a previously enabled HUD button.
adapter.pose=F.position(4,5); F.advance(c,3.2); local writes=io.writes
adapter.valid=false; adapter.reason='earth_transition'
T.check(not c:manualSave(),'save rechecks adapter at click'); T.eq(io.writes,writes,'click during transition writes nothing')
adapter.valid=true; F.advance(c,3.2); adapter.epoch='same-position:new-anchor'
T.check(not c:manualSave(),'new epoch at click rejected'); T.eq(io.writes,writes,'epoch change click writes nothing')
F.advance(c,3.2); adapter.pose=F.position(6,7)
T.check(not c:manualSave(),'unobserved large jump at click rejected'); T.eq(io.writes,writes,'jump cannot write')
F.advance(c,3.2); T.eq(c.state,'READY','jump can be reverified after stable observation')
io.writeFails=true
T.check(not c:manualSave(),'write failure visible'); T.eq(c.state,'ERROR','uncertain write locks session')
T.eq(io.files[B].resume.latitude,4,'latest valid generation retained on failure')
T.check(not c:manualSave(),'error does not retry unsafe write')

-- Invalid/missing configuration, corrupt saves, and unknown schemas remain locked.
for _, scenario in ipairs({
  { files={}, state='CONFIG_REQUIRED' },
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

for _, reason in ipairs({'earth_missing','earth_incompatible','position_invalid','vehicle_required','earth_stale'}) do
  local controller,localIO,a=F.controller()
  a.valid=false; a.reason=reason; F.advance(controller,5)
  T.eq(controller.state,'EARTH_UNAVAILABLE','unavailable Earth/vehicle cannot unlock')
  T.eq(controller.profile,nil,'no profile on unavailable data')
  T.eq(localIO.writes,0,'unavailable Earth never writes')
end
local controller,localIO,a=F.controller()
F.advance(controller,2); a.pose=F.position(1,1); controller:tick(0.1,0.1)
T.eq(controller.verifier.elapsed,0,'departure from radius resets timer')
a.pose=F.position(); F.advance(controller,2); controller:tick(0.1,0)
T.eq(controller.verifier.elapsed,0,'pause interrupts verification')
F.advance(controller,2); controller:tick(2,2)
T.eq(controller.verifier.elapsed,0,'frame gap interrupts verification')
F.advance(controller,3.2); a.epoch='other-vehicle'; controller:tick(0.1,0.1)
T.eq(controller.state,'VERIFYING_LOCATION','vehicle/origin change suspends READY')
T.eq(controller.baseline,nil,'identity change drops baseline')
F.advance(controller,3.2); controller:endMission(); a.valid=false; a.reason='earth_level_required'; controller:tick(0.1,0.1)
T.check(not controller.sessionVerified,'mission end discards session authorization')
T.eq(controller.baseline,nil,'mission end clears baseline')
T.eq(localIO.writes,0,'mission end has no implicit save')

local unsaved,unsavedIO=F.controller(); F.advance(unsaved,3.2)
unsavedIO.files[CONFIG].base=F.position(10,10); unsaved:reload()
T.eq(unsaved.startupTarget.latitude,0,'unsaved created profile also keeps original base on config reload')
unsaved:reload(); T.eq(unsaved:view().base.latitude,0,'repeated reloads keep pending original base')
F.advance(unsaved,3.2); T.eq(unsaved.profile.base.latitude,0,'reverification does not rewrite original unsaved base')

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
