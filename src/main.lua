-- Ajedrez Táctico: ejercicios de la base de Lichess para consolas tipo R36S (LÖVE 11.x).
local C = require("chess")
local lg = love.graphics

local VW, VH = 640, 480          -- resolución de diseño (la de la R36S)
local SQ, BX, BY = 56, 16, 16    -- tablero
local PX, PW = 478, 150          -- panel lateral

local fonts = {}
local sheet, quads = nil, {}

local puzzles, ratings, ids, idIndex = {}, {}, {}, {}
local NLEVELS = 10
local levelRange, levelSeen = {}, {}
local seen, seenCount = {}, 0
local save = { rating = 1500, rd = 350, peak = 1500, played = 0, clean = 0, streak = 0, best = 0, swap = 0, look = 1, sound = 1 }

-- Looks: los mismos colores que la vista previa web.
local function hex(h)
  return { tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255 }
end
local function look(name, t)
  local out = { name = name }
  for k, v in pairs(t) do out[k] = hex(v) end
  return out
end
local LOOKS = {
  look("Walnut", { bg = "#211f1c", light = "#f0d9b5", dark = "#b58863", last = "#ccd14d", sel = "#1a7326",
    check = "#e6261a", hint = "#3380f2", cursor = "#40e6ff", accent = "#ffd159", text = "#ffffff",
    muted = "#b8b8b8", dim = "#9e9e9e", bar = "#408cd9", good = "#73e673", bad = "#ff7366" }),
  look("Slate", { bg = "#1b2027", light = "#dee3e6", dark = "#8ca2ad", last = "#9bc700", sel = "#14551e",
    check = "#e0362c", hint = "#f2a33a", cursor = "#ffcf40", accent = "#7fd4ff", text = "#f4f7f9",
    muted = "#aab4bd", dim = "#8a949d", bar = "#3b7fb8", good = "#7be08a", bad = "#ff7d70" }),
  look("Midnight", { bg = "#0f1020", light = "#9fa8da", dark = "#4a4f8f", last = "#ffd166", sel = "#06d6a0",
    check = "#ef476f", hint = "#4cc9f0", cursor = "#ffffff", accent = "#ffd166", text = "#f1f1ff",
    muted = "#a8a9cc", dim = "#8586ad", bar = "#6a4fd1", good = "#06d6a0", bad = "#ef476f" }),
  look("Handheld", { bg = "#1f2b1b", light = "#c4cfa1", dark = "#8b956d", last = "#e8e36b", sel = "#2d4a2a",
    check = "#b5412f", hint = "#3f7f8f", cursor = "#f6ffc9", accent = "#d9e3a8", text = "#eef3d8",
    muted = "#aab58c", dim = "#8f9a75", bar = "#4d6a3d", good = "#cfe88a", bad = "#f0a07a" }),
}
local T = LOOKS[1]
local function col(k, a)
  local c = T[k]
  lg.setColor(c[1], c[2], c[3], a or 1)
end
local function applyLook()
  if not LOOKS[save.look] then save.look = 1 end
  T = LOOKS[save.look]
  lg.setBackgroundColor(T.bg[1], T.bg[2], T.bg[3])
end

local screen = "menu"
local menuIdx, levelIdx, themeIdx = 1, 1, 1
local mode = { kind = "train", title = "Training" }
local P = nil
local clock = 0

local THEMES = {
  { "mateIn1", "Mate in 1" }, { "mateIn2", "Mate in 2" }, { "mateIn3", "Mate in 3" },
  { "backRankMate", "Back-rank mate" }, { "fork", "Fork" }, { "pin", "Pin" },
  { "skewer", "Skewer" }, { "discoveredAttack", "Discovered attack" },
  { "doubleCheck", "Double check" }, { "sacrifice", "Sacrifice" },
  { "hangingPiece", "Hanging piece" }, { "trappedPiece", "Trapped piece" },
  { "deflection", "Deflection" }, { "attraction", "Attraction" },
  { "promotion", "Promotion" }, { "quietMove", "Quiet move" },
  { "opening", "Opening" }, { "middlegame", "Middlegame" }, { "endgame", "Endgame" },
}
local themeLists = {}

local MENU = { "Train at my level", "Choose level", "By theme", "Statistics", "Controls", "Look", "Sound", "Quit" }

---------------------------------------------------------------------------
-- utilidades
---------------------------------------------------------------------------
local function levelOf(r)
  local l = math.floor((r - 600) / 200) + 1
  if l < 1 then l = 1 end
  if l > NLEVELS then l = NLEVELS end
  return l
end

local function levelLabel(l)
  if l == 1 then return "up to 800" end
  if l == NLEVELS then return "2400 and up" end
  return (400 + l * 200) .. " to " .. (600 + l * 200)
end

local function thousands(n)
  local s = tostring(n)
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return out
end

local PUZZLE_RD, MIN_RD = 80, 75

-- con pocos ejercicios jugados el puntaje es provisional y se muestra con "?"
local function ratingText()
  return tostring(save.rating) .. (save.rd > 110 and "?" or "")
end

