--!strict
--!native
--!optimize 2

local RunService = game:GetService("RunService")

local DataTypes = script.DataTypes

local Types = require(script.Types)
local Settings = require(script.Settings)
local Refs = require(script.Core.Refs)

export type DataType<T> = Types.DataType<T>
export type Reliability = Types.Reliability
export type ReliabilityInput = Types.ReliabilityInput
export type PacketDefinition<T> = Types.PacketDefinition<T>
export type InvokeDefinition<Req, Res> = Types.InvokeDefinition<Req, Res>
export type ServerPacket<T> = Types.ServerPacket<T>
export type ClientPacket<T> = Types.ClientPacket<T>
export type ServerInvoke<Req, Res> = Types.ServerInvoke<Req, Res>
export type ClientInvoke<Req, Res> = Types.ClientInvoke<Req, Res>
export type NamespaceBuilder = Types.NamespaceBuilder
export type NamespaceDefinition = Types.NamespaceDefinition
export type Mode = Settings.Mode
export type GuardConfig = Settings.GuardConfig

export type Packet<T> = {
	send: (self: Packet<T>, value: T) -> (),
	sendTo: (self: Packet<T>, player: Player, value: T) -> (),
	sendToAll: (self: Packet<T>, value: T) -> (),
	sendToAllExcept: (self: Packet<T>, excluded: Player, value: T) -> (),
	sendToList: (self: Packet<T>, players: { Player }, value: T) -> (),
	listen: (self: Packet<T>, callback: (...any) -> ()) -> () -> (),
}

export type Invoke<Req, Res> = {
	invoke: (self: Invoke<Req, Res>, ...any) -> (boolean, any),
	handle: (self: Invoke<Req, Res>, callback: (...any) -> Res) -> () -> (),
}

local Snap = {}

Snap.uint8 = require(DataTypes.uint8) :: DataType<number>
Snap.uint16 = require(DataTypes.uint16) :: DataType<number>
Snap.uint32 = require(DataTypes.uint32) :: DataType<number>
Snap.int8 = require(DataTypes.int8) :: DataType<number>
Snap.int16 = require(DataTypes.int16) :: DataType<number>
Snap.int32 = require(DataTypes.int32) :: DataType<number>

Snap.uvarint = require(DataTypes.uvarint) :: DataType<number>
Snap.varint = require(DataTypes.varint) :: DataType<number>

Snap.float32 = require(DataTypes.float32) :: DataType<number>
Snap.float64 = require(DataTypes.float64) :: DataType<number>

Snap.bool = require(DataTypes.bool) :: DataType<boolean>
Snap.char = require(DataTypes.char) :: DataType<string>
Snap.string = require(DataTypes["string"]) :: DataType<string>

Snap.null = require(DataTypes.null) :: DataType<nil>
Snap.auto = require(DataTypes.auto) :: DataType<any>
Snap.unknown = require(DataTypes.unknown) :: DataType<unknown>
Snap.inst = require(DataTypes.inst) :: DataType<Instance?>

Snap.vector3 = require(DataTypes.vector3) :: DataType<Vector3>
Snap.vector3int16 = require(DataTypes.vector3int16) :: DataType<Vector3int16>
Snap.color3 = require(DataTypes.color3) :: DataType<Color3>
Snap.color3b = require(DataTypes.color3b) :: DataType<Color3>
Snap.cframe = require(DataTypes.cframe) :: DataType<CFrame>

Snap.struct = require(DataTypes.struct) :: (fields: { [string]: DataType<any> }) -> DataType<{ [string]: any }>
Snap.array = require(DataTypes.array) :: <T>(element: DataType<T>) -> DataType<{ T }>
Snap.map = require(DataTypes.map) :: <K, V>(key: DataType<K>, value: DataType<V>) -> DataType<{ [K]: V }>
Snap.optional = require(DataTypes.optional) :: <T>(inner: DataType<T>) -> DataType<T?>
Snap.flags = require(DataTypes.flags) :: (names: { string }) -> DataType<{ [string]: boolean }>

Snap.Settings = Settings
Snap.Bandwidth = require(script.Core.Bandwidth)

local function resolveNamespaceImpl()
	if RunService:IsServer() then
		return (require :: any)(script.Server)
	else
		return (require :: any)(script.Client)
	end
end

function Snap.defineNamespace<D>(
	name: string,
	builder: (p: NamespaceBuilder) -> D & NamespaceDefinition
): { [string]: any } & D
	local impl = resolveNamespaceImpl()
	return impl.defineNamespace(name, builder :: any)
end

function Snap.serialize<T>(schema: DataType<T>, value: T): (buffer, { any }?)
	local size = schema.size
	local byteCount: number = if type(size) == "number" then size else size(value)

	local b = buffer.create(byteCount)
	local refs: { any } = {}
	local lookup: { [any]: number } = {}

	Refs.beginWrite(refs, lookup)
	local ok, err: any = pcall(schema.write, b, 0, value)
	Refs.endWrite()

	if not ok then
		error(err, 2)
	end

	return b, if #refs > 0 then refs else nil
end

function Snap.deserialize<T>(schema: DataType<T>, b: buffer, refs: { any }?): T
	Refs.beginRead(refs)
	local ok, valueOrErr: any = (pcall :: any)(schema.read, b, 0)
	Refs.endRead()

	if not ok then
		error(valueOrErr, 2)
	end

	return valueOrErr
end

setmetatable(Snap, {
	__index = function(_, key)
		if key == "Server" then
			if not RunService:IsServer() then
				error("[Snap] Snap.Server is only available on the server", 2)
			end
			return (require :: any)(script.Server)
		elseif key == "Client" then
			if not RunService:IsClient() then
				error("[Snap] Snap.Client is only available on the client", 2)
			end
			return (require :: any)(script.Client)
		end
		return nil
	end,
})

return Snap
