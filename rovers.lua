-- rovers

step_rate = 30

Rover = include 'lib/rover'

rover_clock = nil

a = arc.connect()
g = grid.connect()

tau = math.pi * 2
seg_per_rad = 64 / tau
knob_max = math.pi * 3 / 4
knob_max_2x = math.pi * 3 / 2

arc_values = { {}, {}, {}, {} }
rovers = {}
held_keys = {}
for r = 1, 4 do
	rovers[r] = Rover.new()
	rovers[r].on_point_cross = function(self, v)
		crow.ii.tt.script_v(r, v * 5)
	end
	rovers[r].cut.loop_start = (r - 1) * 7 + 1
	rovers[r].cut.loop_end = (r - 1) * 7 + 1 + tau
	held_keys[r] = {
		div = false,
		drift_weight = false,
		drift_amount = false,
		input_cut = { false, false, false, false },
		input = { false, false },
		level = false,
		pan = false,
		cutoff = false,
		resonance = false
	}
end

screen_tau = 128 / tau
map_shift = false
map_cursor = 0
map_cursor_p = 1
screen_rover = 1

function has_held_key(r)
	local k = held_keys[r]
	if k.div or k.drift_weight or k.drift_amount or k.level or k.pan or k.cutoff or k.resonance then
		return true
	end
	for v = 1, 4 do
		if k.input_cut[v] then
			return true
		end
	end
	for i = 1, 2 do
		if k.input[i] then
			return true
		end
	end
	return false
end

function led_blend(a, b)
	return 1 - ((1 - a) * (1 - b))
end

function led_blend_15(a, b)
	return util.clamp(math.floor(led_blend(a, b) * 15 + 0.5), 0, 15)
end

function a_blend(r, x, value)
	x = math.floor(x + 0.5) % 64 + 1
	arc_values[r][x] = led_blend(arc_values[r][x], value)
end

function a_notch(r, angle, width, level)
	local x = (angle * seg_per_rad) % 64
	if width == 1 then
		a_blend(r, x, level)
	else
		local w = width / 2
		local xl = x - w
		local xh = x + w
		local ll = 1 - (xl + 0.5 - math.floor(xl + 0.5))
		local lh = xh + 0.5 - math.floor(xh + 0.5)
		a_blend(r, xl, ll * level)
		a_blend(r, xh, lh * level)
		for x = math.floor(xl + 1.5), math.floor(xh - 0.5) do
			a_blend(r, x, level)
		end
	end
end

function a_spiral(r, start, length, level, finish_level)
	local finish = math.floor((start + length) * seg_per_rad + 0.5)
	start = math.floor(start * seg_per_rad + 0.5)
	local increment = finish < start and -1 or 1
	for x = start, finish, increment do
		a_blend(r, x, x == finish and finish_level or level)
	end
end

function a_bipolar(r, value)
	a_spiral(r, 0, value * knob_max, 0.2, 0.7)
end

function a_unipolar(r, value)
	a_spiral(r, -knob_max, value * knob_max_2x, 0.2, 0.7)
end

function a_refresh()
	for r = 1, 4 do
		for x = 1, 64 do
			a:led(r, x, math.min(15, math.floor(arc_values[r][x] * 15 + 0.5)))
		end
	end
	a:refresh()
end

function a_all(r, value)
	for x = 1, 64 do
		arc_values[r][x] = value
	end
end

