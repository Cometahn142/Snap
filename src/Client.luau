--!strict
--!native
--!optimize 2

local RunService = game:GetService("RunService")

local Root = script.Parent
local Core = Root.Core
local BufferWriter = require(Core.BufferWriter)
local Frame = require(Core.Frame)
local Guard = require(Core.Guard)
local Invoke = require(Core.Invoke)
local Namespace = require(Core.Namespace)
local FastDefer = require(Core.FastDefer)
local ThreadPool = require(Core.ThreadPool)
local Bandwidth = require(Core.Bandwidth)
local Refs = require(Core.Refs)
local Transport = require(Core.Transport)
local Settings = require(Root.Settings)
local Types = require(Root.Types)

type BufferWriter = BufferWriter.BufferWriter
type NamespaceInternal = Namespace.Namespace
type PacketDefinition<T> = Types.PacketDefinition<T>
type InvokeDefinition<Req, Res> = Types.InvokeDefinition<Req, Res>
type ClientPacket<T> = Types.ClientPacket<T>
type ClientInvoke<Req, Res> = Types.ClientInvoke<Req, Res>
type NamespaceBuilder = Types.NamespaceBuilder
type NamespaceDefinition = Types.NamespaceDefinition
type TransportPair = Transport.TransportPair
type Reliability = Types.Reliability
type PlayerGuardState = Guard.PlayerGuardState
type RequestValue<Req> = Invoke.RequestValue<Req>
type ResponseValue<Res> = Invoke.ResponseValue<Res>

type Listener = (value: any) -> ()
type InvokeHandler = (value: any) -> any

type PendingInvoke = {
	thread: thread,
	startedAt: number,
	invokeName: string,
}

type RuntimeState = {
	namespace: NamespaceInternal,
	transport: TransportPair,
	listeners: { [number]: { Listener } },
	invokeHandlers: { [string]: InvokeHandler },

	reliableQueue: BufferWriter,
	unreliableQueue: BufferWriter,

	guardState: PlayerGuardState,

	pendingInvokes: { [number]: PendingInvoke },
	hasPendingInvokes: boolean,
	nextCorrId: number,

	_dispatchFrame: any,
}

local USE_XPCALL = Settings.USE_XPCALL
local GUARD_ENABLED = Guard.ENABLED
local INVOKE_TIMEOUT = Settings.GUARD.INVOKE_TIMEOUT
local EARLY_FLUSH_ENABLED = Settings.EARLY_FLUSH_ENABLED
local EARLY_FLUSH_INVOKE_ONLY = Settings.EARLY_FLUSH_INVOKE_ONLY
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

local function assertClient()
	if not RunService:IsClient() then
		error("[Snap] Client API must be used on the client", 3)
	end
end

local function sendFrame(remote: RemoteEvent | UnreliableRemoteEvent, writer: BufferWriter, wireId: number)
	local inner = writer:finalize()
	local refs = if #writer.refs > 0 then writer.refs else nil
	local wire = Transport.wrapFrame(wireId, inner)
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
	local wireId = runtime.namespace.wireId

	local rq = runtime.reliableQueue
	if rq.cursor > 0 then
		sendFrame(transport.reliable, rq, wireId)
	end

	local uq = runtime.unreliableQueue
	if uq.cursor > 0 then
		sendFrame(transport.unreliable, uq, wireId)
	end
end

local function resumeInvokeWaiter(thread: thread, ok: boolean, value: any)
	local resumeOk, err = coroutine.resume(thread, ok, value)
	if not resumeOk then
		warn(string.format("[Snap] Failed to resume invoke waiter: %s", tostring(err)))
	end
end

local function sweepTimeouts(runtime: RuntimeState, now: number)
	if not runtime.hasPendingInvokes then
		return
	end

	local pendingInvokes = runtime.pendingInvokes
	local guardState = runtime.guardState
	local deadlineCutoff = now - INVOKE_TIMEOUT
	local stillHas = false

	for corrId, pending in pendingInvokes do
		if pending.startedAt <= deadlineCutoff then
			pendingInvokes[corrId] = nil
			guardState.pendingInvokes = math.max(0, guardState.pendingInvokes - 1)
			resumeInvokeWaiter(pending.thread, false, "timeout")
		else
			stillHas = true
		end
	end

	runtime.hasPendingInvokes = stillHas
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

