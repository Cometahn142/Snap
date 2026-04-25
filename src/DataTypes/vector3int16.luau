--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)

type DataType<T> = Types.DataType<T>

local vector3int16: DataType<Vector3int16> = {
	size = 6,

	read = function(b: buffer, offset: number): (Vector3int16, number)
		local x = buffer.readi16(b, offset)
		local y = buffer.readi16(b, offset + 2)
		local z = buffer.readi16(b, offset + 4)
		return Vector3int16.new(x, y, z), offset + 6
	end,

	write = function(b: buffer, offset: number, value: Vector3int16): number
		buffer.writei16(b, offset, value.X)
		buffer.writei16(b, offset + 2, value.Y)
		buffer.writei16(b, offset + 4, value.Z)
		return offset + 6
	end,
}

return vector3int16
