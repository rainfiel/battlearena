
local snax = require "snax"
local sproto = require "sproto"

local proto

local function init(p)
	proto = p
end

local function decode_proto(msg, sz)
	local blob = sproto.unpack(msg,sz)
	local type, offset = string.unpack("<I4", blob)
	local ret, name = proto:request_decode(type, blob:sub(5))
	return name, ret
end

local function encode_proto(name, obj)
	return sproto.pack(proto:response_encode(name, obj))
end

local function encode_type(typename, obj)
	return proto:pencode(typename, obj)
end

local function decode_type(typename, ...)
	return proto:pdecode(typename, ...)
end

local function default(...)
	local p = proto:default(...)
	for k, v in pairs(p) do
		if type(v) == "table" and v.__type then
			rawset(p, k, default(v.__type))
		end
	end
	return p
end

return {
	init=init,
	decode_proto=decode_proto,
	encode_proto=encode_proto,
	encode_type=encode_type,
	decode_type=decode_type,
	default=default,
}
