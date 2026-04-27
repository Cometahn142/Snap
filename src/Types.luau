--!strict

export type DataType<T> = {
	size: number | (value: T) -> number,
	read: (b: buffer, offset: number) -> (T, number),
	write: (b: buffer, offset: number, value: T) -> number,
}

export type Reliability = "Reliable" | "Unreliable"

export type ReliabilityInput = Reliability | "R" | "U"

export type RequestRole = "request" | "response"

export type EventDefinition<T> = {
	id: number,
	name: string,
	schema: DataType<T>,
	reliability: Reliability,
	isFixed: boolean,
	fixedSize: number,
	requestRole: RequestRole?,
	requestName: string?,
}

export type RequestDefinition<Req, Res> = {
	kind: "request",
	name: string,
	requestSchema: DataType<Req>,
	responseSchema: DataType<Res>,
	request: EventDefinition<any>,
	response: EventDefinition<any>,
}

export type ServerEvent<T> = {
	sendTo: (self: ServerEvent<T>, player: Player, value: T) -> (),
	sendToAll: (self: ServerEvent<T>, value: T) -> (),
	sendToAllExcept: (self: ServerEvent<T>, excluded: Player, value: T) -> (),
	sendToList: (self: ServerEvent<T>, players: { Player }, value: T) -> (),
	listen: (self: ServerEvent<T>, callback: (player: Player, value: T) -> ()) -> () -> (),
}

export type ClientEvent<T> = {
	send: (self: ClientEvent<T>, value: T) -> (),
	listen: (self: ClientEvent<T>, callback: (value: T) -> ()) -> () -> (),
}

export type ServerRequest<Req, Res> = {
	request: (self: ServerRequest<Req, Res>, player: Player, value: Req) -> (boolean, any),
	handle: (self: ServerRequest<Req, Res>, callback: (player: Player, value: Req) -> Res) -> () -> (),
}

export type ClientRequest<Req, Res> = {
	request: (self: ClientRequest<Req, Res>, value: Req) -> (boolean, any),
	handle: (self: ClientRequest<Req, Res>, callback: (value: Req) -> Res) -> () -> (),
}

export type ChannelEntry = EventDefinition<any> | RequestDefinition<any, any>

export type ChannelDefinition = { [string]: ChannelEntry }

return nil
