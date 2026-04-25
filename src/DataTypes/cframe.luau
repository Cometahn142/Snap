--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)

type DataType<T> = Types.DataType<T>

local cframe: DataType<CFrame> = {
	size = 48,

	read = function(b: buffer, offset: number): (CFrame, number)
		local x = buffer.readf32(b, offset)
		local y = buffer.readf32(b, offset + 4)
		local z = buffer.readf32(b, offset + 8)
		local r00 = buffer.readf32(b, offset + 12)
		local r01 = buffer.readf32(b, offset + 16)
		local r02 = buffer.readf32(b, offset + 20)
		local r10 = buffer.readf32(b, offset + 24)
		local r11 = buffer.readf32(b, offset + 28)
		local r12 = buffer.readf32(b, offset + 32)
		local r20 = buffer.readf32(b, offset + 36)
		local r21 = buffer.readf32(b, offset + 40)
		local r22 = buffer.readf32(b, offset + 44)
		return CFrame.new(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22), offset + 48
	end,

	write = function(b: buffer, offset: number, value: CFrame): number
		local x, y, z,
			r00, r01, r02,
			r10, r11, r12,
			r20, r21, r22 = value:GetComponents()
		buffer.writef32(b, offset, x)
		buffer.writef32(b, offset + 4, y)
		buffer.writef32(b, offset + 8, z)
		buffer.writef32(b, offset + 12, r00)
		buffer.writef32(b, offset + 16, r01)
		buffer.writef32(b, offset + 20, r02)
		buffer.writef32(b, offset + 24, r10)
		buffer.writef32(b, offset + 28, r11)
		buffer.writef32(b, offset + 32, r12)
		buffer.writef32(b, offset + 36, r20)
		buffer.writef32(b, offset + 40, r21)
		buffer.writef32(b, offset + 44, r22)
		return offset + 48
	end,
}

return cframe
