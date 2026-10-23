local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local P = require('beamngEarthEnduro/persistence')
local Core = require('beamngEarthEnduro/core')
local stage = require('beamngEarthEnduro/stages').first()
local CONFIG = '/settings/beamngEarthEnduro/config.json'
local A = P.DIRECTORY .. 'save-a.json'
local TARGET = stage.targetSeconds
local function setup(options)
  options = options or {}
  local config = F.config(); config.base = F.copy(stage.start)
  options.io = options.io or F.io({ [CONFIG] = config })
  options.adapter = options.adapter or F.adapter(F.position(1, 1))
  return F.controller(options)
end

T.check(type(TARGET) == 'number' and TARGET > 0, 'the stage has a time limit')

-- The clock waits for the player to reach the start, then runs only while the game is not paused.
local paused = false
local c, io, adapter, _, _, g = setup({ paused = function() return paused end })
c:tick(0.1)
local timer = c:view().timer
T.eq(timer.remainingSeconds, TARGET, 'full time limit shown before the start')
T.check(not timer.started and not timer.running, 'clock not started before arriving')
T.eq(timer.aheadSeconds, nil, 'no pace before arriving')
F.advance(c, 5); T.eq(c:view().timer.remainingSeconds, TARGET, 'driving to the start costs no time')
adapter.pose = F.copy(stage.start); c:tick(0.1)
T.check(c:view().timer.running, 'clock runs once arrived')
F.advance(c, 10)
T.near(c.profile.progression.drivingSeconds, 10, 0.15, 'driving time counted')
T.eq(c:view().timer.remainingSeconds, TARGET - 10, 'countdown shows whole seconds left')
T.check(math.abs(c:view().timer.aheadSeconds + 10) <= 1, 'standing at the start puts the player behind by the time used')
paused = true; F.advance(c, 10)
T.near(c.profile.progression.drivingSeconds, 10, 0.15, 'paused time is not counted')
T.check(not c:view().timer.running, 'HUD told the clock is stopped'); T.check(c:view().timer.started, 'but it has started')
paused = false
local before = c.profile.progression.drivingSeconds
c:tick(5); T.near(c.profile.progression.drivingSeconds - before, 0.5, 1e-9, 'a long frame adds at most half a second')
adapter.valid = false; F.advance(c, 3)
T.near(c.profile.progression.drivingSeconds - before, 0.5, 1e-9, 'no clock without a vehicle position')
adapter.valid = true

-- Pace: halfway to the finish in a straight line is expected at half the time limit.
local midway = F.position((stage.start.latitude + stage.finish.latitude) / 2, (stage.start.longitude + stage.finish.longitude) / 2)
adapter.pose = midway; c:tick(0.1)
local elapsed = c.profile.progression.drivingSeconds
T.check(math.abs(c:view().timer.aheadSeconds - (TARGET / 2 - elapsed)) <= 30, 'halfway is ahead by half the limit less the time used')
T.check(c:view().timer.aheadSeconds > 0, 'far ahead of pace after a quick trip')

-- A repair costs five minutes, shown as a penalty for a few seconds.
c:addTestMoney(); g.damage = 1000; c:requestRepairQuote()
T.check(c:repairVehicle(), 'repair succeeds')
T.eq(c.profile.progression.penaltySeconds, Core.PENALTY_SECONDS, 'repair adds the penalty')
T.eq(Core.PENALTY_SECONDS, 300, 'the penalty is five minutes')
timer = c:view().timer
T.eq(timer.penaltySeconds, 300, 'HUD shows the penalty total'); T.eq(timer.penalty.reason, 'repair', 'HUD flashes the repair penalty')
T.eq(timer.remainingSeconds, math.ceil(TARGET - c.profile.progression.drivingSeconds - 300), 'penalty comes off the time left')
F.advance(c, 9); T.eq(c:view().timer.penalty, nil, 'penalty flash goes after a few seconds')

