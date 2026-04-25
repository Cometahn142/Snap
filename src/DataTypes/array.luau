--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)
local Varint = require(script.Parent.Parent.Core.Varint)

type DataType<T> = Types.DataType<T>

local writeVarint = Varint.writeUnsigned
local readVarint = Varint.readUnsigned
local varintSize = Varint.sizeUnsigned

local function array<T>(element: DataType<T>): DataType<{ T }>
	local elementSize = element.size
	local elementRead = element.read
	local elementWrite = element.write
	local elementIsFixed = type(elementSize) == "number"
	local elementFixedSize = if elementIsFixed then elementSize :: number else 0

	local function sizeFn(value: { T }): number
		local count = #value
		local total = varintSize(count)

		if elementIsFixed then
			total += elementFixedSize * count
		else
			local fn = elementSize :: (value: T) -> number
			for i = 1, count do
				total += fn(value[i])
			end
		end
		return total
	end

	local function read(b: buffer, offset: number): ({ T }, number)
		local count, cursor = readVarint(b, offset)
		local result = table.create(count)
		for i = 1, count do
			local v: T
			v, cursor = elementRead(b, cursor)
			result[i] = v
		end
		return result, cursor
	end

	local function write(b: buffer, offset: number, value: { T }): number
		local count = #value
		local cursor = writeVarint(b, offset, count)
		for i = 1, count do
			cursor = elementWrite(b, cursor, value[i])
		end
		return cursor
	end

	return {
		size = sizeFn,
		read = read,
		write = write,
	}
end

return array
