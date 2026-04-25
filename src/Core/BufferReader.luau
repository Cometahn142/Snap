--!strict
--!native
--!optimize 2

export type BufferReader = {
	buffer: buffer,
	cursor: number,
	length: number,

	hasMore: (self: BufferReader) -> boolean,
	readU8: (self: BufferReader) -> number,
	readU16: (self: BufferReader) -> number,
	subBuffer: (self: BufferReader, length: number) -> buffer,
	advance: (self: BufferReader, length: number) -> number,
}

local BufferReader = {}
BufferReader.__index = BufferReader

function BufferReader.new(b: buffer): BufferReader
	local self = setmetatable({
		buffer = b,
		cursor = 0,
		length = buffer.len(b),
	}, BufferReader) :: any

	return self
end

function BufferReader.hasMore(self: BufferReader): boolean
	return self.cursor < self.length
end

function BufferReader.readU8(self: BufferReader): number
	local value = buffer.readu8(self.buffer, self.cursor)
	self.cursor += 1
	return value
end

function BufferReader.readU16(self: BufferReader): number
	local value = buffer.readu16(self.buffer, self.cursor)
	self.cursor += 2
	return value
end

function BufferReader.subBuffer(self: BufferReader, length: number): buffer
	local result = buffer.create(length)
	buffer.copy(result, 0, self.buffer, self.cursor, length)
	self.cursor += length
	return result
end

function BufferReader.advance(self: BufferReader, length: number): number
	local before = self.cursor
	self.cursor += length
	return before
end

return BufferReader
