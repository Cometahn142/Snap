--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)
local Varint = require(script.Parent.Parent.Core.Varint)

type DataType<T> = Types.DataType<T>

local varint: DataType<number> = {
	size = Varint.sizeSigned,

	read = function(b: buffer, offset: number): (number, number)
		return Varint.readSigned(b, offset)
	end,

	write = function(b: buffer, offset: number, value: number): number
		return Varint.writeSigned(b, offset, value)
	end,
}

return varint
