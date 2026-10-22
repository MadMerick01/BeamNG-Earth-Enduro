local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local Adapter = require('beamngEarthEnduro/earthAdapter')
local Compatibility = require('beamngEarthEnduro/compatibility')
T.eq(Compatibility.checksum('Wikipedia'),300286872,'Adler-32 independently known vector')
T.eq(Compatibility.checksum(''),1,'empty source checksum')
local ok,why=Compatibility.check(function() return nil end)
T.check(not ok and why:match('source_unreadable'),'unreadable VFS source blocks compatibility')
ok,why=Compatibility.check(function() return 'unrelated source' end)
T.check(not ok and why:match('unsupported_source'),'wrong source blocks compatibility')

local st={ inOurLevel=true, active=true, sessionId='s1', anchorSession='s1', anchorId=1, clock=10,
  block={cx=0,cy=0}, player={lat=0,lon=0}, guard={mode='off'}, loadingUntil=0 }
st.anchor={enuToGeodetic=function(_,x,y,z) return y/111195.0802,x/111195.0802,z end}
local connected,healthy,ready,settled,hold,vehiclePresent=true,true,true,true,{active=false},true
local hello={serverVersion='0.4.0',protocol=4,sessionId='s1'}
local pos={x=0,y=0,z=1}
local vehicle={ getID=function() return 1 end, getPosition=function() return pos end,
  getPath=function() return 'vehicles/pickup/' end }
local core={MOD_VERSION='0.4.0',_state=function() return st end,serverHello=function() return hello end,
  serverHealthy=function() return healthy end,dropHoldState=function() return hold end,
  teleport=function() error('Enduro must never teleport') end}
local modules={
  net={isConnected=function() return connected end},
  places={here=function() return st.player.lat,st.player.lon end},
  lattice={groundBox=function() return -1024,-1024,1022,1022 end},
  roads={enabled=true,readyAround=function() return ready end,settledFor=function() return settled end},
}
local checks=0
local env={ core=function() return core end,module=function(name) return modules[name] end,
  readSource=function() error('source checker injected in stub suite') end,
  vehicle=function() return vehiclePresent and vehicle or nil end }
local a=Adapter.new(env,function() checks=checks+1; return true,'mocked pinned source' end)
local function sample(running)
  st.clock=st.clock+0.1
  return a:sample(0.1,running~=false)
end
local s=sample()
T.check(s.valid,'compatible source/capabilities yield valid sample')
T.eq(s.vehicle.model,'pickup','model path normalized'); T.eq(s.epoch,'s1:1:1','identity includes server/anchor/vehicle')
T.eq(s.version,'1.5.4-beta','server version used instead of stale MOD_VERSION')
sample(); T.eq(checks,1,'source identity checked once per core/load')
pos.y=10; s=sample(); T.near(s.latitude,10/111195.0802,1e-12,'live position used rather than pre-physics pose cache')
pos.y=30; T.eq(sample().reason,'position_invalid','stale mixed coordinate samples rejected'); pos.y=0
local oldCore=core; core=nil
T.eq(sample().reason,'earth_missing','missing mod detected without enabling it'); core=oldCore
T.check(sample().valid,'mod restored through capability gate'); T.eq(checks,2,'reappearing mod rechecks source')
connected=false; T.eq(sample().reason,'earth_disconnected','disconnect detected'); connected=true
hello.serverVersion='1.6.0'; T.eq(sample().reason,'earth_incompatible','unknown server rejected'); hello.serverVersion='0.4.0'
hello.protocol=5; T.eq(sample().reason,'earth_incompatible','unknown protocol rejected'); hello.protocol=4
st.inOurLevel=false; T.eq(sample().reason,'earth_level_required','other maps do not activate Enduro'); st.inOurLevel=true
st.active=false; T.eq(sample().reason,'earth_starting','inactive Earth waits'); st.active=true
st.anchorSession='old'; T.eq(sample().reason,'earth_transition','old server anchor rejected'); st.anchorSession='s1'
for _,field in ipairs({'pending','randomStart','resync','rebasing','lagProbe','placeFrames','floorZ'}) do
  st[field]=field=='floorZ' and 0 or {}
  T.eq(sample().reason,'earth_transition',field .. ' blocks verification')
  st[field]=nil
end
hold.active=true; T.eq(sample().reason,'earth_transition','drop hold blocks'); hold.active=false
st.guard.mode='holding'; T.eq(sample().reason,'earth_transition','edge guard blocks'); st.guard.mode='off'
st.guard.mode='clear'; T.check(sample().valid,'normal clear guard state permits verification'); st.guard.mode='off'
st.loadingUntil=st.clock+10; T.eq(sample().reason,'earth_transition','known teleport loading window blocks'); st.loadingUntil=0
healthy=false; T.eq(sample().reason,'earth_loading','unhealthy world blocks'); healthy=true
T.eq(sample(false).reason,'simulation_paused','paused simulation cannot verify')
st.paused=true; T.eq(sample().reason,'simulation_paused','Earth pause state also checked'); st.paused=false
vehiclePresent=false; T.eq(sample().reason,'vehicle_required','no active vehicle blocks'); vehiclePresent=true
st.player.lat=0/0; T.eq(sample().reason,'position_invalid','NaN Earth coordinate blocks'); st.player.lat=0
pos.z=math.huge; T.eq(sample().reason,'position_invalid','infinite local position blocks'); pos.z=1
pos.x=1000; T.eq(sample().reason,'position_invalid','live/cache disagreement blocked'); pos.x=0
local oldBounds=modules.lattice.groundBox
modules.lattice.groundBox=function() return -10,-10,10,10 end
T.eq(sample().reason,'earth_loading','insufficient current block margin blocks'); modules.lattice.groundBox=oldBounds
ready=false; T.eq(sample().reason,'earth_loading','unready nearby road tiles block'); ready=true
settled=false; T.eq(sample().reason,'earth_loading','unsettled old collision blocks'); settled=true
for _=1,6 do s=a:sample(0.1,true) end
T.eq(s.reason,'earth_stale','non-advancing Earth clock fails freshness')
T.check(sample().valid,'fresh core clock recovers')
local oldHold=hold; hold={}
T.eq(sample().reason,'earth_incompatible','unknown hold layout rejected'); hold=oldHold
local oldHere=modules.places.here; modules.places.here=nil
T.eq(sample().reason,'earth_incompatible','missing getter fails safely'); modules.places.here=oldHere
modules.places.here=function() error('mock runtime fault') end
T.eq(sample().reason,'earth_interface_error','engine exception isolated'); modules.places.here=oldHere
local oldPath=vehicle.getPath; vehicle.getPath=nil
T.check(sample().valid,'optional model API failure is nonfatal'); T.eq(sample().vehicle.model,nil,'unavailable model omitted')
vehicle.getPath=oldPath
T.check(a:filesChanged({{filename='/lua/ge/extensions/beamngEarth/core.lua'}}),'upstream source edit invalidates cached identity')
T.check(sample().valid,'source rechecked after file change'); T.eq(checks,3,'source check repeats after invalidation')
T.check(not a:filesChanged({{filename='/settings/beamngEarthEnduro/save-a.json'}}),'own saves do not invalidate Earth')
local bad=Adapter.new(env,function() return false,'unsupported_source:core' end)
T.eq(bad:sample(0.1,true).reason,'earth_incompatible','unsupported source blocks even if version matches')
T.check(not bad:sample(0.1,true).valid,'no fallback enabling unsupported internal access')
T.done('Earth adapter (mocked engine)')
