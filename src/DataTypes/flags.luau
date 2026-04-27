--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)

type DataType<T> = Types.DataType<T>

local band = bit32.band
local bor = bit32.bor
local lshift = bit32.lshift

local MAX_FLAGS = 64

local function flags(names: { string }): DataType<{ [string]: boolean }>
	local n = #names
	if n == 0 then
		error("[Snap] flags() requires at least one name", 2)
	end
	if n > MAX_FLAGS then
		error(string.format("[Snap] flags() supports up to %d names, got %d", MAX_FLAGS, n), 2)
	end

	local byteCount = math.ceil(n / 8)
	local namesCopy: { string } = table.clone(names)

	local function read(b: buffer, offset: number): ({ [string]: boolean }, number)
		local result: { [string]: boolean } = {}
		local i = 1
		for byteIndex = 0, byteCount - 1 do
			local byte = buffer.readu8(b, offset + byteIndex)
			local remaining = n - (i - 1)
			local count = if remaining > 8 then 8 else remaining
			for bit = 0, count - 1 do
				result[namesCopy[i]] = band(byte, lshift(1, bit)) ~= 0
				i += 1
			end
		end
		return result, offset + byteCount
	end

	local function write(b: buffer, offset: number, value: { [string]: boolean }): number
		for byteIndex = 0, byteCount - 1 do
			local base = byteIndex * 8
			local acc = 0
			local remaining = n - base
			local count = if remaining > 8 then 8 else remaining
			for bit = 0, count - 1 do
				if value[namesCopy[base + bit + 1]] then
					acc = bor(acc, lshift(1, bit))
				end
			end
			buffer.writeu8(b, offset + byteIndex, acc)
		end
		return offset + byteCount
	end

	return {
		size = byteCount,
		read = read,
		write = write,
	}
end

return flags
