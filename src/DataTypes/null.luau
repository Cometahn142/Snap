--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)

type DataType<T> = Types.DataType<T>

local null: DataType<nil> = {
	size = 0,

	read = function(_b: buffer, offset: number): (nil, number)
		return nil, offset
	end,

	write = function(_b: buffer, offset: number, _value: nil): number
		return offset
	end,
}

return null
