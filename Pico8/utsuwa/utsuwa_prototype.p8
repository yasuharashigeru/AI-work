pico-8 cartridge // http://www.pico-8.com
version 43
__lua__

board_w = 8
board_h = 14
cell = 8
board_x = 16
board_y = 12

EMPTY = 0
WHITE_TAMA = 1
BLACK_TAMA = 2
WHITE_UTSUWA = 3
BLACK_UTSUWA = 4
WHITE_KAMI = 5
BLACK_KAMI = 6

MOVE_DAS = 14
MOVE_ARR = 6
EVENT_CAP = 9999
SCORE_CARRY = 10000

board = {}
current = nil
next_pair = nil
score_lo = 0
score_hi = 0
chain = 0
last_chain = 0
game_over = false
fall_timer = 0
move_timer = 0
prev_left = false
prev_right = false
effect_queue = {}
effect_current = nil
shake_timer = 0
pending_clear = {}
fusion_fx = {}
fusion_phase = 0
fusion_start = 0
blast_fx = {}
blast_phase = 0
blast_start = 0
resolve_co = nil
anim_frame = 0
pieces_placed = 0
rise_pending = false
rise_phase = 0
rise_start = 0
rise_row = {}

DROP_SPEED = 56
RISE_EVERY = 12
RISE_FRAMES = 16

function current_drop_speed()
  return DROP_SPEED
end

function _init()
  init_board()
  score_lo = 0
  score_hi = 0
  chain = 0
  last_chain = 0
  effect_queue = {}
  effect_current = nil
  shake_timer = 0
  pending_clear = {}
  fusion_fx = {}
  fusion_phase = 0
  blast_fx = {}
  blast_phase = 0
  resolve_co = nil
  pieces_placed = 0
  rise_pending = false
  rise_phase = 0
  rise_row = {}
  next_pair = make_pair()
  spawn_piece()
  sfx(20, 3)
end

function init_board()
  board = {}
  for y = 1, board_h do
    board[y] = {}
    for x = 1, board_w do
      board[y][x] = EMPTY
    end
  end
end

-->8
-- piece identity helpers

function piece_color(id)
  if id == WHITE_TAMA or id == WHITE_UTSUWA or id == WHITE_KAMI then
    return 1
  elseif id == BLACK_TAMA or id == BLACK_UTSUWA or id == BLACK_KAMI then
    return 2
  end
  return 0
end

function is_tama(id)
  return id == WHITE_TAMA or id == BLACK_TAMA
end

function is_utsuwa(id)
  return id == WHITE_UTSUWA or id == BLACK_UTSUWA
end

function is_kami(id)
  return id == WHITE_KAMI or id == BLACK_KAMI
end

function same_shape(a, b)
  return (is_tama(a) and is_tama(b)) or (is_utsuwa(a) and is_utsuwa(b))
end

-- experimental rule: a same-color tama+utsuwa meeting forms kami;
-- that combination is excluded from falling pairs so kami is still
-- born from pieces meeting on the board
function can_form_kami(a, b)
  if a == 0 or b == 0 then
    return false
  end
  if piece_color(a) ~= piece_color(b) then
    return false
  end
  return (is_tama(a) and is_utsuwa(b)) or (is_utsuwa(a) and is_tama(b))
end

function make_kami(a, b)
  local tama_id = a
  if not is_tama(tama_id) then
    tama_id = b
  end
  if piece_color(tama_id) == 1 then
    return WHITE_KAMI
  end
  return BLACK_KAMI
end

function valid_pair(a, b)
  if a == 0 or b == 0 then
    return false
  end
  return not can_form_kami(a, b)
end

-->8
-- falling piece

