-- Read-only source identity for the TASK-001 baseline. Normalize Windows CRLF.
-- Adler-32 + length identifies supported source; this is not a security signature.
local M = {
  revision = 'bd9c764cb0aa47ae65f1d4998d00c9517988796e',
  version = '1.5.4-beta',
  serverReportedVersion = '0.4.0', -- inspected server/netfetch.py:57; also stale in this revision
  files = {
    core = { 94002, 281365650 }, places = { 21713, 3813163732 },
    geodesy = { 7815, 4188010790 }, net = { 5342, 1590153972 },
    lattice = { 4704, 1809221165 }, roads = { 47619, 779273986 },
    drophold = { 5751, 2673762612 },
    edgeguard = { 9226, 2882697033 }, rebase = { 12882, 1722252714 },
  },
}

function M.checksum(text)
  local a, b = 1, 0
  for i = 1, #text do
    a = (a + text:byte(i)) % 65521
    b = (b + a) % 65521
  end
  return b * 65536 + a
end

function M.check(read)
  for name, expected in pairs(M.files) do
    local ok, text = pcall(read, '/lua/ge/extensions/beamngEarth/' .. name .. '.lua')
    if not ok or type(text) ~= 'string' then return false, 'source_unreadable:' .. name end
    text = text:gsub('\r\n', '\n')
    if #text ~= expected[1] or M.checksum(text) ~= expected[2] then
      return false, 'unsupported_source:' .. name
    end
  end
  return true, M.version .. ' / ' .. M.revision
end

return M
