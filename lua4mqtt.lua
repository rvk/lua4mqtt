#!/usr/bin/env lua
local mqtt = require "mosquitto"
local lfs = require "lfs"
local cqueues = require "cqueues"
local notify = require "cqueues.notify"
local os = require "os"

local cfg = {}
if io.open("lua4mqtt.config") then
	local f, err = loadfile("lua4mqtt.config", "t", cfg)
	if f then f() else error(err) end
end

local ifname = cfg.ifname or "logic"
local broker = cfg.broker or "localhost"
local topics = {ifname .. "/#", "+/connected"}
if (cfg.additional_topics) then
	for _, v in pairs(cfg.additional_topics) do
		table.insert(topics, v)
	end
end

local mq = mqtt.new(ifname, true)
local nfy = notify.opendir("rules")

local rules = {}
local timers = {}
local msgs = {}

local function err_handler(err)
	print(debug.traceback(err))
end

Timer = {}
	function Timer:new(o)
		o = o or {}
		self.__index = self
		setmetatable(o, self)
		o._timers = {}
		return o
	end
	function Timer:add(time, func, rep)
		local calltime = os.time()
		if (time < calltime) then
			if rep < 1 then
				print("time is in the past and event is not recurring. not scheduling at " .. os.date("%c", time))
				return
			end
			local diff = ((calltime - time) // rep + 1) * rep
			local newtime = time + diff
			print("time " .. os.date("%c", time) .. " is in the past, adjusting to " .. os.date("%c", time + diff))
			time = newtime
		end
		print("scheduling timer at " .. os.date("%c", time) .. " with repeat interval of " .. tostring(rep))
		if not self._timers[time] then self._timers[time] = {} end
		self._timers[time][func] = rep
	end
	function Timer:every(time, func)
		self:add(os.time() + time, func, time)
	end
	function Timer:after(time, func)
		self:add(os.time() + time, func, 0)
	end
	function Timer:at(time, func)
		self:add(time, func, 0)
	end
	function Timer:atevery(first, rep, func)
		self:add(first, func, rep)
	end
	function Timer:clear(func)
		assert(type(func) == "function", "parameter must be function")
		for _, time in pairs(self._timers) do
			if time[func] then
				print("clearing timer at " .. os.date("%c", _))
				time[func] = nil
			end
		end
	end
	function Timer:fire()
		local calltime = os.time()
		for time in pairs(self._timers) do
			if time <= calltime then
				for func, rep in pairs(self._timers[time]) do
					self:add(time + rep, func, rep)
					xpcall(func, err_handler)
				end
				self._timers[time] = nil
			end
		end
	end


local function reload(file)
	local r = {}
	print("loading " .. file)
	local timer = Timer:new()
	local env = {}
	env.m = msgs
	env.mq = mq
	env.timer = timer
	setmetatable(env, {__index = _G})
	timers[file] = timer
	local f, err = loadfile("rules/" .. file, "t", env)
	if f then
		local ok, res = xpcall(f, err_handler)
		if ok and res then
			for k, v in pairs(res) do
				r[k] = v
			end
		elseif ok then
			print(file .. " didn't return ruleset")
		end
	else
		print("error loading rule file: " .. err)
	end
	rules[file] = r
end

local function scan()
	local existing = {}
	for file in lfs.dir("rules") do
		if string.match(file, ".lua$") then
			existing[file] = true
			if not rules[file] then
				reload(file)
				nfy:add(file, notify.MODIFY)
			end
		end
	end
	for file, _ in pairs(rules) do
		if not existing[file] then
			print("unloading " .. file)
			timers[file] = nil
			rules[file] = nil
		end
	end
end

mq.ON_CONNECT = function()
        print("connected to " .. broker)
	for _, v in pairs(topics) do
		print("subscribing to " .. v)
		mq:subscribe(v)
	end
	mq:publish(ifname .. "/connected", 2, 2, true)
end

mq.ON_MESSAGE = function(mid, topic, payload)
	print("received from " .. topic, payload)
	msgs[topic] = payload
	for _, ruleset in pairs(rules) do
		for sub, func in pairs(ruleset) do
			if mqtt.topic_matches_sub(sub, topic) then
				xpcall(func, err_handler, payload, topic)
			end
		end
	end
end

scan()
mq:will_set(ifname .. "/connected", 0, 2, true)
mq:connect(broker)
local mq_fd = mq:socket()

local cq = cqueues.new()

cq:wrap(function() -- MQTT loop
	while true do
		cqueues.poll({pollfd = mq_fd, events = "r", timeout=0.1})
		mq:loop()
	end
end)

cq:wrap(function() -- rules configuration loop
	while true do
		for flags, file in nfy:changes() do
			if file == "." then
				scan()
			else
				reload(file)
			end
		end
	end
end)

cq:wrap(function() -- timer loop
	while true do
		cqueues.poll(1)
		for _, timer in pairs(timers) do
			timer:fire()
		end
	end
end)

while not cq:empty() do
	local ok, why = cq:step()

	if not ok then print("error in event loop: ", why) end
end
