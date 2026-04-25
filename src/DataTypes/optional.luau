--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)

type DataType<T> = Types.DataType<T>

local function optional<T>(inner: DataType<T>): DataType<T?>
	local innerSize = inner.size
	local innerRead = inner.read
	local innerWrite = inner.write
	local innerIsFixed = type(innerSize) == "number"
	local innerFixedSize = if innerIsFixed then innerSize :: number else 0

	local function sizeFn(value: T?): number
		if value == nil then
			return 1
		end
		if innerIsFixed then
			return 1 + innerFixedSize
		end
		return 1 + (innerSize :: (value: T) -> number)(value :: T)
	end

	local function read(b: buffer, offset: number): (T?, number)
		local flag = buffer.readu8(b, offset)
		if flag == 0 then
			return nil, offset + 1
		end
		return innerRead(b, offset + 1)
	end

	local function write(b: buffer, offset: number, value: T?): number
		if value == nil then
			buffer.writeu8(b, offset, 0)
			return offset + 1
		end
		buffer.writeu8(b, offset, 1)
		return innerWrite(b, offset + 1, value :: T)
	end

	return {
		size = sizeFn,
		read = read,
		write = write,
	}
end

return optional
