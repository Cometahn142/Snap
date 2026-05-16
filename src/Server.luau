--!strict
--!native
--!optimize 2

local Players = game:GetService("Players")
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
type ServerEvent<T> = Types.ServerEvent<T>
type ServerRequest<Req, Res> = Types.ServerRequest<Req, Res>
type ChannelDefinition = Types.ChannelDefinition
type TransportPair = Transport.TransportPair
type Reliability = Types.Reliability
type PlayerGuardState = Guard.PlayerGuardState
type RequestValue<Req> = Request.RequestValue<Req>
type ResponseValue<Res> = Request.ResponseValue<Res>

type RequestHandler = (player: Player, value: any) -> any

type PendingRequest = {
	thread: thread,
	player: Player,
	startedAt: number,
	requestName: string,
}

type RuntimeState = {
	channel: ChannelInternal,
	transport: TransportPair,
	signifies: { [number]: any },
	RequestHandlers: { [string]: RequestHandler },

	reliableQueues: { [Player]: BufferWriter },
	unreliableQueues: { [Player]: BufferWriter },

	dirtyReliableArray: { Player },
	nextReliableArray: { Player },
	dirtyReliableSet: { [Player]: boolean },

	dirtyUnreliableArray: { Player },
	nextUnreliableArray: { Player },
	dirtyUnreliableSet: { [Player]: boolean },

	broadcastReliable: BufferWriter,
	broadcastUnreliable: BufferWriter,

	guardStates: { [Player]: PlayerGuardState },

	pendingRequests: { [Player]: { [number]: PendingRequest } },
	hasPendingRequests: boolean,
	nextCorrIdByPlayer: { [Player]: number },

	readyPlayers: { [Player]: boolean },
	readyDeadlines: { [Player]: number },

	_dispatchFrame: any,
}

local GUARD_ENABLED = Guard.ENABLED
local INVOKE_TIMEOUT = Settings.GUARD.REQUEST_TIMEOUT
local READY_TIMEOUT = Settings.READY_TIMEOUT
local MAX_PREREADY_QUEUE_BYTES = Settings.MAX_PREREADY_QUEUE_BYTES
local EARLY_FLUSH_ENABLED = Settings.EARLY_FLUSH_ENABLED
local EARLY_FLUSH_REQUEST_ONLY = Settings.EARLY_FLUSH_REQUEST_ONLY
local OMIT_OUTER_LENGTH_PREFIX = Settings.OMIT_OUTER_LENGTH_PREFIX
local BANDWIDTH_TRACKING = Settings.BANDWIDTH_TRACKING
local readVarint = Frame.readVarint

local Server = {}

local runtimeByName: { [string]: RuntimeState } = {}
local runtimeByWireId: { [number]: RuntimeState } = {}
local globalServerReceiveConnected = false
local heartbeatConnected = false
local flushAll: () -> ()
local requestEarlyFlush: () -> ()
local EARLY_FLUSH_KEY = "snap_server_flush"

local serverPendingPool: { PendingRequest } = {}

local function acquireServerPending(
	thread: thread,
	player: Player,
	startedAt: number,
	requestName: string
): PendingRequest
	local pending = table.remove(serverPendingPool)
	if pending then
		pending.thread = thread
		pending.player = player
		pending.startedAt = startedAt
		pending.requestName = requestName
		return pending
	else
		return {
			thread = thread,
			player = player,
			startedAt = startedAt,
			requestName = requestName,
		}
	end
end

local function releaseServerPending(pending: PendingRequest)
	table.clear(pending :: any)
	table.insert(serverPendingPool, pending)
end

local function assertServer()
	if not RunService:IsServer() then
		error("[Snap] Server API must be used on the server", 3)
	end
end

local function getOrCreateQueue(queues: { [Player]: BufferWriter }, player: Player): BufferWriter
	local existing = queues[player]
	if existing then
		return existing
	end
	local new = BufferWriter.new()
	queues[player] = new
	return new
end

local function acquireReliable(runtime: RuntimeState, player: Player): BufferWriter?
	if not player.Parent then
		return nil
	end
	local writer = getOrCreateQueue(runtime.reliableQueues, player)
	if not runtime.dirtyReliableSet[player] then
		runtime.dirtyReliableSet[player] = true
		table.insert(runtime.dirtyReliableArray, player)
	end
	return writer
