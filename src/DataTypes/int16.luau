--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)

type DataType<T> = Types.DataType<T>

local int16: DataType<number> = {
	size = 2,

	read = function(b: buffer, offset: number): (number, number)
		return buffer.readi16(b, offset), offset + 2
	end,

	write = function(b: buffer, offset: number, value: number): number
		buffer.writei16(b, offset, value)
		return offset + 2
	end,
}

return int16
