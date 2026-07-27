pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- breakout v1
-- note: pico-8's built-in font can't save japanese text in code comments (gets corrupted on save), so comments here are ascii-only

function _init()
	poke(0x5f2e, 1) -- enable hidden colors (128-143)
	pal(4, 135, 1)  -- color 4 displays as hidden color 135, used for stage background
	palt(0, false)  -- color 0 (black) no longer transparent
	palt(8, true)   -- color 8 (red) is transparent instead
	frame_count = 0
	game_state = "title" -- title / stage_door / play / clear_freeze / bonus / win / lose
	shake_timer = 0
	particles = {}
	-- persistent high score: cartdata is a real file on desktop pico-8,
	-- and backed by browser localstorage automatically in web exports
	cartdata("citegame_flora_breakout")
	high_score = dget(0)
	debug_menu_open = false
	debug_combo_prev = false
	stage5_entrance_offset = 0
	stage5_entrance_wait = 0
end

confetti_colors = {8, 9, 10, 11, 12, 14, 15} -- bright colors only, no black/bg/dark shades
-- lowercase: pico-8's font draws lowercase letters 5px tall vs uppercase's
-- cramped 4px, so lowercase reads much better for these pop-up banners
item_names = {[0] = "split", [1] = "speed reset", [2] = "wide", [3] = "catch"}
-- matches each item's fish sprite color (12=split/blue, 8=speed/lightblue,
-- 9=wide/purple, 10=catch/green - see item_sprites in _draw)
item_bar_colors = {[0] = 1, [1] = 12, [2] = 2, [3] = 3}

-- x = breakable brick, # = unbreakable brick, . = empty
-- difficulty comes entirely from these layouts, not from speed/paddle size
-- (smaller bricks + a 12-wide grid give more room for corridors/chambers)
stage_layouts = {
	{
		-- open-back intro: ceiling side is wide open, light breakable
		-- cluster near the paddle, no walls yet (that's stage 3's trick)
		"............",
		"............",
		"............",
		"............",
		".xxxxxxxxxx.",
		"xxxxxxxxxxxx",
		"..x.xxxx.x.."
	},
	{
		"............",
		"............",
		"xxxxxxxxxxxx",
		"xxxxxxxxxxxx",
		"............",
		"............",
		"x..x....x..x",
		"x..x....x..x",
		"x..x....x..x",
		"x..x....x..x",
		"x..x....x..x",
		"#..#....#..#"
	},
	{
		"............",
		"............",
		"............",
		"............",
		"x.x.x..x.x.x",
		".x.x.xx.x.x.",
		"xx#x#xx#x#xx",
		"............",
		"............",
		"............",
		"............",
		"#x...x#...x#"
	},
	{
		"............",
		"xx..xx..xx..",
		"xx..xx..xx..",
		"............",
		"..##..##..##",
		"..xx..xx..xx",
		"............",
		"xx..xx..xx..",
		"xx..xx..xx..",
		"............",
		"..x#..x#..x#",
		"..x#..x#..x#"
	},
	{
		"...x....x...",
		"...xxxxxx...",
		"...xxxxxx...",
		"..###xx###..",
		"...xxxxxx...",
		"..###xx###..",
		"...xxxxxx...",
		"...xxxxxx...",
		"...xxxxxx...",
		"...xxxxxx...",
		"...xxxxxx...",
		"...xxxxxx...",
		"...xxxxxx...",
		"...xxxxxx...",
		"...xxxxxx...",
		"...xxxxxx...",
		"....xxxx....",
		".....xx....."
	}
}

function start_game()
	stage = 1
	score = 0
	lives = 3
	next_1up = 1000
	oneup_timer = 0
	frame_count = 0
	paddle_big = false -- paddle-size item: 30s or until a miss, whichever's first
	game_state = "stage_door"
	door_timer = 45
end

