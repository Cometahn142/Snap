--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)
local Varint = require(script.Parent.Parent.Core.Varint)

type DataType<T> = Types.DataType<T>

local writeUnsigned = Varint.writeUnsigned
local readUnsigned = Varint.readUnsigned
local sizeUnsigned = Varint.sizeUnsigned
local writeSigned = Varint.writeSigned
local readSigned = Varint.readSigned
local sizeSigned = Varint.sizeSigned

local TAG_NIL = 0
local TAG_FALSE = 1
local TAG_TRUE = 2
local TAG_UINT = 3
local TAG_INT = 4
local TAG_FLOAT = 5
local TAG_STRING = 6
local TAG_ARRAY = 7
local TAG_MAP = 8
local TAG_BUFFER = 9

local function isArray(t: { [any]: any }): (boolean, number)
	local len = #t
	if len == 0 then
		if next(t) == nil then
			return true, 0
		end
		return false, 0
	end

	local count = 0
	for _ in t do
		count += 1
	end

	if count == len then
		return true, len
	end
	return false, count
end

local computeSize: (value: any) -> number
local writeValue: (b: buffer, offset: number, value: any) -> number
local readValue: (b: buffer, offset: number) -> (any, number)

function computeSize(value: any): number
	local kind = type(value)

	if value == nil then
		return 1
	elseif kind == "boolean" then
		return 1
	elseif kind == "number" then
		if value % 1 == 0 and value >= -2147483648 and value <= 2147483647 then
			if value >= 0 then
				return 1 + sizeUnsigned(value)
			else
				return 1 + sizeSigned(value)
			end
		end
		return 1 + 8
	elseif kind == "string" then
		local len = #value
		return 1 + sizeUnsigned(len) + len
	elseif kind == "buffer" then
		local len = buffer.len(value)
		return 1 + sizeUnsigned(len) + len
	elseif kind == "table" then
		local asArray, count = isArray(value)
		if asArray then
			local total = 1 + sizeUnsigned(count)
			for i = 1, count do
				total += computeSize(value[i])
			end
			return total
		else
			local total = 1
			local n = 0
			for k, v in value do
				n += 1
				total += computeSize(k) + computeSize(v)
			end
			return total + sizeUnsigned(n)
		end
	end

	error(string.format("[Snap] auto: unsupported value type '%s'", kind), 2)
end

function writeValue(b: buffer, offset: number, value: any): number
	local kind = type(value)

	if value == nil then
		buffer.writeu8(b, offset, TAG_NIL)
		return offset + 1
	elseif kind == "boolean" then
		buffer.writeu8(b, offset, if value then TAG_TRUE else TAG_FALSE)
		return offset + 1
	elseif kind == "number" then
		if value % 1 == 0 and value >= -2147483648 and value <= 2147483647 then
			if value >= 0 then
				buffer.writeu8(b, offset, TAG_UINT)
				return writeUnsigned(b, offset + 1, value)
			else
				buffer.writeu8(b, offset, TAG_INT)
				return writeSigned(b, offset + 1, value)
			end
		end
		buffer.writeu8(b, offset, TAG_FLOAT)
		buffer.writef64(b, offset + 1, value)
		return offset + 9
	elseif kind == "string" then
		buffer.writeu8(b, offset, TAG_STRING)
		local len = #value
		local cursor = writeUnsigned(b, offset + 1, len)
		buffer.writestring(b, cursor, value)
		return cursor + len
	elseif kind == "buffer" then
		buffer.writeu8(b, offset, TAG_BUFFER)
		local len = buffer.len(value)
		local cursor = writeUnsigned(b, offset + 1, len)
		buffer.copy(b, cursor, value, 0, len)
		return cursor + len
	elseif kind == "table" then
		local asArray, count = isArray(value)
		if asArray then
			buffer.writeu8(b, offset, TAG_ARRAY)
			local cursor = writeUnsigned(b, offset + 1, count)
			for i = 1, count do
				cursor = writeValue(b, cursor, value[i])
			end
			return cursor
		else
			buffer.writeu8(b, offset, TAG_MAP)
			local reserved = 5
			local slotOffset = offset + 1
			local payloadStart = slotOffset + reserved
			local cursor = payloadStart
			local n = 0
			for k, v in value do
				n += 1
				cursor = writeValue(b, cursor, k)
				cursor = writeValue(b, cursor, v)
			end
			local actualLen = sizeUnsigned(n)
			writeUnsigned(b, slotOffset, n)
			if actualLen ~= reserved then
				buffer.copy(b, slotOffset + actualLen, b, payloadStart, cursor - payloadStart)
				cursor -= (reserved - actualLen)
			end
			return cursor
		end
	end

	error(string.format("[Snap] auto: cannot encode type '%s'", kind), 2)
end

function readValue(b: buffer, offset: number): (any, number)
	local tag = buffer.readu8(b, offset)
	local cursor = offset + 1

	if tag == TAG_NIL then
		return nil, cursor
	elseif tag == TAG_FALSE then
		return false, cursor
	elseif tag == TAG_TRUE then
		return true, cursor
	elseif tag == TAG_UINT then
		return readUnsigned(b, cursor)
	elseif tag == TAG_INT then
		return readSigned(b, cursor)
	elseif tag == TAG_FLOAT then
		return buffer.readf64(b, cursor), cursor + 8
	elseif tag == TAG_STRING then
		local len, nextCursor = readUnsigned(b, cursor)
		return buffer.readstring(b, nextCursor, len), nextCursor + len
	elseif tag == TAG_BUFFER then
		local len, nextCursor = readUnsigned(b, cursor)
		local result = buffer.create(len)
		buffer.copy(result, 0, b, nextCursor, len)
		return result, nextCursor + len
	elseif tag == TAG_ARRAY then
		local count, nextCursor = readUnsigned(b, cursor)
		local result = table.create(count)
		local c = nextCursor
		for i = 1, count do
			local v: any
			v, c = readValue(b, c)
			result[i] = v
		end
		return result, c
	elseif tag == TAG_MAP then
		local count, nextCursor = readUnsigned(b, cursor)
		local result: { [any]: any } = table.create(0, count)
		local c = nextCursor
		for _ = 1, count do
			local k: any
			local v: any
			k, c = readValue(b, c)
			v, c = readValue(b, c)
			result[k] = v
		end
		return result, c
	end

	error(string.format("[Snap] auto: unknown tag %d at offset %d", tag, offset), 2)
end

local auto: DataType<any> = {
	size = computeSize,
	read = readValue,
	write = writeValue,
}

return auto