-- Efectos de sonido. Si el audio no está disponible, el juego sigue en silencio.
local sfx = {}
local function loadSounds()
  if not love.audio then return end
  local names = { "move", "capture", "good", "wrong", "win" }
  for i = 1, #names do
    local ok, src = pcall(love.audio.newSource, "sfx/" .. names[i] .. ".wav", "static")
    if ok then sfx[names[i]] = src end
  end
end
local function play(name)
  local s = sfx[name]
  if s and save.sound == 1 then
    pcall(function() s:stop(); s:play() end)
  end
end

-- Guardado. Se escribe en más de un lugar, porque en algunas consolas la carpeta
-- de guardado de LÖVE no conserva los archivos: junto al juego y además en la de LÖVE.
local stores, saveStatus = {}, { ok = false, where = "" }

local function ioStore(dir)
  local function open(name, m) return io.open(dir .. "/chessing_" .. name, m) end
  return {
    label = dir,
    read = function(name)
      local f = open(name, "rb")
      if not f then return nil end
      local data = f:read("*a")
      f:close()
      return data
    end,
    write = function(name, data, m)
      local f = open(name, m or "wb")
      if not f then return false end
      local ok = f:write(data)
      f:close()
      return ok ~= nil and ok ~= false
    end,
  }
end

local loveStore = {
  label = "the LOVE save folder",
  read = function(name)
    if love.filesystem.getInfo(name) then return (love.filesystem.read(name)) end
    return nil
  end,
  write = function(name, data, m)
    local fn = m == "ab" and love.filesystem.append or love.filesystem.write
    local ok, res = pcall(fn, name, data)
    return ok and res == true
  end,
}