function rand_kind()
  local kinds = {WHITE_TAMA, BLACK_TAMA, WHITE_UTSUWA, BLACK_UTSUWA}
  return kinds[flr(rnd(#kinds)) + 1]
end

function make_pair()
  local a = WHITE_TAMA
  local b = WHITE_TAMA
  repeat
    a = rand_kind()
    b = rand_kind()
  until valid_pair(a, b)
  return {a, b}
end

function spawn_piece()
  local pair = next_pair
  next_pair = make_pair()
  current = {
    x = 3,
    y = 1,
    cells = {
      {x = 0, y = 0, kind = pair[1]},
      {x = 1, y = 0, kind = pair[2]}
    }
  }
  if not can_place(current) then
    game_over = true
    sfx(10)
  end
end

function can_place(piece)
  for i = 1, #piece.cells do
    local cx = piece.x + piece.cells[i].x
    local cy = piece.y + piece.cells[i].y
    if cx < 1 or cx > board_w or cy < 1 or cy > board_h then
      return false
    end
    if board[cy][cx] ~= 0 then
      return false
    end
  end
  return true
end

function move_piece(dx)
  local test = {x = current.x + dx, y = current.y, cells = current.cells}
  if can_place(test) then
    current.x += dx
    sfx(0)
  end
end

function rotate_piece_cw()
  local rotated = {}
  for i = 1, #current.cells do
    local cx = current.cells[i].x
    local cy = current.cells[i].y
    rotated[#rotated + 1] = {x = -cy, y = cx, kind = current.cells[i].kind}
  end
  try_rotate(rotated)
end

function rotate_piece_ccw()
  local rotated = {}
  for i = 1, #current.cells do
    local cx = current.cells[i].x
    local cy = current.cells[i].y
    rotated[#rotated + 1] = {x = cy, y = -cx, kind = current.cells[i].kind}
  end
  try_rotate(rotated)
end

-- puyo-style wall kick: try in place, then 1 left, then 1 right
function try_rotate(rotated)
  local kicks = {0, -1, 1}
  for i = 1, #kicks do
    local test = {x = current.x + kicks[i], y = current.y, cells = rotated}
    if can_place(test) then
      current.x += kicks[i]
      current.cells = rotated
      sfx(1)
      return true
    end
  end
  return false
end

function hard_drop()
  sfx(3)
  while can_place({x = current.x, y = current.y + 1, cells = current.cells}) do
    current.y += 1
  end
  merge_piece_to_board(current)
end

function merge_piece_to_board(piece)
  for i = 1, #piece.cells do
    local cx = piece.x + piece.cells[i].x
    local cy = piece.y + piece.cells[i].y
    if cx >= 1 and cx <= board_w and cy >= 1 and cy <= board_h then
      board[cy][cx] = piece.cells[i].kind
    end
  end

  sfx(2)
  current = nil
  pieces_placed += 1
  if pieces_placed % RISE_EVERY == 0 then
    rise_pending = true
  end
  resolve_co = cocreate(resolve_board_co)
end

-->8
-- board resolution: kami formation, matches, kami explosion, chain
-- runs as a coroutine (resolve_co, driven from _update60) so gravity
-- and each chain step are visibly spread across frames instead of
-- resolving the whole board in a single instant

function wait_frames(n)
  for i = 1, n do
    yield()
  end
end

-- one gravity tick: every floating piece drops exactly one row
function gravity_step()
  local moved = false
  for x = 1, board_w do
    for y = board_h - 1, 1, -1 do
      if board[y][x] ~= 0 and board[y + 1][x] == 0 then
        board[y + 1][x] = board[y][x]
        board[y][x] = 0
        moved = true
      end
    end
  end
  return moved
end

function animate_gravity()
  while gravity_step() do
    wait_frames(2)
  end
end

-- a falling piece fuses into the existing piece it lands on, if the
-- pair is a same-color tama+utsuwa
function find_fusions()
  local found = {}
  local used = {}
  for x = 1, board_w do
    for y = 1, board_h - 1 do
      local a = board[y][x]
      local b = board[y + 1][x]
      local ka = x .. ":" .. y
      local kb = x .. ":" .. (y + 1)
      if not used[ka] and not used[kb] and can_form_kami(a, b) then
        found[#found + 1] = {
          ax = x, ay = y, bx = x, by = y + 1,
          a = a, b = b, kami = make_kami(a, b)
        }
        used[ka] = true
        used[kb] = true
      end
    end
  end
  return found
end

function play_fusions(found)
  fusion_fx = found

  -- pause on contact so resistance reads before it is swallowed
  fusion_phase = 1
  fusion_start = anim_frame
  wait_frames(12)

  for i = 1, #fusion_fx do
    local f = fusion_fx[i]
    board[f.ay][f.ax] = 0
    board[f.by][f.bx] = f.kami
  end
  sfx(5)
  shake_timer = max(shake_timer, 3)

  -- hold the newborn kami for a beat so the result reads clearly
  fusion_phase = 2
  fusion_start = anim_frame
  wait_frames(8)
  fusion_fx = {}
  fusion_phase = 0
end

function animate_kami_settle()
  while true do
    local found = find_fusions()
    if #found == 0 then
      break
    end
    play_fusions(found)
    animate_gravity()
  end
end

-- 4-connected identical pieces of 4+ (same color and shape;
-- kami excluded), no diagonals
function find_normal_matches()
  local visited = {}
  for y = 1, board_h do
    visited[y] = {}
    for x = 1, board_w do
      visited[y][x] = false
    end
  end

  local groups = {}
  for y = 1, board_h do
    for x = 1, board_w do
      local id = board[y][x]
      if id ~= 0 and not is_kami(id) and not visited[y][x] then
        local col = piece_color(id)
        local stack = {{x, y}}
        visited[y][x] = true
        local group = {{x, y}}
        while #stack > 0 do
          local c = stack[#stack]
          stack[#stack] = nil
          local cx, cy = c[1], c[2]
          local nbs = {{cx, cy - 1}, {cx, cy + 1}, {cx - 1, cy}, {cx + 1, cy}}
          for i = 1, 4 do
            local nx, ny = nbs[i][1], nbs[i][2]
            if nx >= 1 and nx <= board_w and ny >= 1 and ny <= board_h and not visited[ny][nx] then
              local nid = board[ny][nx]
              if nid ~= 0 and not is_kami(nid) and piece_color(nid) == col and same_shape(nid, id) then
                visited[ny][nx] = true
                stack[#stack + 1] = {nx, ny}
                group[#group + 1] = {nx, ny}
              end
            end
          end
        end
        if #group >= 4 then
          groups[#groups + 1] = group
        end
      end
    end
  end
  return groups
end

function split_key(key)
  local parts = split(key, ":")
  return parts[1], parts[2]
end

-- opposite-color kami touching orthogonally ignite; each blast clears
-- only its own cell and the four orthogonal neighbours. kami caught in
-- that cross detonate too, but diagonal kami and pieces are untouched.
function resolve_kami_explosion()
  local exploded = {}
  local queue = {}

  for y = 1, board_h do
    for x = 1, board_w do
      local id = board[y][x]
      if is_kami(id) then
        local nbs = {{x, y - 1}, {x, y + 1}, {x - 1, y}, {x + 1, y}}
        for i = 1, 4 do
          local nx, ny = nbs[i][1], nbs[i][2]
          if nx >= 1 and nx <= board_w and ny >= 1 and ny <= board_h then
            local nid = board[ny][nx]
            if is_kami(nid) and piece_color(nid) ~= piece_color(id) then
              local k1 = x .. ":" .. y
              local k2 = nx .. ":" .. ny
              if not exploded[k1] then
                exploded[k1] = true
                queue[#queue + 1] = {x, y}
              end
              if not exploded[k2] then
                exploded[k2] = true
                queue[#queue + 1] = {nx, ny}
              end
            end
          end
        end
      end
    end
  end

  if #queue == 0 then
    return 0, {}, {}
  end

  local cleared = {}
  local blast_offsets = {{0, 0}, {0, -1}, {0, 1}, {-1, 0}, {1, 0}}
  local qi = 1
  while qi <= #queue do
    local ex, ey = queue[qi][1], queue[qi][2]
    qi += 1
    for i = 1, #blast_offsets do
      local bx = ex + blast_offsets[i][1]
      local by = ey + blast_offsets[i][2]
      if bx >= 1 and bx <= board_w and by >= 1 and by <= board_h then
        local id = board[by][bx]
        if id ~= 0 then
          cleared[bx .. ":" .. by] = true
          if is_kami(id) then
            local k = bx .. ":" .. by
            if not exploded[k] then
              exploded[k] = true
              queue[#queue + 1] = {bx, by}
            end
          end
        end
      end
    end
  end

  local kami_count = 0
  for _ in pairs(exploded) do
    kami_count += 1
  end

  return kami_count, cleared, exploded
end

-- chain is hard to earn, so each step is worth flatly one more than
-- the last (x1, x2, x3, ...) rather than a tapered curve
function chain_mult(n)
  if n < 1 then
    return 1
  end
  return n
end

-- pico-8 numbers are 16.16 fixed point (safe range roughly
-- -32768..32767): a plain a*b or a+b that overflows that silently
-- wraps around, which is what was turning score negative on a big
-- kami cascade. these check the limit *before* doing the op, since
-- checking after is too late -- the wraparound already happened.
function safe_mul(a, b, cap)
  if a > 0 and b > 0 and a > cap / b then
    return cap
  end
  return a * b
end

function safe_add(a, b, cap)
  if a > cap - b then
    return cap
  end
  return a + b
end

-- score is tracked as two safe-range digits (lo 0..9999, hi = number
-- of 10000s) so the displayed total can grow indefinitely without
-- ever performing an unsafe addition
function add_score(amount)
  score_lo = safe_add(score_lo, amount, SCORE_CARRY * 2)
  while score_lo >= SCORE_CARRY do
    score_lo -= SCORE_CARRY
    score_hi += 1
  end
end

function score_string()
  if score_hi <= 0 then
    return "" .. score_lo
  end
  local s = "" .. score_lo
  while #s < 4 do
    s = "0" .. s
  end
  return score_hi .. s
end

-- board logic never waits on presentation (spec #47): CHAIN/KAMI
-- events just queue up here and drain on their own pace in _update60
function push_effect(kind, n, ev_score)
  effect_queue[#effect_queue + 1] = {kind = kind, n = n, score = ev_score}
end

-- spec #40: gravity -> kami formation -> normal clear -> kami
-- explosion -> gravity, looping while any reaction keeps happening;
-- each loop that clears something is one CHAIN step. every stage is
-- separated by wait_frames() so the player can watch each step land
-- before the next one fires
function resolve_board_co()
  chain = 0
  animate_gravity()
  animate_kami_settle()
  wait_frames(8)

  while true do
    local groups = find_normal_matches()
    local kami_count, kami_cleared, kami_exploded = resolve_kami_explosion()

    if #groups == 0 and kami_count == 0 then
      break
    end

    chain += 1
    local mult = chain_mult(chain)

    -- mark what's about to clear and let it blink in place first
    pending_clear = {}
    for i = 1, #groups do
      local g = groups[i]
      for j = 1, #g do
        pending_clear[#pending_clear + 1] = {x = g[j][1], y = g[j][2]}
      end
    end
    for key, _ in pairs(kami_cleared) do
      local sx, sy = split_key(key)
      pending_clear[#pending_clear + 1] = {x = sx, y = sy}
    end
    wait_frames(16)

    -- kami gets a real impact beat: freeze on the armed board,
    -- flash from every detonating kami, and layer the explosion sound
    if kami_count > 0 then
      blast_fx = {}
      for key, _ in pairs(kami_exploded) do
        local sx, sy = split_key(key)
        blast_fx[#blast_fx + 1] = {x = sx, y = sy}
      end
      blast_phase = 1
      blast_start = anim_frame
      shake_timer = max(shake_timer, 18 + min(kami_count, 12))
      sfx(6, 0)
      wait_frames(2)
      sfx(6, 1)
      wait_frames(12)
    end

    local step_total = 0
    for i = 1, #groups do
      local g = groups[i]
      local n = #g
      local group_score = safe_mul(10 + 10 * (n - 4), mult, EVENT_CAP)
      add_score(group_score)
      step_total = safe_add(step_total, group_score, EVENT_CAP * 8)
      for j = 1, #g do
        board[g[j][2]][g[j][1]] = 0
      end
    end
    if #groups > 0 then
      sfx(4)
    end

    local kami_score = 0
    if kami_count > 0 then
      local extra = min(kami_count - 2, 18)
      local base = 50 + extra * 50
      kami_score = safe_mul(base, mult, EVENT_CAP)
      add_score(kami_score)
      for key, _ in pairs(kami_cleared) do
        local sx, sy = split_key(key)
        board[sy][sx] = 0
      end
      blast_phase = 2
      blast_start = anim_frame
    end

    pending_clear = {}

    -- CHAIN shown before KAMI within a step (spec #35). chain 1 is
    -- just an ordinary clear, not a chain yet -- only show the
    -- callout once a second reaction actually cascades (chain >= 2).
    -- this applies whether that reaction was a normal clear, a kami
    -- explosion, or both -- not just when groups happened to clear
    if chain >= 2 then
      push_effect("chain", chain, step_total)
      if chain >= 5 then
        sfx(9)
      elseif chain >= 3 then
        sfx(8)
      else
        sfx(7)
      end
    elseif step_total > 0 then
      push_effect("score", 1, step_total)
    end
    if kami_count > 0 then
      push_effect("kami", kami_count, kami_score)
    end

    if kami_count > 0 then
      wait_frames(18)
      blast_fx = {}
      blast_phase = 0
    else
      wait_frames(6)
    end
    animate_gravity()
    animate_kami_settle()
    wait_frames(10)
  end

  last_chain = chain
end

-- after every twelfth placed pair, a full random row slides in from
-- below, giving the player more room to build chains between rises.
function rise_board_co()
  for x = 1, board_w do
    if board[1][x] ~= EMPTY then
      game_over = true
      sfx(10)
      return
    end
  end

  rise_row = {}
  for x = 1, board_w do
    rise_row[x] = rand_kind()
  end
  rise_phase = 1
  rise_start = anim_frame
  wait_frames(RISE_FRAMES)

  for y = 1, board_h - 1 do
    for x = 1, board_w do
      board[y][x] = board[y + 1][x]
    end
  end
  for x = 1, board_w do
    board[board_h][x] = rise_row[x]
  end
  rise_row = {}
  rise_phase = 0
  shake_timer = max(shake_timer, 4)
  resolve_board_co()
end

function rise_draw_offset()
  if rise_phase == 0 then
    return 0
  end
  local age = min(RISE_FRAMES - 1, anim_frame - rise_start)
  return -flr(age * cell / (RISE_FRAMES - 1))
end

-->8
-- update / draw

function update_shake()
  if shake_timer > 0 then
    shake_timer -= 1
  end
end

-- CHAIN/KAMI banners drain one at a time; tempo speeds up if the
-- queue is backing up, but nothing is ever skipped (spec #38)
function update_effects()
  if effect_current then
    effect_current.timer -= 1
    effect_current.age += 1
    if effect_current.timer <= 0 then
      effect_current = nil
    end
  end
  if effect_current == nil and #effect_queue > 0 then
    effect_current = effect_queue[1]
    for i = 1, #effect_queue - 1 do
      effect_queue[i] = effect_queue[i + 1]
    end
    effect_queue[#effect_queue] = nil
    effect_current.timer = max(24, 60 - #effect_queue * 6)
    effect_current.age = 0
  end
end

function _update60()
  anim_frame += 1
  update_shake()
  update_effects()

  if resolve_co then
    if costatus(resolve_co) ~= "dead" then
      coresume(resolve_co)
    end
    if costatus(resolve_co) == "dead" then
      resolve_co = nil
      if not game_over then
        if rise_pending then
          rise_pending = false
          resolve_co = cocreate(rise_board_co)
        else
          spawn_piece()
        end
      end
    end
    return
  end

  if game_over then
    if btnp(4) or btnp(5) then
      init_board()
      score_lo = 0
      score_hi = 0
      chain = 0
      last_chain = 0
      effect_queue = {}
      effect_current = nil
      shake_timer = 0
      pending_clear = {}
      fusion_fx = {}
      fusion_phase = 0
      blast_fx = {}
      blast_phase = 0
      pieces_placed = 0
      rise_pending = false
      rise_phase = 0
      rise_row = {}
      game_over = false
      next_pair = make_pair()
      spawn_piece()
    end
    return
  end

  if current == nil then
    return
  end

  -- edge-detected on btn(), not btnp(): pico-8's btnp() auto-repeats
  -- on its own after 15 held frames, which was fighting this timer
  -- and causing an extra step on an ordinary tap
  local left = btn(0)
  local right = btn(1)

  if left and not prev_left then
    move_timer = 0
    move_piece(-1)
  elseif right and not prev_right then
    move_timer = 0
    move_piece(1)
  elseif left or right then
    move_timer += 1
    if move_timer >= MOVE_DAS then
      if left then
        move_piece(-1)
      end
      if right then
        move_piece(1)
      end
      move_timer = MOVE_DAS - MOVE_ARR
    end
  else
    move_timer = 0
  end

  prev_left = left
  prev_right = right

  local drop_speed = current_drop_speed()
  if btn(3) then
    drop_speed = 4
  end
  fall_timer += 1
  if fall_timer >= drop_speed then
    fall_timer = 0
    if not can_place({x = current.x, y = current.y + 1, cells = current.cells}) then
      merge_piece_to_board(current)
    else
      current.y += 1
    end
  end

  -- the fall timer above may have just locked the piece (current is
  -- now nil, a resolve is starting): don't let rotate/hard_drop
  -- run against it this same frame
  if current == nil then
    return
  end

  if btnp(4) then
    rotate_piece_ccw()
  end

  if btnp(5) then
    rotate_piece_cw()
  end

  if btnp(2) then
    hard_drop()
  end
end

-- hand-drawn CHAIN/KAMI wordmarks live on the sprite sheet as two
-- 32x16 blocks (see __gfx__): CHAIN at sprites 0-3/16-19 (pixel 0,0),
-- KAMI at sprites 4-7/20-23 (pixel 32,0)
CHAIN_SPR_X, CHAIN_SPR_Y = 0, 0
KAMI_SPR_X, KAMI_SPR_Y = 32, 0
BANNER_SPR_W, BANNER_SPR_H = 32, 16

-- small -> overshoot -> settle, an elastic pop instead of a static drop-in
POP_SCALE = {0.7, 0.9, 1.3}

-- big centered CHAIN/KAMI callout, drawn over the board so it reads
-- as the star of the moment rather than a corner stat
function draw_center_banner()
  if not effect_current then
    return
  end

  local sx, sy = CHAIN_SPR_X, CHAIN_SPR_Y
  local col = 10
  if effect_current.kind == "kami" then
    sx, sy = KAMI_SPR_X, KAMI_SPR_Y
    col = 8
  end

  local scale = POP_SCALE[mid(1, effect_current.age + 1, #POP_SCALE)]
  if effect_current.age >= #POP_SCALE then
    scale = 1
  end

  local cx = 64
  local cy = board_y + flr(board_h * cell / 2) - 14
  local w = BANNER_SPR_W * scale
  local h = BANNER_SPR_H * scale

  if effect_current.kind ~= "score" then
    sspr(sx, sy, BANNER_SPR_W, BANNER_SPR_H, flr(cx - w / 2), flr(cy), flr(w), flr(h))
  end

  local num_label = "x" .. effect_current.n
  local score_label = effect_current.score .. " pts"
  local nw = #num_label * 4
  local sw = #score_label * 4

  if effect_current.kind == "score" then
    print(score_label, flr(cx - sw / 2), flr(cy + 8), 7)
  else
    print(num_label, flr(cx - nw / 2), flr(cy + h + 2), col)
    if effect_current.score > 0 then
      print(score_label, flr(cx - sw / 2), flr(cy + h + 10), 7)
    end
  end
end

function draw_blasts()
  if blast_phase == 0 then
    return
  end

  local age = anim_frame - blast_start
  if blast_phase == 1 and (age < 3 or (age < 9 and age % 2 == 0)) then
    rectfill(board_x - 2, board_y - 2,
      board_x + board_w * cell + 1,
      board_y + board_h * cell + 1, 7)
  end

  for i = 1, #blast_fx do
    local b = blast_fx[i]
    local px = board_x + (b.x - 1) * cell + 3
    local py = board_y + (b.y - 1) * cell + 3
    local radius = min(12, 2 + age)
    local col = 12
    if blast_phase == 2 then
      radius = min(20, 5 + age)
    end
    circ(px, py, radius, col)
    if radius > 3 then
      circ(px, py, radius - 3, 12)
    end
  end
end

function _draw()
  cls(6)

  if shake_timer > 0 then
    camera(flr(rnd(3)) - 1, flr(rnd(3)) - 1)
  end

  rectfill(board_x - 3, board_y - 3, board_x + board_w * cell + 2, board_y + board_h * cell + 2, 6)
  rect(board_x - 2, board_y - 2, board_x + board_w * cell + 1, board_y + board_h * cell + 1, 7)

  local rise_dy = rise_draw_offset()
  clip(board_x, board_y, board_w * cell, board_h * cell)
  for y = 1, board_h do
    for x = 1, board_w do
      local kind = board[y][x]
      if kind ~= 0 and not is_fusing_cell(x, y) then
        draw_piece(board_x + (x - 1) * cell, board_y + (y - 1) * cell + rise_dy, kind)
      end
    end
  end
  if rise_phase > 0 then
    for x = 1, board_w do
      draw_piece(board_x + (x - 1) * cell, board_y + board_h * cell + rise_dy, rise_row[x])
    end
  end
  clip()

  draw_fusions()
  draw_blasts()

  if current then
    for i = 1, #current.cells do
      local cx = current.x + current.cells[i].x
      local cy = current.y + current.cells[i].y
      if cx >= 1 and cx <= board_w and cy >= 1 and cy <= board_h then
        draw_piece(board_x + (cx - 1) * cell, board_y + (cy - 1) * cell, current.cells[i].kind)
      end
    end
  end

  if anim_frame % 8 < 4 then
    for i = 1, #pending_clear do
      local p = pending_clear[i]
      rect(board_x + (p.x - 1) * cell - 1, board_y + (p.y - 1) * cell - 1, board_x + p.x * cell - 1, board_y + p.y * cell - 1, 12)
    end
  end

  draw_center_banner()

  camera(0, 0)

  print("score", 86, 4, 7)
  print(score_string(), 86, 12, 7)

  print("next", 86, 24, 7)
  if next_pair then
    draw_piece(88, 32, next_pair[1])
    draw_piece(97, 32, next_pair[2])
  end

  if game_over then
    print("game over", 88, 72, 8)
  end
end

function is_fusing_cell(x, y)
  if fusion_phase == 0 then
    return false
  end
  for i = 1, #fusion_fx do
    local f = fusion_fx[i]
    if (f.ax == x and f.ay == y) or (f.bx == x and f.by == y) then
      return true
    end
  end
  return false
end

function draw_fusions()
  if fusion_phase == 0 then
    return
  end

  local age = anim_frame - fusion_start
  for i = 1, #fusion_fx do
    local f = fusion_fx[i]
    local apx = board_x + (f.ax - 1) * cell
    local apy = board_y + (f.ay - 1) * cell
    local bpx = board_x + (f.bx - 1) * cell
    local bpy = board_y + (f.by - 1) * cell

    if fusion_phase == 1 then
      local press = min(3, flr(age / 3))
      if age < 9 and age % 4 < 2 then
        press = max(0, press - 1)
      end

      draw_piece(bpx, bpy, f.b)
      draw_piece(apx, apy + press, f.a)
      if age >= 7 then
        pset(apx + 2, bpy, 10)
        pset(apx + 5, bpy, 10)
      end
    else
      local pop = 0
      if age < 2 then
        pop = -1
      end
      draw_piece(bpx, bpy + pop, f.kami)
      circ(bpx + 3, bpy + 3, min(4, 1 + flr(age / 2)), 12)
    end
  end
end

-- hand-drawn piece art. normal pieces use one 8x8 sprite; each kami
-- loops through three frames so they can be redrawn in the editor.
PIECE_SPR = {
  [WHITE_TAMA] = 8,
  [BLACK_TAMA] = 9,
  [WHITE_UTSUWA] = 10,
  [BLACK_UTSUWA] = 11
}

KAMI_SPR = {
  [WHITE_KAMI] = {12, 13, 14, 15},
  [BLACK_KAMI] = {28, 29, 30, 31}
}
KAMI_ANIM_SPEED = 8

function draw_piece(px, py, kind)
  local idx = PIECE_SPR[kind]
  local frames = KAMI_SPR[kind]
  if frames then
    idx = frames[flr(anim_frame / KAMI_ANIM_SPEED) % 4 + 1]
  end
  if idx then
    spr(idx, px, py)
  end
end

__gfx__
00888808880880888888088808888800ccc000ccc0ccccccc0ccccccccc00ccc007777000055550077777777555555550777777000077c7000077700000c7770
00888808880880888888088808888880ccc000ccc0ccccccc0cccccccccc0ccc0777557005557750777555575557777577777c770c7777770077777007777770
88888808880880888888088808888888ccc000ccc0ccccccc0cccccccccc0ccc777777575555557577777757555555757777777777777777077c77777777777c
88800008880880888888088808888888ccc000ccc0ccc0ccc0cccccccccc0ccc777777575555557577777757555555757c777777777777770777777c77777777
88800008880880888088088808880888ccc000ccc0ccc0ccc0ccc0ccc0cc0ccc7777777755555555777777575555557577777700777c777c0777777777777777
88800008880880888088088808880888ccc000ccc0ccc0ccc0ccc0ccc0cc0ccc7777777755555555777777775555555507777000777777770007777777777770
88800008888880888088088808880888cccccc0000ccc0ccc0ccc0ccc0cc0ccc07777770055555507777777755555555007c700077777770007777770c777c70
88800008888880888088088808880888cccccc0000ccc0ccc0ccc0ccc0cc0ccc00777700005555007777777755555555007777000777000000777c7000777700
88800008888880888888088808880888cccccc0000ccc0ccc0ccc0ccc0cc0ccc000000000000000000000000000000000555555000055c5000055500000c5550
88800008888880888888088808880888cccccc0000ccccccc0ccc0ccc0cc0ccc0000000000000000000000000000000055555c550c5555550055555005555550
88800008888880888888088808880888ccc000ccc0ccccccc0ccc0ccc0cc0ccc000000000000000000000000000000005555555555555555055c55555555555c
88800008880880888888088808880888ccc000ccc0ccccccc0ccc0ccc0cc0ccc000000000000000000000000000000005c555555555555550555555c55555555
88800008880880888088088808880888ccc000ccc0ccccccc0ccc0ccc0cc0ccc0000000000000000000000000000000055555500555c555c0555555555555555
88888808880880888088088808880888ccc000ccc0ccc0ccc0ccc0ccc0cc0ccc0000000000000000000000000000000005555000555555550005555555555550
00888808880880888088088808880888ccc000ccc0ccc0ccc0ccc0ccc0cc0ccc00000000000000000000000000000000005c500055555550005555550c555c50
00888808880880888088088808880888ccc000ccc0ccc0ccc0ccc0ccc0cc0ccc00000000000000000000000000000000005555000555000000555c5000555500
__label__
66666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666
66666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666
66666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666
66666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666
66666666666666666666666666666666666666666666666666666666666666666666666666666666666666677667766776777677766666666666666666666666
66666666666666666666666666666666666666666666666666666666666666666666666666666666666666766676667676767676666666666666666666666666
66666666666666666666666666666666666666666666666666666666666666666666666666666666666666777676667676776677666666666666666666666666
66666666666666666666666666666666666666666666666666666666666666666666666666666666666666667676667676767676666666666666666666666666
66666666666666666666666666666666666666666666666666666666666666666666666666666666666666776667767766767677766666666666666666666666
66666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666
66666666666666777777777777777777777777777777777777777777777777777777777777777777776666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666777666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666767666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666767666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666767666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666777666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666776677767676777666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666767676667676676666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666767677666766676666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666767676667676676666666666666666666666666666
66666666666666766666666666666666665555666677776666666666666666666666666666666666676666767677767676676666666666666666666666666666
66666666666666766666666666666666655577566777557666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666555555757777775766666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666555555757777775766666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666555555557777777766666666666666666666666666666666676666665555555567777777766666666666666666666666
66666666666666766666666666666666555555557777777766666666666666666666666666666666676666665557777567775555766666666666666666666666
66666666666666766666666666666666655555566777777666666666666666666666666666666666676666665555557567777775766666666666666666666666
66666666666666766666666666666666665555666677776666666666666666666666666666666666676666665555557567777775766666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666665555557567777775766666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666665555555567777777766666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666665555555567777777766666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666665555555567777777766666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666766666666666666666666666666666666666666666666666666666666666666666676666666666666666666666666666666666666666666666
66666666666666777777777777777777777777777777777777777777777777777777777777777777776666666666666666666666666666666666666666666666
66666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666
66666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666666

__sfx__
0004000030d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000400002110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000600001023301000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0003000008d3205b70130000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0005000000e010e0202d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0006000011d0215831250000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0003000031a041205128e120f92500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000400002190311841250000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0003000031a041205120e121000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002000001a051286128f120fd3500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000a000010a0002070205011000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000a001f119021182518a11099102190211835189110a9102d9021182518a1109910059011182518b510ad10199021183518c1109910259031182518b510ad101990111800000000000000000000000000000000
