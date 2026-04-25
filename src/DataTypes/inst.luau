--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)
local Refs = require(script.Parent.Parent.Core.Refs)

type DataType<T> = Types.DataType<T>

local inst: DataType<Instance?> = {
	size = 1,

	read = function(b: buffer, offset: number): (Instance?, number)
		local index = buffer.readu8(b, offset)
		if index == 0 then
			return nil, offset + 1
		end
		local value = Refs.get(index)
		if typeof(value) == "Instance" then
			return value, offset + 1
		end
		return nil, offset + 1
	end,

	write = function(b: buffer, offset: number, value: Instance?): number
		if value == nil then
			buffer.writeu8(b, offset, 0)
			return offset + 1
		end
		local index = Refs.push(value)
		buffer.writeu8(b, offset, index)
		return offset + 1
	end,
}

return inst
