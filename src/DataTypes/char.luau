--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)

type DataType<T> = Types.DataType<T>

local char: DataType<string> = {
	size = 1,

	read = function(b: buffer, offset: number): (string, number)
		return buffer.readstring(b, offset, 1), offset + 1
	end,

	write = function(b: buffer, offset: number, value: string): number
		buffer.writeu8(b, offset, string.byte(value, 1) or 0)
		return offset + 1
	end,
}

return char
