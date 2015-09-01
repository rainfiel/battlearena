local skynet = require "skynet"
local snax = require "snax"

local gate
local users = {}
local ready_count = 0
local room = nil

local reliable_udp_package = {}
local reliable_udp_index = 0

local udp_normal=0
local udp_reliable=1
local udp_confirm=2

local function init_room_data()
	room = {
		id = nil,
		capacity = 2,
		mapid = nil,
		fighting = false,
		winner = nil,
		rseed = os.time(),
		start_time = nil,
		mates = {},
	}
	ready_count = 0
end

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

local function formation_ready()
	if not is_full() then return false end
	for k, v in ipairs(room.mates) do
		if not v.swats then return false end
	end
	return true
end

local function get_mate(session)
	for k, v in ipairs(room.mates) do
		if v.session == session then
			return v
		end
	end
end

local function broadcast(sender, type, data)
	for k, v in pairs(users) do
		if k ~= sender then
			v.agent.req.resp(type, data)
		end
	end
end
--------------------------------------------------------------------

--[[
	4 bytes localtime
	4 bytes eventtime		-- if event time is ff ff ff ff , time sync
	4 bytes session
	padding data
]]

function accept.update(data, ptype, session)
	local time = skynet.now()
	if ptype == udp_reliable then
		local idx = reliable_udp_index + 1
		reliable_udp_index = idx
		data = string.pack("<I", idx)..string.sub(data, 5)
		reliable_udp_package[idx] = {data, {}}
		snax.printf("..........udp_reliable")
	elseif ptype == udp_confirm then
		local idx = string.unpack("<I", data)
		local package = reliable_udp_package[idx]
		if package then
			if not package[2][session] then
				package[2][session] = true
				table.insert(package[2], session)
			end
			snax.printf("......udp_confirm:"..session..#package[2])
			if #package[2] == capacity() then
				reliable_udp_package[idx] = nil
			end
		end
		return
	end
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
	local mate = {session=user.session, ready=false, swats=nil}
	table.insert(room.mates, mate)

	return user.session
end

function response.leave(session)
	assert(users[session])
	users[session] = nil
	-- room.mates[session] = nil
	local cnt = #room.mates
	local idx = 0
	for i=1, cnt do
		if room.mates[i].session ~= session then
			idx = idx + 1
			room.mates[idx] = room.mates[i]
		end
	end
	if idx == cnt - 1 then
		room.mates[cnt] = nil
	end

	local obj = {id=session}
	local cnt = mate_count()
	if cnt == 1 then
		if not room.winner and room.fighting then
			obj.winner = next(users)
		end
	elseif cnt == 0 then
		obj.useless = true
	end

	broadcast(session, "resp_leave", obj)
	return obj
end

function response.reach(session, obj)
	obj.id = session
	broadcast(session, "resp_reach", obj)
	return obj
end

function response.report_formation(session, swats)
	local user = get_mate(session)
	assert(not user.swats)
	user.swats = swats
	ready_count = ready_count + 1
	user.team_id = ready_count

	local ready = formation_ready()
	if ready then
		local obj = {ready=ready, room=room}
		for k, v in pairs(users) do
			if k ~= session then
				v.agent.req.resp_room_ready(obj)
			end
		end
	end
	return room, ready
end

function response.ready_to_fight(session)
	local mate = get_mate(session)
	assert(mate)
	mate.ready = true

	if formation_ready() then
		room.fighting = true
		for k, v in ipairs(room.mates) do
			if not v.ready then
				room.fighting = false
				break
			end
		end
	end
	if room.fighting then
		room.start_time = skynet.now()
		for k, v in pairs(users) do
			v.agent.req.resp_begin_fight(room.start_time)
		end
	end
end

function response.room_info()
	return room, formation_ready()
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

function response.query(session)
	local user = users[session]
	-- todo: we can do more
	if user then
		return user.agent.handle
	end
end

function init(id, mapid, udpserver)
	init_room_data()
	room.id = id
	room.mapid = mapid
	gate = snax.bind(udpserver, "udpserver")
end

function exit()
	for _,user in pairs(users) do
		gate.req.unregister(user.session)
	end
end

