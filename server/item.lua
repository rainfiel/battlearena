

local default_items = {
	pistols={"P226 Pistol"},
	armor={"Raider Vest"}
}


local function default_proto(proto,...)
	local p = proto:default(...)
	for k, v in pairs(p) do
		if type(v) == "table" and v.__type then
			rawset(p, k, default_proto(v.__type))
		end
	end
	return p
end

local M = {}

function M.default_item(role, proto)
	for k, v in pairs(default_items) do
		for _, m in ipairs(v) do
			local i = default_proto(proto, "item")
			i.type=k
			local j = default_proto(proto, k)
			j.name = m
			i.data = proto:pencode(k, j)
			table.insert(role.items, i)
		end
	end
end

return M
