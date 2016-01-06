
local snax = require "snax"
local serialize = require "serialize"

local function bin_path(name)
	return string.format("common_data/%s.bin", name)
end
local function lua_path(name)
	return string.format("common_data/%s.lua", name)
end

local function read_bin(name)
	local path = bin_path(name)
	local f = io.open(path, "rb")
	local raw = f:read("a")
	f:close()
	return serialize.deseristring_string(raw)
end

local function read_lua(name)
	local path = lua_path(name)
	local f = io.open(path, "r")
	local raw = f:read("a")
	f:close()
	return load(raw, name, "t", {})()
end

-----------------------------------------------------------
local item = read_bin("item")
local function get_item(name)
	return assert(item[name], name)
end

local price = read_bin("shopprice")
local function get_price(name)
	return assert(price[name], name)
end

return {
	get_item=get_item,
	get_price=get_price,
}
