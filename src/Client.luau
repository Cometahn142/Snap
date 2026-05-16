--!strict
--!native
--!optimize 2

local RunService = game:GetService("RunService")

local Root = script.Parent
local Core = Root.Core
local BufferWriter = require(Core.BufferWriter)
local Frame = require(Core.Frame)
local Guard = require(Core.Guard)
local Request = require(Core.Request)
local Channel = require(Core.Channel)
local FastDefer = require(Core.FastDefer)
local Signify = require(Root.Packages.Signify)
local Bandwidth = require(Core.Bandwidth)
local Refs = require(Core.Refs)
local Transport = require(Core.Transport)
local Settings = require(Root.Settings)
local Types = require(Root.Types)

type BufferWriter = BufferWriter.BufferWriter
type ChannelInternal = Channel.Channel
type EventDefinition<T> = Types.EventDefinition<T>
type RequestDefinition<Req, Res> = Types.RequestDefinition<Req, Res>
type ClientEvent<T> = Types.ClientEvent<T>
type ClientRequest<Req, Res> = Types.ClientRequest<Req, Res>
type ChannelDefinition = Types.ChannelDefinition
type TransportPair = Transport.TransportPair
type Reliability = Types.Reliability
type PlayerGuardState = Guard.PlayerGuardState
type RequestValue<Req> = Request.RequestValue<Req>
type ResponseValue<Res> = Request.ResponseValue<Res>

type RequestHandler = (value: any) -> any

type PendingRequest = {
	thread: thread,
	startedAt: number,
	requestName: string,
}

type RuntimeState = {
	channel: ChannelInternal,
	transport: TransportPair,
	signifies: { [number]: any },
	RequestHandlers: { [string]: RequestHandler },

	reliableQueue: BufferWriter,
	unreliableQueue: BufferWriter,

	guardState: PlayerGuardState,

	pendingRequests: { [number]: PendingRequest },
	hasPendingRequests: boolean,
	nextCorrId: number,

	_dispatchFrame: any,
}

local GUARD_ENABLED = Guard.ENABLED
local REQUEST_TIMEOUT = Settings.GUARD.REQUEST_TIMEOUT
local EARLY_FLUSH_ENABLED = Settings.EARLY_FLUSH_ENABLED
local EARLY_FLUSH_REQUEST_ONLY = Settings.EARLY_FLUSH_REQUEST_ONLY
local OMIT_OUTER_LENGTH_PREFIX = Settings.OMIT_OUTER_LENGTH_PREFIX
local BANDWIDTH_TRACKING = Settings.BANDWIDTH_TRACKING
local readVarint = Frame.readVarint

local Client = {}

local runtimeByName: { [string]: RuntimeState } = {}
local runtimeByWireId: { [number]: RuntimeState } = {}
local globalClientReceiveConnected = false
local heartbeatConnected = false
local flushAll: () -> ()
local requestEarlyFlush: () -> ()
local EARLY_FLUSH_KEY = "snap_client_flush"

local clientPendingPool: { PendingRequest } = {}

local function acquireClientPending(thread: thread, startedAt: number, requestName: string): PendingRequest
	local pending = table.remove(clientPendingPool)
	if pending then
		pending.thread = thread
		pending.startedAt = startedAt
		pending.requestName = requestName
		return pending
	else
		return {
			thread = thread,
			startedAt = startedAt,
			requestName = requestName,
		}
	end
end

local function releaseClientPending(pending: PendingRequest)
	table.clear(pending :: any)
	table.insert(clientPendingPool, pending)
end

local function assertClient()
	if not RunService:IsClient() then
		error("[Snap] Client API must be used on the client", 3)
	end
end

local function sendFrame(remote: RemoteEvent | UnreliableRemoteEvent, writer: BufferWriter, wireId: number)
	local wire = writer:finalizeWithWireId(wireId)
	local refs = if #writer.refs > 0 then writer.refs else nil
	writer:reset()
	if BANDWIDTH_TRACKING then
		Bandwidth.recordOut(buffer.len(wire))
	end
	if refs then
		(remote :: any):FireServer(wire, refs)
	else
		(remote :: any):FireServer(wire)
	end
end

local function flush(runtime: RuntimeState)
	local transport = runtime.transport
	local wireId = runtime.channel.wireId

	local rq = runtime.reliableQueue
	if rq.cursor > 0 then
		sendFrame(transport.reliable, rq, wireId)
	end

	local uq = runtime.unreliableQueue
	if uq.cursor > 0 then
		sendFrame(transport.unreliable, uq, wireId)
	end
end