end

local function acquireUnreliable(runtime: RuntimeState, player: Player): BufferWriter?
	if not player.Parent then
		return nil
	end
	local writer = getOrCreateQueue(runtime.unreliableQueues, player)
	if not runtime.dirtyUnreliableSet[player] then
		runtime.dirtyUnreliableSet[player] = true
		table.insert(runtime.dirtyUnreliableArray, player)
	end
	return writer
end

local function getOrCreateGuardState(runtime: RuntimeState, player: Player): PlayerGuardState
	local existing = runtime.guardStates[player]
	if existing then
		return existing
	end
	local created = Guard.createState()
	runtime.guardStates[player] = created
	return created
end

local function resumeInvokeWaiter(thread: thread, ok: boolean, value: any)
	local resumeOk, err = coroutine.resume(thread, ok, value)
	if not resumeOk then
		warn(string.format("[Snap] Failed to resume invoke waiter: %s", tostring(err)))
	end
end

local function allocateCorrId(runtime: RuntimeState, player: Player): number
	local current = runtime.nextCorrIdByPlayer[player] or 1
	local next_ = current + 1
	if next_ >= 4294967295 then
		next_ = 1
	end
	runtime.nextCorrIdByPlayer[player] = next_
	return current
end

local function sendFrame(
	remote: RemoteEvent | UnreliableRemoteEvent,
	player: Player?,
	writer: BufferWriter,
	wireId: number
)
	local wire = writer:finalizeWithWireId(wireId)
	local refs = if #writer.refs > 0 then writer.refs else nil
	writer:reset()
	if BANDWIDTH_TRACKING then
		Bandwidth.recordOut(buffer.len(wire))
	end
	if player then
		if refs then
			(remote :: any):FireClient(player, wire, refs)
		else
			(remote :: any):FireClient(player, wire)
		end
	else
		if refs then
			(remote :: any):FireAllClients(wire, refs)
		else
			(remote :: any):FireAllClients(wire)
		end
	end
end

local function dropOversizedQueue(
	runtime: RuntimeState,
	player: Player,
	queues: { [Player]: BufferWriter },
	writer: BufferWriter,
	kind: string
)
	warn(
		string.format(
			"[Snap] Dropping pre-ready %s queue for %s in '%s' (%d bytes > %d)",
			kind,
			player.Name,
			runtime.channel.name,
			writer.cursor,
			MAX_PREREADY_QUEUE_BYTES
		)
	)
	queues[player] = nil
end

local function flush(runtime: RuntimeState)
	local transport = runtime.transport
	local readyPlayers = runtime.readyPlayers
	local wireId = runtime.channel.wireId

	local br = runtime.broadcastReliable
	if br.cursor > 0 then
		sendFrame(transport.reliable, nil, br, wireId)
	end

	local bu = runtime.broadcastUnreliable
	if bu.cursor > 0 then
		sendFrame(transport.unreliable, nil, bu, wireId)
	end

	local reliableQueues = runtime.reliableQueues
	local dirtyReliableArr = runtime.dirtyReliableArray
	local nextReliableArr = runtime.nextReliableArray
	table.clear(nextReliableArr)

	for i = 1, #dirtyReliableArr do
		local player = dirtyReliableArr[i]
		runtime.dirtyReliableSet[player] = nil
		local writer = reliableQueues[player]
		if not writer or writer.cursor == 0 then
			continue
		end
		if readyPlayers[player] then
			sendFrame(transport.reliable, player, writer, wireId)
		elseif writer.cursor > MAX_PREREADY_QUEUE_BYTES then
			dropOversizedQueue(runtime, player, reliableQueues, writer, "reliable")
		else
			runtime.dirtyReliableSet[player] = true
			table.insert(nextReliableArr, player)
		end
	end
	runtime.nextReliableArray = runtime.dirtyReliableArray
	runtime.dirtyReliableArray = nextReliableArr

	local unreliableQueues = runtime.unreliableQueues
	local dirtyUnreliableArr = runtime.dirtyUnreliableArray
	local nextUnreliableArr = runtime.nextUnreliableArray
	table.clear(nextUnreliableArr)

	for i = 1, #dirtyUnreliableArr do
		local player = dirtyUnreliableArr[i]
		runtime.dirtyUnreliableSet[player] = nil
		local writer = unreliableQueues[player]
		if not writer or writer.cursor == 0 then
			continue
		end
		if readyPlayers[player] then
			sendFrame(transport.unreliable, player, writer, wireId)
		elseif writer.cursor > MAX_PREREADY_QUEUE_BYTES then
			dropOversizedQueue(runtime, player, unreliableQueues, writer, "unreliable")
		else
			runtime.dirtyUnreliableSet[player] = true
			table.insert(nextUnreliableArr, player)
		end
	end
	runtime.nextUnreliableArray = runtime.dirtyUnreliableArray
	runtime.dirtyUnreliableArray = nextUnreliableArr
