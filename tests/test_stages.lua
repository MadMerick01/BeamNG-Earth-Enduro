local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local P = require('beamngEarthEnduro/persistence')
local S = require('beamngEarthEnduro/stages')
local location = require('beamngEarthEnduro/location')
local CONFIG = '/settings/beamngEarthEnduro/config.json'
local A, B = P.DIRECTORY .. 'save-a.json', P.DIRECTORY .. 'save-b.json'

-- Every stage is one complete data entry: a unique id, a name, start and finish, a time limit and a
-- difficulty from 1 to 5, which sets its pay.
do
  local ids = {}
  for i, stage in ipairs(S.all()) do
    local label = 'stage ' .. i
    T.check(type(stage.id) == 'string' and stage.id:match('^[a-z0-9_]+$') ~= nil, label .. ' has a plain id')
    T.check(not ids[stage.id], label .. ' id is unique'); ids[stage.id] = true
    for _, old in ipairs(S.list[i].oldIds or {}) do T.check(not ids[old], label .. ' old id is unique'); ids[old] = true end
    T.check(type(stage.name) == 'string' and stage.name ~= '', label .. ' has a name')
    T.check(type(stage.briefing) == 'string' and stage.briefing ~= '', label .. ' has a briefing')
    T.check(location.valid(stage.start) and location.valid(stage.finish), label .. ' has valid coordinates')
    T.check(type(stage.targetSeconds) == 'number' and stage.targetSeconds > 0, label .. ' has a time limit')
    T.check(stage.finishRadiusMetres > 0, label .. ' has a finish radius')
    T.check(stage.difficulty >= 1 and stage.difficulty <= 5 and stage.difficulty == math.floor(stage.difficulty), label .. ' difficulty is 1 to 5')
    T.check(S.list[i].difficulty ~= nil, label .. ' sets its difficulty')
    T.check(stage.lengthKm > 0, label .. ' has a length')
  end
  T.eq(S.first().earningsPerKm, 100, 'Zoji La pays the base rate'); T.eq(S.first().sponsorBonus, 2000, 'and the base sponsor bonus')
  T.eq(S.get('stage_2').earningsPerKm, 100, 'Colo River pays the base rate')
  -- Harder stages pay more; a stage can still set its own pay.
  local saved = S.list[2]
  S.list[2] = { id = 'deadly', name = 'Deadly', difficulty = 5, start = F.position(1, 1), finish = F.position(1, 1.1),
    finishRadiusMetres = 100, targetSeconds = 600 }
  T.eq(S.get('deadly').earningsPerKm, 200, 'difficulty 5 doubles driving pay'); T.eq(S.get('deadly').sponsorBonus, 4000, 'and the sponsor bonus')
  T.check(S.get('deadly').lengthIsStraight and S.get('deadly').lengthKm == 11, 'no lengthKm falls back to the straight line')
  S.list[2].difficulty, S.list[2].earningsPerKm = 4, 175
  T.eq(S.get('deadly').earningsPerKm, 175, 'a stage can set its own pay'); T.eq(S.get('deadly').sponsorBonus, 3000, 'difficulty 4 pays 1.5 times the bonus')
  S.list[2] = saved
end

