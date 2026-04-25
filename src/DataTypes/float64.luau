--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)

type DataType<T> = Types.DataType<T>

local float64: DataType<number> = {
	size = 8,

	read = function(b: buffer, offset: number): (number, number)
		return buffer.readf64(b, offset), offset + 8
	end,

	write = function(b: buffer, offset: number, value: number): number
		buffer.writef64(b, offset, value)
		return offset + 8
	end,
}

return float64
