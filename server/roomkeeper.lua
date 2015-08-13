local snax = require "snax"
local host
local port = 9999
local udpgate
local rooms = {}
local map_rooms = {}

function response.apply(roomid, mapid)
	local room
	if roomid == 0 then
		local maps = map_rooms[mapid]
		if maps then
			for _, rid in ipairs(maps) do
				local r = rooms[rid]
				if r and not r.req.is_full() then
					room = r
					roomid = rid
				end
			end
		end
		if room == nil then
			roomid = #rooms + 1
			room = snax.newservice("room", roomid, mapid, udpgate.handle)
			rooms[roomid] = room
			if not map_rooms[mapid] then map_rooms[mapid] = {} end
			table.insert(map_rooms[mapid], roomid)
		end
	else
		room = rooms[roomid]
		if room.req.mapid() ~= mapid then
			room = nil
		end
	end
	if room  then
		return room.handle , host, port
	end
end

-- todo : close room ?

function init()
	local skynet = require "skynet"
-- todo: we can use a gate pool
	host = skynet.getenv "udp_host"
	udpgate = snax.newservice("udpserver", "0.0.0.0", port)
end
