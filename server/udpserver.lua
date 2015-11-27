local skynet = require "skynet"
local socket = require "socket"
local crypt = require "crypt"
local snax = require "snax"

local U
local S = {}
local SESSION = 0
local package_timeout = 30 * 100	-- 0.5 mins
local session_timeout = 30 * 60 * 100 -- 3 mins

--[[
	8 bytes hmac   crypt.hmac_hash(key, session .. data)
	4 bytes localtime   -- ticket server id if confirm package
	4 bytes eventtime		-- if event time is ff ff ff ff , time sync
	4 bytes session
	4 bytes package type -- 0: normal, 1: confirm, >1: ticket
	padding data
]]

function response.register(service, key)
	SESSION = (SESSION + 1) & 0xffffffff
	S[SESSION] = {
		session = SESSION,
		key = key,
		room = snax.bind(service, "room"),
		address = nil,
		time = skynet.now(),
		lastevent = nil,
	}
	return SESSION
end

function response.unregister(session)
	S[session] = nil
end

function accept.post(session, data)
	local s = S[session]
	if s and s.address then		
		local time = skynet.now()
		data = string.pack("<I", time) .. data

		socket.sendto(U, s.address, data)
	else
		snax.printf("Session is invalid %d", session)
	end
end

function accept.repost(session, data)
	local s = S[session]
	if s and s.address then		
		socket.sendto(U, s.address, data)
	else
		snax.printf("Session is invalid %d", session)
	end
end

local function timesync(session, localtime, from)
	-- return globaltime .. localtime .. eventtime .. session , eventtime = 0xffffffff
	local now = skynet.now()
	socket.sendto(U, from, string.pack("<IIIII", now, localtime, 0xffffffff, session, 0))
end

--ptype: 0 for normal; 1 for confirm; >1 for ticket
local function udpdispatch(str, from)
	local localtime, eventtime, session, ptype = string.unpack("<IIII", str, 9)
	local s = S[session]
	if s then
		if s.address ~= from then
			if crypt.hmac_hash(s.key, str:sub(9)) ~= str:sub(1,8) then
				snax.printf("Invalid signature of session %d from %s", session, socket.udp_address(from))
				return
			end
			s.address = from
		end
		if eventtime == 0xffffffff then
			return timesync(session, localtime, from)
		end

		s.time = skynet.now()
		-- NOTICE: after 497 days, the time will rewind
		if s.time > eventtime + package_timeout then
			snax.printf("The package is delay %f sec", (s.time - eventtime)/100)
			return
		end

		-- confirm package ignore timesync because of
		-- localtime is the ticket index for server side.
		if ptype ~= 1 then
			if eventtime > s.time then
				-- drop this package, and force time sync
				return timesync(session, localtime, from)
			end

			if s.lastevent and eventtime < s.lastevent then
				-- drop older event
				return
			end

			s.lastevent = eventtime
		end

		if ptype > 1 then
			-- snax.printf("rec ticket, id(%d), time(%d), eventtime(%d)", ptype, s.time, eventtime)
		end
		s.room.post.update(str:sub(9), ptype, session)
	else
		snax.printf("Invalid session %d from %s" , session, socket.udp_address(from))
	end
end

local function keepalive()
	-- trash session after no package last 10 mins (timeout)
	while true do
		local i = 0
		local ti = skynet.now()
		for session, s in pairs(S) do
			i=i+1
			if i > 100 then
				skynet.sleep(300)	-- 30s
				ti = skynet.now()
				i = 1
			end
			if ti > s.time + session_timeout then
				s.room.post.timeout(session)
				S[session] = nil
			end
		end
		skynet.sleep(600)	-- 1 min
	end
end

function init(host, port, address)
	U = socket.udp(udpdispatch, host, port)
	skynet.fork(keepalive)
end

function exit()
	if U then
		socket.close(U)
		U = nil
	end
end


