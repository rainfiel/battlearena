local snax = require "snax"
local skynet = require "skynet"
local msgqueue = require "msgqueue"
local lzma = require "lzma"
local item = require "item"
local sprotoloader = require "sprotoloader_x"
local role_mgr = require "role"

local proto_wrapper = require "proto_wrapper"
local decode_proto
local encode_proto
local encode_type
local default_proto

local roomkeeper
local gate, room
local U = {}
local role
local proto

local room_ready_response
local response_queue

local function leave_room()
	if not room then return {id=U.session} end
	local obj = room.req.leave(U.session)

	if obj.useless then
		local room_info = room.req.room_info()
		local resp = roomkeeper.req.close(room_info.id, room_info.mapid)
	end
	room = nil
	response_queue = nil
	room_ready_response = nil
	return obj
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

function response.resp(type, data)
	if response_queue then
		local msg = encode_type(type, data)
		response_queue:call({type=type, msg=msg})
	end
end

function response.encode_type(...)
	return encode_type(...)
end

function response.afk()
	-- the connection is broken, but the user may back
	snax.printf("%s(session:%s) AFK", U.userid, U.session)
	--TEMP
	if room then
		leave_room()
	end
end

--requests
-----------------------------------------------------------------------------
local client_request = {}

function client_request.role_info()
	role = role_mgr.load_role(U.userid)
	return {role=role.raw}
end

function client_request.buy_item(name)
	local ok, item = role:buy_item(name)
	return {ok=ok, item=item}
end

function client_request.join(msg)
	local handle, roomid, host, port = roomkeeper.req.apply(msg.room, msg.map)
	if not handle then
		return nil  --TODO handle error
	end
	local r = snax.bind(handle , "room")
	local session = assert(r.req.join(skynet.self(), U.key, U.userid))
	U.session = session
	room = r
	snax.printf("%s joined to room %d(mapid %d, session %s)", U.userid, roomid, msg.map, session)
	return { session = session, host = host, port = port }
end

function client_request.cancel_join(msg)
	snax.printf("%s(session:%s) cancel join room", U.userid, U.session)
	leave_room()
	return {ok=true}
end

function client_request.leave(msg)
	snax.printf("%s(session:%s) leaved room", U.userid, U.session)
	local obj = leave_room()
	return {resp=obj}
end

function client_request.report_formation(msg)
	local room_info, ready = room.req.report_formation(U.session, msg.swats)
	snax.printf("%s(session:%s) reported formation, swat count(%d)", U.userid, U.session, #msg.swats)
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

function client_request.cut_seat(msg)
	snax.printf("%s(session:%s) cut_seat", U.userid, U.session)
	room.req.cut_seat(U.session)
	return nil
end

function client_request.ready_to_fight(msg, name)
	snax.printf("%s(session:%s) ready_to_fight", U.userid, U.session)
	room.req.ready_to_fight(U.session)
	return {}
end

function client_request.loading_done()
	snax.printf("%s(session:%s) loading_done", U.userid, U.session)
	room.req.loading_done(U.session)
	return {}
end

function client_request.queue_item(msg, name)
	local resp = skynet.response(function( ... )
		return encode_proto(name, ...)
	end)
	if not response_queue then
		response_queue = msgqueue.new()
	end
	response_queue:add_resp(msg.index, resp)
end

function client_request.reach(msg)
	local resp = room.req.reach(U.session, msg)
	return {resp=resp}
end

function client_request.log(msg)
	local room_info = room.req.room_info()
	local d = os.date("*t")
	local fname = string.format("%d-%d-%d%d%d%d%d", room_info.id, U.session, d.year, d.month, d.day, d.hour, d.sec)
	
	local txt = lzma.uncompress(msg.log)

	snax.printf("%s(session:%s) log file:%s", U.userid, U.session, fname)
	local f = io.open(string.format("log/%s.log", fname), "w")
	f:write(txt)
	f:close()
	return {}
end

local function dispatch_client(_,_,name,msg)
	local f = assert(client_request[name], name)
	local obj = f(msg, name)
	if obj ~= nil then
		skynet.ret(encode_proto(name, obj))
	end
end

function init()
	proto = sprotoloader.load(1)
	proto_wrapper.init(proto)

	decode_proto = proto_wrapper.decode_proto
	encode_proto = proto_wrapper.encode_proto
	encode_type = proto_wrapper.encode_type
	default_proto = proto_wrapper.default

	skynet.register_protocol {
		name = "client",
		id = skynet.PTYPE_CLIENT,
		unpack = decode_proto,
	}
	skynet.dispatch("client", dispatch_client)
end
