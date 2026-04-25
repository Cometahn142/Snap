--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)

type DataType<T> = Types.DataType<T>

local int8: DataType<number> = {
	size = 1,

	read = function(b: buffer, offset: number): (number, number)
		return buffer.readi8(b, offset), offset + 1
	end,

	write = function(b: buffer, offset: number, value: number): number
		buffer.writei8(b, offset, value)
		return offset + 1
	end,
}

return int8
