local skynet = require "skynet"
local snax = require "snax"
local ticket = require "ticket"

local gate
local users = {}
local room = nil
local ticket_mgr = nil
local heartbeat_freq = 10 -- 100ms

local function init_room_data()
	room = {
		id = nil,
		capacity = 8,
		mapid = nil,
		fighting = false,
		winner = nil,
		rseed = os.time(),
		start_time = nil,
		mates = {},
	}
end

local function mate_count()
	local n = 0
	for _ in pairs(users) do
		n = n + 1
	end
	return n 
end

local function swat_count()
	local n = 0
	for i=1, room.capacity do
		local mate = room.mates[i]
		if mate then
			n = n + (mate.swats and #mate.swats or 1)
		end
	end
	return n 
end

local function capacity()
	return room.capacity
end

local function is_full()
	return swat_count() >= capacity()
end

local function formation_ready()
	if not is_full() then return false end
	for k, v in ipairs(room.mates) do
		if not v.swats then return false end
	end
	return true
end

local function get_mate(session)
	for i=1, room.capacity do
		local mate = room.mates[i]
		if mate and mate.session == session then
			return mate
		end
	end
end

local function get_mate_by_index(idx)
	for i=1, room.capacity do
		local mate = room.mates[i]
		if mate and mate.index == idx then
			return mate
		end
	end
end

local function find_seat()
	local max_seat = room.capacity / 2
	local team_1 = 0
	for i=1, room.capacity, 2 do
		local mate = get_mate_by_index(i)
		if mate then
			team_1 = team_1 + (mate.swats and #mate.swats or 1)
		else
			if team_1 < max_seat then
				return 2 * (team_1+1) - 1
			end
		end
	end
	local team_2 = 0
	for i=2, room.capacity, 2 do
		local mate = get_mate_by_index(i)
		if mate then
			team_2 = team_2 + (mate.swats and #mate.swats or 1)
		else
			if team_2 <  max_seat then
				return 2 * (team_2+1)
			end
		end
	end
	if team_1 <= team_2 then
		return 2 * (team_1+1) - 1
	else
		return 2 * (team_2+1)
	end
end

local function broadcast(sender, type, data)
	for k, v in pairs(users) do
		if not sender or k ~= sender then
			v.agent.req.resp(type, data)
		end
	end
end

local function heartbeat()
	local heartbeat_index = 0
	while true do
		local now = skynet.now() - room.start_time
		heartbeat_index = heartbeat_index + 1
		local data = string.pack("<II", now, heartbeat_index)
		for session in pairs(users) do
			if ticket_mgr:all_confirmed(session) then
				gate.post.repost(session, data)
			else
				-- snax.printf("%d heartbeat delayed:%d", session, now)
			end
		end

		skynet.sleep(heartbeat_freq)
	end
end

local function begin_fight()
	room.start_time = skynet.now()
	snax.printf("%s fight begin!", room.id)
	broadcast(nil, "resp_go", {start_time=room.start_time})
	skynet.fork(heartbeat)
end

local function on_close(survival)
	if not room.winner then return end

	local header = survival.agent.req.encode_type("room", room)

	local t = ticket_mgr:serialize()

	local d = os.date("*t")
	local fname = string.format("%d-%d%d%d%d%d", room.id, d.year, d.month, d.day, d.hour, d.sec)
	local f = io.open(string.format("record/%s.rcd", fname), "w")
	f:write(header.."\t"..t)
	f:close()
end

--[[
	4 bytes localtime   -- ticket server id if confirm package
	4 bytes eventtime		-- if event time is ff ff ff ff , time sync
	4 bytes session
	4 bytes package type -- 0: normal, 1: confirm, >1: ticket
	padding data
]]

function accept.update(data, ptype, session)
	data = ticket_mgr:update(data, ptype, session)

	if not data then return end

	for s,v in pairs(users) do
		gate.post.repost(s, data)
	end
end

function accept.timeout(session)
	local user = users[session]
	if user then
		user.agent.req.afk()  --TODO not real afk
		user.agent.req.resp("resp_leave", {id=session}) --tell self
	end
end

local function sort_mate(a, b)
	return a.index < b.index
end
function response.join(agent, secret, userid)
	if is_full() then
		return false	-- max number of room
	end
	agent = snax.bind(agent, "agent")
	local user = {
		agent = agent,
		key = secret,
		session = gate.req.register(skynet.self(), secret),
		tickets = {}
	}
	users[user.session] = user

	local mate = {name=userid, session=user.session, index=find_seat(), ready=false, swats=nil}
	table.insert(room.mates, mate)
	table.sort(room.mates, sort_mate)
	snax.printf("seat num:%d", mate.index)

	return user.session
end

function response.leave(session)
	local user = users[session]
	assert(user)
	users[session] = nil
	-- room.mates[session] = nil

	local index = 0
	for i=1, room.capacity do
		local mate = room.mates[i]
		if mate then
			if mate.session ~= session then
				index = index + 1
				room.mates[index] = mate
				if not room.fighting then
					mate.ready = false
				end
			end
		end
	end
	for i=index+1, room.capacity do
		room.mates[i] = nil
	end

	local obj = {id=session}
	local cnt = mate_count()
	if cnt == 1 then
		if not room.winner and room.fighting then
			obj.winner = next(users)
			room.winner = obj.winner
		end
	elseif cnt == 0 then
		obj.useless = true
		on_close(user)
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
	user.swats = swats
	broadcast(session, "resp_mate_change", {type="add", room=room})

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
	mate.client_loaded = false

	if formation_ready() then
		room.begin_loading = true
		for k, v in ipairs(room.mates) do
			if not v.ready then
				room.begin_loading = false
				break
			end
		end
	end
	if room.begin_loading then
		broadcast(nil, "resp_loading", {})
	end
end

function response.loading_done(session)
	local mate = get_mate(session)
	assert(mate)
	mate.client_loaded = true

	if formation_ready() then
		room.fighting = true
		for k, v in pairs(room.mates) do
			if not v.ready or not v.client_loaded then
				room.fighting = false
			end
		end
	end
	if room.fighting then
		begin_fight()
	end
end

function response.room_info()
	return room, formation_ready()
end

function response.capacity()
	return capacity()
end

function response.is_available()
	return not room.fighting and not is_full()
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
	ticket_mgr = ticket(users, gate)
end

function exit()
	for _,user in pairs(users) do
		gate.req.unregister(user.session)
	end
end

