-- CarKov: an extraction run outside the stages. The player pays to enter, their car is dropped at a
-- random place on land anywhere on Earth, and they drive to an extraction point a set distance away
-- in a straight line, on or off road. The stage is saved on entry and the player goes back to it
-- afterwards with their car and money. The core controller runs the run; this file holds its
-- settings and picks the points.
local location = require('beamngEarthEnduro/location')
local M = {}

-- One-line settings. Tune these after testing in game.
M.ENTRY_FEE = 2000
M.REWARD = 15000
M.EXTRACTION_KM = 15 -- straight line from the drop
M.EXTRACTION_RADIUS_METRES = 100 -- the extraction counts once the car is this close
M.DROP_RADIUS_METRES = 500 -- arriving anywhere this close to the drop point starts the run
M.EXTRACT_HOLD_SECONDS = 5 -- the car must stay in the extraction zone this long
M.CLOSING_IN_METRES = 1000 -- the HUD counts down in metres from here
-- Random tries before giving up: drop points, then extraction bearings around each drop.
local DROP_TRIES, BEARING_TRIES = 5000, 64

-- The land map (landmask.lua, built by tools/make_land_mask.py): land less lakes, Antarctica,
-- Greenland and the big deserts, and less anything touching water. Rows are decoded on first use.
local mask
local decoded = {}
local function row(index)
  local runs = decoded[index]
  if runs then return runs end
  runs = {}
  local text = mask.rows[index] or ''
  for i = 1, #text - 2, 3 do runs[#runs + 1] = tonumber(text:sub(i, i + 2), 36) end
  decoded[index] = runs
  return runs
end

-- Whether a CarKov point may land here.
function M.land(p)
  if not location.valid(p) then return false end
  mask = mask or require('beamngEarthEnduro/landmask')
  local cells = mask.CELLS_PER_DEGREE
  local x = math.min(mask.WIDTH - 1, math.floor((p.longitude + 180) * cells))
  local y = math.min(mask.HEIGHT, math.floor((90 - p.latitude) * cells) + 1)
  local runs = row(y)
  for i = 1, #runs - 1, 2 do
    if x < runs[i] then return false end
    if x < runs[i + 1] then return true end
  end
  return false
end

-- Picks a drop point, spread evenly over the Earth's surface, and an extraction point EXTRACTION_KM
-- from it on a random bearing; each is picked again until it is on land. random() returns a number
-- in [0, 1). Returns the drop and extraction, or nil when nothing was found.
function M.pick(random)
  for _ = 1, DROP_TRIES do
    local drop = { latitude = math.deg(math.asin(2 * random() - 1)), longitude = 360 * random() - 180 }
    if M.land(drop) then
      for _ = 1, BEARING_TRIES do
        local extraction = location.destination(drop, random() * 360, M.EXTRACTION_KM * 1000)
        if M.land(extraction) then return drop, extraction end
      end
    end
  end
  return nil
end

return M
