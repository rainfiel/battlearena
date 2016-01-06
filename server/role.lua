
local snax = require "snax"
local data = require "data"
local proto_wrapper = require "proto_wrapper"
local sprotoloader = require "sprotoloader_x"

local proto
local roles = {}
local default_cfg = {{name="Friendly_Pointman",hp=100,
										items={{name="P226 Pistol", default=true},
										{name="Raider Vest", default=true}}
										}}

local function load(name)
	local f = io.open(string.format("role/%s", name), "rb")
	if not f then return end
	local raw = f:read("a")
	f:close()
	if raw then
		return proto_wrapper.decode_type("role", raw)
	end
end

local function save(name, data)
	local raw = proto_wrapper.encode_type("role", data)
	local f = io.open(string.format("role/%s", name), "wb")
	f:write(raw)
	f:close()
end

local function get_role(id)
	return roles[id]
end

-------------------------------------------------------------------
local function new_item(name, id)
	local d = data.get_item(name)
	local item_type = d.rigid_type and d.rigid_type or d.type

	local obj = proto_wrapper.default("item")
	obj.id = id
	obj.type = item_type
	obj.count = 1

	local i = proto_wrapper.default(item_type)
	i.name = name
	obj.data = proto_wrapper.encode_type(item_type, i)
	obj.plain = i
	return obj
end

local function decode_item(obj)
	obj.plain = proto_wrapper.decode_type(obj.type, obj.data)
end

local function encode_item(obj)
	obj.data = proto_wrapper.encode_type(obj.type, obj.plain)
end

local function new_role_proto()
	local cfgs = default_cfg
	local role = proto_wrapper.default("role")
	local item_count = 0
	for k, v in ipairs(cfgs) do
		local default_weapon={}
		if v.items then
			for m, n in ipairs(v.items) do
				item_count = item_count + 1
				table.insert(role.items, new_item(n.name, item_count))
				if n.default then
					table.insert(default_weapon, item_count)
				end
			end
		end

		local swat = proto_wrapper.default("swat")
		for m, n in pairs(swat) do
			local t = rawget(v, m)
			if t then swat[m] = t end
		end
		swat.index = k
		swat.ammo = data.const.init_ammo
		swat.default_weapon=default_weapon
		table.insert(role.swats, swat)
	end
	for k, v in ipairs(cfgs.items or {}) do
		item_count = item_count + 1
		table.insert(role.items, new_item(v.name, item_count))
	end

	role.index = 1
	role.coins = 50000
	return role
end

------------------------------------------------------------------
local role_mt = {}
role_mt.__index = role_mt

function role_mt:init()
	self.id = self.name
	self.items = self.raw.items
	for k, v in ipairs(self.items) do
		decode_item(v)
	end
end

function role_mt:get_item(id)
	return self.items[id]
end

function role_mt:get_item_by_name(name)
	for k, v in ipairs(self.items) do
		if v.plain.name == name then
			return v
		end
	end
end

function role_mt:add_item(name)
	local item = self:get_item_by_name(name)
	if item then
		item.count = item.count + 1
	else
		local id = #self.items + 1
		item = new_item(name, id)
		table.insert(self.items, item)
		self:save()
	end
	return item
end

function role_mt:buy_item(name)
	local price = data.get_price(name)
	price = price.activate_price
	local now_coins = self.raw.coins
	if now_coins >= price then
		self.raw.coins = now_coins - price
		local item = self:add_item(name)
		return true, self.raw.coins, item
	else
		return false
	end
end

function role_mt:upgrade_attr(id, group_id, group_idx, attr, lv_count)
	local obj = self:get_item(id)
	assert(obj, id)
	local group = obj.plain

	local _data = data.get_item(group.name)

	if group_id > 0 then
		group = rawget(group, string.format("%s_c%d", obj.type, group_id))
		group = group[group_idx]
		_data = _data[group_idx]
	end

	local lv = group[attr]
	if lv == 0 then lv = 1 end
	local cost = _data[attr][lv].cost

	local now = self.raw.coins
	if now >= cost then
		local new_lv = lv + lv_count
		if _data[attr][new_lv] then
			self.raw.coins = now - cost
			group[attr] = new_lv
			self:save()
			return true, self.raw.coins, obj
		else
			return false
		end
	else
		return false
	end
end

function role_mt:save()
	for k, v in ipairs(self.raw.items) do
		encode_item(v)
	end
	save(self.name, self.raw)
end

--------------------------------------------------------
function response.load_role(name)
	local inst = roles[name]
	if inst then return inst end
	local data = load(name)
	if not data then
		snax.printf("create new role:"..name)
		data = new_role_proto()
		save(name, data)
	end
	local inst = setmetatable({raw=data,name=name}, role_mt)
	inst:init()
	roles[inst.id] = inst
	return inst
end

function response.buy_item(id, name)
	local role = get_role(id)
	return role:buy_item(name)
end

function response.upgrade_attr(id, msg)
	local role = get_role(id)
	return role:upgrade_attr(msg.id, msg.attr_group_id, 
													 msg.attr_group_idx, msg.attr, msg.lv_count)
end

function init()
	proto = sprotoloader.load(1)
	proto_wrapper.init(proto)
end
