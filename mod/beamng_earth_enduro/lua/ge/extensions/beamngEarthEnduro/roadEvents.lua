-- Roadside events: on a stage or a CarKov run, now and then something happens by the road. Every
-- EVERY_KM of counted driving there is a CHANCE of an event, which is either a friendly village
-- offering a free part for the car (Install fits it and repairs the car for free, with no time
-- penalty and without losing the perk held) or bandits making off with some of the player's money.
-- The core controller decides when; this file holds the settings and the choices.
local M = {}

-- One-line settings. Tune these after testing in game.
M.EVERY_KM = 20
-- The checks fall halfway between perk offers (every 5 km), so an event never comes at the same
-- moment as one: at 22.5 km, 42.5 km and so on.
M.OFFSET_KM = 2.5
M.CHANCE = 1 / 3 -- of an event at each check
M.VILLAGE_SHARE = 0.5 -- of events that are a friendly village; the rest are bandits
M.BANDITS_MIN, M.BANDITS_MAX = 100, 1000 -- dollars taken, never more than the player has
M.SAFE_FINISH_METRES = 1000 -- none this close to the stage finish or CarKov extraction
M.SHOWN_FOR = 8 -- seconds the HUD shows what happened

-- The slots a village part can go in, by the part's slot type, and the name the card gives them.
-- The first pattern that matches wins.
M.SLOTS = {
  { pattern = '^tire', label = 'Tyres' },
  { pattern = 'brake', label = 'Brakes' },
  { pattern = 'coilover', label = 'Suspension' },
  { pattern = 'spring', label = 'Suspension' },
  { pattern = 'shock', label = 'Suspension' },
  { pattern = 'damper', label = 'Suspension' },
  { pattern = '_engine$', label = 'Engine' },
  { pattern = '^engine$', label = 'Engine' },
}

-- The label for a slot type, or nil when village parts never go in it.
function M.category(slotType)
  if type(slotType) ~= 'string' then return nil end
  local lower = slotType:lower()
  for _, slot in ipairs(M.SLOTS) do
    if lower:find(slot.pattern) then return slot.label end
  end
  return nil
end

-- How many checks are due by this distance: one at OFFSET_KM past each whole EVERY_KM.
function M.due(km)
  if type(km) ~= 'number' or km ~= km then return 0 end
  return math.max(0, math.floor((km - M.OFFSET_KM) / M.EVERY_KM))
end

-- Whole dollars the bandits take, before the balance limits it. random() returns a number in [0, 1).
function M.banditAmount(random)
  local span = M.BANDITS_MAX - M.BANDITS_MIN + 1
  return M.BANDITS_MIN + math.max(0, math.min(span - 1, math.floor(random() * span)))
end

-- A random one of a list, or nil when it is empty.
function M.pick(random, list)
  if type(list) ~= 'table' or #list == 0 then return nil end
  return list[math.max(1, math.min(#list, math.floor(random() * #list) + 1))]
end

return M
