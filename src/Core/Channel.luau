--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)
local Request = require(script.Parent.Request)

type DataType<T> = Types.DataType<T>
type EventDefinition<T> = Types.EventDefinition<T>
type RequestDefinition<Req, Res> = Types.RequestDefinition<Req, Res>
type Reliability = Types.Reliability
type ReliabilityInput = Types.ReliabilityInput
type ChannelDefinition = Types.ChannelDefinition

export type Channel = {
	name: string,
	wireId: number,
	packets: { EventDefinition<any> },
	requests: { [string]: RequestDefinition<any, any> },
	definition: ChannelDefinition,
}

local Channel = {}

local MAX_PACKETS_PER_channel = 256
local MAX_channelS = 256

local definedChannels: { [string]: Channel } = {}
local nextWireId = 0

local function normalizeReliability(input: ReliabilityInput?): Reliability
	if input == nil or input == "R" or input == "Reliable" then
		return "Reliable"
	elseif input == "U" or input == "Unreliable" then
		return "Unreliable"
	end
	error(
		string.format("[Snap] Invalid reliability %q (expected 'R' / 'U' / 'Reliable' / 'Unreliable')", tostring(input)),
		3
	)
end

function Channel.event<T>(schema: DataType<T>, reliability: ReliabilityInput?): EventDefinition<T>
	local schemaSize = schema.size
	local isFixed = type(schemaSize) == "number"
	local fixedSize = if isFixed then schemaSize :: number else 0

	local def: EventDefinition<T> = {
		id = -1,
		name = "",
		schema = schema,
		reliability = normalizeReliability(reliability),
		isFixed = isFixed,
		fixedSize = fixedSize,
	}
	return def
end

function Channel.request<Req, Res>(requestSchema: DataType<Req>, responseSchema: DataType<Res>): RequestDefinition<Req, Res>
	return Request.createDefinition(requestSchema, responseSchema)
end

local function isRequest(entry: any): boolean
	return entry.kind == "request"
end

local function assignPacketId(packets: { EventDefinition<any> }, def: EventDefinition<any>, channelName: string)
	local count = #packets + 1
	if count > MAX_PACKETS_PER_channel then
		error(
			string.format(
				"[Snap] Channel '%s' exceeded maximum of %d packet slots",
				channelName,
				MAX_PACKETS_PER_channel
			),
			2
		)
	end
	def.id = count - 1
	packets[count] = def
end

function Channel.define(name: string, definition: ChannelDefinition): Channel
	local existing = definedChannels[name]
	if existing then
		return existing
	end

	local packets: { EventDefinition<any> } = {}
	local requests: { [string]: RequestDefinition<any, any> } = {}

	for entryName, entry in definition do
		if isRequest(entry) then
			local requestDef = entry :: RequestDefinition<any, any>
			requestDef.name = entryName
			requestDef.request.name = entryName .. ":req"
			requestDef.request.requestName = entryName
			requestDef.response.name = entryName .. ":res"
			requestDef.response.requestName = entryName

			assignPacketId(packets, requestDef.request, name)
			assignPacketId(packets, requestDef.response, name)
			requests[entryName] = requestDef
		else
			local eventDef = entry :: EventDefinition<any>
			eventDef.name = entryName
			assignPacketId(packets, eventDef, name)
		end
	end

	if nextWireId >= MAX_channelS then
		error(string.format("[Snap] Exceeded maximum of %d channels (wire channel ids are u8)", MAX_channelS), 2)
	end
	local wireId = nextWireId
	nextWireId += 1

	local channel: Channel = {
		name = name,
		wireId = wireId,
		packets = packets,
		requests = requests,
		definition = definition,
	}

	definedChannels[name] = channel
	return channel
end

function Channel.getPacketById(ns: Channel, id: number): EventDefinition<any>?
	return ns.packets[id + 1]
end

return Channel