local function resumeRequestWaiter(thread: thread, ok: boolean, value: any)
	local resumeOk, err = coroutine.resume(thread, ok, value)
	if not resumeOk then
		warn(string.format("[Snap] Failed to resume request waiter: %s", tostring(err)))
	end
end

local function sweepTimeouts(runtime: RuntimeState, now: number)
	if not runtime.hasPendingRequests then
		return
	end

	local pendingRequests = runtime.pendingRequests
	local guardState = runtime.guardState
	local deadlineCutoff = now - REQUEST_TIMEOUT
	local stillHas = false

	for corrId, pending in pendingRequests do
		if pending.startedAt <= deadlineCutoff then
			pendingRequests[corrId] = nil
			guardState.pendingRequests = math.max(0, guardState.pendingRequests - 1)
			resumeRequestWaiter(pending.thread, false, "timeout")
			releaseClientPending(pending)
		else
			stillHas = true
		end
	end

	runtime.hasPendingRequests = stillHas
end

function flushAll()
	local now = os.clock()
	for _, runtime in runtimeByName do
		sweepTimeouts(runtime, now)
		flush(runtime)
	end
end

local function runEarlyFlush()
	flushAll()
end

function requestEarlyFlush()
	if not EARLY_FLUSH_ENABLED then
		return
	end
	FastDefer.defer(EARLY_FLUSH_KEY, runEarlyFlush)
end

local function requestFlush()
	if EARLY_FLUSH_REQUEST_ONLY then
		requestEarlyFlush()
	end
end

local function ensureHeartbeat()
	if heartbeatConnected then
		return
	end
	heartbeatConnected = true
	RunService.Heartbeat:Connect(flushAll)
end

local function allocateCorrId(runtime: RuntimeState): number
	local current = runtime.nextCorrId
	local next_ = current + 1
	if next_ >= 4294967295 then
		next_ = 1
	end
	runtime.nextCorrId = next_
	return current
end

local function sendRequestResponse(
	runtime: RuntimeState,
	responseDef: EventDefinition<any>,
	responseValue: ResponseValue<any>
)
	Frame.appendPacket(runtime.reliableQueue, responseDef, responseValue)
	requestFlush()
end

local function handleRequestRequest(runtime: RuntimeState, def: EventDefinition<any>, decoded: RequestValue<any>)
	local requestName = def.requestName
	if not requestName then
		return
	end

	local requestDef = runtime.channel.requests[requestName]
	if not requestDef then
		return
	end

	local handler = runtime.RequestHandlers[requestName]
	if not handler then
		sendRequestResponse(runtime, requestDef.response, {
			corrId = decoded.corrId,
			ok = false,
			err = "no handler",
		})
		return
	end

	local ok, result = pcall(handler, decoded.value)
	if ok then
		sendRequestResponse(runtime, requestDef.response, {
			corrId = decoded.corrId,
			ok = true,
			value = result,
		})
	else
		sendRequestResponse(runtime, requestDef.response, {
			corrId = decoded.corrId,
			ok = false,
			err = tostring(result),
		})
	end
end

local function handleRequestResponse(runtime: RuntimeState, decoded: ResponseValue<any>)
	local pending = runtime.pendingRequests[decoded.corrId]
	if not pending then
		return
	end

	runtime.pendingRequests[decoded.corrId] = nil

	runtime.guardState.pendingRequests = math.max(0, runtime.guardState.pendingRequests - 1)

	if decoded.ok then
		resumeRequestWaiter(pending.thread, true, decoded.value)
	else
		resumeRequestWaiter(pending.thread, false, decoded.err)
	end

	releaseClientPending(pending)
end

local function dispatchPacket(runtime: RuntimeState, def: EventDefinition<any>, decodedValue: any)
	local role = def.requestRole
	if role == "request" then
		handleRequestRequest(runtime, def, decodedValue :: RequestValue<any>)
	elseif role == "response" then
		handleRequestResponse(runtime, decodedValue :: ResponseValue<any>)
	else
		local signify = runtime.signifies[def.id]
		if signify then
			signify:Fire(decodedValue)
		end
	end
end