function tick()
	g:all(0)
	for r = 1, 4 do

		local held_keys = held_keys[r]
		local rover = rovers[r]
		local cut = rover.cut
		rover:step()

		crow.output[r].volts = (rover.values.d - 0.5) * 5

		if has_held_key(r) then
			a_all(r, 0)
			a_notch(r, rover.position, 1.5, 0.3)
		else
			a_all(r, rover.point_highlight.value * rover.point_highlight.value * 0.3)
			a_notch(r, rover.position, 2, 1)
			if rover.div ~= 1 then
				a_notch(r, rover.disposition, 1.5, 0.3)
			end
			a_notch(r, rover.highlight_point.i, 1.5, rover.point_highlight.value)
		end

		if held_keys.drift_amount then
			a_bipolar(r, rover.drift_amount)
		end

		if held_keys.drift_weight then
			-- a_spiral(r, -knob_max, knob_max, 0.15, 0.1) -- TODO
			a_unipolar(r, rover.drift_weight)
		end
		
		if held_keys.div then
			local div = params:get(string.format('rover_%d_div', r))
			div = math.floor(div + 0.5)
			local start = 0
			if div < 0 then
				div = -div
				start = math.pi
			end
			div = div + 1
			a_notch(r, start, 1, 1)
			for d = 1, div - 1 do
				a_notch(r, start + d * tau / div, 1, 0.5)
			end
			a_notch(r, rover.position, 2, 0.3)
		end

		for v = 1, 4 do
			if held_keys.input_cut[v] then
				if v == r then
					a_unipolar(r, cut.dub_level)
				else
					a_unipolar(r, rovers[v].cut.sends[r])
				end
			end
		end

		for i = 1, 2 do
			if held_keys.input[i] then
				a_unipolar(r, cut.inputs[i])
			end
		end

		if held_keys.level then
			a_unipolar(r, cut.level)
		end

		if held_keys.pan then
			a_bipolar(r, cut.pan)
		end
			
		if held_keys.cutoff then
			-- TODO:
		end

		if held_keys.resonance then
			-- TODO
		end
		
		local gx = (r - 1) * 4 + 1

		g:led(gx + 2, 1, held_keys.div and 10 or 2)

		local hold_level = 5 - rover.hold
		g:led(gx + 2, 2, math.floor(hold_level * rover.values.a * rover.values.a * 2 + 0.5))
		g:led(gx + 2, 3, math.floor(hold_level * rover.values.b * rover.values.b * 2 + 0.5))
		g:led(gx + 1, 3, math.floor(hold_level * rover.values.c * rover.values.c * 2 + 0.5))
		g:led(gx + 1, 2, math.floor(hold_level * rover.values.d * rover.values.d * 2 + 0.5))

		local drift_level = rover.drift.value * rover.drift_amount * 100
		g:led(gx + 2, 4, led_blend_15(math.max(0, drift_level * 0.05) ^ 2, 0.15))
		g:led(gx + 1, 4, led_blend_15(math.max(0, -drift_level * 0.05) ^ 2, 0.15))

		local cut = rover.cut
		for v = 1, 4 do
			if v == r then
				g:led(gx + v - 1, 6, math.floor(cut.dub_level ^ 2 * 4 + 0.5))
			else
				g:led(gx + v - 1, 6, math.floor(rovers[v].cut.sends[r] ^ 2 * 4 + 0.5))
			end
		end
		g:led(gx, 7, (cut.state == cut.state_PLAY or cut.state == cut.state_OVERDUB) and 6 or 2)
		g:led(gx + 1, 7, (cut.state == cut.state_RECORD or cut.state == cut.state_OVERDUB) and 6 or 2)
		for i = 1, 2 do
			g:led(gx + i + 1, 7, math.floor(cut.inputs[i] ^ 2 * 4 + 0.5))
		end
		g:led(gx, 8, math.floor(cut.level ^ 2 * 4 + 0.5))
		g:led(gx + 1, 8, math.floor(cut.pan ^ 2 * 4 + 0.5))
		-- TODO: filters
	end
	a_refresh()
	g:refresh()
	redraw()
end

arc_time = {}
for r = 1, 4 do
	arc_time[r] = util.time()
end

function a.delta(r, d)

	local rover = rovers[r]

	if not has_held_key(r) then
		-- acceleration logic ripped from norns/lua/core/encoders.lua
		-- TODO: tune acceleration response
		local now = util.time()
		local diff = now - arc_time[r]
		arc_time[r] = now
		if diff < 0.005 then
			d = d*6
		elseif diff < 0.01 then
			d = d*4
		elseif diff < 0.02 then
			d = d*3
		elseif diff < 0.03 then
			d = d*2
		end
		rover:nudge(d)
		return
	end

	local held_keys = held_keys[r]
	local cut = rover.cut
	local d_bipolar = d / 384
	local d_unipolar = d / 768

	if held_keys.drift_amount then
		rover.drift_amount = rover.drift_amount + d_bipolar
	end

	if held_keys.drift_weight then
		rover.drift_weight = util.clamp(rover.drift_weight + d_unipolar, 0, 0.99)
		rover.noise:set_weight(rover.drift_weight)
		rover.drift:set_weight(rover.drift_weight)
	end

	if held_keys.div then
		-- TODO: set quant on controlspec
		params:delta(string.format('rover_%d_div', r), d * 0.06)
	end

	for v = 1, 4 do
		if held_keys.input_cut[v] then
			if v == r then
				cut.dub_level = util.clamp(cut.dub_level + d_unipolar, 0, 1)
			else
				rovers[v].cut.sends[r] = util.clamp(rovers[v].cut.sends[r] + d_unipolar, 0, 1)
			end
		end
	end

	for i = 1, 2 do
		if held_keys.input[i] then
			cut.inputs[i] = util.clamp(cut.inputs[i] + d_unipolar, 0, 1)
		end
	end

	if held_keys.level then
		cut.level = util.clamp(cut.level + d_unipolar, 0, 1)
	end

	if held_keys.pan then
		cut.pan = util.clamp(cut.pan + d_bipolar, -1, 1)
	end

	if held_keys.cutoff then
		-- TODO
	end

	if held_keys.resonance then
		-- TODO
	end

	screen_rover = r
