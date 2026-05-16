--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)
type DataType<T> = Types.DataType<T>

local datetime: DataType<DateTime> = {
	size = 8,
	read = function(b: buffer, offset: number): (DateTime, number)
		local unixMs = buffer.readf64(b, offset)
		return DateTime.fromUnixTimestampMillis(unixMs), offset + 8
	end,
	write = function(b: buffer, offset: number, value: DateTime): number
		buffer.writef64(b, offset, value.UnixTimestampMillis)
		return offset + 8
	end,
}

return datetime
