-- AI Mouse: ⌥⌘A asks a question about what you're pointing at, ⌥⌘E just explains it
local PYTHON = "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3"
local SCRIPT = os.getenv("HOME") .. "/Desktop/AI_mouse_agent/ask.py"

-- "Breathing" orb, ported from thinking-orbs by Jakub Antalik (MIT):
-- https://github.com/Jakubantalik/thinking-orbs (ring mode, size-20 preset)
local ORB, PAD = 20, 3
local W = ORB + 2 * PAD
local LANES, SEGS, WOB, SPEED = 8, 15, 0.565, 3.78
local RBASE, RDEPTH = 1.7842, 2.7574
local RS = (ORB / 300) ^ 0.6
local R = ORB / 2 * 0.78
local BASE_R = R / (1 + 0.85 * 0.23 * WOB)
local CT, ST = math.cos(0.3), math.sin(0.3)  -- fixed camera tilt
-- Frames are drawn once and looped. The original wave speeds (1.7, 1.1) are
-- nudged to 3 and 2 cycles per loop so the loop has no visible seam.
local FPS, LOOP = 30, 3  -- seconds
local F1, F2 = 2 * math.pi * 3 / (LOOP * SPEED), 2 * math.pi * 2 / (LOOP * SPEED)

local HIDPI = 2  -- frames are drawn at 2x so they stay sharp on Retina screens

local function orbElements(t, dark)
  local glow = { white = dark and 0 or 1, alpha = 0.35 }  -- keeps dots visible on any background
  local dots = {}
  local mid = (LANES - 1) / 2
  for w = 0, LANES - 1 do
    local off = (w - mid) * 0.075
    local edge = math.abs(w - mid) / math.max(1, mid)
    for k = 0, SEGS - 1 do
      local a = k / SEGS * 2 * math.pi
      local wob = (0.16 * math.sin(a * 3 - t * F1 + w * 0.22) + 0.07 * math.sin(a * 5 + t * F2)) * WOB
      local x, y, z = math.cos(a), CT * math.sin(a) + ST * off, -ST * math.sin(a) + CT * off
      local s = BASE_R * (1 + wob) / math.sqrt(x * x + y * y + z * z)
      x, y, z = x * s, y * s, z * s
      local depth = ((y * ST + z * CT) / R + 1) / 2
      local ink = 0.52 - 0.44 * depth + 0.18 * edge
      dots[#dots + 1] = { depth, {
        type = "circle", action = "fill",
        center = { x = (W / 2 + x) * HIDPI, y = (W / 2 - (y * CT - z * ST)) * HIDPI },
        radius = math.max(0.3, (RBASE + RDEPTH * depth) * (1 - 0.25 * edge) * RS) * HIDPI,
        fillColor = { white = dark and 1 - ink or ink, alpha = 0.4 + 0.6 * depth },
        withShadow = true, shadow = { blurRadius = 0.6 * HIDPI, color = glow, offset = { h = 0, w = 0 } },
      } }
    end
  end
  table.sort(dots, function(p, q) return p[1] < q[1] end)  -- far dots first
  local els = {}
  for _, d in ipairs(dots) do els[#els + 1] = d[2] end
  return els
end

local cache = {}
local function frames()
  local dark = hs.host.interfaceStyle() == "Dark"
  local key = dark and "dark" or "light"
  if not cache[key] then
    local c = hs.canvas.new({ x = 0, y = 0, w = W * HIDPI, h = W * HIDPI })
    cache[key] = {}
    for i = 0, FPS * LOOP - 1 do
      c:replaceElements(orbElements(i / FPS * SPEED, dark))
      cache[key][#cache[key] + 1] = c:imageFromCanvas()
    end
    c:delete()
  end
  return cache[key]
end
frames()  -- draw ahead of time so the first use starts instantly

-- Shows the orb just below-right of the cursor and follows it. Returns a function that removes it.
local function spinner()
  local imgs = frames()
  local c = hs.canvas.new({ x = 0, y = 0, w = W, h = W })
  c:level("overlay")
  c:behavior({ "canJoinAllSpaces", "fullScreenAuxiliary" })  -- also show over full-screen apps
  c[1] = { type = "image", image = imgs[1], imageScaling = "scaleProportionally",
           frame = { x = 0, y = 0, w = W, h = W } }
  local start, shown = hs.timer.secondsSinceEpoch(), 1
  local function tick()
    local p = hs.mouse.absolutePosition()
    c:topLeft({ x = p.x + 14, y = p.y + 14 })
    local i = math.floor((hs.timer.secondsSinceEpoch() - start) * FPS) % #imgs + 1
    if i ~= shown then c[1].image = imgs[i]; shown = i end
  end
  tick()
  c:show()
  local timer = hs.timer.doEvery(1 / 60, tick)  -- 60 fps keeps the cursor-follow smooth
  return function() timer:stop(); c:delete() end
end

local function aiMouse(args)
  local stop
  local function hide() if stop then stop(); stop = nil end end
  hs.task.new(PYTHON, hide,  -- also hide on exit, in case of a crash
    function(_, out)
      if out:find("done") then hide()
      elseif out:find("thinking") and not stop then stop = spinner() end
      return true
    end,
    args):start()
end

hs.hotkey.bind({ "alt", "cmd" }, "A", function() aiMouse({ SCRIPT }) end)
hs.hotkey.bind({ "alt", "cmd" }, "E", function() aiMouse({ SCRIPT, "--explain" }) end)
