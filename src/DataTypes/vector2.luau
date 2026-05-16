--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)
type DataType<T> = Types.DataType<T>

local vector2: DataType<Vector2> = {
	size = 8,
	read = function(b: buffer, offset: number): (Vector2, number)
		local x = buffer.readf32(b, offset)
		local y = buffer.readf32(b, offset + 4)
		return Vector2.new(x, y), offset + 8
	end,
	write = function(b: buffer, offset: number, value: Vector2): number
		buffer.writef32(b, offset, value.X)
		buffer.writef32(b, offset + 4, value.Y)
		return offset + 8
	end,
}

return vector2
