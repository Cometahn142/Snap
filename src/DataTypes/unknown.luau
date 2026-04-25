--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)
local Refs = require(script.Parent.Parent.Core.Refs)

type DataType<T> = Types.DataType<T>

local unknown: DataType<unknown> = {
	size = 1,

	read = function(b: buffer, offset: number): (unknown, number)
		local index = buffer.readu8(b, offset)
		if index == 0 then
			return nil, offset + 1
		end
		return Refs.get(index), offset + 1
	end,

	write = function(b: buffer, offset: number, value: unknown): number
		if value == nil then
			buffer.writeu8(b, offset, 0)
			return offset + 1
		end
		local index = Refs.push(value)
		buffer.writeu8(b, offset, index)
		return offset + 1
	end,
}

return unknown
