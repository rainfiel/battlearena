local skynet = require "skynet"

function printf(fmt, ...)
	skynet.error(string.format(fmt, ...))
end

local udp_normal=0
local udp_confirm=1

local mt = {}
mt.__index = mt

function mt:init()
	self.packages = {}
	self.index = 0
	self.retry_timeout = 50 --500ms
end

function mt:user_count()
	local user_count = 0
	for _ in pairs(self.users) do
		user_count = user_count + 1
	end
	return user_count
end

function mt:add_ticket(session, index, data)
	local user = self.users[session]
	if not user then return end
	-- assert(not user.tickets[index])

	-- client resend ticket, resp to it only
	if user.tickets[index] then
		local ticket = user.tickets[index]
		local package = self.packages[ticket.s_index]
		package.timestamp = skynet.now() + self.retry_timeout
		self.gate.post.repost(session, ticket.data)
		return
	end

	local s_index = self.index + 1
	self.index = s_index

	-- change localtime to package index
	data = string.pack("<I", s_index)..string.sub(data, 5)
	local timestamp = skynet.now() + self.retry_timeout
	self.packages[s_index] = {sender=session, c_index=index, timestamp=timestamp}

	local tdata = string.pack("<I", skynet.now()) .. data
	user.tickets[index] = {data=tdata, confirm={}, count=0, s_index=s_index}
	printf("%d send udp_reliable, s_index:%d", session, s_index)
	return data
end

function mt:confirm_ticket(session, s_index)
	local package = self.packages[s_index]
	if not package then return end

	local owner = self.users[package.sender]
	if not owner then return end

	local ticket = owner.tickets[package.c_index]
	if not ticket then return end

	local confirm = ticket.confirm
	if confirm[session] then return end

	confirm[session] = true
	ticket.count = ticket.count + 1
	printf("...... %d confirm ticket %d", session, s_index)

	if ticket.count >= self:user_count() then
		owner.tickets[package.c_index] = nil
		self.packages[s_index] = nil
		printf("ticket finished:%d", s_index)
	end
end

function mt:get_ticket(package)
	local owner = self.users[package.sender]
	if not owner then return end

	return owner.tickets[package.c_index]
end

function mt.update_ticket(self)
	local remove = {}
	while true do
		local now = skynet.now()
		for s_index, package in pairs(self.packages) do
			if package.timestamp < now then
				local ticket = self:get_ticket(package)
				if ticket then
					for session in pairs(self.users) do
						if not ticket.confirm[session] then
							printf("repost ticket %d to %d", s_index, session)
							self.gate.post.repost(session, ticket.data)
						end
					end

					package.timestamp = now + self.retry_timeout
				else
					table.insert(remove, s_index)
				end
			end

			local cnt = #remove
			for i=1, cnt do
				self.packages[remove[i]] = nil
				remove[i] = nil
			end
		end
		skynet.sleep(10)	-- 100 ms
	end
end

function mt:update(data, ptype, session)
	if ptype > udp_confirm then
		data = self:add_ticket(session, ptype, data)
	elseif ptype == udp_confirm then
		local s_index = string.unpack("<I", data)
		self:confirm_ticket(session, s_index)
		data = nil
	end
	return data
end

return function(users, gate)
	local ret = setmetatable({users=users, gate=gate}, mt)
	ret:init()

	skynet.fork(ret.update_ticket, ret)
	return ret
end
