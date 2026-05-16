--!strict
--!optimize 2

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
	_id: number,
}

export type Signify<T...> = {
	Connect: (self: Signify<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signify<T...>, fn: (T...) -> ()) -> Connection,
	Wait: (self: Signify<T...>) -> T...,
	Fire: (self: Signify<T...>, T...) -> (),
	DisconnectAll: (self: Signify<T...>) -> (),
	Destroy: (self: Signify<T...>) -> (),
}

type _Signify<T...> = Signify<T...> & {
	_head: number,
	_tail: number,
	_trash: number,
	_destroyed: boolean,
	_firing: number,
}

local WAIT_CANCEL_TOKEN = {} :: {}

local DEBUG = false

local freeRunnerThread: thread? = nil

local acquireRunnerThreadAndCallEventHandler: ((...any) -> (), ...any) -> ()
if DEBUG then
	acquireRunnerThreadAndCallEventHandler = function(fn, ...)
		local acquiredRunnerThread = freeRunnerThread
		freeRunnerThread = nil
		local packed = table.pack(pcall(fn, ...))
		local ok = packed[1]
		local err = packed[2]
		freeRunnerThread = acquiredRunnerThread
		if not ok then
			error(err, 0)
		end
	end
else
	acquireRunnerThreadAndCallEventHandler = function(fn, ...)
		local acquiredRunnerThread = freeRunnerThread
		freeRunnerThread = nil
		fn(...)
		freeRunnerThread = acquiredRunnerThread
	end
end

local function runEventHandlerInFreeThread()
	while true do
		acquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

local function ensureFreeRunnerThread(): thread
	local t = freeRunnerThread
	if t then
		return t
	end
	local created = coroutine.create(runEventHandlerInFreeThread)
	if DEBUG then
		local ok, err = coroutine.resume(created)
		if not ok then
			error(err, 0)
		end
	else
		coroutine.resume(created)
	end
	freeRunnerThread = created
	return created
end

local function assertAlive(signify: _Signify<...any>)
	if signify._destroyed then
		error("Signify is destroyed", 3)
	end
end

local function asSignify<T...>(self: Signify<T...>): _Signify<T...>
	return (self :: any) :: _Signify<T...>
end

local NODE_SIZE = 16
local POOL_CAPACITY = 256

local nodeBuffer = buffer.create(POOL_CAPACITY * NODE_SIZE)
local nodeData = table.create(POOL_CAPACITY) :: { any }
local nodeConn = table.create(POOL_CAPACITY) :: { Connection }
local nodeOwner = table.create(POOL_CAPACITY) :: { _Signify<...any> }

local freeHead = 1

local function initBufferSegment(startIdx: number, endIdx: number)
	for i = startIdx, endIdx - 1 do
		buffer.writeu32(nodeBuffer, i * NODE_SIZE + 8, i + 1)
	end
	buffer.writeu32(nodeBuffer, endIdx * NODE_SIZE + 8, 0)
end

initBufferSegment(1, POOL_CAPACITY - 1)

local function acquireId(): number
	local id = freeHead
	if id == 0 then
		local oldCap = POOL_CAPACITY
		local newCap = oldCap * 2
		local newBuf = buffer.create(newCap * NODE_SIZE)
		buffer.copy(newBuf, 0, nodeBuffer)
		nodeBuffer = newBuf
		initBufferSegment(oldCap, newCap - 1)
		POOL_CAPACITY = newCap
		id = oldCap
		freeHead = oldCap + 1
	else
		freeHead = buffer.readu32(nodeBuffer, id * NODE_SIZE + 8)
	end
	return id
end

local function releaseId(id: number)
	nodeData[id] = nil
	nodeConn[id] = nil
	nodeOwner[id] = nil
	buffer.writeu32(nodeBuffer, id * NODE_SIZE + 8, freeHead)
	freeHead = id
end

local function insertNode(signify: _Signify<...any>, id: number)
	local tail = signify._tail
	local offset = id * NODE_SIZE
	buffer.writeu32(nodeBuffer, offset, 0)
	buffer.writeu32(nodeBuffer, offset + 4, tail)

	if tail ~= 0 then
		buffer.writeu32(nodeBuffer, tail * NODE_SIZE, id)
		signify._tail = id
	else
		signify._head = id
		signify._tail = id
	end
end

local Connection = {}
Connection.__index = Connection

local function disconnectNode(signify: _Signify<...any>, id: number, suppressWaitResume: boolean?)
	local offset = id * NODE_SIZE
	local flags = buffer.readu8(nodeBuffer, offset + 12)
	if bit32.band(flags, 1) == 0 then
		return
	end

	buffer.writeu8(nodeBuffer, offset + 12, bit32.band(flags, 254))

	local conn = nodeConn[id]
	if conn then
		conn.Connected = false
		conn._id = 0
	end

	local prev = buffer.readu32(nodeBuffer, offset + 4)
	local next = buffer.readu32(nodeBuffer, offset)

	if prev ~= 0 then
		buffer.writeu32(nodeBuffer, prev * NODE_SIZE, next)
	else
		signify._head = next
	end

	if next ~= 0 then
		buffer.writeu32(nodeBuffer, next * NODE_SIZE + 4, prev)
	else
		signify._tail = prev
	end

	local data = nodeData[id]
	if type(data) == "thread" and not suppressWaitResume then
		task.spawn(data, WAIT_CANCEL_TOKEN)
	end

	if signify._firing > 0 then
		local trash = signify._trash
		buffer.writeu32(nodeBuffer, offset + 8, trash)
		signify._trash = id
	else
		releaseId(id)
	end
