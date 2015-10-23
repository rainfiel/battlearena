local snax = require "snax"
local host
local port = 9999
local udpgate
local room_index = 0
local rooms = {}
local map_rooms = {}

function response.apply(roomid, mapid)
	local room
	if roomid == 0 then
		local maps = map_rooms[mapid]
		if maps then
			for rid in pairs(maps) do
				local r = rooms[rid]
				if r and r.req.is_available() then
					print("found")
					room = r
					roomid = rid
				end
			end
		end
		if room == nil then
			roomid = room_index + 1
			room_index = roomid
			room = snax.newservice("room", roomid, mapid, udpgate.handle)
			rooms[roomid] = room
			if not map_rooms[mapid] then map_rooms[mapid] = {} end
			map_rooms[mapid][roomid] = true
		end
	else
		room = rooms[roomid]
		if room.req.mapid() ~= mapid then
			room = nil
		end
	end
	if room then
		return room.handle, roomid, host, port
	end
end

function response.close(roomid, mapid)
	snax.printf("close room %d", roomid)
	rooms[roomid] = nil
	map_rooms[mapid][roomid] = nil
		--TODO reuse room
end

-- todo : close room ?

function init()
	local skynet = require "skynet"
-- todo: we can use a gate pool
	host = skynet.getenv "udp_host"
	udpgate = snax.newservice("udpserver", "0.0.0.0", port)
end
