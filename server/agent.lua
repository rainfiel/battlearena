local snax = require "snax"
local skynet = require "skynet"
local sprotoloader = require "sprotoloader"
local sproto = require "sproto"

local roomkeeper
local gate, room
local U = {}
local proto

local room_ready_response
local begin_fight_response

local function decode_proto(msg, sz)
	local blob = sproto.unpack(msg,sz)
	local type, offset = string.unpack("<I4", blob)
	local ret, name = proto:request_decode(type, blob:sub(5))
	return name, ret
end

local function encode_proto(name, obj)
	return sproto.pack(proto:response_encode(name, obj))
end


function response.login(source, uid, sid, secret)
	-- you may use secret to make a encrypted data stream
	roomkeeper = snax.queryservice "roomkeeper"
	snax.printf("%s is login", uid)
	gate = source
	U.userid = uid
	U.subid = sid
	U.key = secret
	-- you may load user data from database
end

local function logout()
	if gate then
		skynet.call(gate, "lua", "logout", U.userid, U.subid)
	end
	snax.exit()
end

function response.logout()
	-- NOTICE: The logout MAY be reentry
	snax.printf("%s is logout", U.userid)
	if room then
		room.req.leave(U.session)
	end
	logout()
end

function response.resp_room_ready(obj)
	if room_ready_response then
		room_ready_response(true, obj)
		room_ready_response = nil
	end
end

function response.resp_begin_fight(ok)
	if begin_fight_response then
		begin_fight_response(true, {ok=ok})
		begin_fight_response = nil
	end
end

function response.afk()
	-- the connection is broken, but the user may back
	snax.printf("AFK")
end

local client_request = {}

function client_request.join(msg)
	local handle, host, port = roomkeeper.req.apply(msg.room, msg.map)
	if not handle then
		return nil  --TODO handle error
	end
	local r = snax.bind(handle , "room")
	local session = assert(r.req.join(skynet.self(), U.key))
	U.session = session
	room = r
	snax.printf("%s joined to room %d(mapid %d, session %s)", U.userid, msg.room, msg.map, session)
	return { session = session, host = host, port = port }
end

function client_request.leave(msg)
	local room_info = room.req.room_info()
	roomkeeper.req.leave(room_info.id, room_info.mapid)
end

function client_request.report_formation(msg)
	local room_info, ready = room.req.report_formation(U.session, msg.swats)
	snax.printf("%s(session:%s) reported formation", U.userid, U.session)
	if ready then
		snax.printf("formation is ready")
	end
	return {ready=ready, room=room_info}
end

function client_request.query_current_room(msg, name)
	local room_info, ready = room.req.room_info()
	if ready or not msg.until_ready then
		return {ready=ready, room=room_info}
	else
		room_ready_response = skynet.response(function(...)
			return encode_proto(name, ...)
		end)
		return nil
	end
end

function client_request.ready_to_fight(msg, name)
	begin_fight_response = skynet.response(function( ... )
		return encode_proto(name, ...)
	end)
	room.req.ready_to_fight(U.session)
	return nil
end

local function dispatch_client(_,_,name,msg)
	local f = assert(client_request[name])
	local obj = f(msg, name)
	if obj ~= nil then
		skynet.ret(encode_proto(name, obj))
	end
end

function init()
	skynet.register_protocol {
		name = "client",
		id = skynet.PTYPE_CLIENT,
		unpack = decode_proto,
	}

	-- todo: dispatch client message
	skynet.dispatch("client", dispatch_client)

	proto = sprotoloader.load(1)
end
