-- The rally's stages. To add one, add an entry to the list: an id that never changes (saves
-- store it; ids it had before go in oldIds so older saves still load), the name the HUD shows, the start and finish coordinates, and the towns nearest the
-- start and finish, which the HUD shows so the player can find them on the map, a one-line
-- summary for the Stages tab, a short briefing shown when the stage starts, the money the player starts it with, and the time limit
-- in seconds (the stage's Google Maps driving time; set targetIsEstimate = true to mark a guess). The finish counts once the vehicle is within
-- finishRadiusMetres of it. Each stage also has a difficulty from 1 (gentle) to 5 (deadly), not shown in the HUD,
-- and the road distance in lengthKm, shown in the stage list (approximate; leave it out and the HUD shows the
-- straight-line distance). Pay is the same on every stage. The first stage is where a new player
-- starts. A stage can set its own sponsorBonus (dollars), sponsorEveryKm and finishReward (dollars,
-- paid on reaching the finish); otherwise the defaults below apply. Stages are optional: the player can start any stage
-- from the Stages tab at any time, taking the car and money they have. List order is only the order
-- the HUD shows them in, and the stage a finish offers as next.
local location = require('beamngEarthEnduro/location')
local M = {}

-- Sponsor bonus: paid once for every SPONSOR_EVERY_KM of counted driving on a stage.
M.SPONSOR_BONUS = 4000
M.SPONSOR_EVERY_KM = 10
-- Stage complete reward: paid once when the player reaches the finish.
M.FINISH_REWARD = 25000

M.list = {
  {
    id = 'stage_1', oldIds = { 'zoji_la' }, name = 'Stage 1: Zoji La Pass',
    summary = 'Shelf road over a 3,528 m Himalayan pass.',
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
    summary = 'Bush roads north of the Hawkesbury River.',
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
  -- Stages 3 to 8: coordinates from Wikipedia, gazetteer and border-post listings, not yet checked
  -- in game; time limits are estimates, not Google Maps times.
  {
    id = 'death_road', name = 'Stage 3: Death Road',
    summary = 'Cliff-edge dirt track from 4,650 m into the jungle.',
    startTown = 'La Cumbre pass, Bolivia', finishTown = 'Yolosa, Bolivia',
    briefing = 'Drive from the La Cumbre pass at 4,650 m down the North Yungas Road, the Death Road, '
      .. 'a cliff-edge dirt track that drops into the jungle at Yolosa. Reach the finish to complete the stage.',
    start = { latitude = -16.3367, longitude = -68.0406 },
    finish = { latitude = -16.2333, longitude = -67.7333 },
    finishRadiusMetres = 100,
    difficulty = 5, lengthKm = 60,
    startingMoney = 3000,
    -- Time limit: 2 h 0 min.
    targetSeconds = 2 * 3600, targetIsEstimate = true,
  },
  {
    id = 'fairy_meadows', name = 'Stage 4: Fairy Meadows Road',
    summary = 'Gravel shelf above the Indus with no guardrails.',
    startTown = 'Raikot Bridge, Gilgit-Baltistan', finishTown = 'Tato, Gilgit-Baltistan',
    briefing = 'Drive from the Raikot Bridge on the Karakoram Highway up the Fairy Meadows Road, a narrow gravel shelf '
      .. 'above the Indus with no guardrails, to Tato village. Reach the finish to complete the stage.',
    start = { latitude = 35.4926, longitude = 74.5918 },
    finish = { latitude = 35.4331, longitude = 74.5979 },
    finishRadiusMetres = 100,
    difficulty = 5, lengthKm = 15,
    startingMoney = 3000,
    -- Time limit: 45 min.
    targetSeconds = 45 * 60, targetIsEstimate = true,
  },
  {
    id = 'sani_pass', name = 'Stage 5: Sani Pass',
    summary = 'Gravel hairpins up into Lesotho.',
    startTown = 'Sani Pass border post, South Africa', finishTown = 'Sani Top, Lesotho',
    briefing = 'Drive from the South African border post up the gravel hairpins of the Sani Pass '
      .. 'to Sani Top in Lesotho. Reach the finish to complete the stage.',
    start = { latitude = -29.6030, longitude = 29.3391 },
    finish = { latitude = -29.5847, longitude = 29.2856 },
    finishRadiusMetres = 100,
    difficulty = 4, lengthKm = 9,
    startingMoney = 3000,
    -- Time limit: 30 min.
    targetSeconds = 30 * 60, targetIsEstimate = true,
  },
  {
    id = 'skippers_canyon', name = 'Stage 6: Skippers Canyon',
    summary = 'One-lane canyon road to a bridge 91 m up.',
    startTown = 'Skippers Saddle, Queenstown', finishTown = 'Skippers Bridge, Otago',
    briefing = 'Drive from Skippers Saddle down the one-lane Skippers Canyon Road to the Skippers Bridge, '
      .. '91 m above the Shotover River. Reach the finish to complete the stage.',
    start = { latitude = -44.94, longitude = 168.71 },
    finish = { latitude = -44.8444, longitude = 168.6868 },
    finishRadiusMetres = 100,
    difficulty = 4, lengthKm = 13,
    startingMoney = 3000,
    -- Time limit: 30 min.
    targetSeconds = 30 * 60, targetIsEstimate = true,
  },
  {
    id = 'dalton_highway', name = 'Stage 7: Dalton Highway',
    summary = 'Arctic haul road over the Atigun Pass.',
    startTown = 'Chandalar Shelf, Alaska', finishTown = 'Galbraith Lake, Alaska',
    briefing = 'Drive the Dalton Highway from the Chandalar Shelf over the Atigun Pass and across the Brooks Range '
      .. 'to Galbraith Lake. Reach the finish to complete the stage.',
    start = { latitude = 68.0481, longitude = -149.6230 },
    finish = { latitude = 68.4532, longitude = -149.4837 },
    finishRadiusMetres = 100,
    difficulty = 3, lengthKm = 61,
    startingMoney = 3000,
    -- Time limit: 1 h 15 min.
    targetSeconds = 75 * 60, targetIsEstimate = true,
  },
  {
    id = 'transfagarasan', name = 'Stage 8: Transfăgărășan',
    summary = 'Carpathian hairpins up to a glacial lake.',
    startTown = 'Cârțișoara, Romania', finishTown = 'Bâlea Lac, Romania',
    briefing = 'Drive from Cârțișoara up the hairpins of the Transfăgărășan to the glacial lake at Bâlea Lac. '
      .. 'Reach the finish to complete the stage.',
    start = { latitude = 45.7239, longitude = 24.5792 },
    finish = { latitude = 45.6033, longitude = 24.6172 },
    finishRadiusMetres = 100,
    difficulty = 2, lengthKm = 30,
    startingMoney = 3000,
    -- Time limit: 45 min.
    targetSeconds = 45 * 60, targetIsEstimate = true,
  },
}

local function copy(stage, index)
  return {
    number = index, count = #M.list,
    id = stage.id, name = stage.name, startTown = stage.startTown, finishTown = stage.finishTown,
    summary = stage.summary, briefing = stage.briefing, start = location.copy(stage.start), finish = location.copy(stage.finish),
    finishRadiusMetres = stage.finishRadiusMetres, startingMoney = stage.startingMoney or 0,
    targetSeconds = stage.targetSeconds, targetIsEstimate = stage.targetIsEstimate == true,
    difficulty = stage.difficulty or 1,
    lengthKm = stage.lengthKm or math.floor((location.distance(stage.start, stage.finish) or 0) / 1000 + 0.5),
    lengthIsStraight = stage.lengthKm == nil,
    sponsorBonus = stage.sponsorBonus or M.SPONSOR_BONUS,
    sponsorEveryKm = stage.sponsorEveryKm or M.SPONSOR_EVERY_KM,
    finishReward = stage.finishReward or M.FINISH_REWARD,
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
