-- The rally's stages. To add one, add an entry to the list: an id that never changes (saves
-- store it), the name the HUD shows, the start and finish coordinates, and the towns nearest the
-- start and finish, which the HUD shows so the player can find them on the map, and a short
-- briefing shown when the stage starts, and the money the player starts it with. The finish counts
-- once the vehicle is within finishRadiusMetres of it. The first stage is where a new player starts.
local location = require('beamngEarthEnduro/location')
local M = {}

M.list = {
  {
    id = 'zoji_la', name = 'Zoji La',
    startTown = 'Gund, Kashmir', finishTown = 'Dras, Ladakh',
    briefing = 'Drive from Gund, Kashmir, up the Sind valley past Sonamarg and over the Zoji La pass to Dras, Ladakh. '
      .. 'Reach the finish to complete the stage.',
    start = { latitude = 34.224032, longitude = 75.029787 },
    finish = { latitude = 34.43223, longitude = 75.80991 },
    finishRadiusMetres = 100,
    startingMoney = 3000,
  },
}

local function copy(stage)
  return {
    id = stage.id, name = stage.name, startTown = stage.startTown, finishTown = stage.finishTown,
    briefing = stage.briefing, start = location.copy(stage.start), finish = location.copy(stage.finish),
    finishRadiusMetres = stage.finishRadiusMetres, startingMoney = stage.startingMoney or 0,
  }
end

function M.first() return copy(M.list[1]) end

-- Returns the stage with this id, or nil when this version has no such stage.
function M.get(id)
  for _, stage in ipairs(M.list) do
    if stage.id == id then return copy(stage) end
  end
  return nil
end

return M
