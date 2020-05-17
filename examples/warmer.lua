-- Controls color temperature of Philips Hue lighting based on time of day

local start_warming = os.date("*t")
start_warming.hour = 17
start_warming.min = 0
start_warming.sec = 0

local end_warming = os.date("*t")
end_warming.hour = 19
end_warming.min = 0
end_warming.sec = 0

local start_cooling = os.date("*t")
start_cooling.hour = 6
start_cooling.min = 0
start_cooling.sec = 0

local end_cooling = os.date("*t")
end_cooling.hour = 6
end_cooling.min = 1
end_cooling.sec = 0

local warm = 454 -- hue max 454mirek = 2203K
local cool = 200 -- 5000K, hue min 153mirek = 6536K, ikea min 250mirek = 4000K

local min_step = 5 -- min change to color temperature in mirek
local min_delay = 10 -- min delay between changes in seconds

r = {}

local current = 333 -- 3000K, kludgy default after startup

local function between(x, a, b)
	return a < x and x < b or b < x and x < a
end

local function progress(from, to, transition_time)
	local difference = to - from
	current = from
	print("going from",from,"to",to,". difference is",difference, "and transition time is", transition_time)
	local steps = math.ceil(math.abs(difference) / min_step)
	if transition_time < math.abs(difference) / min_step * min_delay then
		steps = math.floor(transition_time / min_delay)
	end
	local step_value = difference / steps
	local step_delay = math.floor(transition_time / steps)
	print("with",steps,"steps of",step_value,"each and",step_delay,"in between")
	local function step()
		current = current + step_value
		for k, v in pairs(s.hue.lights) do
			if v.reachable and not between(tonumber(v.ct), current, to) then
				mq:publish("hue/set/lights/" .. k .. "/ct", tostring(math.floor(current)))
			end
		end
		if math.floor(current) == to or math.ceil(current) == to then
			timer:clear(step)
		end
	end
	timer:every(step_delay, step)
end

timer:atevery(os.time(start_warming), 60 * 60 * 24, function()
	print("starting warming")
	progress(cool, warm, os.time(end_warming) - os.time(start_warming))
end)

timer:atevery(os.time(start_cooling), 60 * 60 * 24, function()
	print("starting cooling")
	progress(warm, cool, os.time(end_cooling) - os.time(start_cooling))
end)

r["hue/status/lights/+/reachable"] = function(event, topic)
	if event == "true" then
		local light = string.gsub(topic, "hue/status/lights/([^/]+).*","%1")
		mq:publish("hue/set/lights/" .. light .. "/ct", current)
	end
end

return r