-- The Route tab lists every stage, and any of them can be started at any time.
do
  local m,_,ma,_,_,g=F.controller()
  m:tick(0.1); m:vehicleSpawned(); m:tick(0.1)
  local list = m:view().stageList
  T.eq(#list, #S.list, 'every stage listed'); T.check(list[1].current and not list[2].current, 'Stage 1 is the current one')
  T.eq(list[1].difficulty, 3, 'difficulty shown'); T.eq(list[1].lengthKm, 95, 'length shown'); T.eq(list[2].targetSeconds, 1800, 'time limit shown')
  T.check(not list[1].completed and not list[2].completed, 'nothing completed yet'); T.check(m:view().stageSelectAllowed, 'stages can be picked')
  T.check(not m:startStage('stage_1'), 'the current stage is not started from the list')
  T.check(m:view().saveFeedback:find('Restart stage'), 'player pointed to Restart stage')
  T.check(not m:startStage('nowhere'), 'an unknown stage is refused')
  -- Drive a little on Stage 1, then jump to Stage 2 without finishing.
  for i = 1, 20 do ma.pose = F.position(0, i * 0.0005); m:tick(1) end
  m:addTestMoney(); g.damage = 300
  local balance = m:view().balance
  T.check(m:view().totalDistanceKm > 1, 'some mileage on Stage 1')
  T.check(not m:startStage('stage_2'), 'leaving an unfinished stage asks to confirm')
  T.eq(m:view().stageArmed, 'stage_2', 'Stage 2 button shows Confirm'); T.check(m:view().saveFeedback:find('lost'), 'player told the progress is lost')
  T.eq(m.stage.id, 'stage_1', 'still on Stage 1 until confirmed')
  T.check(m:startStage('stage_2'), 'Stage 2 started without finishing Stage 1')
  T.eq(m.stage.id, 'stage_2', 'now on Stage 2'); T.eq(m.mode, 'start', 'sent to the Stage 2 start')
  T.eq(m:view().balance, balance, 'money carried'); T.eq(m:view().totalDistanceKm, 0, 'mileage starts again')
  T.check(m.carriedCar, 'car carried'); T.eq(m:view().stageArmed, nil, 'confirm cleared')
  T.eq(m:view().resume.latitude, S.get('stage_2').start.latitude, 'Stage 2 start shown')
  local saved = m.profile
  T.eq(saved.stage, 'stage_2', 'Stage 2 saved'); T.eq(#saved.completedStages, 0, 'Stage 1 not marked completed')
  T.eq(saved.entry.balance, balance, 'Stage 2 entry money saved'); T.eq(saved.entry.vehicle.damage, 300, 'damage comes with the car')
  -- Before reaching Stage 2's start, go back to Stage 1: the saved car still comes along.
  T.check(not m:startStage('stage_1') and m:startStage('stage_1'), 'back to Stage 1 before reaching Stage 2')
  T.eq(m.stage.id, 'stage_1', 'on Stage 1 again'); T.check(m.carriedCar, 'the saved car comes back too')
  T.eq(m:view().balance, balance, 'money still carried')
  local spawns = #g.spawns
  ma.pose = F.position(0, 0); m:tick(0.1)
  T.eq(#g.spawns, spawns + 1, 'car given at the Stage 1 start'); T.eq(g.spawns[#g.spawns].model, 'pickup', 'the player\'s own car')
  m:vehicleSpawned(); m:tick(0.1)
  -- Finish Stage 1: it is ticked, and leaving it needs no confirm.
  local first = S.get('stage_1')
  ma.pose = F.position(first.finish.latitude, first.finish.longitude); m:tick(0.1)
  T.check(m:view().stageFinished, 'Stage 1 finished'); T.check(m:view().stageList[1].completed, 'Stage 1 ticked')
  T.check(m:startStage('stage_2'), 'a finished stage is left with one press')
  T.check(m:view().stageList[1].completed, 'Stage 1 stays ticked on Stage 2'); T.check(not m:view().stageList[2].completed, 'Stage 2 not ticked')
  -- A save made under the old id still counts as Stage 1, once.
  m.profile.completedStages = { 'zoji_la', 'stage_1' }
  T.eq(#m:completedStageIds(), 1, 'old and new ids count once'); T.check(m:view().stageList[1].completed, 'old id still ticks Stage 1')
  -- Not on a CarKov run, and not with a bill open.
  m.carkov = { extraction = F.position() }
  T.check(not m:view().stageSelectAllowed, 'no stage picking on CarKov'); T.check(not m:startStage('stage_1'), 'refused on CarKov')
  m.carkov = nil; m.pendingParts = { damage = 0 }
  T.check(not m:view().stageSelectAllowed, 'no stage picking with a bill open'); T.check(not m:startStage('stage_1'), 'refused with a bill open')
  m.pendingParts = nil
end

-- A new player can pick any stage straight away: no save yet, so it starts fresh with the stage's
-- starting money and the starter car, with no confirm.
do
  local m,mio,ma=F.controller()
  ma.pose = F.position(1, 1); m:tick(0.1)
  T.check(not m.arrived, 'not at the Stage 1 start yet'); T.eq(mio.writes, 0, 'nothing saved yet')
  T.check(m:startStage('stage_2'), 'Stage 2 started before ever reaching Stage 1')
  T.eq(m.stage.id, 'stage_2', 'on Stage 2'); T.eq(m:view().balance, S.get('stage_2').startingMoney, 'Stage 2 starting money')
  T.check(not m.carriedCar, 'starter car waiting'); T.eq(m:view().resume.longitude, S.get('stage_2').start.longitude, 'Stage 2 start shown')
  T.check(m:restartStage() == false and m:restartStage(), 'Stage 2 can be restarted')
  T.eq(m:view().balance, S.get('stage_2').startingMoney, 'restart keeps the Stage 2 starting money')
end

-- Saves from before the stage list load as they were.
do
  local old = F.save(1); old.stage = 'zoji_la'; old.completedStages = { 'zoji_la' }
  local r = F.controller({ io = F.io({ [CONFIG] = F.config(), [A] = old }) })
  T.check(r.state ~= 'ERROR', 'old save loads'); T.eq(r.stage.id, 'stage_1', 'old stage id maps to Stage 1')
  T.check(r:view().stageList[1].current and r:view().stageList[1].completed, 'old completed id ticks Stage 1')
end

T.done('stage list')
