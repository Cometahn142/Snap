--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)

type DataType<T> = Types.DataType<T>

local vector3: DataType<Vector3> = {
	size = 12,

	read = function(b: buffer, offset: number): (Vector3, number)
		local x = buffer.readf32(b, offset)
		local y = buffer.readf32(b, offset + 4)
		local z = buffer.readf32(b, offset + 8)
		return Vector3.new(x, y, z), offset + 12
	end,

	write = function(b: buffer, offset: number, value: Vector3): number
		buffer.writef32(b, offset, value.X)
		buffer.writef32(b, offset + 4, value.Y)
		buffer.writef32(b, offset + 8, value.Z)
		return offset + 12
	end,
}

return vector3
