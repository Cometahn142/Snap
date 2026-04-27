--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)

type DataType<T> = Types.DataType<T>

type AnyDataType = DataType<any>

local function struct(fields: { [string]: AnyDataType }): DataType<{ [string]: any }>
	local names: { string } = {}
	local types: { AnyDataType } = {}
	local n = 0

	local fixedSize = 0
	local allFixed = true

	for fieldName, dt in fields do
		n += 1
		names[n] = fieldName
		types[n] = dt

		local ds = dt.size
		if type(ds) == "number" then
			fixedSize += ds :: number
		else
			allFixed = false
		end
	end

	local sizeFn: number | (value: { [string]: any }) -> number

	if allFixed then
		sizeFn = fixedSize
	else
		sizeFn = function(value: { [string]: any }): number
			local total = fixedSize
			for i = 1, n do
				local ds = types[i].size
				if type(ds) == "function" then
					total += (ds :: (value: any) -> number)(value[names[i]])
				end
			end
			return total
		end
	end

	local fieldCount = n

	local function read(b: buffer, offset: number, target: { [string]: any }?): ({ [string]: any }, number)
		local result: { [string]: any } = target or {}
		local cursor = offset
		for i = 1, fieldCount do
			local value: any
			value, cursor = types[i].read(b, cursor)
			result[names[i]] = value
		end
		return result, cursor
	end

	local function write(b: buffer, offset: number, value: { [string]: any }): number
		local cursor = offset
		for i = 1, n do
			cursor = types[i].write(b, cursor, value[names[i]])
		end
		return cursor
	end

	return {
		size = sizeFn,
		read = read,
		write = write,
	}
end

return struct
