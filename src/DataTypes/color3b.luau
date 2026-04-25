--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)

type DataType<T> = Types.DataType<T>

local function quantize(v: number): number
	if v <= 0 then
		return 0
	end
	if v >= 1 then
		return 255
	end
	return math.floor(v * 255 + 0.5)
end

local INV_255 = 1 / 255

local color3b: DataType<Color3> = {
	size = 3,

	read = function(b: buffer, offset: number): (Color3, number)
		local r = buffer.readu8(b, offset) * INV_255
		local g = buffer.readu8(b, offset + 1) * INV_255
		local bl = buffer.readu8(b, offset + 2) * INV_255
		return Color3.new(r, g, bl), offset + 3
	end,

	write = function(b: buffer, offset: number, value: Color3): number
		buffer.writeu8(b, offset, quantize(value.R))
		buffer.writeu8(b, offset + 1, quantize(value.G))
		buffer.writeu8(b, offset + 2, quantize(value.B))
		return offset + 3
	end,
}

return color3b
