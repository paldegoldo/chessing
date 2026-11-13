-- Reglas de ajedrez mínimas para los ejercicios (compatible con Lua 5.1, sin JIT).
-- Casillas 0..63: a1 = 0, h1 = 7, a8 = 56, h8 = 63.
local C = {}

local floor = math.floor
local FILES = "abcdefgh"

local KNIGHT = { {1,2},{2,1},{2,-1},{1,-2},{-1,-2},{-2,-1},{-2,1},{-1,2} }
local KING   = { {1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1},{0,-1},{1,-1} }
local ROOK   = { {1,0},{0,1},{-1,0},{0,-1} }
local BISHOP = { {1,1},{-1,1},{-1,-1},{1,-1} }

function C.colorOf(p)
  if p == "." then return nil end
  if p == p:upper() then return "w" end
  return "b"
end
local colorOf = C.colorOf

function C.sqName(sq)
  local f = sq % 8
  return FILES:sub(f + 1, f + 1) .. tostring(floor(sq / 8) + 1)
end

function C.sqFromName(s)
  local f = FILES:find(s:sub(1, 1), 1, true)
  local r = tonumber(s:sub(2, 2))
  return (r - 1) * 8 + (f - 1)
end

function C.uci(m)
  return C.sqName(m.from) .. C.sqName(m.to) .. (m.promo or "")
end

function C.parseUci(s)
  local m = { from = C.sqFromName(s:sub(1, 2)), to = C.sqFromName(s:sub(3, 4)) }
  if #s >= 5 then m.promo = s:sub(5, 5) end
  return m
end

