local msgserver = require "snax.msgserver"
local crypt = require "crypt"
local skynet = require "skynet"
local snax = require "snax"
local sprotoloader = require "sprotoloader_x"

local loginservice = tonumber(...)

local server = {}
local users = {}
local username_map = {}
local internal_id = 0

-- login server disallow multi login, so login_handler never be reentry
-- call by login server
function server.login_handler(uid, secret)
	if users[uid] then
		error(string.format("%s is already login", uid))
	end

	internal_id = internal_id + 1
	local username = msgserver.username(uid, internal_id, servername)

	-- you can use a pool to alloc new agent
	local agent = snax.newservice "agent"
	local u = {
		username = username,
		agent = agent,
		uid = uid,
		subid = internal_id,
	}

	-- trash subid (no used)
	agent.req.login(skynet.self(), uid, internal_id, secret)

	users[uid] = u
	username_map[username] = u

	msgserver.login(username, secret)

	-- you should return unique subid
	return internal_id
end

-- call by agent
function server.logout_handler(uid, subid)
	local u = users[uid]
	if u then
		local username = msgserver.username(uid, subid, servername)
		assert(u.username == username)
		msgserver.logout(u.username)
		users[uid] = nil
		username_map[u.username] = nil
		skynet.call(loginservice, "lua", "logout",uid, subid)
	end
end

-- call by login server
function server.kick_handler(uid, subid)
	local u = users[uid]
	if u then
		local username = msgserver.username(uid, subid, servername)
		assert(u.username == username)
		-- NOTICE: logout may call skynet.exit, so you should use pcall.
		pcall(u.agent.req.logout)
	end
end

-- call by self (when socket disconnect)
function server.disconnect_handler(username)
	local u = username_map[username]
	if u then
		u.agent.req.afk()
	end
end

-- call by self (when recv a request from client)
function server.request_handler(username, msg, sz)
	local u = username_map[username]
	return skynet.tostring(skynet.rawcall(u.agent.handle, "client", msg, sz))
end

-- call by self (when gate open)
function server.register_handler(name)
	servername = name
	-- todo: move the gate into a cluster, split from loginservice
	skynet.call(loginservice, "lua", "register_gate", servername, skynet.self())
end

sprotoloader.register(1, "common_data/lobby.sproto", "common_data/item.sproto")
msgserver.start(server)

