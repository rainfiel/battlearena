local skynet = require "skynet"
local snax = require "snax"

local gate
local users = {}
local ready_cnt = 0

local room = {
	id = nil,
	capacity = 2,
	mapid = nil,
	mates = {},
}

local function mate_count()
	local n = 0
	for _ in pairs(users) do
		n = n + 1
	end
	return n
end

local function capacity()
	return room.capacity
end

local function is_full()
	return mate_count() >= capacity()
end
--------------------------------------------------------------------

--[[
	4 bytes localtime
	4 bytes eventtime		-- if event time is ff ff ff ff , time sync
	4 bytes session
	padding data
]]

function accept.update(data)
	local time = skynet.now()
	data = string.pack("<I", time) .. data
	for s,v in pairs(users) do
		gate.post.post(s, data)
	end
end

function response.join(agent, secret)
	if is_full() then
		return false	-- max number of room
	end
	agent = snax.bind(agent, "agent")
	local user = {
		agent = agent,
		key = secret,
		session = gate.req.register(skynet.self(), secret),
	}
	users[user.session] = user
	local mate = {session=user.session, swats={}}
	table.insert(room.mates, mate)
	-- room.mates[user.session] = mate
	return user.session
end

function response.report_formation(session, swats)
	for k, v in ipairs(room.mates) do
		if v.session == session then
			print("report_formation", session, swats)
			for a,b in ipairs(swats) do
				for c,d in ipairs(b) do
					print(c..":"..d)
				end
			end
			v.swats = swats
			break
		end
	end
	-- local user = room.mates[session]
	-- user.swats = swats
	ready_cnt = ready_cnt + 1
	return room
end

function response.capacity()
	return capacity()
end

function response.is_full()
	return is_full()
end

function response.mapid()
	return room.mapid
end

function response.leave(session)
	users[session] = nil
end

function response.query(session)
	local user = users[session]
	-- todo: we can do more
	if user then
		return user.agent.handle
	end
end

function init(id, mapid, udpserver)
	room.id = id
	room.mapid = mapid
	gate = snax.bind(udpserver, "udpserver")
end

function exit()
	for _,user in pairs(users) do
		gate.req.unregister(user.session)
	end
end