end

function g.key(x, y, z)
	local r = math.floor((x - 1) / 4) + 1
	local rover = rovers[r]
	local held_keys = held_keys[r]
	local x = (x - 1) % 4 + 1
	if y == 1 then
		if x == 3 then
			held_keys.div = z == 1
		end
	elseif y == 2 or y == 3 then
		if x == 2 or x == 3 then
			rover.hold = rover.hold + (z == 1 and 1 or -1)
		end
	elseif y == 4 then
		if x == 2 then
			held_keys.drift_weight = z == 1
		elseif x == 3 then
			held_keys.drift_amount = z == 1
		end
	elseif y == 6 then
		held_keys.input_cut[x] = z == 1
	elseif y == 7 then
		local cut = rover.cut
		if y == 7 then
			if x == 1 and z == 1 then
				if cut.state == cut.state_RECORD then
					cut:overdub()
				elseif cut.state == cut.state_PLAY then
					cut:mute()
				elseif cut.state == cut.state_OVERDUB then
					cut:record()
				else
					cut:play()
				end
			elseif x == 2 and z == 1 then
				if cut.state == cut.state_PLAY then
					cut:overdub()
				elseif cut.state == cut.state_RECORD then
					cut:mute()
				elseif cut.state == cut.state_OVERDUB then
					cut:play()
				else
					cut:record()
				end
			elseif x == 3 then
				held_keys.input[1] = z == 1
			elseif x == 4 then
				held_keys.input[2] = z == 1
			end
		end
	elseif y == 8 then
		if x == 1 then
			held_keys.level = z == 1
		elseif x == 2 then
			held_keys.pan = z == 1
		elseif x == 3 then
			held_keys.cutoff = z == 1
		elseif x == 4 then
			held_keys.resonance = z == 1
		end
	end
	screen_rover = r
end

function init()

	crow.clear()
	for o = 1, 4 do
		crow.output[o].slew = 1 / step_rate
	end

	rover_clock = metro.init{
		time = 1 / step_rate,
		event = tick
	}

	for r = 1, 4 do
		rovers[r].cut:init()
		rovers[r].cut:mute()
	end
	softcut.poll_start_phase()

	--[[
	params:add{
		id = 'touch_type',
		name = 'touch control',
		type = 'option',
		labels = {
			'position',
			'rate'
		},
		action = function(value)
			-- TODO!
		end
	}

	params:add{
		id = 'touch_weight',
		name = 'touch weight',
		type = 'control',
		controlspec = controlspec.new(0, 0.9999, 'lin', 0.001, 0.6),
		action = function(value)
			-- TODO
		end
	}

	params:add{
		id = 'touch_type',
		name = 'touch control',
		type = 'option',
		labels = {
			'direct',
			'rate'
		},
		action = function(value)
			-- TODO!
		end
	}
	-- TODO: in 'direct' mode, you can sync all four
	-- -- use a sync toggle, slew up/down to synced rate
	--]]

	--[[
	TODO: possible output types:
	- crow CV rate
	- crow CV pos (a, b, c, d)
	- crow CV map value (p)
	- ...additional, multi-dimensional map values?
	- TT events
	- MIDI events: notes, chords
	- crow triggers
	- softcut loops!!

	TODO: 'recorder' modes:
	- softcut, duh
	- MIDI recorder
	- CV recorder
	]]

	for r = 1, 4 do
		local rover = rovers[r]
		params:add{
			id = string.format('rover_%d_div', r),
			name = string.format('rover %d div', r),
			type = 'control',
			controlspec = controlspec.new(-12, 11, 'lin', 1, 0),
			formatter = function()
				local value = rover.div
				if value >= 1 then
					return string.format('%dx', value)
				else
					return string.format('%.2fx', value)
				end
			end,
			action = function(value)
				value = math.floor(value + 0.5)
				if value >= 0 then
					rover.div = value + 1
				else
					rover.div = -1 / (value - 1)
				end
			end
		}
	end
	params:bang()

	rover_clock:start()
