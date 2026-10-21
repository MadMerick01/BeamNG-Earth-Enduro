local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local L = require('beamngEarthEnduro/location')
local F = require('fixtures')
local C = require('beamngEarthEnduro/config')
for _, p in ipairs({ F.position(), F.position(90,180), F.position(-90,-180), F.position(-33.86,151.21) }) do
  T.check(L.valid(p), 'valid coordinate')
end
for _, p in ipairs({ {}, { latitude = '0', longitude = 0 }, F.position(91,0), F.position(0,181),
    F.position(0/0,0), F.position(0,math.huge), F.position(-math.huge,0), F.position(0,false) }) do
  T.check(not L.valid(p), 'invalid coordinate rejected')
end
T.eq(L.distance(F.position(),F.position()),0,'zero distance')
T.near(L.distance(F.position(),F.position(1,0)),111195.0802,0.01,'one degree north')
T.near(L.distance(F.position(0,179.9999),F.position(0,-179.9999)),22.239,0.01,'antimeridian')
T.near(L.distance(F.position(90,0),F.position(90,180)),0,1e-6,'pole longitudes coincide')
T.near(L.distance(F.position(),F.position(0,180)),20015114.44,0.1,'antipodal numeric stability')
T.eq(L.distance({},F.position()),nil,'invalid distance not zero')
local metresToDeg = 180 / (math.pi * 6371008.8)
local v = L.verifier(50,3)
T.check(not v:step(F.position(49.99*metresToDeg),F.position(),0.1,'a'),'inside begins with zero elapsed')
for _=1,29 do v:step(F.position(49.99*metresToDeg),F.position(),0.1,'a') end
T.near(v.elapsed,2.9,1e-8,'not ready before interval')
T.check(v:step(F.position(49.99*metresToDeg),F.position(),0.1,'a'),'ready after continuous three seconds')
T.check(not v:step(F.position(50.01*metresToDeg),F.position(),0.1,'a'),'outside boundary resets')
T.eq(v.elapsed,0,'outside clears elapsed')
v:step(F.position(),F.position(),0.1,'a'); v:step(F.position(),F.position(),0.5,'a')
T.eq(v.elapsed,0.5,'elapsed accumulates')
v:step({},F.position(),0.1,'a'); T.eq(v.elapsed,0,'invalid sample clears elapsed')
v:step(F.position(),F.position(),0.1,'a'); v:step(F.position(),F.position(),0.5,'a')
v:step(F.position(),F.position(),0.1,'b'); T.eq(v.elapsed,0,'origin epoch restarts interval')
v:step(F.position(),F.position(),2,'b'); T.eq(v.elapsed,0,'long sample gap resets')
v:step(F.position(),F.position(),0,'b'); T.eq(v.elapsed,0,'paused time cannot verify')
v:step(F.position(),F.position(),0/0,'b'); T.eq(v.elapsed,0,'NaN time rejected')
v:step(F.position(),F.position(),0.1,nil); T.eq(v.elapsed,0,'missing epoch rejected')
v:step(F.position(),F.position(),0.1,'a'); v:step(F.position(),F.position(),0.5,'a')
v:step(F.position(),F.position(0.00001),0.1,'a'); T.eq(v.elapsed,0,'changed target restarts interval')
T.check(C.validate(F.config()) ~= nil,'valid config')
local cfg = F.config(); cfg.base.latitude=nil; T.eq(C.validate(cfg),nil,'unset base rejected')
for _, patch in ipairs({ { 'resumeRadiusMetres',0 }, {'resumeRadiusMetres',math.huge}, {'stabilitySeconds',0},
    {'stabilitySeconds','3'}, {'resumeRadiusMetres',1001}, {'stabilitySeconds',61} }) do
  cfg=F.config(); cfg[patch[1]]=patch[2]; T.eq(C.validate(cfg),nil,'unsafe config value rejected')
end
cfg=F.config(); cfg.resumeRadiusMetres=nil; cfg.stabilitySeconds=nil
local clean=C.validate(cfg); T.eq(clean.resumeRadiusMetres,50,'default radius'); T.eq(clean.stabilitySeconds,3,'default interval')
T.done('location/config')
