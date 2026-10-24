-- The rally's stages. To add one, add an entry to the list: an id that never changes (saves
-- store it; ids it had before go in oldIds so older saves still load), the name the HUD shows, the start and finish coordinates, and the towns nearest the
-- start and finish, which the HUD shows so the player can find them on the map, and a short
-- briefing shown when the stage starts, the money the player starts it with, and the time limit
-- in seconds (the stage's Google Maps driving time; set targetIsEstimate = true to mark a guess). The finish counts once the vehicle is within
-- finishRadiusMetres of it. Each stage also has a difficulty from 1 (gentle) to 5 (deadly), which
-- sets its pay (see PAY_BY_DIFFICULTY), and the road distance in lengthKm (approximate; leave it out
-- and the HUD shows the straight-line distance). The first stage is where a new player starts. A
-- stage can set its own earningsPerKm, sponsorBonus (dollars) and sponsorEveryKm; otherwise its
-- difficulty and the defaults below set them. Stages are optional: the player can start any stage
-- from the Route tab at any time, taking the car and money they have. List order is only the order
-- the HUD shows them in, and the stage a finish offers as next.
local location = require('beamngEarthEnduro/location')
local M = {}

-- Driving pay per km, and the sponsor bonus paid once for every SPONSOR_EVERY_KM of counted
-- driving on a stage, before the stage's difficulty scales them.
M.EARNINGS_PER_KM = 100
M.SPONSOR_BONUS = 2000
M.SPONSOR_EVERY_KM = 10
-- How much a stage of each difficulty multiplies its pay by, so the rough roads are worth the risk.
M.PAY_BY_DIFFICULTY = { 1, 1, 1, 1.5, 2 }

M.list = {
  {
    id = 'stage_1', oldIds = { 'zoji_la' }, name = 'Stage 1: Zoji La Pass',
    startTown = 'Sind River, Kashmir', finishTown = 'Dras, Ladakh',
    briefing = 'Drive from the Sind River, Kashmir, up the Sind valley past Sonamarg and over the Zoji La Pass to Dras, Ladakh. '
      .. 'Reach the finish to complete the stage.',
    start = { latitude = 34.271288, longitude = 75.163671 },
    finish = { latitude = 34.43223, longitude = 75.80991 },
    finishRadiusMetres = 100,
    difficulty = 3, lengthKm = 95,
    startingMoney = 3000,
    -- Time limit: 2 h 0 min.
    targetSeconds = 2 * 3600,
  },
  {
    id = 'stage_2', name = 'Stage 2: Colo River',
    startTown = 'Windsor, NSW', finishTown = 'Colo Heights, NSW',
    briefing = 'Drive from the Windsor Bridge on the Hawkesbury River, Windsor, north through the Colo River country '
      .. 'to the bush tracks at Colo Heights. Reach the finish to complete the stage.',
    start = { latitude = -33.601664, longitude = 150.822650 },
    finish = { latitude = -33.366081, longitude = 150.790919 },
    finishRadiusMetres = 100,
    difficulty = 2, lengthKm = 40,
    -- Used when a player with no save yet starts here.
    startingMoney = 3000,
    -- Time limit: 30 min.
    targetSeconds = 30 * 60,
  },
}

local function copy(stage, index)
  local difficulty = stage.difficulty or 1
  local pay = M.PAY_BY_DIFFICULTY[difficulty] or 1
  return {
    number = index, count = #M.list,
    id = stage.id, name = stage.name, startTown = stage.startTown, finishTown = stage.finishTown,
    briefing = stage.briefing, start = location.copy(stage.start), finish = location.copy(stage.finish),
    finishRadiusMetres = stage.finishRadiusMetres, startingMoney = stage.startingMoney or 0,
    targetSeconds = stage.targetSeconds, targetIsEstimate = stage.targetIsEstimate == true,
    difficulty = difficulty,
    lengthKm = stage.lengthKm or math.floor((location.distance(stage.start, stage.finish) or 0) / 1000 + 0.5),
    lengthIsStraight = stage.lengthKm == nil,
    earningsPerKm = stage.earningsPerKm or math.floor(M.EARNINGS_PER_KM * pay + 0.5),
    sponsorBonus = stage.sponsorBonus or math.floor(M.SPONSOR_BONUS * pay + 0.5),
    sponsorEveryKm = stage.sponsorEveryKm or M.SPONSOR_EVERY_KM,
  }
end

function M.first() return copy(M.list[1], 1) end

-- Every stage, in list order.
function M.all()
  local out = {}
  for i, stage in ipairs(M.list) do out[i] = copy(stage, i) end
  return out
end

-- Returns the stage with this id, or nil when this version has no such stage.
function M.get(id)
  for i, stage in ipairs(M.list) do
    if stage.id == id then return copy(stage, i) end
    for _, old in ipairs(stage.oldIds or {}) do
      if old == id then return copy(stage, i) end
    end
  end
  return nil
end

-- Returns the stage after the one with this id, or nil when it is the last.
function M.after(id)
  local stage = M.get(id)
  local nextStage = stage and M.list[stage.number + 1]
  return nextStage and copy(nextStage, stage.number + 1) or nil
end

return M
