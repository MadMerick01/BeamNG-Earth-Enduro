-- The rally's stages. To add one, add an entry to the list: an id that never changes (saves
-- store it; ids it had before go in oldIds so older saves still load), the name the HUD shows, the start and finish coordinates, and the towns nearest the
-- start and finish, which the HUD shows so the player can find them on the map, and a short
-- briefing shown when the stage starts, the money the player starts it with, and the time limit
-- in seconds (the stage's Google Maps driving time; set targetIsEstimate = true to mark a guess). The finish counts once the vehicle is within
-- finishRadiusMetres of it. The first stage is where a new player starts. A stage can set its own
-- sponsorBonus (dollars) and sponsorEveryKm; otherwise the defaults below apply. Stages run in list
-- order: finishing one offers the next, which the player starts with the car and money they finished on.
local location = require('beamngEarthEnduro/location')
local M = {}

-- Sponsor bonus: paid once for every SPONSOR_EVERY_KM of counted driving on a stage.
M.SPONSOR_BONUS = 2000
M.SPONSOR_EVERY_KM = 10

M.list = {
  {
    id = 'stage_1', oldIds = { 'zoji_la' }, name = 'Stage 1: Zoji La Pass',
    startTown = 'Sind River, Kashmir', finishTown = 'Dras, Ladakh',
    briefing = 'Drive from the Sind River, Kashmir, up the Sind valley past Sonamarg and over the Zoji La Pass to Dras, Ladakh. '
      .. 'Reach the finish to complete the stage.',
    start = { latitude = 34.271288, longitude = 75.163671 },
    finish = { latitude = 34.43223, longitude = 75.80991 },
    finishRadiusMetres = 100,
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
    -- Only used if Stage 2 is ever started without coming from Stage 1.
    startingMoney = 3000,
    -- Time limit: 30 min.
    targetSeconds = 30 * 60,
  },
}

local function copy(stage, index)
  return {
    number = index, count = #M.list,
    id = stage.id, name = stage.name, startTown = stage.startTown, finishTown = stage.finishTown,
    briefing = stage.briefing, start = location.copy(stage.start), finish = location.copy(stage.finish),
    finishRadiusMetres = stage.finishRadiusMetres, startingMoney = stage.startingMoney or 0,
    targetSeconds = stage.targetSeconds, targetIsEstimate = stage.targetIsEstimate == true,
    sponsorBonus = stage.sponsorBonus or M.SPONSOR_BONUS, sponsorEveryKm = stage.sponsorEveryKm or M.SPONSOR_EVERY_KM,
  }
end

function M.first() return copy(M.list[1], 1) end

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
