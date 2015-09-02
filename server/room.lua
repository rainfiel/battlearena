local skynet = require "skynet"
local snax = require "snax"

local gate
local users = {}
local ready_count = 0
local room = nil

local reliable_udp_package = {}
local reliable_udp_index = 0
local ticket_retry_timeout = 50 -- 500 ms

local udp_normal=0
local udp_confirm=1
-- local udp_reliable=1

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
--ticket
local function add_ticket(session, index, data)
	local user = users[session]
	if not user then return end
	-- assert(not user.tickets[index])

	-- client resend ticket, resp to it only
	if user.tickets[index] then
		local ticket = user.tickets[index]
		local package = reliable_udp_package[ticket.s_index]
		package.timestamp = skynet.now() + ticket_retry_timeout
		gate.post.post(session, ticket.data)
		return
	end

	local s_index = reliable_udp_index + 1
	reliable_udp_index = s_index

	-- change localtime to package index
	data = string.pack("<I", s_index)..string.sub(data, 5)
	local timestamp = skynet.now() + ticket_retry_timeout
	reliable_udp_package[s_index] = {sender=session, c_index=index, timestamp=timestamp}

	user.tickets[index] = {data=data, confirm={}, count=0, s_index=s_index}
	snax.printf("%d send udp_reliable, s_index:%d", session, s_index)
	return data
end

local function confirm_ticket(session, s_index)
	local package = reliable_udp_package[s_index]
	if not package then return end

	local owner = users[package.sender]
	if not owner then return end

	local ticket = owner.tickets[package.c_index]
	if not ticket then return end

	local confirm = ticket.confirm
	if confirm[session] then return end

	confirm[session] = true
	ticket.count = ticket.count + 1
	snax.printf("...... %d confirm ticket %d", session, s_index)

	if ticket.count >= capacity() then
		owner.tickets[package.c_index] = nil
		reliable_udp_package[s_index] = nil
		snax.printf("ticket finished:%d", s_index)
	end
end

local function get_ticket(package)
	local owner = users[package.sender]
	if not owner then return end

	return owner.tickets[package.c_index]
end

local function update_ticket()
	local remove = {}
	while true do
		local now = skynet.now()
		for s_index, package in pairs(reliable_udp_package) do
			if package.timestamp < now then
				local ticket = get_ticket(package)
				if ticket then
					for session in pairs(users) do
						if not ticket.confirm[session] then
							snax.printf("repost ticket %d to %d", s_index, session)
							gate.post.post(session, ticket.data)
						end
					end

					package.timestamp = now + ticket_retry_timeout
				else
					table.insert(remove, s_index)
				end
			end

			local cnt = #remove
			for i=1, cnt do
				reliable_udp_package[remove[i]] = nil
				remove[i] = nil
			end
		end
		skynet.sleep(10)	-- 100 ms
	end
end
--------------------------------------------------------------------

--[[
	4 bytes localtime   -- ticket server id if confirm package
	4 bytes eventtime		-- if event time is ff ff ff ff , time sync
	4 bytes session
	4 bytes package type -- 0: normal, 1: confirm, >1: ticket
	padding data
]]

function accept.update(data, ptype, session)
	if ptype > udp_confirm then
		data = add_ticket(session, ptype, data)
	elseif ptype == udp_confirm then
		local s_index = string.unpack("<I", data)
		confirm_ticket(session, s_index)
		return
	end

	if not data then return end

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
		tickets = {}
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

	skynet.fork(update_ticket)
end

function exit()
	for _,user in pairs(users) do
		gate.req.unregister(user.session)
	end
end

