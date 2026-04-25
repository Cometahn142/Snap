--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)
local Varint = require(script.Parent.Parent.Core.Varint)

type DataType<T> = Types.DataType<T>

local writeVarint = Varint.writeUnsigned
local readVarint = Varint.readUnsigned
local varintSize = Varint.sizeUnsigned

local function map<K, V>(key: DataType<K>, value: DataType<V>): DataType<{ [K]: V }>
	local keySize = key.size
	local keyRead = key.read
	local keyWrite = key.write
	local keyIsFixed = type(keySize) == "number"
	local keyFixedSize = if keyIsFixed then keySize :: number else 0

	local valueSize = value.size
	local valueRead = value.read
	local valueWrite = value.write
	local valueIsFixed = type(valueSize) == "number"
	local valueFixedSize = if valueIsFixed then valueSize :: number else 0

	local function sizeFn(tbl: { [K]: V }): number
		local count = 0
		local total = 0

		if keyIsFixed and valueIsFixed then
			for _ in tbl do
				count += 1
			end
			total = keyFixedSize * count + valueFixedSize * count
		else
			local keyFn = if keyIsFixed then nil else keySize :: (v: K) -> number
			local valueFn = if valueIsFixed then nil else valueSize :: (v: V) -> number
			for k, v in tbl do
				count += 1
				total += if keyFn then keyFn(k) else keyFixedSize
				total += if valueFn then valueFn(v) else valueFixedSize
			end
		end

		return varintSize(count) + total
	end

	local function read(b: buffer, offset: number): ({ [K]: V }, number)
		local count, cursor = readVarint(b, offset)
		local result: { [K]: V } = {}
		for _ = 1, count do
			local k: K
			local v: V
			k, cursor = keyRead(b, cursor)
			v, cursor = valueRead(b, cursor)
			result[k] = v
		end
		return result, cursor
	end

	local function write(b: buffer, offset: number, tbl: { [K]: V }): number
		local reserved = 5
		local payloadStart = offset + reserved
		local cursor = payloadStart
		local count = 0
		for k, v in tbl do
			count += 1
			cursor = keyWrite(b, cursor, k)
			cursor = valueWrite(b, cursor, v)
		end
		local actualLen = varintSize(count)
		writeVarint(b, offset, count)
		if actualLen ~= reserved then
			buffer.copy(b, offset + actualLen, b, payloadStart, cursor - payloadStart)
			cursor -= (reserved - actualLen)
		end
		return cursor
	end

	return {
		size = sizeFn,
		read = read,
		write = write,
	}
end

return map