function C.fromFEN(fen)
  local parts = {}
  for w in fen:gmatch("%S+") do parts[#parts + 1] = w end
  local b = {}
  for i = 0, 63 do b[i] = "." end
  local rank, file = 7, 0
  for ch in parts[1]:gmatch(".") do
    if ch == "/" then
      rank = rank - 1; file = 0
    elseif ch:match("%d") then
      file = file + tonumber(ch)
    else
      b[rank * 8 + file] = ch
      file = file + 1
    end
  end
  local cs = parts[3] or "-"
  local st = {
    b = b,
    turn = parts[2] or "w",
    castle = {
      K = cs:find("K", 1, true) ~= nil, Q = cs:find("Q", 1, true) ~= nil,
      k = cs:find("k", 1, true) ~= nil, q = cs:find("q", 1, true) ~= nil,
    },
    ep = nil,
  }
  if parts[4] and parts[4] ~= "-" then st.ep = C.sqFromName(parts[4]) end
  return st
end

-- ¿La casilla sq está atacada por alguna pieza del color "by"?
function C.attacked(st, sq, by)
  local b = st.b
  local f, r = sq % 8, floor(sq / 8)
  local n  = by == "w" and "N" or "n"
  local k  = by == "w" and "K" or "k"
  local p  = by == "w" and "P" or "p"
  local rk = by == "w" and "R" or "r"
  local bp = by == "w" and "B" or "b"
  local q  = by == "w" and "Q" or "q"
  for i = 1, 8 do
    local d = KNIGHT[i]
    local nf, nr = f + d[1], r + d[2]
    if nf >= 0 and nf < 8 and nr >= 0 and nr < 8 and b[nr * 8 + nf] == n then return true end
    d = KING[i]
    nf, nr = f + d[1], r + d[2]
    if nf >= 0 and nf < 8 and nr >= 0 and nr < 8 and b[nr * 8 + nf] == k then return true end
  end
  -- peones: un peón blanco ataca hacia arriba, así que está una fila más abajo
  local pr = by == "w" and r - 1 or r + 1
  if pr >= 0 and pr < 8 then
    if f > 0 and b[pr * 8 + f - 1] == p then return true end
    if f < 7 and b[pr * 8 + f + 1] == p then return true end
  end
  for i = 1, 4 do
    local d = ROOK[i]
    local nf, nr = f + d[1], r + d[2]
    while nf >= 0 and nf < 8 and nr >= 0 and nr < 8 do
      local x = b[nr * 8 + nf]
      if x ~= "." then
        if x == rk or x == q then return true end
        break
      end
      nf, nr = nf + d[1], nr + d[2]
    end
    d = BISHOP[i]
    nf, nr = f + d[1], r + d[2]
    while nf >= 0 and nf < 8 and nr >= 0 and nr < 8 do
      local x = b[nr * 8 + nf]
      if x ~= "." then
        if x == bp or x == q then return true end
        break
      end
      nf, nr = nf + d[1], nr + d[2]
    end
  end
  return false
end

function C.kingSquare(st, color)
  local k = color == "w" and "K" or "k"
  for i = 0, 63 do
    if st.b[i] == k then return i end
  end
  return nil
end

function C.inCheck(st, color)
  local ks = C.kingSquare(st, color)
  if not ks then return false end
  return C.attacked(st, ks, color == "w" and "b" or "w")
end

-- Aplica una jugada y devuelve un estado nuevo (no modifica el original).
function C.make(st, m)
  local b = {}
  for i = 0, 63 do b[i] = st.b[i] end
  local piece = b[m.from]
  local color = colorOf(piece)
  local lower = piece:lower()
  local cas = { K = st.castle.K, Q = st.castle.Q, k = st.castle.k, q = st.castle.q }
  local ep = nil
  b[m.from] = "."
  if lower == "p" then
    if m.to == st.ep and (m.to % 8) ~= (m.from % 8) then
      -- captura al paso
      if color == "w" then b[m.to - 8] = "." else b[m.to + 8] = "." end
    end
    if m.to - m.from == 16 then ep = m.from + 8
    elseif m.from - m.to == 16 then ep = m.from - 8 end
  elseif lower == "k" then
    if color == "w" then cas.K = false; cas.Q = false else cas.k = false; cas.q = false end
    local df = (m.to % 8) - (m.from % 8)
    if df == 2 then
      b[m.to - 1] = b[m.to + 1]; b[m.to + 1] = "."
    elseif df == -2 then
      b[m.to + 1] = b[m.to - 2]; b[m.to - 2] = "."
    end
  end
  if m.from == 0 or m.to == 0 then cas.Q = false end
  if m.from == 7 or m.to == 7 then cas.K = false end
  if m.from == 56 or m.to == 56 then cas.q = false end
  if m.from == 63 or m.to == 63 then cas.k = false end
  if m.promo then
    b[m.to] = color == "w" and m.promo:upper() or m.promo:lower()
  else
    b[m.to] = piece
  end
  return { b = b, turn = (st.turn == "w") and "b" or "w", castle = cas, ep = ep }
end

local PROMOS = { "q", "r", "b", "n" }

local function pseudo(st)
  local b, us = st.b, st.turn
  local them = us == "w" and "b" or "w"
  local out = {}
  local function add(from, to, promo)
    out[#out + 1] = { from = from, to = to, promo = promo }
  end
  for sq = 0, 63 do
    local p = b[sq]
    if p ~= "." and colorOf(p) == us then
      local f, r = sq % 8, floor(sq / 8)
      local l = p:lower()
      if l == "p" then
        local dir = us == "w" and 1 or -1
        local startR = us == "w" and 1 or 6
        local lastR = us == "w" and 7 or 0
        local nr = r + dir
        if nr >= 0 and nr < 8 then
          local one = nr * 8 + f
          if b[one] == "." then
            if nr == lastR then
              for i = 1, 4 do add(sq, one, PROMOS[i]) end
            else
              add(sq, one)
              if r == startR and b[(r + 2 * dir) * 8 + f] == "." then
                add(sq, (r + 2 * dir) * 8 + f)
              end
            end
          end
          for df = -1, 1, 2 do
            local nf = f + df
            if nf >= 0 and nf < 8 then
              local t = nr * 8 + nf
              local x = b[t]
              if (x ~= "." and colorOf(x) == them) or (x == "." and t == st.ep) then
                if nr == lastR then
                  for i = 1, 4 do add(sq, t, PROMOS[i]) end
                else
                  add(sq, t)
                end
              end
            end
          end
        end
      elseif l == "n" or l == "k" then
        local steps = l == "n" and KNIGHT or KING
        for i = 1, 8 do
          local nf, nr = f + steps[i][1], r + steps[i][2]
          if nf >= 0 and nf < 8 and nr >= 0 and nr < 8 then
            local x = b[nr * 8 + nf]
            if x == "." or colorOf(x) == them then add(sq, nr * 8 + nf) end
          end
        end
        if l == "k" then
          local home = us == "w" and 4 or 60
          if sq == home and not C.attacked(st, sq, them) then
            local rook = us == "w" and "R" or "r"
            local ks = us == "w" and st.castle.K or st.castle.k
            local qs = us == "w" and st.castle.Q or st.castle.q
            if ks and b[home + 1] == "." and b[home + 2] == "." and b[home + 3] == rook
               and not C.attacked(st, home + 1, them) and not C.attacked(st, home + 2, them) then
              add(sq, home + 2)
            end
            if qs and b[home - 1] == "." and b[home - 2] == "." and b[home - 3] == "."
               and b[home - 4] == rook
               and not C.attacked(st, home - 1, them) and not C.attacked(st, home - 2, them) then
              add(sq, home - 2)
            end
          end
        end
      else
        local sets = {}
        if l == "r" or l == "q" then sets[#sets + 1] = ROOK end
        if l == "b" or l == "q" then sets[#sets + 1] = BISHOP end
        for s = 1, #sets do
          for i = 1, 4 do
            local d = sets[s][i]
            local nf, nr = f + d[1], r + d[2]
            while nf >= 0 and nf < 8 and nr >= 0 and nr < 8 do
              local x = b[nr * 8 + nf]
              if x == "." then
                add(sq, nr * 8 + nf)
              else
                if colorOf(x) == them then add(sq, nr * 8 + nf) end
                break
              end
              nf, nr = nf + d[1], nr + d[2]
            end
          end
        end
      end
    end
  end
  return out
end

-- Todas las jugadas legales del bando que mueve.
function C.legalMoves(st)
  local us = st.turn
  local out = {}
  local ps = pseudo(st)
  for i = 1, #ps do
    local nst = C.make(st, ps[i])
    if not C.inCheck(nst, us) then out[#out + 1] = ps[i] end
  end
  return out
end

function C.isCheckmate(st)
  if not C.inCheck(st, st.turn) then return false end
  return #C.legalMoves(st) == 0
end

-- Solo la disposición de piezas, en formato FEN (para pruebas).
function C.boardFen(st)
  local rows = {}
  for r = 7, 0, -1 do
    local s, empty = "", 0
    for f = 0, 7 do
      local p = st.b[r * 8 + f]
      if p == "." then
        empty = empty + 1
      else
        if empty > 0 then s = s .. empty; empty = 0 end
        s = s .. p
      end
    end
    if empty > 0 then s = s .. empty end
    rows[#rows + 1] = s
  end
  return table.concat(rows, "/")
end

return C
