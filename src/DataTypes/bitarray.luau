--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)
local Varint = require(script.Parent.Parent.Core.Varint)

type DataType<T> = Types.DataType<T>
local readVarint = Varint.readUnsigned
local writeVarint = Varint.writeUnsigned
local varintSize = Varint.sizeUnsigned
local band = bit32.band
local bor = bit32.bor
local lshift = bit32.lshift

local bitarray: DataType<{ boolean }> = {
	size = function(value: { boolean }): number
		local len = #value
		local bytes = math.ceil(len / 8)
		return varintSize(len) + bytes
	end,
	read = function(b: buffer, offset: number): ({ boolean }, number)
		local len, cur = readVarint(b, offset)
		local result: { boolean } = table.create(len)
		local bytes = math.ceil(len / 8)
		local i = 1
		for byteIndex = 0, bytes - 1 do
			local byte = buffer.readu8(b, cur + byteIndex)
			local remaining = len - (i - 1)
			local count = if remaining > 8 then 8 else remaining
			for bit = 0, count - 1 do
				result[i] = band(byte, lshift(1, bit)) ~= 0
				i += 1
			end
		end
		return result, cur + bytes
	end,
	write = function(b: buffer, offset: number, value: { boolean }): number
		local len = #value
		local cur = writeVarint(b, offset, len)
		local bytes = math.ceil(len / 8)
		local i = 1
		for byteIndex = 0, bytes - 1 do
			local acc = 0
			local remaining = len - (i - 1)
			local count = if remaining > 8 then 8 else remaining
			for bit = 0, count - 1 do
				if value[i] then
					acc = bor(acc, lshift(1, bit))
				end
				i += 1
			end
			buffer.writeu8(b, cur + byteIndex, acc)
		end
		return cur + bytes
	end,
}

return bitarray
