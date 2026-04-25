--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)

type DataType<T> = Types.DataType<T>

local uint16: DataType<number> = {
	size = 2,

	read = function(b: buffer, offset: number): (number, number)
		return buffer.readu16(b, offset), offset + 2
	end,

	write = function(b: buffer, offset: number, value: number): number
		buffer.writeu16(b, offset, value)
		return offset + 2
	end,
}

return uint16