local function requestInvokeFlush()
	if EARLY_FLUSH_INVOKE_ONLY then
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

local function sendInvokeResponse(
	runtime: RuntimeState,
	responseDef: PacketDefinition<any>,
	responseValue: ResponseValue<any>
)
	Frame.appendPacket(runtime.reliableQueue, responseDef, responseValue)
	requestInvokeFlush()
end

local function handleInvokeRequest(
	runtime: RuntimeState,
	def: PacketDefinition<any>,
	decoded: RequestValue<any>
)
	local invokeName = def.invokeName
	if not invokeName then
		return
	end

	local invokeDef = runtime.namespace.invokes[invokeName]
	if not invokeDef then
		return
	end

	local handler = runtime.invokeHandlers[invokeName]
	if not handler then
		sendInvokeResponse(runtime, invokeDef.response, {
			corrId = decoded.corrId,
			ok = false,
			err = "no handler",
		})
		return
	end

	local ok, result = pcall(handler, decoded.value)
	if ok then
		sendInvokeResponse(runtime, invokeDef.response, {
			corrId = decoded.corrId,
			ok = true,
			value = result,
		})
	else
		sendInvokeResponse(runtime, invokeDef.response, {
			corrId = decoded.corrId,
			ok = false,
			err = tostring(result),
		})
	end
end

local function handleInvokeResponse(
	runtime: RuntimeState,
	decoded: ResponseValue<any>
)
	local pending = runtime.pendingInvokes[decoded.corrId]
	if not pending then
		return
	end

	runtime.pendingInvokes[decoded.corrId] = nil

	runtime.guardState.pendingInvokes = math.max(0, runtime.guardState.pendingInvokes - 1)

	if decoded.ok then
		resumeInvokeWaiter(pending.thread, true, decoded.value)
	else
		resumeInvokeWaiter(pending.thread, false, decoded.err)
	end
end

local function dispatchPacket(
	runtime: RuntimeState,
	def: PacketDefinition<any>,
	decodedValue: any
)
	local role = def.invokeRole
	if role == "request" then
		handleInvokeRequest(runtime, def, decodedValue :: RequestValue<any>)
	elseif role == "response" then
		handleInvokeResponse(runtime, decodedValue :: ResponseValue<any>)
	else
		local packetListeners = runtime.listeners[def.id]
		if not packetListeners then
			return
		end

		if USE_XPCALL then
			local packetName = def.name
			for _, listener in packetListeners do
				xpcall(listener, function(err)
					warn(
						string.format(
							"[Snap] Listener error for packet '%s': %s\n%s",
							packetName,
							tostring(err),
							debug.traceback(nil, 2)
						)
					)
				end, decodedValue)
			end
		else
			local packetName = def.name
			if #packetListeners == 1 then
				local listener = packetListeners[1]
				local ok, err: any = pcall(listener, decodedValue)
				if not ok then
					warn(
						string.format(
							"[Snap] Listener error for packet '%s': %s",
							packetName,
							tostring(err)
						)
					)
				end
			else
				for _, listener in packetListeners do
					ThreadPool.spawn1(function(v)
						local ok, err: any = pcall(listener, v)
						if not ok then
							warn(
								string.format(
									"[Snap] Listener error for packet '%s': %s",
									packetName,
									tostring(err)
								)
							)
						end
					end, decodedValue)
				end
			end
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
		local channelId, inner = Transport.unwrapFrame(wire)
		if channelId == nil or inner == nil then
			return
		end
		local runtime = runtimeByWireId[channelId]
		if not runtime then
			Guard.report(nil, "?", "unknownPacket", string.format("unknown namespace wire id %d", channelId), nil)
			return
		end
		local namespace = runtime.namespace
		local guardState = runtime.guardState
		if GUARD_ENABLED and not Guard.checkFrame(guardState, wire, nil, namespace.name) then
			return
		end
		if BANDWIDTH_TRACKING then
			Bandwidth.recordIn(wireLen)
		end
		local dispatch = runtime._dispatchFrame :: any
		local ok, err: any = pcall(dispatch, inner, refs)
		if not ok then
			warn(
				string.format(
					"[Snap] Frame dispatch failure in namespace '%s': %s",
					namespace.name,
					tostring(err)
				)
			)
		end
	end

	transport.reliable.OnClientEvent:Connect(onWire)
	transport.unreliable.OnClientEvent:Connect(onWire)
