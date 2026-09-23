-- audiotest.lua : build every sound and tune and report what is in them, so a silent or
-- clipped one is caught without anyone listening.
local music = require("music")
local out = {}
local function stats(name, sd)
  local n = sd:getSampleCount()
  local peak, sum, zero = 0, 0, 0
  local last = 0
  for i = 0, n - 1 do
    local v = sd:getSample(i)
    if math.abs(v) > peak then peak = math.abs(v) end
    sum = sum + v * v
    if (v >= 0) ~= (last >= 0) then zero = zero + 1 end
    last = v
  end
  local rms = math.sqrt(sum / n)
  -- crossings per second gives the rough pitch of the sound
  out[#out + 1] = ("%-8s %6.2f s  peak %.2f  loudness %.3f  pitch about %d Hz")
    :format(name, n / sd:getSampleRate(), peak, rms, zero / 2 / (n / sd:getSampleRate()))
end
return { stats = stats, out = out }
