--!strict
--!native
--!optimize 2

local Settings = require(script.Parent.Parent.Settings)
local Types = require(script.Parent.Parent.Types)
local BufferWriter = require(script.Parent.BufferWriter)
local Refs = require(script.Parent.Refs)
local Varint = require(script.Parent.Varint)

type EventDefinition<T> = Types.EventDefinition<T>

local OMIT_FIXED_LENGTH = Settings.OMIT_FIXED_LENGTH
local OMIT_OUTER_LENGTH_PREFIX = Settings.OMIT_OUTER_LENGTH_PREFIX
local VALIDATE_FRAMES = Settings.VALIDATE_FRAMES
local USE_XPCALL = Settings.USE_XPCALL

local MAX_PAYLOAD_SIZE = 65535

type WriterLike = {
	buffer: buffer,
	capacity: number,
	cursor: number,
	refs: { any },
	refsLookup: { [any]: number },
	reserve: (self: WriterLike, additional: number) -> (),
}

type ChannelLike = {
	name: string,
	packets: { EventDefinition<any> },
}

local Frame = {}

local writeVarint = Varint.writeUnsigned
local readVarint = Varint.readUnsigned
local varintSize = Varint.sizeUnsigned

Frame.writeVarint = writeVarint
Frame.readVarint = readVarint
Frame.varintSize = varintSize

local function appendPacketImpl<T>(writer: WriterLike, definition: EventDefinition<T>, value: T)
	local schema = definition.schema

	if definition.isFixed then
		local payloadSize = definition.fixedSize

		if OMIT_FIXED_LENGTH then
			if writer.cursor + 1 + payloadSize > writer.capacity then
				writer:reserve(1 + payloadSize)
			end
			local b = writer.buffer
			local c = writer.cursor
			buffer.writeu8(b, c, definition.id)
			schema.write(b, c + 1, value)
			writer.cursor = c + 1 + payloadSize
			return
		else
			if writer.cursor + 3 + payloadSize > writer.capacity then
				writer:reserve(3 + payloadSize)
			end
			local b = writer.buffer
			local c = writer.cursor
			buffer.writeu8(b, c, definition.id)
			buffer.writeu16(b, c + 1, payloadSize)
			schema.write(b, c + 3, value)
			writer.cursor = c + 3 + payloadSize
			return
		end
	end

	local payloadSize: number = (schema.size :: any)(value)

	if OMIT_FIXED_LENGTH and OMIT_OUTER_LENGTH_PREFIX then
		if writer.cursor + 1 + payloadSize > writer.capacity then
			writer:reserve(1 + payloadSize)
		end
		local b = writer.buffer
		local c = writer.cursor
		buffer.writeu8(b, c, definition.id)
		schema.write(b, c + 1, value)
		writer.cursor = c + 1 + payloadSize
		return
	end

	if OMIT_FIXED_LENGTH then
		local sizeBytes = varintSize(payloadSize)
		if writer.cursor + 1 + sizeBytes + payloadSize > writer.capacity then
			writer:reserve(1 + sizeBytes + payloadSize)
		end
		local b = writer.buffer
		local c = writer.cursor
		buffer.writeu8(b, c, definition.id)
		c = writeVarint(b, c + 1, payloadSize)
		schema.write(b, c, value)
		writer.cursor = c + payloadSize
		return
	end

	if payloadSize > MAX_PAYLOAD_SIZE then
		error(
			string.format(
				"[Snap] Packet '%s' payload size %d exceeds maximum %d",
				definition.name,
				payloadSize,
				MAX_PAYLOAD_SIZE
			),
			2
		)
	end

	if writer.cursor + 3 + payloadSize > writer.capacity then
		writer:reserve(3 + payloadSize)
	end
	local b = writer.buffer
	local c = writer.cursor
	buffer.writeu8(b, c, definition.id)
	buffer.writeu16(b, c + 1, payloadSize)
	schema.write(b, c + 3, value)
	writer.cursor = c + 3 + payloadSize
end

Frame.appendPacketImpl = appendPacketImpl

if USE_XPCALL then
	function Frame.appendPacket<T>(writer: WriterLike, definition: EventDefinition<T>, value: T)
		local savedCursor = writer.cursor
		local savedRefsLen = #writer.refs

		Refs.beginWrite(writer.refs, writer.refsLookup)

		local ok, err: any = pcall(appendPacketImpl, writer, definition, value)

		Refs.endWrite()

		if not ok then
			writer.cursor = savedCursor
			local refs = writer.refs
			local lookup = writer.refsLookup
			for i = #refs, savedRefsLen + 1, -1 do
				lookup[refs[i]] = nil
				refs[i] = nil
			end
			error(err, 2)
		end
	end
else
	function Frame.appendPacket<T>(writer: WriterLike, definition: EventDefinition<T>, value: T)
		Refs.beginWrite(writer.refs, writer.refsLookup)
		appendPacketImpl(writer, definition, value)
		Refs.endWrite()
	end
end

local sharedWriter = BufferWriter.new(4096) :: any

function Frame.encodeShared<T>(definition: EventDefinition<T>, value: T): (buffer?, number)
	sharedWriter.cursor = 0
	if #sharedWriter.refs > 0 then
		table.clear(sharedWriter.refs)
		table.clear(sharedWriter.refsLookup :: any)
	end

	Refs.beginWrite(sharedWriter.refs, sharedWriter.refsLookup)
	local ok, err: any = pcall(appendPacketImpl, sharedWriter, definition, value)
	Refs.endWrite()

	if not ok then
		error(err, 2)
	end

	if #sharedWriter.refs > 0 then
		return nil, 0
	end

	return sharedWriter.buffer, sharedWriter.cursor
end

function Frame.appendRaw(writer: WriterLike, source: buffer, length: number)
	if writer.cursor + length > writer.capacity then
		writer:reserve(length)
	end
	buffer.copy(writer.buffer, writer.cursor, source, 0, length)
	writer.cursor += length
end

if not OMIT_FIXED_LENGTH then
	function Frame.decode(
		channel: ChannelLike,
		frameBuffer: buffer,
		onPacket: (definition: EventDefinition<any>, payloadBuffer: buffer, payloadOffset: number) -> ()
	)
		local length = buffer.len(frameBuffer)
		local cursor = 0
		local packets = channel.packets

		while cursor < length do
			if VALIDATE_FRAMES and cursor + 3 > length then
				warn(string.format("[Snap] Truncated header in channel '%s'", channel.name))
				return
			end

			local packetId = buffer.readu8(frameBuffer, cursor)
			local size = buffer.readu16(frameBuffer, cursor + 1)
			cursor += 3

			if VALIDATE_FRAMES and cursor + size > length then
				warn(
					string.format(
						"[Snap] Malformed payload for packet id=%d in channel '%s' (claims %d bytes)",
						packetId,
						channel.name,
						size
					)
				)
				return
			end

			local def = packets[packetId + 1]
			if def then
				onPacket(def, frameBuffer, cursor)
			else
				warn(
					string.format("[Snap] Unknown packet id %d in channel '%s' (skipping)", packetId, channel.name)
				)
			end

			cursor += size
		end
	end
end

return Frame
