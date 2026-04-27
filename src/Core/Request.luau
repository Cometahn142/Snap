--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)
local Varint = require(script.Parent.Varint)

type DataType<T> = Types.DataType<T>
type EventDefinition<T> = Types.EventDefinition<T>
type RequestDefinition<Req, Res> = Types.RequestDefinition<Req, Res>

export type RequestValue<Req> = {
	corrId: number,
	value: Req,
}

export type ResponseValue<Res> = {
	corrId: number,
	ok: boolean,
	value: Res?,
	err: string?,
}

local writeUnsigned = Varint.writeUnsigned
local readUnsigned = Varint.readUnsigned
local sizeUnsigned = Varint.sizeUnsigned

local Request = {}

local function wrapRequest<Req>(inner: DataType<Req>): DataType<RequestValue<Req>>
	local innerSize = inner.size
	local innerRead = inner.read
	local innerWrite = inner.write
	local innerIsFixed = type(innerSize) == "number"
	local innerFixedSize = if innerIsFixed then innerSize :: number else 0

	return {
		size = function(value: RequestValue<Req>): number
			local total = sizeUnsigned(value.corrId)
			if innerIsFixed then
				return total + innerFixedSize
			end
			return total + (innerSize :: (v: Req) -> number)(value.value)
		end,

		read = function(b: buffer, offset: number): (RequestValue<Req>, number)
			local corrId, cursor = readUnsigned(b, offset)
			local inner_, nextCursor = innerRead(b, cursor)
			return {
				corrId = corrId,
				value = inner_,
			}, nextCursor
		end,

		write = function(b: buffer, offset: number, value: RequestValue<Req>): number
			local cursor = writeUnsigned(b, offset, value.corrId)
			return innerWrite(b, cursor, value.value)
		end,
	}
end

local function wrapResponse<Res>(inner: DataType<Res>): DataType<ResponseValue<Res>>
	local innerSize = inner.size
	local innerRead = inner.read
	local innerWrite = inner.write
	local innerIsFixed = type(innerSize) == "number"
	local innerFixedSize = if innerIsFixed then innerSize :: number else 0

	return {
		size = function(value: ResponseValue<Res>): number
			local total = sizeUnsigned(value.corrId) + 1
			if value.ok then
				if innerIsFixed then
					return total + innerFixedSize
				end
				return total + (innerSize :: (v: Res) -> number)(value.value :: Res)
			end
			local err = value.err or ""
			local len = #err
			return total + sizeUnsigned(len) + len
		end,

		read = function(b: buffer, offset: number): (ResponseValue<Res>, number)
			local corrId, cursor = readUnsigned(b, offset)
			local status = buffer.readu8(b, cursor)
			cursor += 1

			if status == 1 then
				local value, nextCursor = innerRead(b, cursor)
				return {
					corrId = corrId,
					ok = true,
					value = value,
				}, nextCursor
			else
				local len, c1 = readUnsigned(b, cursor)
				local err = buffer.readstring(b, c1, len)
				return {
					corrId = corrId,
					ok = false,
					err = err,
				}, c1 + len
			end
		end,

		write = function(b: buffer, offset: number, value: ResponseValue<Res>): number
			local cursor = writeUnsigned(b, offset, value.corrId)
			if value.ok then
				buffer.writeu8(b, cursor, 1)
				return innerWrite(b, cursor + 1, value.value :: Res)
			else
				buffer.writeu8(b, cursor, 0)
				local err = value.err or ""
				local len = #err
				local c1 = writeUnsigned(b, cursor + 1, len)
				buffer.writestring(b, c1, err)
				return c1 + len
			end
		end,
	}
end

function Request.createDefinition<Req, Res>(
	requestSchema: DataType<Req>,
	responseSchema: DataType<Res>
): RequestDefinition<Req, Res>
	local requestWrapped = wrapRequest(requestSchema)
	local responseWrapped = wrapResponse(responseSchema)

	local request: EventDefinition<any> = {
		id = -1,
		name = "",
		schema = requestWrapped :: any,
		reliability = "Reliable",
		isFixed = false,
		fixedSize = 0,
		requestRole = "request",
		requestName = "",
	}

	local response: EventDefinition<any> = {
		id = -1,
		name = "",
		schema = responseWrapped :: any,
		reliability = "Reliable",
		isFixed = false,
		fixedSize = 0,
		requestRole = "response",
		requestName = "",
	}

	return {
		kind = "request",
		name = "",
		requestSchema = requestSchema,
		responseSchema = responseSchema,
		request = request,
		response = response,
	}
end

return Request





