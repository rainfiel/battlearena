
local snax = require "snax"
local proto = require "proto_wrapper"

local role_mt = {}
role_mt.__index = role_mt

function role_mt:buy_item(name)
	return false
end

-------------------------------------------------------------------
local roles = {}
local default_cfg = {{name="Friendly_Pointman",hp=100,
										items={{name="P226 Pistol", type="pistol", default=true},
										{name="Raider Vest", type="armor", default=true}}
										}}

local function new_item(name, item_type, id)
	-- local d = item:get_data(name)
	-- assert(d, name)
	-- local item_type = d.rigid_type and d.rigid_type or d.type

	local obj = proto.default("item")
	obj.id = id
	obj.type = item_type

	local i = proto.default(item_type)
	i.name = name
	obj.data = proto.encode_type(item_type, i)
	return obj
end

local function new_role_proto()
	local cfgs = default_cfg
	local role = proto.default("role")
	local item_count = 0
	for k, v in ipairs(cfgs) do
		local default_weapon={}
		if v.items then
			for m, n in ipairs(v.items) do
				item_count = item_count + 1
				table.insert(role.items, new_item(n.name, n.type, item_count))
				if n.default then
					table.insert(default_weapon, item_count)
				end
			end
		end

		local swat = proto.default("swat")
		for m, n in pairs(swat) do
			local t = rawget(v, m)
			if t then swat[m] = t end
		end
		swat.index = k
		swat.default_weapon=default_weapon
		table.insert(role.swats, swat)
	end
	for k, v in ipairs(cfgs.items or {}) do
		item_count = item_count + 1
		table.insert(role.items, new_item(v.name, n.type, item_count))
	end

	role.index = 1
	role.coins = 50000
	return role
end

local function load(name)
	local f = io.open(string.format("role/%s", name), "rb")
	if not f then return end
	local raw = f:read("a")
	f:close()
	if raw then
		return proto.decode_type("role", raw)
	end
end

local function save(name, data)
	local raw = proto.encode_type("role", data)
	local f = io.open(string.format("role/%s", name), "wb")
	f:write(raw)
	f:close()
end

local function load_role(name)
	local inst = roles[name]
	if inst then return inst end
	local data = load(name)
	if not data then
		snax.printf("create new role:", name)
		data = new_role_proto()
		save(name, data)
	end
	local inst = setmetatable({raw=data}, role_mt)
	roles[name] = inst
	return inst
end

return {
	load_role=load_role,
}
