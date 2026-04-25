--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)
local Varint = require(script.Parent.Parent.Core.Varint)

type DataType<T> = Types.DataType<T>

local uvarint: DataType<number> = {
	size = Varint.sizeUnsigned,

	read = function(b: buffer, offset: number): (number, number)
		return Varint.readUnsigned(b, offset)
	end,

	write = function(b: buffer, offset: number, value: number): number
		return Varint.writeUnsigned(b, offset, value)
	end,
}

return uvarint
