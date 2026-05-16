--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)
type DataType<T> = Types.DataType<T>

local vector2int16: DataType<Vector2int16> = {
	size = 4,
	read = function(b: buffer, offset: number): (Vector2int16, number)
		local x = buffer.readi16(b, offset)
		local y = buffer.readi16(b, offset + 2)
		return Vector2int16.new(x, y), offset + 4
	end,
	write = function(b: buffer, offset: number, value: Vector2int16): number
		buffer.writei16(b, offset, value.X)
		buffer.writei16(b, offset + 2, value.Y)
		return offset + 4
	end,
}

return vector2int16
