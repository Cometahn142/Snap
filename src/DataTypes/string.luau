--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)
local Varint = require(script.Parent.Parent.Core.Varint)

type DataType<T> = Types.DataType<T>

local writeVarint = Varint.writeUnsigned
local readVarint = Varint.readUnsigned
local varintSize = Varint.sizeUnsigned

local str: DataType<string> = {
	size = function(value: string): number
		local len = #value
		return varintSize(len) + len
	end,

	read = function(b: buffer, offset: number): (string, number)
		local length, cursor = readVarint(b, offset)
		local value = buffer.readstring(b, cursor, length)
		return value, cursor + length
	end,

	write = function(b: buffer, offset: number, value: string): number
		local length = #value
		local cursor = writeVarint(b, offset, length)
		buffer.writestring(b, cursor, value)
		return cursor + length
	end,
}

return str
