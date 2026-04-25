--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)

type DataType<T> = Types.DataType<T>

local float32: DataType<number> = {
	size = 4,

	read = function(b: buffer, offset: number): (number, number)
		return buffer.readf32(b, offset), offset + 4
	end,

	write = function(b: buffer, offset: number, value: number): number
		buffer.writef32(b, offset, value)
		return offset + 4
	end,
}

return float32
