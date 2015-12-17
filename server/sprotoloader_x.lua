local parser = require "sprotoparser"
local core = require "sproto.core"
local sproto = require "sproto"

local loader = {}

function loader.register(index, ...)
	local data = {}
	for k, v in ipairs({...}) do
		local f = assert(io.open(v), "Can't open sproto file")
		table.insert(data, f:read("a"))
		f:close()
	end
	local sp = core.newproto(parser.parse(table.concat(data, "\n")))
	core.saveproto(sp, index)
end

function loader.save(bin, index)
	local sp = core.newproto(bin)
	core.saveproto(sp, index)
end

function loader.load(index)
	local sp = core.loadproto(index)
	--  no __gc in metatable
	return sproto.sharenew(sp)
end

return loader

