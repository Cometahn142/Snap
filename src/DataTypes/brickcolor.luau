--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)
type DataType<T> = Types.DataType<T>

local brickcolor: DataType<BrickColor> = {
	size = 2,
	read = function(b: buffer, offset: number): (BrickColor, number)
		local num = buffer.readu16(b, offset)
		return BrickColor.new(num), offset + 2
	end,
	write = function(b: buffer, offset: number, value: BrickColor): number
		buffer.writeu16(b, offset, value.Number)
		return offset + 2
	end,
}

return brickcolor