local function ensureGlobalClientReceive()
	if globalClientReceiveConnected then
		return
	end
	globalClientReceiveConnected = true
	local transport = Transport.getGlobalTransport()

	local function onWire(wire: any, refs: any)
		if typeof(wire) ~= "buffer" then
			return
		end
		local wireLen = buffer.len(wire)
		if wireLen < Transport.HEADER_SIZE + 1 then
			return
		end
		local channelId, offset = Transport.unwrapFrame(wire)
		if channelId == nil or offset == nil then
			return
		end
		local runtime = runtimeByWireId[channelId]
		if not runtime then
			Guard.report(nil, "?", "unknownPacket", string.format("unknown channel wire id %d", channelId), nil)
			return
		end
		local channel = runtime.channel
		local guardState = runtime.guardState
		if GUARD_ENABLED and not Guard.checkFrame(guardState, wire, nil, channel.name) then
			return
		end
		if BANDWIDTH_TRACKING then
			Bandwidth.recordIn(wireLen)
		end
		local dispatch = runtime._dispatchFrame :: any
		local ok, err: any = pcall(dispatch, wire, offset, refs)
		if not ok then
			warn(string.format("[Snap] Frame dispatch failure in channel '%s': %s", channel.name, tostring(err)))
		end
	end

	transport.reliable.OnClientEvent:Connect(onWire)
	transport.unreliable.OnClientEvent:Connect(onWire)
end

local function setupReceive(runtime: RuntimeState)
	local channel = runtime.channel
	local packets = channel.packets

	if Settings.USE_XPCALL then
		runtime._dispatchFrame = function(wire: buffer, offset: number, refs: any)
			local guardState = runtime.guardState

			Refs.beginRead(if typeof(refs) == "table" then refs else nil)

			local decodeOk, decodeErr: any = pcall(
				Frame.decode,
				channel,
				wire,
				offset,
				function(def, payloadBuffer, payloadOffset)
					if GUARD_ENABLED then
						if def.requestRole == "request" then
							if not Guard.accountRequest(guardState, nil, channel.name) then
								return
							end
						end
						if not Guard.accountPacket(guardState, nil, channel.name) then
							return
						end
					end

					local packetName = def.name
					local ok, val1, _val2 = pcall(def.schema.read, payloadBuffer, payloadOffset)
					if not ok then
						warn(
							string.format(
								"[Snap] Failed to decode packet '%s': %s",
								packetName,
								tostring(val1)
							)
						)
						return
					end

					dispatchPacket(runtime, def, val1)
				end
			)

			Refs.endRead()

			if not decodeOk then
				warn(
					string.format("[Snap] Frame decode failure in channel '%s': %s", channel.name, tostring(decodeErr))
				)
			end
		end
	else
		local function decodeFast(frame: buffer, startOffset: number, guardState: PlayerGuardState)
			local length = buffer.len(frame)
			local cursor = startOffset

			while cursor < length do
				local packetId = buffer.readu8(frame, cursor)
				cursor += 1

				local def = packets[packetId + 1]
				if not def then
					Guard.report(
						nil,
						channel.name,
						"unknownPacket",
						string.format("id=%d at offset %d (remaining frame dropped)", packetId, cursor - 1),
						guardState
					)
					break
				end

				if def.isFixed then
					local payloadOffset = cursor
					local payloadSize = def.fixedSize

					if cursor + payloadSize > length then
						Guard.report(
							nil,
							channel.name,
							"malformedFrame",
							string.format(
								"packet '%s' claims %d bytes but only %d remain",
								def.name,
								payloadSize,
								length - cursor
							),
							guardState
						)
						break
					end

					if GUARD_ENABLED then
						if def.requestRole == "request" then
							if not Guard.accountRequest(guardState, nil, channel.name) then
								cursor += payloadSize
								continue
							end
						end
						if not Guard.accountPacket(guardState, nil, channel.name) then
							cursor += payloadSize
							continue
						end
					end

					local decodedValue = (def.schema.read(frame, payloadOffset))
					dispatchPacket(runtime, def, decodedValue)
					cursor += payloadSize
				elseif OMIT_OUTER_LENGTH_PREFIX then
					local payloadOffset = cursor
					local decodedValue: any
					local nextCursor: number
					decodedValue, nextCursor = def.schema.read(frame, payloadOffset)
					if nextCursor > length or nextCursor < payloadOffset then
						Guard.report(
							nil,
							channel.name,
							"malformedFrame",
							string.format("packet '%s' read past frame (%d > %d)", def.name, nextCursor, length),
							guardState
						)
						break
					end

					if GUARD_ENABLED then
						if def.requestRole == "request" then
							if not Guard.accountRequest(guardState, nil, channel.name) then
								cursor = nextCursor
								continue
							end
						end
						if not Guard.accountPacket(guardState, nil, channel.name) then
							cursor = nextCursor
							continue
						end
					end

					dispatchPacket(runtime, def, decodedValue)
					cursor = nextCursor
				else
					local size, nextCursor = readVarint(frame, cursor)
					local payloadOffset = nextCursor
					local payloadSize = size
					cursor = nextCursor

					if cursor + payloadSize > length then
						Guard.report(
							nil,
							channel.name,
							"malformedFrame",
							string.format(
								"packet '%s' claims %d bytes but only %d remain",
								def.name,
								payloadSize,
								length - cursor
							),
							guardState
						)
						break
					end

					if GUARD_ENABLED then
						if def.requestRole == "request" then
							if not Guard.accountRequest(guardState, nil, channel.name) then
								cursor += payloadSize
								continue
							end
						end
						if not Guard.accountPacket(guardState, nil, channel.name) then
							cursor += payloadSize
							continue
						end
					end

					local decodedValue = (def.schema.read(frame, payloadOffset))
					dispatchPacket(runtime, def, decodedValue)
					cursor += payloadSize
				end
			end
		end

		runtime._dispatchFrame = function(wire: buffer, offset: number, refs: any)
			local guardState = runtime.guardState
			Refs.beginRead(if typeof(refs) == "table" then refs else nil)
			local ok, err: any = pcall(decodeFast, wire, offset, guardState)
			Refs.endRead()

			if not ok then
				warn(string.format("[Snap] Frame decode failure in channel '%s': %s", channel.name, tostring(err)))
			end
		end
	end

	runtimeByWireId[channel.wireId] = runtime
	ensureGlobalClientReceive()
