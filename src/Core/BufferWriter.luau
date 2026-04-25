--!strict
--!native
--!optimize 2

local DEFAULT_CAPACITY = 2048
local MAX_RETAINED_CAPACITY = 65536

export type BufferWriter = {
	buffer: buffer,
	capacity: number,
	cursor: number,
	refs: { any },
	refsLookup: { [any]: number },

	reserve: (self: BufferWriter, additional: number) -> (),
	writeU8: (self: BufferWriter, value: number) -> (),
	writeU16: (self: BufferWriter, value: number) -> (),
	writeBuffer: (self: BufferWriter, source: buffer, sourceOffset: number, length: number) -> (),
	finalize: (self: BufferWriter) -> buffer,
	reset: (self: BufferWriter) -> (),
}

local BufferWriter = {}
BufferWriter.__index = BufferWriter

BufferWriter.DEFAULT_CAPACITY = DEFAULT_CAPACITY
BufferWriter.MAX_RETAINED_CAPACITY = MAX_RETAINED_CAPACITY

function BufferWriter.new(initialCapacity: number?): BufferWriter
	local capacity = initialCapacity or DEFAULT_CAPACITY
	local self = setmetatable({
		buffer = buffer.create(capacity),
		capacity = capacity,
		cursor = 0,
		refs = {},
		refsLookup = {},
	}, BufferWriter) :: any

	return self
end

function BufferWriter.reserve(self: BufferWriter, additional: number)
	local needed = self.cursor + additional
	if needed <= self.capacity then
		return
	end

	local newCapacity = self.capacity * 2
	if newCapacity < needed then
		newCapacity = needed + 64
	end

	local newBuffer = buffer.create(newCapacity)
	buffer.copy(newBuffer, 0, self.buffer, 0, self.cursor)
	self.buffer = newBuffer
	self.capacity = newCapacity
end

function BufferWriter.writeU8(self: BufferWriter, value: number)
	local c = self.cursor
	if c + 1 > self.capacity then
		self:reserve(1)
	end
	buffer.writeu8(self.buffer, c, value)
	self.cursor = c + 1
end

function BufferWriter.writeU16(self: BufferWriter, value: number)
	local c = self.cursor
	if c + 2 > self.capacity then
		self:reserve(2)
	end
	buffer.writeu16(self.buffer, c, value)
	self.cursor = c + 2
end

function BufferWriter.writeBuffer(self: BufferWriter, source: buffer, sourceOffset: number, length: number)
	local c = self.cursor
	if c + length > self.capacity then
		self:reserve(length)
	end
	buffer.copy(self.buffer, c, source, sourceOffset, length)
	self.cursor = c + length
end

function BufferWriter.finalize(self: BufferWriter): buffer
	local cursor = self.cursor
	local result = buffer.create(cursor)
	buffer.copy(result, 0, self.buffer, 0, cursor)
	return result
end

function BufferWriter.shrinkRangeInPlace(
	self: BufferWriter,
	slotOffset: number,
	reservedLen: number,
	actualLen: number
)
	if actualLen == reservedLen then
		return
	end
	local payloadStart = slotOffset + reservedLen
	local payloadEnd = self.cursor
	local payloadLen = payloadEnd - payloadStart
	if payloadLen > 0 then
		buffer.copy(self.buffer, slotOffset + actualLen, self.buffer, payloadStart, payloadLen)
	end
	self.cursor -= (reservedLen - actualLen)
end

function BufferWriter.reset(self: BufferWriter)
	self.cursor = 0
	if #self.refs > 0 then
		table.clear(self.refs)
		table.clear(self.refsLookup :: any)
	end
	if self.capacity > MAX_RETAINED_CAPACITY then
		self.buffer = buffer.create(MAX_RETAINED_CAPACITY)
		self.capacity = MAX_RETAINED_CAPACITY
	end
end

return BufferWriter
