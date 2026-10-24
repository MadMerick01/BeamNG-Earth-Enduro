-- Service Perks. The player holds one perk at a time; every OFFER_EVERY_KM of counted driving a
-- random perk is offered to keep or swap for. Any repair loses the perk held, except Insurance.
-- Passive perks work by themselves the next time they apply; the others wait for Activate.
-- Once activated, a timed perk (Time Freeze, Lucky Mile) runs out on its own: it no longer sits in
-- the perk slot, so a repair does not stop it and a new perk can be offered meanwhile.
local M = {}

-- One-line settings. Tune these after testing in game.
M.OFFER_EVERY_KM = 5
M.DOUBLE_CASH_MULTIPLIER = 2 -- driving pay while Double Cash is held
M.SPONSOR_BOOST_MULTIPLIER = 2 -- the next sponsor bonus
M.TIME_FREEZE_SECONDS = 180 -- the stage clock stops this long once activated
M.PARTS_DISCOUNT_SHARE = 0.5 -- taken off the parts on the next parts bill (not the repair in it)
M.CAR_DISCOUNT_SHARE = 0.3 -- taken off the price of the next new car
M.PACE_GIFT_SECONDS = 120 -- taken off the stage clock once activated
M.LUCKY_MILE_KM = 5 -- driving pay is multiplied for this far once activated
M.LUCKY_MILE_MULTIPLIER = 3

local function minutes(seconds)
  local m, s = math.floor(seconds / 60), seconds % 60
  return s == 0 and (m .. ' minute' .. (m == 1 and '' or 's')) or string.format('%d:%02d', m, s)
end
local function percent(share) return math.floor(share * 100 + 0.5) .. '%' end
local function times(n) return n == 2 and 'double' or (n == 3 and 'triple' or (n .. 'x')) end

-- The perks, in the order the Tips tab lists them. Ids are saved, so they never change.
function M.list()
  return {
    { id = 'doubleCash', name = 'Double Cash',
      description = 'While you hold it, driving pays ' .. times(M.DOUBLE_CASH_MULTIPLIER) .. '.' },
    { id = 'sponsorBoost', name = 'Sponsor Boost',
      description = 'Your next sponsor bonus pays ' .. times(M.SPONSOR_BOOST_MULTIPLIER) .. '.' },
    { id = 'timeFreeze', name = 'Time Freeze', activate = true,
      description = 'Activate to stop the stage clock for ' .. minutes(M.TIME_FREEZE_SECONDS) .. ' of driving.' },
    { id = 'noPenalty', name = 'No Penalty',
      description = 'Your next repair or new car costs no time. A repair uses it up instead of losing it.' },
    { id = 'partsDiscount', name = 'Parts Discount',
      description = 'Your next parts bill is ' .. percent(M.PARTS_DISCOUNT_SHARE) .. ' off the parts.' },
    { id = 'carDeal', name = 'Car Dealer Deal',
      description = 'Your next new car costs ' .. percent(M.CAR_DISCOUNT_SHARE) .. ' less.' },
    { id = 'paceGift', name = 'Pace Gift', activate = true,
      description = 'Activate to take ' .. minutes(M.PACE_GIFT_SECONDS) .. ' off your stage clock.' },
    { id = 'insurance', name = 'Insurance',
      description = 'If you are out of money and your damaged car cannot move, it pays for the repair once. Repairs do not lose it.' },
    { id = 'luckyMile', name = 'Lucky Mile', activate = true,
      description = 'Activate to make the next ' .. M.LUCKY_MILE_KM .. ' km of driving pay ' .. times(M.LUCKY_MILE_MULTIPLIER) .. '.' },
  }
end

-- Returns the perk with this id, or nil.
function M.get(id)
  for _, perk in ipairs(M.list()) do
    if perk.id == id then return perk end
  end
  return nil
end

-- A random perk other than the one held. random() returns a number in [0, 1).
function M.pick(random, held)
  local choices = {}
  for _, perk in ipairs(M.list()) do
    if perk.id ~= held then choices[#choices + 1] = perk.id end
  end
  local index = math.floor(random() * #choices) + 1
  return choices[math.max(1, math.min(#choices, index))]
end

return M