end

function key(k, z)
	local rover = rovers[screen_rover]
	if k == 1 then
		map_shift = z == 1
	elseif k == 2 then
		if z == 1 then
			rover.map:delete(map_cursor)
			local _, p = rover.map:read(map_cursor)
			map_cursor_p = p
		end
	elseif k == 3 then
		if z == 1 then
			rover.map:insert(map_cursor)
			local _, p = rover.map:read(map_cursor)
			map_cursor_p = p
		end
	end
end

function enc(e, d)
	local rover = rovers[screen_rover]
	if e == 1 then
		-- TODO
	elseif e == 2 then
		if map_shift then
			local point = rover.map.points[map_cursor_p]
			rover.map:move(map_cursor_p, d * 0.03)
			map_cursor = point.i
		else
			map_cursor = (map_cursor + d * 0.03) % tau
		end
		local _, p = rover.map:read(map_cursor)
		map_cursor_p = p
	elseif e == 3 then
		local point = rover.map.points[map_cursor_p]
		map_cursor = point.i
		point.o = util.clamp(point.o + d * 0.01, -1, 1)
	end
end

function get_point_y(o)
	return 31.5 - o * 31
end

function redraw()
	local rover = rovers[screen_rover]
	local map = rover.map
	local points = map.points
	local count = map.count

	screen.clear()

	screen.aa(0)
	screen.level(1)

	-- x axis
	screen.move(0, 63.5)
	screen.line(128, 63.5)
	screen.stroke()
	screen.pixel(63, 62)
	screen.pixel(127, 62)
	screen.fill()
	
	-- y axis
	screen.move(0.5, 0)
	screen.line(0.5, 63)
	screen.stroke()
	screen.pixel(1, 0)
	screen.pixel(1, 31)
	screen.fill()

	-- cursor
	screen.move(map_cursor * screen_tau, 0)
	screen.line_rel(0, 64)
	screen.stroke()

	screen.aa(1)

	local x = rover.highlight_point.i * screen_tau
	local y = get_point_y(rover.highlight_point.o)
	local r = 5 / rover.point_highlight.value
	local l = rover.point_highlight.value ^ 3 * 15
	if l > 1 then
		screen.circle(x, y, r)
		screen.level(math.floor(l))
		screen.stroke()
	end

	for p = 0, count + 1 do
		local point = points[(p - 1) % count + 1]
		x = point.i * screen_tau
		y = get_point_y(point.o)
		if p < 1 then
			x = x - 128
		elseif p > count then
			x = x + 128
		end
		screen.line(x, y)
	end
	screen.level(2)
	screen.stroke()

	for p = 1, count do
		local point = points[p]
		x = point.i * screen_tau
		y = get_point_y(point.o)
		if p ~= map_cursor_p then
			screen.circle(x, y, 2.2)
			screen.level(0)
			screen.fill()
			screen.circle(x, y, 0.9)
			screen.level(9)
			screen.fill()
		elseif p > count then
		end
	end

	local o, p = rover.map:read(rover.position)
	x = rover.position * screen_tau
	y = get_point_y(o)
	screen.circle(x, y, 1)
	screen.level(15)
	screen.fill()

	local cursor_point = points[map_cursor_p]
	x = cursor_point.i * screen_tau
	y = get_point_y(cursor_point.o)
	screen.circle(x, y, 2.5)
	screen.level(0)
	screen.fill()
	screen.circle(x, y, 1.2)
	screen.level(15)
	screen.fill()

	screen.update()
end

function cleanup()
	if rover_clock ~= nil then
		rover_clock:stop()
	end
	softcut.poll_stop_phase()
end