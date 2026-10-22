local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local Adapter = require('beamngEarthEnduro/earthAdapter')

local st={ anchor={enuToGeodetic=function(_,x,y,z) return y/111195.0802,x/111195.0802,z end} }
local vehiclePresent=true
local pos={x=0,y=0,z=1}
local vehicle={ getID=function() return 1 end, getPosition=function() return pos end,
  getPath=function() return 'vehicles/pickup/' end }
local core={_state=function() return st end, teleport=function() error('Enduro must never teleport') end}
local env={ core=function() return core end, vehicle=function() return vehiclePresent and vehicle or nil end }
local a=Adapter.new(env)
local function sample() return a:sample() end

local s=sample()
T.check(s.valid,'Earth anchor plus vehicle yields valid sample')
T.eq(s.vehicle.model,'pickup','model path normalized'); T.eq(s.vehicle.id,1,'vehicle id reported')
pos.y=10; s=sample(); T.near(s.latitude,10/111195.0802,1e-12,'live vehicle position converted through anchor'); pos.y=0
local oldCore=core; core=nil
T.eq(sample().reason,'earth_missing','missing mod detected without enabling it'); core=oldCore
T.check(sample().valid,'mod restored')
local oldAnchor=st.anchor; st.anchor=nil
T.eq(sample().reason,'earth_starting','no anchor yet waits'); st.anchor=oldAnchor
vehiclePresent=false; T.eq(sample().reason,'vehicle_required','no active vehicle blocks'); vehiclePresent=true
pos.z=0/0; st.anchor={enuToGeodetic=function() return 0/0,0 end}
T.eq(sample().reason,'position_invalid','NaN coordinate blocks'); st.anchor=oldAnchor; pos.z=1
st.anchor={enuToGeodetic=function() error('mock runtime fault') end}
T.eq(sample().reason,'earth_interface_error','engine exception isolated'); st.anchor=oldAnchor
local oldPath=vehicle.getPath; vehicle.getPath=nil
T.check(sample().valid,'optional model API failure is nonfatal'); T.eq(sample().vehicle.model,nil,'unavailable model omitted')
vehicle.getPath=oldPath
-- Earth loading/transition/pause state no longer matters: only the vehicle position does.
st.pending, st.rebasing, st.paused, st.inOurLevel = true, true, true, false
T.check(sample().valid,'Earth transition flags do not block the position check')
T.done('Earth adapter (mocked engine)')
