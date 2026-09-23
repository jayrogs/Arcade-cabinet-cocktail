return function(G, tick, beginGame, startRound, AI, Board, music, HS, sfx)
  local frame, log = 0, {}
  local realPlay = sfx.play
  sfx.play = function(name) log[#log + 1] = { frame, "SOUND " .. name } return realPlay(name) end
  G.titleSel = 3
  G.settings[1] = { level = 3, speed = "low" }   -- easy: the CPU will clear and combo
  beginGame(3)
  tick({ { start = true }, {} })
  for _ = 1, 120 do tick({ {}, {} }) end
  local human = G.boards[1]
  for p = 1, 2 do
    local b = G.boards[p]
    local old = b.emit
    b.emit = function(self, e)
      log[#log + 1] = { frame, (p == 1 and "P1 " or "CPU ") .. e }
      return old(self, e)
    end
  end
  -- the human sits still so every sound in the log is either the CPU's or a reaction to it
  while G.state == "play" and frame < 40000 do
    tick({ {}, {} })
    frame = frame + 1
  end
  sfx.play = realPlay
  print("state " .. G.state .. " after " .. frame .. " frames")
  local counts = {}
  for _, e in ipairs(log) do counts[e[2]] = (counts[e[2]] or 0) + 1 end
  local keys = {}
  for k in pairs(counts) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do print(("%-14s %d"):format(k, counts[k])) end
  -- show the window around the CPU's first combo
  for i, e in ipairs(log) do
    if e[2] == "CPU combo1" or e[2] == "CPU combo2" then
      print("--- around the CPU's first combo (frame " .. e[1] .. ") ---")
      for j = math.max(1, i - 3), math.min(#log, i + 12) do
        print(("  f%-6d %s"):format(log[j][1], log[j][2]))
      end
      break
    end
  end
end