end

local function setupReceive(runtime: RuntimeState)
	local namespace = runtime.namespace
	local packets = namespace.packets

	if USE_XPCALL then
		runtime._dispatchFrame = function(inner: buffer, refs: any)
			local guardState = runtime.guardState

			Refs.beginRead(if typeof(refs) == "table" then refs else nil)

			local decodeOk, decodeErr: any = pcall(Frame.decode, namespace, inner, function(def, payloadBuffer, payloadOffset)
				if GUARD_ENABLED then
					if def.invokeRole == "request" then
						if not Guard.accountInvoke(guardState, nil, namespace.name) then
							return
						end
					end
					if not Guard.accountPacket(guardState, nil, namespace.name) then
						return
					end
				end

				local packetName = def.name
				local decodedValue: any = nil
				local packetDecodeOk = xpcall(function()
					decodedValue = (def.schema.read(payloadBuffer, payloadOffset))
				end, function(err)
					warn(
						string.format(
							"[Snap] Failed to decode packet '%s': %s",
							packetName,
							tostring(err)
						)
					)
				end)
				if not packetDecodeOk then
					return
				end

				dispatchPacket(runtime, def, decodedValue)
			end)

			Refs.endRead()

			if not decodeOk then
				warn(
					string.format(
						"[Snap] Frame decode failure in namespace '%s': %s",
						namespace.name,
						tostring(decodeErr)
					)
				)
			end
		end
	else
		local function decodeFast(frame: buffer, guardState: PlayerGuardState)
			local length = buffer.len(frame)
			local cursor = 0

			while cursor < length do
				local packetId = buffer.readu8(frame, cursor)
				cursor += 1

				local def = packets[packetId + 1]
				if not def then
					Guard.report(
						nil,
						namespace.name,
						"unknownPacket",
						string.format(
							"id=%d at offset %d (remaining frame dropped)",
							packetId,
							cursor - 1
						),
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
							namespace.name,
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
						if def.invokeRole == "request" then
							if not Guard.accountInvoke(guardState, nil, namespace.name) then
								cursor += payloadSize
								continue
							end
						end
						if not Guard.accountPacket(guardState, nil, namespace.name) then
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
							namespace.name,
							"malformedFrame",
							string.format(
								"packet '%s' read past frame (%d > %d)",
								def.name,
								nextCursor,
								length
							),
							guardState
						)
						break
					end

					if GUARD_ENABLED then
						if def.invokeRole == "request" then
							if not Guard.accountInvoke(guardState, nil, namespace.name) then
								cursor = nextCursor
								continue
							end
						end
						if not Guard.accountPacket(guardState, nil, namespace.name) then
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
							namespace.name,
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
						if def.invokeRole == "request" then
							if not Guard.accountInvoke(guardState, nil, namespace.name) then
								cursor += payloadSize
								continue
							end
						end
						if not Guard.accountPacket(guardState, nil, namespace.name) then
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

		runtime._dispatchFrame = function(inner: buffer, refs: any)
			local guardState = runtime.guardState
			Refs.beginRead(if typeof(refs) == "table" then refs else nil)
			local ok, err: any = pcall(decodeFast, inner, guardState)
			Refs.endRead()

			if not ok then
				warn(
					string.format(
						"[Snap] Frame decode failure in namespace '%s': %s",
						namespace.name,
						tostring(err)
					)
				)
			end
		end
	end

	runtimeByWireId[namespace.wireId] = runtime
	ensureGlobalClientReceive()
