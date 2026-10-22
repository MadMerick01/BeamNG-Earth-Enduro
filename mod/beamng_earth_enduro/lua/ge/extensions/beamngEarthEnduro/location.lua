-- Pure geographic math and continuous-sample verification; no game globals.
local M = {}
local rad, sin, cos, sqrt, atan2 = math.rad, math.sin, math.cos, math.sqrt, math.atan2
local EARTH_MEAN_RADIUS = 6371008.8 -- metres; spherical short-range approximation for WGS84 coordinates

function M.finite(v)
  return type(v) == 'number' and v == v and v > -math.huge and v < math.huge
end

function M.valid(p)
  return type(p) == 'table' and M.finite(p.latitude) and M.finite(p.longitude)
    and p.latitude >= -90 and p.latitude <= 90 and p.longitude >= -180 and p.longitude <= 180
end

function M.copy(p)
  if not M.valid(p) then return nil end
  return { latitude = p.latitude, longitude = p.longitude }
end

function M.distance(a, b)
  if not M.valid(a) or not M.valid(b) then return nil end
  local dlat, dlon = rad(b.latitude - a.latitude), rad(b.longitude - a.longitude)
  local h = sin(dlat / 2)^2 + cos(rad(a.latitude)) * cos(rad(b.latitude)) * sin(dlon / 2)^2
  h = math.max(0, math.min(1, h))
  return 2 * EARTH_MEAN_RADIUS * atan2(sqrt(h), sqrt(1 - h))
end

function M.verifier(radius, seconds)
  assert(M.finite(radius) and radius > 0 and M.finite(seconds) and seconds > 0)
  local v = { elapsed = 0 }
  function v:reset()
    self.elapsed, self.epoch, self.target = 0, nil, nil
  end
  function v:step(pose, target, dt, epoch)
    local distance = M.distance(pose, target)
    if not distance or distance > radius or epoch == nil or not M.finite(dt) or dt <= 0 or dt > 1 then
      self:reset()
      return false, distance
    end
    if self.epoch ~= epoch or not self.target or self.target.latitude ~= target.latitude
        or self.target.longitude ~= target.longitude then
      self.elapsed, self.epoch, self.target = 0, epoch, M.copy(target)
    else
      self.elapsed = self.elapsed + dt
    end
    return self.elapsed + 1e-9 >= seconds, distance
  end
  return v
end

return M
