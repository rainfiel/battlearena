
local function printf(...)
	print(...)
end

-------------------------------------------------------------------
local queue_mt = {}
queue_mt.__index = queue_mt

function queue_mt:push_back(item)
	if not self.tail then
		self.tail = item
		self.head = item
	else
		self.tail.next = item
		self.tail = item
	end
end

function queue_mt:pop_front()
	local head = self.head
	self.head = head.next
	if not self.head then
		self.tail = nil
	end
	return head
end

-------------------------------------------------------------------
local mt = {}
mt.__index = mt

function mt:init()
end

function mt:add_resp(index, resp)
	local item = {index=index, resp=resp}
	self.queue:push_back(item)
end

function mt:call(...)
	local item = self.queue:pop_front()
	assert(item, "empty msgqueue")
	item.resp(true, ...)
end

-------------------------------------------------------------------
local M = {}

function M.new()
	local ret = setmetatable({queue = setmetatable({head=nil, tail=nil}, queue_mt)}, mt)
	ret:init()
	return ret
end

return M