end

local function createPacketHandle<T>(runtime: RuntimeState, definition: EventDefinition<T>): ClientEvent<T>
	local id = definition.id
	local isReliable = definition.reliability == "Reliable"

	local handle = {} :: ClientEvent<T>

	local signify = runtime.signifies[id]
	if not signify then
		signify = Signify.new()
		runtime.signifies[id] = signify
	end

	function handle.send(_self, value)
		local writer = if isReliable then runtime.reliableQueue else runtime.unreliableQueue
		Frame.appendPacket(writer, definition, value)
	end

	function handle.listen(_self, callback)
		local conn = signify:Connect(callback)
		return function()
			conn:Disconnect()
		end
	end

	function handle.Connect(_self, callback)
		return signify:Connect(callback)
	end

	function handle.Once(_self, callback)
		return signify:Once(callback)
	end

	function handle.Wait(_self)
		return signify:Wait()
	end

	return handle
end

local function createRequestHandle<Req, Res>(runtime: RuntimeState, def: RequestDefinition<Req, Res>): ClientRequest<Req, Res>
	local requestName = def.name
	local requestDef = def.request

	local handle = {} :: ClientRequest<Req, Res>

	function handle.request(_self, value: Req): (boolean, any)
		local thread = coroutine.running()
		if not thread then
			return false, "request must be called from a coroutine"
		end

		local guardState = runtime.guardState
		if not Guard.canAllocatePending(guardState, nil, runtime.channel.name) then
			return false, "pending request limit reached"
		end

		local corrId = allocateCorrId(runtime)

		local pending = acquireClientPending(thread, os.clock(), requestName)
		runtime.pendingRequests[corrId] = pending
		guardState.pendingRequests += 1
		runtime.hasPendingRequests = true

		Frame.appendPacket(runtime.reliableQueue, requestDef, {
			corrId = corrId,
			value = value,
		})
		requestFlush()

		return coroutine.yield()
	end

	function handle.handle(_self, callback)
		runtime.RequestHandlers[requestName] = callback :: any

		return function()
			if runtime.RequestHandlers[requestName] == callback then
				runtime.RequestHandlers[requestName] = nil
			end
		end
	end

	return handle
end

function Client.channel<D>(name: string, definition: D & ChannelDefinition): { [string]: any } & D
	assertClient()
	ensureHeartbeat()

	local existingRuntime = runtimeByName[name]
	if existingRuntime then
		error(string.format("[Snap] Channel '%s' is already defined on the client", name), 2)
	end

	local channel = Channel.define(name, definition :: any)
	local transport = Transport.getGlobalTransport()

	local runtime: RuntimeState = {
		channel = channel,
		transport = transport,
		signifies = {},
		RequestHandlers = {},
		reliableQueue = BufferWriter.new(),
		unreliableQueue = BufferWriter.new(),
		guardState = Guard.createState(),
		pendingRequests = {},
		hasPendingRequests = false,
		nextCorrId = 1,
		_dispatchFrame = nil :: any,
	}

	runtimeByName[name] = runtime
	setupReceive(runtime)

	local wireId = channel.wireId
	task.defer(function()
		(transport.ready :: any):FireServer(Transport.readyPayload(wireId))
	end)

	local result: { [string]: any } = {}
	for entryName, entry in channel.definition do
		if (entry :: any).kind == "request" then
			result[entryName] = createRequestHandle(runtime, entry :: RequestDefinition<any, any>)
		else
			result[entryName] = createPacketHandle(runtime, entry :: EventDefinition<any>)
		end
	end

	return (result :: any) :: { [string]: any } & D
end

return Client
