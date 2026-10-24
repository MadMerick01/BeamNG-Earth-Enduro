local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local F = require('fixtures')
local P = require('beamngEarthEnduro/persistence')
local stages = require('beamngEarthEnduro/stages')
local A = P.DIRECTORY .. 'save-a.json'
local north = 1 / 111195.0802 -- degrees latitude per metre
local BONUS, EVERY = stages.first().sponsorBonus, stages.first().sponsorEveryKm
T.eq(BONUS, 2000, 'sponsor pays $2,000'); T.eq(EVERY, 10, 'every 10 km')

-- Drives north from the current odometer reading, in 100 m steps at 100 m/s.
local function drive(c, a, fromMetres, metres)
  for step = 1, math.floor(metres / 100) do a.pose = F.position((fromMetres + step * 100) * north); c:tick(1) end
  return fromMetres + metres
end
local DRIVING_PAY = 100 -- dollars per km

do
  local c, io, a = F.controller()
  c:tick(0.1)
  local s = c:view().sponsor
  T.eq(s.amount, BONUS, 'HUD shows the bonus amount'); T.near(s.nextKm, 10, 1e-9, 'first bonus 10 km away'); T.eq(s.earned, 0, 'none earned yet')
  local at = drive(c, a, 0, 3200)
  T.near(c:view().sponsor.nextKm, 6.8, 1e-6, 'counts down as the player drives'); T.near(c:view().sponsor.progress, 0.32, 1e-6, 'bar fills with distance')
  T.eq(c:view().sponsor.flash, nil, 'no flash before 10 km')
  at = drive(c, a, at, 6800)
  T.eq(c:view().sponsor.earned, 1, 'one bonus at 10 km'); T.eq(c:view().balance, 10 * DRIVING_PAY + BONUS, 'bonus added to the balance')
  T.eq(c:view().sponsor.flash.amount, BONUS, 'bonus flashes on the HUD'); T.near(c:view().sponsor.nextKm, 10, 1e-6, 'next bonus 10 km on')
  F.advance(c, 7); T.eq(c:view().sponsor.flash, nil, 'flash fades after a few seconds')
  -- A teleport pays nothing, however far it goes.
  a.pose = F.position((at + 50000) * north); c:tick(0.1); at = at + 50000
  T.eq(c:view().sponsor.earned, 1, 'teleports earn no bonus')
  T.check(c:manualSave(), 'saved'); T.eq(io.files[A].progression.sponsorBonuses, 1, 'bonus count saved')
  -- Unsaved bonuses go with a reload, and the reloaded count stops the next one paying twice.
  drive(c, a, at, 10000)
  T.eq(c:view().sponsor.earned, 2, 'second bonus at 20 km')
  c:reload(); a.pose = F.position(at * north); c:tick(0.1)
  T.eq(c:view().sponsor.earned, 1, 'reload restores the saved count'); T.eq(c:view().balance, 10 * DRIVING_PAY + BONUS, 'and the saved balance')
  drive(c, a, at, 9900); T.eq(c:view().sponsor.earned, 1, 'no bonus before 20 km'); T.eq(c:view().balance, 10 * DRIVING_PAY + BONUS + 990, 'only driving pay')
  drive(c, a, at + 9900, 100); T.eq(c:view().sponsor.earned, 2, 'paid once at 20 km')
  -- No bonus after the finish.
  c.stageFinished = true; drive(c, a, at + 10000, 10000); T.eq(c:view().sponsor.earned, 2, 'no bonus after the finish')
  c.stageFinished = false
  -- Restart stage resets the count.
  c:restartStage(); T.check(c:restartStage(), 'stage restarted')
  T.eq(io.files[P.DIRECTORY .. 'save-' .. c.store.slot .. '.json'].progression.sponsorBonuses, 0, 'restart saves no bonuses')
  T.eq(c:view().sponsor.earned, 0, 'restart resets the count'); T.near(c:view().sponsor.nextKm, 10, 1e-9, 'next bonus 10 km from the start')
end

-- A save from before sponsor bonuses treats the distance already driven as paid.
do
  local io = F.io({ ['/settings/beamngEarthEnduro/config.json'] = F.config(), [A] = F.save(1, 0, 0) })
  io.files[A].progression.totalDistanceKm = 25
  local c, _, a = F.controller({ io = io })
  T.eq(c.profile.progression.sponsorBonuses, 2, 'older save counts 20 km as paid')
  local balance = c.profile.progression.balance
  a.pose = F.position(0, 0); c:tick(0.1)
  drive(c, a, 0, 4900); T.eq(c:view().sponsor.earned, 2, 'nothing back-paid'); T.eq(c:view().balance, balance + 490, 'only driving pay')
  drive(c, a, 4900, 100); T.eq(c:view().sponsor.earned, 3, 'next bonus at 30 km'); T.eq(c:view().balance, balance + 500 + BONUS, 'bonus paid')
end

-- Saves reject a bad bonus count.
for _, bad in ipairs({ -1, 1.5, 'two' }) do
  local s = F.save(); s.progression.sponsorBonuses = bad; T.eq(P.validate(s), nil, 'invalid bonus count rejected')
end
T.done('sponsor bonus')