end

local function createPacketHandle<T>(runtime: RuntimeState, definition: PacketDefinition<T>): ClientPacket<T>
	local id = definition.id
	local isReliable = definition.reliability == "Reliable"

	local handle = {} :: ClientPacket<T>

	function handle.send(_self, value)
		local writer = if isReliable then runtime.reliableQueue else runtime.unreliableQueue
		Frame.appendPacket(writer, definition, value)
	end

	function handle.listen(_self, callback)
		local packetListeners = runtime.listeners[id]
		if not packetListeners then
			packetListeners = {}
			runtime.listeners[id] = packetListeners
		end
		table.insert(packetListeners, callback :: any)

		return function()
			local current = runtime.listeners[id]
			if not current then
				return
			end
			local index = table.find(current, callback :: any)
			if index then
				table.remove(current, index)
			end
		end
	end

	return handle
end

local function createInvokeHandle<Req, Res>(
	runtime: RuntimeState,
	invokeDef: InvokeDefinition<Req, Res>
): ClientInvoke<Req, Res>
	local invokeName = invokeDef.name
	local requestDef = invokeDef.request

	local handle = {} :: ClientInvoke<Req, Res>

	function handle.invoke(_self, value: Req): (boolean, any)
		local thread = coroutine.running()
		if not thread then
			return false, "invoke must be called from a coroutine"
		end

		local guardState = runtime.guardState
		if not Guard.canAllocatePending(guardState, nil, runtime.namespace.name) then
			return false, "pending invoke limit reached"
		end

		local corrId = allocateCorrId(runtime)

		local pending: PendingInvoke = {
			thread = thread,
			startedAt = os.clock(),
			invokeName = invokeName,
		}
		runtime.pendingInvokes[corrId] = pending
		guardState.pendingInvokes += 1
		runtime.hasPendingInvokes = true

		Frame.appendPacket(runtime.reliableQueue, requestDef, {
			corrId = corrId,
			value = value,
		})
		requestInvokeFlush()

		return coroutine.yield()
	end

	function handle.handle(_self, callback)
		runtime.invokeHandlers[invokeName] = callback :: any

		return function()
			if runtime.invokeHandlers[invokeName] == callback then
				runtime.invokeHandlers[invokeName] = nil
			end
		end
	end

	return handle
end

function Client.defineNamespace<D>(
	name: string,
	builder: (p: NamespaceBuilder) -> D & NamespaceDefinition
): { [string]: any } & D
	assertClient()
	ensureHeartbeat()

	local existingRuntime = runtimeByName[name]
	if existingRuntime then
		error(
			string.format(
				"[Snap] Namespace '%s' is already defined on the client",
				name
			),
			2
		)
	end

	local namespace = Namespace.define(name, builder :: any)
	local transport = Transport.getGlobalTransport()

	local runtime: RuntimeState = {
		namespace = namespace,
		transport = transport,
		listeners = {},
		invokeHandlers = {},
		reliableQueue = BufferWriter.new(),
		unreliableQueue = BufferWriter.new(),
		guardState = Guard.createState(),
		pendingInvokes = {},
		hasPendingInvokes = false,
		nextCorrId = 1,
		_dispatchFrame = nil :: any,
	}

	runtimeByName[name] = runtime
	setupReceive(runtime)

	local wireId = namespace.wireId
	task.defer(function()
		(transport.ready :: any):FireServer(Transport.readyPayload(wireId))
	end)

	local result: { [string]: any } = {}
	for entryName, entry in namespace.definition do
		if (entry :: any).kind == "invoke" then
			result[entryName] = createInvokeHandle(runtime, entry :: InvokeDefinition<any, any>)
		else
			result[entryName] = createPacketHandle(runtime, entry :: PacketDefinition<any>)
		end
	end

	return (result :: any) :: { [string]: any } & D
end

return Client