end

function Connection:Disconnect()
	local conn = self :: Connection
	if not conn.Connected then
		return
	end

	local id = conn._id
	if id == 0 then
		return
	end
	conn.Connected = false
	conn._id = 0

	local owner = nodeOwner[id]
	if owner then
		disconnectNode(owner, id)
	end
end

local function createConnection(id: number): Connection
	local raw = setmetatable({}, Connection) :: any
	raw.Connected = true
	raw._id = id
	return raw :: Connection
end

local Signify = {}
Signify.__index = Signify

function Signify.new<T...>(): Signify<T...>
	local self = setmetatable({}, Signify) :: any
	local s = (self :: any) :: _Signify<T...>
	s._head = 0
	s._tail = 0
	s._trash = 0
	s._destroyed = false
	s._firing = 0
	return self
end

local function connectInternal<T...>(signify: _Signify<T...>, data: any, once: boolean): number
	assertAlive(signify)
	local id = acquireId()

	local flags = 1
	if once then
		flags = bit32.bor(flags, 2)
	end
	buffer.writeu8(nodeBuffer, id * NODE_SIZE + 12, flags)

	nodeData[id] = data
	nodeOwner[id] = signify

	insertNode(signify, id)
	return id
end

function Signify:Connect<T...>(fn: (T...) -> ()): Connection
	local s = asSignify(self)
	local id = connectInternal(s, fn, false)
	local conn = createConnection(id)
	nodeConn[id] = conn
	return conn
end

function Signify:Once<T...>(fn: (T...) -> ()): Connection
	local s = asSignify(self)
	local id = connectInternal(s, fn, true)
	local conn = createConnection(id)
	nodeConn[id] = conn
	return conn
end

function Signify:Wait<T...>(): T...
	local s = asSignify(self)
	assertAlive(s)
	local thread = coroutine.running()

	connectInternal(s, thread, true)

	local function resumeWait(...)
		local token = (...)
		if token == WAIT_CANCEL_TOKEN then
			error("Signify wait was cancelled", 3)
		end
		return select(2, ...)
	end

	return resumeWait(coroutine.yield())
end

local function fireSpawn<T...>(signify: _Signify<T...>, ...: T...)
	assertAlive(signify)
	signify._firing += 1
	local taskSpawn = task.spawn
	local cur = signify._head

	while cur ~= 0 do
		local offset = cur * NODE_SIZE
		local nxt = buffer.readu32(nodeBuffer, offset)
		local flags = buffer.readu8(nodeBuffer, offset + 12)

		if bit32.band(flags, 1) == 1 then
			local data = nodeData[cur]
			if type(data) == "thread" then
				taskSpawn(data, nil, ...)
			else
				taskSpawn(ensureFreeRunnerThread(), data :: (...any) -> (), ...)
			end

			if bit32.band(flags, 2) == 2 then
				disconnectNode(signify, cur, true)
			end
		end
		cur = nxt
	end

	signify._firing -= 1
	if signify._firing == 0 then
		local trash = signify._trash
		signify._trash = 0
		while trash ~= 0 do
			local nxtTrash = buffer.readu32(nodeBuffer, trash * NODE_SIZE + 8)
			releaseId(trash)
			trash = nxtTrash
		end
	end
end

function Signify:Fire<T...>(...: T...)
	local s = asSignify(self)
	fireSpawn(s, ...)
end

function Signify:DisconnectAll<T...>()
	local s = asSignify(self)
	assertAlive(s)
	local cur = s._head
	s._head = 0
	s._tail = 0

	while cur ~= 0 do
		local offset = cur * NODE_SIZE
		local nxt = buffer.readu32(nodeBuffer, offset)

		local flags = buffer.readu8(nodeBuffer, offset + 12)
		buffer.writeu8(nodeBuffer, offset + 12, bit32.band(flags, 254))

		local conn = nodeConn[cur]
		if conn then
			conn.Connected = false
			conn._id = 0
		end

		local data = nodeData[cur]
		if type(data) == "thread" then
			task.spawn(data, WAIT_CANCEL_TOKEN)
		end

		if s._firing > 0 then
			local trash = s._trash
			buffer.writeu32(nodeBuffer, offset + 8, trash)
			s._trash = cur
		else
			releaseId(cur)
		end
		cur = nxt
	end
end

function Signify:Destroy<T...>()
	local s = asSignify(self)
	if s._destroyed then
		return
	end
	self:DisconnectAll()
	s._destroyed = true
end

return Signify
