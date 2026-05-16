--!strict
--!native
--!optimize 2

local Varint = {}

function Varint.sizeUnsigned(value: number): number
	if value < 128 then
		return 1
	elseif value < 16384 then
		return 2
	elseif value < 2097152 then
		return 3
	elseif value < 268435456 then
		return 4
	end
	return 5
end

function Varint.writeUnsigned(b: buffer, offset: number, value: number): number
	if value < 128 then
		buffer.writeu8(b, offset, value)
		return offset + 1
	end
	while value >= 128 do
		buffer.writeu8(b, offset, bit32.bor(bit32.band(value, 0x7F), 0x80))
		offset += 1
		value = bit32.rshift(value, 7)
	end
	buffer.writeu8(b, offset, value)
	return offset + 1
end

function Varint.readUnsigned(b: buffer, offset: number): (number, number)
	local byte = buffer.readu8(b, offset)
	if byte < 128 then
		return byte, offset + 1
	end
	local value = bit32.band(byte, 0x7F)
	local shift = 7
	offset += 1
	while true do
		byte = buffer.readu8(b, offset)
		offset += 1
		value = bit32.bor(value, bit32.lshift(bit32.band(byte, 0x7F), shift))
		if byte < 128 then
			return value, offset
		end
		shift += 7
	end
end

local function zigZagEncode(value: number): number
	if value >= 0 then
		return value * 2
	end
	return -value * 2 - 1
end

local function zigZagDecode(value: number): number
	if value % 2 == 0 then
		return value * 0.5
	end
	return -(value + 1) * 0.5
end

function Varint.sizeSigned(value: number): number
	return Varint.sizeUnsigned(zigZagEncode(value))
end

function Varint.writeSigned(b: buffer, offset: number, value: number): number
	return Varint.writeUnsigned(b, offset, zigZagEncode(value))
end

function Varint.readSigned(b: buffer, offset: number): (number, number)
	local u, nextOffset = Varint.readUnsigned(b, offset)
	return zigZagDecode(u), nextOffset
end

return Varint