end

local function sweepTimeouts(runtime: RuntimeState, now: number)
	if not runtime.hasPendingRequests then
		return
	end

	local pendingRequests = runtime.pendingRequests
	local guardStates = runtime.guardStates
	local deadlineCutoff = now - INVOKE_TIMEOUT
	local stillHas = false

	for player, perPlayer in pendingRequests do
		local anyRemaining = false
		for corrId, pending in perPlayer do
			if pending.startedAt <= deadlineCutoff then
				perPlayer[corrId] = nil
				local gs = guardStates[player]
				if gs then
					gs.pendingRequests = math.max(0, gs.pendingRequests - 1)
				end
				resumeInvokeWaiter(pending.thread, false, "timeout")
				releaseServerPending(pending)
			else
				anyRemaining = true
			end
		end
		if not anyRemaining then
			pendingRequests[player] = nil
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

local function sendInvokeResponse(
	runtime: RuntimeState,
	player: Player,
	responseDef: EventDefinition<any>,
	responseValue: ResponseValue<any>
)
	local writer = acquireReliable(runtime, player)
	if writer then
		Frame.appendPacket(writer, responseDef, responseValue)
		requestFlush()
	end
end

local function handleInvokeRequest(
	runtime: RuntimeState,
	player: Player,
	def: EventDefinition<any>,
	decoded: RequestValue<any>
)
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
		sendInvokeResponse(runtime, player, requestDef.response, {
			corrId = decoded.corrId,
			ok = false,
			err = "no handler",
		})
		return
	end

	local ok, result = pcall(handler, player, decoded.value)
	if ok then
		sendInvokeResponse(runtime, player, requestDef.response, {
			corrId = decoded.corrId,
			ok = true,
			value = result,
		})
	else
		sendInvokeResponse(runtime, player, requestDef.response, {
			corrId = decoded.corrId,
			ok = false,
			err = tostring(result),
		})
	end
end

local function handleInvokeResponse(runtime: RuntimeState, player: Player, decoded: ResponseValue<any>)
	local pendingForPlayer = runtime.pendingRequests[player]
	if not pendingForPlayer then
		return
	end

	local pending = pendingForPlayer[decoded.corrId]
	if not pending then
		return
	end

	pendingForPlayer[decoded.corrId] = nil
	if next(pendingForPlayer) == nil then
		runtime.pendingRequests[player] = nil
	end

	local guardState = runtime.guardStates[player]
	if guardState then
		guardState.pendingRequests = math.max(0, guardState.pendingRequests - 1)
	end

	if decoded.ok then
		resumeInvokeWaiter(pending.thread, true, decoded.value)
	else
		resumeInvokeWaiter(pending.thread, false, decoded.err)
	end
	releaseServerPending(pending)
end

local function dispatchPacket(runtime: RuntimeState, def: EventDefinition<any>, player: Player, decodedValue: any)
	local role = def.requestRole
	if role == "request" then
		handleInvokeRequest(runtime, player, def, decodedValue :: RequestValue<any>)
	elseif role == "response" then
		handleInvokeResponse(runtime, player, decodedValue :: ResponseValue<any>)
	else
		local signify = runtime.signifies[def.id]
		if signify then
			signify:Fire(player, decodedValue)
		end
	end
