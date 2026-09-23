-- hiscore.lua : top-five solo scores, kept in LÖVE's save directory.
local HS = {}
local FILE = "hiscores.txt"
local MAX = 5

HS.list = {}

function HS.load()
  HS.list = {}
  if love.filesystem.getInfo(FILE) then
    for line in love.filesystem.lines(FILE) do
      local score, level = line:match("^(%d+)%s+(%d+)")
      if score then HS.list[#HS.list + 1] = { score = tonumber(score), level = tonumber(level) } end
    end
  end
  if #HS.list == 0 then
    for i = 1, MAX do HS.list[i] = { score = (MAX - i + 1) * 2000, level = 10 } end
  end
end

function HS.save()
  local out = {}
  for _, e in ipairs(HS.list) do out[#out + 1] = ("%d %d"):format(e.score, e.level) end
  love.filesystem.write(FILE, table.concat(out, "\n") .. "\n")
end

-- Inserts a score. Returns its rank (1-based) or nil if it did not make the table.
function HS.add(score, level)
  if score <= 0 then return nil end
  for i = 1, MAX do
    if not HS.list[i] or score > HS.list[i].score then
      table.insert(HS.list, i, { score = score, level = level })
      while #HS.list > MAX do table.remove(HS.list) end
      HS.save()
      return i
    end
  end
  return nil
end

return HS
