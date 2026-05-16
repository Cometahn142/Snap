--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CONTAINER_NAME = "_SnapNetwork"
local NAME_RELIABLE = "_R"
local NAME_UNRELIABLE = "_U"
local NAME_READY = "_K"

local HEADER_SIZE = 1

export type TransportPair = {
	reliable: RemoteEvent,
	unreliable: UnreliableRemoteEvent,
	ready: RemoteEvent,
}

local Transport = {}

Transport.HEADER_SIZE = HEADER_SIZE

local globalPair: TransportPair? = nil

local function getContainer(): Folder
	local existing = ReplicatedStorage:FindFirstChild(CONTAINER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	if RunService:IsServer() then
		local folder = Instance.new("Folder")
		folder.Name = CONTAINER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end

	return ReplicatedStorage:WaitForChild(CONTAINER_NAME, math.huge) :: Folder
end

local function getOrCreateRemote<T>(container: Folder, name: string, className: "RemoteEvent" | "UnreliableRemoteEvent"): T
	local existing = container:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing :: any
	end

	if RunService:IsServer() then
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = container
		return remote :: any
	end

	return container:WaitForChild(name, math.huge) :: any
end

function Transport.getGlobalTransport(): TransportPair
	local cached = globalPair
	if cached then
		return cached
	end

	local container = getContainer()
	local reliable = getOrCreateRemote(container, NAME_RELIABLE, "RemoteEvent") :: RemoteEvent
	local unreliable = getOrCreateRemote(container, NAME_UNRELIABLE, "UnreliableRemoteEvent") :: UnreliableRemoteEvent
	local ready = getOrCreateRemote(container, NAME_READY, "RemoteEvent") :: RemoteEvent

	local pair: TransportPair = {
		reliable = reliable,
		unreliable = unreliable,
		ready = ready,
	}

	globalPair = pair
	return pair
end

function Transport.wrapFrame(wireId: number, inner: buffer): buffer
	local innerLen = buffer.len(inner)
	local out = buffer.create(HEADER_SIZE + innerLen)
	buffer.writeu8(out, 0, wireId)
	buffer.copy(out, HEADER_SIZE, inner, 0, innerLen)
	return out
end

function Transport.unwrapFrame(wire: buffer): (number?, number?)
	local len = buffer.len(wire)
	if len < HEADER_SIZE then
		return nil, nil
	end
	local wireId = buffer.readu8(wire, 0)
	return wireId, HEADER_SIZE
end

function Transport.readyPayload(wireId: number): buffer
	local b = buffer.create(HEADER_SIZE)
	buffer.writeu8(b, 0, wireId)
	return b
end

return Transport