end

local function ensureGlobalServerReceive()
	if globalServerReceiveConnected then
		return
	end
	globalServerReceiveConnected = true
	local transport = Transport.getGlobalTransport()

	local function onWire(player: Player, wire: any, refs: any)
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
			Guard.report(player, "?", "unknownPacket", string.format("unknown channel wire id %d", channelId), nil)
			return
		end
		local channel = runtime.channel
		local guardState = getOrCreateGuardState(runtime, player)
		if GUARD_ENABLED and not Guard.checkFrame(guardState, wire, player, channel.name) then
			return
		end
		if BANDWIDTH_TRACKING then
			Bandwidth.recordIn(wireLen)
		end
		local dispatch = runtime._dispatchFrame :: any
		local ok, err: any = pcall(dispatch, player, wire, offset, refs)
		if not ok then
			warn(
				string.format(
					"[Snap] Frame dispatch failure in channel '%s' from %s: %s",
					channel.name,
					player.Name,
					tostring(err)
				)
			)
		end
	end

	transport.reliable.OnServerEvent:Connect(onWire)
	transport.unreliable.OnServerEvent:Connect(onWire)

	transport.ready.OnServerEvent:Connect(function(player: Player, payload: any)
		if typeof(payload) ~= "buffer" or buffer.len(payload) < Transport.HEADER_SIZE then
			return
		end
		local channelId = buffer.readu8(payload, 0)
		local rt = runtimeByWireId[channelId]
		if not rt then
			return
		end
		if rt.readyPlayers[player] then
			return
		end
		rt.readyPlayers[player] = true
		rt.readyDeadlines[player] = nil
	end)
end

