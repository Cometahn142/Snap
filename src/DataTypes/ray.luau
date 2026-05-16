--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)
type DataType<T> = Types.DataType<T>

local ray: DataType<Ray> = {
	size = 24,
	read = function(b: buffer, offset: number): (Ray, number)
		local ox = buffer.readf32(b, offset)
		local oy = buffer.readf32(b, offset + 4)
		local oz = buffer.readf32(b, offset + 8)
		local dx = buffer.readf32(b, offset + 12)
		local dy = buffer.readf32(b, offset + 16)
		local dz = buffer.readf32(b, offset + 20)
		return Ray.new(Vector3.new(ox, oy, oz), Vector3.new(dx, dy, dz)), offset + 24
	end,
	write = function(b: buffer, offset: number, value: Ray): number
		buffer.writef32(b, offset, value.Origin.X)
		buffer.writef32(b, offset + 4, value.Origin.Y)
		buffer.writef32(b, offset + 8, value.Origin.Z)
		buffer.writef32(b, offset + 12, value.Direction.X)
		buffer.writef32(b, offset + 16, value.Direction.Y)
		buffer.writef32(b, offset + 20, value.Direction.Z)
		return offset + 24
	end,
}

return ray
