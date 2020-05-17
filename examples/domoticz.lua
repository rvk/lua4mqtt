require "json"

r = {}

-- convert domoticz MQTT to MQTT smarthome style

r["domoticz/out"] = function(val)
	local t = json.decode(val)
	local o = s.logic.domoticz and s.logic.domoticz[tostring(t.idx)]
	for k, v in pairs(t) do
		local function pub(k, v, o, parents)
			local parents = {table.unpack(parents)}
			if type(v) == "table" then
				table.insert(parents, k)
				for l, w in pairs(v) do
					pub(l, w, o and o[k], parents)
				end
			elseif not o or tostring(o[k]) ~= tostring(v) then
				table.insert(parents, "")
				mq:publish("logic/status/domoticz/" .. t.idx .. "/" .. table.concat(parents, "/") .. k, v)
			end
		end
		pub(k, v, o, {})
	end
	return true
end

r["logic/set/domoticz/#"] = function(val, topic)
	local name
	local t = {}
	string.gsub(topic, "^logic/set/domoticz/([^/]+)/(.+)", function(idx, name)
		if not s.logic.domoticz then
			s.logic.domoticz = {}
		end
		if not s.logic.domoticz[idx] then
			s.logic.domoticz[idx] = {}
		end
		local o = s.logic.domoticz[idx]
		t.idx = tonumber(idx)
		t.nvalue = tonumber(o and o.nvalue)
		local svalues = {}
		while o and o["svalue" .. #svalues + 1] do
			table.insert(svalues, o["svalue" .. #svalues + 1])
		end
		if name == "nvalue" then
			t.nvalue = tonumber(val)
		elseif string.find(name, "^svalue") then
			local svalue_idx = tonumber(string.sub(name, 7))
			for i = 1, svalue_idx do
				if not svalues[i] then
					svalues[i] = "0"
				end
			end
			svalues[svalue_idx] = val
			o["svalue" .. svalue_idx] = val
		end
		t.svalue = table.concat(svalues, ";")
	end)
	mq:publish("domoticz/in", json.encode(t))
end

return r