local function setupReceive(runtime: RuntimeState)
	local channel = runtime.channel
	local packets = channel.packets

	if Settings.USE_XPCALL then
		runtime._dispatchFrame = function(player: Player, wire: buffer, offset: number, refs: any)
			local guardState = getOrCreateGuardState(runtime, player)

			Refs.beginRead(if typeof(refs) == "table" then refs else nil)

			local decodeOk, decodeErr: any = pcall(
				Frame.decode,
				channel,
				wire,
				offset,
				function(def, payloadBuffer, payloadOffset)
					if GUARD_ENABLED then
						if def.requestRole == "request" then
							if not Guard.accountRequest(guardState, player, channel.name) then
								return
							end
						end
						if not Guard.accountPacket(guardState, player, channel.name) then
							return
						end
					end

					local packetName = def.name
					local ok, val1, _val2 = pcall(def.schema.read, payloadBuffer, payloadOffset)
					if not ok then
						warn(
							string.format(
								"[Snap] Failed to decode packet '%s' from %s: %s",
								packetName,
								player.Name,
								tostring(val1)
							)
						)
						return
					end

					dispatchPacket(runtime, def, player, val1)
				end
			)

			Refs.endRead()

			if not decodeOk then
				warn(
					string.format(
						"[Snap] Frame decode failure in channel '%s' from %s: %s",
						channel.name,
						player.Name,
						tostring(decodeErr)
					)
				)
			end
		end
	else
		local function decodeFast(player: Player, frame: buffer, startOffset: number, guardState: PlayerGuardState)
			local length = buffer.len(frame)
			local cursor = startOffset

			while cursor < length do
				local packetId = buffer.readu8(frame, cursor)
				cursor += 1

				local def = packets[packetId + 1]
				if not def then
					Guard.report(
						player,
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
							player,
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
							if not Guard.accountRequest(guardState, player, channel.name) then
								cursor += payloadSize
								continue
							end
						end
						if not Guard.accountPacket(guardState, player, channel.name) then
							cursor += payloadSize
							continue
						end
					end

					local decodedValue = (def.schema.read(frame, payloadOffset))
					dispatchPacket(runtime, def, player, decodedValue)
					cursor += payloadSize
				elseif OMIT_OUTER_LENGTH_PREFIX then
					local payloadOffset = cursor
					local decodedValue: any
					local nextCursor: number
					decodedValue, nextCursor = def.schema.read(frame, payloadOffset)
					if nextCursor > length or nextCursor < payloadOffset then
						Guard.report(
							player,
							channel.name,
							"malformedFrame",
							string.format("packet '%s' read past frame (%d > %d)", def.name, nextCursor, length),
							guardState
						)
						break
					end

					if GUARD_ENABLED then
						if def.requestRole == "request" then
							if not Guard.accountRequest(guardState, player, channel.name) then
								cursor = nextCursor
								continue
							end
						end
						if not Guard.accountPacket(guardState, player, channel.name) then
							cursor = nextCursor
							continue
						end
					end

					dispatchPacket(runtime, def, player, decodedValue)
					cursor = nextCursor
				else
					local size, nextCursor = readVarint(frame, cursor)
					local payloadOffset = nextCursor
					local payloadSize = size
					cursor = nextCursor

					if cursor + payloadSize > length then
						Guard.report(
							player,
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
							if not Guard.accountRequest(guardState, player, channel.name) then
								cursor += payloadSize
								continue
							end
						end
						if not Guard.accountPacket(guardState, player, channel.name) then
							cursor += payloadSize
							continue
						end
					end

					local decodedValue = (def.schema.read(frame, payloadOffset))
					dispatchPacket(runtime, def, player, decodedValue)
					cursor += payloadSize
				end
			end
		end

		runtime._dispatchFrame = function(player: Player, wire: buffer, offset: number, refs: any)
			local guardState = getOrCreateGuardState(runtime, player)
			Refs.beginRead(if typeof(refs) == "table" then refs else nil)
			local ok, err: any = pcall(decodeFast, player, wire, offset, guardState)
			Refs.endRead()

			if not ok then
				warn(
					string.format(
						"[Snap] Frame decode failure in channel '%s' from %s: %s",
						channel.name,
						player.Name,
						tostring(err)
					)
				)
			end
		end
	end

	runtimeByWireId[channel.wireId] = runtime
	ensureGlobalServerReceive()
end

local function cleanupPlayer(player: Player)
	for _, runtime in runtimeByName do
		runtime.reliableQueues[player] = nil
		runtime.unreliableQueues[player] = nil
		runtime.dirtyReliableSet[player] = nil
		runtime.dirtyUnreliableSet[player] = nil
		runtime.guardStates[player] = nil
		runtime.nextCorrIdByPlayer[player] = nil
		runtime.readyPlayers[player] = nil
		runtime.readyDeadlines[player] = nil

		local pendingForPlayer = runtime.pendingRequests[player]
		if pendingForPlayer then
			for corrId, pending in pendingForPlayer do
				pendingForPlayer[corrId] = nil
				resumeInvokeWaiter(pending.thread, false, "player left")
			end
			runtime.pendingRequests[player] = nil
		end
	end
end

Players.PlayerRemoving:Connect(cleanupPlayer)

local function registerPlayerReadyDeadline(player: Player)
	local deadline = os.clock() + READY_TIMEOUT
	for _, runtime in runtimeByName do
		if not runtime.readyPlayers[player] then
			runtime.readyDeadlines[player] = deadline
		end
	end

	task.delay(READY_TIMEOUT, function()
		if not player.Parent then
			return
		end
		for _, runtime in runtimeByName do
			if not runtime.readyPlayers[player] then
				warn(
					string.format(
						"[Snap] Ready timeout for %s in channel '%s' (%ds)",
						player.Name,
						runtime.channel.name,
						READY_TIMEOUT
					)
				)
				runtime.readyDeadlines[player] = nil
			end
		end
	end)
end

Players.PlayerAdded:Connect(registerPlayerReadyDeadline)
for _, player in Players:GetPlayers() do
	registerPlayerReadyDeadline(player)
end

local function createPacketHandle<T>(runtime: RuntimeState, definition: EventDefinition<T>): ServerEvent<T>
	local id = definition.id
	local isReliable = definition.reliability == "Reliable"

	local handle = {} :: ServerEvent<T>

	local acquire: (runtime: RuntimeState, player: Player) -> BufferWriter? = if isReliable
		then acquireReliable
		else acquireUnreliable

	local signify = runtime.signifies[id]
	if not signify then
		signify = Signify.new()
		runtime.signifies[id] = signify
	end

	function handle.sendTo(_self, player, value)
		local writer = acquire(runtime, player)
		if writer then
			Frame.appendPacket(writer, definition, value)
		end
	end

	function handle.sendToAll(_self, value)
		local writer = if isReliable then runtime.broadcastReliable else runtime.broadcastUnreliable
		Frame.appendPacket(writer, definition, value)
	end

	function handle.sendToAllExcept(_self, excluded, value)
		local players = Players:GetPlayers()

		local sharedBuf, sharedLen = Frame.encodeShared(definition, value)
		if sharedBuf then
			for i = 1, #players do
				local player = players[i]
				if player ~= excluded then
					local writer = acquire(runtime, player)
					if writer then
						Frame.appendRaw(writer, sharedBuf, sharedLen)
					end
				end
			end
			return
		end

		for i = 1, #players do
			local player = players[i]
			if player ~= excluded then
				local writer = acquire(runtime, player)
				if writer then
					Frame.appendPacket(writer, definition, value)
				end
			end
		end
	end

	function handle.sendToList(_self, players, value)
		local sharedBuf, sharedLen = Frame.encodeShared(definition, value)
		if sharedBuf then
			for _, player in players do
				local writer = acquire(runtime, player)
				if writer then
					Frame.appendRaw(writer, sharedBuf, sharedLen)
				end
			end
			return
		end

		for _, player in players do
			local writer = acquire(runtime, player)
			if writer then
				Frame.appendPacket(writer, definition, value)
			end
		end
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

local function createRequestHandle<Req, Res>(runtime: RuntimeState, def: RequestDefinition<Req, Res>): ServerRequest<Req, Res>
	local requestName = def.name
	local requestDef = def.request

	local handle = {} :: ServerRequest<Req, Res>

	function handle.request(_self, player: Player, value: Req): (boolean, any)
		local thread = coroutine.running()
		if not thread then
			return false, "request must be called from a coroutine"
		end

		local guardState = getOrCreateGuardState(runtime, player)
		if not Guard.canAllocatePending(guardState, player, runtime.channel.name) then
			return false, "pending request limit reached"
		end

		local corrId = allocateCorrId(runtime, player)

		local pendingForPlayer = runtime.pendingRequests[player]
		if not pendingForPlayer then
			pendingForPlayer = {}
			runtime.pendingRequests[player] = pendingForPlayer
		end

		local pending = acquireServerPending(thread, player, os.clock(), requestName)
		pendingForPlayer[corrId] = pending
		guardState.pendingRequests += 1
		runtime.hasPendingRequests = true

		local writer = acquireReliable(runtime, player)
		if writer then
			Frame.appendPacket(writer, requestDef, {
				corrId = corrId,
				value = value,
			})
			requestFlush()
		end

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

function Server.channel<D>(name: string, definition: D & ChannelDefinition): { [string]: any } & D
	assertServer()
	ensureHeartbeat()

	local existingRuntime = runtimeByName[name]
	if existingRuntime then
		error(string.format("[Snap] Channel '%s' is already defined on the server", name), 2)
	end

	local channel = Channel.define(name, definition :: any)
	local transport = Transport.getGlobalTransport()

	local runtime: RuntimeState = {
		channel = channel,
		transport = transport,
		signifies = {},
		RequestHandlers = {},
		reliableQueues = {},
		unreliableQueues = {},
		dirtyReliableArray = {},
		nextReliableArray = {},
		dirtyReliableSet = {},
		dirtyUnreliableArray = {},
		nextUnreliableArray = {},
		dirtyUnreliableSet = {},
		broadcastReliable = BufferWriter.new(),
		broadcastUnreliable = BufferWriter.new(),
		guardStates = {},
		pendingRequests = {},
		hasPendingRequests = false,
		nextCorrIdByPlayer = {},
		readyPlayers = {},
		readyDeadlines = {},
		_dispatchFrame = nil :: any,
	}

	runtimeByName[name] = runtime
	setupReceive(runtime)

	local deadline = os.clock() + READY_TIMEOUT
	for _, player in Players:GetPlayers() do
		if not runtime.readyPlayers[player] then
			runtime.readyDeadlines[player] = deadline
		end
	end

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

return Server
