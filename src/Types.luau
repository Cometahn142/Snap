--!strict

export type DataType<T> = {
	size: number | (value: T) -> number,
	read: (b: buffer, offset: number) -> (T, number),
	write: (b: buffer, offset: number, value: T) -> number,
}

export type Reliability = "Reliable" | "Unreliable"

export type ReliabilityInput = Reliability | "R" | "U"

export type InvokeRole = "request" | "response"

export type PacketDefinition<T> = {
	id: number,
	name: string,
	schema: DataType<T>,
	reliability: Reliability,
	isFixed: boolean,
	fixedSize: number,
	invokeRole: InvokeRole?,
	invokeName: string?,
}

export type InvokeDefinition<Req, Res> = {
	kind: "invoke",
	name: string,
	requestSchema: DataType<Req>,
	responseSchema: DataType<Res>,
	request: PacketDefinition<any>,
	response: PacketDefinition<any>,
}

export type ServerPacket<T> = {
	sendTo: (self: ServerPacket<T>, player: Player, value: T) -> (),
	sendToAll: (self: ServerPacket<T>, value: T) -> (),
	sendToAllExcept: (self: ServerPacket<T>, excluded: Player, value: T) -> (),
	sendToList: (self: ServerPacket<T>, players: { Player }, value: T) -> (),
	listen: (self: ServerPacket<T>, callback: (player: Player, value: T) -> ()) -> () -> (),
}

export type ClientPacket<T> = {
	send: (self: ClientPacket<T>, value: T) -> (),
	listen: (self: ClientPacket<T>, callback: (value: T) -> ()) -> () -> (),
}

export type ServerInvoke<Req, Res> = {
	invoke: (self: ServerInvoke<Req, Res>, player: Player, value: Req) -> (boolean, any),
	handle: (self: ServerInvoke<Req, Res>, callback: (player: Player, value: Req) -> Res) -> () -> (),
}

export type ClientInvoke<Req, Res> = {
	invoke: (self: ClientInvoke<Req, Res>, value: Req) -> (boolean, any),
	handle: (self: ClientInvoke<Req, Res>, callback: (value: Req) -> Res) -> () -> (),
}

export type NamespaceBuilder = {
	packet: <T>(schema: DataType<T>, reliability: ReliabilityInput?) -> PacketDefinition<T>,
	invoke: <Req, Res>(request: DataType<Req>, response: DataType<Res>) -> InvokeDefinition<Req, Res>,
}

export type NamespaceEntry = PacketDefinition<any> | InvokeDefinition<any, any>

export type NamespaceDefinition = { [string]: NamespaceEntry }

return nil
