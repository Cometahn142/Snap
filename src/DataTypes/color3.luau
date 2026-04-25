--!strict
--!native
--!optimize 2

--[[
	Color3 (3 × f32 = 12B). 정밀한 색상 (HDR 포함) 필요 시 사용.
	일반적인 UI/게임 색상이라면 color3b(3B)가 압도적으로 효율적.
]]

local Types = require(script.Parent.Parent.Types)

type DataType<T> = Types.DataType<T>

local color3: DataType<Color3> = {
	size = 12,

	read = function(b: buffer, offset: number): (Color3, number)
		local r = buffer.readf32(b, offset)
		local g = buffer.readf32(b, offset + 4)
		local bl = buffer.readf32(b, offset + 8)
		return Color3.new(r, g, bl), offset + 12
	end,

	write = function(b: buffer, offset: number, value: Color3): number
		buffer.writef32(b, offset, value.R)
		buffer.writef32(b, offset + 4, value.G)
		buffer.writef32(b, offset + 8, value.B)
		return offset + 12
	end,
}

return color3