function new_stage()
	paddle = {
		x = 0,
		y = 120,
		base_w = 24,
		h = 4,
		speed = 5
	}
	paddle.w = paddle.base_w
	paddle.x = (128 - paddle.w) / 2

	balls = {}
	local first_ball = add(balls, {
		x = 64,
		y = 100,
		hw = 4,
		hh = 8,
		speed = 1.8,
		flash = 0,
		pink = false,
		bebetori = 0
	})
	set_dir(first_ball, 1, -1)

	items = {}
	particles = {} -- clear leftover break-chunks from the previous stage's clear celebration

	catch_timer = 0
	bebetori_intro_timer = 0
	bebetori_target = nil
	oneup_timer = 0 -- don't let a 1up caught right at a stage's last brick bleed its banner into the next stage
	shake_timer = 0
	paddle_big = false -- likewise: don't carry a still-active paddle-size effect into the next stage
	paddle_big_timer = 0
	item_banner_timer = 0
	bonus_scored = false

	-- stage 5 only: 5s of nothing (ball just bounces in the empty room),
	-- then the whole brick block slides in from off-screen right over 8s
	-- to an ominous low melody. entrance_x is each brick's true resting
	-- x; b.x (the actual collision coordinate) is offset from it and
	-- eased toward 0 during the slide, so the ball can clip a brick
	-- mid-slide, before it's "arrived"
	stage5_entrance_offset = (stage == 5) and 150 or 0
	stage5_entrance_wait = (stage == 5) and 150 or 0

	bricks = {}
	local brick_w = 9
	local brick_h = 4
	local layout = stage_layouts[stage]
	for row = 1, #layout do
		local rowstr = layout[row]
		for col = 1, #rowstr do
			local ch = sub(rowstr, col, col)
			if ch != "." then
				local ex = (col - 1) * (brick_w + 1) + 4
				add(bricks, {
					x = ex + stage5_entrance_offset,
					entrance_x = ex,
					y = (row - 1) * (brick_h + 1) + 8,
					w = brick_w,
					h = brick_h,
					alive = true,
					has_item = false,
					breakable = (ch != "#")
				})
			end
		end
	end

	-- hide 3-4 items among the breakable bricks. each kind appears at most
	-- once per stage, except speed reset (1) which can show up multiple
	-- times since it's a relief valve for the ever-rising ball speed
	-- (0=split/classic 1=speed reset 2=paddle x1.5 3=catch 4=bebetori)
	local breakable_list = {}
	for b in all(bricks) do
		if b.breakable then add(breakable_list, b) end
	end
	local kinds_left = {0, 1, 2, 3, 4}
	local item_count = min(#breakable_list, 3 + flr(rnd(2)))
	for i = 1, item_count do
		local idx = flr(rnd(#breakable_list)) + 1
		local br = breakable_list[idx]
		br.has_item = true
		local kidx = flr(rnd(#kinds_left)) + 1
		local picked = kinds_left[kidx]
		br.item_kind = picked
		if picked != 1 then
			del(kinds_left, picked)
		end
		del(breakable_list, br)
	end
end

-- sets a ball's direction from a raw (dx,dy) vector, normalized to length
-- 1 so the actual on-screen speed is always exactly ball.speed, no matter
-- how steep the angle is (an un-normalized angle made sharper hits move
-- faster than straight ones, which felt like unintended extra speed)
function set_dir(ball, dx, dy)
	local mag = sqrt(dx * dx + dy * dy)
	if mag > 0 then
		ball.dx = dx / mag
		ball.dy = dy / mag
	else
		ball.dx = 0
		ball.dy = -1
	end
end

-- while split (pink flora out), paddle is 3x, taking priority over the
-- paddle-size item's 2x (they don't stack; 3x wins if both are active)
function update_paddle_width()
	local mult = 1
	local split_active = false
	for ball in all(balls) do
		if ball.pink then split_active = true end
	end
	if split_active then
		mult = 3
	elseif paddle_big then
		mult = 2
	end
	local new_w = paddle.base_w * mult
	paddle.x -= (new_w - paddle.w) / 2
	paddle.w = new_w
	paddle.x = mid(0, paddle.x, 128 - paddle.w)
end

function _update()
	frame_count += 1

	if game_state == "title" then
		if btnp(4) then
			start_game()
		end
		return
	end

	if game_state == "stage_door" then
		door_timer -= 1
		if door_timer <= 0 then
			new_stage()
			game_state = "play"
		end
		return
	end

	if game_state == "clear_freeze" then
		clear_freeze_timer -= 1

		-- let particles keep falling/fading naturally while everything
		-- else (paddle, flora, bricks) just holds still where it was the
		-- instant the last block broke
		for p in all(particles) do
			p.x += p.dx
			p.y += p.dy
			p.dy += 0.15
			p.life -= 1
			if p.life <= 0 then
				del(particles, p)
			end
		end

		if clear_freeze_timer <= 0 then
			local pink_count = 0
			for ball in all(balls) do
				if ball.pink then pink_count += 1 end
			end
			if pink_count > 0 then
				game_state = "bonus"
				bonus_timer = 150
				bonus_total = 0
				bonus_scored = false
				local spacing = 16
				local start_x = 64 - (pink_count - 1) * spacing / 2
				local i = 0
				for ball in all(balls) do
					if ball.pink then
						ball.target_x = start_x + i * spacing
						ball.target_y = 64
						i += 1
					end
				end
			elseif stage >= 5 then
				game_state = "win"
				win_timer = 0
				dance_state = "crawl_r"
				dance_x = 24
				dance_phase_timer = 0
				dance_trips = 0
				music(0)
			else
				-- the clear announcement already had its full moment
				-- during clear_freeze; go straight on to the next stage,
				-- no second "stage clear" pause
				stage += 1
				game_state = "stage_door"
				door_timer = 45
			end
		end
		return
	end

	if game_state == "bebetori_intro" then
		bebetori_intro_timer -= 1
		if bebetori_intro_timer <= 0 then
			bebetori_target.bebetori = 450
			bebetori_target = nil
			game_state = "play"
		end
		return
	end

	if game_state == "bonus" then
		bonus_timer -= 1

		-- the "stage x clear!" moment already happened during clear_freeze;
		-- this phase is just the pink flora gathering in, then the point
		-- tally landing
		for ball in all(balls) do
			if ball.pink then
				ball.x += (ball.target_x - ball.x) * 0.2
				ball.y += (ball.target_y - ball.y) * 0.2
			end
		end

		if not bonus_scored and bonus_timer <= 90 then
			-- <= instead of == so this can never be skipped by an
			-- off-by-one/desync in bonus_timer's starting value
			bonus_scored = true
			for ball in all(balls) do
				if ball.pink then bonus_total += 200 end
			end
			score += bonus_total
			sfx(7)
		end

		if bonus_timer <= 0 then
			if stage >= 5 then
				game_state = "win"
				win_timer = 0
				dance_state = "crawl_r"
				dance_x = 24
				dance_phase_timer = 0
				dance_trips = 0
				music(0)
			else
				-- straight to the next stage; no extra "stage clear"
				-- pause after the bonus tally lands
				stage += 1
				game_state = "stage_door"
				door_timer = 45
			end
		end
		return
	end

	if game_state == "win" then
		win_timer += 1

		-- victory dance: inchworm-crawl right (thrust on 32/33, anchor on
		-- 34/35, ~8fps alternation), hold on 36/37 at the edge, then mirror
		-- and crawl back left; after a couple round trips, cut the loop and
		-- settle on 36/37 dead center for the bgm's closing stinger
		if dance_state == "crawl_r" or dance_state == "crawl_l" then
			dance_phase_timer += 1
			local pose_idx = flr(dance_phase_timer / 4) % 2 -- 0=thrust 1=anchor
			local dir = (dance_state == "crawl_r") and 1 or -1
			if pose_idx == 0 then
				dance_x += dir * 2 -- 8px per 4-frame thrust
			end
			if dance_state == "crawl_r" and dance_x >= 104 then
				dance_x = 104
				dance_state = "hold_r"
				dance_phase_timer = 0
			elseif dance_state == "crawl_l" and dance_x <= 24 then
				dance_x = 24
				dance_state = "hold_l"
				dance_phase_timer = 0
			end
		elseif dance_state == "hold_r" or dance_state == "hold_l" then
			dance_phase_timer += 1
			if dance_phase_timer >= 20 then
				dance_phase_timer = 0
				if dance_state == "hold_r" then
					dance_state = "crawl_l"
				else
					dance_trips += 1
					if dance_trips >= 2 then
						dance_state = "finale"
						music(-1)
						sfx(11)
						confetti = {}
						for i = 1, 40 do
							add(confetti, {
								x = rnd(128),
								y = rnd(128) - 128,
								c = confetti_colors[flr(rnd(#confetti_colors)) + 1],
								speed = 0.5 + rnd(1),
								phase = rnd(1)
							})
						end
					else
						dance_state = "crawl_r"
					end
				end
			end
		elseif dance_state == "finale" then
			-- confetti keeps drifting down and re-spawning at the top
			-- forever, each flake swaying side to side as it falls
			for p in all(confetti) do
				p.y += p.speed
				p.x += sin(p.phase + frame_count * 0.05) * 0.6
				if p.y > 128 then
					p.y = -4 - rnd(20)
					p.x = rnd(128)
					p.c = confetti_colors[flr(rnd(#confetti_colors)) + 1]
				end
			end
		end

		if btnp(4) then
			music(-1)
			_init()
		end
		return
	end

	if game_state != "play" then
		if btnp(4) then
			_init()
		end
		return
	end

	-- debug menu: hold o+up together to open (pauses the game), same
	-- combo again to close and apply the chosen stage/lives
	local debug_combo_now = btn(4) and btn(2)
	if debug_combo_now and not debug_combo_prev then
		debug_menu_open = not debug_menu_open
		if debug_menu_open then
			debug_menu_stage = stage
			debug_menu_life = lives
			debug_menu_cursor = 1
		else
			stage = debug_menu_stage
			lives = debug_menu_life
			new_stage()
		end
	end
	debug_combo_prev = debug_combo_now

	if debug_menu_open then
		if btnp(2) then debug_menu_cursor = 1 end
		if btnp(3) then debug_menu_cursor = 2 end
		if debug_menu_cursor == 1 then
			if btnp(0) then debug_menu_stage = max(1, debug_menu_stage - 1) end
			if btnp(1) then debug_menu_stage = min(5, debug_menu_stage + 1) end
		else
			if btnp(0) then debug_menu_life = max(1, debug_menu_life - 1) end
			if btnp(1) then debug_menu_life = min(9, debug_menu_life + 1) end
		end
		return
	end

	-- paddle input
	local paddle_move = 0
	if btn(0) then
		paddle.x -= paddle.speed
		paddle_move = -1
	end
	if btn(1) then
		paddle.x += paddle.speed
		paddle_move = 1
	end
	paddle.x = mid(0, paddle.x, 128 - paddle.w)

	-- launch any balls currently stuck to the paddle (catch item):
	-- angled opposite to whichever way the paddle is moving right now
	if btnp(4) then
		for ball in all(balls) do
			if ball.stuck then
				ball.stuck = false
				set_dir(ball, -paddle_move * 0.8, -1)
			end
		end
	end

	-- true while any split (pink) flora is active; used to keep the
	-- paddle-size item from dropping during a split (it'd be pointless,
	-- split already forces the paddle to its widest 3x)
	local split_active = false
	for b2 in all(balls) do
		if b2.pink then split_active = true end
	end

	-- stage 5 entrance: 5s (150 frames) of nothing, then the ominous
	-- melody kicks in and the block slides to rest over 8s (240 frames)
	if stage5_entrance_wait > 0 then
		stage5_entrance_wait -= 1
		if stage5_entrance_wait <= 0 then
			music(1)
		end
	elseif stage5_entrance_offset > 0 then
		stage5_entrance_offset = max(0, stage5_entrance_offset - 150 / 240)
		for b in all(bricks) do
			b.x = b.entrance_x + stage5_entrance_offset
		end
	end

	-- balls: movement + collisions
	for ball in all(balls) do
		if ball.bebetori > 0 then
			ball.bebetori -= 1
		end

		if ball.stuck then
			-- caught by the paddle: stay at the same spot on the paddle
			-- (where it was actually caught) and follow it until launched
			ball.x = paddle.x + mid(0, ball.stick_offset, paddle.w)
			ball.y = paddle.y - ball.hh
			if ball.flash > 0 then
				ball.flash -= 1
			end
		else
			ball.x += ball.dx * ball.speed
			ball.y += ball.dy * ball.speed

			if ball.flash > 0 then
				ball.flash -= 1
			end

			-- each ball may only reverse per axis once per frame, otherwise
			-- overlapping triggers (e.g. a wall and a brick at the same time)
			-- can flip a direction twice and cancel out, leaving the ball stuck
			local dx_bounced = false
			local dy_bounced = false

			-- wall bounce (also push the ball back to the boundary and
			-- guarantee it's moving away, or it can keep re-triggering
			-- for several frames and look "stuck" vibrating at the edge)
			if ball.x - ball.hw < 0 then
				ball.x = ball.hw
				ball.dx = max(0.3, abs(ball.dx))
				dx_bounced = true
				sfx(2)
			elseif ball.x + ball.hw > 128 then
				ball.x = 128 - ball.hw
				ball.dx = -max(0.3, abs(ball.dx))
				dx_bounced = true
				sfx(2)
			end
			if ball.y - ball.hh < 0 then
				ball.y = ball.hh
				ball.dy = max(0.3, abs(ball.dy))
				dy_bounced = true
				sfx(2)
			end

			-- paddle collision
			if not dy_bounced
			and ball.dy > 0
			and ball.y + ball.hh >= paddle.y
			and ball.y + ball.hh <= paddle.y + paddle.h
			and ball.x + ball.hw >= paddle.x
			and ball.x - ball.hw <= paddle.x + paddle.w then
				if catch_timer > 0 then
					ball.stuck = true
					ball.stick_offset = ball.x - paddle.x
					ball.dx = 0
					ball.dy = 0
					dy_bounced = true
					sfx(1)
				else
					local hit_pos = (ball.x - paddle.x) / paddle.w - 0.5
					set_dir(ball, hit_pos * 2, -ball.dy)
					dy_bounced = true
					ball.speed = min(4, ball.speed + 0.05) -- arkanoid-style: speeds up on every paddle hit (halved, since brick bounces now add speed too)
					sfx(1)
				end
			end

			-- brick collision
			for b in all(bricks) do
				if b.alive
				and ball.x + ball.hw > b.x
				and ball.x - ball.hw < b.x + b.w
				and ball.y + ball.hh > b.y
				and ball.y - ball.hh < b.y + b.h then
					-- bebetori destroys and pierces straight through any
					-- brick, breakable or not; only the ball currently
					-- under the bebetori effect gets this
					local pierce = ball.bebetori > 0

					if not pierce then
						-- figure out which side got hit (smaller overlap =
						-- the side just grazed), then push the ball back
						-- outside the brick so it can't re-trigger next
						-- frame and get stuck vibrating against it
						local overlap_x = min(ball.x + ball.hw, b.x + b.w) - max(ball.x - ball.hw, b.x)
						local overlap_y = min(ball.y + ball.hh, b.y + b.h) - max(ball.y - ball.hh, b.y)
						if overlap_x < overlap_y then
							if not dx_bounced then
								if ball.x < b.x + b.w / 2 then
									ball.x -= overlap_x
									ball.dx = -abs(ball.dx)
								else
									ball.x += overlap_x
									ball.dx = abs(ball.dx)
								end
								dx_bounced = true
							end
						else
							if not dy_bounced then
								if ball.y < b.y + b.h / 2 then
									ball.y -= overlap_y
									ball.dy = -abs(ball.dy)
								else
									ball.y += overlap_y
									ball.dy = abs(ball.dy)
								end
								dy_bounced = true
							end
						end
						if not b.breakable then
							sfx(9)
						end
						ball.speed = min(4, ball.speed + 0.02) -- arkanoid-style: brick bounces speed up too, but more gently than the paddle
					end

					if b.breakable or pierce then
						b.alive = false
						score += 10
						if pierce and not b.breakable then
							sfx(12) -- bebetori punching through a normally-indestructible block: a punchier crunch
						else
							sfx(0)
						end
						while score >= next_1up do
							lives += 1
							next_1up += 1000
							oneup_timer = 60
							sfx(6)
						end
						-- item drop rules: speed-reset (1) only worth it once
						-- speed has actually built up (80% of the 4.0 max);
						-- paddle-size (2) is pointless during a split (paddle
						-- is already forced to its widest 3x); and never let
						-- two of the same kind be on screen/falling at once
						if b.has_item then
							local kind = b.item_kind
							local drop_ok = true
							if kind == 1 and ball.speed < 3.2 then drop_ok = false end
							if kind == 2 and split_active then drop_ok = false end
							for it in all(items) do
								if it.kind == kind then drop_ok = false end
							end
							if drop_ok then
								add(items, {x = b.x + b.w / 2, y = b.y + b.h / 2, kind = kind})
							end
						end

						-- juice: brief screen shake + a burst of brick-colored
						-- chunks scattering from where it broke
						shake_timer = 7
						for i = 1, 6 do
							add(particles, {
								x = b.x + b.w / 2,
								y = b.y + b.h / 2,
								dx = (rnd(2) - 1) * 1.5,
								dy = (rnd(2) - 1) * 1.5 - 0.5,
								life = 15 + flr(rnd(10)),
								c = (rnd(1) < 0.25) and 11 or 3
							})
						end
					end
					break
				end
			end
		end
	end

	-- (shake_timer itself decays in _draw, right after it's used, so the
	-- full duration is actually visible instead of losing a frame here)

	-- brick-break particles: simple gravity-arc chunks that fade out
	for p in all(particles) do
		p.x += p.dx
		p.y += p.dy
		p.dy += 0.15
		p.life -= 1
		if p.life <= 0 then
			del(particles, p)
		end
	end

	-- items: fall and get caught by paddle
	for it in all(items) do
		it.y += 1.2

		if it.y + 4 >= paddle.y
		and it.y - 4 <= paddle.y + paddle.h
		and it.x + 4 >= paddle.x
		and it.x - 4 <= paddle.x + paddle.w then
			-- pop-up name banner for every kind except bebetori, which
			-- already gets its own full-screen announcement
			if it.kind != 4 then
				item_banner_timer = 80
				item_banner_kind = it.kind
			end

			if it.kind == 1 then
				-- speed reset
				for ball in all(balls) do
					ball.speed = 1.8
				end
				sfx(5)
			elseif it.kind == 2 then
				-- paddle x2, for 30s or until the next miss, whichever's first
				paddle_big = true
				paddle_big_timer = 900
				sfx(5)
			elseif it.kind == 3 then
				-- catch + launch for 15s
				catch_timer = 450
				sfx(5)
			elseif it.kind == 4 then
				-- bebetori: only affects the main (non-pink) ball, even if
				-- split; a big paused announcement plays first, then it
				-- pierces blocks for 15s
				for ball in all(balls) do
					if not ball.pink then
						bebetori_target = ball
					end
				end
				bebetori_intro_timer = 45
				game_state = "bebetori_intro"
				sfx(8)
			else
				-- classic: adds 2 pink flora at an angle; the original ball
				-- keeps going straight and stays its normal color. if it
				-- was mid-catch (stuck to the paddle, speed zeroed out),
				-- carry that over too, or it'd end up neither stuck nor
				-- moving - frozen in place with no way to launch it
				local t = balls[1]
				balls = {}
				add(balls, {x = t.x, y = t.y, dx = t.dx, dy = t.dy, hw = 4, hh = 8, speed = t.speed, flash = 15, pink = false, bebetori = t.bebetori or 0, stuck = t.stuck, stick_offset = t.stick_offset})
				local pink_l = add(balls, {x = t.x, y = t.y, hw = 4, hh = 8, speed = t.speed, flash = 15, pink = true, bebetori = 0})
				set_dir(pink_l, -0.3, -1)
				local pink_r = add(balls, {x = t.x, y = t.y, hw = 4, hh = 8, speed = t.speed, flash = 15, pink = true, bebetori = 0})
				set_dir(pink_r, 0.3, -1)
				sfx(5)
			end
			del(items, it)
		elseif it.y > 128 then
			del(items, it)
		end
	end

	-- remove balls that fell off the bottom; losing the main (non-pink)
	-- ball is always a miss, even if pink flora are still in play
	local main_died = false
	for ball in all(balls) do
		if ball.y - ball.hh > 128 then
			if not ball.pink then
				main_died = true
			end
			del(balls, ball)
		end
	end
	if main_died then
		balls = {}
	end

	if #balls == 0 then
		lives -= 1
		paddle_big = false
		sfx(3)
		if lives <= 0 then
			music(-1)
			game_state = "lose"
			sfx(4)
		else
			local new_ball = add(balls, {
				x = 64, y = 100,
				hw = 4, hh = 8,
				speed = 1.8,
				flash = 0,
				pink = false,
				bebetori = 0
			})
			set_dir(new_ball, 1, -1)
		end
	end

	update_paddle_width()

	if score > high_score then
		high_score = score
		dset(0, high_score)
	end

	if oneup_timer > 0 then
		oneup_timer -= 1
	end
	if catch_timer > 0 then
		catch_timer -= 1
	end
	if paddle_big and paddle_big_timer > 0 then
		paddle_big_timer -= 1
		if paddle_big_timer <= 0 then
			paddle_big = false
		end
	end
	if item_banner_timer > 0 then
		item_banner_timer -= 1
	end

	-- clear check (unbreakable bricks never die, so they don't count)
	local remaining = 0
	for b in all(bricks) do
		if b.alive and b.breakable then remaining += 1 end
	end
	if remaining == 0 then
		if stage == 5 then
			music(-1) -- stop stage 5's ominous loop right as it's cleared
		end
		-- freeze the scene right where it is (paddle, flora, whatever's
		-- left of the particles) and announce the clear over the top of
		-- it; the bonus-gather / win / next-stage branch happens once
		-- clear_freeze_timer runs out, see the clear_freeze state above
		game_state = "clear_freeze"
		clear_freeze_timer = 60
		sfx(5)
	end
end

function _draw()
	camera(0, 0) -- always start unshaken; the play state re-applies shake below

	if game_state == "title" then
		cls(4)
		-- logo: sprites 22,23 + only x64-69 of 24 (6px, not the full 8),
		-- then sprite 25, all at 4x size
		sspr(48, 8, 22, 8, 4, 22, 88, 32)
		sspr(72, 8, 8, 8, 92, 22, 32, 32)
		print("start", 54, 84, 3)
		local hs_label = "high score:"
		local hs_num = ""..high_score
		local hs_x = 64 - (#hs_label + #hs_num) * 2
		print(hs_label, hs_x, 96, 3)
		local blink_col = (frame_count % 24 < 12) and 14 or 12
		print(hs_num, hs_x + #hs_label * 4, 96, blink_col)
		print("(c)2026 citegame", 32, 116, 3)
		return
	end

	if game_state == "stage_door" then
		cls(4)
		print("stage "..stage, 50, 60, 3)
		return
	end

	if game_state == "bonus" then
		cls(4)
		for ball in all(balls) do
			if ball.pink then
				for c = 0, 15 do pal(c, 14) end
				sspr(0, 0, 8, 16, ball.x - ball.hw, ball.y - ball.hh)
				for c = 0, 15 do pal(c, c) end
			end
		end
		if bonus_timer <= 90 then
			local blink_col = (frame_count % 4 < 2) and 14 or 12
			local msg = "bonus +"..bonus_total
			print(msg, 64 - #msg * 2, 80, blink_col)
		end
		return
	end

	if game_state == "win" then
		-- solid yellow, no hud/bricks/paddle clutter: just the dance,
		-- with the dance+caption as one group centered on screen
		-- (32px sprite + 8px gap + 8px text = 48px tall, so top = (128-48)/2)
		cls(4)
		local flip = (dance_state == "crawl_l" or dance_state == "hold_l")
		local sx
		if dance_state == "crawl_r" or dance_state == "crawl_l" then
			local pose_idx = flr(dance_phase_timer / 4) % 2
			sx = (pose_idx == 0) and 0 or 16
		else
			sx = 32
		end
		local draw_x = (dance_state == "finale") and 64 or dance_x
		sspr(sx, 16, 16, 16, draw_x - 16, 40, 32, 32, flip)
		print("congratulations!", 32, 80, 3)

		if dance_state == "finale" then
			-- flicker: each flake blinks on/off on its own phase, so the
			-- whole flurry twinkles instead of falling as solid dots
			for p in all(confetti) do
				if (frame_count + flr(p.phase * 20)) % 5 != 0 then
					rectfill(p.x, p.y, p.x + 1, p.y + 1, p.c)
				end
			end
		end
		return
	end

	cls(4)

	-- screen shake: a smoothly-varying (not resampled-per-frame) fractional
	-- offset. pico-8 still floors to a whole pixel at draw time, but since
	-- the underlying value glides continuously along a decaying sine, the
	-- moments it ticks between 0px and 1px follow a smooth curve instead
	-- of jumping to a fresh random spot every frame - reads as a much
	-- finer tremble than the old per-frame-random version, closer to
	-- "less than 1px" than true random jitter can ever look
	if shake_timer > 0 then
		local envelope = shake_timer / 7
		camera(sin(shake_timer * 0.3) * 0.9 * envelope, cos(shake_timer * 0.3) * 0.9 * envelope)
		shake_timer -= 1
	else
		camera(0, 0)
	end

	for b in all(bricks) do
		if b.alive then
			if b.breakable then
				sspr(40, 0, 14, 6, b.x, b.y, b.w, b.h)
			else
				rectfill(b.x, b.y, b.x + b.w - 1, b.y + b.h - 1, 6)
			end
		end
	end

	for p in all(particles) do
		pset(p.x, p.y, p.c)
	end

	sspr(16, 0, 24, 4, paddle.x, paddle.y, paddle.w, paddle.h)

	local launch_prompt_shown = false
	for ball in all(balls) do
		if ball.bebetori > 0 then
			-- bebetori: alternate sprite, blinks light blue for extra flair
			if frame_count % 4 < 2 then
				sspr(8, 0, 8, 16, ball.x - ball.hw, ball.y - 8)
			else
				for c = 0, 15 do pal(c, 12) end
				sspr(8, 0, 8, 16, ball.x - ball.hw, ball.y - 8)
				for c = 0, 15 do pal(c, c) end
			end
		else
			local tint = nil
			if ball.flash > 0 and ball.flash % 4 < 2 then
				tint = 7
			elseif ball.pink then
				tint = 14
			end
			if tint then
				for c = 0, 15 do pal(c, tint) end
				sspr(0, 0, 8, 16, ball.x - ball.hw, ball.y - ball.hh)
				for c = 0, 15 do pal(c, c) end
			else
				sspr(0, 0, 8, 16, ball.x - ball.hw, ball.y - ball.hh)
			end
		end

		if ball.stuck and not launch_prompt_shown then
			-- only one prompt even if several flora are stuck at once
			-- (e.g. split + catch together); follows this flora's x,
			-- clamped to stay fully on screen so it snaps to the other
			-- side the instant there's no longer room to stay centered
			launch_prompt_shown = true
			local msg_w = 16 * 4 -- "press o: launch!" length, kept as one unit for clamping
			local tx = mid(0, ball.x - msg_w / 2, 128 - msg_w)
			local ty = ball.y - ball.hh - 10
			-- the font's "o" glyph reads as a small square at this size,
			-- so draw a real circle in its place instead (letting it
			-- poke slightly above/below the text line is fine here)
			print("press ", tx, ty, 3)
			circ(tx + 6 * 4 + 2, ty + 2, 3, 3)
			print(": launch!", tx + 7 * 4, ty, 3)
		end
	end

	-- each item kind has its own fish sprite:
	-- 0=classic(12) 1=speed reset(8) 2=paddle size(9) 3=catch(10)
	-- 4=bebetori (blinks between 8 and 11)
	local item_sprites = {[0] = 12, [1] = 8, [2] = 9, [3] = 10}
	for it in all(items) do
		if it.kind == 4 then
			spr((frame_count % 4 < 2) and 8 or 11, it.x - 4, it.y - 4)
		else
			spr(item_sprites[it.kind], it.x - 4, it.y - 4)
		end
	end

	print("score:"..score, 2, 2, 3)
	print("stage:"..stage, 50, 2, 3)
	spr(7, 102, 2)
	print("x"..lives, 112, 2, 3)

	if oneup_timer > 0 then
		local blink_col = (frame_count % 4 < 2) and 14 or 12
		print("1up!", 56, 60, blink_col)
	end

	-- item-get banner: a horizontal bar punches in (0 -> full thickness),
	-- then the item's name quickly eases in from the left and settles
	-- dead center, holds a moment, then the bar itself shrinks away
	if item_banner_timer > 0 then
		local t = 80 - item_banner_timer
		local line_h
		if t < 6 then
			local p = t / 6
			line_h = flr((1 - (1 - p) * (1 - p)) * 9)
		elseif t < 70 then
			line_h = 9
		else
			local p = (t - 70) / 10
			line_h = flr((1 - p * p) * 9)
		end
		if line_h > 0 then
			rectfill(0, 64 - line_h / 2, 127, 64 + line_h / 2 - 1, item_bar_colors[item_banner_kind])
		end
		if t >= 3 and t < 70 then
			local msg = item_names[item_banner_kind]
			local msg_w = #msg * 4
			local target_x = 64 - msg_w / 2
			local start_x = -msg_w
			local p = min(1, max(0, (t - 3) / 10))
			local eased = 1 - (1 - p) * (1 - p) * (1 - p)
			print(msg, start_x + (target_x - start_x) * eased, 61, 7)
		end
	end

	if debug_menu_open then
		-- everything above is the frozen play scene; this is a simple
		-- paused overlay for jumping to a stage / setting lives
		rectfill(24, 40, 103, 76, 1)
		rect(24, 40, 103, 76, 7)
		print("debug menu", 44, 44, 7)
		local stage_col = (debug_menu_cursor == 1) and 14 or 7
		local life_col = (debug_menu_cursor == 2) and 14 or 7
		print("stage: "..debug_menu_stage, 32, 56, stage_col)
		print("life: "..debug_menu_life, 32, 65, life_col)
	elseif game_state == "clear_freeze" then
		-- everything above (bricks, paddle, flora, fading particles) is
		-- the real play scene, just frozen; this is only the text on top
		local msg = "stage "..stage.." clear!"
		print(msg, 64 - #msg * 2, 60, 3)
	elseif game_state == "lose" then
		print("game over", 44, 60, 3)
		-- same circle-instead-of-"o" trick as the catch launch prompt
		print("press ", 24, 70, 3)
		circ(24 + 6 * 4 + 2, 72, 3, 3)
		print(" to restart", 24 + 7 * 4, 70, 3)
	elseif game_state == "bebetori_intro" then
		-- "bebetori" logo sprites (4-7), drawn 2x size over the frozen
		-- scene, blinking cyan/pink like the bebetori ball itself
		local blink_col = (frame_count % 4 < 2) and 12 or 14
		for c = 0, 15 do pal(c, blink_col) end
		sspr(16, 8, 32, 8, 32, 56, 64, 16)
		for c = 0, 15 do pal(c, c) end

		-- kirakira sparkle: a handful of fixed points around the logo,
		-- each twinkling on its own offbeat phase in the same two colors
		local sparkle_pts = {
			{-6, -4}, {10, -6}, {24, 4}, {40, -8}, {56, 2}, {68, -4},
			{70, 10}, {54, 14}, {30, 16}, {8, 12}, {-4, 6}
		}
		for i, pt in ipairs(sparkle_pts) do
			if (frame_count + i * 3) % 10 < 3 then
				local col = ((frame_count + i) % 8 < 4) and 12 or 14
				pset(32 + pt[1], 56 + pt[2], col)
			end
		end
	end
end
__gfx__
58777785588888853333333333333333333333333333333333333300888388838888888888888888888888888888888888888888000000000000000000000000
55757575555555553333333333333333333333333333333333333300888333338888888888888888888888888888888888888888000000000000000000000000
000000055555555533333333333333333333333333333333333333008883333388ccc888882228888833388888eee88888111888000000000000000000000000
00050005565556553333333333333333333333333333333333333300888333338ccccc8c82222282833333838eeeee8e81111181000000000000000000000000
7777777755656555000000000000000000000000333333333333330088833333c0cdcdcc202d2d22303d3d33e0ededee101d1d11000000000000000000000000
77777777565556550000000000000000000000003333333333333300888888888cdcdc8c82d2d28283d3d3838edede8e81d1d181000000000000000000000000
777777775555555500000000000000000000000000000000000000008888888888ccc888882228888833388888eee88888111888000000000000000000000000
66767676555555550000000000000000000000000000000000000000888888888888888888888888888888888888888888888888000000000000000000000000
666767665555555588888c8c88888c8c8cc88888cc88cc8883333333833333338888888883333338000000000000000000000000000000000000000000000000
555555555555555588888c8c88888c8c8cc88888cc88cc8883333333833333338888888883333338000000000000000000000000000000000000000000000000
555555555555555588ccc88888ccc8888ccc8888cc88cc8888883333833833338888888888888888000000000000000000000000000000000000000000000000
55555555555555558ccccc888ccccc888ccccc88cc88cc8888883333833833338888888883333338000000000000000000000000000000000000000000000000
5555555555555555ccc8ccc8ccc8ccc88cc8ccc8888cc88888883333833833338333338883333338000000000000000000000000000000000000000000000000
5555555555555555cc888ccccc888ccc8cc88cc8888cc88888833333833833338333388888833338000000000000000000000000000000000000000000000000
5555555555555555c88888ccc88888cc8cc8888888cc888888333338833333338888888888333338000000000000000000000000000000000000000000000000
85555558855555588888888888888888888888888888888888333388833333388888888888333388000000000000000000000000000000000000000000000000
88888888888888888888888888888888888888888555888800000000000000000000000000000000000000000000000000000000000000000000000000000000
88888888888888888888888888888888888888855555555800000000000000000000000000000000000000000000000000000000000000000000000000000000
88888888888888888855555888888888888888556555555800000000000000000000000000000000000000000000000000000000000000000000000000000000
88855558888888888555555558888888888888555655555800000000000000000000000000000000000000000000000000000000000000000000000000000000
88555555555888888555555555588888888885556555665800000000000000000000000000000000000000000000000000000000000000000000000000000000
88555555555558888555555555558888888855555555558800000000000000000000000000000000000000000000000000000000000000000000000000000000
88556555555555888566555555555888888855555555558800000000000000000000000000000000000000000000000000000000000000000000000000000000
88565555555555888855555555555888888555555555558800000000000000000000000000000000000000000000000000000000000000000000000000000000
88855555555555888885555555555888888555555555588800000000000000000000000000000000000000000000000000000000000000000000000000000000
88885555555555558888885555555888885555555555588800000000000000000000000000000000000000000000000000000000000000000000000000000000
88888885555555558888888555555558885555555555888800000000000000000000000000000000000000000000000000000000000000000000000000000000
88888888555555888888888555555558885555555558888800000000000000000000000000000000000000000000000000000000000000000000000000000000
88888885555558888888888855555888885555555588888800000000000000000000000000000000000000000000000000000000000000000000000000000000
88888885555588888888888885555888885555555888888800000000000000000000000000000000000000000000000000000000000000000000000000000000
88888888888888888888888885558888885555558888888800000000000000000000000000000000000000000000000000000000000000000000000000000000
88888888888888888888888888888888888555558888888800000000000000000000000000000000000000000000000000000000000000000000000000000000
__label__
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
88833333333333333333333333333333333388888333333333333333333333333333333888888888888888888888833333333333333333333333333333333888
88833333333333333333333333333333333388888333333333333333333333333333333888888888888888888888833333333333333333333333333333333888
88833333333333333333333333333333333388888333333333333333333333333333333888888888888888888888833333333333333333333333333333333888
88833333333333333333333333333333333388888333333333333333333333333333333888888888888888888888833333333333333333333333333333333888
88833333333333333333333333333333333388888333333333333333333333333333333888888888888888888888833333333333333333333333333333333888
88833333333333333333333333333333333388888333333333333333333333333333333888888888888888888888833333333333333333333333333333333888
88833333333333333333333333333333333388888333333333333333333333333333333888888888888888888888833333333333333333333333333333333888
88833333333333333333333333333333333388888333333333333333333333333333333888888888888888888888833333333333333333333333333333333888
88833333333333333333333333333333333388888333333333333333333333333333333888888888888888888888833333333333333333333333333333333888
88833333333333333333333333333333333388888333333333333333333333333333333888888888888888888888833333333333333333333333333333333888
88833333333333333333333333333333333388888333333333333333333333333333333888888888888888888888833333333333333333333333333333333888
88833333333333333333333333333333333388888333333333333333333333333333333888888888888888888888833333333333333333333333333333333888
88888888888888888888833333333333333388888333333333338888888888833333333888888888888888888888888888888888888888888888888888888888
88888888888888888888833333333333333388888333333333338888888888833333333888888888888888888888888888888888888888888888888888888888
88888888888888888888833333333333333388888333333333338888888888833333333888888888888888888888888888888888888888888888888888888888
88888888888888888888833333333333333388888333333333338888888888833333333888888888888888888888833333333333333333333333333333333888
88888888888888888888833333333333333388888333333333338888888888833333333888888888888888888888833333333333333333333333333333333888
88888888888888888888833333333333333388888333333333338888888888833333333888888888888888888888833333333333333333333333333333333888
88888888888888888888833333333333333388888333333333338888888888833333333888888888888888888888833333333333333333333333333333333888
88888888888888888888833333333333333388888333333333338888888888833333333888888888888888888888833333333333333333333333333333333888
88888888888888888888833333333333333388888333333333338888888888833333333888888888888888888888833333333333333333333333333333333888
88888888888888888888833333333333333388888333333333338888888888833333333888888888888888888888833333333333333333333333333333333888
88888888888888888888833333333333333388888333333333338888888888833333333888888888888888888888833333333333333333333333333333333888
88888888888888888888833333333333333388888333333333338888888888833333333888888888888888888888833333333333333333333333333333333888
88888888888888888888833333333333333388888333333333338888888888833333333888888888888888888888888888888888888888888883333333333888
88888888888888888888833333333333333388888333333333338888888888833333333888888888888888888888888888888888888888888883333333333888
88888888888888888888833333333333333388888333333333338888888888833333333888333333333333333333388888888888888888888883333333333888
88888888888888888888833333333333333388888333333333338888888888833333333888333333333333333333388888888888888888888883333333333888
88888888888888888888833333333333333388888333333333338888888888833333333888333333333333333333388888888888888888888883333333333888
88888888888888888888833333333333333388888333333333338888888888833333333888333333333333333333388888888888888888888883333333333888
88888888888888888888833333333333333388888333333333338888888888833333333888333333333333333333388888888888888888888883333333333888
88888888888333333333333333333388888888888333333333333333333333333333333888333333333333333333388888333333333333333333333333333888
88888888888333333333333333333388888888888333333333333333333333333333333888333333333333333333388888333333333333333333333333333888
88888888888333333333333333333388888888888333333333333333333333333333333888333333333333333333388888333333333333333333333333333888
88888888888333333333333333333388888888888333333333333333333333333333333888333333333333333333388888333333333333333333333333333888
88888888888333333333333333333388888888888333333333333333333333333333333888333333333333333333388888333333333333333333333888888888
88888888888333333333333333333388888888888333333333333333333333333333333888888888888888888888888888333333333333333333333888888888
88888888888333333333333333333388888888888333333333333333333333333333333888888888888888888888888888333333333333333333333888888888
88888888888333333333333333333388888888888333333333333333333333333333333888888888888888888888888888333333333333333333333888888888
88888888888333333333333333333388888888888333333333333333333333333333333888888888888888888888888888333333333333333333333888888888
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444

__sfx__
000200002d0502b0502d050330503d050290002460023600226001f6001b6001900019000190001b0001d0002000023000260002700028000280002800028000280002600024000210001e0001a0000000000000
00010000000001905017050160501505014050140501505016050190501c0501f050220502505027050270502805028050280502805027050260502505023050210501f0501d0501b05019050160501305011050
00080000007500000000000000000000000000000000000000000000002e0002d000000002d0002d0002c0002c0002c0000000000000000000000000000000000000000000000000000000000000000000000000
0001000021350213502135021350293500f600136001160009350093500935008350083500735006000000000000014350153501435013350113501035010350180000f000000000400000000000000000000000
081000001a0500e0500e05014050140501405017050170502005021050200502105020050210502005021050050000500007000080000a0000c0000d0000f0001100013000140001600018000180000000000000
0106000024550285502b550305502b550305503455037550375503755037550375550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01080000183501c350213501d3501f35021350243501a3001c3001d3001f30021300233002430018300263002b200312003810037100351003510035100361003810029100000002c1002e100301003410000000
050a00002415018100281502b1502d150000002f15000000301500000000000000001c1561a1561c1561a15600000000000000000000000000000000000000000000000000000000000000000000000000000000
140400001905016050140501b0501e05019050190501f0501b05024050200501f0502b05023050240502c05028050260502805023050310502f050330503e050340003300036000380003a000390003500037000
310100003f0503f0503f0503f0503f0503f0503f05000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00400008180401c0401f040240401f0401c0401804013040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011000001c0601f060240602b0602b0602b0600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
310200002f0602d0602f060350603f06500000000001f650206501e6501e650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
002000080c0500a0500c0500705009050070500505003050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
03 0a404040
03 0d404040