-- Parts cost no time, unless the bill includes a repair.
g:fit('turbo', 'pickup_turbo'); c:vehicleSpawned(); c:tick(0.1)
T.check(c:buyParts(), 'parts bought'); T.eq(c.profile.progression.penaltySeconds, 300, 'parts alone add no penalty')
g.damage = 1000; c:tick(0.1); g:fit('intake', 'pickup_intake_race'); c:vehicleSpawned(); c:tick(0.1)
T.check(c:view().partsChange.repair > 0, 'parts bill includes the repair')
T.check(c:buyParts(), 'parts and repair bought'); T.eq(c.profile.progression.penaltySeconds, 600, 'a bill with a repair adds the penalty')
-- A new car costs five minutes.
for _ = 1, 4 do c:addTestMoney() end
g.model, g.fitted = 'sport', { engine = 'sport_v12' }; c:vehicleSpawned(); c:tick(0.1)
T.eq(c.profile.progression.penaltySeconds, 600, 'picking a car costs nothing until it is bought')
T.check(c:buyCar(), 'car bought'); T.eq(c.profile.progression.penaltySeconds, 900, 'a new car adds the penalty')
T.eq(c:view().timer.penalty.reason, 'car', 'HUD flashes the car penalty')

-- Save keeps the clock; a reload goes back to the saved clock.
T.check(c:manualSave(), 'saved'); local saved = io.files[A].progression
T.near(saved.drivingSeconds, c.profile.progression.drivingSeconds, 1e-9, 'driving time saved')
T.eq(saved.penaltySeconds, 900, 'penalties saved')
F.advance(c, 5); c:reload()
T.near(c.profile.progression.drivingSeconds, saved.drivingSeconds, 1e-9, 'reload restores the saved clock')
T.eq(c.profile.progression.penaltySeconds, 900, 'reload restores the saved penalties')

-- Over the limit the clock carries on into overtime; it is not game over.
c.profile.progression.drivingSeconds = TARGET; c.profile.progression.penaltySeconds = 5
adapter.pose = midway; c:tick(0.1); c:tick(0.1)
timer = c:view().timer
T.check(timer.remainingSeconds < 0, 'overtime shown as negative time left'); T.eq(timer.remainingSeconds, -5, 'overtime counts up')
T.check(not c.gameOver and timer.running, 'overtime is not game over')

-- Reaching the finish stops the clock.
adapter.pose = F.copy(stage.finish); c:tick(0.1)
T.check(c.stageFinished, 'stage finished'); local final = c.profile.progression.drivingSeconds
F.advance(c, 5); T.eq(c.profile.progression.drivingSeconds, final, 'clock stops at the finish')
T.check(not c:view().timer.running, 'HUD told the clock is stopped')
T.eq(c:view().timer.aheadSeconds, math.floor(TARGET - final - 5 + 0.5), 'final pace is the time left at the finish')

-- Restart stage resets the clock.
T.check(not c:restartStage(), 'restart asks to confirm'); T.check(c:view().saveFeedback:find('clock'), 'player told the clock resets')
T.check(c:restartStage(), 'restart confirmed')
T.eq(c.profile.progression.drivingSeconds, 0, 'restart resets driving time'); T.eq(c.profile.progression.penaltySeconds, 0, 'restart resets penalties')
T.eq(c:view().timer.remainingSeconds, TARGET, 'full time limit after restart')

-- Saves from before the clock load with no time used.
local old = F.save(1, 1, 1)
local oldIO = F.io({ [CONFIG] = F.config(), [A] = old })
local r = F.controller({ io = oldIO })
T.eq(r.profile.progression.drivingSeconds, 0, 'old save starts with no driving time')
T.eq(r.profile.progression.penaltySeconds, 0, 'old save starts with no penalties')
old.progression.drivingSeconds = -1
T.eq(P.validate(old), nil, 'negative driving time rejected')
old.progression.drivingSeconds = 0 / 0
T.eq(P.validate(old), nil, 'NaN driving time rejected')

T.done('stage clock')
