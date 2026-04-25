--!strict
--!native
--!optimize 2

local Types = require(script.Parent.Parent.Types)
local Invoke = require(script.Parent.Invoke)

type DataType<T> = Types.DataType<T>
type PacketDefinition<T> = Types.PacketDefinition<T>
type InvokeDefinition<Req, Res> = Types.InvokeDefinition<Req, Res>
type NamespaceBuilder = Types.NamespaceBuilder
type NamespaceDefinition = Types.NamespaceDefinition
type NamespaceEntry = Types.NamespaceEntry
type Reliability = Types.Reliability
type ReliabilityInput = Types.ReliabilityInput

export type Namespace = {
	name: string,
	--- 0..255, assigned in order of first `Namespace.define` (must match server/client registration order).
	wireId: number,
	packets: { PacketDefinition<any> },
	invokes: { [string]: InvokeDefinition<any, any> },
	definition: NamespaceDefinition,
}

local Namespace = {}

local MAX_PACKETS_PER_NAMESPACE = 256
local MAX_NAMESPACES = 256

local definedNamespaces: { [string]: Namespace } = {}
local nextWireId = 0

local function normalizeReliability(input: ReliabilityInput?): Reliability
	if input == nil or input == "R" or input == "Reliable" then
		return "Reliable"
	elseif input == "U" or input == "Unreliable" then
		return "Unreliable"
	end
	error(
		string.format(
			"[Snap] Invalid reliability %q (expected 'R' / 'U' / 'Reliable' / 'Unreliable')",
			tostring(input)
		),
		3
	)
end

local function createBuilder(): NamespaceBuilder
	return {
		packet = function<T>(schema: DataType<T>, reliability: ReliabilityInput?): PacketDefinition<T>
			local schemaSize = schema.size
			local isFixed = type(schemaSize) == "number"
			local fixedSize = if isFixed then schemaSize :: number else 0

			local def: PacketDefinition<T> = {
				id = -1,
				name = "",
				schema = schema,
				reliability = normalizeReliability(reliability),
				isFixed = isFixed,
				fixedSize = fixedSize,
			}
			return def
		end,

		invoke = function<Req, Res>(
			request: DataType<Req>,
			response: DataType<Res>
		): InvokeDefinition<Req, Res>
			return Invoke.createDefinition(request, response)
		end,
	}
end

local function isInvoke(entry: NamespaceEntry): boolean
	return (entry :: any).kind == "invoke"
end

local function assignPacketId(
	packets: { PacketDefinition<any> },
	def: PacketDefinition<any>,
	namespaceName: string
)
	local count = #packets + 1
	if count > MAX_PACKETS_PER_NAMESPACE then
		error(
			string.format(
				"[Snap] Namespace '%s' exceeded maximum of %d packet slots",
				namespaceName,
				MAX_PACKETS_PER_NAMESPACE
			),
			2
		)
	end
	def.id = count - 1
	packets[count] = def
end

function Namespace.define(
	name: string,
	builder: (b: NamespaceBuilder) -> NamespaceDefinition
): Namespace
	local existing = definedNamespaces[name]
	if existing then
		return existing
	end

	local api = createBuilder()
	local definition = builder(api)

	local packets: { PacketDefinition<any> } = {}
	local invokes: { [string]: InvokeDefinition<any, any> } = {}

	for entryName, entry in definition do
		if isInvoke(entry) then
			local invokeDef = entry :: InvokeDefinition<any, any>
			invokeDef.name = entryName
			invokeDef.request.name = entryName .. ":req"
			invokeDef.request.invokeName = entryName
			invokeDef.response.name = entryName .. ":res"
			invokeDef.response.invokeName = entryName

			assignPacketId(packets, invokeDef.request, name)
			assignPacketId(packets, invokeDef.response, name)
			invokes[entryName] = invokeDef
		else
			local packetDef = entry :: PacketDefinition<any>
			packetDef.name = entryName
			assignPacketId(packets, packetDef, name)
		end
	end

	if nextWireId >= MAX_NAMESPACES then
		error(
			string.format(
				"[Snap] Exceeded maximum of %d namespaces (wire channel ids are u8)",
				MAX_NAMESPACES
			),
			2
		)
	end
	local wireId = nextWireId
	nextWireId += 1

	local namespace: Namespace = {
		name = name,
		wireId = wireId,
		packets = packets,
		invokes = invokes,
		definition = definition,
	}

	definedNamespaces[name] = namespace
	return namespace
end

function Namespace.getPacketById(ns: Namespace, id: number): PacketDefinition<any>?
	return ns.packets[id + 1]
end

return Namespace