local function setupStores()
  local base = love.filesystem.getSourceBaseDirectory()
  if base and base ~= "" then
    -- como port, la carpeta "saves" ya existe junto al juego; si no, junto al archivo
    local probe = io.open(base .. "/saves/chessing_save.txt", "ab")
    if probe then
      probe:close()
      stores[#stores + 1] = ioStore(base .. "/saves")
    else
      stores[#stores + 1] = ioStore(base)
    end
  end
  stores[#stores + 1] = loveStore
end

local function writeAll(name, data, m)
  local okAny, where = false, nil
  for i = 1, #stores do
    if stores[i].write(name, data, m) then
      okAny = true
      where = where or stores[i].label
    end
  end
  saveStatus.ok = okAny
  saveStatus.where = where or ""
  return okAny
end

local function writeSave()
  local s = string.format("rating=%d\nrd=%d\npeak=%d\nplayed=%d\nclean=%d\nstreak=%d\nbest=%d\nswap=%d\nlook=%d\nsound=%d\n",
    save.rating, save.rd, save.peak, save.played, save.clean, save.streak, save.best, save.swap, save.look, save.sound)
  writeAll("save.txt", s)
  -- que llegue de verdad a la tarjeta aunque la consola se apague de golpe
  if love.system and love.system.getOS() == "Linux" then pcall(os.execute, "sync") end
end

local function markSeen(id)
  if seen[id] then return end
  seen[id] = true
  seenCount = seenCount + 1
  local i = idIndex[id]
  if i then
    local l = levelOf(ratings[i])
    levelSeen[l] = levelSeen[l] + 1
  end
  writeAll("seen.txt", id .. "\n", "ab")
end

local function loadData()
  local n = 0
  for line in love.filesystem.lines("puzzles.txt") do
    local id, r = line:match("^([^;]*);(%d+);")
    if id then
      n = n + 1
      puzzles[n] = line
      ids[n] = id
      ratings[n] = tonumber(r)
      idIndex[id] = n
    end
  end
  for l = 1, NLEVELS do levelSeen[l] = 0 end
  for i = 1, n do
    local l = levelOf(ratings[i])
    if not levelRange[l] then levelRange[l] = { i, i } else levelRange[l][2] = i end
  end
  setupStores()
  local bestPlayed, storeSeen = -1, {}
  for i = 1, #stores do
    local txt = stores[i].read("save.txt")
    if txt then
      local t = {}
      for k, v in txt:gmatch("(%w+)=(-?%d+)") do t[k] = tonumber(v) end
      if (t.played or 0) > bestPlayed then
        bestPlayed = t.played or 0
        for k, v in pairs(t) do
          if save[k] ~= nil then save[k] = v end
        end
      end
    end
    local count = 0
    local list = stores[i].read("seen.txt")
    if list then
      for id in list:gmatch("%S+") do
        count = count + 1
        if idIndex[id] and not seen[id] then
          seen[id] = true
          seenCount = seenCount + 1
          local l = levelOf(ratings[idIndex[id]])
          levelSeen[l] = levelSeen[l] + 1
        end
      end
    end
    storeSeen[i] = count
  end
  -- deja todos los lugares de guardado al día y comprueba que se puede escribir
  if seenCount > 0 then
    local all = {}
    for id in pairs(seen) do all[#all + 1] = id end
    local blob = table.concat(all, "\n") .. "\n"
    for i = 1, #stores do
      if storeSeen[i] < seenCount then stores[i].write("seen.txt", blob) end
    end
  end
  writeSave()
end

local function themeList(key)
  if themeLists[key] then return themeLists[key] end
  local list = {}
  local needle = " " .. key .. " "
  for i = 1, #puzzles do
    local line = puzzles[i]
    local pos = line:match("^.*();")
    if line:find(needle, pos, true) then list[#list + 1] = i end
  end
  themeLists[key] = list
  return list
end

---------------------------------------------------------------------------
-- elección del siguiente ejercicio
---------------------------------------------------------------------------
-- primer k tal que ratings[at(k)] >= value (las listas están ordenadas por dificultad)
local function lowerBound(count, at, value)
  local lo, hi = 1, count + 1
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if ratings[at(mid)] < value then lo = mid + 1 else hi = mid end
  end
  return lo
end

local function pickNear(count, at, target)
  local current = P and P.idx or -1
  local w = 60
  for pass = 1, 2 do
    local allowSeen = pass == 2
    w = 60
    while true do
      local cands = {}
      local k1 = lowerBound(count, at, target - w)
      local k2 = lowerBound(count, at, target + w + 1) - 1
      for k = k1, k2 do
        local i = at(k)
        if i ~= current and (allowSeen or not seen[ids[i]]) then
          cands[#cands + 1] = i
        end
      end
      if #cands > 0 then return cands[love.math.random(#cands)] end
      if w > 4000 then break end
      w = w * 2
    end
  end
  return at(love.math.random(count))
end

local function pickNext()
  if mode.kind == "level" then
    local rg = levelRange[mode.level]
    local first, last = rg[1], rg[2]
    local current = P and P.idx or -1
    local cands = {}
    for i = first, last do
      if i ~= current and not seen[ids[i]] then cands[#cands + 1] = i end
    end
    if #cands > 0 then return cands[love.math.random(#cands)] end
    return love.math.random(first, last)
  elseif mode.kind == "theme" then
    local list = themeList(mode.key)
    return pickNear(#list, function(k) return list[k] end, save.rating)
  end
  return pickNear(#puzzles, function(k) return k end, save.rating)
end

---------------------------------------------------------------------------
-- lógica de un ejercicio
---------------------------------------------------------------------------
local function refreshPosition()
  P.legal = C.legalMoves(P.st)
  P.check = nil
  if C.inCheck(P.st, P.st.turn) then P.check = C.kingSquare(P.st, P.st.turn) end
end

local function applyRating(win)
  if P.rated then return end
  P.rated = true
  -- Glicko (como Lichess): el puntaje se mueve mucho al principio, cuando la
  -- incertidumbre (rd) es alta, y se va estabilizando con cada ejercicio.
  local q = math.log(10) / 400
  local g = 1 / math.sqrt(1 + 3 * q * q * PUZZLE_RD * PUZZLE_RD / (math.pi * math.pi))
  local e = 1 / (1 + 10 ^ (-g * (save.rating - P.rating) / 400))
  local inv = 1 / (save.rd * save.rd) + q * q * g * g * e * (1 - e)
  local d = math.floor(q / inv * g * ((win and 1 or 0) - e) + 0.5)
  if save.rating + d < 400 then d = 400 - save.rating end
  save.rating = save.rating + d
  save.rd = math.max(MIN_RD, math.floor(math.sqrt(1 / inv) + 0.5))
  if save.rating > save.peak then save.peak = save.rating end
  save.played = save.played + 1
  if win then
    save.clean = save.clean + 1
    save.streak = save.streak + 1
    if save.streak > save.best then save.best = save.streak end
  else
    save.streak = 0
  end
  P.delta = d
  markSeen(P.id)
  writeSave()
end

local function fail()
  P.failed = true
  applyRating(false)
end

local function finish()
  P.phase = "done"
  P.sel, P.targets, P.hint = nil, {}, 0
  if P.auto then
    P.msg = "That was the solution."
  elseif P.failed then
    P.msg = "Solved, but not on the first try."
  else
    P.msg = "Correct!"
  end
  if not P.auto then play(P.failed and "good" or "win") end
  applyRating(not P.failed)
end

local function animate(uci, after)
  local m = C.parseUci(uci)
  local capture = P.st.b[m.to] ~= "."
    or (P.st.b[m.from]:lower() == "p" and (m.to % 8) ~= (m.from % 8))
  play(capture and "capture" or "move")
  P.anim = { from = m.from, to = m.to, piece = P.st.b[m.from], t = 0, dur = 0.22 }
  P.st = C.make(P.st, m)
  P.last = { m.from, m.to }
  P.sel, P.targets, P.hint = nil, {}, 0
  refreshPosition()
  P.phase = "anim"
  P.after = after
end

-- juega la jugada P.moves[P.step] de forma automática (rival o solución)
local function playScripted()
  animate(P.moves[P.step], function()
    P.step = P.step + 1
    if P.step > #P.moves then
      finish()
    elseif P.auto then
      P.phase = "wait"; P.timer = 0.7
    else
      P.phase = "input"
      P.msg = "Your turn."
    end
  end)
end

local function startPuzzle(idx)
  local line = puzzles[idx]
  local id, rating, fen, moves, themes = line:match("^([^;]*);(%d+);([^;]*);([^;]*);(.*)$")
  local st = C.fromFEN(fen)
  P = {
    idx = idx, id = id, rating = tonumber(rating), themes = themes,
    moves = {}, step = 1, st = st,
    player = st.turn == "w" and "b" or "w",
    phase = "wait", timer = 0.7,
    sel = nil, targets = {}, hint = 0, msg = "Watch the opponent's move...",
    failed = false, rated = false, auto = false,
  }
  for u in moves:gmatch("%S+") do P.moves[#P.moves + 1] = u end
  P.flip = P.player == "b"
  P.cursor = C.parseUci(P.moves[1]).to
  refreshPosition()
  screen = "play"
end

local function attempt(m)
  local u = C.uci(m)
  if u == P.moves[P.step] then
    animate(u, function()
      P.step = P.step + 1
      if P.step > #P.moves then
        finish()
      else
        P.phase = "wait"; P.timer = 0.3
        play("good")
        P.msg = "Good! Keep going..."
      end
    end)
    return
  end
  -- cualquier jugada que dé mate también vale, como en Lichess
  if C.isCheckmate(C.make(P.st, m)) then
    animate(u, function() finish() end)
    return
  end
  P.bad = { from = m.from, to = m.to, t = 0.7 }
  P.sel, P.targets = nil, {}
  P.msg = "That's not it. Try again."
  play("wrong")
  fail()
end

local function selectSquare(sq)
  local t = {}
  for i = 1, #P.legal do
    if P.legal[i].from == sq then t[P.legal[i].to] = true end
  end
  if next(t) then
    P.sel, P.targets = sq, t
    return true
  end
  return false
end

local function confirmSquare()
  local cur = P.cursor
  if P.sel then
    if cur == P.sel then
      P.sel, P.targets = nil, {}
      return
    end
    local cands = {}
    for i = 1, #P.legal do
      local m = P.legal[i]
      if m.from == P.sel and m.to == cur then cands[#cands + 1] = m end
    end
    if #cands == 1 then
      attempt(cands[1])
    elseif #cands > 1 then
      P.phase = "promo"
      P.promo = { from = P.sel, to = cur, i = 1 }
    else
      local p = P.st.b[cur]
      if p ~= "." and C.colorOf(p) == P.player then selectSquare(cur) end
    end
  else
    local p = P.st.b[cur]
    if p ~= "." and C.colorOf(p) == P.player then selectSquare(cur) end
  end
end

local PROMO = { "q", "r", "b", "n" }
local PROMO_NAME = { "Queen", "Rook", "Bishop", "Knight" }

local function moveCursor(dx, dy)
  local f, r = P.cursor % 8, math.floor(P.cursor / 8)
  if P.flip then f = f - dx; r = r + dy else f = f + dx; r = r - dy end
  if f < 0 then f = 0 elseif f > 7 then f = 7 end
  if r < 0 then r = 0 elseif r > 7 then r = 7 end
  P.cursor = r * 8 + f
end

---------------------------------------------------------------------------
-- acciones por pantalla
---------------------------------------------------------------------------
local function wrap(i, n)
  if i < 1 then return n end
  if i > n then return 1 end
  return i
end

local function actionPlay(a)
  if a == "select" then screen = "menu"; return end
  if a == "r1" then startPuzzle(pickNext()); return end
  if P.phase == "done" then
    if a == "a" or a == "start" then startPuzzle(pickNext())
    elseif a == "b" then screen = "menu" end
    return
  end
  if P.phase == "promo" then
    if a == "left" or a == "up" then P.promo.i = wrap(P.promo.i - 1, 4)
    elseif a == "right" or a == "down" then P.promo.i = wrap(P.promo.i + 1, 4)
    elseif a == "b" then P.phase = "input"
    elseif a == "a" or a == "start" then
      P.phase = "input"
      attempt({ from = P.promo.from, to = P.promo.to, promo = PROMO[P.promo.i] })
    end
    return
  end
  if a == "up" then moveCursor(0, -1)
  elseif a == "down" then moveCursor(0, 1)
  elseif a == "left" then moveCursor(-1, 0)
  elseif a == "right" then moveCursor(1, 0) end
  if P.phase ~= "input" then return end
  if a == "a" then
    confirmSquare()
  elseif a == "b" then
    P.sel, P.targets = nil, {}
  elseif a == "x" then
    fail()
    if P.hint < 2 then P.hint = P.hint + 1 end
    P.msg = P.hint == 1 and "Hint: move that piece." or "Hint: that is the move."
  elseif a == "y" then
    fail()
    P.auto = true
    P.msg = "Showing the solution..."
    P.phase = "wait"; P.timer = 0.4
  end
end

local function actionMenu(a)
  if a == "up" then menuIdx = wrap(menuIdx - 1, #MENU)
  elseif a == "down" then menuIdx = wrap(menuIdx + 1, #MENU)
  elseif a == "a" or a == "start" then
    if menuIdx == 1 then
      mode = { kind = "train", title = "Training" }
      startPuzzle(pickNext())
    elseif menuIdx == 2 then screen = "levels"
    elseif menuIdx == 3 then screen = "themes"
    elseif menuIdx == 4 then screen = "stats"
    elseif menuIdx == 5 then screen = "help"
    elseif menuIdx == 6 then
      save.look = save.look % #LOOKS + 1
      applyLook(); writeSave()
    elseif menuIdx == 7 then
      save.sound = save.sound == 1 and 0 or 1
      writeSave(); play("good")
    else love.event.quit() end
  elseif menuIdx == 7 and (a == "left" or a == "right") then
    save.sound = save.sound == 1 and 0 or 1
    writeSave(); play("good")
  elseif menuIdx == 6 and (a == "left" or a == "right") then
    save.look = a == "right" and (save.look % #LOOKS + 1) or ((save.look - 2) % #LOOKS + 1)
    applyLook(); writeSave()
  end
end

local function actionLevels(a)
  if a == "up" then levelIdx = wrap(levelIdx - 1, NLEVELS)
  elseif a == "down" then levelIdx = wrap(levelIdx + 1, NLEVELS)
  elseif a == "b" or a == "select" then screen = "menu"
  elseif (a == "a" or a == "start") and levelRange[levelIdx] then
    mode = { kind = "level", level = levelIdx, title = "Level " .. levelIdx }
    P = nil
    startPuzzle(pickNext())
  end
end

local function actionThemes(a)
  if a == "up" then themeIdx = wrap(themeIdx - 1, #THEMES)
  elseif a == "down" then themeIdx = wrap(themeIdx + 1, #THEMES)
  elseif a == "b" or a == "select" then screen = "menu"
  elseif a == "a" or a == "start" then
    local t = THEMES[themeIdx]
    if #themeList(t[1]) > 0 then
      mode = { kind = "theme", key = t[1], title = t[2] }
      P = nil
      startPuzzle(pickNext())
    end
  end
end

local function onAction(a)
  if screen == "play" then actionPlay(a)
  elseif screen == "menu" then actionMenu(a)
  elseif screen == "levels" then actionLevels(a)
  elseif screen == "themes" then actionThemes(a)
  elseif screen == "help" then
    if a == "x" then
      save.swap = save.swap == 1 and 0 or 1
      writeSave()
    elseif a == "a" or a == "b" or a == "start" or a == "select" then
      screen = "menu"
    end
  else
    if a == "a" or a == "b" or a == "start" or a == "select" then screen = "menu" end
  end
end

---------------------------------------------------------------------------
-- entrada: teclado (incluye las teclas que envía gptokeyb), gamepad y joystick
---------------------------------------------------------------------------
local held = {}
local lastAny, dualInput = { src = nil, t = 0 }, false
local rep = { dir = nil, t = 0 }
local DIRS = { up = true, down = true, left = true, right = true }

local KEYS = {
  up = "up", down = "down", left = "left", right = "right",
  x = "a", space = "a",
  z = "b", backspace = "b",
  c = "x", h = "x",
  a = "y", s = "y",
  ["return"] = "start", kpenter = "start",
  escape = "select",
  rshift = "l1", pageup = "l1", q = "l1",
  lshift = "r1", pagedown = "r1", e = "r1", n = "r1",
}
local PAD = {
  dpup = "up", dpdown = "down", dpleft = "left", dpright = "right",
  a = "a", b = "b", x = "x", y = "y",
  start = "start", back = "select", guide = "select",
  leftshoulder = "l1", rightshoulder = "r1",
}
local RAWBTN = { "a", "b", "x", "y", "l1", "r1", "select", "start" }

local function press(a, src)
  if not a then return end
  if save.swap == 1 then
    if a == "a" then a = "b" elseif a == "b" then a = "a" end
  end
  local now = love.timer.getTime()
  -- En la consola una misma pulsación puede llegar dos veces: como tecla emulada
  -- (gptokeyb) y como botón real del mando. Si pasa, nos quedamos solo con el mando.
  if src ~= "stick" then
    if dualInput and src == "key" then return end
    if lastAny.src and lastAny.src ~= src and now - lastAny.t < 0.08 then
      dualInput = true
      lastAny.src, lastAny.t = "pad", now
      return
    end
    lastAny.src, lastAny.t = src, now
  end
  held[a] = true
  if DIRS[a] then rep.dir = a; rep.t = 0.32 end
  if held.start and held.select then love.event.quit(); return end
  onAction(a)
end

local function release(a)
  if not a then return end
  if save.swap == 1 then
    if a == "a" then a = "b" elseif a == "b" then a = "a" end
  end
  held[a] = false
  if rep.dir == a then rep.dir = nil end
end

function love.keypressed(key) press(KEYS[key], "key") end
function love.keyreleased(key) release(KEYS[key]) end
function love.gamepadpressed(_, button) press(PAD[button], "pad") end
function love.gamepadreleased(_, button) release(PAD[button]) end

function love.joystickpressed(j, button)
  if j:isGamepad() then return end
  press(RAWBTN[button], "pad")
end
function love.joystickreleased(j, button)
  if j:isGamepad() then return end
  release(RAWBTN[button])
end

local hatState = {}
local function setDirs(state, src, up, down, left, right)
  local want = { up = up, down = down, left = left, right = right }
  for d, on in pairs(want) do
    if on and not state[d] then state[d] = true; press(d, src)
    elseif not on and state[d] then state[d] = false; release(d) end
  end
end

function love.joystickhat(j, _, dir)
  if j:isGamepad() then return end
  setDirs(hatState, "pad", dir:find("u") ~= nil, dir:find("d") ~= nil,
    dir:find("l") ~= nil, dir:find("r") ~= nil)
end

local stickState = {}
local function pollSticks()
  local x, y = 0, 0
  local js = love.joystick.getJoysticks()
  for i = 1, #js do
    if js[i]:isGamepad() then
      local ax, ay = js[i]:getGamepadAxis("leftx"), js[i]:getGamepadAxis("lefty")
      if math.abs(ax) > math.abs(x) then x = ax end
      if math.abs(ay) > math.abs(y) then y = ay end
    end
  end
  setDirs(stickState, "stick", y < -0.6, y > 0.6, x < -0.6, x > 0.6)
end

---------------------------------------------------------------------------
-- ciclo principal
---------------------------------------------------------------------------
function love.load()
  love.keyboard.setKeyRepeat(false)
  if love.mouse then love.mouse.setVisible(false) end
  sheet = lg.newImage("pieces.png", { mipmaps = true })
  sheet:setFilter("linear", "linear")
  local order = { "k", "q", "r", "b", "n", "p" }
  for i = 1, 6 do
    quads[order[i]:upper()] = lg.newQuad((i - 1) * 2 * SQ, 0, 2 * SQ, 2 * SQ, sheet:getDimensions())
    quads[order[i]] = lg.newQuad((i - 1) * 2 * SQ, 2 * SQ, 2 * SQ, 2 * SQ, sheet:getDimensions())
  end
  loadData()
  applyLook()
  loadSounds()
  if os.getenv("AJEDREZ_TEST") then
    App = { sfx = sfx, press = press, release = release, state = function() return screen, P end }
    pcall(require, "devtest")
  end
end

function love.update(dt)
  if dt > 0.1 then dt = 0.1 end
  clock = clock + dt
  pollSticks()
  if rep.dir and held[rep.dir] then
    rep.t = rep.t - dt
    if rep.t <= 0 then
      rep.t = 0.09
      onAction(rep.dir)
    end
  end
  if screen ~= "play" or not P then return end
  if P.bad then
    P.bad.t = P.bad.t - dt
    if P.bad.t <= 0 then P.bad = nil end
  end
  if P.phase == "wait" then
    P.timer = P.timer - dt
    if P.timer <= 0 then playScripted() end
  elseif P.phase == "anim" then
    P.anim.t = P.anim.t + dt
    if P.anim.t >= P.anim.dur then
      P.anim = nil
      local after = P.after
      P.after = nil
      P.phase = "input"
      if after then after() end
    end
  end
end

---------------------------------------------------------------------------
-- dibujo
---------------------------------------------------------------------------
local function sqXY(sq)
  local f, r = sq % 8, math.floor(sq / 8)
  if P.flip then return BX + (7 - f) * SQ, BY + r * SQ end
  return BX + f * SQ, BY + (7 - r) * SQ
end

local function fillSq(sq, key, a)
  local x, y = sqXY(sq)
  col(key, a)
  lg.rectangle("fill", x, y, SQ, SQ)
end

local function drawBoard()
  local st = P.st
  for sq = 0, 63 do
    local f, r = sq % 8, math.floor(sq / 8)
    local x, y = sqXY(sq)
    local dark = (f + r) % 2 == 0
    col(dark and "dark" or "light")
    lg.rectangle("fill", x, y, SQ, SQ)
  end
  if P.last then
    fillSq(P.last[1], "last", 0.55)
    fillSq(P.last[2], "last", 0.55)
  end
  if P.check then fillSq(P.check, "check", 0.60) end
  if P.hint >= 1 and P.phase == "input" then
    local m = C.parseUci(P.moves[P.step])
    fillSq(m.from, "hint", 0.60)
    if P.hint >= 2 then fillSq(m.to, "hint", 0.60) end
  end
  if P.bad then
    local a = math.min(0.7, P.bad.t)
    fillSq(P.bad.from, "check", a)
    fillSq(P.bad.to, "check", a)
  end
  if P.sel then fillSq(P.sel, "sel", 0.55) end

  -- coordenadas
  lg.setFont(fonts.tiny)
  for i = 0, 7 do
    local file = P.flip and (7 - i) or i
    local rank = P.flip and i or (7 - i)
    local darkBottom = (file + (P.flip and 7 or 0)) % 2 == 0
    if darkBottom then col("light") else col("dark") end
    lg.print(("abcdefgh"):sub(file + 1, file + 1), BX + i * SQ + SQ - 9, BY + 8 * SQ - 13)
    local leftFile = P.flip and 7 or 0
    if (leftFile + rank) % 2 == 0 then col("light") else col("dark") end
    lg.print(tostring(rank + 1), BX + 2, BY + i * SQ + 1)
  end

  -- piezas
  lg.setColor(1, 1, 1)
  for sq = 0, 63 do
    local p = st.b[sq]
    if p ~= "." and not (P.anim and P.anim.to == sq) then
      local x, y = sqXY(sq)
      lg.draw(sheet, quads[p], x, y, 0, 0.5, 0.5)
    end
  end

  -- destinos posibles
  for sq in pairs(P.targets) do
    local x, y = sqXY(sq)
    if st.b[sq] ~= "." then
      col("sel", 0.75)
      lg.setLineWidth(4)
      lg.circle("line", x + SQ / 2, y + SQ / 2, SQ / 2 - 4)
    else
      col("sel", 0.55)
      lg.circle("fill", x + SQ / 2, y + SQ / 2, 8)
    end
  end

  if P.anim then
    local t = P.anim.t / P.anim.dur
    if t > 1 then t = 1 end
    t = t * t * (3 - 2 * t)
    local x1, y1 = sqXY(P.anim.from)
    local x2, y2 = sqXY(P.anim.to)
    lg.setColor(1, 1, 1)
    lg.draw(sheet, quads[P.anim.piece], x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, 0, 0.5, 0.5)
  end

  -- cursor
  if P.phase ~= "done" then
    local x, y = sqXY(P.cursor)
    local pulse = 0.75 + 0.25 * math.sin(clock * 6)
    lg.setLineWidth(4)
    lg.setColor(0, 0, 0, 0.8)
    lg.rectangle("line", x + 2, y + 2, SQ - 4, SQ - 4)
    lg.setLineWidth(2)
    col("cursor", pulse)
    lg.rectangle("line", x + 2, y + 2, SQ - 4, SQ - 4)
  end
  lg.setLineWidth(1)

  if P.phase == "promo" then
    local w, h = 4 * SQ + 24, SQ + 54
    local x, y = BX + 4 * SQ - w / 2, BY + 4 * SQ - h / 2
    lg.setColor(0.10, 0.10, 0.10, 0.94)
    lg.rectangle("fill", x, y, w, h, 8, 8)
    col("text")
    lg.setFont(fonts.normal)
    lg.printf("Promote to: " .. PROMO_NAME[P.promo.i], x, y + 8, w, "center")
    for i = 1, 4 do
      local px = x + 12 + (i - 1) * SQ
      if i == P.promo.i then
        col("cursor", 0.45)
        lg.rectangle("fill", px, y + 36, SQ, SQ, 6, 6)
      end
      lg.setColor(1, 1, 1)
      local ch = PROMO[i]
      if P.player == "w" then ch = ch:upper() end
      lg.draw(sheet, quads[ch], px, y + 36, 0, 0.5, 0.5)
    end
  end
end

local function drawPanel()
  local y = BY
  lg.setFont(fonts.normal)
  col("accent")
  lg.printf(mode.title, PX, y, PW, "left")
  y = y + 26
  lg.setFont(fonts.small)
  col("muted")
  lg.print("Puzzle " .. P.id, PX, y)
  y = y + 18
  lg.print("Difficulty " .. P.rating, PX, y)
  y = y + 28

  if P.player == "w" then lg.setColor(0.97, 0.97, 0.93) else lg.setColor(0.08, 0.08, 0.08) end
  lg.rectangle("fill", PX, y, 20, 20, 3, 3)
  lg.setColor(0.6, 0.6, 0.6)
  lg.rectangle("line", PX, y, 20, 20, 3, 3)
  col("text")
  lg.setFont(fonts.normal)
  lg.print(P.player == "w" and "White to move" or "Black to move", PX + 28, y)
  y = y + 36

  if P.phase == "done" then
    if P.failed then col("bad") else col("good") end
  else
    col("text")
  end
  lg.printf(P.msg, PX, y, PW, "left")
  y = y + 70

  lg.setFont(fonts.small)
  col("muted")
  lg.print("Your rating", PX, y)
  y = y + 16
  lg.setFont(fonts.big)
  col("text")
  lg.print(ratingText(), PX, y)
  if P.rated and P.delta then
    local w = fonts.big:getWidth(ratingText())
    lg.setFont(fonts.normal)
    if P.delta >= 0 then col("good") else col("bad") end
    lg.print((P.delta >= 0 and "+" or "") .. P.delta, PX + w + 8, y + 5)
  end
  y = y + 32
  lg.setFont(fonts.small)
  col("muted")
  lg.print("Streak: " .. save.streak, PX, y)

  lg.setFont(fonts.small)
  col("dim")
  local help
  if P.phase == "done" then
    help = "A   next puzzle\nB   menu"
  else
    help = "A   pick / move\nB   drop\nX   hint\nY   show solution\nR1  skip\nSELECT  menu"
  end
  local _, lines = help:gsub("\n", "\n")
  lg.print(help, PX, VH - 16 - (lines + 1) * 16)
end

local function drawList(title, items, idx, rowText, footer)
  lg.setFont(fonts.big)
  col("accent")
  lg.printf(title, 0, 20, VW, "center")
  local rowH, visible = 32, 11
  local first = 1
  if #items > visible then
    first = idx - math.floor(visible / 2)
    if first < 1 then first = 1 end
    if first > #items - visible + 1 then first = #items - visible + 1 end
  end
  lg.setFont(fonts.normal)
  for k = 0, math.min(visible, #items) - 1 do
    local i = first + k
    local y = 66 + k * rowH
    if i == idx then
      col("bar", 0.85)
      lg.rectangle("fill", 90, y - 4, VW - 180, rowH - 4, 6, 6)
    end
    local left, right = rowText(i)
    col("text")
    lg.print(left, 106, y)
    if right then
      col("muted")
      lg.printf(right, 90, y, VW - 196, "right")
    end
  end
  lg.setFont(fonts.small)
  col("dim")
  lg.printf(footer, 0, VH - 30, VW, "center")
end

local function drawMenu()
  lg.setFont(fonts.title)
  col("accent")
  lg.printf("Chessing", 0, 40, VW, "center")
  lg.setFont(fonts.small)
  col("muted")
  lg.printf(thousands(#puzzles) .. " puzzles from the Lichess database", 0, 96, VW, "center")
  lg.setFont(fonts.big)
  for i = 1, #MENU do
    local y = 126 + (i - 1) * 37
    if i == menuIdx then
      col("bar", 0.85)
      lg.rectangle("fill", 170, y - 5, 300, 36, 8, 8)
    end
    col("text")
    local label = MENU[i]
    if i == 6 then label = "<  Look: " .. T.name .. "  >" end
    if i == 7 then label = "<  Sound: " .. (save.sound == 1 and "On" or "Off") .. "  >" end
    lg.printf(label, 170, y, 300, "center")
  end
  lg.setFont(fonts.small)
  col("dim")
  lg.printf("Rating " .. ratingText() .. "   ·   Seen " .. thousands(seenCount)
    .. "   ·   SELECT + START to quit", 0, VH - 30, VW, "center")
end

local function drawStats()
  lg.setFont(fonts.big)
  col("accent")
  lg.printf("Statistics", 0, 20, VW, "center")
  local pct = save.played > 0 and math.floor(100 * save.clean / save.played + 0.5) or 0
  local rows = {
    { "Current rating", ratingText() },
    { "Highest rating", tostring(save.peak) },
    { "Puzzles played", thousands(save.played) },
    { "Solved on first try", thousands(save.clean) .. "  (" .. pct .. "%)" },
    { "Current streak", tostring(save.streak) },
    { "Best streak", tostring(save.best) },
    { "Puzzles seen", thousands(seenCount) .. " of " .. thousands(#puzzles) },
  }
  lg.setFont(fonts.normal)
  for i = 1, #rows do
    local y = 80 + (i - 1) * 40
    col("muted")
    lg.print(rows[i][1], 130, y)
    col("text")
    lg.printf(rows[i][2], 130, y, VW - 260, "right")
  end
  lg.setFont(fonts.small)
  if saveStatus.ok then
    col("dim")
    lg.printf("Progress is saved in " .. saveStatus.where, 30, VH - 86, VW - 60, "center")
  else
    col("bad")
    lg.printf("Warning: progress could not be saved on this device.", 30, VH - 86, VW - 60, "center")
  end
  col("dim")
  lg.printf("B  back", 0, VH - 30, VW, "center")
end

local function drawHelp()
  lg.setFont(fonts.big)
  col("accent")
  lg.printf("Controls", 0, 20, VW, "center")
  local rows = {
    { "D-pad / stick", "move the cursor" },
    { "A", "pick a piece and move it" },
    { "B", "drop the piece / back" },
    { "X", "hint (two levels)" },
    { "Y", "show the solution" },
    { "R1", "skip to the next puzzle" },
    { "SELECT", "back to the menu" },
    { "SELECT + START", "quit the game" },
  }
  lg.setFont(fonts.normal)
  for i = 1, #rows do
    local y = 66 + (i - 1) * 30
    col("text")
    lg.print(rows[i][1], 90, y)
    col("muted")
    lg.print(rows[i][2], 270, y)
  end
  lg.setFont(fonts.small)
  col("muted")
  lg.printf("Your rating goes up only if you solve on the first try: no mistakes, hints or solution.",
    60, 318, VW - 120, "center")
  col("accent")
  lg.printf("A and B feel reversed?  Press X to swap them.  Now: "
    .. (save.swap == 1 and "swapped" or "normal"), 60, 364, VW - 120, "center")
  col("dim")
  lg.printf("A or B  back", 0, VH - 30, VW, "center")
end

-- Las fuentes se generan a la escala de la pantalla para que el texto se vea nítido.
local fontScale = 0
local function makeFonts(s)
  fontScale = s
  local sizes = { tiny = 10, small = 13, normal = 16, big = 22, title = 40 }
  for name, size in pairs(sizes) do
    local ok, f = pcall(lg.newFont, size, "normal", s)
    fonts[name] = ok and f or lg.newFont(size)
  end
end

function love.draw()
  local w, h = lg.getDimensions()
  local s = math.min(w / VW, h / VH)
  if s ~= fontScale then makeFonts(s) end
  lg.push()
  lg.translate(math.floor((w - VW * s) / 2), math.floor((h - VH * s) / 2))
  lg.scale(s, s)
  if screen == "play" and P then
    drawBoard()
    drawPanel()
  elseif screen == "menu" then
    drawMenu()
  elseif screen == "levels" then
    local items = {}
    for l = 1, NLEVELS do items[l] = l end
    drawList("Choose level", items, levelIdx, function(l)
      local rg = levelRange[l]
      local total = rg and (rg[2] - rg[1] + 1) or 0
      return "Level " .. l .. "   (" .. levelLabel(l) .. ")",
        thousands(levelSeen[l]) .. " / " .. thousands(total)
    end, "A  play      B  back      (seen / total)")
  elseif screen == "themes" then
    drawList("By theme", THEMES, themeIdx, function(i)
      local cached = themeLists[THEMES[i][1]]
      return THEMES[i][2], cached and thousands(#cached) or nil
    end, "A  play      B  back")
  elseif screen == "stats" then
    drawStats()
  elseif screen == "help" then
    drawHelp()
  end
  lg.pop()
  lg.setColor(1, 1, 1)
end
