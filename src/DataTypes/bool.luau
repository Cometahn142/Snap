--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)

type DataType<T> = Types.DataType<T>

local bool: DataType<boolean> = {
	size = 1,

	read = function(b: buffer, offset: number): (boolean, number)
		return buffer.readu8(b, offset) ~= 0, offset + 1
	end,

	write = function(b: buffer, offset: number, value: boolean): number
		buffer.writeu8(b, offset, if value then 1 else 0)
		return offset + 1
	end,
}

return bool
